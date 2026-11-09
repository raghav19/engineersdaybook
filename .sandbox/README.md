# The Podman sandbox

This folder will replace `.msb/`. The sandbox is a krun microVM that rootless Podman starts. It runs Claude Code and the [TTT](https://github.com/eugenioenko/ttt) editor. `crun` starts the microVM when the annotation `run.oci.handler=krun` is set. `krun` is not a separate program. The research note is `docs/research/podman-sandbox-runtimes.md`. The handoff is `docs/handoff/podman-krun-sandbox.md`.

**Status:** the image only. The compose file, the egress proxy, access to the sandbox and the signed artifact come in later changes. `.msb/` stays in use until the last of them.

## What is here

| Path | Content |
|---|---|
| `image/` | The image. It is the image of `.msb/image/` with the changes that krun needs. |
| `justfile` | The recipes `build` and `run`. |
| `AGENTS.md` | The rules for a change to the tools of the image. |

## Changes from `.msb/image/`

| Change | Reason |
|---|---|
| `sandbox-entry` replaces `sandbox-boot`. | krun has no `podman exec`. The entry runs as the command of the container, then drops to the user `agent`. |
| `sandbox-entry` mounts an ext4 image on `~/.local/share/containers`. | The overlay driver of nested Podman cannot use the virtiofs disk of the microVM. A volume, a tmpfs and the `vfs` driver fail too. `force_mask` does not fix it. Spike N1 calls the ext4 image fix B. |
| `sandbox-entry` gives `/dev/net/tun` to the group `agent`. | Nested containers use pasta for the network, and pasta opens `/dev/net/tun`. |
| The image has `e2fsprogs`. | `sandbox-entry` needs `mkfs.ext4`. |
| `TMPDIR=/dev/shm`. | Buildah fails with its temporary folder on virtiofs (spike N1). |
| `fuse-overlayfs` is not installed. | Native overlay works under krun. |
| The SPIRE agent is not installed. | A krun guest cannot reach the Workload API socket. The identity is an open decision. |
| The placeholder of the GitHub token is `$GH_TOKEN`. | The placeholder of msb (`$MSB_GH_TOKEN`) does not exist here. |

This change does not port the boot steps of `sandbox-boot` that need a clone, the network or a volume. These steps are the clone, `prek`, Headroom, the plugins of Claude Code and the layout of Herdr. They move with the compose file.

## Prerequisites

1. Install `podman`, `crun` with `+LIBKRUN`, `libkrun` and `libkrunfw`. The command `crun --version` must show `+LIBKRUN`.
2. Make sure that `/dev/kvm` is open for your user.

## Use

```shell
just sandbox run                      # builds the image, starts the microVM and opens Herdr as the user agent
just sandbox run claude --version     # runs one command in place of Herdr
```

`run` builds the image first. The first build takes several minutes. Quit Herdr to stop the sandbox. Run `just sandbox run bash --login -i` for a plain shell. In this change the sandbox uses the network of the host, and `claude` has no token. The egress proxy, the token placeholders, the clone of the repo and the start of Claude Code and Herdr come in later changes. Then `just sandbox run` is the one daily command.
