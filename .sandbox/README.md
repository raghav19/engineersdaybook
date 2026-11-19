# Agent Sandbox

A sandbox for AI agents. It runs Claude Code, Qwen Code and the Fresh editor in a hardened rootless Podman container with gVisor. A second container, the builder, builds images for the agent.

## The problem

You let a coding agent work on your repository. The agent has three abilities. They are dangerous together:

- **Untrusted content.** The agent reads text that you did not write: web pages, issues, packages and code.
- **Private data.** The agent reaches your repository, your files and your tokens.
- **Outside communication.** The agent can send data out with a `git push`, an API call or a web request.

A prompt injection hides an instruction in the text that the agent reads. A fooled agent then runs commands with your rights. It can send your private data to an attacker. Simon Willison calls this combination the [lethal trifecta](https://simonwillison.net/2025/Jun/16/the-lethal-trifecta/). A filter that stops most attacks is not enough, because one missed attack is enough.

You cannot remove the first ability, because the agent must read. You cannot remove all outside communication, because the agent must work. In this repository the agent must:

- clone, commit and push to GitHub
- call the APIs of the models (Claude and Qwen), which need tokens
- install tools and read documentation
- build container images, with no Docker daemon and no root on your host

The sandbox must run on one Linux machine with rootless Podman. It must start with one command.

## The solution

The sandbox keeps the agent useful and limits what a fooled agent can do. It has one step for each ability:

| Ability | What the sandbox does |
|---|---|
| Private data | The agent works in a private clone. It holds placeholders, not real tokens. The real tokens stay in the proxy. |
| Untrusted content | The sandbox cannot stop it, because the agent must read. The other two steps limit the damage. |
| Outside communication | The agent has no network device. The only way out is a file that leads to a proxy. The proxy allows listed hosts, methods and paths only. |

Builds follow the same model. A second container, the builder, runs the build steps. It has no token, no network device and its own proxy.

The [sandbox of Claude Code](https://www.anthropic.com/engineering/claude-code-sandboxing) uses the same idea. Internet access goes only through a socket to a proxy outside the sandbox. That proxy enforces approved domains.

## What is out of scope

The sandbox limits what a fooled agent can do. Other layers handle the rest. These risks are out of scope:

| Risk | Who handles it |
|---|---|
| A prompt injection changes what the agent tries to do | The model and the client. The sandbox limits only the damage. |
| A tool of the MCP server writes outside this repository | The central MCP gateway. The proxy does not read MCP calls. |
| A write goes to `main` | Branch protection on GitHub. A rule in the proxy cannot see the branch. |
| A token has more scope than the agent needs | The scope of the token. Use a fine-grained token for one repository. |
| A pushed branch holds bad code | You. Read the diff before you merge or check it out. |
| Data leaves through a listed host | The allowlists. Keep them short. |

The sandbox has two limits of its own:

- The proxy reads every request of the agent. A bug in the proxy can expose the real tokens.
- gVisor is not a microVM. A bug in gVisor can give an attacker your host user.

## Architecture

[![Architecture of the hardened Podman sandbox](docs/diagrams/architecture.png)](docs/diagrams/architecture.svg)

The allowed hosts are in `agent/proxy/iron-proxy.yaml` and `builder/proxy/iron-proxy.yaml`. For the parts and the flows, read [How the sandbox works in detail](docs/internals.md).

## Security controls

The baseline is rootless Podman and limits on memory and threads for every container. The agent sandbox also has a user that is not root, no capability, `no-new-privileges` and a read-only root file system. The proxies have the same, except the user. The builder keeps three capabilities and has no `no-new-privileges`, because `rootlesskit` needs them. An agent needs more. These controls are specific to a sandbox for an agent:

| Control | What it stops |
|---|---|
| No network device in the agent sandbox and the builder | A tool or a build step that ignores the proxy settings has no route out. |
| One way out: a socket to a proxy container | The agent reaches only the tunnel port of the proxy. It cannot see the files, the process or the other ports of the proxy. |
| Placeholders in the agent, real tokens in the proxy | A fooled agent cannot read a token. The proxy swaps a token in for the listed hosts only. |
| Tokens outside the Podman storage | The proxy reads a systemd credential. The real tokens are in memory only while a session runs. |
| Rules for the host, the method and the path | A write goes to one GitHub repository and one `ghcr.io` namespace. A merge, a file removal, a gist, a fork and GraphQL get `403`. |
| gVisor for the agent sandbox and the builder | A system call of a hostile command reaches gVisor, not the host kernel. |
| A private clone, with your `.git` mounted read-only | The agent cannot plant a git hook or change your repository. A push goes to GitHub, and you read the branch. |
| A separate builder for build steps | A `RUN` step runs as root in a container with no token and no network device. The agent has no Docker daemon. |
| Read-only policy: `/etc/docker` and the managed settings | The agent cannot add a builder, change the endpoint or edit its own policy. |
| A new builder and new proxies for each session | The cache and the tokens in memory end with the session. |
| An audit log in the proxy | Each request is one JSON line in `journalctl --user -u sandbox-proxy`. |

## Prerequisites

This is a personal setup. Other people can use other tools.

What the setup assumes:

- The image registry is `ghcr.io`. The secret manager is Bitwarden Secrets Manager.
- The Bitwarden project holds `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `QWEN_API_KEY` and `GITHUB_TOKEN`. `GITHUB_TOKEN` has the scope `write:packages`.
- You have the access token of a machine account that reads that project. `just sandbox setup` asks for it. Do not paste it into a chat or a file.

For another registry or secret manager, change `agent/proxy/iron-proxy.yaml`, `agent/proxy/proxy.container` and the `build` recipe.

What the host needs:

| Need | Check |
|---|---|
| A Linux host with a systemd user manager | `systemctl --user is-system-running` |
| `systemd-creds`, to keep the Bitwarden access token | `command -v systemd-creds` |
| `bws`, from `mise install`. `build` uses it to log in to `ghcr.io`. | `bws --version` |
| `openssl`, to make the CA | `openssl version` |
| `podman`, `runsc` and `git`. `just` stops if one is missing. | `podman --version` and `runsc --version` |
| `ip` and `nsenter`, to bring up the loopback of the container | `ip -V` and `nsenter --version` |
| 6 GB of free memory: 3 GB for the agent sandbox, 2 GB for the builder and less than 1 GB for the two proxies | `free -h` |
| Linger for your user (optional). The sandbox keeps running after you log out. | `loginctl enable-linger "$USER"` |

## Quick start

Run these steps in your main checkout.

1. Run `mise install`. It installs `bws`.
2. Run these commands:

```shell
just sandbox setup   # make the CA and the credential, and link the container units
just sandbox build   # build the four images and push the agent sandbox image to ghcr.io
just sandbox run     # start the proxies, the builder and the agent sandbox, and open Herdr
```

`setup` needs no root. It asks for the Bitwarden access token only if the credential is missing or unreadable. Run `setup` again after you edit a file in `agent/` or `builder/`.

`podman ps` then shows four containers: `sandbox-proxy`, `sandbox-builder-proxy`, `sandbox-builder` and `sandbox-agent`. Each unit starts the next one, so you start no proxy by hand.

## Commands

| Command | What it does |
|---|---|
| `just sandbox setup` | Makes the CA and the credential. Links the container units and the gVisor flags. |
| `just sandbox run` | Makes a new agent sandbox, a new builder and two new proxies. Opens Herdr. Add a command to run it in place of Herdr. |
| `just sandbox rm` | Removes the agent sandbox, the builder and both proxies. The volume stays. |
| `just sandbox build` | Builds the four images and pushes the agent sandbox image with the commit tag. `--no-cache` updates the pinned tools. |
| `podman ps` | Shows `(starting)`, `(healthy)` or `(unhealthy)`. |
| `podman logs -f sandbox-agent` | Follows the log of the agent sandbox. |
| `journalctl --user -u sandbox-proxy -f` | Follows the audit log of the host proxy: one JSON line for each request. |
| `podman logs -f sandbox-builder-proxy` | Follows the log of the builder proxy. |

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

- **`run` fails at the start.** A failed step of a unit fails the start. Run `journalctl --user -u sandbox-proxy -u sandbox-builder-proxy -u sandbox-builder`. If the image is missing, run `just sandbox build`.
- **`run` says that the credential is missing.** Run `just sandbox setup`.
- **`Failed to read encrypted credential data: Invalid argument`.** `bws-token` holds the plain token. Run `just sandbox setup`. It asks for the token again.
- **`podman logs sandbox-proxy` shows a Bitwarden error.** The access token is wrong or expired. Remove `~/.config/credstore.encrypted/bws-token`, then run `just sandbox setup`.
- **`run` says the agent sandbox is not healthy.** Run `podman logs sandbox-agent`.
- **`run` says the builder is not healthy.** Run `podman logs sandbox-builder`.
- **`docker build` says `failed to connect to the docker API`.** `DOCKER_CONFIG` and `BUILDX_BUILDER` are missing in your shell. Open a new session with `just sandbox run`.
- **A `FROM` or a `RUN` step gets `403`.** The host is not in `builder/proxy/iron-proxy.yaml`. Add it and run `just sandbox setup`.
- **`crane push` gets `403`.** The namespace is not `raghav19`.
- **A GitHub call gets `403`.** The host proxy allows a push to `raghav19/engineersdaybook` and a REST write on its issues and pull requests. It denies a merge, a file write, a removal and GraphQL. To change this, edit `agent/proxy/iron-proxy.yaml` and run `just sandbox run`.
- **`status sandbox-agent` shows `failed`.** A limit killed it. Run `just sandbox run`. The clone stays in the volume.
- **`status sandbox-builder` shows `failed` after `just sandbox rm`.** This is normal. `buildkitd` exits with code 1 when it stops.
- **`run` stops at a `Credential` error of the proxy.** The file `~/.config/credstore.encrypted/bws-token` is missing or unreadable. Run `just sandbox setup`.
- **A tool fails with a connection error.** The tool ignores `HTTPS_PROXY`.
- **You made a new CA.** Run `just sandbox run`.
