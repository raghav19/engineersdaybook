# Agents

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

## 5. Secrets

**Never commit secrets to the repository. Reference secrets by name, never by literal value.**

- Reference secrets by name (env var, e.g. $GH_TOKEN), never by literal value.
- Never echo, cat, print, or paste a secret's raw value into output or context — including config files, .env, or CLI auth files that may contain one.
- Auth is set up outside the session (`gh auth login`, etc.) before work starts; the agent calls tools (`gh`, `git`) that use stored credentials implicitly.
- If a command's output contains a credential, redact it before showing it (write `<REDACTED>` in place of the value).
- If a secret is genuinely missing, stop and ask — don't request the value be pasted into chat.

## 6. Agent skills

### Issue tracker

Issues and specs live as GitHub issues on `raghav19/engineersdaybook`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

You are inside the dev-agent-sandbox microVM (started by `just sandbox run`) when `$SANDBOX_NAME` is set. There, every read or write on GitHub (issues, PRs, comments, labels, file contents) goes through the GitHub tools on the sbx MCP gateway (`mcp__mcp-gateway__*`), never through `gh` or direct API calls such as `curl`. That includes a quick read like `gh pr view`. The gateway tools are deferred: load their schemas with ToolSearch first, then call them directly. `docs/agents/issue-tracker.md` maps each `gh` command to its tool. Plain `git` (commit, push, fetch) stays in Bash. Outside the sandbox (`$SANDBOX_NAME` unset), use `gh` as described.

### Triage labels

Default five canonical roles, label strings equal to their names (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Per-project, not root-level: each `code/<project>/` is an independent project with its own `CONTEXT.md` and `docs/adr/`. See `docs/agents/domain.md`.

### Kubernetes and Flux schemas

Before you write or edit a Kubernetes, Flux, Gateway API or other CRD manifest, look up the real kind and fields on the gateway's flux-schema-catalog (`mcp__mcp-gateway__*`). Use `grep_catalog` to find the apiVersion and kind, `grep_schema` for field names, types and required values, and `get_schema` only when you need the full schema. Do not write fields from memory. If the gateway is not available, say so before you edit.

## 7. Host handoff

You run in a **clone** of this repo (`/run/sandbox/source` exists). Your edits and commits are invisible to the host until you push them.

- Before you ask the user to run any command on the host that depends on your changes, commit them and `git push` to a feature branch. Never push to `main`.
- In the same message, name the branch and the exact commit (`git rev-parse --short HEAD`). Give the host command with the checkout, e.g. `git fetch origin && git checkout <branch> && just <target>`.
- If the push fails, say so and stop. Do not ask the user to run a host command against unpushed changes.
- Host-only commands that need no repo changes (`sbx policy ...`, `sbx secret ...`, `sbx ports ...`) need no push.

## 7a. Pull requests

In the sandbox, open a PR with the gateway tool `create_pull_request`. Never use `gh pr create` or `curl`. Do these steps in this order. If a step fails, stop and report the exact error text. Do not go on to the next step.

1. Git identity. Run `git config user.name` and `git config user.email`. If either prints nothing, call `get_me`. Then run `git config user.name "<name>"` and `git config user.email "<email>"`. If `email` is null, use `<id>+<login>@users.noreply.github.com`. Never use `--global`. Never invent a value.
2. GitHub identity. Call `get_me`. If it returns an error, or `login` is not `raghav19`, stop. Tell the user that the gateway has no GitHub authorization. Do not try `gh auth login`.
3. Branch. `git branch --show-current` must not print `main`. If it does, run `git checkout -b <branch>` before you commit.
4. Push. Run `git push -u origin <branch>`. Then run `git ls-remote origin refs/heads/<branch>`. The hash must equal `git rev-parse HEAD`. A PR for an unpushed branch always fails.
5. Duplicate check. Call `list_pull_requests` with `owner: raghav19`, `repo: engineersdaybook`, `head: raghav19:<branch>`, `state: open`. If a PR exists, call `update_pull_request` on it. Do not create a second PR.
6. Create. Call `create_pull_request` with `owner: raghav19`, `repo: engineersdaybook`, `head: <branch>` (the branch name only, no `raghav19:` prefix), `base: main`, `title`, and `body`. Write the body with the `pr` skill.
7. Report. Give the `html_url` that the tool returned. If the call returned no URL, the PR does not exist.

## 8. Diagrams

- Save `<name>.drawio`, `.svg` and `.png` (2x, white background) in `docs/diagrams/`. Add each to its README table.
- Show only what the user named. Add no legend, caption or before-and-after pair unless asked.
- Match the style of the newest `.drawio`. Make boxes `rounded=1` and arrows `curved=1`.
- Start each arrow of a fan at a different point on its source box. Leave 80 px between joined rows.
- Take every fact from a repo file. Before you report, check that the XML parses and read every label in the PNG.

## 9. Python

- Give every parameter and every return value a type hint. ruff rule `ANN` reports a missing hint. ty reports a wrong hint.
- Before you finish, run `ruff check`, `ruff format --check` and `ty check` on each Python file you changed. Fix every finding.
- Do not add `# noqa` or `# type: ignore` without a reason in the same comment.
- A script is a Python file that a recipe or a person runs. Start it with `#!/usr/bin/env -S uv run --script` and a PEP 723 block (`requires-python` and `dependencies`). Pin each dependency to an exact version.
- A tool is a build function in `tools/`. Build it as one PyInstaller binary with the `build` recipe of `tools/tools.just`. Copy the `pyproject.toml` of a sibling tool. Do not write other PyInstaller flags.
- To make a binary smaller, add `--exclude-module` to `flags` in `tools/tools.just`. Measure the size before and after.
- A service that runs in a container (`platform/ext-mcp`) is not a script and not a tool. Keep its Dockerfile.
- The reasons for each pin are in `docs/research/typer-ty-tools.md`.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
