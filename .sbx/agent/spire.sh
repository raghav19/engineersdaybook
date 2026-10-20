#!/usr/bin/env bash
# The node identity of the microVM, host side. Run it on the host. Usage: spire.sh enroll [context]
#   enroll   make a one-time join token for the user and write it, with the trust bundle, into .sbx/spire/
# The SPIRE agent in the VM reads both files at /run/sandbox/source/.sbx/spire/ (the host repo, read-only in the VM) and attests its node to the
# SPIRE server in the kind cluster. Needs SANDBOX_GITHUB_ID, the numeric GitHub id of the user.
# The token is a secret until the agent has used it. It goes into a file with mode 600 and is never printed.
# The context is the argument, else SANDBOX_KUBE_CONTEXT, else the current context of kubectl. A context that you did not name must be a kind-* one.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
sbx_dir=$(cd "$here/.." && pwd)
repo=$(dirname "$sbx_dir")
out=$sbx_dir/spire
identity=$repo/code/mcp-sandbox/part-3-mcp-guardrails/config/cloud/kind/identity.yaml
ttl=600 # seconds; the agent starts with the VM, a minute after this script

die() { echo "spire.sh: $*" >&2; exit 1; }

[ -z "${SANDBOX_NAME:-}" ] || die "run this on the host, not in the sandbox ($SANDBOX_NAME): the token is made by the SPIRE server of the kind cluster."

mode=${1:-}
[ "$mode" = enroll ] || die "usage: spire.sh enroll [context]"
ctx=${2:-${SANDBOX_KUBE_CONTEXT:-}}
if [ -z "$ctx" ]; then
  ctx=$(kubectl config current-context) || die "kubectl has no current context."
  [[ $ctx == kind-* ]] || die "the current context $ctx is not a kind cluster. Name it to use it: just sandbox agent spire-enroll $ctx"
fi
k() { kubectl --context "$ctx" "$@"; }

[[ ${SANDBOX_GITHUB_ID:-} =~ ^[0-9]+$ ]] || die "set SANDBOX_GITHUB_ID to your numeric GitHub id (not the login). Find it with: gh api user --jq .id"
trust_domain=$(yq -r .trust_domain "$identity") || die "cannot read trust_domain from $identity"
[ -n "$trust_domain" ] && [ "$trust_domain" != null ] || die "$identity has no trust_domain."

# The alias names this agent for the entries of the user: a workload entry takes it as its parentID. SPIRE refuses an ID under /spire/.
alias=spiffe://$trust_domain/microvm/$SANDBOX_GITHUB_ID
spire_server() { k -n spire-system exec spire-server-0 -c spire-server -- /opt/spire/bin/spire-server "$@"; }

mkdir -p "$out"
# The bundle is public. Read it first: a failure here stops before a token exists.
spire_server bundle show -format spiffe > "$out/bundle.spiffe.tmp" || { rm -f "$out/bundle.spiffe.tmp"; die "cannot read the trust bundle. Is the SPIRE server of $ctx running?"; }
mv "$out/bundle.spiffe.tmp" "$out/bundle.spiffe"

# JSON output: the field value is the token. The token goes into the variable and the file only.
json=$(spire_server token generate -ttl "$ttl" -spiffeID "$alias" -output json) || die "cannot make a join token. Is joinToken enabled in the spire chart (spire.yaml)?"
token=$(jq -er .value <<< "$json") || die "the SPIRE server answered without a token."
( umask 077; printf '%s' "$token" > "$out/join-token.tmp" )
mv "$out/join-token.tmp" "$out/join-token"
echo "spire: join token for user $SANDBOX_GITHUB_ID in .sbx/spire/ (valid $((ttl / 60)) minutes), alias $alias"
