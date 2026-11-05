# Handoff documents

A handoff document lets a fresh session continue a piece of work without the old conversation. This file is the index. Newest first.

## How to add one

1. Write the document in the `docs/handoff/` folder of the project that owns the work.
2. Add one entry to the top of the list below. Give the date, the title, the path and the status.
3. In the document, link the specs, PRs and files. Do not copy them.
4. Leave out secrets and personal data.

## The list

- **2026-11-05. Ephemeral environments: status after the platform PRs.** The merged PRs (#242, #248, #249, #250 and #255), the user's decisions, the next steps, the open decisions and the traps in the sandbox VM. Nothing ran on a cluster yet.
  Path: [`code/ephemeral-env/docs/handoff/ephemeral-env-status.md`](../code/ephemeral-env/docs/handoff/ephemeral-env-status.md). Status: active. The design entry below holds the details of the next steps.
- **2026-11-05. Node attestation of the msb sandbox microVM.** The microVM attests to the SPIRE server on k3s with `x509pop`. The guide and the diagram are on `main`. Open: the second attestation, the failing `github-upstream` ExternalSecret and the workload entry.
  Path: [`code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/node-attestation.md`](../code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/node-attestation.md). Status: active.
- **2026-11-05. Ephemeral environments with Istio, Gateway API and Flux ResourceSet.** Research and design of one baseline and sandboxes for the changed services.
  Path: `code/ephemeral-env/docs/handoff/ephemeral-env-design.md`. Status: on the branch `docs/handoff-ephemeral-env`, not on `main`.
- **2026-11-04. Backstage learning path.**
  Path: `code/platform-engineering/docs/handoff/backstage-learning-path.md`. Status: on the branch `docs/handoff-backstage`, not on `main`.
- **2026-10-29. SPIRE node attestation of the msb sandbox with `sshpop`.**
  Path: `docs/research/msb-spire-sshpop-handoff.md`. Status: on the branch `msb-spire-sshpop-handoff`, not on `main`. The first entry above replaces it. The work moved to `x509pop`.
