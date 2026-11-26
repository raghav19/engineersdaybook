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

# --- The token. A running proxy holds its token already, so only a new proxy gets one. ---

if [ -n "$(docker compose -p sandbox -f compose.yaml ps -q --status running proxy)" ]; then
    exit 0
fi

# Make the token folder in RAM ($XDG_RUNTIME_DIR) with mode 0700: only you can open it.
install -d -m 0700 "$secrets"
# Let the proxy (uid 10001) open the folder and delete the token file in it. An ACL adds this one user without root. chown to another user needs root.
setfacl -m "u:$proxy_uid:rwx" "$secrets"
# Decrypt the Bitwarden token into the folder. Only you and the proxy can open the folder.
systemd-creds --user decrypt --name=bws-token "$credential" - >"$secrets/bws-token"
# Let the proxy read the token file. The proxy deletes the file after it reads it.
setfacl -m "u:$proxy_uid:r" "$secrets/bws-token"

