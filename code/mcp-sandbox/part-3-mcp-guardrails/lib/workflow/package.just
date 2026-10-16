# package-artifact: the folder with the config values applied, rendered and checked -> out/<name>/manifests.yaml. Imported by workflow.just.

# reads:  this folder, through out/<name>/build/ks.yaml
# writes: out/<name>/manifests.yaml
# output: the inflated output manifest: the artifact, not yet validated
# - the namespace flate puts on the kinds in cluster_scoped is removed
# - the component's own checks run first (_checks)
# - when the flag of the component is false (out/values.yaml), nothing is rendered and manifests.yaml is empty. An empty file means disabled
# render the artifact; package-artifact validates it, diff compares it with the one `base` pins
[script('bash')]
_manifest: _checks _stub_build
    set -euo pipefail
    if [ "$(yq '.{{ flag }}' {{ root }}/out/values.yaml)" = false ]; then
      echo "disabled: {{ flag }} is false, nothing built"
      : > {{ out }}/manifests.yaml
      exit 0
    fi
    flate --no-progress build all \
      --path {{ out }}/build \
      --skip-kinds HelmRelease,OCIRepository \
      --skip-crds=false \
      --skip-secrets=false \
      | yq '{{ drop_namespace }}' > {{ out }}/manifests.yaml

# reads:  out/<name>/manifests.yaml, written by _manifest
# writes: nothing
# output: the schema result; nothing for a disabled component (its manifests.yaml is empty)
# the artifact, then its schema validation last: a package-artifact run that does not validate does not push
[script('bash')]
package-artifact: _manifest
    set -euo pipefail
    [ -s {{ out }}/manifests.yaml ] || exit 0
    flux-schema validate {{ out }}/manifests.yaml \
      --schema-location default \
      --schema-location ecosystem

# reads:  the *.yaml of config/ and of each level down to the placement of clusters/<cluster>/cluster.yaml
#         (config/cloud/kind/, or config/cloud/aws/, config/cloud/aws/dev/, ...), each only where it exists
# writes: out/values.yaml
# output: the config files it merged
# the converged config: the overrides of the cluster as one flat set, the file lower in the hierarchy wins. The default of a value is
# the manifest, so a value that nothing overrides is not in it. Every package-artifact run writes it, whether the folder uses it or not
_config: tools::_tools
    {{ tools }}/config-builder/config-builder {{ root }}/config {{ root }}/clusters/{{ cluster }}/cluster.yaml {{ root }}/out/values.yaml

# reads:  out/values.yaml, and setters.yaml of this folder
# writes: out/<name>/build/src/ (a copy of this folder with the values set), only when the folder has a setters.yaml
# the function: setters.yaml says which config value goes into which field, value-injector (tools/) sets it in the copy
[script('bash')]
_apply: _config
    rm -rf {{ out }}/build/src
    [ -f setters.yaml ] || exit 0
    {{ tools }}/value-injector/value-injector {{ root }}/out/values.yaml {{ justfile_directory() }} {{ out }}/build/src

# reads:  nothing, it is generated from the folder name and path
# writes: out/<name>/build/ks.yaml
# output: the Flux Kustomization flate reads to render this folder, used by package-artifact and by the candidate side of diff
# flate can only inflate Flux objects, not plain folders, and it needs these references to know what to render:
# - a GitRepository: a stub, flate maps it to the working tree and fetches nothing
# - a Kustomization named after this folder (as in its stack) whose path is the folder to render
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

# reads:  nothing
# writes: nothing
# output: pass or fail
# a component justfile redefines this to add its own checks; package-artifact runs it
_checks:
    true
