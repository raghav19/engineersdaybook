#!/usr/bin/env bash
# Self-test of the host proxy. `just sandbox-proxy selftest` runs it. It does not run on its own.
# It starts nothing and stops nothing: the recipe starts the proxy and the bridge with dummy tokens, and stops them after.
# Input (environment): NS, STATE_DIR, RUN_DIR, RELAY_PORT, PORTS (the five proxy ports), DUMMIES (the dummy tokens, space separated).
# Each check prints PASS or FAIL. Exit code 1 if any check is FAIL. The script never prints a token value.
set -uo pipefail

: "${NS:?}" "${STATE_DIR:?}" "${RUN_DIR:?}" "${RELAY_PORT:?}" "${PORTS:?}" "${DUMMIES:?}"
sock="$RUN_DIR/proxy.sock"
fails=0

res() { # res STATUS NAME DETAIL
  printf '%-4s %-34s %s\n' "$1" "$2" "$3"
  [ "$1" = FAIL ] && fails=$((fails + 1))
  return 0
}

# connect_status HOST: sends a CONNECT for HOST:443 over the socket and prints the status code of the answer.
connect_status() {
  printf 'CONNECT %s:443 HTTP/1.1\r\nHost: %s:443\r\n\r\n' "$1" "$1" \
    | timeout 10 socat - "UNIX-CONNECT:$sock" 2>/dev/null | head -n 1 | awk '{print $2}'
}

# 1. The socket is private to the host user.
mode=$(stat -c '%a %U' "$sock" 2>/dev/null || echo missing)
if [ "$mode" = "600 $(id -un)" ]; then res PASS socket-mode "mode 600, owner $(id -un)"; else res FAIL socket-mode "got: $mode"; fi

# 2. Each proxy port listens on 127.0.0.1 and on no other address.
for p in $PORTS; do
  addrs=$(ss -H -lntu "sport = :$p" 2>/dev/null | awk '{print $5}' | sort -u | tr '\n' ' ')
  if [ -z "$addrs" ]; then res FAIL "listen-$p" "no listener"
  elif printf '%s\n' $addrs | grep -v -q -E '^127\.0\.0\.1:'; then res FAIL "listen-$p" "not only loopback: $addrs"
  else res PASS "listen-$p" "$addrs"; fi
done

# 3. A host on the allowlist gets a tunnel. A host that is not on it gets 403.
code=$(connect_status api.github.com)
if [ "$code" = 200 ]; then res PASS allowed-host "CONNECT api.github.com: 200"; else res FAIL allowed-host "CONNECT api.github.com: ${code:-no answer}"; fi
code=$(connect_status example.com)
if [ "$code" = 403 ]; then res PASS blocked-host "CONNECT example.com: 403"; else res FAIL blocked-host "CONNECT example.com: ${code:-no answer}"; fi

# 4. The swap. A relay (as in the sandbox) joins a TCP port to the socket. curl sends the placeholder to api.github.com.
# The dummy token is not valid, so GitHub answers 401. The audit log must show the swap, and no log line may hold a token value.
socat "TCP-LISTEN:$RELAY_PORT,bind=127.0.0.1,fork,reuseaddr" "UNIX-CONNECT:$sock" >/dev/null 2>&1 &
relay=$!
trap 'kill "$relay" 2>/dev/null' EXIT
sleep 0.5
status=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' -x "http://127.0.0.1:$RELAY_PORT" --cacert "$STATE_DIR/ca.crt" \
  -H 'Authorization: Bearer sandbox-placeholder-GH_TOKEN' https://api.github.com/zen 2>/dev/null || true)
case "$status" in
  200|401|403) res PASS tls-through-proxy "api.github.com answered $status through the proxy CA" ;;
  *) res FAIL tls-through-proxy "status ${status:-000}. The test needs the internet and the CA at $STATE_DIR/ca.crt" ;;
esac
sleep 1
log=$(journalctl --user -u "$NS-proxy" -o cat --since '-5min' 2>/dev/null)
if printf '%s\n' "$log" | grep -q '"swapped"' && printf '%s\n' "$log" | grep -q 'GH_TOKEN'; then
  res PASS swap-in-audit "the audit log shows the swap of GH_TOKEN"
else
  res FAIL swap-in-audit "no swap of GH_TOKEN in the audit log"
fi
leaks=0
for d in $DUMMIES; do
  printf '%s\n' "$log" | grep -q -F -- "$d" && leaks=$((leaks + 1))
done
if [ "$leaks" = 0 ]; then res PASS no-token-in-log "no token value in the audit log"; else res FAIL no-token-in-log "$leaks token value(s) in the audit log"; fi

if [ "$fails" = 0 ]; then echo "selftest: all checks passed"; else echo "selftest: $fails check(s) failed"; fi
[ "$fails" = 0 ]
