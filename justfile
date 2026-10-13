# The sandbox tooling lives in .sbx/. `mod` makes it `just sandbox <recipe>` from anywhere in the repo (it replaces the Taskfile's `sandbox:` prefix).
# Part 3 has its own justfiles under code/mcp-sandbox/part-3-mcp-guardrails/; they do not fall back to this one.
#
#   just sandbox            list the sandbox recipes
#   just sandbox run        developer: create or start the sandbox and open VS Code on it

set quiet

mod sandbox '.sbx'

# list the recipes, modules included (the default)
[default]
help:
    just --list --list-submodules
