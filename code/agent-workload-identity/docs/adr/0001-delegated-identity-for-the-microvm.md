---
status: accepted
---

# The microVM gets its SPIFFE ID through the Delegated Identity API

The microVM is the workload. Its SPIFFE ID must come from facts about the VM, and its key must stay outside the VM. SPIRE 1.15.5 has no workload attestor for a VM. So a delegate on the host sends the pid of the VMM to the host SPIRE agent. A custom attestor `msbvm` turns the pid into the VM name and the sandbox ID.

## Decision

- One SPIRE agent runs on the host, and not in the VM. It attests as a node with `x509pop`.
- The delegate connects to the admin socket of the agent. The agent checks the delegate and the list `authorized_delegates`.
- The delegate sends the pid of the VMM and nothing else. The pid is an input and not a selector, because it changes at each start.
- The agent runs its workload attestors on the pid. `unix` gives the uid. `msbvm` gives the VM name and the sandbox ID.
- The entry of the VM has the selectors `msbvm:name:<vm>` and `unix:uid:<uid>`. Its parent is the node entry.
- The agent returns the SVID and the key to the delegate. The VM never sees them.
- `msbvm` checks that the exe of the process is `msb`. Then it reads the name and the ID of the VM from the `run` row in `msb.db` that has this pid and the status Running.

## Considered options

- **Systemd unit for each VM.** The selector would be `systemd:id:<unit>`. The VMM has no unit of its own. The system D-Bus returns `user@1000.service` for its pid. This needs a change in how `msb` starts the VMM.
- **One SPIRE agent for each VM.** This costs one agent, one node entry and one credential for each VM. If the guest reaches the agent socket, the guest holds the key.
- **Delegated Identity API with selectors only.** The agent makes no check. The delegate alone says which VM it is.
- **SPIFFE Broker API with a vendor reference.** This matches "the agent checks the VM" best. The API is experimental in 1.15.5, and no one tested it with a custom reference type.

## Consequences

- The plugin must be in Go, because the SPIRE plugin SDK is Go only.
- The plugin depends on the tables `run` and `sandbox` of msb 0.7.13. They are internal and can change. Pin the msb version.
- A refusal is an empty response with zero SVIDs. The delegate must treat zero SVIDs as a failure.
- The delegate checks that the SVID has the ID that it expected. A recycled pid then gives zero SVIDs or an SVID with another ID, and the delegate fails. The SPIRE docs say that the delegate must make sure that the pid is not recycled between the request and the answer. A `pidfd` in the delegate is a later hardening.
- The API does not limit a delegate to certain VMs. An attacker who controls a delegate can get the SVID of any VM that the agent can attest. On a host with many users, use one agent for each user.
- The delegate must run on the same host as the agent, because the API uses a local Unix socket.
- This decision replaces the design of PR #260 and `docs/zero-trust-workload-attestation.md` (Envoy in the VM).

## Not decided here

- The language of the delegate, and how it finds the pid of the VMM.
- The node certificate of the host agent, and the fate of the agent in the VM.
- What starts the delegate.
- Whether the delegate needs its own SVID.

The evidence is in the section "Spike results" of [`docs/research/microvm-workload-attestation-spire.md`](../../../../docs/research/microvm-workload-attestation-spire.md). The handoff is [`microvm-attestation-spike.md`](../../../mcp-sandbox/part-3-mcp-guardrails/docs/handoff/microvm-attestation-spike.md).
