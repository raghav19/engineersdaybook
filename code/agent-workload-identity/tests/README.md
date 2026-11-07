# End-to-end test

This test checks that the [`msbvm` plugin](../plugin/README.md) and the [delegate](../delegate/README.md) work together with a real SPIRE agent. It rebuilds the spike of the [handoff](../../mcp-sandbox/part-3-mcp-guardrails/docs/handoff/microvm-attestation-spike.md) as a test that you can repeat.

## What it proves

The test starts a throwaway SPIRE server and a throwaway SPIRE agent on this host. It uses the real VM `sandbox-dev` and the real `msb.db`. It runs seven cases. Each case prints `PASS` or `FAIL` with a short reason.

| Case | What it checks |
|---|---|
| E1 | The delegate finds the real VMM in `/proc`. The agent and the plugin check the pid against `msb.db`. The delegate prints the ID of the VM entry as `spiffe_id=`. It never prints the key. |
| E2 | A second call returns the same SPIFFE ID. |
| E3 | The pid of a plain `sleep` process gets zero SVIDs. |
| E4 | A fake `msb` gets zero SVIDs. It has the exe name and the command line of the real VMM, but `msb.db` has no `run` row for its pid. |
| E5 | The agent denies a copy of the delegate at another path. It answers `PermissionDenied`, and the delegate exits with a non-zero code. |
| E6 | The delegate refuses a VM name that has no VMM. It exits with a non-zero code before it calls the agent. |
| E7 | The agent returns the SVID of the VM, but the delegate expects another ID. The delegate exits with a non-zero code. The error names both IDs. Only the delegate can make this check, because the agent does not know which VM it meant. |

The script exits with a non-zero code if one case fails.

## Run it

```text
cd code/agent-workload-identity/tests
just e2e
```

You can also run `./e2e.sh` directly. The test needs these things:

- Go and [`just`](https://just.systems).
- `gh`, logged in. It downloads SPIRE 1.15.5 at the first run.
- Network access for the first run only. The next runs use the cache.
- A running VM `sandbox-dev` that `msb` started. The test never starts, stops or changes it. It only reads the pid and `msb.db`.

## What the script does

1. It downloads `spire-1.15.5-linux-amd64-musl.tar.gz` and its checksum file to `~/.cache/agent-workload-identity/spire-1.15.5/`. It checks the archive with `sha256sum -c` and unpacks it there. It skips these steps if the checked files exist.
2. It builds the plugin, the delegate, the Go test binary and the fake `msb` into a temp folder. The folder is under `$XDG_RUNTIME_DIR`. The script never commits a binary.
3. It starts a SPIRE server on `127.0.0.1:18081` with the trust domain `mcp.local`. It never calls the cluster or the live SPIRE server.
4. It makes a join token for `spiffe://mcp.local/test/agent` and keeps it in a file with mode 600. It never prints the token.
5. It creates the delegate entry and the VM entry. They have the same IDs and selectors as the cluster manifests. Only the parent is different.
6. It starts a SPIRE agent with the join token and the `msbvm` plugin. The admin socket is in another folder than the Workload API socket.
7. It runs the cases.
8. A `trap` stops the server, the agent and the test processes by their saved pids. It removes the temp folders.

## Details to know

- **The fake `msb` stops after E4.** The delegate scans `/proc` by VM name. With two VMMs of one VM, it refuses to choose. So the script stops the fake `msb` before the next cases.
- **A third entry.** E3 and E4 use a Go test, because the delegate cannot send an arbitrary pid. The Go test is a binary at its own path. The agent would deny it, and then E3 and E4 could pass for the wrong reason. So the script adds one more entry. It has the ID of the delegate and the path of the Go test binary. The cluster has no such entry. The test of E3 and E4 only passes on the answer "zero SVIDs". A `PermissionDenied` answer fails it.
- **The wait at the start.** The agent opens its sockets before it has the entries of its node. In this time it answers every caller with `PermissionDenied: no identity issued`. The script calls the delegate until the agent answers. This takes about 5 seconds.
- **The checksum.** The script computes the checksum of the plugin binary at run time. The agent config gets this value.

## What it does not prove

- The `x509pop` attestation of the host agent against the cluster server. The test agent uses a join token.
- Two VMs at the same time.
- A stop and start of the VM. The test does not stop `sandbox-dev`.
- The use of the SVID in mTLS.
- The gateway.
- That the cluster entries work. The test uses the same IDs and selectors, but it does not read the manifests.
- The exe check of the plugin against a stale `Running` row. The test cannot make `msb` leave such a row.
- The SVID of the delegate itself, and a delegate that runs for a long time.
