#!/bin/sh
# Egress self-test. It runs inside the sandbox container as the user agent. It prints PASS or FAIL for each check. Exit code 1 if any check fails.
# Usage: egress-selftest [-c CAPEFF] [-a ALLOWED_URL] [BLOCKED_HOST]
#   -c CAPEFF      the effective capabilities that the agent must have, 16 hex digits. Default: none. The build profile has 00000000000400cb.
#   -a ALLOWED_URL a URL on the allowlist. The proxy must answer 2xx.
#   BLOCKED_HOST   a host that is not on the allowlist. The proxy must answer 403.
# The script never prints a secret. It never writes to an existing file.
CAPS=0000000000000000 ALLOWED="" FAILS=0
while getopts c:a: o; do case $o in c) CAPS=$OPTARG ;; a) ALLOWED=$OPTARG ;; *) exit 2 ;; esac; done
shift $((OPTIND - 1))
res() { printf '%-4s %-24s %s\n' "$1" "$2" "$3"; [ "$1" = FAIL ] && FAILS=$((FAILS + 1)); return 0; }
# must NAME COMMAND...: PASS when the command fails (the wall holds), FAIL when it succeeds
must() { n=$1; shift; if "$@" >/dev/null 2>&1; then res FAIL "$n" "it worked, and it must fail"; else res PASS "$n" "it failed"; fi; }
tcp() { timeout 4 bash -c "exec 3<>/dev/tcp/$1/$2"; }
code() { curl -s -o /dev/null -m6 -w '%{http_code} %{http_connect}' "$@" 2>/dev/null; }
noproxy() { env -u HTTPS_PROXY -u https_proxy -u HTTP_PROXY -u http_proxy "$@"; }

# 1. The network: only lo, and no route to a public IP, a LAN IP, a port on the host loopback, or a UDP resolver
ifaces=$(ls /sys/class/net | tr '\n' ' ')
[ "$ifaces" = "lo " ] && res PASS only-loopback "interfaces: $ifaces" || res FAIL only-loopback "interfaces: $ifaces"
must tcp-public-ip tcp 1.1.1.1 443
must tcp-lan-ip tcp 192.168.1.1 80
must tcp-host-loopback tcp 127.0.0.1 18080 # the tunnel port of iron-proxy on the host
must udp-public-ip timeout 4 bash -c 'echo x > /dev/udp/1.1.1.1/53'
must skip-the-proxy noproxy curl -sf -m5 https://api.github.com/zen

# 2. The proxy: a listed host works, an unlisted host gets 403
if [ -n "$ALLOWED" ]; then
  c=$(code "$ALLOWED")
  case $c in 2*) res PASS allowed-host "HTTP ${c%% *}" ;; *) res FAIL allowed-host "got: $c" ;; esac
fi
if [ -n "$1" ]; then
  c=$(code "https://$1/")
  case $c in "000 403") res PASS blocked-host-403 "$1" ;; *) res FAIL blocked-host-403 "$1 got: $c" ;; esac
fi

# 3. No real token: the placeholders only
[ "$GH_TOKEN" = sandbox-placeholder-GH_TOKEN ] && res PASS placeholder-in-env "GH_TOKEN is the placeholder" || res FAIL placeholder-in-env "GH_TOKEN is not the placeholder"
env | grep -qE 'ghp_[A-Za-z0-9]{36}|github_pat_|sk-ant-' && res FAIL no-real-token "a token shape is in the environment" || res PASS no-real-token "none in the environment"

# 4. The agent cannot change the sandbox
mounts=$(awk '$2=="/" {print $4}' /proc/mounts)
case ",$mounts," in *,ro,*) res PASS root-read-only "mounted ro" ;; *) res FAIL root-read-only "not read-only" ;; esac
must write-etc touch /etc/.selftest
must write-usr touch /usr/.selftest
must write-ca sh -c ': >> /etc/ssl/certs/ca-certificates.crt'
must write-socket-dir touch /run/sandbox/proxy/.selftest

# 5. No capability, no new privileges, a seccomp filter
for f in CapEff CapBnd CapAmb; do
  v=$(awk -v f="$f:" '$1==f {print $2}' /proc/self/status)
  [ "$v" = "$CAPS" ] && res PASS "cap-${f#Cap}" "$v" || res FAIL "cap-${f#Cap}" "$v, need $CAPS"
done
grep -q '^NoNewPrivs:.1' /proc/self/status && res PASS no-new-privileges "on" || res FAIL no-new-privileges "off"
grep -q '^Seccomp:.2' /proc/self/status && res PASS seccomp-filter "on" || res FAIL seccomp-filter "off"

[ "$FAILS" -eq 0 ]
