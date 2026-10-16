# Shared by every component justfile: `import '<../>lib/workflow/workflow.just'`. This file holds the settings, the variables and the
# help; the recipes are in package.just (build), diff.just (diff) and push.just (push, pin).
#
# The component is the folder the justfile sits in. Its name is the folder name, and the folder name is
# also the OCIRepository / Kustomization name in sync/<full name>/infra-stack.yaml or app-stack.yaml.
#
#   just build      the folder with the config values applied, rendered completely (charts included)
#                   -> out/<name>/manifests.yaml, then checked against the Kubernetes, Flux and ecosystem schemas.
#                   This is the artifact. The converged config it used is out/values.yaml.
#   just diff       the change against the artifact `base` (origin/main) pins in its stack,
#                   that is what the cluster runs
#   just push       build (which validates), then push out/<name>/manifests.yaml, tagged with the commit
#   just pin        write the pushed tag and digest into its stack (commit it in a PR). The stacks are sync/<full name>/infra-stack.yaml
#                   (the components of platform/addons) and app-stack.yaml (the rest)
#
# out/<name>/ holds everything of one component. Only manifests.yaml is pushed:
#
#   manifests.yaml   the artifact
#   build/ks.yaml    the Flux Kustomization flate reads to render this folder
#   build/src/       a copy of the folder with the config values applied (only when it has a setters.yaml)
#   baseline/        the artifact `base` pins, pulled by diff
#   push.json        tag and digest of the last push, read by pin

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
# the cluster that a run targets: CLUSTER=<name> just <component>/pin. Its folder is clusters/<cluster>/ (bring-up, cluster.yaml)
cluster := env('CLUSTER', 'kind')
# the sync folder of the cluster, sync/<full name>/: the name is `sync:` in clusters/<cluster>/cluster.yaml (local-kind, later aws-dev-us-east-1)
sync := 'sync/' + shell('yq .sync "$1"', root / 'clusters' / cluster / 'cluster.yaml')
# the tier of the component decides its stack: the folders of platform/addons are the infrastructure, everything else is the app side
tier := if justfile_directory() =~ '/platform/addons/' { 'infra' } else { 'app' }
stack := sync + '/' + tier + '-stack.yaml'
base := 'origin/main'

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

# pin: in its stack, set spec.ref of the component's OCIRepository to the tag and digest of the last
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

# the recipes, by command
import 'package.just'
import 'diff.just'
import 'push.just'
