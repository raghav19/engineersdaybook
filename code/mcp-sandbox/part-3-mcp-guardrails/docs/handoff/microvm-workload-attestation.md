# Handoff: SPIFFE identity of the msb microVM (workload attestation)

Written on 2026-11-06. The index of all handoff documents is `docs/handoff.md` at the root of the repo.

This handoff is for work on the **host**. The sandbox VM cannot run `msb`, so it cannot answer the open questions. Read this document, then do "Step 1" on the host.

**Where this document and an older record disagree, this document wins.** PR #260 (Envoy in the VM) and `docs/zero-trust-workload-attestation.md` describe a design that this work replaces. The user has not yet decided to close #260.

## Goal

Each microVM gets its own SPIFFE ID. The private key stays on the host, outside the guest. The SPIRE agent must check **properties of the VM**, and not properties of a forwarder program.

The agreed ID has three parts: the node, the user and the VM.

```text
spiffe://mcp.local/node/sandbox-dev/user/raghav19/vm/<vm-name>
```

## Read these first (do not copy them here)

- The research note: `docs/research/microvm-workload-attestation-spire.md`. It lists the SPIRE plugins, the Workload API facts, and five options (a) to (e). It marks each claim with its source.
- The node attestation guide: `code/mcp-sandbox/part-3-mcp-guardrails/docs/node-attestation.md`.
- The earlier handoff: `code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/node-attestation.md`. It has the rules for work in this repo.
- The node entry: `platform/addons/spire/node-entry.yaml`. The agent config of the VM: `.msb/image/configs/spire/spire-agent.conf`.
- PR #260 (Envoy in the VM, open).

## The model the user chose

- One SPIRE agent runs on the **host**. It attests with the node key and certificate that `just msb node-cert` copies to `~/.config/msb/node`. The server then adds it to the alias `spiffe://mcp.local/node/sandbox-dev`.
- A workload entry for each VM has the alias as `parentID`.
- A process on the host calls `agent.sock` and holds the SVID. The VM never sees the socket or the key.
- The gateway reads the SPIFFE ID and checks the node, the user and the VM.
- The alias is not in any certificate. It is a record in the SPIRE server. The agent SVID has only the agent ID `spire/agent/x509pop/<fingerprint>`.

## The open problem

The agent only sees host processes. It reads the pid of the caller of `agent.sock`. The `unix` attestor gives the uid and the path. The `systemd` attestor gives the unit name. The cgroup gives a **group**, and a group has no VM properties.

In Kubernetes the group is the first step only. The k8s attestor maps the cgroup to a pod, then asks the kubelet for the pod facts. The facts come from the platform record, not from the process.

We need the same second step for a microVM: a lookup into the record that `msb` keeps about the VM. Nothing in SPIRE 1.15.5 does this for us. The research note found no Kata, Firecracker or SPIRE source that gives a microVM a SPIFFE identity.

## Step 1: find what msb records (on the host)

Run these with a VM running. They change nothing. Remove any token or secret from the output before you paste it anywhere.

```text
msb inspect <vm-name> --format json
ps -eo pid,ppid,user,cgroup,args | grep -iE 'msb|krun|microsandbox'
```

Answer these questions:

- Does the `inspect` output have a VM ID, a pid, an image digest or a start time? These are possible selectors.
- Which process is the VM itself (the VMM)? Write down its pid and its chain of parents.
- Is the host process that carries the traffic of the VM (the msb proxy) the same process as the VMM, or a different one? If it is the same, that process can be the workload, and you do not need a separate forwarder.
- In which cgroup does the VMM run? Does it have its own scope or unit?
- Does the VM ID stay the same when you stop and start the same VM? The SPIFFE ID must stay stable.
- Can a program find the VM from the pid alone? Look for a pid file, `/proc/<pid>/cmdline` or a state folder. The plugin of option (b) gets only a pid.
- Does `systemd` run on the host? Run `systemctl --version`. The README mentions Hyprland, so the host is probably Linux. I did not check this.

Write the answers in a short note. They decide the route in Step 3.

## Step 2: run a SPIRE agent on the host

No host agent exists in the repo yet. Build a test agent from the VM config `.msb/image/configs/spire/spire-agent.conf`. Change these values:

- `private_key_path`, `certificate_path` and `trust_bundle_path`: the files in `~/.config/msb/node` (`node.key`, `node.crt`, `bundle.json`).
- `socket_path`: a short path. A Unix socket path has a limit of 108 characters.
- `data_dir`: a folder that you own.
- `server_address = "spire.localhost"`. I do not know if the host resolves this name to the gateway. Check it first.
- Add `discover_workload_path = true` to the `unix` plugin if you test path selectors.
- Add `WorkloadAttestor "systemd" { plugin_data {} }` if you test option (a).

Run `just msb node-cert` first, so the files are current. Then start the agent and look at `spire-server agent list` on `spire-server-0` (namespace `spire-system`). The new agent must show `x509pop`.

## Step 3: get an SVID through the Workload API

The test: a process asks the agent for an SVID, and the SVID has the ID of the entry that you made.

```text
spire-agent api fetch x509 -socketPath <socket> -write <dir>
openssl x509 -in <dir>/svid.0.pem -noout -ext subjectAltName
```

The SAN must show the SPIFFE ID of the entry. If the call fails with a permission error, no entry matched the caller.

Make a test entry with `spire-server entry create` on `spire-server-0`. Use the alias as `-parentID`. Remove it after the test. I did not check if spire-controller-manager keeps or removes an entry that it does not own.

Pick the route from the answers of Step 1:

- **Route A, no code (option a).** Start the process in a **system** unit with the VM ID in its name: `sudo systemd-run --unit=msb-<vm-id> ...`. The entry selector is `systemd:id:msb-<vm-id>.service`. The `systemd` attestor asks the system D-Bus for the unit of the pid. A unit of the user manager (`--user`) is probably not visible there. I did not test this. This route proves only that the caller is in the unit that the launcher made.
- **Route B, plugin (option b).** An external `WorkloadAttestor` plugin gets one input: the pid. It walks the parents of the pid up to the VMM, asks `msb` which VM that is, and returns selectors such as `msbvm:name:<vm>` and `msbvm:id:<id>`. The agent config loads it with `plugin_cmd`, `plugin_checksum` and `plugin_data`. The selector type is the plugin name. This route needs a Go plugin and a reliable pid-to-VM lookup from Step 1. It uses the stable Workload API. This is the route I recommend if Step 1 shows such a lookup.
- **Route C, Delegated Identity API (option d).** The launcher sends the selectors of the VM to the admin socket and gets the SVID and the key. The agent makes no check. The launcher alone says which VM it is. Use it as a stable fallback.
- **Route D, Broker API (option e).** The closest match to "the agent checks the VM". The API is experimental in SPIRE 1.15.2 and later. It needs a plugin that handles `AttestReference`. Use it only if you need the agent itself to check the VM.

Success for Route A or B has two parts. Two VMs get two different SPIFFE IDs. A process outside the unit, or outside the VM tree, gets none.

## Decisions of the user (do not reopen without a reason)

- The microVM is the workload. The key stays outside the guest.
- The SPIFFE ID has the node, the user and the VM.
- The SPIRE agent runs on the host, not in the VM.
- The user reads on a phone. Use short lists and narrow diagrams.
- Do not write code before the host findings of Step 1 exist.

## Not checked

- Nobody ran anything for this work. The research note comes from reading.
- What `msb inspect` returns, and which process holds the VM.
- Whether the host resolves `spire.localhost` to the gateway.
- Whether the Delegated Identity API accepts a selector that no plugin produces.
- Whether a custom reference type of the Broker API works end to end in 1.15.5.
- Whether a released plugin SDK tag has `AttestReference`.
- How a VM name and ID reach a pid. This is the question of Step 1.
- Whether the gateway (agentgateway) can read a URI SAN in a rule. The gateway also has an open problem: the ExternalSecret `github-upstream` fails. See the earlier handoff.

## Suggested skills

- `asd-ste100` before you finish any change.
- `pr` for the body of a PR.
- `research` if Step 1 raises a new question about SPIRE or `msb`.
- `gitops-knowledge` and the flux-schema-catalog for any Flux or Kubernetes manifest.
