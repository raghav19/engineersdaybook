# The Podman sandbox

This folder will replace `.msb/`. The sandbox is a krun microVM that rootless Podman starts. It runs Claude Code and the [TTT](https://github.com/eugenioenko/ttt) editor. `crun` starts the microVM when the annotation `run.oci.handler=krun` is set. `krun` is not a separate program. The research note is `docs/research/podman-sandbox-runtimes.md`. The handoff is `docs/handoff/podman-krun-sandbox.md`.

**Status:** the image, the egress proxy and the compose file. The clone of the repo, the start of Claude Code in Herdr, the CI guard and the signed artifact come in later changes. `.msb/` stays in use until the last of them.

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
| `sandbox-entry` replaces `sandbox-boot`. | krun has no `podman exec`. The entry runs as the command of the container, then drops to the user `agent`. |
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
just sandbox run                      # builds the image, makes the CA, starts the proxy and the sandbox, opens Herdr as the user agent
just sandbox run claude --version     # runs one command in place of Herdr
just sandbox selftest                 # checks the wall with dummy tokens. No Bitwarden needed
just sandbox down                     # removes the containers and the networks
```

`run` asks for the passphrase of the Bitwarden token, as `just msb run` does. Quit Herdr to leave the sandbox. Run `just sandbox run bash --login -i` for a plain shell. The proxy keeps running until `just sandbox down`.

The clone of the repo and the start of Claude Code in Herdr come in a later change. Then `just sandbox run` is the one daily command.
