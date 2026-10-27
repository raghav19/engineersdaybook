# The sandbox tooling lives in .msb/ (microsandbox). `mod` makes it `just msb <recipe>` from anywhere in the repo. `just msb` lists its recipes.
# Part 3 has its own justfiles under code/mcp-sandbox/part-3-mcp-guardrails/; they do not fall back to this one.
#
#   just msb run            developer: create or start the sandbox and open VS Code on it. See .msb/README.md

set quiet

mod msb '.msb'

# list the recipes, modules included (the default)
[default]
help:
    just --list --list-submodules

# The agent skills in .claude/skills. The `skills` CLI (vercel-labs/skills) installs them and records them in skills-lock.json. See docs/agents/skills.md
# The CLI is third-party code from npm, so the version is pinned here. No telemetry. It needs Node (npx).
skills_cli := 'DISABLE_TELEMETRY=1 DO_NOT_TRACK=1 npx -y skills@1.7.4'

# list the installed skills and where each one comes from
skills-list:
    {{ skills_cli }} list

# install skills from a GitHub repository: `just skills-add fluxcd/agent-skills gitops-knowledge`. Pin a commit with `owner/repo#<sha>` (skills-update keeps it)
[script('bash')]
skills-add repo +skills:
    set -euo pipefail
    args=()
    for s in {{ skills }}; do args+=(--skill "$s"); done
    {{ skills_cli }} add '{{ repo }}' "${args[@]}" -a claude-code -y

# move the installed skills (or the ones you name) to the newest upstream version. Read the diff before you commit: a skill changes how the agent works
skills-update *skills:
    {{ skills_cli }} update -p -y {{ skills }}

# remove skills
skills-remove +skills:
    {{ skills_cli }} remove {{ skills }} -y
