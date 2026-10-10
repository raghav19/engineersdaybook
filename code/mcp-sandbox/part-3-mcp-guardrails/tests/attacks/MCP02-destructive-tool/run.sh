#!/usr/bin/env bash
# MCP02: call github merge_pull_request through the gateway. Needs a valid JWT on phase-1 (TOKEN env).
source "$(dirname "$0")/../lib.sh"
url=$1 profile=$2
auth=(); [[ -n "${TOKEN:-}" ]] && auth=(-H "Authorization: Bearer $TOKEN")
code=$(post "$url" "$INIT" "${auth[@]}" -D /tmp/mcp-hdr.$$)
sid=$(awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}' /tmp/mcp-hdr.$$ | tr -d '\r'); rm -f /tmp/mcp-hdr.$$
call='{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"github_merge_pull_request","arguments":{"owner":"x","repo":"y","pullNumber":1}}}'
post "$url" "$call" "${auth[@]}" -H "Mcp-Session-Id: $sid" >/dev/null
observed=ok; grep -q 'Unknown tool' "$BODY_FILE" && observed=denied
report MCP02 merge_pull_request "$profile" "$observed" ok denied
