# Delegate

The delegate asks the host SPIRE agent for the SVID of one microVM. It uses the Delegated Identity API on the admin socket of the agent.

Read [ADR 0001](../docs/adr/0001-delegated-identity-for-the-microvm.md) for the decision. Read [Workload attestation](../docs/workload-attestation.md) for the flow.

## What it does

The command runs these steps once:

1. It reads the `run` row with status `Running` of the VM in `msb.db`. It opens the file read-only. It fails if there is no such row.
2. It opens a pidfd for the pid.
3. It checks that `/proc/<pid>/cmdline` has `--name <vm>`. Then it checks through the pidfd that the process has not exited. The pid can be reused between step 1 and step 2. If the process has not exited after the read, the command line belongs to the process of the pidfd. The command line check is only a sanity check. The plugin `msbvm` does the full check.
4. It calls `SubscribeToX509SVIDs` with the pid and reads the first response.
5. It checks the pidfd again. The SPIRE docs say that the pid must not be recycled between the request and the answer. If the process exited during the call, it fails and returns no SVID.
6. It picks the SVID whose ID equals `-id`. The agent returns the SVIDs of all entries that match the process, so the command never takes the first one. If no SVID has this ID, it fails and names the expected ID and the IDs that it got.
7. It prints the SPIFFE ID, `not_after` and the URI SAN. It exits with code 0.

The command fails in these cases. It prints a short message on stderr and exits with code 1:

- No running row, or a wrong command line.
- The process exited, before or during the call.
- The agent returns zero SVIDs. This is the refusal of the agent. The code returns the error `ErrRefused` for it.
- No SVID has the expected ID. The code returns the error `ErrIDMismatch` for it.
- The agent returns `PermissionDenied` or any other gRPC error.
- The certificate or the key does not parse.

The command never prints, logs or writes the private key. The type `SVID` also hides the key when you format it.

## Flags

| Flag | Meaning |
|---|---|
| `-vm` | Name of the microVM. Required. |
| `-id` | The SPIFFE ID that the SVID of the VM must have. Required. |
| `-socket` | Path of the admin socket of the host SPIRE agent. Required. |
| `-db` | Path of `msb.db`. Default: `~/.microsandbox/db/msb.db`. |

Example output:

```text
spiffe_id=spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/sandbox-dev
not_after=2026-11-07T12:00:00Z
uri_san=spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/sandbox-dev
```

## Build and run

```text
cd code/agent-workload-identity/delegate
go build -o delegate ./cmd/delegate
./delegate -vm sandbox-dev -id spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/sandbox-dev -socket <admin-socket>
```

## Tests

```text
go test ./...
```

The tests use no real SPIRE agent. They start a fake `DelegatedIdentity` server on a Unix socket in a temporary folder. They build a fake `msb.db` with the tables `sandbox` and `run`. They start `sh` processes whose command line has `--name <vm>`, to act as a VMM.

## Layout

- `cmd/delegate`: the flags and the output.
- `internal/vmm`: finds the pid of the VMM and checks its command line.
- `internal/pidfd`: holds the pidfd.
- `internal/agent`: calls the agent and parses the SVID.
- `internal/delegate`: runs the steps in order.
- `internal/testutil`: the fakes of the tests.

## Out of scope

Later PRs do these parts:

- The own SVID of the delegate.
- The long-lived stream and the renewal of the SVID. The command takes the first response and ends.
- The start of the delegate from `just msb run`.
- Any use of the SVID in mTLS.
