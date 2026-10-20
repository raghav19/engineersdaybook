#!/usr/bin/env bash
# The node identity of the microVM, host side. Run it on the host. Usage: spire.sh enroll
#   enroll   make a one-time join token for the user and write it, with the trust bundle, into ~/.sbx/spire/
# sbxenv.yaml runs it before every create and run of the sandbox (lifecycle.initialize) and mounts ~/.sbx/spire read-only in the VM
# (additionalWorkspaces). The SPIRE agent in the VM reads both files there and attests its node to the SPIRE server of the current
# kubectl context. Needs SANDBOX_GITHUB_ID, the numeric id of your GitHub account (gh api user --jq .id).
# The token is a secret until the agent has used it. It goes into a file with mode 600 and is never printed.
# Exit codes: 1 = a wrong setup (not on the host, no or wrong id, no trust domain, sbxenv.yaml does not mount the folder): stop.
#             3 = the cluster cannot make the token (no kubectl context, no SPIRE server): sbxenv.yaml lets the run go on without it.
set -euo pipefail

# --- Variables
sbx_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo=$(dirname "$sbx_dir")
out=$HOME/.sbx/spire # the same absolute path is in additionalWorkspaces of sbxenv.yaml and in the start command of the dev-tools kit
sbxenv=$sbx_dir/sbxenv.yaml
identity_file=$repo/code/mcp-sandbox/part-3-mcp-guardrails/config/cloud/kind/identity.yaml
ttl=600 # seconds; the agent starts with the VM, a minute after this script
github_id=${SANDBOX_GITHUB_ID:-}
context=$(kubectl config current-context 2>/dev/null || true)
trust_domain=$(yq -r .trust_domain "$identity_file" 2>/dev/null || true)
mounted=$(OUT=$out yq -r '.additionalWorkspaces[] | select(.path == strenv(OUT)) | .path' "$sbxenv" 2>/dev/null || true)
# The alias names this agent for the entries of the user: a workload entry takes it as its parentID. SPIRE refuses an ID under /spire/.
alias=spiffe://$trust_domain/microvm/$github_id

# --- Prechecks
die() { echo "spire.sh: $1" >&2; exit "${2:-1}"; }

[ -z "${SANDBOX_NAME:-}" ] || die "run this on the host, not in the sandbox ($SANDBOX_NAME): the token is made by the SPIRE server of the cluster."
[ "${1:-}" = enroll ] || die "usage: spire.sh enroll"
[[ $github_id =~ ^[0-9]+$ ]] || die "SANDBOX_GITHUB_ID is not set to a number. Use the numeric id of your GitHub account, not the login: export SANDBOX_GITHUB_ID=\$(gh api user --jq .id)"
{ [ -n "$trust_domain" ] && [ "$trust_domain" != null ]; } || die "cannot read trust_domain from $identity_file"
[ -n "$mounted" ] || die "$sbxenv does not mount $out. Put this under additionalWorkspaces: - path: $out, readOnly: true"
[ -n "$context" ] || die "kubectl has no current context, so no join token is made. Set one: kubectl config use-context <name>" 3

# --- Token generation
k() { kubectl --context "$context" "$@"; }
spire_server() { k -n spire-system exec spire-server-0 -c spire-server -- /opt/spire/bin/spire-server "$@"; }

mkdir -p "$out"
chmod 700 "$out"
# A failed run must not leave an old token behind.
rm -f "$out/join-token"
# The bundle is public. Read it first: a failure here stops before a token exists.
spire_server bundle show -format spiffe > "$out/bundle.spiffe.tmp" || { rm -f "$out/bundle.spiffe.tmp"; die "cannot read the trust bundle. Is the SPIRE server of $context running?" 3; }
mv "$out/bundle.spiffe.tmp" "$out/bundle.spiffe"

# JSON output: the field value is the token. The token goes into the variable and the file only.
json=$(spire_server token generate -ttl "$ttl" -spiffeID "$alias" -output json) || die "cannot make a join token. Is joinToken enabled in the spire chart (spire.yaml)?" 3
token=$(jq -er .value <<< "$json") || die "the SPIRE server answered without a token." 3
( umask 077; printf '%s' "$token" > "$out/join-token.tmp" )
mv "$out/join-token.tmp" "$out/join-token"
echo "spire: join token for user $github_id in $out (valid $((ttl / 60)) minutes), alias $alias"
