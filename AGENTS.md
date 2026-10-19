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

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.
