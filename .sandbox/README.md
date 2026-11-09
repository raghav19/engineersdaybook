# The Podman sandbox

This folder will replace `.msb/`. The sandbox is a krun microVM that Rootless Podman starts. It runs Claude Code and the [TTT](https://github.com/eugenioenko/ttt) editor. The research note is `docs/research/podman-sandbox-runtimes.md`. The handoff is `docs/handoff/podman-krun-sandbox.md`.

**Status:** the image only. The compose file, the egress proxy, access to the sandbox and the signed artifact come in later changes. `.msb/` stays in use until the last of them.

## What is here

| Path | Content |
|---|---|
| `image/` | The image. It is the image of `.msb/image/` with the changes that krun needs. |
| `justfile` | The recipes `build` and `smoke`. |
| `AGENTS.md` | The rules for a change to the tools of the image. |

## Changes from `.msb/image/`

| Change | Reason |
|---|---|
| `sandbox-entry` replaces `sandbox-boot`. | krun has no `podman exec`. The entry runs as the command of the container, then drops to the user `agent`. |
| `sandbox-entry` mounts an ext4 image on `~/.local/share/containers`. | On the root filesystem of the guest (virtiofs), the overlay driver of nested Podman fails with "unable to create kernel-style whiteout". The setting `force_mask = "0700"` does not fix it in this image. Spike N1 calls this fix B. |
| The image has `e2fsprogs`. | `sandbox-entry` needs `mkfs.ext4`. |
| `TMPDIR=/dev/shm`. | Buildah fails with its temporary folder on virtiofs (spike N1). |
| `fuse-overlayfs` is not installed. | Native overlay works under krun. |
| The SPIRE agent is not installed. | A krun guest cannot reach the Workload API socket. The identity is an open decision. |
| The placeholder of the GitHub token is `$GH_TOKEN`. | The placeholder of msb (`$MSB_GH_TOKEN`) does not exist here. |

This change does not port the boot steps of `sandbox-boot` that need a clone, the network or a volume. These steps are the clone, `prek`, Headroom, the plugins of Claude Code and the layout of Herdr. They move with the compose file.

## Prerequisites

1. Install `podman`, `crun` with `+LIBKRUN`, `libkrun` and `libkrunfw`. The command `crun --version` must show `+LIBKRUN`.
2. Make the runtime name `krun`. Podman looks for `/usr/bin/krun`. One time for each host: `sudo ln -s crun /usr/bin/krun`.
3. Make sure that `/dev/kvm` is open for your user.

## Use

```shell
just sandbox build   # several minutes the first time
just sandbox smoke   # starts the microVM, then runs a nested container and a nested build as the user agent
```
