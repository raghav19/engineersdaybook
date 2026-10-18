#!/bin/sh
# Prints one secret of the Bitwarden Secrets Manager project by its key name, with no newline. Usage: bws-secret.sh <key>
#   bws-secret.sh token    prints the access token of the machine account instead (the host recipes that create the Secret in the cluster use it)
# The machine account (read-only, one project) sees only that project, so the key name is unique when the project holds one secret of that name.
# The access token comes from, in this order:
#   1. BWS_ACCESS_TOKEN
#   2. the file BWS_ACCESS_TOKEN_FILE (default ~/.config/bws/access-token), when it exists. Its mode must be 600 or 400. The sbx daemon runs this script
#      on demand with no terminal (the secret ghcr.io, `secrets-sync` in agent.just), so it can read the token only from a file.
#   3. a prompt on the terminal, without an echo
# Run it on the host only. The microVM holds no access token. For the EU cloud set BWS_SERVER_URL=https://vault.bitwarden.eu.
set -eu

[ $# -eq 1 ] || { echo "usage: bws-secret.sh <key>|token" >&2; exit 2; }

token_file=${BWS_ACCESS_TOKEN_FILE:-${XDG_CONFIG_HOME:-${HOME:-/nonexistent}/.config}/bws/access-token}
if [ -z "${BWS_ACCESS_TOKEN:-}" ] && [ -f "$token_file" ]; then
  case $(stat -c %a "$token_file") in
    600|400) BWS_ACCESS_TOKEN=$(cat "$token_file") ;;
    *) echo "bws-secret.sh: $token_file must have mode 600 or 400." >&2; exit 1 ;;
  esac
fi

if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
  (: < /dev/tty) 2> /dev/null || { echo "bws-secret.sh: set BWS_ACCESS_TOKEN, there is no token file and no terminal to ask on." >&2; exit 1; }
  printf 'Bitwarden access token (machine account): ' >&2
  trap 'stty echo < /dev/tty' EXIT
  stty -echo < /dev/tty
  read -r BWS_ACCESS_TOKEN < /dev/tty
  stty echo < /dev/tty
  trap - EXIT
  printf '\n' >&2
fi
[ -n "$BWS_ACCESS_TOKEN" ] || { echo "bws-secret.sh: the access token is empty." >&2; exit 1; }

if [ "$1" = token ]; then
  printf %s "$BWS_ACCESS_TOKEN"
  exit 0
fi

export BWS_ACCESS_TOKEN
bws secret list --output json \
  | jq -j --arg key "$1" '[.[] | select(.key == $key)] | if length == 1 then .[0].value else error("expected one secret named " + $key + ", found " + (length | tostring)) end'
