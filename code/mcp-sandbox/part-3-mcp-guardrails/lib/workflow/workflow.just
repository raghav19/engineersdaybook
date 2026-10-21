# Shared by every component justfile: `import '<../>lib/workflow/workflow.just'`. This file holds the settings, the variables and the
# help; the recipes are in package.just (package-artifact), diff.just (diff), publish.just (publish-artifact) and compose.just (compose-stack).
#
# The component is the folder the justfile sits in. Its name is the folder name, and the folder name is
# also the OCIRepository / Kustomization name in the stack of its app, sync/<full name>/infra/<app>/stack.yaml.
#
#   just package-artifact    the folder with the config values applied, rendered completely (charts included)
#                            -> out/<name>/manifests.yaml, then checked against the Kubernetes, Flux and ecosystem schemas.
#                            This is the artifact. The converged config it used is out/values.yaml.
#                            A component whose flag <name>_enabled is false gets an empty manifests.yaml: nothing is rendered, checked or published.
#   just diff                the change against the artifact `base` (origin/main) pins in its stack,
#                            that is what the cluster runs. For a disabled component: every object that Flux will remove
#   just publish-artifact    package-artifact (which validates), then push out/<name>/manifests.yaml, tagged with the commit. The tag and digest go into out/manifest.yaml
#   just compose-stack       stack-composer (tools/) composes the stack of this component: the published tag and digest (out/manifest.yaml) patch its
#                            flux/stack.yaml, which patches the stack, or removes the pair when the flag is false. The stack is
#                            sync/<full name>/infra/<app>/stack.yaml (the app is policies for platform/policies/, else addons). Never edit it by hand.
#
# out/<name>/ holds everything of one component. Only manifests.yaml is published:
#
#   manifests.yaml   the artifact
#   build/ks.yaml    the Flux Kustomization flate reads to render this folder
#   build/src/       a copy of the folder with the config values applied (only when it has a setters.yaml)
#   baseline/        the artifact `base` pins, pulled by diff

set lazy
set allow-duplicate-recipes

# the settings and ALL the variables of the recipes below and of tools/tools.just: see common.just
import 'common.just'

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
import 'publish.just'
import 'compose.just'
import '../../tools/tools.just'
