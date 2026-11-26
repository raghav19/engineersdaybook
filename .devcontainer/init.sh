#!/usr/bin/env bash
# The initializeCommand of devcontainer.json: it runs on the host before each `devcontainer up`. It checks the one-time setup and gives a new proxy its token.
# Setup: README.md#prerequisites. Flow: README.md#run-flow
set -euo pipefail
cd "$(dirname "$0")"

credential="$HOME/.config/credstore.encrypted/bws-token"
ca_dir="$HOME/.local/state/sandbox"
# Must equal the secrets mount of the proxy in compose.yaml.
secrets="${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/sandbox-secrets"
# Must equal the uid of x-proxy in compose.yaml.
proxy_uid=10001

fail() {
    echo "sandbox: $1. See .devcontainer/README.md#prerequisites" >&2
    exit 1
}

# --- Checks of the one-time setup. Each check names the missing step. ---

runtimes=$(docker info --format '{{json .Runtimes}}')
for runtime in runsc-uds runsc-builder; do
    if ! jq -e --arg name "$runtime" 'has($name)' <<<"$runtimes" >/dev/null; then
        fail "Docker has no runtime $runtime (step: gVisor)"
    fi
done

if [ ! -f "$ca_dir/ca.crt" ] || [ ! -f "$ca_dir/ca.key" ]; then
    fail "the proxy CA is missing in $ca_dir (step: CA)"
fi

if ! getfacl --omit-header "$ca_dir/ca.key" 2>/dev/null | grep -q "^user:$proxy_uid:r"; then
    fail "uid $proxy_uid cannot read $ca_dir/ca.key (step: CA)"
fi

if [ ! -f "$credential" ]; then
    fail "the encrypted Bitwarden token $credential is missing (step: token)"
fi

# --- The secrets of the proxy. A running proxy has read them already, so only a new proxy gets them. ---

if [ -n "$(docker compose -p sandbox -f compose.yaml ps -q --status running proxy)" ]; then
    exit 0
fi

# Make the secrets folder in RAM ($XDG_RUNTIME_DIR) with mode 0700: only you can open it.
install -d -m 0700 "$secrets"
# Let the proxy (uid 10001) open the folder. The default ACL (d:) gives each new file in it read access for the proxy.
# An ACL adds this one user without root. chown to another user needs root.
setfacl -m "u:$proxy_uid:rx,d:u:$proxy_uid:r" "$secrets"

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
