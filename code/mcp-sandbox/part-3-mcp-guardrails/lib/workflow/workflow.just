# Shared by every component justfile: `import '<../>lib/workflow/workflow.just'`. This file holds the settings, the variables and the
# help; the recipes are in package.just (build), diff.just (diff) and push.just (push, pin).
#
# The component is the folder the justfile sits in. Its name is the folder name, and the folder name is
# also the OCIRepository / Kustomization name in sync/<full name>/infra-stack.yaml.
#
#   just build      the folder with the config values applied, rendered completely (charts included)
#                   -> out/<name>/manifests.yaml, then checked against the Kubernetes, Flux and ecosystem schemas.
#                   This is the artifact. The converged config it used is out/values.yaml.
#                   A component whose flag <name>_enabled is false gets an empty manifests.yaml: nothing is rendered, checked or pushed.
#   just diff       the change against the artifact `base` (origin/main) pins in its stack,
#                   that is what the cluster runs. For a disabled component: every object that Flux will remove
#   just push       build (which validates), then push out/<name>/manifests.yaml, tagged with the commit. The tag and digest go into out/manifest.yaml
#   just pin        stack-composer (tools/) composes the stack of this component: the pushed tag and digest (out/manifest.yaml) patch its
#                   flux/stack-entry.yaml, which patches the stack, or removes the pair when the flag is false. The stack is
#                   sync/<full name>/infra-stack.yaml. Never edit it by hand.
#
# out/<name>/ holds everything of one component. Only manifests.yaml is pushed:
#
#   manifests.yaml   the artifact
#   build/ks.yaml    the Flux Kustomization flate reads to render this folder
#   build/src/       a copy of the folder with the config values applied (only when it has a setters.yaml)
#   baseline/        the artifact `base` pins, pulled by diff

set quiet
set lazy
set fallback
set allow-duplicate-recipes
set shell := ['bash', '-euo', 'pipefail', '-c']

# the build functions (config-builder, value-injector): their build, push and pull are all in tools/tools.just
mod tools '../../tools/tools.just'

# VARIABLES

root := parent_directory(parent_directory(source_directory()))
name := file_name(justfile_directory())
out := root / 'out' / name
# the config value that switches this component: istio-ingress -> istio_ingress_enabled (no value means enabled)
flag := replace(name, '-', '_') + '_enabled'
# the cluster that a run targets: CLUSTER=<name> just <component>/pin. Its folder is clusters/<cluster>/ (bring-up, cluster.yaml)
cluster := env('CLUSTER', 'kind')
# the sync folder of the cluster, sync/<full name>/: the name is `sync:` in clusters/<cluster>/cluster.yaml (local-kind, later aws-dev-us-east-1)
sync := 'sync/' + shell('yq .sync "$1"', root / 'clusters' / cluster / 'cluster.yaml')
cluster_name := file_name(sync)
# every component is in the one stack of the cluster
stack := sync + '/infra-stack.yaml'
base := 'origin/main'
# what `push` recorded: the pins of the tools (`tools:`) and of the components of each cluster (`components:`). Local, next to out/values.yaml. `pin` reads it
manifest := root / 'out' / 'manifest.yaml'

# registry
registry := 'oci://ghcr.io/raghav19/mcp-guardrails'
tag := `git log -1 --format=%h --abbrev=12 -- .`
ghcr_user := env('GHCR_USER', 'raghav19')
# placeholder-ghcr.io is replaced by the sbx proxy
ghcr_push_token := env('GHCR_PUSH_TOKEN', 'placeholder-ghcr.io')

# where the pulled build functions are linked, by the `_tools` recipe of tools/tools.just (the same path is set there)
tools := root / 'out' / '.tools'

# The `path` of a Flux Kustomization is relative to the root of the Git repository, as in Flux. These turn
# the absolute paths of this checkout into that form, for the stubs flate reads:
#   top           the root of the Git repository
#   src           this component's folder: the stub of build renders it
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

# build: remove .metadata.namespace from the objects whose kind is in cluster_scoped (flate puts one there)
drop_namespace := 'del(select(.kind | test("^(' + cluster_scoped + ')$")) | .metadata.namespace)'

# _baseline: from its stack, the digest of this component's OCIRepository ("" when it has none yet)
pinned_digest := 'select(.spec.url == "' + registry + '/' + name + '") | .spec.ref.digest // ""'

# RECIPES

# reads:  nothing
# writes: nothing
# output: the list of recipes
# list the recipes
[default]
help:
    just --list

# the recipes, by command
import 'package.just'
import 'diff.just'
import 'push.just'
