# Handoff: the hardened Podman sandbox is on main, and the work that remains

Written on 2026-11-10. The index of all handoff documents is `docs/handoff.md`. This document continues [podman-plain-sandbox.md](podman-plain-sandbox.md). Where the two differ, this one is right.

The owner merged both PRs of the new sandbox: [#291](https://github.com/raghav19/engineersdaybook/pull/291) (the host proxy) and [#292](https://github.com/raghav19/engineersdaybook/pull/292) (the sandbox). `main` is at `7c2fe93`. The host of the owner still runs the old design. A fresh session continues with the README PR, the host bring-up and the open decisions. This handoff lets it start without the old conversation. Read it, then read "Next steps".

## Goal

The owner wants a sandbox for AI agents (Claude Code, Qwen Code, Herdr, the TTT editor) that:

1. Is a hardened rootless Podman container with the `crun` runtime and a small memory footprint. The agent cannot change the sandbox.
2. Has `network none`. It has one way out: iron-proxy on the host. That proxy applies the egress allowlist and swaps the secrets.
3. Holds no real secret. The real tokens come from Bitwarden into the memory of the proxy.
4. Builds container images with `buildah`. The owner runs the images on the host or in CI.
5. Later: gives the egress proxy a SPIFFE identity (a JWT-SVID).

## Read these first (do not copy them here)

- The rules of the repo: `AGENTS.md`. Use Herdr worktrees. Write all text in Simplified Technical English (`/asd-ste100`). Before a PR, read `docs/agents/pull-requests.md`. Before a diagram, read `docs/agents/diagrams.md`.
- The merged sandbox: [`.sandbox/README.md`](../../.sandbox/README.md), [`.sandbox/justfile`](../../.sandbox/justfile) and [`.sandbox/image/`](../../.sandbox/image/).
- The merged host proxy: [`.sandbox/proxy/README.md`](../../.sandbox/proxy/README.md) and the three unit files in that folder.
- The bodies of #291 and #292. They hold the test evidence of the two PRs.
- The older handoffs [podman-krun-sandbox.md](podman-krun-sandbox.md) and [podman-plain-sandbox.md](podman-plain-sandbox.md), and the research note [`docs/research/podman-sandbox-runtimes.md`](../research/podman-sandbox-runtimes.md).

## The design as merged

| Part | Where it runs | Where it lives in the repo |
|---|---|---|
| The agent sandbox | A rootless Podman container, `crun`, `--network=none`, `--read-only`, `--cap-drop=ALL`, `no-new-privileges`, limits, tmpfs. The default seccomp profile of Podman applies. | `just sandbox run` in `.sandbox/justfile` |
| The build sandbox | A second container. It adds six capabilities for `buildah` and has a writable root. It has its own home volume. It sees the home of the agent read-only at `/src`. | `just sandbox build` |
| The home | One named volume, `sandbox-home`, at `/home/agent`. It holds the clone, the logins and the histories. | `.sandbox/justfile` |
| The relay | One `socat` in the container: `127.0.0.1:3128` to the Unix socket. | `.sandbox/image/sandbox-entry` |
| The socket and the bridge | Systemd user units on the host. `systemd-socket-proxyd` joins `$XDG_RUNTIME_DIR/sandbox/proxy.sock` to `127.0.0.1:18080`. | `.sandbox/proxy/sandbox-bridge.{socket,service}` |
| iron-proxy | A systemd user unit on the host. `bws run` gives it the real tokens. | `.sandbox/proxy/sandbox-proxy.service`, `iron-proxy.yaml` |

The commands are `just sandbox run` and `just sandbox build`. You make the image once with `podman build .sandbox/image -t localhost/sandbox-dev:latest`. You manage the host side with one-line `systemctl --user start|stop|restart sandbox-proxy` commands. The proxy ports are 127.0.0.1:18080 to 18084. The sandbox proxy reserves the range 18080 to 18089. The sandbox mounts only `ca.crt`, never `ca.key`.

## What the owner decided, in order

1. Use a plain hardened Podman container with `crun` and a host-side iron-proxy. The owner rejected the krun microVM as too complex and parked gVisor.
2. `network none` is a must. The proxy is the only route.
3. Keep Bitwarden (`bws run`) for the secrets. The owner ignored OpenBao.
4. The identity of the egress proxy is enough, like a sidecar. The gateway accepts a JWT.
5. No nested Podman in the sandbox. Builds use `buildah` in a separate build sandbox. Tier 2 builds run in CI. Tier 3 runs the image on the host.
6. The host proxy is plain systemd user units with fixed ports. No `justfile` module, no port variables, no CA bundle. The CA is one `openssl` command.
7. The Bitwarden access token is a systemd credential (`systemd-creds --user encrypt`), not a prompt. iron-proxy starts as `bws run -- env -u BWS_ACCESS_TOKEN iron-proxy`, so it does not hold the access token.
8. The binary of iron-proxy comes from `mise use -g github:ironsh/iron-proxy@0.56.0`.
9. The sandbox is a normal `podman run`, not Quadlet. Quadlet gave 14 files. The owner wants few files and short commands. The owner parked the seccomp profile and the self-test.
10. One home volume, and two plain commands, `run` and `build`, as separate containers.

## Options that the owner rejected or parked

Do not offer these again without a new reason.

| Option | State and reason |
|---|---|
| krun microVM, libkrun | Rejected. It works, but it has no `podman exec`, and it needs a relay on the host side. |
| gVisor (`runsc`) | Parked. `--network=none` gives no loopback in the guest, so the relay cannot start. |
| Quadlet for the sandbox | Rejected. Too many files. |
| Quadlet for iron-proxy | Not done. The tokens would reach the container as files on a tmpfs. The two bridge units stay. The gain is a digest-pinned image. |
| A builder container with an API gate | Rejected. The gate was a 285-line Python filter. |
| A pod with a shared network | Rejected. The agent and the builder share one network and one egress policy. |
| vsock, supervisord | Rejected. See the evidence below. |
| A custom seccomp profile, the egress self-test | Parked, not rejected. |

## Evidence to reuse

All of it ran on the host of the owner in this session, with dummy tokens.

| Fact | Test |
|---|---|
| Under krun, `--network=none` gives the guest no route to the host loopback. A host Unix socket in the guest gives `ECONNREFUSED`. `podman exec` fails with `the handler does not support exec`. | Direct tests. A relay that runs in the container network namespace after the start (`podman unshare nsenter --net=/proc/<pid>/ns/net socat ...`) reached a host socket. |
| `systemd-run --user -p IPAddressDeny=any` does nothing. The user manager logs `unit configures an IP firewall, but not running as root`. | A host process in such a scope reached `1.1.1.1`. |
| vsock is not usable. The modules are not loaded and `/dev/vsock` is missing. `socket(AF_VSOCK)` in the hardened container gives `EPERM`. | Direct test. |
| iron-proxy 0.56.0 listens on TCP only. `tunnel_listen: unix://...` fails with `listen tcp: ... unknown port`. | Direct test and the docs. No upstream issue exists. |
| A socket unit with `systemd-socket-proxyd` works. The socket file has mode 0600. The bridge starts at the first connection. You need `RemoveOnStop=yes`, because the file stays after a stop. | Tests with a stub proxy. |
| `systemd-creds --user encrypt` and `LoadCredentialEncrypted=` work in a user unit (systemd 262). The `.cred` file gets mode 0644, so run `chmod 0600`. | Tests with a dummy value. |
| Nested Podman in the hardened plain container fails in every set of flags. It works only with `SYS_ADMIN`, `unmask=ALL` and `no-new-privileges` off. | Nine flag sets. |
| `buildah` works in the hardened container with `CHOWN DAC_OVERRIDE FOWNER SYS_CHROOT SETUID SETGID`, `--isolation chroot` and `no-new-privileges` on. A `RUN` step works. The pull of `python:3.13-slim` through iron-proxy took 9 s. The image ran on the host. | The allowlist needed `registry-1.docker.io`, `auth.docker.io` and `production.cloudfront.docker.com`. |
| Chroot isolation needs a writable root. `podman images` and `podman push` panic in this container. `buildah` does not. | Direct tests. |
| A pod with an agent and a `SYS_ADMIN` builder works with `podman --remote` over a shared socket. | A tested prototype, rejected. |
| Under gVisor, nested Podman builds work with `allow-suid`, `ignore-cgroups`, `vfs` and the host network. The host socket works with `--host-uds=open`. | A tested prototype. The loopback problem is open. |
| The strict seccomp profile (without `unshare`, `mount` and the like) breaks `buildah`. | A test in #292. |
| The draw.io export makes SVG with `foreignObject` and `light-dark()` colors. The text disappears on a dark theme. | The SVG of #292 is hand-drawn from the `.drawio` coordinates, with plain `<text>`. |
| Anthropic's docs say `docker` and `podman` do not work in their sandbox. Excluded commands run outside it. Their secure deployment guide matches this design. Docker Sandboxes gives builds in a microVM with a private daemon. | Docs read. The Linux support of Docker Sandboxes is not verified. |

## What was not tested

- The real-token start. It needs the Bitwarden credential on the host.
- The merged units of #291 together with the merged sandbox. Tests used a stand-in bridge.
- The `iron-proxy` mise shim in a unit. The `bws` shim exists.
- An interactive Herdr session.
- The capabilities of the build sandbox and `mise run build` and `push` with the new image. The tests used the old image, which has no `buildah`.
- A push to a real registry, and `pip`, `npm` or `go` in a `RUN` step. The allowlist has the Go hosts.
- The migration command of #292 on the real volumes.

## Open decisions (ask the owner)

1. **The README PR.** The owner wants a better structure: prerequisites, getting started, the architecture with a draw.io diagram, the flow in mermaid, and the reasoning. See "Next steps".
2. **iron-proxy as a Quadlet container.** The owner mentioned it. My advice is no (see the table above). The owner has not decided.
3. **The upstream issue.** The draft asks iron-proxy for a Unix socket listener. It would remove the two bridge units. Nobody posted it.
4. **The JWT-SVID.** A host loop runs `spire-agent api fetch jwt` and writes a file. A `file` source with `ttl` in iron-proxy swaps it in. `spire-agent` is not on the host.
5. **The build sandbox access.** The build sandbox sees the home of the agent at `/src`, read-only. Remove that flag if the owner wants no access.
6. **PRs #284 and #287** and the branch `sandbox-plain`. The new design supersedes them. The older handoff says to close them only after the owner agrees.

## Next steps

Do them in this order. Ask the owner first which one to start.

1. **The README PR.** Use a Herdr worktree from `origin/main`. Rewrite `.sandbox/README.md` with the structure below. In the same PR, fix the stale sentence in `.sandbox/proxy/README.md`, section "How the sandbox uses it". It still says the sandbox is a Quadlet unit. Do it without subagents. Lint with `ste-lint.py`.
   - The structure, in this order:
     1. The summary.
     2. The architecture. Reuse `docs/diagrams/architecture.drawio`.
     3. Why the design looks like this.
     4. How a request leaves the sandbox, as a mermaid `sequenceDiagram`.
     5. The prerequisites, as a table with a check command for each row.
     6. Getting started from scratch, and daily use.
     7. The developer workflow, as a mermaid `flowchart` with three tiers.
     8. Hardening, limits, troubleshooting and files.
   - check: the lint shows 0 hard findings. A mermaid parser accepts both diagrams. The PNG labels read well.
2. **The host bring-up. The owner runs it.** Give the commands in one message after you push. Stop the old `sandbox` container and the transient units. Install the binaries with `mise`. Keep the CA. Make the credential. Link the units. Start the proxy. Build the image. Run `just sandbox run`. Copy the old volumes with the command in the body of #292.
   - check: `systemctl --user is-active sandbox-proxy` prints `active`. The socket shows `srw-------`. `just sandbox run claude --version` works.
3. **Real traffic, with real tokens (the owner runs it).** Test the Claude API with a long stream, a GitHub clone and push, `ghcr.io` and the Qwen endpoint. In the build sandbox, test `mise run build` and `push`, and `pip`, `npm` and `go` in a `RUN` step.
4. **Close #284 and #287** with a comment, after the owner agrees.
5. **The JWT-SVID loop** (open decision 4).
6. **Later:** the CI workflow for tier 2, a `CODEOWNERS` rule and a CI guard for `.sandbox/`, the custom seccomp profile, the egress self-test, a signed artifact.

## Lessons

- The owner wants few files and short commands. He objected to: a justfile module with shell-built ports, port placeholders, a CA bundle, 14 Quadlet files, and a long parameterized `_up` recipe. Keep recipes plain.
- Subagents ran 15 to 25 minutes on small tasks, and the owner objected. Do small work yourself. When you use a fork, give it size limits and a time box.
- Test only in a renamed copy with its own ports. Never touch the live `sandbox` container, the `sandbox-*` volumes or the `sandbox-proxy` and `sandbox-bridge` units.
- `ps | grep` with a pattern that is also in your own command line kills your shell. Use a pid, a port (`ss -ltnp`) or `systemctl`.
- `just --dry-run` prints `shell(...)` as text. Use `just --evaluate <name>` to see a value.
- The voice dictation of the owner is sometimes unclear. Ask when a tool name is new or odd.
- A short message in the middle of a run can change the direction. Stop forks that work on the old direction.
- The PR rules: the identity check, `git ls-remote` equals `git rev-parse`, `--base main`, an SVG image with the sha URL. Lint the PR body too.

## State of the host

These changes are outside the repo.

- The live `sandbox` container (up 17 hours) runs the old design from the branch `sandbox-plain`. Its image tag `localhost/sandbox-dev:latest` is from 2026-11-09 and has no `buildah`.
- Six old volumes hold the owner data: `sandbox-workspace`, `sandbox-claude-home`, `sandbox-qwen-home`, `sandbox-headroom-home`, `sandbox-herdr` and `sandbox-terraform-providers`. Two more volumes have hash names. I do not know their source.
- The old units `sandbox-proxy` and `sandbox-bridge` are transient `systemd-run` units. Their ports are 1080, 8081, 8443, 9091 and 15353. Their names clash with the new unit files.
- `~/.local/state/sandbox` has `ca.crt`, `ca.key`, `bin/` and `ssh/` (the folder `ssh/` is old). `~/.config/sandbox` does not exist. `mise` has `bws` and no iron-proxy shim.
- The host has `buildah`, `bwrap`, `crun` 1.30.1 and `runsc` (release 20261102.0, in `/usr/local/bin`). I did not re-check the Docker items of the older handoff.
- The worktrees `sandbox-iron-proxy`, `sandbox-podman-crun` and `sandbox-readme` are obsolete, because the owner merged the first two. Remove them with `herdr worktree remove`. The branch `sandbox-readme` is local only.
- The main checkout has four untracked files that you must **not** commit: `docs/handoff/agent-microsandbox-handoff.md`, `docs/handoff/agent-sandbox-iron-proxy-handoff.md`, `docs/research/msb-runtime-network-allowlist.md` and `docs/research/podman-gvisor-caddy-sandbox.md`. The two handoffs hold wrong claims. They say that `--network=none` with TSI reaches the host loopback. They say that `IPAddressDeny` in a user scope works and that `podman exec` works under krun. They say that a `bao:` pointer is a placeholder. The owner decides what to do with them.
- The scratch files of this session were in a temporary folder, including the gate prototype and the test scripts. Assume they are gone.
