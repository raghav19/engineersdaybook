#!/bin/sh
# Prints the token for a host from .sbx/secrets.json. Usage: secret-token.sh <absolute path of sops> <host>
# sbx runs this as the --command of a custom secret (see `just sandbox sync-secrets` in agent.just). The sops path is an argument because sandboxd's PATH has no
# mise. The command sbx stores must not contain a double quote: sbx 0.47 saves such a secret with an empty value and then `sbx secret ls` fails. That is why
# the quoted sops key path lives here and not in the task.
exec "$1" -d --extract "[\"$2\"]" "$(dirname "$0")/../secrets.json"
