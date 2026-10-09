#!/usr/bin/env bash
# Demo of the sandbox, one section per Anthropic principle. Run it in one terminal window (see README.md).
# It needs the sandbox running (`task sandbox:run` once beforehand). It prints variable names and status codes, never secret values.
# It makes no model call. Section 3 sends two dummy strings to third-party hosts and makes one temporary untracked file in the repo directory.
set -u

VM=sandbox-dev.sbx
REPO=$(git rev-parse --show-toplevel)
HERE=$(cd "$(dirname "$0")" && pwd)
CANARY="$REPO/.demo-canary-untracked.txt"
trap 'rm -f "$CANARY"' EXIT

section() { clear; printf '\033[1;35m%s\033[0m\n' "$1"; printf '\033[0;35m%s\033[0m\n' "$2"; sleep 1.5; }
say() { printf '\n\033[1;36m# %s\033[0m\n' "$1"; sleep 0.6; }
run() { printf '\033[1;32m$ %s\033[0m\n' "$1"; shift; "$@"; sleep 0.5; }
gw() { ssh $VM "bash -s -- $*" < "$HERE/mcp-call.sh"; }

section "1/3  Limit what the agent is ABLE to do" "not what it does"

say "Its own kernel"
run "uname -r" uname -r
run "ssh sandbox uname -r" ssh $VM uname -r

say "The network: listed hosts only, and no repo deletes"
run "curl github.com / example.com" ssh $VM 'for u in github.com example.com; do curl -s -o /dev/null -m 10 -w "$u %{http_code}\n" https://$u; done'
run "curl -X DELETE api.github.com/repos/..." ssh $VM 'curl -s -o /dev/null -m 10 -w "DELETE %{http_code}\n" -X DELETE https://api.github.com/repos/raghav19/nonexistent-demo-xyz'

say "The tools: the gateway removes the destructive ones"
run "list the tools the agent sees" gw tools
run "call merge_pull_request anyway" gw call merge_pull_request '{}'

say "The proxy logged the refused delete"
printf '\033[1;32m$ %s\033[0m\n' "sbx policy log"
sbx policy log --json | jq -r '.blocked_hosts[] | select(.vm_name=="sandbox-dev" and (.rule | test("http:request:delete"))) | .rule' | head -1 \
  | sed -E 's/^denied: rule "([^"]*)" matched op\(action=([^,]*),.*http:path:([^]]*)\].*/denied by \1: \2 \3/'
sleep 2

section "2/3  Real credentials never enter the sandbox" "the VM holds placeholders"

say "None of my host secrets"
run "ls ~/.ssh ~/.aws; id" ssh $VM 'ls ~/.ssh ~/.aws 2>&1; id'

say "The token variables are placeholders"
run "env | grep TOKEN (names only)" ssh $VM "env | grep -o '^[A-Z_]*TOKEN[A-Z_]*='"
run "GH_TOKEN against api.github.com/user" ssh $VM 'curl -s -o /dev/null -m 10 -w "HTTP %{http_code}\n" -H "Authorization: Bearer $GH_TOKEN" https://api.github.com/user'
run "direct call to the MCP host" ssh $VM 'curl -s -o /dev/null -m 10 -w "HTTP %{http_code}\n" -X POST https://api.githubcopilot.com/mcp/'

say "Yet the MCP call works: the gateway adds the real token on the host"
run "list_branches through the gateway" gw branches
sleep 1.5

section "3/3  An allowed domain is a capability grant" "what the open channels can still carry"

say "Allowed hosts accept a body (a dummy string, not a secret)"
run "POST to registry.terraform.io (kit allow list)" ssh $VM 'curl -s -o /dev/null -m 10 -w "server answered HTTP %{http_code}\n" -X POST -d "demo-canary-not-a-secret" https://registry.terraform.io/demo-canary'
run "PUT to an S3 bucket nobody owns (baseline **.amazonaws.com)" ssh $VM 'curl -s -m 10 -X PUT -d "demo-canary-not-a-secret" https://demo-canary-'$RANDOM'-nobody.s3.amazonaws.com/x | grep -o "<Code>[A-Za-z]*</Code>"'

say "The repo directory is readable, even files git does not track"
printf 'DEMO-CANARY-not-a-secret\n' > "$CANARY"
run "cat /run/sandbox/source/.demo-canary-untracked.txt" ssh $VM 'cat /run/sandbox/source/.demo-canary-untracked.txt'
run "cat ~/.ssh/id_ed25519 (outside the repo)" ssh $VM 'cat /home/rana/.ssh/id_ed25519 2>&1 | head -1'

say "And the GitHub write tools stay open"
run "the write tools the agent can still call" gw writes

printf '\n\033[1;33m%s\033[0m\n' "On 2026-10-08 this route put a host-only file into a public GitHub issue."
printf '\033[1;33m%s\033[0m\n' "The sandbox shrinks the blast radius. It does not close the channel."
sleep 3
