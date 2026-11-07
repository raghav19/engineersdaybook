# Agent workload identity

How an agent microVM gets its own SPIFFE ID while its private key stays on the host. The name follows the term "Agent Workload Identity" of Google Agent Compute Engine.

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

**Agent workload identity**:
The SPIFFE ID of one agent microVM. It names the node, the user and the VM: `spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/<vm-name>`.
_Avoid_: microVM identity, agent identity (Google uses it for a different identity), VM ID (the sandbox ID of `msb` is a different value)
