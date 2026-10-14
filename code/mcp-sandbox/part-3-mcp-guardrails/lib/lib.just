# Shared by every component justfile: `import '<../>lib/lib.just'`.
#
# The component is the folder the justfile sits in. Its name is the folder name, and the folder name is
# also the OCIRepository / Kustomization name in clusters/<cluster>/sync/stack.yaml.
#
#   just build      the folder with the config values applied, rendered completely (charts included)
#                   -> out/<name>/manifests.yaml, then checked against the Kubernetes, Flux and ecosystem schemas.
#                   This is the artifact. The converged config it used is out/values.yaml.
#   just diff       the change against the artifact `base` (origin/main) pins in stack.yaml,
#                   that is what the cluster runs
#   just push       build (which validates), then push out/<name>/manifests.yaml, tagged with the commit
#   just pin        write the pushed tag and digest into stack.yaml (commit it in a PR)
#
# out/<name>/ holds everything of one component. Only manifests.yaml is pushed:
#
#   manifests.yaml   the artifact
#   build/ks.yaml    the Flux Kustomization flate reads to render this folder
#   build/src/       a copy of the folder with the config values applied (only when it has a setters.yaml)
#   diff/ks.yaml     the same, for baseline/
#   baseline/        the artifact `base` pins, pulled by diff
#   push.json        tag and digest of the last push, read by pin

set quiet
set lazy
set fallback
set allow-duplicate-recipes
set shell := ['bash', '-euo', 'pipefail', '-c']

# VARIABLES

root := parent_directory(source_directory())
name := file_name(justfile_directory())
out := root / 'out' / name
cluster := 'kind'
stack := 'clusters/' + cluster + '/sync/stack.yaml'
base := 'origin/main'

# registry
registry := 'oci://ghcr.io/raghav19/mcp-guardrails'
tag := `git log -1 --format=%h --abbrev=12 -- .`
ghcr_user := env('GHCR_USER', 'raghav19')
# placeholder-ghcr.io is replaced by the sbx proxy
ghcr_push_token := env('GHCR_PUSH_TOKEN', 'placeholder-ghcr.io')

# the build functions of lib/tools (config-builder, value-injector): each its own artifact <registry>/tools/<name>. Their digests are
# config, not part of this library: config/tools/pins.yaml, from the block `just lib/tools/<name>/push` prints
tools_pin := root / 'config' / 'tools' / 'pins.yaml'
tools := root / 'out' / '.tools'

# The `path` of a Flux Kustomization is relative to the root of the Git repository, as in Flux. These turn
# the absolute paths of this checkout into that form, for the stubs flate reads:
#   top           the root of the Git repository
#   src           this component's folder: the stub of build renders it
#                 ./code/mcp-sandbox/part-3-mcp-guardrails/platform/routes
#   build_src     the copy of this folder with the config values applied: the stub of build renders it when there is a setters.yaml
#                 ./code/mcp-sandbox/part-3-mcp-guardrails/out/routes/build/src
#   baseline_src  the artifact pulled by diff for this component: the stub of diff renders it
#                 ./code/mcp-sandbox/part-3-mcp-guardrails/out/routes/baseline
top := `git rev-parse --show-toplevel`
src := '.' + trim_start_match(justfile_directory(), top)
build_src := '.' + trim_start_match(out, top) + '/build/src'
baseline_src := '.' + trim_start_match(out, top) + '/baseline'

# used by flate to determine which kinds are cluster-scoped 
# and should have their namespace removed
cluster_scoped := 'ValidatingAdmissionPolicy|ValidatingAdmissionPolicyBinding|MutatingAdmissionPolicy|RuntimeClass|CSIDriver'

# yq filters

# build: remove .metadata.namespace from the objects whose kind is in cluster_scoped (flate puts one there)
drop_namespace := 'del(select(.kind | test("^(' + cluster_scoped + ')$")) | .metadata.namespace)'

# _baseline: from stack.yaml, the digest of this component's OCIRepository ("" when it has none yet)
pinned_digest := 'select(.spec.url == "' + registry + '/' + name + '") | .spec.ref.digest // ""'

# pin: in stack.yaml, set spec.ref of the component's OCIRepository to the tag and digest of the last
# push (out/<name>/push.json), keeping only those two fields
pin_ref := '(select(.spec.url == "' + registry + '/' + name + '") | .spec.ref)' + \
           ' = (load("' + out + '/push.json") | pick(["tag", "digest"]) | ... style="")'

# RECIPES

# reads:  nothing
# writes: nothing
# output: the list of recipes
# list the recipes
[default]
help:
    just --list

# reads:  this folder, through out/<name>/build/ks.yaml
# writes: out/<name>/manifests.yaml
# output: the schema result and the inflated output manifest
# - the namespace flate puts on the kinds in cluster_scoped is removed
# - the component's own checks run first (_checks), the schema validation last: a build that does not
build: _checks _stub_build
    flate --no-progress build all \
      --path {{ out }}/build \
      --skip-kinds HelmRelease,OCIRepository \
      --skip-crds=false \
      --skip-secrets=false \
      | yq '{{ drop_namespace }}' > {{ out }}/manifests.yaml

    flux-schema validate {{ out }}/manifests.yaml \
      --schema-location default \
      --schema-location ecosystem

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

# reads:  the digests and binary sha256 of config/tools/pins.yaml, then the registry, only for a digest that is not in out/.tools/ yet
# writes: out/.tools/<name>/<digest>/<name>, and the link out/.tools/<name>/<name> to it
# output: nothing; _config and _apply run the links
# pull the build functions (lib/tools) at the digests the config pins
[script('bash')]
_tools:
    set -euo pipefail
    pull() {
      digest=$(yq -r ".\"$1\".digest // \"\"" {{ tools_pin }})
      binary=$(yq -r ".\"$1\".binary // \"\"" {{ tools_pin }})
      [ -n "$digest" ] && [ -n "$binary" ] || { echo "$1 is not pinned in config/tools/pins.yaml: run 'just lib/tools/$1/push' (host) and put the block it prints there" >&2; exit 1; }
      dir={{ tools }}/$1/${digest#sha256:}
      if [ ! -x "$dir/$1" ]; then
        rm -rf "$dir" && mkdir -p "$dir"
        flux pull artifact {{ registry }}/tools/$1@$digest -o "$dir" \
          --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" >/dev/null 2>&1 \
          || { rm -rf "$dir"; echo "cannot pull {{ registry }}/tools/$1@$digest" >&2; exit 1; }
      fi
      # the pinned sha256 of the binary is checked on every run, not only after a pull
      [ "sha256:$(sha256sum "$dir/$1" | cut -d' ' -f1)" = "$binary" ] \
        || { echo "$1: the binary of $digest is not $binary" >&2; rm -rf "$dir"; exit 1; }
      ln -sfn "${digest#sha256:}/$1" {{ tools }}/$1/$1
    }
    pull config-builder
    pull value-injector

# reads:  the *.yaml of config/ and of each level down to the placement of clusters/<cluster>/cluster.yaml
#         (config/cloud/local/, or config/cloud/aws/, config/cloud/aws/dev/, ...), each only where it exists
# writes: out/values.yaml
# output: the config files it merged
# the converged config: the overrides of the cluster as one flat set, the file lower in the hierarchy wins. The default of a value is
# the manifest, so a value that nothing overrides is not in it. Every build writes it, whether the folder uses it or not
_config: _tools
    {{ tools }}/config-builder/config-builder {{ root }}/config {{ root }}/clusters/{{ cluster }}/cluster.yaml {{ root }}/out/values.yaml

# reads:  out/values.yaml, and setters.yaml of this folder
# writes: out/<name>/build/src/ (a copy of this folder with the values set), only when the folder has a setters.yaml
# the function: setters.yaml says which config value goes into which field, value-injector (lib/tools) sets it in the copy
[script('bash')]
_apply: _config
    rm -rf {{ out }}/build/src
    [ -f setters.yaml ] || exit 0
    {{ tools }}/value-injector/value-injector {{ root }}/out/values.yaml {{ justfile_directory() }} {{ out }}/build/src

# reads:  nothing, it is generated from the folder name and path
# writes: out/<name>/build/ks.yaml
# output: the Flux Kustomization flate reads to render this folder, used by build and by the candidate side of diff
# flate can only inflate Flux objects, not plain folders, and it needs these references to know what to render:
# - a GitRepository: a stub, flate maps it to the working tree and fetches nothing
# - a Kustomization named after this folder (as in stack.yaml) whose path is the folder to render
# a folder with a setters.yaml is rendered from the copy with the values applied (build/src), the others from the folder itself
# write the Kustomization that renders this folder
[script('bash')]
_stub_build: _apply
    mkdir -p {{ out }}/build
    path='{{ src }}'
    if [ -d {{ out }}/build/src ]; then path='{{ build_src }}'; fi
    cat > {{ out }}/build/ks.yaml <<EOF
    apiVersion: source.toolkit.fluxcd.io/v1
    kind: GitRepository
    metadata: {name: flux-system, namespace: flux-system}
    spec: {interval: 10m, url: https://example.invalid/repo.git}
    ---
    apiVersion: kustomize.toolkit.fluxcd.io/v1
    kind: Kustomization
    metadata: {name: {{ name }}, namespace: flux-system}
    spec: {interval: 10m, path: $path, sourceRef: {kind: GitRepository, name: flux-system}}
    EOF

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

# reads:  out/<name>/manifests.yaml, and only that: the rest of out/<name>/ is helper files
# writes: the registry, and out/<name>/push.json (the tag and digest)
# output: the artifact in the registry as <registry>/<name>:<commit>, with its tag and digest printed
# build (which validates), then push the artifact
push: build
    flux push artifact {{ registry }}/{{ name }}:{{ tag }} \
      --path {{ out }} \
      --ignore-paths '/*,!/manifests.yaml' \
      --source "$(git remote get-url origin)" \
      --revision "$(git branch --show-current)@sha1:$(git rev-parse HEAD)" \
      --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" \
      --output json \
      | jq --arg tag {{ tag }} '. + {tag: $tag}' \
      | tee {{ out }}/push.json

# reads:  out/<name>/push.json
# writes: stack.yaml
# output: stack.yaml with this component's OCIRepository pointing at the pushed tag and digest
# rollback: git revert the commit
# rollout: record the pushed artifact in stack.yaml
pin:
    yq -i '{{ pin_ref }}' {{ root }}/{{ stack }}

# reads:  nothing
# writes: nothing
# output: pass or fail
# a component justfile redefines this to add its own checks; build runs it
_checks:
    true
