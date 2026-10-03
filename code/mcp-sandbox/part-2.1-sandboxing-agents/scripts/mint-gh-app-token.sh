#!/usr/bin/env bash
# Mint a short-lived GitHub App installation token and print it on stdout.
#
# Usage: mint-gh-app-token.sh APP_ID INSTALLATION_ID KEY_PATH
#
# Run by the sbx daemon on the HOST (sbx secret set-custom --command), at set
# time and again whenever the proxy needs a fresh value
set -euo pipefail

[ "$#" -eq 3 ] || { echo "usage: mint-gh-app-token.sh APP_ID INSTALLATION_ID KEY_PATH" >&2; exit 2; }
app_id=$1 installation_id=$2 key_path=$3

# Swap this one function to read the key from sops or AWS Secrets Manager later.
load_key() { cat "$key_path"; }

b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

now=$(date +%s)
header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64)
payload=$(printf '{"iat":%d,"exp":%d,"iss":"%s"}' $((now - 60)) $((now + 540)) "$app_id" | b64)
signature=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -sign <(load_key) | b64)

response=$(curl -sS -w '\n%{http_code}' -X POST \
  -H "Authorization: Bearer $header.$payload.$signature" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  "https://api.github.com/app/installations/$installation_id/access_tokens")
code=${response##*$'\n'}
body=${response%$'\n'*}

if [ "$code" != 201 ]; then
  echo "mint-gh-app-token: GitHub returned HTTP $code: $(printf '%s' "$body" | jq -r '.message // "no message"')" >&2
  exit 1
fi
printf '%s' "$body" | jq -r .token
