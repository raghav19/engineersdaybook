#!/usr/bin/env bash
# MCP01/MCP07: a request with no token. baseline serves it; phase-1 answers 401.
source "$(dirname "$0")/../lib.sh"
url=$1 profile=$2
code=$(post "$url" "$INIT")
report MCP07 no-token "$profile" "$code" 200 401
