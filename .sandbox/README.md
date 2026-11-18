# Agent Sandbox

A sandbox for AI agents. It runs Claude Code, Qwen Code and the Fresh editor in a hardened rootless Podman container with gVisor. A second container, the builder, builds images for the agent.

## What it does

A coding agent reads text that you did not write. That text can hold a prompt injection, and a fooled agent runs commands with your rights. The sandbox limits what the agent can do, not what it chooses to do:

| Limit | What it does |
|---|---|
| No network | Each container has no route out. The only way out is a proxy on the host with an allowlist. |
| No real token | The agent sandbox holds placeholders. Only the host proxy holds the real tokens. |
| A private clone | The agent works on a clone of your repo. It cannot write to your repo. |
| A hardened container | gVisor, no capability, a read-only root file system and limits on memory, CPU and threads. |

## Architecture

[![Architecture of the hardened Podman sandbox](docs/diagrams/architecture.png)](docs/diagrams/architecture.svg)

For the parts, the flows, the controls and the limits, read [How the sandbox works in detail](docs/internals.md). The terms are in [The names](docs/internals.md#the-names).

## Prerequisites

This is a personal setup. Other people can use other tools.

What the setup assumes:

- The image registry is `ghcr.io`. The secret manager is Bitwarden Secrets Manager.
- The Bitwarden project holds `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `QWEN_API_KEY` and `GITHUB_TOKEN`. `GITHUB_TOKEN` has the scope `write:packages`.
- You have the access token of a machine account that reads that project. `just sandbox setup` asks for it. Do not paste it into a chat or a file.

For another registry or secret manager, change `agent/proxy/iron-proxy.yaml`, `agent/proxy/proxy.service` and the `build` recipe.

What the host needs:

| Need | Check |
|---|---|
| A Linux host with a systemd user manager | `systemctl --user is-system-running` |
| `systemd-creds` and `systemd-socket-proxyd`. The unit uses `/usr/lib/systemd/systemd-socket-proxyd`. | `command -v systemd-creds` and `ls /usr/lib/systemd/systemd-socket-proxyd` |
| `iron-proxy` and `bws`, from `mise install` | `iron-proxy --version` and `bws --version` |
| `openssl`, to make the CA | `openssl version` |
| `podman`, `runsc` and `git`. `just` stops if one is missing. | `podman --version` and `runsc --version` |
| `ip` and `nsenter`, to bring up the loopback of the container | `ip -V` and `nsenter --version` |
| `sudo` and `nft`, for the firewall rule | `sudo -v` and `nft --version` |
| 5 GB of free memory: 3 GB for the agent sandbox and 2 GB for the builder | `free -h` |
| Linger for your user (optional). The proxies keep running after you log out. | `loginctl enable-linger "$USER"` |

## Quick start

Run these steps in your main checkout.

1. Run `mise install`. It installs `bws` and `iron-proxy`.
2. Run these commands:

```shell
just sandbox setup   # install the proxies, the firewall rule and the container units
just sandbox build   # build the images and push the agent sandbox image to ghcr.io
just sandbox run     # start the builder and the agent sandbox, and open Herdr
```

`setup` asks for your `sudo` password. It asks for the Bitwarden access token only if the credential is missing or unreadable. Run `setup` again after you edit a file in `agent/`, `builder/` or `host/`.

For the commands of the proxy units and the firewall rule, read the [guide to the proxies](host/README.md).

## Commands

| Command | What it does |
|---|---|
| `just sandbox setup` | Installs both proxies, the firewall rule, the container units and the gVisor flags. |
| `just sandbox run` | Makes a new agent sandbox and a new builder. Opens Herdr. Add a command to run it in place of Herdr. |
| `just sandbox rm` | Removes the agent sandbox and the builder. The volume stays. |
| `just sandbox build` | Builds both images and pushes the agent sandbox image with the commit tag. `--no-cache` updates the pinned tools. |
| `podman ps` | Shows `(starting)`, `(healthy)` or `(unhealthy)`. |
| `podman logs -f sandbox-agent` | Follows the log of the agent sandbox. |

The volume `sandbox-home` keeps the clone, the logins and the histories.

## Build and push in the agent sandbox

[![Build and push in the agent sandbox](docs/diagrams/build-push.png)](docs/diagrams/build-push.svg)

1. Run `docker build` as on any host. A normal Dockerfile builds as it is. The agent sandbox has no Docker daemon, so the build writes a tar file:

   ```shell
   docker build -t ghcr.io/raghav19/<NAME>:<TAG> --output type=docker,dest=/tmp/image.tar .
   ```

2. Push the tar file with `crane`:

   ```shell
   crane push /tmp/image.tar ghcr.io/raghav19/<NAME>:<TAG>
   ```

Rules:

- `docker build`, `docker buildx build` and `docker buildx bake` work. Add `--output type=docker,dest=FILE`. One platform only.
- Without `--output`, the image stays in the cache of the builder.
- `--push`, `--load`, `docker push`, `run`, `images`, `tag` and `compose` fail. There is no daemon and no image store. Use `crane push`.
- A `FROM` or `RUN` step reaches only the hosts in `builder/proxy/iron-proxy.yaml`. An unlisted host gets `403`. To add a host, edit the file and run `just sandbox setup`.
- For a private base image, run `crane pull --format oci REF /tmp/base`. Then add `--build-context NAME=oci-layout:///tmp/base@sha256:DIGEST`.

## Troubleshooting

- **`run` says `proxy.sock` is missing.** Run `systemctl --user start sandbox-proxy`. After a start limit, run `systemctl --user reset-failed sandbox-proxy` first. Then run `just sandbox setup`.
- **`run` says `sandbox-builder-proxy/proxy.sock` is missing.** Run `systemctl --user start sandbox-builder-proxy`, or run `just sandbox setup`.
- **`run` says the agent sandbox is not healthy.** Run `podman logs sandbox-agent`.
- **`run` says the builder is not healthy.** Run `podman logs sandbox-builder`.
- **`docker build` says `failed to connect to the docker API`.** `DOCKER_CONFIG` and `BUILDX_BUILDER` are missing in your shell. Open a new session with `just sandbox run`.
- **A `FROM` or a `RUN` step gets `403`.** The host is not in `builder/proxy/iron-proxy.yaml`. Add it and run `just sandbox setup`.
- **`crane push` gets `403`.** The namespace is not `raghav19`.
- **`status sandbox-agent` shows `failed`.** A limit killed it. Run `just sandbox run`. The clone stays in the volume.
- **`status sandbox-builder` shows `failed` after `just sandbox rm`.** This is normal. `buildkitd` exits with code 1 when it stops.
- **A tool fails with a connection error.** The tool ignores `HTTPS_PROXY`.
- **You made a new CA.** Run `just sandbox run`.
