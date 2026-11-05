# Guides on one part of a system

A guide on one part of a system builds a correct picture of that part in the head of the reader. The reader finishes it and can explain the flow to another person.

## Scope

This structure is for a guide that documents the details of one part. Examples: the node attestation of a VM, the rendered manifest pattern, the orchestration of Flux.

A main README keeps its own shape. It says what the project is and how to start, and it links to the guides.

## Structure

Write the sections in this order. Skip a section only if the system has nothing to put in it.

1. **Title.** Name the subject, for example `Node attestation of the microVM`.
2. **The idea.** Give the problem and the model in 3 to 5 short points. Write them before any name of a part.
3. **The picture.** Add the diagram of the system. Follow `docs/agents/diagrams.md`.
4. **The cast.** Name each part once. Give its job in one line. Group the parts by where they run (cluster, host, VM).
5. **The flow in phases.** Split the flow by time: the prerequisites (once), each run, and while the system runs. Draw each phase in mermaid. Use `flowchart` for a setup and `sequenceDiagram` for a run. Add 2 or 3 sentences below each diagram.
6. **Lifetimes.** List what lives how long (certificates, tokens, caches) and what renews it.
7. **Why the design looks like this.** Give one line per choice, with its reason.
8. **The names.** Define each name of the domain once. Example: the trust domain `mcp.local`.
9. **Where each part is in the repo.** Link the file of each part.
10. **What comes next.** Link the next doc to read.

## Style

- Use short lists. A table has at most 2 columns.
- Keep each mermaid diagram to 7 participants or fewer, so that it fits on a phone screen.
- Take every fact from a repo file or from a command that you ran.
- Put verdicts, evidence tags, gaps and open items in a research note in `docs/research/`.
- Check each mermaid block with a parser before you commit.
