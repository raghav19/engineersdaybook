#!/bin/bash
# Runs as root. Gets the SPIFFE SVID, starts the root supervisor, drops to agent. Fails closed.
set -eu
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
SOCK=/run/priv/spire/agent.sock
ID=/run/identity
fail() { echo "entry: $*" >&2; exit 1; }

chmod 0700 /run/priv                      # agent cannot walk to the Workload API socket
umask 077
mkdir -p "$ID" && chmod 0700 "$ID"        # root only: svid.0.pem, svid.0.key, bundle.0.pem

out=
for i in 1 2 3 4 5; do
  out=$(/usr/local/bin/spire-agent api fetch x509 -socketPath "$SOCK" -write "$ID" -timeout 5s 2>&1) && break
  out=; sleep 1
done
[ -n "$out" ] || fail "no SVID from the SPIRE agent. Refuse to start."
echo "$out" | grep -m1 'SPIFFE ID' | sed 's/^/entry: got /'
[ -s "$ID/svid.0.pem" ] || fail "SVID files missing"

# Supervisor: root, own session, no stdin. It renews the SVID and runs the mTLS relay.
setsid /usr/local/sbin/identity-supervisor.sh </dev/null &

exec setpriv --reuid=agent --regid=agent --init-groups --inh-caps=-all "$@"
