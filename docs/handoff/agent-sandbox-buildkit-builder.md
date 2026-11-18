# Handoff: the BuildKit builder of the agent sandbox

Written on 2026-11-18. The index of all handoff documents is `docs/handoff.md`. This document replaces the build design of [agent-image-build-system.md](agent-image-build-system.md) (Valkey) and the Go listener plan. It continues [podman-gvisor-sandbox.md](podman-gvisor-sandbox.md).

The agent in the sandbox builds container images with `buildctl`. `buildkitd` runs in a second gVisor container, the builder. This removes the `build.sock` listener, `crane`, the context registry and the Valkey queue. The change is [PR #317](https://github.com/raghav19/engineersdaybook/pull/317). A fresh session continues with "Next steps".

## Goal

The owner wants the agent to build images with no custom build code and no build capability in the sandbox. The sandbox must stay hardened. The agent is hostile, so a build step is code that nobody trusts.

## State of the repo

- PR #317 (branch `sandbox-builder-buildkit`) is open. It adds the builder, the health check, the diagram and the research note, and it removes `.sandbox/build/` (Valkey). It keeps the `nftables` rule.
- The research note is `docs/research/remote-buildkit-for-agent-sandbox.md`. It has the sources and the spike results.
- The Go listener in `code/agent-sandbox/builder/` and the handoff `go-build-socket-listener.md` are untracked and obsolete.
- The host has no part of PR #317 installed. After the merge, run `just sandbox setup` and `just sandbox build`.

## The design as built

```
sandbox.service (agent, gVisor, no network)
  Requires and After
sandbox-builder.service (buildkitd, rootless, gVisor runsc-builder, no network)
  tmpfs cache, new for each sandbox session
  buildkitd.sock in $XDG_RUNTIME_DIR/sandbox/buildkit, mounted read-only in the sandbox
agent: buildctl build ... --output type=oci,dest=image.tar   (BUILDKIT_HOST is set)
```

- **Lifetime:** `sandbox.service` requires the builder. A stop or a restart removes it, with its cache.
- **Limits:** 2 GB of memory, 2 CPUs, `TasksMax` 1024 and a 1 GB `tmpfs`.
- **Health:** `Notify=healthy` fails the start if `buildctl debug workers` fails. `HealthOnFailure=kill` stops a builder that becomes unhealthy, and systemd starts a new one.
- **Runtime:** `runsc-builder` in `.sandbox/runsc.conf` has `network=none` and `host-uds=create`. The sandbox keeps `runsc` with `network=host` and `host-uds=open`.
- **Push:** the builder never pushes. The sandbox pushes the OCI tar through the proxy. This is not tested.
- **Trust:** BuildKit has no authorization. Any holder of the socket can run any build step as root in the builder. The container is the wall.

## Evidence

All tests ran on the host of the owner on 2026-11-18 with Podman 6.1.4, `runsc` release-20261102.0 and `moby/buildkit:v0.35.0-rootless`. The client was a second gVisor container with `host-uds=open`.

| Test | Result |
|---|---|
| `buildkitd` in `runsc` with `tmpfs` state | Runs. `buildctl debug workers` lists one worker. |
| Capabilities | `SETUID`, `SETGID` and `SYS_CHROOT` are enough. |
| `no-new-privileges` on | `rootlesskit` hangs with no log and no socket. |
| A `COPY` build and a `RUN` build with an OCI layout base image | Both pass. The OCI tar arrives in the client. |
| Restart of the builder | The `tmpfs` state is empty. |
| Start, restart and stop of `sandbox.service` | The builder starts first, a restart gives a new builder, a stop removes it. |
| A builder that is never healthy | `systemctl start sandbox` fails in 3 seconds. |
| `buildkitd` frozen after a good start | The health check fails, Podman kills the builder, and systemd starts a new healthy one. It takes about 100 seconds, because the start period is 60 seconds. |
| A build that writes 1.5 GB | Fails with "No space left on device". The builder stays healthy. |
| Load | Idle: 75 threads and 230 MB. A small build: 95 threads and 300 MB. |

## What was not tested

- A `FROM` pull through iron-proxy. The builder has no network.
- A push of the OCI tar from the sandbox.
- `buildctl` in the real sandbox image. The image is not rebuilt.
- Parallel builds, a memory bomb and a fork bomb.
- `just sandbox setup` and `just sandbox run` with the new units.
- `network=none` for the agent container (a TODO in `runsc.conf`).

## Decisions of the owner

- BuildKit in a second gVisor container, new for each sandbox session. One builder for all Herdr sessions.
- The Valkey queue and the Go listener are dropped.
- The `nftables` rule stays. The owner tried to remove it, then reverted.
- Containerizing iron-proxy is deferred. See "Next steps".
- Comments are crisp one-liners in Simplified Technical English. They explain the line, with no measurements.

## Open decisions (ask the owner)

1. Remove or move the untracked documents that describe rejected designs: `agent-microsandbox-handoff.md`, `agent-sandbox-iron-proxy-handoff.md` and `docs/research/podman-gvisor-caddy-sandbox.md`.
2. Commit `go-build-socket-listener.md` and `spiffe-identity-podman-sandbox.md`, or keep them local.
3. Split `.sandbox/` into `agent/`, `builder/`, `proxy/` and `runtime/`. This is its own PR.
4. The Dockerfile installs `podman` in the sandbox image. Decide if it stays.

## Next steps

1. Merge PR #317. Run `just sandbox setup` and `just sandbox build`. Run a build from the sandbox.
2. Test a push of the OCI tar from the sandbox through the proxy. The check is that the proxy log shows the token swap and that the push to a path outside the allowed list gets `403`.
3. Build the relay for `FROM` pulls: `socat` in the builder, a socket to the bridge and the CA. The check is that an allowed host passes and an unlisted host gets `403`.
4. Test `network=none` for the agent container. The check is that `socat` binds `127.0.0.1:3128`, a tool reaches the proxy, and `curl --noproxy '*' https://1.1.1.1` fails.
5. TODO: test iron-proxy in a Quadlet container on an internal Podman network (`Internal=true`), with no `socat`, no bridge and no `nftables` rule. The check has three parts. `ss -ltn` on the host shows no ports 18080 to 18084. The sandbox reaches an allowed host. A second user cannot reach the proxy. `iron-proxy` 0.56.0 cannot listen on a Unix socket (tested), and the real tokens must reach the container without Podman storage.
6. Run parallel builds and a memory bomb against the limits.

## Lessons

- A runtime name other than `runsc` needs the full path of the binary in `[engine.runtimes]`. A relative path gives "not found".
- A subuid must own the socket folder. `podman unshare chown 1000:1000` does this. The mode is 0700.
- `tmpfs` takes `mode=1777` for the container user. It takes no `uid=` option.
- `buildkitd` exits with code 1 on a stop. systemd shows `failed` after a stop. The sandbox unit shows the same.
- `PartOf=` in the builder and `Requires=` in the sandbox give a new builder for each session.
- A health check counts failures only after the start period.
- Test in renamed units. The first tests of this work started the live `sandbox.service`. Do not do this.
- The git credential helper of the host points to a `gh` version that no longer exists. `gh auth setup-git` fixes it.

## State of the host

- The links in `~/.config/containers/` point to the main checkout. The builder is not installed.
- The `nftables` rule from the earlier setup is still installed.
- `sandbox-proxy.service` has been in `failed` state since 2026-11-12 (start limit). Check it before `just sandbox run`.
- A `build.sock` file from the listener spike and the folder `$XDG_RUNTIME_DIR/sandbox-queue/` may remain. Remove them.
- The image `moby/buildkit:v0.35.0-rootless` is in the Podman storage of the owner.
