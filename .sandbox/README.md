# The Podman sandbox

This folder will replace `.msb/`. The sandbox is a krun microVM that rootless Podman starts. It runs Claude Code and the [TTT](https://github.com/eugenioenko/ttt) editor. `crun` starts the microVM when the annotation `run.oci.handler=krun` is set. `krun` is not a separate program. The research note is `docs/research/podman-sandbox-runtimes.md`. The handoff is `docs/handoff/podman-krun-sandbox.md`.

**Status:** the image, the egress proxy, the compose file and the start of the sandbox. The CI guard, the signed artifact and the SPIFFE identity come in later changes. `.msb/` stays in use until the last of them.

## What is here

| Path | Content |
|---|---|
| `image/` | The image. It is the image of `.msb/image/` with the changes that krun needs. |
| `compose.yaml` | The sandbox (a krun microVM) and iron-proxy, its only way out. |
| `proxy/iron-proxy.yaml` | The allowlist of hosts and the secret swaps. It has placeholders and variable names, never a real value. |
| `egress-selftest.sh` | The egress self-test. It runs inside the sandbox. |
| `justfile` | The recipes `run`, `selftest`, `build`, `ca` and `down`. |
| `AGENTS.md` | The rules for a change to the tools of the image. |

## Changes from `.msb/image/`

| Change | Reason |
|---|---|
| `sandbox-entry` replaces `sandbox-boot`. | krun has no `podman exec`. The entry is the `ENTRYPOINT` of the image. It runs as root, then drops to the user `agent` and runs the command. The default command is `sandbox-start`. |
| `sandbox-entry` mounts an ext4 image on `~/.local/share/containers`. | The overlay driver of nested Podman cannot use the virtiofs disk of the microVM. A volume, a tmpfs and the `vfs` driver fail too. `force_mask` does not fix it. Spike N1 calls the ext4 image fix B. |
| `sandbox-entry` gives `/dev/net/tun` to the group `agent`. | Nested containers use pasta for the network, and pasta opens `/dev/net/tun`. |
| `sandbox-entry` runs `e2fsck -p` before it mounts the file, and mounts with `discard`. | The VM never unmounts the file system, so `e2fsck` checks it at each start. With `discard`, the file on the host shrinks when Podman removes data. Test: 300 MiB written and removed. The file went from 435 MiB to 135 MiB. |
| The image has `e2fsprogs`. | `sandbox-entry` needs `mkfs.ext4`. |
| `TMPDIR=/dev/shm`. | Buildah fails with its temporary folder on virtiofs (spike N1). |
| `fuse-overlayfs` is not installed. | Native overlay works under krun. |
| The SPIRE agent is not installed. | A krun guest cannot reach the Workload API socket. The identity is an open decision. |
| The placeholder of the GitHub token is `$GH_TOKEN`. | The placeholder of msb (`$MSB_GH_TOKEN`) does not exist here. |

This change does not port the boot steps of `sandbox-boot` that need a clone, the network or a volume. These steps are the clone, `prek`, Headroom, the plugins of Claude Code and the layout of Herdr. They move with the compose file.

## Prerequisites

1. Install `podman`, `crun` with `+LIBKRUN`, `libkrun` and `libkrunfw`. The command `crun --version` must show `+LIBKRUN`.
2. Install `podman-compose` (1.6.0 or newer), `openssl`, `bws` and `age`. Set up Bitwarden as in `.msb/README.md`, prerequisite 4. The project needs the keys `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `QWEN_API_KEY` and `GITHUB_TOKEN`.
3. Make sure that `/dev/kvm` is open for your user.

## How the network wall works

```text
sandbox (krun microVM)  --inner network, no route out-->  proxy  --outer network-->  internet
  placeholders only                                   real tokens, allowlist
```

- The sandbox is on the `inner` network. The network is internal, so the sandbox has no default route. All DNS goes to the proxy.
- The proxy ends the TLS with its own CA. `just sandbox ca` makes the CA. The key is a Podman secret that only the proxy gets. The sandbox gets the certificate, and `sandbox-entry` adds it to the trust store.
- A host that is not in `proxy/iron-proxy.yaml` gets 403. A placeholder that goes to a host of its rule becomes the real token. The real tokens come from Bitwarden into the environment of the proxy.
- The proxy passes HTTP and TLS only. Use https remotes for `git`.

## Use

```shell
just sandbox run                      # builds the image, makes the CA, starts the proxy and the sandbox, opens Herdr with Claude Code as the user agent
just sandbox run claude --version     # runs one command in place of the start script
just sandbox selftest                 # checks the wall with dummy tokens. No Bitwarden needed
just sandbox down                     # removes the containers and the networks
```

`run` asks for the passphrase of the Bitwarden token, as `just msb run` does. Quit Herdr to leave the sandbox. Run `just sandbox run bash --login -i` for a plain shell. The proxy keeps running until `just sandbox down`.

## What `run` starts

`sandbox-entry` and `sandbox-start` are two scripts because they need two users. The entry needs root (the loop mount, `/dev/net/tun` and the CA). The start script does the work of the user agent. The image runs them together: `sandbox-entry` is the `ENTRYPOINT`, and `sandbox-start` is the default command. `just sandbox run bash` replaces only the command, so the root steps still run first.

`sandbox-start` does these steps. Each step does nothing if its work exists.

1. It clones the host repo into `~/engineersdaybook`, on the branch of the host checkout. The source is the `.git` folder of the host repo, mounted read-only at `/run/sandbox/source`. The sandbox cannot change the host repo. The clone has `origin` set to GitHub, so a push goes to a feature branch. Only committed work reaches the clone.
2. It installs the `prek` hooks of the clone.
3. It starts Headroom on `127.0.0.1:8787`. The `.claude/settings.json` of the repo points Claude Code to it.
4. It installs the plugins of Claude Code. A failure prints a warning.
5. It starts the Herdr server in the background and waits until it answers. Krun has no `podman exec`, so the script cannot start Claude Code from outside. Then the script calls the Herdr API. It makes the workspace in the clone, splits it, and runs `claude` in the top pane. A restored layout keeps its panes, and the script runs `claude` in the first pane. Then it opens the Herdr client.

## Volumes

A volume stays after `just sandbox down`. Remove one with `podman volume rm`. `compose.yaml` gives each volume to the user agent with the volume option `uid=101000,gid=101000`. The ids are the ids of the host user namespace: 100000 (the start of the static map) plus 1000 (the user agent). A volume that exists before you change the option keeps its old owner. Remove it first.

| Volume | Folder in the sandbox | Content |
|---|---|---|
| `sandbox-workspace` | `~/engineersdaybook` | The clone. The work of the agent stays here. |
| `sandbox-claude-home` | `~/.claude` | The settings and the plugins of Claude Code. |
| `sandbox-qwen-home` | `~/.qwen` | The sessions of Qwen Code. |
| `sandbox-headroom-home` | `~/.headroom` | The history and the settings of Headroom. |
| `sandbox-herdr` | `~/.herdr` | The layout of Herdr. A new sandbox restores the panes. |
| `sandbox-terraform-providers` | `~/.cache/terraform-providers` | The Terraform provider cache. |
| `sandbox-state` | `/var/lib/sandbox` | The ext4 file with the images of nested Podman. |
