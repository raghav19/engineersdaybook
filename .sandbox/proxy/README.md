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
| `mise` | It installs iron-proxy and `bws`. | `mise --version` |
| `openssl` | It makes the CA. | `openssl version` |
| `podman`, `podman-compose` and `git` | `just` stops if one is missing. The proxy itself needs no Podman. | `podman --version` |
| Linger for your user (optional) | The proxy keeps running after you log out. | `loginctl enable-linger "$USER"` |

### Step 1: run the setup

Run this in your main checkout. The links of the units point to the files in this folder.

```bash
just sandbox setup
```

The recipe asks for the access token. Nothing shows as you type. It does these steps and skips a step that is already done.

1. Installs iron-proxy and `bws` with `mise`.
2. Makes the CA in `~/.local/state/sandbox`. An existing CA stays.
3. Links `iron-proxy.yaml` to `~/.config/sandbox/iron-proxy.yaml`.
4. Encrypts the access token with `systemd-creds` into `~/.config/sandbox/bws-token.cred`. It asks for the token only if the file is missing or cannot be read.
5. Links the three units, enables `sandbox-proxy.service` and restarts it.

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

## Files

`iron-proxy.yaml` has the allowlist and the secret rules. `sandbox-proxy.service` starts iron-proxy with the real tokens from Bitwarden. `sandbox-bridge.socket` makes `$XDG_RUNTIME_DIR/sandbox/proxy.sock` (mode 0666, in a folder with mode 0711). `sandbox-bridge.service` joins the socket to the tunnel.

## Why there is a bridge

The sandbox has no network, so only a Unix socket file can reach the host. iron-proxy listens on TCP only. `systemd-socket-proxyd` joins the socket to the tunnel. If iron-proxy later listens on a Unix socket, delete `sandbox-bridge.socket` and `sandbox-bridge.service` and set `tunnel_listen` to the socket path.

## How the sandbox uses it

`.sandbox/compose.yaml` defines the container, and `just sandbox run` starts it. `run` does not start the proxy. It stops if the proxy socket is missing. Start the proxy first with `systemctl --user start sandbox-proxy.service`. The container has `network_mode: none`. It mounts `$XDG_RUNTIME_DIR/sandbox` and `ca.crt`, and nothing else from this folder.

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
| `RuntimeDirectory=` with `MISE_STATE_DIR` and `MISE_CACHE_DIR` | `mise` writes its state and cache to a folder that exists only while the proxy runs. | A `mise` error. `mise` cannot write to the empty `/home`. |
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
| `~/.local/share/mise` and `~/.config/mise` | The shims, the installed tools and the global tool list. |

If you point the config at another file, for example a `file` secret source, add a `BindReadOnlyPaths=` line for it in the unit.

### Troubleshooting

Run `journalctl --user -u sandbox-proxy` and look for the text in the first column. The first two rows come from `just`, not from the proxy.

| Text | Cause | Fix |
|---|---|---|
| `Failed to read encrypted credential data: Invalid argument` | `bws-token.cred` holds the plain token. `systemd-creds` has no password. It reads only a file that `systemd-creds encrypt` made. | Run `just sandbox setup`. It finds that it cannot read the file and asks for the token again. |
| `just sandbox setup` fails at `systemctl --user link` | The old transient `systemd-run` units `sandbox-proxy` and `sandbox-bridge` have the same names. | Run `systemctl --user stop sandbox-proxy sandbox-bridge`. Run `just sandbox setup` again. |
| `Bad system call` | The proxy used a call that the filter bans. | Add the group that you need to `SystemCallFilter=`, for example `@network-io`. Keep the filter. |
| An address family error | The proxy needs a socket type that the list leaves out. | Add `AF_NETLINK` to `RestrictAddressFamilies=`. |
| `No such file or directory` for a path in `/home` | The path is not in a `BindReadOnlyPaths=` line. | Add a line for the path. |
| `mise ERROR No version is set for shim` | The tool is not in the global tool list. | Run `just sandbox setup`. |

## Later

Not built yet. The gateway accepts a JWT. iron-proxy has no SPIFFE support and no upstream mTLS. A `file` source with a `ttl` can carry a JWT-SVID. A loop on the host would run `spire-agent api fetch jwt` and write the token to that file. The identity is then the identity of the proxy, not of one sandbox.
