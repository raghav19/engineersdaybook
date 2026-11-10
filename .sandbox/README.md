# The Podman sandbox

A sandbox for AI agents. The agent runs in a hardened, rootless Podman container with the `crun` runtime. The container has no network. The only way out is iron-proxy on the host. It allows the listed hosts and swaps placeholders for real tokens. The container never holds a real token. The agent cannot change the sandbox.

**Status:** this folder replaces `.msb/` in steps. `.msb/` stays in use until you switch. The host proxy is in [`proxy/`](proxy/README.md). The CI workflow for tier 2 (see "Developer workflow") is not here yet.

| Path | Content |
|---|---|
| `quadlet/` | The Quadlet files: two containers, the volumes, the environment and the two seccomp profiles. |
| `egress-selftest.sh` | The self-test. It runs in the container as the user `agent`. |
| `image/` | The image, `sandbox-entry`, `sandbox-start` and the `mise` tasks. |
| `justfile` | `build`: builds the image. |

## Architecture

[![Architecture of the hardened Podman sandbox](docs/diagrams/architecture.png)](docs/diagrams/architecture.svg)

## How a request leaves the sandbox

1. A tool sends its request to `HTTPS_PROXY`, which is `http://127.0.0.1:3128`.
2. `sandbox-entry` starts one `socat` relay on that address. It copies the bytes to the Unix socket `/run/sandbox/proxy/proxy.sock`.
3. On the host, a systemd socket unit owns `proxy.sock`. `systemd-socket-proxyd` copies it to the tunnel port of iron-proxy (`127.0.0.1:18080`). There is no `socat` on the host.
4. iron-proxy ends the TLS with its own CA and checks the host. An unlisted host gets `403`. For a listed host, iron-proxy swaps each placeholder (`sandbox-placeholder-<NAME>`) for the real token and sends the request on.

**Why does `--network none` leave no route to the host?** The container has its own loopback interface, and nothing else. Its `127.0.0.1` is not the loopback of the host. Only a file crosses the wall: the socket in the mounted folder.

**Why a relay?** Tools need a TCP address for a proxy. The relay turns that address into the socket. It runs as container root, which is the host user who owns the socket. It has no capability. The agent user cannot open the socket.

**Why is the CA mounted and not installed?** The root file system is read-only, so `update-ca-certificates` cannot run. The unit mounts `~/.local/state/sandbox/ca.crt` read-only over `/etc/ssl/certs/ca-certificates.crt`. All HTTPS goes through the proxy, which ends the TLS with this CA, so the sandbox trusts this CA only. The unit never mounts `ca.key`. If you make a new CA, restart the sandbox.

**The host side:** the units are `sandbox-proxy.service`, `sandbox-bridge.socket` and `sandbox-bridge.service`. iron-proxy uses the ports 18080 to 18089 on `127.0.0.1`. See [`proxy/README.md`](proxy/README.md). `sandbox.service` has `Requires=sandbox-proxy.service`, so `systemctl --user start sandbox` starts the proxy and the socket first.

## Install and use

Quadlet reads the folder `~/.config/containers/systemd/` and makes the systemd units. Link the folder, then build the image and start the sandbox:

```shell
mkdir -p ~/.config/containers/systemd
ln -s "$PWD/.sandbox/quadlet" ~/.config/containers/systemd/sandbox
systemctl --user daemon-reload
just sandbox build                # the first build takes several minutes
systemctl --user start sandbox    # starts sandbox-proxy first
podman exec -it -u 0 sandbox sandbox-entry herdr
```

The container mounts `~/Projects/engineersdaybook/.git` read-only and clones it. Change the `Volume=` line in `sandbox.container` if your checkout is elsewhere. The clone has the git identity `agent`. Set yours with `git config` in the clone.

| Command | What it does |
|---|---|
| `podman exec -it -u 0 sandbox sandbox-entry herdr` | Opens Herdr. The entry drops to `agent`. Close the terminal and the sandbox keeps running. |
| `systemctl --user cat sandbox` | Shows the unit that Quadlet made. |
| `journalctl --user -u sandbox -f` | Follows the log. |
| `systemctl --user stop sandbox` | Stops and removes the container. The volumes stay. |
| `podman exec -i -u 0 sandbox sandbox-entry sh -s -- -a https://api.github.com/zen example.com < .sandbox/egress-selftest.sh` | Runs the self-test. The proxy must run. |

## Hardening

| Control | What it does |
|---|---|
| `runtime=crun`, `Network=none` | A small runtime. The container has the loopback interface only. |
| `ReadOnly=true` | The agent cannot write to `/etc`, `/usr`, `/opt/mise`, the policy of Claude Code or the CA. |
| tmpfs for `/tmp`, `/run` and `/home/agent` | Scratch space. A restart gives the agent a clean home. Only the named volumes keep data. |
| `DropCapability=ALL` | The entry drops the agent to an empty capability set. |
| `NoNewPrivileges=true` | A setuid program cannot raise a privilege. |
| `SeccompProfile=` | A system call filter. See below. |
| User `agent` (uid 1000) | Not root. |
| `PidsLimit`, `Memory`, `--cpus` | 1024 processes, 3 GB, 4 CPUs. |
| Read-only mounts | The CA, the proxy socket folder, the `.git` of the repo and the theme. |

The self-test proves the network and the read-only checks as `agent`. It prints 20 checks, PASS or FAIL.

### The seccomp profiles

`quadlet/seccomp.json` is `/usr/share/containers/seccomp.json` without these system calls: `ptrace`, `bpf`, `keyctl`, `add_key`, `request_key`, `userfaultfd`, `perf_event_open`, `io_uring_setup`, `io_uring_enter`, `io_uring_register`, `kexec_load`, `kexec_file_load`, `open_by_handle_at`, `unshare`, `setns`, `mount`, `umount2` and `pivot_root`. The default profile allows `ptrace`, `unshare`, `setns`, `mount`, `umount2`, `pivot_root` and `keyctl` with no condition.

`quadlet/seccomp-build.json` removes the same calls except `unshare`, `setns`, `mount`, `umount2` and `pivot_root`, because `buildah` needs a user namespace. To review or make the files again:

```shell
common='"ptrace","bpf","keyctl","add_key","request_key","userfaultfd","perf_event_open","io_uring_setup","io_uring_enter","io_uring_register","kexec_load","kexec_file_load","open_by_handle_at"'
make() { jq --argjson rm "[$1]" '.syscalls |= (map(.names -= $rm) | map(select(.names | length > 0)))' /usr/share/containers/seccomp.json; }
make "$common" > .sandbox/quadlet/seccomp-build.json
make "$common,\"unshare\",\"setns\",\"mount\",\"umount2\",\"pivot_root\"" > .sandbox/quadlet/seccomp.json
```

## Developer workflow

The sandbox has no container engine. A build makes an image. You run the image on the host or in CI.

```mermaid
flowchart TD
    A[Start the sandbox: systemctl --user start sandbox] --> B[Tier 1: edit and test in the sandbox]
    B --> C{Does the change need an image?}
    C -->|No| G[Push a feature branch with git]
    C -->|Yes| E[Start the build sandbox: systemctl --user start sandbox-build. It stops sandbox]
    E --> F[Build: mise run build -- -t name .]
    F --> H{Must you run the image?}
    H -->|Yes| I[Tier 3: save the image as an OCI archive in the workspace]
    I --> J[On the host: load the archive and run it with Podman]
    H -->|No| K[Push the image: mise run push -- name ghcr.io/owner/name:tag]
    J --> G
    K --> G
    G --> L[Tier 2: CI builds the image and runs the tests]
    L --> M{Do the checks pass?}
    M -->|Yes| N[Open the pull request]
    M -->|No| B
```

| Tier | Where | Work |
|---|---|---|
| 1 | The sandbox | Lint, render manifests, unit tests: `flux build`, `kubeconform`, `terraform validate`, `pytest`, `go test`. |
| 2 | CI | Build and test the image. The registry push token is not in the sandbox. |
| 3 | The host | Run a container to debug it. |

**Build and push.** `mise` tasks call `buildah`. They work in the build profile. Open its shell with `podman exec -it -u 0 sandbox-build sandbox-entry herdr`.

| Run | Docker command |
|---|---|
| `mise run build -- -t name .` | `docker build -t name .` (`buildah bud --isolation chroot`) |
| `mise run login` | `docker login ghcr.io`. The proxy swaps in the real token. |
| `mise run push -- name ghcr.io/owner/name:tag` | `docker push` |

A base image and every download in a `RUN` step go through the proxy, so their hosts must be on the allowlist. **Run the image on the host:** in the build sandbox, save it with `buildah push name oci-archive:/home/agent/engineersdaybook/name.tar:localhost/name:latest`. The workspace volume is that folder, so load it on the host from the volume:

```shell
podman unshare cat "$(podman volume inspect sandbox-workspace -f '{{.Mountpoint}}')/name.tar" | podman load
podman run --rm -p 8080:8080 localhost/name:latest
```

### What the build profile gives up

`sandbox-build` adds `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SYS_CHROOT`, `SETUID` and `SETGID` to the agent. It has no `SYS_ADMIN`. `buildah` needs them for chroot isolation. They let the agent ignore file permissions in the container and change to any user id, root too. Container root is your host user, but every host path in the container is read-only.

The root file system of `sandbox-build` is **writable**. `buildah` chroot isolation fails on a read-only root. The agent can change `/etc` and `/usr` in this container, and it loses the changes when the container stops. A `RUN` step runs with the authority of the agent. The two units conflict: starting one stops the other. Use the default sandbox when you do not build.

## What does not work

- **No `podman run`, no `docker`.** The sandbox has no engine. `buildah` builds and pushes.
- **No SSH and no raw TCP.** The proxy passes HTTP and TLS. Use HTTPS remotes for `git`.
- **A tool that ignores `HTTPS_PROXY` fails.** It has no route.
- **A tool that needs a user namespace or `ptrace` fails.** The seccomp profile denies them. A browser sandbox is an example.
- **No `sudo` and no package install.** The root file system is read-only. Change the image.
- **The agent runs as a sub-user of your host user.** The container shares the host kernel. A microVM is a stronger boundary.
- **Listed hosts can receive data from the agent.** Keep the allowlist short.
