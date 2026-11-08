#!/bin/bash
# Root-owned. Renews the SVID in /run/identity (atomic rename) and keeps the relay running.
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SOCK=/run/priv/spire/agent.sock
ID=/run/identity
INTERVAL=${RENEW_INTERVAL:-10}
umask 077
relay_pid=
while :; do
  tmp=$(mktemp -d "$ID/.new.XXXXXX")
  if /usr/local/bin/spire-agent api fetch x509 -socketPath "$SOCK" -write "$tmp" -silent -timeout 5s >/dev/null 2>&1 && [ -s "$tmp/svid.0.pem" ]; then
    old=$(openssl x509 -in "$ID/svid.0.pem" -noout -serial 2>/dev/null)
    new=$(openssl x509 -in "$tmp/svid.0.pem" -noout -serial)
    mv -f "$tmp"/svid.0.key "$tmp"/svid.0.pem "$tmp"/bundle.0.pem "$ID"/
    [ "$old" = "$new" ] || echo "supervisor: SVID renewed $new $(openssl x509 -in "$ID/svid.0.pem" -noout -enddate)"
  else
    echo "supervisor: fetch failed" >&2
  fi
  rm -rf "$tmp"
  if [ -n "${GATEWAY_URL:-}" ] && { [ -z "$relay_pid" ] || ! kill -0 "$relay_pid" 2>/dev/null; }; then
    /usr/bin/perl /usr/local/sbin/identity-relay.pl &
    relay_pid=$!
  fi
  sleep "$INTERVAL"
done
