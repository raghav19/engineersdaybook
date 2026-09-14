# Handoff: "Why MCP needed its own OWASP Top 10" primer post

## What this is

A standalone Medium companion post for the `engineersdaybook` `mcp-sandbox` series —
**not** part of the numbered Part-N sequence (Part 1: lethal-trifecta, Part 2:
agentgateway gateway architecture). It explains how MCP calls structurally differ from
traditional HTTP/API calls, and why that difference is *why* OWASP wrote a dedicated MCP
Top 10 instead of reusing existing API security guidance.

It was scoped and researched inside a long Part 2 grilling session, then **explicitly
deferred** by the user ("this should be part of a separate session ... lets keep the
current session focussed on part 2") before any spec or writing happened. Nothing has
been written yet — this handoff is scope + research only.

## Where the full detail lives — don't re-derive, read this first

**`/home/rana/.claude/projects/-home-rana-Projects-engineersdaybook/memory/mcp-vs-http-primer-post.md`**

That file (part of this user's persistent cross-session memory, auto-loaded via
`MEMORY.md` each session) contains everything settled so far:
- Placement decision (unnumbered, cross-linked from Part 2 only, Part 1 left untouched)
- Depth/audience decision (skip MCP 101, open with the trust-boundary shift, assume Part
  1 is most readers' entry point)
- Explicit scope boundary against Part 2's own OWASP coverage table (this primer
  introduces categories generically; it does not carry Part 2's architecture-specific
  covered/gap/non-fit verdicts)
- A full research report already landed and stashed in that file: the pinned OWASP API
  Security Top 10 (2023 edition, confirmed still current as of 2026-09-14), the
  MCP-vs-HTTP structural comparison sourced from the live MCP spec (including a
  significant July 2026 spec revision that removed the stateful session/handshake model
  in favor of per-request stateless negotiation — read this carefully, it invalidates a
  commonly-assumed "MCP has sessions, REST doesn't" framing), and the full MCP01–MCP10 vs.
  API Security Top 10 category-mapping table with honest analog-vs-novel judgments.

Read that memory file in full before doing anything else in the new session — this
handoff doc deliberately does not repeat its content.

## What's genuinely not decided yet

- Exact post outline/section structure (the research gives raw material, not a
  section-by-section plan)
- Title
- Whether it needs its own LinkedIn support posts (Part 2's LinkedIn plan — 3 staggered
  posts in plain "gatekeeper" language — was settled separately; this primer's social
  support wasn't discussed)
- Repository location / folder (Part 2 itself lives at
  `code/mcp-sandbox/part-2-mcp-gateway/` — this primer has no assigned home yet; it's
  unnumbered by design, so it may not want a `part-N-*` folder at all)
- Whether the July 2026 MCP spec revision changes anything about how Part 1 or Part 2
  should describe "sessions" in their own existing text (worth a quick cross-check, not
  a rewrite, per the memory file's note)

## Suggested skills for the next session

1. **`grilling`** (via the `Skill` tool) — settle the remaining open questions above
   (outline, title, LinkedIn scope, repo location) before writing anything. The memory
   file explicitly says "grill any remaining outline/structure questions fresh."
2. **`/to-spec`** — once outline/scope is settled, build the actual spec artifact,
   following the same convention Part 1 used (see
   `code/mcp-sandbox/part-1-lethal-trifecta/spec.md` for the shape).
3. **`/to-tickets`** — after the spec exists, ticket it the same way Part 1 was (issue
   #1 plus #2–#8 on `raghav19/engineersdaybook`), if this user wants tracker-based
   execution for this piece too.

## Notes

- No credentials, tokens, or secrets are involved in this piece of work — nothing to
  redact.
- The parent series context (Part 1's outcome, Part 2's architecture) is not repeated
  here; if the new session needs it, it's in `[[lethal-trifecta-poc]]` and
  `[[agentgateway-mcp-policy-model]]` in the same memory directory.
- Moved into this repo (`code/mcp-sandbox/handoff-mcp-vs-http-primer.md`) at the user's
  request on 2026-09-14, so it doesn't get lost with `/tmp`'s original location.
