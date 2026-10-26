# Agent skills

The skills in `.claude/skills/` are copies of upstream skills, committed here so that every environment (the host, sbx and msb) has the same skills. `skills-lock.json` in the repo root records the source of each one. Nobody edits them here.

```text
.claude/skills/<name>/         the skill (Claude Code reads this folder)
skills-lock.json               source, path and hash of each skill
docs/agents/skills-licenses/   the licence of each upstream repository
```

The [`skills` CLI](https://github.com/vercel-labs/skills) installs and updates them. The recipes in the root `justfile` run it with the right settings (a pinned version, Claude Code only, no telemetry). They need Node and network access.

| Task | Command |
|---|---|
| List the skills and their sources | `just skills-list` |
| Add a skill | `just skills-add <owner/repo> <skill>...` |
| Update all skills, or the ones you name | `just skills-update [<skill>...]` |
| Remove a skill | `just skills-remove <skill>...` |

## Update the skills

1. Make a branch.
2. Run `just skills-update`.
3. Read `git diff`. A skill changes how the agent works, and the upstream is not trusted. Do not run its scripts.
4. Commit the changes in `.claude/skills` and `skills-lock.json`, and open a pull request.

- A skill that you add with `owner/repo#<sha>` stays at that commit. `skills-update` skips it. To move it, run `just skills-add` again with a new commit.
- `npx skills check` also applies updates. Use `just skills-update` and read the diff.
- If an upstream changes its licence, copy the new file to `skills-licenses/`. The CLI does not copy licences.
- The prek hooks skip `.claude/skills/`: they must not rewrite the copies.
