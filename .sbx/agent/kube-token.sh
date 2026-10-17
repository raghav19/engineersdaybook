#!/bin/sh
# Prints a token for the read-only ServiceAccount of the sandbox. Usage: kube-token.sh <absolute path of kubectl> <context>
# sbx runs this as the --command of the custom secret for host.docker.internal (see kubeconfig-install in agent.just) and runs it again when its cached value
# is older than the --refresh time. The token lives 8 hours, the refresh is 6 hours, so the placeholder in .sbx/kubeconfig always gets a valid token.
# sandboxd runs it outside the shell of the user, hence the absolute path of kubectl. kubectl reads ~/.kube/config: a KUBECONFIG variable of your shell is not
# visible here. The command that sbx stores must not contain a double quote (see secret-token.sh), so the arguments are plain words.
exec "$1" --context "$2" -n sandbox-viewer create token sandbox-viewer --duration=8h
