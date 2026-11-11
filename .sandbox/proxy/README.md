# The host proxy of the sandbox

iron-proxy runs on the host as a systemd user service. It is the only way out of the sandbox. It checks each request against an allowlist and replaces placeholders with real tokens. The sandbox has no network and holds no real token.

```text
sandbox (no network) -> relay -> proxy.sock -> sandbox-bridge -> iron-proxy (127.0.0.1:18080) -> allowed hosts
```

## Set up the proxy

Do these steps once. After you edit a file in this folder, run `just sandbox setup` again.

### What this setup assumes

This is a personal setup. Other people can use other tools. The guide assumes:

- The image registry is the GitHub Container Registry (`ghcr.io`).
- The secret manager is Bitwarden Secrets Manager.
- The secrets are already in a Bitwarden project: `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `QWEN_API_KEY` and `GITHUB_TOKEN`. `GITHUB_TOKEN` has the scope `write:packages`. `just sandbox build` uses it to push to `ghcr.io`. [Placeholders](#placeholders) shows which host each secret is for.
- You have the access token of a machine account that can read that project. `just sandbox setup` asks for it. Do not paste the token into a chat or a file.

For another registry or another secret manager, change `iron-proxy.yaml`, `sandbox-proxy.service` and the `build` recipe in `justfile`.

### Before you start

| Need | Why | Check |
|---|---|---|
| A Linux host with a systemd user manager | It runs the units and decrypts the credential. | `systemctl --user is-system-running` |
| `systemd-creds` and `systemd-socket-proxyd` (in the `systemd` package) | The credential and the bridge. The unit uses `/usr/lib/systemd/systemd-socket-proxyd`. Change the path if your distribution puts the file elsewhere. | `command -v systemd-creds` and `ls /usr/lib/systemd/systemd-socket-proxyd` |
| `iron-proxy` and `bws`, installed with `mise install` from `mise.toml` | The proxy and its secret loader. | `iron-proxy --version` and `bws --version` |
| `openssl` | It makes the CA. | `openssl version` |
| `podman`, `runsc` and `git` | `just` stops if one is missing. The proxy itself needs no Podman and no gVisor. | `podman --version` and `runsc --version` |
| `sudo` and `nft` | The firewall rule needs root once. See [The firewall rule](#the-firewall-rule). `just` stops if one is missing. | `sudo -v` and `nft --version` |
| Linger for your user (optional) | The proxy keeps running after you log out. | `loginctl enable-linger "$USER"` |

### Step 1: run the setup

Run this in your main checkout. The links of the units point to the files in this folder.

```bash
just sandbox setup
```

The recipe asks for your `sudo` password and for the access token. Nothing shows as you type. It does these steps and skips a step that is already done.

1. Links the `iron-proxy` and `bws` binaries into `~/.config/sandbox/bin`. The unit runs these links.
2. Makes the CA in `~/.local/state/sandbox`. An existing CA stays.
3. Links `iron-proxy.yaml` to `~/.config/sandbox/iron-proxy.yaml`.
4. Installs the firewall rule with `sudo`: it copies `sandbox-guard.nft` and `sandbox-guard.service` to `/etc` and starts the unit. If this step fails, the recipe stops and the proxy does not start.
5. Encrypts the access token with `systemd-creds` into `~/.config/credstore.encrypted/bws-token`. The unit loads it by name with `LoadCredentialEncrypted=bws-token`. It asks for the token only if the file is missing or cannot be read.
6. Links the three units, enables `sandbox-proxy.service` and restarts it.

The recipe ends with `The proxy runs.`

### Step 2: check the proxy

```bash
systemctl --user status sandbox-proxy.service sandbox-bridge.socket
ls "$XDG_RUNTIME_DIR/sandbox/proxy.sock"
```

The status shows `active`, and the socket file exists. Next, go to the [README of the sandbox](../README.md#install-and-use) and run `just sandbox build`, then `just sandbox run`.

If something fails, see [Troubleshooting](#troubleshooting).

## Ports

This proxy reserves the range **18080 to 18089 on 127.0.0.1**. The files use 18080 to 18084. The sandbox uses only the tunnel.

| Port | Listener |
|---|---|
| 18080 | tunnel (CONNECT) |
| 18081 | HTTP |
| 18082 | HTTPS |
| 18083 | metrics |
| 18084 | DNS |

## The firewall rule

A TCP or UDP port on `127.0.0.1` has no check of the user. Without a rule, any local user, and any program that reaches the loopback of the host, can connect to these ports. It can use the proxy and send the placeholders to get the real tokens.

`sandbox-guard.nft` is a rule of `nftables` for the five ports that `iron-proxy.yaml` uses, 18080 to 18084. It rejects every connection to those ports from a user other than yours. The spare ports 18085 to 18089 have no listener. If you add one, extend the range in the rule. The bridge runs as you, so it still connects.

- `just sandbox setup` replaces `@UID@` with your user id and copies the rule to `/etc/sandbox-guard.nft`. It copies `sandbox-guard.service` to `/etc/systemd/system/`. The unit loads the rule at each boot, before the network.
- The copies belong to root on purpose. A link to a file in your repo would let you change what root runs.
- The rule is its own table, `inet sandbox_guard`. It does not change `ufw` or another firewall.
- Check it with `sudo nft list table inet sandbox_guard` and `systemctl status sandbox-guard`.
- Turn it off with `sudo systemctl disable --now sandbox-guard`. Then delete `/etc/sandbox-guard.nft` and `/etc/systemd/system/sandbox-guard.service`.

What the rule does not do:

- It separates users. It does not separate programs of the same user. A rootless container of your user with `pasta` networking can connect to the host loopback as your user. The sandbox has `Network=none`, so it cannot. Do not give another container of your user a route to these ports.
- It does not guard `proxy.sock`. The folder `$XDG_RUNTIME_DIR` has the mode 0700 and guards the socket.
- Tests of the rule ran in a temporary network namespace. See the handoff `docs/handoff/podman-gvisor-sandbox.md`.

## Files

`iron-proxy.yaml` has the allowlist and the secret rules. `sandbox-proxy.service` starts iron-proxy with the real tokens from Bitwarden. `sandbox-bridge.socket` makes `$XDG_RUNTIME_DIR/sandbox/proxy.sock` (mode 0666, in a folder with mode 0711). `sandbox-bridge.service` joins the socket to the tunnel. `sandbox-guard.nft` and `sandbox-guard.service` install the firewall rule. They are copied to `/etc`, not linked.

## Why there is a bridge

The sandbox has no network, so only a Unix socket file can reach the host. iron-proxy listens on TCP only. `systemd-socket-proxyd` joins the socket to the tunnel. If iron-proxy later listens on a Unix socket, delete `sandbox-bridge.socket` and `sandbox-bridge.service` and set `tunnel_listen` to the socket path.

## How the sandbox uses it

`.sandbox/sandbox.container` defines the container, and `just sandbox run` starts it. `run` does not start the proxy. It stops if the proxy socket is missing. Start the proxy first with `systemctl --user start sandbox-proxy.service`. The container has `Network=none`. It mounts `$XDG_RUNTIME_DIR/sandbox` and `ca.crt`, and nothing else from this folder.

## Daily use

```bash
systemctl --user start sandbox-proxy.service     # starts the socket too
systemctl --user stop sandbox-proxy.service      # stops the socket and the bridge too
systemctl --user restart sandbox-proxy.service   # also after you edit iron-proxy.yaml
systemctl --user status sandbox-proxy.service sandbox-bridge.socket
journalctl --user -u sandbox-proxy -f             # the audit log: one JSON line for each request
```

systemd starts the bridge at the first connection, and the bridge starts the proxy. The first connection can fail while the proxy starts. The second one works.

## Placeholders

The sandbox holds the placeholder. The proxy replaces it in the `Authorization` header of a request to the hosts of its rule. Any other host gets 403 at the CONNECT. These values must equal the `proxy_value` lines in `iron-proxy.yaml`.

| Placeholder in the sandbox | Variable of the proxy | Hosts |
|---|---|---|
| `sandbox-placeholder-GH_TOKEN` | `GH_TOKEN` | `github.com`, `api.github.com`, `api.githubcopilot.com` |
| `sandbox-placeholder-CLAUDE_CODE_OAUTH_TOKEN` | `CLAUDE_CODE_OAUTH_TOKEN` | `api.anthropic.com` |
| `sandbox-placeholder-QWEN_API_KEY` | `QWEN_API_KEY` | `token-plan.ap-southeast-1.maas.aliyuncs.com` |
| `sandbox-placeholder-GHCR_PUSH_TOKEN` | `GITHUB_TOKEN` | `ghcr.io` |

## Hardening of the proxy unit

iron-proxy reads requests that the agent controls, and it holds the real tokens. If someone finds a bug in it, the attacker gets the rights of your user. The lines in `sandbox-proxy.service` limit what the proxy can do. The proxy runs as your user, so these lines do not give it a second account. They give the proxy only the powers that it needs.

Check the result with `systemd-analyze --user security sandbox-proxy.service`. A lower score is better.

| Directive | What it does | What it stops |
|---|---|---|
| `NoNewPrivileges=yes` | The proxy cannot gain rights through a setuid program. | A step from a bug to more rights. |
| `PrivateTmp=yes` | The proxy has its own `/tmp`. | Reading the temporary files of other programs. |
| `ProtectHome=tmpfs` | The proxy sees an empty `/home`. | Reading `~/.ssh`, other repos and browser data. |
| `BindReadOnlyPaths=` | Adds back only the files that the proxy needs, read-only. | Access to any other file. |
| `SystemCallFilter=@system-service` | The proxy can use only the system calls of a normal service. A system call is a request to the kernel. | `ptrace` (spy on a process), `mount`, loading a kernel module, `reboot` and `unshare`. Most kernel exploits use such calls. |
| `SystemCallArchitectures=native` | The proxy cannot make 32-bit calls on a 64-bit host. | A way around the filter. |
| `RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX` | The proxy can open only IPv4 sockets, IPv6 sockets and local (Unix) sockets. | Raw packet sockets (sniffing) and netlink sockets (a change of the network setup of the kernel). |
| `RestrictNamespaces=yes` | The proxy cannot make a namespace. A namespace is a private view of files, network or users. | Many exploits start with a new namespace. |
| `RestrictRealtime=yes` | The proxy cannot ask for real-time scheduling. | A real-time process runs before all normal processes. It can use a whole CPU core, so the desktop freezes. |
| `ProtectKernelTunables=yes`, `ProtectKernelModules=yes` | The proxy cannot write to `/proc/sys` and `/sys`. It cannot load kernel modules. | A change of the kernel settings. |
| `ProtectControlGroups=yes`, `ProtectClock=yes` | The proxy cannot change the control group tree or the clock. | A change of the system setup. |

The unit leaves out lines that do not lower the score of `systemd-analyze security`: `LockPersonality=`, `ProtectHostname=` and `UMask=`. It does not use `CapabilityBoundingSet=`, because a user unit has no capabilities. It does not use `MemoryDenyWriteExecute=`, because it can break programs that make code at run time.

The unit cannot restrict the network. `IPAddressDeny=` does nothing in a user unit, and the proxy must reach the internet. The allowlist in `iron-proxy.yaml` is the control. Treat that file as the most important file of the proxy.

### What the proxy sees in `/home`

| Path | Why |
|---|---|
| `~/.config/sandbox/iron-proxy.yaml` | The config. It is a link to the file in the repo. The bind gives the file that the link points to. |
| `~/.local/state/sandbox/ca.crt` and `ca.key` | The CA. |
| `~/.local/share/mise` | The installed tools. |
| `~/.config/sandbox/bin` | The links to `iron-proxy` and `bws`. |

If you point the config at another file, for example a `file` secret source, add a `BindReadOnlyPaths=` line for it in the unit.

### Troubleshooting

Run `journalctl --user -u sandbox-proxy` and look for the text in the first column. The first two rows come from `just`, not from the proxy.

| Text | Cause | Fix |
|---|---|---|
| `Failed to read encrypted credential data: Invalid argument` | `~/.config/credstore.encrypted/bws-token` holds the plain token. `systemd-creds` has no password. It reads only a file that `systemd-creds encrypt` made. | Run `just sandbox setup`. It finds that it cannot read the file and asks for the token again. |
| `just sandbox setup` stops at the firewall step | `sudo` refused the password, or `nft` could not load the rule. | Run `sudo -v`. Run `sudo nft -c -f /etc/sandbox-guard.nft` to check the file. Run `journalctl -u sandbox-guard`. Then run `just sandbox setup` again. |
| `just sandbox setup` fails at `systemctl --user link` | The old transient `systemd-run` units `sandbox-proxy` and `sandbox-bridge` have the same names. | Run `systemctl --user stop sandbox-proxy sandbox-bridge`. Run `just sandbox setup` again. |
| `Bad system call` | The proxy used a call that the filter bans. | Add the group that you need to `SystemCallFilter=`, for example `@network-io`. Keep the filter. |
| An address family error | The proxy needs a socket type that the list leaves out. | Add `AF_NETLINK` to `RestrictAddressFamilies=`. |
| `No such file or directory` for a path in `/home` | The path is not in a `BindReadOnlyPaths=` line. | Add a line for the path. |
| `No such file or directory` for `~/.config/sandbox/bin/bws` or `iron-proxy` | The links are missing or point to an old version. | Run `mise install`, then `just sandbox setup`. |

## Later

Not built yet. The gateway accepts a JWT. iron-proxy has no SPIFFE support and no upstream mTLS. A `file` source with a `ttl` can carry a JWT-SVID. A loop on the host would run `spire-agent api fetch jwt` and write the token to that file. The identity is then the identity of the proxy, not of one sandbox.
