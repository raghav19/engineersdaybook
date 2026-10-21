# diff: the change against the artifact `base` pins. Imported by workflow.just; uses _manifest of package.just.

# reads:  out/<name>/baseline/manifests.yaml (what `base` pins), and out/<name>/manifests.yaml (this folder, built)
# writes: nothing
# output: a unified diff of the two artifacts, so you see the objects that change in the cluster (charts inflated).
#         Both sides are the manifests.yaml that publish-artifact sends and Flux applies: an unchanged component gives an empty diff.
#         A disabled component has an empty manifests.yaml, so the diff lists every object of the pinned artifact: what Flux will remove.
#         CRDs and Secrets are left out of both sides; FLATE_SKIP_CRDS=false shows them. No pin yet: everything is new.
[script('bash')]
diff: _manifest _baseline
    set -euo pipefail
    filter() {
      [ -s "$1" ] || return 0
      if [ "${FLATE_SKIP_CRDS:-true}" = false ]; then cat "$1"
      else yq 'select(.kind != "CustomResourceDefinition" and .kind != "Secret")' "$1"; fi
    }
    left={{ out }}/baseline/manifests.yaml
    [ -f "$left" ] || left=/dev/null
    diff -u --label baseline --label {{ name }} <(filter "$left") <(filter {{ out }}/manifests.yaml) || [ $? -eq 1 ]

# reads:  the stack of the app of the component at `base` (the digest of the component), then the registry
# writes: out/<name>/baseline/
# output: the artifact `base` pins, which is what the cluster runs (left empty when there is no pin yet)
# pull the artifact `base` pins for the component, by digest
[script('bash')]
_baseline:
    set -euo pipefail
    rm -rf {{ out }}/baseline && mkdir -p {{ out }}/baseline
    # a stack that is not on `base` yet (a new stack, for example after a move) means no pin yet.
    # The legacy stack is the one file that held every component before the apps: remove this fallback after the pull request that introduced the apps.
    digest=$( (git -C {{ root }} show {{ base }}:./{{ stack }} 2>/dev/null || git -C {{ root }} show {{ base }}:./{{ legacy_stack }} 2>/dev/null || true) | yq -N '{{ pinned_digest }}')
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
