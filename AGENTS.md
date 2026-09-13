# Agents

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues on `raghav19/engineersdaybook`, via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Default five canonical roles, label strings equal to their names (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Per-project, not root-level: each `code/<project>/` is an independent project with its own `CONTEXT.md` and `docs/adr/`. See `docs/agents/domain.md`.

## Secrets
- Reference secrets by name (env var, e.g. $GH_TOKEN), never by literal value.
- Never echo, cat, print, or paste a secret's raw value into output or context —
  including config files, .env, or CLI auth files that may contain one.
- Auth is set up outside the session (`gh auth login`, etc.) before work starts;
  the agent calls tools (`gh`, `git`) that use stored credentials implicitly.
- If a command's output contains a credential, redact it before showing it
  (write `<REDACTED>` in place of the value).
- If a secret is genuinely missing, stop and ask — don't request the value be
  pasted into chat.
