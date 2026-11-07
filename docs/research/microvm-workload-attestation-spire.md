# SPIRE workload attestation of a microVM

Question: How can a SPIRE agent attest a microVM as the workload? The microVM runs on Firecracker, Kata Containers, libkrun, Cloud Hypervisor or Microsandbox. The SPIFFE ID must bind to VM properties that the platform assigns (a VM name or ID). It must not bind to a process on the host.

Source: SPIRE docs and source at tag `v1.15.5` (read on raw.githubusercontent.com). Also the SPIRE plugin SDK, the SPIRE agent API SDK, and the SPIFFE Workload Endpoint and Broker specs. Also the Kata Containers and Firecracker docs, and SPIRE GitHub issues. Research date: 2026-11-06. Local repo state: `main` at `c6a9dc2`. Update of 2026-11-07: the section "Spike results" adds the results of a test on the host.

Evidence tags: **[spike]** is a result in the spike handoff `code/mcp-sandbox/part-3-mcp-guardrails/docs/handoff/microvm-attestation-spike.md`. The spike ran on the host with a throwaway SPIRE server on localhost. It did not use the cluster. **[spire-doc]** is a file in `spiffe/spire/doc/` at `v1.15.5`. **[spire-src]** is Go source in `spiffe/spire` at `v1.15.5`. **[sdk]** is a file in `spiffe/spire-plugin-sdk` or `spiffe/spire-api-sdk` (branch `main`). **[spiffe-spec]** is a spec in `spiffe/spiffe` (branch `main`). **[kata]** is a doc in `kata-containers/kata-containers`. **[firecracker]** is a doc in `firecracker-microvm/firecracker`. **[vmm-doc]** is a doc or header in another VMM repo, read on raw.githubusercontent.com. **[issue]** is a GitHub issue. **[secondary]** is a blog or talk (none used). **[inference]** is my own conclusion.

## Verdict

1. SPIRE 1.15.5 has no workload attestor for a VM. The built-in attestors read the PID of the caller. None of them reads a VM name or ID. [spire-doc]
2. The SPIFFE Workload API cannot carry VM properties. The agent learns the caller only from the peer credentials of a Unix socket. The Workload API does not allow a proxy to speak for a workload. [spire-src] [spiffe-spec]
3. SPIRE 1.15.5 has two documented ways for a trusted host component to ask for the SVID of another workload. They are the Delegated Identity API and the experimental SPIFFE Broker API (added in 1.15.2). The private key then stays with that component on the host. [spire-doc] [sdk]
4. The best match for "the real VM properties reach the agent" is the Broker API with a vendor reference type. It also needs an external workload attestor that handles `AttestReference`. The spec allows vendor reference types. The agent code passes them to the plugin. The plugin can check the VM name against the platform. [spiffe-spec] [spire-src] [inference]
5. Today, the lowest cost step is a systemd unit or scope per VM. The selector `systemd:id:<unit>` then carries the VM name. It still describes a host process, but the launcher controls the name. [spire-doc] [inference]
6. No Kata, Firecracker or SPIRE source that I read gives a SPIFFE identity to a microVM. The one SPIRE issue on this topic closed as stale with no design. [issue]
7. The Broker API is experimental in 1.15.5. The SPIRE doc says that breaking changes can come. [spire-doc]

Update of 2026-11-07: the spike tested option (d) with a PID, and a plugin of option (b) that maps the PID to the VM. It worked on the host. The spike chose option (d) with a PID, and not option (e). It also corrected verdict 5. See the next section.

## Spike results

The spike used msb 0.7.13 and SPIRE 1.15.5 on the host. It tested the Delegated Identity API with a PID. A custom workload attestor `msbvm` mapped the PID to the VM name and the sandbox ID. It did not test the options (c) and (e). [spike]

### Tests

- T1: the delegate sent the PID of the real VMM. The SVID of the VM came back, and the key parsed as ECDSA.
- T2: the delegate sent a PID that is not a VMM. The agent returned zero SVIDs.
- T3: the same delegate binary ran from another path. The agent answered `PermissionDenied: no identity issued`.
- T4: a fake `msb` with the same exe name and command line. The agent returned zero SVIDs, because the plugin found no `run` row in `msb.db`.
- T5: the real VMM again. The same SVID came back.

### Open questions that the spike closed

- `msb inspect` shows the name, `created_at`, the image digest and a `config-sha` label. It shows no VM ID, no PID and no start time.
- The VMM is the process `msb machine --name <vm> --sandbox-id <id>`. Its parent is `systemd --user`. It has no child process.
- The VMM is also the network proxy of the VM. It holds the `msb` sockets `agent.sock` and `control.sock` under `~/.microsandbox/run/sandboxes/`.
- The plugin reads the name and the ID from the command line of the VMM. The `run` row in `msb.db` (PID, status, `started_at`) only checks them. `started_at` matches the start time in `/proc` within 5 ms.
- Each start of the VM adds a `run` row. The `sandbox` ID is an autoincrement value.
- The Delegated Identity API accepted a PID and ran the workload attestors on it. The attestors were `unix` and `msbvm`.

### Claims that the spike corrected

- Verdict 5 and option (a): the VMM has no cgroup scope of its own. It runs in the scope of the terminal. The system D-Bus returns `user@1000.service` for its PID. So the `systemd` attestor cannot name the VM today. Option (a) needs a change in how `msb` starts the VMM.
- Option (b): the note said that a PID to VM link was not checked. The link exists: the command line of the VMM, and the `run` row.
- Option (d): the spike used a PID, and not a selector. The question of a selector that no plugin produces is still open.

### New facts

- A refusal is an empty response with zero SVIDs. It is not an error. The delegate must treat zero SVIDs as a failure.
- The admin socket must be in a different folder from the Workload API socket. The agent refuses to start otherwise.
- The API does not limit a delegate to certain VMs. On a host with many users, use one agent for each user.
- The Delegated Identity API runs on a local Unix socket only. The delegate must run on the same host as the agent.
- The agent mints the SVIDs of all entries of its node at start. The server is not involved when a delegate calls.
- The delegate has its own entry, and the agent mints an SVID for it. The `admin.sock` call does not deliver that SVID.
- A `join_token` agent cannot attest again. The spike agent used the `memory` key manager and warned about this. The real setup uses `x509pop`.
- The plugin depends on the `run` and `sandbox` tables of msb 0.7.13. These tables are internal and can change.
- A recycled PID is a risk. The spike has no `pidfd`. A real delegate must hold a `pidfd`.

### Not tested

- The `x509pop` attestation of the host agent against the cluster server, and the alias parent.
- Two agents with the same node certificate. The agent IDs can clash.
- The delegate that gets its own SVID with a second call to `agent.sock`.
- The use of the SVID for mTLS to the gateway. The spike only parsed it.
- A stop and start of the VM.
- `tpm_devid`, and whether the agent user can open the TPM.
- Whether agentgateway can read a URI SAN in a rule.

## 1. SPIRE workload attestor plugins

### 1.1 Built-in plugins

| Plugin and what it reads | Selectors |
|---|---|
| `unix`: the PID of the caller, then `/proc/<pid>` (the user, the groups, and with `discover_workload_path` also `/proc/<pid>/exe`) [spire-doc] [spire-src] | `unix:uid`, `unix:user`, `unix:gid`, `unix:group`, `unix:supplementary_gid`, `unix:supplementary_group`. With `discover_workload_path`: `unix:path`, `unix:sha256`. |
| `systemd`: the PID, then the D-Bus call `org.freedesktop.systemd1.Manager.GetUnitByPID` [spire-src] | `systemd:id` (for example `nginx.service`), `systemd:fragment_path`. |
| `docker`: the container ID from the cgroup of the PID, then the Docker or Podman API [spire-doc] | `docker:label:<key>:<value>`, `docker:env:<VAR=val>`, `docker:image_id`, `docker:image_config_digest`, and Sigstore selectors. |
| `k8s`: the pod ID from the cgroup of the PID, then the kubelet [spire-doc] | `k8s:ns`, `k8s:sa`, `k8s:pod-name`, `k8s:pod-uid`, `k8s:pod-label`, `k8s:container-name`, `k8s:node-name`, `k8s:pod-image`, and more. |
| `slurm`: the cgroup v2 path under `slurmstepd.scope` [spire-doc] | `slurm:job_id` or `slurm:sluid`, and `slurm:step`. |
| `windows`: the access token of the process [spire-doc] | Windows user and group selectors. Not relevant for this case. |

Quotes:

- `unix`: "The `unix` plugin generates unix-based selectors for workloads calling the agent." `doc/plugin_agent_workloadattestor_unix.md`. Does not say: anything about VMs or namespaces of another kernel.
- `systemd`: "generates selectors based on systemd unit properties of the workloads calling the agent". `doc/plugin_agent_workloadattestor_systemd.md`. Does not say: that it reads unit properties other than `Id` and `FragmentPath`. The source at `pkg/agent/plugin/workloadattestor/systemd/systemd_posix.go` returns only those two fields (`UnitID`, `UnitFragmentPath`).
- `docker`: "retrieving the workload's container ID from its cgroup membership on Unix systems ... then querying the container runtime API (Docker by default, or Podman when detected) for the container's labels." `doc/plugin_agent_workloadattestor_docker.md`. Does not say: that it supports containerd, CRI-O or any VMM.
- `k8s`: "retrieving the workload's pod ID from its cgroup membership, then querying the kubelet for information about the pod." `doc/plugin_agent_workloadattestor_k8s.md`. Does not say: that it works across a VM boundary.
- `slurm`: "Because the cgroup hierarchy is created and owned by `slurmstepd` and the kernel ... the job and step derived from it cannot be forged by the workload." `doc/plugin_agent_workloadattestor_slurm.md`. Does not say: that it applies outside Slurm. It is the closest pattern to a platform-owned ID: the scheduler creates the cgroup, and the plugin reads the ID from it. [inference]

The doc folder of v1.15.5 has no other workload attestor doc. I listed `doc/` through the GitHub API and found only `docker`, `k8s`, `slurm`, `systemd`, `unix` and `windows`. Does not say: anything about plugins outside this repo. I did not search for third-party plugins.

### 1.2 External plugins in the agent config

`doc/spire_agent.md`, "Plugin configuration":

| Option | Meaning in the doc |
|---|---|
| `plugin_cmd` | "Path to the plugin implementation binary (optional, not needed for built-ins)" |
| `plugin_checksum` | "An optional sha256 of the plugin binary" |
| `plugin_data` | "Plugin-specific data (mutually exclusive with `plugin_data_file`)" |
| `plugin_data_file` | "Path to a file containing plugin-specific data" |

[spire-doc] The doc example is `SomeType "some_plugin" { plugin_cmd = "./path/to/plugin"  plugin_checksum = "..."  plugin_data_file = "some_plugin.conf" }`. For a workload attestor, the type is `WorkloadAttestor`. The selector type is the plugin name. [spire-src] `pkg/agent/plugin/workloadattestor/v1.go` builds each selector with `Type: v1.Name()`. Does not say: how the agent starts the plugin process or with which user. The SDK README says external plugins "are separate processes and use go-plugin under the covers". [sdk]

### 1.3 The gRPC contract

`proto/spire/plugin/agent/workloadattestor/v1/workloadattestor.proto` in `spire-plugin-sdk`: [sdk]

- `rpc Attest(AttestRequest) returns (AttestResponse)`. `AttestRequest` has one field: "Required. The process ID of the workload to attest." `int32 pid = 1`.
- `AttestResponse` has `repeated string selector_values`. "The type of the selector is inferred from the plugin name."
- `rpc AttestReference(AttestReferenceRequest) returns (AttestReferenceResponse)`. The request holds one `google.protobuf.Any reference`. "The packed message is one of the WorkloadReference reference types defined by the SPIFFE Broker API specification ... or a vendor-specific extension type."
- A plugin that does not implement `AttestReference` returns `Unimplemented`. A plugin that gets an unknown type returns `InvalidArgument`.

So the exact input of `Attest` is one PID. The plugin gets no socket path, no UID and no environment of the caller. It runs on the host, so the PID is a host PID. [sdk] [inference]

How the agent uses the plugins: `pkg/agent/attestor/workload/workload.go` runs all configured workload attestors in parallel and merges their selectors. For `AttestReference`, a plugin that returns `Unimplemented` is skipped. Any other error fails the whole attestation. [spire-src] This matters if you also load the `k8s` attestor on the same agent. It handles `AttestReference` and can reject a reference it does not know. I did not test that. [inference]

Example plugins: the SDK has a template at `templates/agent/workloadattestor/workloadattestor.go` and a guide at `docs/AUTHORING.md`. The template returns `Unimplemented` in both RPCs. [sdk] Does not say: any working external workload attestor. I found no example outside the built-in plugins.

## 2. Kata, Firecracker and other VMMs

| Claim | Source |
|---|---|
| The Kata agent runs inside the VM. "Only a single agent process is run for each VM created." | [kata] `docs/design/architecture/README.md`, "Agent" |
| The Kata runtime on the host talks to the agent over vsock: "communicating with the agent using a ttRPC based protocol over a VSOCK socket that provides a communications link between the VM and the host." The doc names this link for container management and for standard I/O. | [kata] same file, "Runtime" |
| SPIRE issue 4522: the SPIFFE CSI driver bind-mounts the Unix socket into a Kata pod, and the connection fails ("connect: connection refused"). Maintainer: "SPIRE needs to be able to introspect the processes that connect to the socket ... it does this by asking the kernel. So I don't think this will work the way you expect." Closed 2023-09-28. | [issue] `spiffe/spire#4522` |
| SPIRE issue 4531 "Support kata-containers workload attestation". The maintainer asks how to mount the socket into the Kata container: "We'd want the peercred on that socket read to match the PID of the kata-container for the agent to make sense of it". Later, the maintainer wrote: "what we really want is first class support from the kata runtime. If it can attach to the workload api, and reflect that socket into the workload's sandbox, then we'd see the runtime shim and be able to properly attest it as such. Then on the SPIRE side, we might choose to pair that with a (new) kata workload attestor". Closed as stale, 2025-04-06, with no design. | [issue] `spiffe/spire#4531` |
| In that issue, one user ran a workaround: an SSH binding of the host socket into the Kata pod. The agent attested the `sshd` PID and not the pod. | [issue] `spiffe/spire#4531`, comment of 2024-03-05 |
| Firecracker vsock: "mediates communication between AF_UNIX sockets (on the host end) and AF_VSOCK sockets (on the guest end)". "the guest `AF_VSOCK` ports are mapped 1:1 to `AF_UNIX` sockets on the host." | [firecracker] `docs/vsock.md`, "Firecracker Virtio-vsock Design" |
| A guest connection to host CID 2, port N goes to a host socket at `<uds_path>_<N>`. "I.e. a guest connection to port 52 will get forwarded to `./v.sock_52`." The `uds_path` is set per VM. | [firecracker] same file, "Setting up the virtio-vsock device" |
| Cloud Hypervisor: "The `virtio-vsock` is based on the Firecracker implementation". It uses `--vsock cid=3,socket=/tmp/ch.vsock`. | [vmm-doc] `cloud-hypervisor/cloud-hypervisor` `docs/vsock.md` |
| libkrun has a call that maps a guest vsock port to a host Unix path: `void krun_vsock_device_add_unix_port(KrunVsockDevice handle, uint32_t port, KrunStr path, bool listen);` | [vmm-doc] `containers/libkrun` `include/libkrun.h` |

Does not say (Kata docs): anything about SPIFFE or SPIRE. A code search for "spiffe" in `kata-containers/kata-containers` returned only `.github/workflows/run-substrate-tests.yaml`. I did not open that file. Does not say: how to forward a Unix socket into the guest, or which attestor to use.

Does not say (Firecracker docs): anything about SPIFFE, SPIRE or caller identity. A code search for "spiffe" in `firecracker-microvm/firecracker` returned no result. The vsock doc does not say which host process holds the socket peer. [inference] The VMM process connects to `<uds_path>_<N>`, so a listener there sees the VMM process as the peer. It does not see the guest process.

Does not say (Cloud Hypervisor, libkrun): anything about SPIFFE. For libkrun, I read only the function signature. I did not read what `listen` does. I did not read any Microsandbox source or doc, because that host is not in my list of sources.

Where the agent runs: in every source above, the SPIRE agent has no VM-aware mode. The issues assume the agent runs on the host. I found no source that runs the SPIRE agent in the guest. [issue]

How the Workload API socket could reach the guest: the documented ways are vsock to a host Unix socket (Firecracker, Cloud Hypervisor, libkrun) and a proxy such as `socat`. [firecracker] [vmm-doc] The Firecracker doc shows `socat` for both directions. In all cases, the SPIRE agent sees the proxy or the VMM as the caller, and not the guest. [inference]

## 3. Community work on VM attestation

- SPIRE issues 4522 and 4531 above are the only SPIRE issues that I found on microVMs. Searches for "vsock", "firecracker", "KubeVirt" and "microvm" in `spiffe/spire` found nothing else on this topic. [issue]
- `spiffe/spiffe#395` "Make SPIFFE compatible with Confidential Computing" (open) asks for an SVID key that the node and the agent cannot read. It points to the Delegated Identity API as a place to add a wrapped key. It does not describe a VM attestor. [issue]
- `spiffe/spire#6973` "SPIFFE Broker API: better support for resources that are not node bound" (open) shows that the SPIRE team extends the Broker API. The new references are not processes. They are Kubernetes objects. [issue]
- I found no first-party project for gVisor or KubeVirt with SPIRE. I did not search for them in depth. I did not use any blog post or talk, so there is no [secondary] claim in this note.

Does not say: anything about production use. I did not read the Google post, as you asked.

## 4. Caller identity, TCP, vsock and proxies

| Claim | Source |
|---|---|
| The Workload Endpoint does no direct authentication: "the SPIFFE Workload Endpoint MUST NOT require any direct authentication of its clients." It uses "out-of-band authenticity checks ... such as kernel introspection or orchestrator interrogation. As an example, it is possible to understand which process is calling the API by examining kernel socket state." | [spiffe-spec] `standards/SPIFFE_Workload_Endpoint.md`, section 5 |
| The same section gives a second method: "allow an orchestrator to place a Unix Domain Socket into a particular container, informing the SPIFFE Workload Endpoint implementation of the container's properties/identity." | same |
| Transport: "It may be exposed as either a Unix Domain Socket (UDS) or a TCP listen socket. Implementations SHOULD prefer Unix Domain Socket transport". TCP "MUST NOT be used unless the underlying network allows the Workload Endpoint server to strongly authenticate the workload based on source IP address (e.g., over a localhost or link-local network), or other strong network-level assertions". | same, section 3 |
| The endpoint "SHOULD be exposed through a local endpoint, and implementers SHOULD NOT expose the same endpoint instance to more than one host." | same, section 2 |
| The spec names only `unix` and `tcp` as schemes for `SPIFFE_ENDPOINT_SOCKET`. It does not name vsock. | same, section 4 |
| SPIRE serves the Workload API on a Unix socket only: `socket_path` is "Location to bind the SPIRE Agent Workload API and SDS socket (Unix only)". The agent wraps the listener in a peer tracker. The Linux code reads `SO_PEERCRED` (PID, UID, GID). The gRPC handshake rejects any connection that the peer tracker did not wrap. | [spire-doc] `doc/spire_agent.md`, and [spire-src] `pkg/common/peertracker/uds_linux.go`, `credentials.go` |
| The Broker spec says that a proxy for many workloads breaks the model: "The security boundary of the Broker and the workload is different ... The SPIFFE of today would see the broker as the workload and not the workload the broker represents." | [spiffe-spec] `standards/SPIFFE_Broker_Endpoint.md`, section 1 |

Does not say (Workload Endpoint spec): what to do for a VM. It does not name vsock. It does not say that a proxy may speak for a workload. The Workload Endpoint has no field for a reference to a workload. [spiffe-spec]

So a proxy cannot speak for a VM through the Workload API. A proxy that connects to the agent socket is the workload for the agent. Its selectors describe the proxy process. [inference]

### 4.1 The two documented "on behalf of" APIs

Delegated Identity API. `doc/spire_agent.md`: "allows an authorized (i.e. delegated) workload to obtain SVIDs and bundles on behalf of workloads that cannot be attested by SPIRE Agent directly." It is served on the admin socket. The agent attests the delegate and checks its SPIFFE ID against `authorized_delegates`. The delegate can send selectors: "the SPIRE Agent will simply return SVIDs for any workload registration entries that match the provided selectors. No other checks or attestations will be performed by the SPIRE Agent." Or it can send a PID, and the agent attests it. The response also holds the private key. The message `X509SVIDWithKey` has the field `x509_svid_key` (encoding DER PKCS#8). [spire-doc] [sdk] The doc warns that the delegate "may impersonate and act on behalf of all workload SVIDs it obtains". Does not say: that a selector type must be one that a plugin produces. I expect that the agent accepts any `type:value` pair. I did not verify that. [inference]

SPIFFE Broker API. Added in SPIRE 1.15.2 ("SPIFFE Broker endpoint, API, and documentation (#6915, #7112)" in `CHANGELOG.md`). The 1.15.5 agent binary contains the string `broker.spiffe.io`. [spire-src] I checked that with a text search of the file. I did not run it. The doc status is: "experimental ... breaking changes may land before this configuration moves out of `experimental`." [spire-doc] Facts from the SPIRE doc and the spec:

- The broker sends a `WorkloadReference`. The agent runs its own attestor stack on the reference. The doc says: "the broker never hand-supplies selectors". [spire-doc]
- The spec says: "Servers MUST NOT trust reference data provided by the client without independent verification." [spiffe-spec] `SPIFFE_Broker_API.md`, 3.1.1
- Reference types: `WorkloadPIDReference` and `KubernetesObjectReference`. Vendor types are allowed: "Implementations MAY define and use vendor-specific or implementation-specific reference types by packing their custom message types into the Any field." [spiffe-spec] 3.1.4
- The endpoint uses mutual TLS with X.509-SVIDs. The broker needs its own SVID first. The agent only accepts brokers listed in `brokers` by SPIFFE ID, with `allowed_reference_types`. A `type_url = "*"` allows any type that the attestor stack understands. Every call needs the header `broker.spiffe.io: true`. [spire-doc]
- A PID reference is local. Over TCP it is denied unless `allow_over_tcp = true`. The Unix socket must not be in the directory of the Workload API socket. [spire-doc]
- In the agent code, a custom `type_url` passes to every workload attestor through `AttestReference`. The `unix` and `systemd` plugins do not implement it, so the agent skips them for such a reference. [spire-src] `pkg/agent/broker/api/service.go`, `pkg/agent/attestor/workload/workload.go`

Does not say (Broker docs): any example of a vendor reference type, or any external plugin that handles one. I found no such example.

## 5. Options for your case

Your constraints: the SPIRE agent on the host, the key on the host, one SPIFFE ID per microVM, selectors that describe the VM.

### (a) systemd or Docker envelope per VM [source] [inference]

- Gives: The launcher starts the forwarder (or the VMM) in a transient unit `msb-<vm>.service` or `.scope`. The registration entry uses `systemd:id:msb-<vm>.service`. With Docker, the entry uses `docker:label:msb.vm:<vm>`. [spire-doc]
- Cost: No code. The selector still describes a host process. The launcher sets the name, and not the platform. Any host process in the same unit has the same ID. The agent needs access to the system D-Bus. Docker needs the Docker socket and a cgroup match. [spire-doc] [inference]
- Check: Start two VMs. Request an SVID through each forwarder. Check that each gets its own SPIFFE ID. Run the forwarder of VM 1 outside its unit. Confirm that it gets no SVID.

### (b) Custom workload attestor plugin that maps PID to VM name [source] [inference]

- Gives: Selectors such as `msbvm:name:<vm>` and `msbvm:id:<id>`. The plugin reads the PID of the caller and looks up the VM in the platform. The plugin loads with `plugin_cmd`, `plugin_checksum` and `plugin_data`. It must implement `Attest(pid)`. [sdk] [spire-doc]
- Cost: A Go plugin that you write and maintain. The input is only a PID, so the plugin needs a PID to VM map. The libkrun VMM runs in a host process. A PID to VM link can then come from a PID file, the cgroup, or an msb state file. I did not check that msb offers this. [inference] If the caller is a forwarder, the PID still names the forwarder. The map must then name the forwarder per VM.
- Check: Unit-test with `plugintest` from the SDK. Then start the agent with the plugin and run `spire-server entry create -selector msbvm:name:<vm>`. Confirm the SVID for a caller in VM 1 and none for a caller in VM 2.

### (c) Per-VM SPIRE agent [source] [inference]

- Gives: The VM binds to the node identity. Each VM gets its own agent with its own `socket_path` and `data_dir`. The launcher gives each agent its own credential: a `join_token` (one-time, `plugin_agent_nodeattestor_jointoken.md`) or an `x509pop` certificate whose name holds the VM name. The workload entries use that agent as parent. The agent only gets entries for its own node ID and aliases. [spire-doc] [inference]
- Cost: One agent process per VM, one node entry and one credential per VM. A Unix attestor on the per-VM agent still sees only a host process. The VM binding is in the node identity, and the launcher decides it. I did not measure the memory of an agent. If the agent socket is the vsock target (`<uds_path>_<port>` in Firecracker), the guest holds the key. That breaks your rule. [firecracker] [inference]
- Check: Start two per-VM agents. Confirm that agent 1 cannot get the entries of VM 2. Confirm the node SPIFFE ID in `spire-server agent list`.

### (d) Delegated Identity API from the launcher [source] [inference]

- Gives: The launcher is an authorized delegate. It sends the selectors of the VM (or the PID of the VMM) over the admin socket. It gets the SVID and the key on the host. The key does not go to the guest. This API is not marked experimental in `spire_agent.md`. [spire-doc] [sdk]
- Cost: With selectors, "No other checks or attestations will be performed by the SPIRE Agent". The launcher alone asserts the VM name. A compromise of the launcher can impersonate every VM. With a PID, the launcher must hold the PID stable (for example with a pidfd). [spire-doc]
- Check: Enable `admin_socket_path` and `authorized_delegates`. Call `SubscribeToX509SVIDs` with a selector such as `msbvm:name:<vm>`. Confirm that the agent returns the SVID of the entry. Confirm that an unlisted caller gets `PermissionDenied`.

### (e) Broker API with a vendor reference type and a plugin [source] [inference]

- Gives: The launcher is a broker. It sends a reference such as `type.googleapis.com/msb.VMReference { name, id }`. A workload attestor plugin handles `AttestReference`, checks the VM against the platform, and returns `msbvm:name:<vm>`. The agent does the attestation, as the spec requires. The key goes to the broker on the host. [spiffe-spec] [spire-doc] [spire-src] [sdk]
- Cost: The Broker API is experimental in 1.15.5. You need a Go plugin, a broker client with an SVID of its own, and a `brokers` entry. I could not confirm that an SDK release tag has `AttestReference`. The 1.15.5 `go.mod` uses `spire-plugin-sdk v1.4.4-0.20260617144146-5dcde407c4d1`, a pseudo-version. [spire-src]
- Check: Write a test plugin that returns a fixed selector for a vendor type. Configure the agent with `type_url = "*"` for one broker. Call `SubscribeToX509SVID` with the vendor reference. Confirm the SVID. Then call with an unknown VM name and confirm that the plugin refuses.

### Ranking [inference]

1. For the most direct match to your wish (VM properties checked by the agent): (e). It costs the most and uses an experimental API.
2. For a stable API with little code: (d), if you accept that the launcher asserts the VM name.
3. For no code now: (a), as a first step. It binds to the unit name that the launcher sets.
4. (b) works with the plain Workload API, and fits if the VMM process or the forwarder has a stable map to a VM.
5. (c) costs one agent per VM and moves the binding to the node identity.

## Gaps and conflicts

The gaps below are from 2026-11-06. The spike closed some of them. Read the section "Spike results" first.

- I did not run `spire-agent`, a plugin, or any VMM. All claims come from reading.
- I did not confirm that the agent accepts a selector type that no loaded plugin produces in the Delegated Identity API. I did not confirm that the Broker API passes a custom `type_url` end to end in 1.15.5. I read the code paths only.
- I did not read the `unix` plugin `AttestReference` path in full. I found no `AttestReference` in `unix.go` and `systemd.go`. The embedded `Unimplemented` server is my reading of the pattern. [inference]
- I did not read Microsandbox docs or source. I did not check what msb exposes as a VM name or ID.
- libkrun: I read the header signature of `krun_vsock_device_add_unix_port` only. I did not read the meaning of `listen`.
- Kata: I read the architecture doc only. I did not read the runtime-rs or Cloud Hypervisor Kata docs for socket forwarding.
- KubeVirt and gVisor: I found no first-party source. I did not search their repos.
- The GitHub issue search rate-limited once. One Firecracker issue search did not run. The code search for "spiffe" in Firecracker and Kata is a weak negative: it may miss items.
- Raw GitHub fetches worked. I did not need any host outside the sandbox allowlist, apart from reading `containers/libkrun` and `cloud-hypervisor/cloud-hypervisor` through `raw.githubusercontent.com`, which is on the list.
- `docs/agents/project-docs.md` says that research notes follow their own rules. I followed the format of `docs/research/mcp-client-workload-identity.md`.
