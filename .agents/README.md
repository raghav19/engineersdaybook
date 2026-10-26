# Agent skills

The skills in `skills/` are copies of upstream skills, committed here so that every environment (the host, sbx and msb) has the same skills. `skills-lock.json` in the repo root records the source of each one. Nobody edits them here.

```text
.agents/skills/<name>/    the skill (Codex reads this folder)
.claude/skills/<name>     a link to it (Claude Code reads this folder)
skills-lock.json          source, path and hash of each skill
.agents/licenses/         the licence of each upstream repository
```

The [`skills` CLI](https://github.com/vercel-labs/skills) installs and updates them. `just skills` runs it with the right settings (a pinned version, both agents, no telemetry). It needs Node and network access.

| Task | Command |
|---|---|
| List the skills and their sources | `just skills list` |
| Add a skill | `just skills add <owner/repo> <skill>...` |
| Update all skills, or the ones you name | `just skills update [<skill>...]` |
| Remove a skill | `just skills remove <skill>...` |

## Update the skills

1. Make a branch.
2. Run `just skills update`.
3. Read `git diff`. A skill changes how the agent works, and the upstream is not trusted. Do not run its scripts.
4. Commit the changes in `.agents/skills`, `.claude/skills` and `skills-lock.json`, and open a pull request.

- A skill that you add with `owner/repo#<sha>` stays at that commit. `update` skips it. To move it, run `just skills add` again with a new commit.
- `npx skills check` also applies updates. Use `just skills update` and read the diff.
- If an upstream changes its licence, copy the new file to `licenses/`. The CLI does not copy licences.
- The prek hooks skip `.agents/skills/`: they must not rewrite the copies.
