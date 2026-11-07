# Delegate

The delegate asks the host SPIRE agent for the SVID of one microVM. It uses the Delegated Identity API on the admin socket of the agent.

Read [ADR 0001](../docs/adr/0001-delegated-identity-for-the-microvm.md) for the decision. Read [Workload attestation](../docs/workload-attestation.md) for the flow.

## What it does

The delegate only guesses the pid and checks the answer. The plugin `msbvm` in the agent verifies the pid against `msb.db`. A wrong pid gets zero SVIDs.

The command runs these steps once:

1. It scans `/proc` for the process `msb machine --name <vm>`. It fails if there is none, or if there is more than one.
2. It sends the pid to the agent with `SubscribeToX509SVIDs` on `admin.sock`. It reads the first answer.
3. The agent answers with the SVIDs of all entries that match the process. The delegate picks the SVID whose ID equals `-id`. It never takes the first one. The agent does not know which VM the delegate meant, so only the delegate can do this check.
4. It prints the SPIFFE ID and `not_after`. It exits with code 0. The SVID and its key stay in memory until the command ends.

The command prints a short message on stderr and exits with code 1 in these cases:

- No VMM, or more than one VMM, of the VM.
- The agent returns zero SVIDs. This is the refusal of the agent. The error is `errRefused`.
- No SVID has the expected ID. The message names the expected ID and the IDs that it got. The error is `errIDMismatch`.
- The agent returns `PermissionDenied` or any other gRPC error.

The command never prints, logs or writes the private key. The type `svid` also hides the key when you format it.

## Flags

| Flag | Meaning |
|---|---|
| `-vm` | Name of the microVM. Required. |
| `-id` | The SPIFFE ID that the SVID of the VM must have. Required. |
| `-socket` | Path of the admin socket of the host SPIRE agent. Required. |

Example output:

```text
spiffe_id=spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/sandbox-dev
not_after=2026-11-07T12:00:00Z
```

## Build and run

```text
cd code/agent-workload-identity/delegate
go build -o delegate .
./delegate -vm sandbox-dev -id spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/sandbox-dev -socket <admin-socket>
```

## Tests

```text
go test ./...
```

The tests use no real SPIRE agent. They start a fake `DelegatedIdentity` server on a Unix socket in a temporary folder. They write a fake `/proc` in a temporary folder.

## Files

- `main.go`: the flags and the output.
- `vmm.go`: finds the pid of the VMM.
- `agent.go`: calls the agent and picks the SVID.

## Out of scope

Later PRs do these parts:

- The own SVID of the delegate.
- The long-lived stream, the renewal of the SVID, and a retry while the agent loads its entries.
- A check with a `pidfd` that the VMM has not exited. The SPIRE docs say that the pid must not be recycled between the request and the answer. The check of the returned ID covers the risk of a wrong VM today.
- The start of the delegate from `just msb run`.
- Any use of the SVID in mTLS.
