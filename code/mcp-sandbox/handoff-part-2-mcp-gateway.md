# Handoff: Part 2 MCP Gateway spec — pending review before (re)posting

## What this is

A long grilling session produced a full spec for Part 2 of the `engineersdaybook`
`mcp-sandbox` blog series (Part 1: `part-1-lethal-trifecta`, published). Part 2 builds an
MCP gateway (agentgateway) architecture and demonstrates it against the same attack
pattern Part 1 used, plus three more mechanisms. The spec was written, published as a
GitHub issue, **then deleted** after the user spotted rendering problems, fixed, and is
now sitting on a branch awaiting the user's own review before being reposted.

## Where everything lives — don't re-derive, read these first

- **The spec itself**: `code/mcp-sandbox/part-2-mcp-gateway/spec.md`, on git branch
  `part-2-mcp-gateway-spec` (based off `main`, pushed to `origin`, not merged, no PR
  opened). This is the actual content — read it directly rather than asking the user to
  re-explain scope.
- **The architecture diagram**: `code/mcp-sandbox/part-2-mcp-gateway/assets/enterprise-architecture.excalidraw`
  — a real Excalidraw source file (9 boxes, colored by trust zone), generated via a
  script, not yet opened/reviewed by the user or exported to PNG.
- **Research already done**: `code/mcp-sandbox/part-2-mcp-gateway/research/mcp05-mcp08-gap-investigation.md`
  — primary-source investigation into whether agentgateway can mitigate OWASP MCP05
  (command injection) and provide MCP08 (audit/telemetry). Read before touching either
  topic again.
- **Full decision history**: project memory files (auto-loaded each session via
  `MEMORY.md` in `~/.claude/projects/-home-rana-Projects-engineersdaybook/memory/`) —
  `agentgateway-mcp-policy-model.md` is the primary one for Part 2 and has the fullest
  timeline (spec settled → published as issue #9 → deleted for quality issues → fixed).
  Also relevant: `lethal-trifecta-poc.md` (Part 1's full history), `istio-ambient-poc-parked.md`
  (corrected: rootless-vs-rootful is moot for this series' actual k3s-on-VM infra),
  `mcp-vs-http-primer-post.md` (a separate deferred deliverable, see below).
- **A separate deferred deliverable**: an unnumbered primer post ("why MCP needed its own
  OWASP Top 10") was explicitly scoped out of the Part 2 session and has its own handoff
  doc already sitting in the repo: `code/mcp-sandbox/handoff-mcp-vs-http-primer.md`. Not
  this session's job unless the user asks for it — it's a fully separate thread.

## Current state, precisely

- Part 2's spec content is **settled** — every architecture/scope decision (infra, identity
  chain, both MCP servers, all four demos, full OWASP mapping, diagram, write-up
  structure, LinkedIn plan) was grilled and confirmed. Nothing in the spec's substance is
  known to be in question.
- What's **not yet done**: the user has not yet finished reviewing the spec/diagram since
  the last fix. Two commits exist on the branch: the original spec+research, then a fix
  commit adding the real Excalidraw file and reflowing the spec's markdown (the original
  version had manually hard-wrapped ~80-column lines, which likely caused the "not using
  full width, looks truncated" complaint in whatever viewer the user was using — fixed by
  writing single-line paragraphs instead).
- **Not reposted to GitHub.** The user explicitly asked for the issue to be removed after
  spotting the rendering problem and said they'd review thoroughly before it goes back up
  — don't repost without the user actively asking for it this time.

## What a fresh session should do

1. If the user says something like "post it" or "repost the spec" — first check whether
   they've actually reviewed the current committed version (diagram export included, or
   at least the `.excalidraw` source), not just assume the prior fix is sufficient. If they
   haven't mentioned specific new changes, the repost mechanics are:
   `gh issue create --title "MCP Gateway Architecture (Part 2)" --body-file code/mcp-sandbox/part-2-mcp-gateway/spec.md --label "ready-for-agent"`
   (same pattern used before, in `raghav19/engineersdaybook`).
2. If the user wants changes to the spec/diagram, treat this as a normal edit — the spec
   file and diagram source are both plain text/JSON, editable directly.
3. Once posted, the natural next step (not yet requested) would be `/to-tickets` to break
   the spec into tracked issues, the same way Part 1 went from one spec issue to 7 child
   tickets (`raghav19/engineersdaybook#1`–`#8`).

## Suggested skills for the next session

- No skill is needed just to resume — read the spec and memory files above first.
- **`/to-tickets`** — once the user confirms the spec is ready and (re)posted, to break it
  into child tickets following Part 1's precedent.
- **`grilling`** (via the `Skill` tool) — only if the user raises a genuinely new,
  unsettled design question about Part 2 (unlikely at this point, but the pattern this
  whole effort has followed is grill-first).
- Do **not** invoke `to-spec` again for Part 2 — the spec already exists; re-running it
  would duplicate work. `to-spec` would apply to the separate primer post instead, per its
  own handoff doc.

## Notes

- No credentials, tokens, or secrets are involved in any of this — nothing to redact.
- Moved into this repo (`code/mcp-sandbox/handoff-part-2-mcp-gateway.md`) at the user's
  request on 2026-09-16, same reasoning as the primer's handoff doc — so it doesn't get
  lost with `/tmp`'s original location.
- This repo's convention (from `AGENTS.md`): reference secrets by name, never paste raw
  values; credential-creation steps (PATs, OAuth Apps, cloud provisioning) are manual,
  human-only steps the agent never touches — expect the same `/wizard`-shaped split Part 1
  used once Part 2 moves from spec to actual build.
