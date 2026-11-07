# Agent workload identity

Each agent microVM gets its own SPIFFE ID. The private key stays on the host, outside the VM. Google Agent Compute Engine uses the term "Agent Workload Identity" for the same idea.

## The idea

- The microVM is the workload. It never holds its key.
- A SPIRE agent on the host checks properties of the VM. It does not check a forwarder program.
- A delegate on the host holds the SVID and the key for the VM.
- The gateway reads the SPIFFE ID and checks the node, the user and the VM.

The ID has three parts: `spiffe://mcp.local/node/<host-name>/user/<user>/vm/<vm-name>`. The node is the host, and not a VM.

## Status

The `msbvm` plugin and the delegate are in this repo, with unit tests. The host agent config, the registration entries and the end-to-end test are not. The spike proved the flow on the host with a throwaway SPIRE server. The ADR records the decision.

## How to start

Read the docs in this order. Then run the tests of each part, as the README of the part says.

1. [`CONTEXT.md`](CONTEXT.md) defines the terms.
2. [Workload attestation of the microVM](docs/workload-attestation.md) explains the model, the parts and the flow.
3. [ADR 0001](docs/adr/0001-delegated-identity-for-the-microvm.md) records the decision, the rejected options and the open questions.
4. The [research note](../../docs/research/microvm-workload-attestation-spire.md) has the evidence. Read the section "Spike results".
5. The [spike handoff](../mcp-sandbox/part-3-mcp-guardrails/docs/handoff/microvm-attestation-spike.md) has the plan in PRs and the spike code.

## What stays in part 3

[Part 3: MCP guardrails](../mcp-sandbox/part-3-mcp-guardrails/README.md) owns the cluster side. That is the SPIRE server, the node CA, the node certificate, the node entry and the gateway rule. The [node attestation guide](../mcp-sandbox/part-3-mcp-guardrails/docs/node-attestation.md) explains the first link, the attestation of the node.

## Where the parts are

- [`plugin/`](plugin/README.md): the `msbvm` workload attestor, in Go.
- [`delegate/`](delegate/README.md): the delegate, in Go.
- `agent/` (not yet): the config of the host SPIRE agent.
- `tests/` (not yet): the end-to-end check.
