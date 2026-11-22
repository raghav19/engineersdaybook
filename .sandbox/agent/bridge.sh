#!/usr/bin/env bash
# The host bridge. For each port in ports, it listens on 127.0.0.1:<port> on the host.
# For each connection, it runs socat inside the agent sandbox. That socat connects to 127.0.0.1:<port> in the sandbox.
# The host starts every connection. The sandbox keeps Network=none and cannot start one.
set -euo pipefail

ports="$HOME/.config/sandbox/ports"
while read -r port _; do
    case "$port" in '' | '#'*) continue ;; esac
    if ! [[ $port =~ ^[0-9]+$ ]] || ((port < 1024 || port > 65535)); then
        echo "sandbox-bridge: bad port '$port' in $ports" >&2
        exit 1
    fi
    # max-children stops a flood of connections to one port. If the sandbox is down, podman exec fails and the connection closes.
    socat "TCP-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork,max-children=8" \
        "EXEC:podman exec -i sandbox-agent socat - TCP\\:127.0.0.1\\:$port" &
done <"$ports"
wait
