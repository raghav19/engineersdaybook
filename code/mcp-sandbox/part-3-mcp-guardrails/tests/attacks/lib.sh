#!/usr/bin/env bash
# Shared helpers for tests/attacks/*/run.sh. Output: one line per case: ID  case  profile  observed  expected  PASS|FAIL
set -euo pipefail

INIT='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"attack-suite","version":"0"}}}'

# post URL BODY [extra curl args] -> prints "<http-code>" and leaves body in $BODY_FILE
post() {
  local url=$1 body=$2; shift 2
  BODY_FILE=$(mktemp)
  curl -s -o "$BODY_FILE" -w '%{http_code}' -X POST "$url" \
    -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
    -d "$body" "$@"
}

report() { # id case profile observed expected_baseline expected_guarded
  local id=$1 case=$2 profile=$3 observed=$4 eb=$5 eg=$6 expected
  [[ "$profile" == baseline ]] && expected=$eb || expected=$eg
  [[ "$observed" == "$expected" ]] && r=PASS || r=FAIL
  printf '%-6s %-28s %-9s observed=%-6s expected=%-6s %s\n' "$id" "$case" "$profile" "$observed" "$expected" "$r"
}
