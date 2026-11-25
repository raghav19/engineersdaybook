#!/usr/bin/env bash
# The host bridge. For each port or port range in ports, it listens on 127.0.0.1:<port> on the host and runs socat in the sandbox for each connection.
# The host starts every connection. The sandbox keeps Network=none. Flow: ../README.md#host-port-bridge-flow
set -euo pipefail

ports="$HOME/.config/sandbox/ports"
while read -r spec _; do
    case "$spec" in '' | '#'*) continue ;; esac
    # A line is one port or a range like 19432-19441. A plain port gives first=last.
    first=${spec%-*} last=${spec#*-}
    if ! [[ $first =~ ^[0-9]+$ && $last =~ ^[0-9]+$ ]] || ((first < 1024 || last > 65535 || first > last || last - first >= 16)); then
        echo "sandbox-bridge: bad port '$spec' in $ports" >&2
        exit 1
    fi
    for ((port = first; port <= last; port++)); do
        # max-children limits the connections to one port. If the sandbox is down, podman exec fails and the connection closes.
        socat "TCP-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork,max-children=8" \
            "EXEC:podman exec -i sandbox-agent socat - TCP\\:127.0.0.1\\:$port" &
    done
done <"$ports"
wait
