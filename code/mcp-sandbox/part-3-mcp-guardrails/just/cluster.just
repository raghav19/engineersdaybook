# The kind cluster and the one hand-over to Flux, on the host. `up` needs no credential, so it always comes up; `credentials` adds the two
# Secrets Flux cannot get from Git. Both are safe to run again. The cluster is a folder under clusters/ (default kind); its kube context is
# kind-<name in clusters/<cluster>/kind-config.yaml>.
# `credentials` needs no environment variable: it decrypts the ghcr.io token of .sbx/secrets.json inside the one command that creates
# ghcr-pull, with your personal sops key (~/.config/sops/age/keys.txt, or SOPS_AGE_KEY_FILE), and reads one file, the private age key of
# this cluster (created once, never in Git): AGE_KEY_FILE. The token reads the private artifacts. A classic PAT cannot be limited to one
# package: if it also has write:packages, the cluster holds that right, so use a read:packages token of its own when that matters.
set quiet

root := justfile_directory()
# The chart version equals the Flux Operator release. Check it with `helm show chart <chart> --version <v>` when you change it.
flux_operator_chart := 'oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator'
flux_operator_version := '0.61.0'
# helm waits 5 minutes by default. The node pulls the operator image from ghcr.io on first start, which can take longer than that.
flux_operator_timeout := env('FLUX_OPERATOR_TIMEOUT', '10m')
ghcr_user := env('GHCR_USER', 'raghav19')
ghcr_token_file := root / '../../../.sbx/secrets.json'

# create the kind cluster, install the Flux Operator, apply the FluxInstance. Flux does the rest
[script('bash')]
up cluster='kind': (_need 'kind' 'kubectl' 'helm' 'yq')
    set -eu
    name=$(yq .name {{ root }}/clusters/{{ cluster }}/kind-config.yaml); ctx=kind-$name
    kind get clusters | grep -qx "$name" || kind create cluster --config {{ root }}/clusters/{{ cluster }}/kind-config.yaml
    # kind returns when the control plane is up. The operator needs Ready nodes and kube-proxy (ClusterIP of the API) on its node.
    kubectl --context "$ctx" wait --for=condition=Ready node --all --timeout=5m
    kubectl --context "$ctx" -n kube-system rollout status daemonset/kube-proxy --timeout=5m
    kubectl --context "$ctx" create namespace flux-system --dry-run=client -o yaml | kubectl --context "$ctx" apply -f -
    helm upgrade --install flux-operator {{ flux_operator_chart }} --version {{ flux_operator_version }} \
      --kube-context "$ctx" --namespace flux-system --wait --timeout {{ flux_operator_timeout }}
    kubectl --context "$ctx" apply -f {{ root }}/clusters/{{ cluster }}/sync/flux-instance.yaml
    echo "Flux is installed. It waits for the credentials: just cluster credentials {{ cluster }}"
    echo "Watch it: kubectl --context $ctx -n flux-system get kustomizations"

# create the two Secrets Flux needs, sops-age (decrypt Git) and ghcr-pull (private artifacts). Run after `up`
[script('bash')]
credentials cluster='kind': (_need 'kubectl' 'sops' 'yq')
    set -eu
    name=$(yq .name {{ root }}/clusters/{{ cluster }}/kind-config.yaml); ctx=kind-$name
    age_key=${AGE_KEY_FILE:-$HOME/.config/sops/age/mcp-guardrails-{{ cluster }}.agekey}
    [ -f "$age_key" ] || { echo "No age key at $age_key. Create one: age-keygen -o $age_key (see README, Secrets)" >&2; exit 1; }
    sops -d --extract '["ghcr.io"]' {{ ghcr_token_file }} >/dev/null 2>&1 \
      || { echo "Cannot decrypt the ghcr.io token in {{ ghcr_token_file }}. sops needs your personal age key: ~/.config/sops/age/keys.txt, or SOPS_AGE_KEY_FILE" >&2; exit 1; }
    kubectl --context "$ctx" -n flux-system create secret generic sops-age --from-file=age.agekey="$age_key" --dry-run=client -o yaml \
      | kubectl --context "$ctx" apply -f -
    kubectl --context "$ctx" -n flux-system create secret docker-registry ghcr-pull --docker-server=ghcr.io --docker-username={{ ghcr_user }} \
      --docker-password="$(sops -d --extract '["ghcr.io"]' {{ ghcr_token_file }})" --dry-run=client -o yaml \
      | kubectl --context "$ctx" apply -f -

# delete the kind cluster
down cluster='kind': (_need 'kind' 'yq')
    kind delete cluster --name "$(yq .name {{ root }}/clusters/{{ cluster }}/kind-config.yaml)"

# stop with a message that says what to run instead of a raw kubectl or kind error
_need +tools:
    for t in {{ tools }}; do command -v "$t" >/dev/null || { echo "missing tool $t. Run: mise install" >&2; exit 1; }; done
