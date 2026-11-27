#!/usr/bin/env bash
# The initializeCommand of devcontainer.json: it runs on the host before each `devcontainer up`. It gives a new proxy a new CA and its tokens.
# Setup: README.md#prerequisites. Flow: README.md#run-flow
set -euo pipefail
cd "$(dirname "$0")"

credential="$HOME/.config/credstore.encrypted/bws-token"
# Must equal the secrets mount of the proxy and the CA mount of the agent in compose.yaml.
secrets="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/sandbox-secrets"
# Must equal the uid of x-proxy in compose.yaml.
proxy_uid=10001

fail() {
    echo "sandbox: $1. See .devcontainer/README.md#prerequisites" >&2
    exit 1
}

# A running proxy has read its CA and its tokens already, so only a new proxy gets them.
if [ -n "$(docker compose -p sandbox -f compose.yaml ps -q --status running proxy)" ]; then
    exit 0
fi

# Make the secrets folder in RAM ($XDG_RUNTIME_DIR) with mode 0700: only you can open it.
install -d -m 0700 "$secrets"
# Let the proxy (uid 10001) open the folder. The default ACL (d:) gives each new file in it read access for the proxy.
# An ACL adds this one user without root. chown to another user needs root.
setfacl -m "u:$proxy_uid:rx,d:u:$proxy_uid:r" "$secrets"

# A new CA for each new proxy. The proxy ends the TLS of each HTTPS call with it, and the agent trusts only ca.crt.
# Trap: gVisor can keep the old ca.crt in a running agent. Stop the whole sandbox, not only the proxy.
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 365 \
    -subj '/CN=sandbox egress proxy CA' \
    -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
    -addext 'keyUsage=critical,keyCertSign,cRLSign' \
    -keyout "$secrets/ca.key" -out "$secrets/ca.crt" 2>/dev/null
# openssl makes the key with mode 0600, and that mode blocks the default ACL. This line gives the proxy its read access again.
setfacl -m "u:$proxy_uid:r" "$secrets/ca.key"

# Fetch the API tokens from Bitwarden. The access token stays in this script and in bws, and bws exits after the call.
# Must equal the file sources in policy/agent.yaml.
names=(GH_TOKEN CLAUDE_CODE_OAUTH_TOKEN QWEN_API_KEY GITHUB_TOKEN)
if ! json=$(BWS_ACCESS_TOKEN="$(systemd-creds --user decrypt --name=bws-token "$credential" -)" bws secret list --output json); then
    fail "bws cannot read the secrets (step: token)"
fi

# Write one file for each token. Each file gets the read access of the proxy from the default ACL of the folder.
for name in "${names[@]}"; do
    # The value of the secret with this key, or nothing if Bitwarden has no such secret.
    value=$(jq -r --arg key "$name" '.[] | select(.key == $key) | .value' <<<"$json")
    [ -n "$value" ] || fail "Bitwarden has no secret $name"
    # No newline at the end: iron-proxy uses the exact content of the file.
    printf '%s' "$value" >"$secrets/$name"
done
