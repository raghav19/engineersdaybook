#!/bin/sh
# Egress self-test. Run it INSIDE the sandbox container.
# Usage: C-egress-selftest.sh [-p TOKEN_REGEX] [BLOCKED_HOST ...]
#   -p TOKEN_REGEX  extended regex (grep -E) of a real-token shape. Example: 'ghp_[A-Za-z0-9]{36}|sk-ant-[A-Za-z0-9_-]{20,}'
#   BLOCKED_HOST    hosts that are NOT on the allowlist. The proxy must answer 403 for them.
# Each check prints PASS, FAIL or SKIP. SKIP means the tool or the proxy that the check needs is missing.
# Exit code: 1 if any check is FAIL, else 0.
# The script never prints the value of a secret. It prints only file names and variable names.

PATTERN=""
if [ "$1" = "-p" ]; then
  PATTERN=$2
  shift 2
fi
FAILS=0
res() { # res STATUS NAME DETAIL
  printf '%-4s %-34s %s\n' "$1" "$2" "$3"
  [ "$1" = FAIL ] && FAILS=$((FAILS + 1))
}
have() { command -v "$1" >/dev/null 2>&1; }

# http_code URL: prints the HTTP status, or 000 when no connection. Returns 2 when there is no HTTP tool.
http_code() {
  if have curl; then
    curl -s -o /dev/null -m3 -w '%{http_code}' "$1" 2>/dev/null || true
  elif have wget; then
    out=$(wget -q -T3 -O /dev/null -S "$1" 2>&1)
    code=$(printf '%s\n' "$out" | sed -n 's/^ *HTTP\/[0-9.]* \([0-9][0-9][0-9]\).*/\1/p' | head -n 1)
    printf '%s' "${code:-000}"
  else
    return 2
  fi
}

# 1. Direct HTTPS to an IP address must fail. A proxy variable must not hide the test.
if have curl || have wget; then
  code=$(unset HTTPS_PROXY https_proxy HTTP_PROXY http_proxy ALL_PROXY all_proxy; http_code https://1.1.1.1)
  if [ "$code" = "000" ] || [ -z "$code" ]; then
    res PASS direct-https-1.1.1.1 "no connection (code 000)"
  else
    res FAIL direct-https-1.1.1.1 "got HTTP $code"
  fi
else
  res SKIP direct-https-1.1.1.1 "no curl and no wget"
fi

# 2. DNS to a public resolver must fail.
dns_out=""
dns_tool=""
if have dig; then
  dns_tool=dig
  dns_out=$(dig +time=2 +tries=1 +short @1.1.1.1 example.com 2>&1)
elif have nslookup; then
  dns_tool=nslookup
  dns_out=$(nslookup -timeout=2 example.com 1.1.1.1 2>&1 || true)
fi
if [ -z "$dns_tool" ]; then
  res SKIP dns-to-1.1.1.1 "no dig and no nslookup"
elif printf '%s' "$dns_out" | grep -Eq '([0-9]{1,3}\.){3}[0-9]{1,3}' && ! printf '%s' "$dns_out" | grep -Eiq 'timed out|no servers|unreachable|refused|failed'; then
  res FAIL dns-to-1.1.1.1 "$dns_tool got an answer"
else
  res PASS dns-to-1.1.1.1 "$dns_tool got no answer"
fi

# 3. No default route. /proc/net/route needs no tool. A default route has Destination 00000000 and Mask 00000000.
if awk 'NR>1 && $2=="00000000" && $8=="00000000" {f=1} END {exit !f}' /proc/net/route 2>/dev/null; then
  res FAIL no-default-route "default route exists: $(awk 'NR>1 && $2=="00000000" && $8=="00000000" {print $1}' /proc/net/route | head -n 1)"
else
  res PASS no-default-route "no default route in /proc/net/route"
fi

# 4. A host that is not on the allowlist must get 403 from the proxy.
if [ "$#" -eq 0 ]; then
  res SKIP blocked-host-403 "no host given"
else
  for h in "$@"; do
    if ! have curl && ! have wget; then
      res SKIP "blocked-host-403:$h" "no curl and no wget"
      continue
    fi
    if [ -z "${HTTPS_PROXY:-}${https_proxy:-}" ] && ! getent hosts "$h" >/dev/null 2>&1; then
      res SKIP "blocked-host-403:$h" "no proxy variable and the name does not resolve"
      continue
    fi
    code=$(http_code "https://$h/")
    if [ "$code" = "403" ]; then
      res PASS "blocked-host-403:$h" "HTTP 403"
    else
      res FAIL "blocked-host-403:$h" "HTTP $code (need 403)"
    fi
  done
fi

# 5. No container-engine socket. conmon makes /run/notify/notify.sock in each Podman container. It is not an API socket.
socks=$(find / \( -path /proc -o -path /sys \) -prune -o \( -type s -o -name '*.sock' \) -print 2>/dev/null | grep -v '^/run/notify/notify.sock$')
if [ -z "$socks" ]; then
  res PASS no-engine-socket "no socket outside /proc and /sys (except the conmon notify socket)"
else
  res FAIL no-engine-socket "$(printf '%s' "$socks" | tr '\n' ' ')"
fi

# 6. Not root, and CapEff is 0.
uid=$(id -u)
capeff=$(awk '/^CapEff:/ {print $2}' /proc/self/status)
if [ "$uid" = "0" ]; then
  res FAIL non-root "uid is 0"
else
  res PASS non-root "uid $uid"
fi
case "$capeff" in
  0000000000000000) res PASS cap-eff-zero "CapEff $capeff" ;;
  *) res FAIL cap-eff-zero "CapEff $capeff" ;;
esac

# 7. Root file system is not writable.
probe=/.egress-selftest.$$
if ( : > "$probe" ) 2>/dev/null; then
  rm -f "$probe"
  res FAIL rootfs-read-only "could write to /"
else
  res PASS rootfs-read-only "write to / failed"
fi

# 8. No real token in the environment or in files under $HOME.
if [ -z "$PATTERN" ]; then
  res SKIP no-token-in-env "no pattern given (-p)"
  res SKIP no-token-in-home "no pattern given (-p)"
else
  names=$(env | grep -E -- "$PATTERN" | sed 's/=.*//' | tr '\n' ' ')
  if [ -z "$names" ]; then
    res PASS no-token-in-env "no match"
  else
    res FAIL no-token-in-env "variables: $names"
  fi
  if [ -z "${HOME:-}" ] || [ ! -d "$HOME" ]; then
    res SKIP no-token-in-home "HOME is not a directory"
  else
    files=$(grep -rIlE -- "$PATTERN" "$HOME" 2>/dev/null | head -n 10 | tr '\n' ' ')
    if [ -z "$files" ]; then
      res PASS no-token-in-home "no match under $HOME"
    else
      res FAIL no-token-in-home "files: $files"
    fi
  fi
fi

[ "$FAILS" -eq 0 ] || exit 1
exit 0
