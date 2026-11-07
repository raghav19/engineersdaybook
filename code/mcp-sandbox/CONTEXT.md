# MCP sandbox

A series about an AI agent that calls MCP tools from a sandbox. Part 3 puts guardrails on a gateway. The gateway decides from the identity of the caller.

## Language

**Node**:
The host that runs the microVM. The SPIRE server knows it through its node certificate.
_Avoid_: machine, box

**Node entry**:
A registration entry that gives an attested node a fixed SPIFFE ID, for example `spiffe://mcp.local/node/sandbox-dev`. It is a record in the SPIRE server and is in no certificate.
_Avoid_: alias

**microVM**:
The virtual machine that `msb` runs for the agent. It is the workload that gets a SPIFFE ID.
_Avoid_: sandbox VM, guest

**VMM**:
The host process that runs one microVM. In `msb` it is the `msb machine` process.
_Avoid_: hypervisor process

**Delegate**:
A host program that the SPIRE agent trusts to ask for the SVID of a microVM. The SVID and its key stay with the delegate.
_Avoid_: proxy, forwarder, launcher

**microVM identity**:
The SPIFFE ID of one microVM. It names the node, the user and the VM: `spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/<vm-name>`.
_Avoid_: VM ID (the sandbox ID of `msb` is a different value)
