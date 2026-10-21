# The settings and ALL the variables of lib/workflow/workflow.just (package.just, diff.just, publish.just, compose.just) and of tools/tools.just.
# Both import this file. A justfile that imports both loads it once. The variables that only the build of a tool uses are in tools/tools.just.
# The recipe files define no variable. How the files fit together, and how to find a definition: README.md in this folder.

set quiet
set fallback
set shell := ['bash', '-euo', 'pipefail', '-c']

# the root of part 3 (this file is lib/workflow/common.just)
root := parent_directory(parent_directory(source_directory()))
# the folder that the justfile sits in: a component, or a function of tools/
name := file_name(justfile_directory())
# what `publish-artifact` and the `push` of a tool recorded: the pins of the tools (`tools:`) and of the components of each cluster (`components:`).
# Local, next to out/values.yaml. `compose-stack` reads it
manifest := root / 'out' / 'manifest.yaml'
# where the build functions (tools/) are built
tools := root / 'out' / 'tools'

# registry
registry := 'oci://ghcr.io/raghav19/mcp-guardrails'
ghcr_user := env('GHCR_USER', 'raghav19')
# placeholder-ghcr.io is replaced by the sbx proxy
ghcr_push_token := env('GHCR_PUSH_TOKEN', 'placeholder-ghcr.io')

# COMPONENT: the paths, the cluster and the filters of the recipes of a component

out := root / 'out' / name
# the config value that switches this component: istio-ingress -> istio_ingress_enabled (no value means enabled)
flag := replace(name, '-', '_') + '_enabled'
# the cluster that a run targets: CLUSTER=<name> just <component>/compose-stack. Its folder is clusters/<cluster>/ (bring-up, cluster.yaml)
cluster := env('CLUSTER', 'kind')
# the sync folder of the cluster, sync/<full name>/: the name is `sync:` in clusters/<cluster>/cluster.yaml (local-kind, later aws-dev-us-east-1)
sync := 'sync/' + shell('yq .sync "$1"', root / 'clusters' / cluster / 'cluster.yaml')
cluster_name := file_name(sync)
# the app of this component: a component in platform/policies/ is in the app `policies`, every other component is in the app `addons`
app := if justfile_directory() =~ '/platform/policies/' { 'policies' } else { 'addons' }
# the stack of that app, in the sync folder of the cluster
stack := sync + '/infra/' + app + '/stack.yaml'
# the stack of the other app: stack-composer reads it to check dependsOn across the two apps
other_app := if app == 'policies' { 'addons' } else { 'policies' }
other_stack := sync + '/infra/' + other_app + '/stack.yaml'
# the one stack that held every component before the apps: diff reads it as the baseline in the pull request that introduced the apps
legacy_stack := sync + '/infra-stack.yaml'
base := 'origin/main'

# the tag of the artifact of this component: the commit that last changed its folder
artifact_tag := `git log -1 --format=%h --abbrev=12 -- .`

# The `path` of a Flux Kustomization is relative to the root of the Git repository, as in Flux. These turn
# the absolute paths of this checkout into that form, for the stubs flate reads:
#   top           the root of the Git repository
#   src           this component's folder: the stub of package-artifact renders it
#                 ./code/mcp-sandbox/part-3-mcp-guardrails/platform/routes
#   build_src     the copy of this folder with the config values applied: the stub of build renders it when there is a setters.yaml
#                 ./code/mcp-sandbox/part-3-mcp-guardrails/out/routes/build/src
top := `git rev-parse --show-toplevel`
src := '.' + trim_start_match(justfile_directory(), top)
build_src := '.' + trim_start_match(out, top) + '/build/src'

# used by flate to determine which kinds are cluster-scoped 
# and should have their namespace removed
cluster_scoped := 'ValidatingAdmissionPolicy|ValidatingAdmissionPolicyBinding|MutatingAdmissionPolicy|RuntimeClass|CSIDriver|ClusterSPIFFEID'

# yq filters

# package-artifact: remove .metadata.namespace from the objects whose kind is in cluster_scoped (flate puts one there)
drop_namespace := 'del(select(.kind | test("^(' + cluster_scoped + ')$")) | .metadata.namespace)'

# _baseline: from its stack, the digest of this component's OCIRepository ("" when it has none yet)
pinned_digest := 'select(.spec.url == "' + registry + '/' + name + '") | .spec.ref.digest // ""'
