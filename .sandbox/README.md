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

## Quick start

Run these steps in your main checkout.

1. Read [what the setup assumes](host/README.md#what-this-setup-assumes). The registry is `ghcr.io`. The secret manager is Bitwarden Secrets Manager. The secrets already exist.
2. Run `mise install`. It installs `bws` and `iron-proxy`. The host also needs `podman`, `runsc`, `git`, `openssl`, `systemd-creds`, `systemd-socket-proxyd`, `ip`, `nsenter`, `nft` and `sudo`. The agent sandbox needs 3 GB of memory and the builder needs 2 GB.
3. Run these commands:

```shell
just sandbox setup   # install the proxies, the firewall rule and the container units
just sandbox build   # build the images and push the agent sandbox image to ghcr.io
just sandbox run     # start the builder and the agent sandbox, and open Herdr
```

`setup` asks for your `sudo` password. It asks for the Bitwarden access token only if the credential is missing or unreadable. Run `setup` again after you edit a file in `agent/`, `builder/` or `host/`.

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

Run `docker build` as on any host. A normal Dockerfile builds as it is. The agent sandbox has no Docker daemon, so the build writes a tar file, and `crane` pushes it.

```shell
docker build -t ghcr.io/raghav19/<NAME>:<TAG> --output type=docker,dest=/tmp/image.tar .
crane push /tmp/image.tar ghcr.io/raghav19/<NAME>:<TAG>
```

| Command | Result |
|---|---|
| `docker build`, `docker buildx build`, `docker buildx bake` | Work. Add `--output type=docker,dest=FILE`. One platform only. |
| `docker build --push`, `--load` | Fail. The builder holds no login, and there is no daemon. |
| `docker push`, `run`, `images`, `tag`, `compose` | Fail. There is no daemon and no image store. Use `crane push FILE REF`. |
| `docker build` without `--output` | The result stays in the cache of the builder. `docker` prints a warning. |

| Topic | Detail |
|---|---|
| Hosts | A `FROM` or `RUN` step reaches the `domains` of `builder/proxy/iron-proxy.yaml`. An unlisted host gets `403`. To add a host, edit the file and run `just sandbox setup`. |
| Push | `crane` uses the placeholder login of `ghcr.io`. The host proxy allows writes in the namespace `raghav19` only. |
| Private base image | Run `crane pull --format oci REF /tmp/base`. Then add `--build-context NAME=oci-layout:///tmp/base@sha256:DIGEST`. |
| Health | A failed health check of the builder at the start fails `run`. A later failure restarts the builder with an empty cache. |

## Troubleshooting

| Symptom | Action |
|---|---|
| `run` says `proxy.sock` is missing | Run `systemctl --user start sandbox-proxy`. After a start limit, run `systemctl --user reset-failed sandbox-proxy` first. Then run `just sandbox setup`. |
| `run` says `sandbox-builder-proxy/proxy.sock` is missing | Run `systemctl --user start sandbox-builder-proxy`, or run `just sandbox setup`. |
| `run` says the agent sandbox is not healthy | Run `podman logs sandbox-agent`. |
| `run` says the builder is not healthy | Run `podman logs sandbox-builder`. |
| `docker build` says `failed to connect to the docker API` | `DOCKER_CONFIG` and `BUILDX_BUILDER` are missing in your shell. Open a new session with `just sandbox run`. |
| A `FROM` or a `RUN` step gets `403` | The host is not in `builder/proxy/iron-proxy.yaml`. Add it and run `just sandbox setup`. |
| `crane push` gets `403` | The namespace is not `raghav19`. |
| `status sandbox-agent` shows `failed` | A limit killed it. Run `just sandbox run`. The clone stays in the volume. |
| `status sandbox-builder` shows `failed` after `just sandbox rm` | Normal. `buildkitd` exits with code 1 when it stops. |
| A tool fails with a connection error | The tool ignores `HTTPS_PROXY`. |
| You made a new CA | Run `just sandbox run`. |

## Files

| Path | Content |
|---|---|
| `agent/` | The agent sandbox: the unit `sandbox-agent.container`, `runsc.conf`, `image/` and `proxy/` (the host proxy and its bridge). |
| `builder/` | The builder: the unit `sandbox-builder.container`, `runsc.conf`, `image/` (the `Containerfile` and `relay-entry`) and `proxy/` (the builder proxy and its bridge). |
| `host/` | The firewall rule for both proxies and the [guide to set up the proxies](host/README.md). |
| `docs/` | [How the sandbox works in detail](docs/internals.md) and the diagrams. |
| `justfile` | The recipes `setup`, `run`, `rm` and `build`. |
