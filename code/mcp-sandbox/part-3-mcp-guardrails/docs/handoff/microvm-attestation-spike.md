# Handoff: delegated identity for the msb microVM (spike done)

Written on 2026-11-07. The index of all handoff documents is `docs/handoff.md` at the root of the repo.

This handoff continues `microvm-workload-attestation.md` in the same folder. The spike on the host answered its open questions. A fresh session can read this document and start the PRs.

**Where this document and an older record disagree, this document wins.** The old handoff lists Route A (a systemd unit) and four other routes. This work chose the Delegated Identity API with a pid and a custom plugin. Route A does not work as it stands (see "Facts checked on the host").

## Goal

Each microVM gets its own SPIFFE ID. The private key stays on the host, outside the guest. The SPIRE agent checks properties of the VM, and not properties of a forwarder.

```text
spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/<vm-name>
```

## Read these first (do not copy them here)

- The old handoff: `microvm-workload-attestation.md`.
- The research note: `docs/research/microvm-workload-attestation-spire.md`. It comes from reading only. The spike proved some of its claims and corrected others.
- The node attestation guide: `code/mcp-sandbox/part-3-mcp-guardrails/docs/node-attestation.md`.
- The spike code and configs: the folder `microvm-attestation-spike/` next to this file. It is an archive of a test. It is not production code.
- The repo rules: `AGENTS.md`. Read `docs/agents/pull-requests.md` before any commit or PR.

## The design (agreed with the user)

One host agent. One proxy process (the delegate). One custom plugin inside the agent. Two registration entries.

1. The proxy connects to `admin.sock` of the host agent.
2. The agent reads the pid of the caller from the kernel. It attests the proxy with its attesters. It matches the entry of the proxy and checks `authorized_delegates`.
3. The proxy sends the pid of the VMM (the `msb machine` process) in the request. It sends nothing else.
4. The agent runs its workload attesters on that pid. The `unix` attester gives the uid. The `msbvm` plugin gives the VM name and the sandbox ID.
5. The agent matches the entry of the VM. The selectors are `msbvm:name:<vm>` and `unix:uid:<uid>`.
6. The agent returns the SVID and the key to the proxy on a stream. The VM never sees them.

## Facts to keep straight

The user and I corrected these during the session. Do not repeat the old claims.

- The pid is the input of the attesters. It is not a selector, because it changes at each start.
- The plugin reads the name and the ID from the command line of the VMM. The `run` row in `msb.db` only checks them.
- The proxy has its own entry, and the agent mints an SVID for it. The `admin.sock` call does not deliver that SVID. The proxy gets it with a second call to `agent.sock`. I did not test that call.
- The agent mints the SVIDs of all entries of its node at start. The server is not involved when a delegate calls.
- A refusal is an empty response with zero SVIDs. It is not an error. The proxy must treat zero SVIDs as a failure.
- The Delegated Identity API runs on a local Unix socket only. The delegate must run on the same host as the agent.
- The API does not limit a delegate to certain VMs. Use one agent for each user in a multi-tenant host.
- A plugin must be in Go. The SPIRE SDK is Go only. The proxy can be in Go or in Python.

## Facts checked on the host (2026-11-06, live)

- msb is version 0.7.13. SPIRE is 1.15.5. systemd is 262. Go is 1.27.3 (mise). `spire-agent` is not installed on the host.
- `msb inspect` has no VM ID, no pid and no start time. It has the name, `created_at`, the image digest and a `config-sha` label that changes with the config.
- The VMM is the process `msb machine --name sandbox-dev --sandbox-id 184 ...`. Its parent is `systemd --user`. It has no child process.
- The VMM is also the network proxy. Threads `smoltcp-poll` and `virtio-net` run inside it. It holds `agent.sock` and `control.sock` under `~/.microsandbox/run/sandboxes/`.
- The VMM has no cgroup scope of its own. It runs in the scope of the terminal. The system D-Bus returns `user@1000.service` for its pid.
- `msb.db` has a `sandbox` table (the ID is an autoincrement) and a `run` table (pid, status, `started_at`). Each start adds a `run` row.
- The `run.started_at` value matches the start time in `/proc` within 5 ms.
- `spire.localhost` resolves on the host and the gateway answers. The server has `join_token` and `x509pop` enabled.

## Spike results

The spike used a throwaway SPIRE server on localhost. It did not use the cluster. The agent attested with a join token.

| Test | Result |
|---|---|
| T1: the delegate sends the real VMM pid | The SVID of the VM came back. The key parsed as ECDSA. |
| T2: a pid that is not a VMM | Zero SVIDs |
| T3: the same delegate binary at another path | `PermissionDenied: no identity issued` |
| T4: a fake `msb` with the same exe name and command line | Zero SVIDs. The plugin found no `run` row. |
| T5: the real VMM again | The same SVID came back. |

## Findings that change the design

- The admin socket must be in a different folder from the Workload API socket. The agent refuses to start otherwise.
- The host agent cannot share the `x509pop` node certificate with the agent in the VM. Both would get the same agent ID. I think they would remove each other from the server. I did not test it.
- The plugin depends on the `run` and `sandbox` tables of msb 0.7.13. These tables are internal and can change.
- A `join_token` agent cannot attest again. The agent warned about this with the `memory` key manager. The real setup uses `x509pop`.
- The spike has no `pidfd`. The proxy must hold a `pidfd`, so a recycled pid is never sent.

## Google Agent Compute Engine

Source: the post [Agent Compute Engine deep dive](https://cloud.google.com/blog/topics/ai-infrastructure/agent-compute-engine-deep-dive).

- One microVM for each agent. The keys for node and workload attestation stay "outside the guest environment within the IPU, the host, or remotely".
- The VM gets a session-scoped public SPIFFE certificate and a token. A local proxy forwards its traffic. The gateway checks the user, the agent identity and the node identity.
- The node anchor is Google silicon: Titan and the Titanium IPU. The post does not mention a TPM or TPU attestation. It does not say what evidence the attestation produces.
- Our design has the same shape. The attestation mechanics of Google are not public, so I cannot say they are equal.
- Option for later: the SPIRE node attestor `tpm_devid` puts the node key in a TPM. The host has `/dev/tpm0`. The device is open to root and the group `tss` only. I did not test `tpm_devid`.

## Plan: separate PRs

1. **Docs and ADR.** The answers of Step 1, the spike results and the decision. No code. Move this handoff and the spike archive here.
2. **The `msbvm` plugin.** A Go module with unit tests (a fake `/proc` and a fake database). Pin the tested msb version. Print the checksum of the binary.
3. **Host agent.** The agent config, a `just msb` recipe, a node certificate for the host, and the decision about the agent in the VM. Depends on PR 2.
4. **The proxy (delegate).** It finds the VMM pid, holds a `pidfd`, treats zero SVIDs as a failure and keeps the stream. Depends on PR 3.
5. **Registration.** A `ClusterStaticEntry` for the proxy and one for each VM. The alias is the parent. Use `gitops-knowledge` and the schema catalog. Can run in parallel with PR 4.
6. **Gateway.** The gateway reads the URI SAN and checks the node, the user and the VM. This has its own open problem (see the earlier handoff: the ExternalSecret `github-upstream` fails).

Do PR 1 and PR 2 first. A later PR can add `tpm_devid` for the node key.

## Open decisions (ask the user)

- The language of the proxy: Go or Python. I suggest Go. The repo rules for Python are in `docs/agents/python.md`.
- How the proxy finds the VMM pid. Option 1: it starts the VM and keeps the child pid. Option 2: it reads the `run` row in `msb.db`. I tested neither.
- The node certificate of the host agent: a separate certificate, or the VM agent goes away.
- The location of the code in the repo: under `code/mcp-sandbox/part-3-mcp-guardrails/`, or a new `tools/` folder.
- Does the proxy need its own SVID? If it does, it needs the second connection to `agent.sock`.
- What starts the proxy: `just msb run`, or a systemd user unit.
- The user has not decided to close PR #260 (Envoy in the VM).

## Cleanup on the cluster

My first attempt left two items on the SPIRE server of the cluster. I could not remove them, because the permission check blocked writes to the live server. Check first. Run these on `spire-server-0` in `spire-system`.

```text
spire-server entry show          # look for spiffe://mcp.local/spike/agent
spire-server agent list          # look for an agent with the type join_token
spire-server entry delete -entryID b5504c60-6d3d-4112-a3f0-fc378a86544a
spire-server agent evict -spiffeID <the join_token agent ID from the list>
```

The user may have removed them already. Do not touch the entries `mcp-guardrails.*` and the agents `k8s_psat` and `x509pop`.

## How to rebuild the spike

Run these on the host. Use an empty folder for the unpacked SPIRE release. Do not run an interpreter inside it.

1. Download the SPIRE release: `gh release download v1.15.5 -R spiffe/spire -p 'spire-1.15.5-linux-amd64-musl*'`. Check it with `sha256sum -c` on the `_sha256sum.txt` file. Unpack it.
2. Build the plugin and the delegate. In each folder under `microvm-attestation-spike/`, run `go mod tidy` and `go build`.
3. Fill the placeholders in `spike-server.conf` and `spike-agent.conf`. Put the checksum of the plugin binary in the agent config.
4. Start `spire-server run`. Make a join token for `spiffe://mcp.local/spike/agent`. Keep the token in a file with mode 600.
5. Make two entries on the local server. Both have the parent `spiffe://mcp.local/spike/agent`. The proxy entry uses `unix:uid` and `unix:path` of the delegate binary. The VM entry uses `msbvm:name:<vm>` and `unix:uid`.
6. Start `spire-agent run` with the join token. Run `delegate -socket <admin.sock> -pid <VMM pid>`. Get the pid with `ps -eo pid,args | grep '[m]sb machine'`.

## Rules for the session

- Never use `pkill -f` or `pgrep -f` with a pattern that also appears in your own command. It matches your shell.
- The permission check blocked two actions: a chained download, unpack and run, and `entry create` on the live server. Do each step on its own. Ask the user for the live server.
- Herdr was not running on 2026-11-07. `herdr worktree create` fails until the user starts `herdr`.

## Decisions of the user (do not reopen without a reason)

- The microVM is the workload. The key stays outside the guest.
- The SPIFFE ID has the node, the user and the VM.
- The SPIRE agent runs on the host, not in the VM.
- The user reads on a phone. Use short lists and narrow diagrams.
- Write all text in Simplified Technical English. Run `/asd-ste100` before you finish a change.

## Not checked

- The `x509pop` attestation of the host agent against the cluster server, and the alias parent.
- The proxy getting its own SVID through `agent.sock`.
- The use of the SVID for mTLS to the gateway. The spike only parsed it.
- A stop and start of the VM. I did not stop `sandbox-dev`, because that ends the user session.
- Collision of two agents with the same node certificate.
- `tpm_devid`, and whether the agent user can open the TPM.
- Whether agentgateway can read a URI SAN in a rule.
- A write on the cluster server. The permission check blocked it.

## Suggested skills

- `asd-ste100` before you finish any change.
- `tdd` for the plugin in PR 2.
- `pr` for the body of a PR.
- `gitops-knowledge` and the flux-schema-catalog for any Flux or Kubernetes manifest.
- `research` if a new question about SPIRE or `msb` comes up.
