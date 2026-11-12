# The Podman sandbox

A sandbox for AI agents. It runs Claude Code, Qwen Code and the TTT editor in a hardened rootless Podman container with gVisor.

## The problem and the solution

**The problem.** A coding agent reads text that you did not write: issues, web pages, packages and files. That text can hold a prompt injection. A fooled agent runs commands with your rights. It can read your tokens, send your data to an outside host or change files in your repo. The rules of a model do not stop this, because its defenses are not certain.

**The solution.** Limit what the agent can do, not what it chooses to do. The sandbox sets four limits:

- **No network.** The container has no route out. The only way out is a host proxy with an allowlist.
- **No real token.** The container holds placeholders. The proxy puts in the real token for the listed hosts only.
- **A private clone.** The agent works on a clone of your repo. It cannot write to your repo.
- **A hardened container.** gVisor, no capability, a read-only root file system and limits on memory, CPU and threads.

A fooled agent can use only what the sandbox allows.

## Quick start

Run these steps in your main checkout.

1. Read [what the setup assumes](proxy/README.md#what-this-setup-assumes). The registry is `ghcr.io`. The secret manager is Bitwarden Secrets Manager. The secrets already exist.
2. Run `mise install`. The host also needs `podman`, `runsc`, `git`, `openssl`, `systemd-creds`, `ip`, `nsenter`, `nft` and `sudo`.
3. Run these commands:

```shell
just sandbox setup   # install the host proxy, the firewall rule and the container unit
just sandbox build   # build the image and push it to ghcr.io (the first build takes several minutes)
just sandbox run     # start the container and open Herdr
```

`setup` asks for your `sudo` password and the Bitwarden access token. Run it again after you edit a file in `proxy/`, `runsc.conf` or `sandbox.container`.

## Commands

| Command | What it does |
|---|---|
| `just sandbox setup` | Installs the host proxy, the firewall rule, the container unit and the gVisor flags. |
| `just sandbox run` | Makes a new container from the image and opens Herdr. Add a command to run it in place of Herdr. |
| `just sandbox rm` | Stops the service and removes the container. The volume stays. |
| `just sandbox build` | Builds the image, tags it with the commit and pushes it. `just sandbox build --no-cache` updates the pinned tools. |
| `podman ps` | Shows `(starting)`, `(healthy)` or `(unhealthy)`. |
| `podman logs -f sandbox` | Follows the log of the container. |

The volume `sandbox-home` keeps the clone, the logins and the histories. Each `run` stops the processes of the old container.

## How it works

[![Architecture of the hardened Podman sandbox](docs/diagrams/architecture.png)](docs/diagrams/architecture.svg)

1. A tool sends its request to `HTTPS_PROXY` (`http://127.0.0.1:3128`).
2. `socat` in the container copies the bytes to the Unix socket `proxy.sock`.
3. On the host, `systemd-socket-proxyd` copies them to iron-proxy (`127.0.0.1:18080`).
4. iron-proxy checks the host. An unlisted host gets `403`. For a listed host, iron-proxy replaces each placeholder with the real token and sends the request.

For the details, see [How it works in detail](docs/internals.md).

## Security controls

Each row is one attack of an injected agent and the control that stops it.

| If the agent tries to | What stops it |
|---|---|
| Plant a git hook or a config change in your repo | The agent works in a clone, not in your checkout. The `.git` folder of your repo is a read-only mount. |
| Steal a token | The container holds placeholders. The real tokens stay on the host. |
| Send data to an unlisted host | The container has no network. The proxy answers `403` for a host that is not on the allowlist. |
| Break out of the container | gVisor, no capability, `no-new-privileges` and a user that is not root. |
| Use the proxy from another process | The firewall rule lets only your user connect to the proxy ports. |
| Move code to your host | The only way out is a `git push` to GitHub through the proxy. You read the branch before you check it out. |
| Use all memory, CPU or threads | The service limits. The kernel kills the sandbox, not the host. |

`sandbox.container` sets these controls.

| Control | What it does |
|---|---|
| `--runtime=runsc --network=none` | gVisor. The sentry runs the system calls of the agent. The container has an empty network namespace with the loopback interface only. |
| `--read-only` | The agent cannot write to `/etc`, `/usr`, `/opt/mise`, the policy of Claude Code or the CA. |
| tmpfs on `/tmp` and `/run` | Scratch space. A restart empties it. |
| The named volume `sandbox-home` at `/home/agent` | The clone, the logins and the histories stay here. The start script copies the home files of the image back at each start. |
| The repo in clone mode | The unit mounts the `.git` folder of your repo at `/run/sandbox/source`, read-only. At the first start, `sandbox-start` clones it to `/home/agent/engineersdaybook` in the volume. Git runs the hooks in `.git/hooks` and reads `.git/config` on the host, so a writable `.git` would let an injected agent plant code that runs on the host. The agent can change only its clone. The `origin` of the clone is the GitHub URL. |
| `--cap-drop=ALL` | The container has no capability. |
| `--security-opt no-new-privileges` | A setuid program cannot raise a privilege. |
| The default seccomp profile of Podman | A system call filter. Not tested under gVisor. gVisor has its own filter between the sentry and the host. |
| `User=agent` (uid 1000) | The container starts as `agent`, not as root. In rootless Podman, `agent` is a subuid, not your host user. The sentry and the gofer run as your host user. |
| `MemoryMax`, `MemorySwapMax`, `TasksMax`, `CPUQuota` in `[Service]` | 3 GB of memory with no swap, 2048 host threads, 4 CPUs. gVisor ignores the limits of Podman, so they are on the service. The kernel kills a sandbox that goes over a limit. |
| Read-only mounts | The CA, the proxy socket folder, the `.git` of the repo and the theme. |
| The nftables rule `proxy/sandbox-guard.nft` | Only your user may connect to the TCP ports 18080 to 18083 and the UDP port 18084 of the proxy, on `127.0.0.1`. It separates users, not programs of the same user. `just sandbox setup` installs it with `sudo`. |

## Limits

- No `podman`, `docker` or `buildah` in the sandbox. Build and run images on the host with `podman build`. Read a Containerfile before you build it, because a `RUN` step uses the network of the host and not the proxy.
- No SSH and no raw TCP. Use HTTPS remotes. A tool that ignores `HTTPS_PROXY` has no route.
- No `sudo` and no package install. Change the image.
- gVisor is not a microVM. A bug in the sentry gives an attacker your host user.
- The firewall rule separates users only. A rootless container of your user that has a route to the host loopback can still connect to the proxy ports.
- The clone starts on the current branch of your repo. Its git identity is `agent`. Set yours with `git config` in the clone.
- Listed hosts can receive data from the agent. Keep the allowlist short.
- A branch that the agent pushes can hold hooks or settings files. Read the diff before you check it out on the host.

## Troubleshooting

| Symptom | Action |
|---|---|
| `run` says `proxy.sock` is missing | Run `systemctl --user start sandbox-proxy`. |
| `run` says the container is not healthy | Run `podman logs sandbox`. |
| `systemctl --user status sandbox` shows `failed` | A limit killed the sandbox. Run `just sandbox run`. The clone stays in the volume. |
| A tool fails with a connection error | The tool ignores `HTTPS_PROXY` and has no route. |
| You made a new CA | Restart the sandbox with `just sandbox run`. |

## Files

| Path | Content |
|---|---|
| `sandbox.container` | The Quadlet unit: environment, hardening, mounts and limits. |
| `runsc.conf` | The gVisor flags for Podman. |
| `justfile` | The `setup`, `run`, `rm` and `build` recipes. |
| `image/` | The Dockerfile, `sandbox-entry`, `sandbox-start` and the `mise` tasks. |
| `proxy/` | The host proxy. See [`proxy/README.md`](proxy/README.md). |

## References

- Anthropic, [How we contain Claude across products](https://www.anthropic.com/engineering/how-we-contain-claude) (25 May 2026). Set hard limits in the environment first. Keep credentials out of the sandbox. Treat an allowlist as a grant of capability. Limit access to the repo.
- Simon Willison, [The lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/) (June 2025). An agent with private data, untrusted content and a way to send data out can leak the data.
