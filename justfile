# The sandbox tooling lives in .sbx/. `mod` makes it `just sandbox <recipe>` from anywhere in the repo (it replaces the Taskfile's `sandbox:` prefix).
# Part 3 has its own justfiles under code/mcp-sandbox/part-3-mcp-guardrails/; they do not fall back to this one.
#
#   just sandbox            list the sandbox recipes: `host` (services on the host machine) and `agent` (what the VM receives), with the step of each
#   just sandbox run        developer: create or start the sandbox and open VS Code on it

set quiet

# The agent skills in .agents/skills: `just skills add`, `just skills update`. See .agents/README.md
mod skills '.agents'

mod sandbox '.sbx'

# list the recipes, modules included (the default)
[default]
help:
    just --list --list-submodules
