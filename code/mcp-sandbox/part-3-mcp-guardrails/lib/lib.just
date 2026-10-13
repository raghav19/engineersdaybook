# Shared by every component justfile: `import '<../>lib/lib.just'`. The component is the folder the justfile sits in; its name is the
# folder name, and the folder name is also the OCIRepository / Kustomization name in clusters/<cluster>/sync/stack.yaml.
#
#   just build      the folder, rendered completely (charts included) -> out/<name>/manifests.yaml. This is the artifact.
#   just diff       the change against the artifact <base> (default origin/main) pins in stack.yaml: what the cluster runs
#   just validate   build, then flux-schema validate against the Kubernetes, Flux and ecosystem schemas
#   just push       validate, then push out/<name>/ to the URL its OCIRepository in stack.yaml pulls, tagged with the commit
#   just pin        write the pushed tag and digest into stack.yaml (a developer or agent commits it in a PR)
#

set quiet
set lazy
set fallback
set allow-duplicate-recipes
set shell := ['bash', '-euo', 'pipefail', '-c']

# VARIABLES
root := parent_directory(source_directory())
name := file_name(justfile_directory())
out := root / 'out' / name
tag := `git log -1 --format=%h --abbrev=12 -- .`
registry := 'oci://ghcr.io/raghav19/mcp-guardrails'
ghcr_user := env('GHCR_USER', 'raghav19')
# note: placeholder-ghcr.io replaced by sbx proxy
ghcr_push_token := env('GHCR_PUSH_TOKEN', 'placeholder-ghcr.io')
# kinds flate (0.6.5) does not know are cluster-scoped: it puts a namespace on them. Found by rendering one of each; remove when flate fixes it.
cluster_scoped := 'ValidatingAdmissionPolicy|ValidatingAdmissionPolicyBinding|MutatingAdmissionPolicy|RuntimeClass|CSIDriver'
# a Kustomization path is relative to the root of the Git repository
top := `git rev-parse --show-toplevel`
src := '.' + trim_start_match(justfile_directory(), top)
baseline := '.' + trim_start_match(out, top) + '/baseline'

# RECIPES
[default]
help:
    just --list

# the artifact: this folder rendered completely by flate, as Flux would apply it, nothing left to inflate in the cluster. The HelmRelease and its
# chart OCIRepository are dropped, CRDs and Secrets stay in. A chart's CRDs are never pruned: that is a postRenderer on its HelmRelease
# (see agentgateway/crds.yaml). Deleting them is an explicit step: `just clusters/kind/delete-crds`.
# flate puts a namespace on the kinds in cluster_scoped; it is removed.
build: (_stub out + '/build' src)
    flate --no-progress build all --path {{ out }}/build --skip-crds=false --skip-secrets=false --skip-kinds HelmRelease,OCIRepository \
      | yq 'del(select(.kind | test("^({{ cluster_scoped }})$")) | .metadata.namespace)' > {{ out }}/manifests.yaml

# the change this makes to the cluster: this folder rendered now, against the artifact that <base>'s stack.yaml pins (what runs). flate renders
# both sides the same way, so CRDs and Secrets are not shown (flags go to flate: --skip-crds=false). A component with no pin yet shows
# entirely as added.
[script('bash')]
diff base='origin/main' cluster='kind' *flags: (_stub out + '/build' src) (_stub out + '/diff' baseline)
    set -euo pipefail
    pin=$(git -C {{ root }} show {{ base }}:./clusters/{{ cluster }}/sync/stack.yaml \
      | yq -N 'select(.kind == "OCIRepository" and .metadata.name == "{{ name }}") | .spec.url + ":" + .spec.ref.tag')
    rm -rf {{ out }}/baseline && mkdir -p {{ out }}/baseline
    case "$pin" in
      ""|*:unpinned) echo "baseline: none ({{ name }} has no pin in {{ base }})" ;;
      *) echo "baseline: $pin"
         flux pull artifact "$pin" -o {{ out }}/baseline --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" >/dev/null 2>&1 \
           || { echo "cannot pull $pin" >&2; exit 1; } ;;
    esac
    render() { flate --no-progress build all --path "$1" --skip-kinds HelmRelease,OCIRepository {{ flags }}; }
    diff -u --label baseline --label {{ name }} <(render {{ out }}/diff) <(render {{ out }}/build) || [ $? -eq 1 ]

# the Flux Kustomization flate reads: named after this folder (as in stack.yaml), applying <path> of this repository
[script('bash')]
_stub dir path:
    mkdir -p {{ dir }}
    cat > {{ dir }}/ks.yaml <<EOF
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: GitRepository
    metadata: {name: flux-system, namespace: flux-system}
    spec: {interval: 10m, url: https://example.invalid/repo.git}
    ---
    apiVersion: kustomize.toolkit.fluxcd.io/v1
    kind: Kustomization
    metadata: {name: {{ name }}, namespace: flux-system}
    spec: {interval: 10m, path: {{ path }}, sourceRef: {kind: GitRepository, name: flux-system}}
    EOF

validate: build _checks
    flux-schema validate {{ out }}/manifests.yaml --schema-location default --schema-location ecosystem --verbose

# validate, then push out/<name>/manifests.yaml as <registry>/<name>:<commit> (the rest of out/<name>/ is helper files and is not pushed);
# the tag and digest land in out/<name>/push.json
push: validate
    flux push artifact {{ registry }}/{{ name }}:{{ tag }} --path {{ out }} --ignore-paths '/*,!/manifests.yaml' \
      --source "$(git remote get-url origin)" \
      --revision "$(git branch --show-current)@sha1:$(git rev-parse HEAD)" \
      --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" --output json \
      | jq --arg tag {{ tag }} '. + {tag: $tag}' | tee {{ out }}/push.json

# rollout: write the pushed tag and digest into this component's OCIRepository in stack.yaml 
# rollback: git revert the commit
pin cluster='kind':
    yq -i '(select(.spec.url == "{{ registry }}/{{ name }}") | .spec.ref) = (load("{{ out }}/push.json") | pick(["tag", "digest"]) | ... style="")' \
      {{ root }}/clusters/{{ cluster }}/sync/stack.yaml

_checks:
    true
