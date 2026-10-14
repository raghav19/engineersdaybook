# diff: the change against the artifact `base` pins. Imported by workflow.just; uses _stub_build of package.just.

# reads:  out/<name>/baseline/ (what `base` pins) through out/<name>/diff/ks.yaml
#         this folder, through out/<name>/build/ks.yaml
# writes: nothing
# output: a unified diff of the rendered manifests, so you see the objects that 
#         change in the cluster(charts inflated)
diff: _stub_build _stub_diff _baseline
    diff -u --label baseline --label {{ name }} \
      <(flate --no-progress build all --path {{ out }}/diff --skip-kinds HelmRelease,OCIRepository) \
      <(flate --no-progress build all --path {{ out }}/build --skip-kinds HelmRelease,OCIRepository) \
      || [ $? -eq 1 ]

# reads:  stack.yaml at `base` (the digest of the component), then the registry
# writes: out/<name>/baseline/
# output: the artifact `base` pins, which is what the cluster runs (left empty when there is no pin yet)
# pull the artifact `base` pins for the component, by digest
[script('bash')]
_baseline:
    set -euo pipefail
    rm -rf {{ out }}/baseline && mkdir -p {{ out }}/baseline
    digest=$(git -C {{ root }} show {{ base }}:./{{ stack }} | yq -N '{{ pinned_digest }}')
    if [ -z "$digest" ]; then
      echo "baseline: none ({{ name }} has no pin in {{ base }})"
      exit 0
    fi
    echo "baseline: {{ registry }}/{{ name }}@$digest"
    flux pull artifact {{ registry }}/{{ name }}@$digest \
      -o {{ out }}/baseline \
      --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" \
      >/dev/null 2>&1 \
      || { echo "cannot pull the baseline" >&2; exit 1; }

# reads:  nothing, it is generated from the folder name and path
# writes: out/<name>/diff/ks.yaml
# output: the Flux Kustomization flate reads to render baseline/, used by the baseline side of diff
# the same reason: flate only inflates Flux objects, so the pulled baseline/ needs its own Kustomization
# it differs from build/ks.yaml only in its path, and sits in its own directory because flate renders
# every Flux object it finds in the --path it is given
# write the Kustomization that renders the pulled baseline
[script('bash')]
_stub_diff:
    mkdir -p {{ out }}/diff
    cat > {{ out }}/diff/ks.yaml <<EOF
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: GitRepository
    metadata: {name: flux-system, namespace: flux-system}
    spec: {interval: 10m, url: https://example.invalid/repo.git}
    ---
    apiVersion: kustomize.toolkit.fluxcd.io/v1
    kind: Kustomization
    metadata: {name: {{ name }}, namespace: flux-system}
    spec: {interval: 10m, path: {{ baseline_src }}, sourceRef: {kind: GitRepository, name: flux-system}}
    EOF
