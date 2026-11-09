# Handoff: a Podman sandbox with a microVM to replace the msb sandbox

Written on 2026-11-08. The index of all handoff documents is `docs/handoff.md`.

> **Update of 2026-11-09.** The owner chose another direction: a plain hardened Podman container with a host-side proxy. See [podman-plain-sandbox.md](podman-plain-sandbox.md). Read this document for the spike results, the lessons and the state of the host.

The research and the spikes are done. No part of the new sandbox exists in `.msb/` or in a `.sandbox/` folder yet. This handoff lets a fresh session continue without the old conversation. Read it, then read "Next steps".

## Goal

The owner wants a sandbox for the AI agent that:

1. Replaces the msb microVM and the dev container with one declarative Compose file.
2. Gives the agent a normal developer experience. The agent builds images with Podman and pushes them to a registry. It also packages Kubernetes manifests as OCI artifacts. `kind` and k3s inside the sandbox are not needed.
3. Has no real secrets inside. An egress proxy swaps placeholders for real values and allows only listed hosts.
4. Gives the sandbox container a SPIFFE identity, if this is possible without a complex flow.
5. Ships as a signed OCI artifact. The host runs only a pinned and verified digest.

## Read these first (do not copy them here)

- The research note: `docs/research/podman-sandbox-runtimes.md`. The section "Update of 2026-11-08" has all spike results, the three-way comparison and the plans. The sections below it are the first research, before the spikes.
- The configs and scripts of the spikes: `docs/research/podman-sandbox-spikes/README.md`.
- The rules of the repo: `AGENTS.md`. Before a PR, read `docs/agents/pull-requests.md`. Before a topic doc, read `docs/agents/project-docs.md`. Before any text, run `/asd-ste100`.
- The older identity work for the msb microVM: `code/agent-workload-identity/docs/handoff/agent-workload-identity-status.md`.

## What is done

- Fifteen spikes on the host on 2026-11-08, with fake secrets only. The research note has a table for each spike.
- Three runtimes are tested with iron-proxy as the egress proxy:
  - Rootless Podman with `krun` (a libkrun microVM). Spikes A, N1 and N2.
  - Rootless Podman with gVisor. Spikes G1 and G2.
  - Rootful Docker with gVisor. Spikes D1, D2, F1 and F2.
- Other spikes: iron-proxy (B), hardening and volumes (C), SPIRE with Podman (D) and the signed OCI artifact (E).
- No file in `.msb/` changed.

## The result in short

| Topic | Result |
|---|---|
| `krun` | Works rootless. Nested Podman works as non-root with native overlay. It has no `podman exec`. It cannot get a SPIFFE identity natively. |
| gVisor with Podman | Works. A SPIFFE identity needs a start wrapper. Limits are not enforced. |
| gVisor with Docker | The sandbox container gets its SVID natively at start. Limits are enforced. A sentry escape gives host root. Nested Podman needs `allow-suid`, `vfs` and the host network. |
| iron-proxy | Passed every egress, swap, rotation and streaming test. |
| Build, push and publish | Passed as non-root `agent` under Docker with gVisor. Passed under `krun` as non-root (N1). |

## Decisions of the owner

- Use iron-proxy in its own container as the only way out. Caddy is dropped. [spike B]
- Keep the config in a repo folder, for example `.sandbox/`. The sandbox works on a clone. The host reads the config read-only. A change takes effect only after a reviewed merge and a reload on the host.
- All bind mounts are read-only. All writable data is a named volume.
- The agent runs as non-root `agent`.
- At the end of this session the owner said, by voice, to use a microVM with `krun`. The reason: Podman inside then needs no special privileges, and developers get a normal experience. The text of the message was unclear. This is the reading of the session. Ask the owner about it first (see "Open decisions", item 1).

## Open decisions (ask the owner)

1. **Runtime.** Podman with `krun` (the direction at the end), or Docker with gVisor. Docker with gVisor has a native identity and enforced limits. It also has a root daemon, and an escape gives host root. Ask which host engine to use for `krun`. Rootless Podman is tested. Docker with a `krun` runtime is not tested.
2. **SPIFFE identity for a `krun` sandbox.** `krun` cannot get it natively. The options:
   - A vsock port mapped to the agent socket. It needs a `crun` patch. `libkrun` has `krun_add_vsock_port2`. `crun` never calls it.
   - A root-owned helper in the guest.
   - An Envoy sidecar on the host that holds the SVID. Native on the host with the `docker` attestor.
   - No identity for the sandbox.
3. **Access to a `krun` sandbox.** `podman exec` does not work under `krun`. Choose between TTT or a shell as the foreground process, more shells through Herdr, or an `sshd` in the guest.
4. **Storage of nested Podman.** Fix A (not persistent, `force_mask` on the container rootfs) or fix B (an ext4 loop image on a named volume).
5. **Package list on the host.** Where the file with the packages lives, and whether a post-update hook installs them. Omarchy has no such feature. It has `omarchy-pkg-add` and the hook folder `~/.config/omarchy/hooks/post-update.d/`.

## Next steps

For the `krun` path. Do them in this order.

1. Ask the owner about open decisions 1 to 4.
2. **N9: access without `podman exec`.** Test TTT as the foreground process, `podman attach` and an `sshd` in the guest.
   - verify: you open an editor and two shells in the sandbox from the host terminal.
3. **N4: the full stack under `krun`.** Use the static uid maps (`0:100000:65536` for the sandbox and `0:200000:65536` for the proxy), a Podman secret for `ca.key`, and the caps `CHOWN`, `SETUID`, `SETGID`, `FOWNER` and `DAC_OVERRIDE`. Apply the image changes: a `storage.conf` with `force_mask` or the loop mount, `TMPDIR=/dev/shm`, boot as guest root through the container command, and no `fuse-overlayfs`.
   - verify: the egress self-test passes. `claude`, TTT and Herdr start. As `agent`, `podman build`, `podman push` and `flux push artifact` work through iron-proxy.
4. **N3: CA trust per tool.** Use the table in the research note (spike F2). The tools: `python`, `node`, `requests`, `git`, `podman`, `flux`, `terraform`.
5. **N5: real traffic (the owner runs it).** Use `bws run` with the real tokens, one at a time. Test the Claude API with a long SSE stream and a large body. Test GitHub with a Basic auth `git` clone and push. Test `ghcr.io` with a scoped token (the bearer-token exchange is not tested). Test the Qwen endpoint.
   - verify: each call works. The audit log shows the swap. No real token appears in the sandbox.
6. **N6: SSH remotes.** iron-proxy passes HTTP and TLS only. Change `git` remotes that use SSH to https.
7. **Identity.** Spike the option chosen in open decision 2.
8. **Build `.sandbox/` in a Herdr worktree.** Add `compose.yaml`, `iron-proxy.yaml` (secret names and placeholders only), the image files, a `justfile`, a README and the egress self-test. Add a CODEOWNERS rule for the folder and a CI test that the compose file has no `privileged`, no `network_mode: host`, no socket mount and no extra `devices`.
9. **Publish and gate.** Pin images by digest. Publish with `podman artifact` or `flux push artifact`. Sign by digest with `cosign`. The host runs `E/verify-pinned.sh` and `cosign verify` before `up`. Give the sandbox no token that can push to the bundle package.
10. **Switch.** Run next to `msb` for one week. Switch the daily command. Keep `.msb/` for two more weeks. Remove it after that.

If the owner chooses Docker with gVisor, use the "Plan changes after G1 and G2" and the F1 and F2 sections of the research note. The open items for it: a watchdog for the identity supervisor, `no-new-privileges`, `userns-remap` with `runsc`, and the real GHCR flow.

## Lessons

- A microVM changes where limits and mounts are enforced. Under `krun`, host flags confine only the VMM. The guest has full capabilities and no seccomp.
- The libkrun virtiofs server runs each file operation with the uid of the caller and no capabilities. This broke nested Podman as non-root. `force_mask = "0700"` or an ext4 loop image fixes it.
- `podman-compose` 1.6.0 has traps: it ignores `configs:` and the `uid`, `gid` and `mode` of file secrets. It puts all services in one pod unless you set `x-podman: {in_pod: false}`. Docker Compose ignores the secret options too.
- `--userns=auto` fails while any `keep-id` container exists in the store. Auto ranges shift between runs. Use static maps.
- Docker's embedded DNS (`127.0.0.11`) is refused inside gVisor. Bind-mount a `resolv.conf` with the proxy IP.
- A forged label gets any workload's SVID if the user has Docker API access. The trust anchor is that access.
- Podman 6.1.4 cannot verify cosign v3 signatures. Verify with `cosign` and a pinned digest in a script.
- `docker compose publish` bundles only `compose.yaml`. `--with-env` puts env values in plaintext.
- The permission system denied downloads of binaries more than once. Give the owner the exact command for such a step.
- A bind mount of a missing host path makes Docker create a root-owned folder there. Two spikes left such folders.
- gVisor has a public security record (`https://gvisor.dev/security-track-record/`). Keep `runsc` current. The fix for the gofer and CUSE bug (commit `573a9e73cf84`) is in release 20261102.0.

## State of the host

These changes are outside the repo. They stay until someone removes them.

- Installed: `crun` 1.30.1 (it shows `+LIBKRUN`), `libkrun` 1.19.6, `libkrunfw` 5.6.2, Docker 29.9.2 and Docker Compose. `runc` is still installed. `cosign` 3.1.4 and `oras` 1.3.6 came through mise.
- Docker runs. Three runtimes are in `/etc/docker/daemon.json`: `runsc`, `runsc-uds` and `runsc-suid`. `runsc` is in `/usr/local/bin`. The old config is `/etc/docker/daemon.json.bak-before-gvisor`.
- User `rana` has an ACL on `/var/run/docker.sock`. This is root-equivalent. Remove it with `sudo setfacl -x u:rana /var/run/docker.sock` or stop Docker.
- Root-owned leftovers: `/tmp/D-spire` (an empty folder) and `~/.local/share/mise/installs/aqua-oras-project-oras` (the `oras` install is broken). Fix: `sudo rm -rf /tmp/D-spire ~/.local/share/mise/installs/aqua-oras-project-oras && mise install oras`.
- An empty `~/.gnupg` that spike B made.
- Docker images from the spikes: `dev-sbx` (7.2 GB), `stage10-verify` and `iron-proxy`.
- `.msb/vm/sandbox.yaml` shows as modified in the main checkout. It is not a change of this work.
- The raw result files of the spikes were in a temporary folder and are gone. The tables are in the research note. The configs and scripts are in `docs/research/podman-sandbox-spikes/`.
