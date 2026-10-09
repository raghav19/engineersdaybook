#!/usr/bin/env bash
# Model-free MCP calls to the sbx MCP gateway, the VM's only MCP endpoint. Run it inside the sandbox:
#   ssh sandbox-dev.sbx 'bash -s -- tools' < mcp-call.sh
#   ssh sandbox-dev.sbx 'bash -s -- call merge_pull_request {}' < mcp-call.sh
#   ssh sandbox-dev.sbx 'bash -s -- branches' < mcp-call.sh
#   ssh sandbox-dev.sbx 'bash -s -- writes' < mcp-call.sh
# The VM sends no token. The gateway adds the GitHub OAuth token on the host and applies the tool filter.
set -u

URL=${MCP_GATEWAY_URL:-http://mcp-gateway.docker.internal/mcp}
H=(-H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream')
mode=${1:-tools}

rpc() { curl -s -m 20 "${H[@]}" ${sid:+-H "Mcp-Session-Id: $sid"} -X POST "$URL" -d "$1" | sed -n 's/^data: //p'; }

hdr=$(curl -s -D - -o /dev/null -m 15 "${H[@]}" -X POST "$URL" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"demo","version":"0"}}}')
sid=$(printf '%s' "$hdr" | tr -d '\r' | awk -F': ' 'tolower($1)=="mcp-session-id"{print $2}')
rpc '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null

case $mode in
  tools)
    names=$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | jq -r '.result.tools[].name')
    echo "the agent sees $(printf '%s\n' "$names" | wc -l) GitHub tools"
    for t in merge_pull_request delete_file delete_repository create_repository fork_repository; do
      printf '%s\n' "$names" | grep -qx "$t" && echo "  $t: present" || echo "  $t: absent"
    done
    for t in issue_write push_files create_pull_request; do
      printf '%s\n' "$names" | grep -qx "$t" && echo "  $t: present" || echo "  $t: absent"
    done ;;
  writes)
    names=$(rpc '{"jsonrpc":"2.0","id":2,"method":"tools/list"}' | jq -r '.result.tools[].name')
    for t in issue_write add_issue_comment push_files create_or_update_file create_pull_request; do
      printf '%s\n' "$names" | grep -qx "$t" && echo "  $t: open"
    done ;;
  call)
    rpc "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"$2\",\"arguments\":${3:-{\}}}}" \
      | jq -r 'if .error then "error: " + .error.message else "ok" end' ;;
  branches)
    rpc '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_branches","arguments":{"owner":"raghav19","repo":"engineersdaybook"}}}' \
      | jq -r '.result.content[0].text | fromjson | .[].name' 2>/dev/null | head -5 ;;
esac
