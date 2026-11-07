# Handoff documents

A handoff document lets a fresh session continue a piece of work without the old conversation. This file is the index. Newest first.

## How to add one

1. Write the document in the `docs/handoff/` folder of the project that owns the work.
2. Add one entry to the top of the list below. Give the date, the title, the path and the status.
3. In the document, link the specs, PRs and files. Do not copy them.
4. Leave out secrets and personal data.

## The list

- **2026-11-07. Delegated identity for the msb microVM (spike done).** The spike proved the flow on the host. A proxy sends the pid of the VMM to the agent. A custom plugin turns the pid into the VM name and ID. The document has the design, the results, the plan in six PRs and the open decisions.
  Path: [`code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/microvm-attestation-spike.md`](../code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/microvm-attestation-spike.md). The spike code is in the same document. It continues the entry below. Status: active.
- **2026-11-06. SPIFFE identity of the msb microVM (workload attestation).** Each microVM gets its own SPIFFE ID, and the SPIRE agent on the host checks VM properties. Start on the host: find what `msb inspect` records, then test how it reaches the Workload API.
  Path: [`code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/microvm-workload-attestation.md`](../code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/microvm-workload-attestation.md). Research: [`docs/research/microvm-workload-attestation-spire.md`](research/microvm-workload-attestation-spire.md). Status: active.
- **2026-11-05. Node attestation of the msb sandbox microVM.** The microVM attests to the SPIRE server on k3s with `x509pop`. The guide and the diagram are on `main`. Open: the second attestation, the failing `github-upstream` ExternalSecret and the workload entry.
  Path: [`code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/node-attestation.md`](../code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/node-attestation.md). Status: active.
- **2026-11-05. Ephemeral environments with Istio, Gateway API and Flux ResourceSet.** Research and design of one baseline and sandboxes for the changed services.
  Path: `code/ephemeral-env/docs/handoff/ephemeral-env-design.md`. Status: on the branch `docs/handoff-ephemeral-env`, not on `main`.
- **2026-11-04. Backstage learning path.**
  Path: `code/platform-engineering/docs/handoff/backstage-learning-path.md`. Status: on the branch `docs/handoff-backstage`, not on `main`.
- **2026-10-29. SPIRE node attestation of the msb sandbox with `sshpop`.**
  Path: `docs/research/msb-spire-sshpop-handoff.md`. Status: on the branch `msb-spire-sshpop-handoff`, not on `main`. The first entry above replaces it. The work moved to `x509pop`.
