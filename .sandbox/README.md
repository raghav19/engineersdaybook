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
2. Install `podman-compose` (1.6.0 or newer), `openssl`, `ssh`, `bws` and `age`. Set up Bitwarden as in `.msb/README.md`, prerequisite 4. The project needs the keys `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `QWEN_API_KEY` and `GITHUB_TOKEN`.
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
just sandbox run                      # builds the image, makes the CA and the ssh key, starts the proxy and the sandbox if they do not run, opens Herdr over ssh
just sandbox run claude --version     # runs one command over ssh in place of Herdr
just sandbox selftest                 # checks the wall with dummy tokens. No Bitwarden needed
just sandbox down                     # removes the containers and the networks. The volumes stay
```

The sandbox works as the msb VM does. `run` starts it once and asks for the passphrase of the Bitwarden token. Close the terminal and the sandbox keeps running, with Herdr and Claude Code in it. Run `just sandbox run` again to get the same Herdr session at once, with no passphrase. `just sandbox down` stops the sandbox. The next `run` makes a new sandbox, and Herdr restores its layout from the volume. A restored pane has a shell, and you start Claude Code again, as Herdr does not restart agents. In the first Herdr session, run `claude` in the pane. Run `just sandbox run bash -l` for a plain shell.

## Resume a session

The history of each agent is in a volume, and a volume is a folder on the host (`podman volume inspect <name>`). It stays after `just sandbox down` and after a new container. Claude Code keeps its sessions by working folder, and the clone is always `~/engineersdaybook`, so a new sandbox finds them. Start the agent again in the pane. Herdr restores the pane with a shell and does not restart agents.

| Agent | Resume the newest session | Pick a session | Volume |
|---|---|---|---|
| Claude Code | `claude --continue` | `claude --resume` | `sandbox-claude-home` |
| Qwen Code | `qwen -c` | `qwen --resume` | `sandbox-qwen-home` |

Test: a file in `~/.claude/projects` and in `~/.qwen` was still there after `down` and a new `run`. The volume folder belongs to a mapped user id, so read it from the host with `podman unshare ls <folder>`. `just sandbox run` runs one command (`exec <command>`), so give it one command and no `&&`.

## How you get in

Krun has no `podman exec`, so the sandbox has an `sshd`. The msb VM has none, because the `msb` command on the host is its SSH server. Here:

- `sandbox-entry` starts `sshd` as root. It listens on port 2222 in the sandbox. Port 22 needs a capability that the sandbox does not have.
- `compose.yaml` publishes the port on `127.0.0.1:2222` of the host only. The sandbox network stays internal, so the port adds no way out. A published port works on an internal network (test: HTTP 200 from the host).
- Only the key `~/.local/state/sandbox/ssh/id_ed25519` can log in, and only as the user agent. `just sandbox run` makes the key pair. The sandbox gets the public part, read-only. No password, no root, no port forwarding.
- The server key of `sshd` is new for each container. `sandbox-entry` runs `ssh-keygen -A`, which makes a missing key. The image has no server key (the Dockerfile removes the one that the package makes), so two sandboxes never share one. The ssh command does not check the server key, as the msb ssh config does, because the connection is a port on your loopback.
- An ssh session does not inherit the environment of the container. `sandbox-entry` writes the environment to `/etc/environment`, so a session has the placeholders, `NODE_OPTIONS`, the workspace path and the other values. A session has no capability (`CapEff` is 0).

## What `run` starts

`sandbox-entry` and `sandbox-start` are two scripts because they need two users. The entry needs root (the loop mount, `/dev/net/tun`, the CA and `sshd`). The start script does the work of the user agent. The image runs them together: `sandbox-entry` is the `ENTRYPOINT`, and `sandbox-start` is the default command. `just sandbox run bash` replaces only the command that `ssh` runs.

`sandbox-start` does these steps. Each step does nothing if its work exists.

1. It clones the host repo into `~/engineersdaybook`, on the branch of the host checkout. The source is the `.git` folder of the host repo, mounted read-only at `/run/sandbox/source`. The sandbox cannot change the host repo. The clone has `origin` set to GitHub, so a push goes to a feature branch. Only committed work reaches the clone.
2. It installs the `prek` hooks of the clone.
3. It starts Headroom on `127.0.0.1:8787`. The `.claude/settings.json` of the repo points Claude Code to it.
4. It installs the plugins of Claude Code. A failure prints a warning.
5. It links the Herdr session files to the volume, writes `/tmp/sandbox-ready` and waits. `run` waits for this file, then opens Herdr with `ssh -t`.

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
