# The settings and the variables that lib/workflow/workflow.just and tools/tools.just share. Both import this file. A justfile that imports both
# loads it once.

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
