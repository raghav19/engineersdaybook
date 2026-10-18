#!/usr/bin/env bash
# The sandbox identity on a kind cluster. Run it on the host. Usage: kube.sh install|write [context]
#   install   apply sandbox-operator.yaml: the ServiceAccount, its roles and bindings (once per cluster, and after editing the file)
#   write     write .sbx/kubeconfig: a new token for that ServiceAccount (the VM reads it as /run/sandbox/source/.sbx/kubeconfig)
# The context is the argument, else SANDBOX_KUBE_CONTEXT, else the current context of kubectl. A context that you did not name must be a kind-* one.
# The VM reaches a kind API server (127.0.0.1) as host.docker.internal through the sbx proxy, which passes TLS through: so the file holds a real token.
set -euo pipefail

sa=sandbox-operator
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

die() { echo "kube.sh: $*" >&2; exit 1; }

mode=${1:-}
ctx=${2:-${SANDBOX_KUBE_CONTEXT:-}}
if [ -z "$ctx" ]; then
  ctx=$(kubectl config current-context) || die "kubectl has no current context."
  [[ $ctx == kind-* ]] || die "the current context $ctx is not a kind cluster. Name it to use it: just sandbox agent kube $ctx"
fi
k() { kubectl --context "$ctx" "$@"; }

case $mode in
  install)
    k apply -f "$here/sandbox-operator.yaml" > /dev/null
    echo "kube: $ctx has the identity $sa/$sa, with view and sandbox-writer in all namespaces"
    ;;
  write)
    k -n "$sa" get serviceaccount "$sa" > /dev/null 2>&1 || die "$ctx has no sandbox identity yet. Run: just sandbox agent kube $ctx"
    token=$(k -n "$sa" create token "$sa" --duration="${SANDBOX_KUBE_TOKEN_DURATION:-720h}")
    # The context's own cluster entry (server and CA), with the admin credential replaced by the token. tls-server-name is a SAN of every kind API server certificate.
    k config view --minify --flatten -o json | jq --arg t "$token" --arg sa "$sa" '
      .users = [{name: $sa, user: {token: $t}}]
      | .contexts[0].context.user = $sa
      | .clusters[0].cluster |= if (.server | test("//127\\.0\\.0\\.1:"))
          then (.server |= sub("//127\\.0\\.0\\.1:"; "//host.docker.internal:")) + {"tls-server-name": "localhost"}
          else . end' > "$here/../kubeconfig"
    echo "kube: wrote .sbx/kubeconfig for $ctx"
    ;;
  *) die "usage: kube.sh install|write [context]" ;;
esac
