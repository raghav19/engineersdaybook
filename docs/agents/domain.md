# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`code/<project>/CONTEXT.md`**, for whichever project under `code/` you're working in.
- **`code/<project>/docs/adr/`**: read ADRs scoped to that project that touch the area you're about to work in.

There is no root-level `CONTEXT.md` or `CONTEXT-MAP.md` in this repo, and none is expected: each folder under `code/` is an independent project with no shared domain across them. Don't look for, or suggest creating, root-level domain docs.

If a project's `CONTEXT.md` or `docs/adr/` don't exist yet, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill creates them lazily when terms or decisions actually get resolved.

## File structure

    /
    └── code/
        ├── mcp-sandbox/
        │   ├── CONTEXT.md
        │   ├── docs/adr/
        │   └── part-1-lethal-trifecta/   ← sub-effort inside the mcp-sandbox project; its decisions land in the parent's docs/adr/
        ├── rootless-docker/
        │   ├── CONTEXT.md
        │   └── docs/adr/
        └── <other-project>/
            ├── CONTEXT.md
            └── docs/adr/

## Use the glossary's vocabulary

When your output names a domain concept, use the term as defined in that project's `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids. If the concept isn't in the glossary yet, that's a signal: either you're inventing language the project doesn't use, or there's a real gap worth noting for `/domain-modeling`.

## Flag ADR conflicts

If your output contradicts an existing ADR in that project's `docs/adr/`, surface it explicitly rather than silently overriding.
