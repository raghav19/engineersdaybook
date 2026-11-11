# The host proxy of the sandbox

iron-proxy runs on the host as a systemd user service. It is the only way out of the sandbox. It checks each request against an allowlist and replaces placeholders with real tokens. The sandbox has no network and holds no real token.

```text
sandbox (no network) -> relay -> proxy.sock -> sandbox-bridge -> iron-proxy (127.0.0.1:18080) -> allowed hosts
```

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

`iron-proxy.yaml` has the allowlist and the secret rules. `sandbox-proxy.service` starts iron-proxy with the real tokens from Bitwarden. `sandbox-bridge.socket` makes `$XDG_RUNTIME_DIR/sandbox/proxy.sock` (mode 0666, in a folder with mode 0711). `sandbox-bridge.service` joins the socket to the tunnel. Use the path of your main checkout for `$REPO` below.

## Why there is a bridge

The sandbox has no network, so only a Unix socket file can reach the host. iron-proxy 0.56.0 listens on TCP only. A `unix://` address in `tunnel_listen` fails with `listen tcp: ... unknown port`. `systemd-socket-proxyd` joins the socket to the tunnel. If iron-proxy later listens on a Unix socket itself, delete `sandbox-bridge.socket` and `sandbox-bridge.service` and set `tunnel_listen` to the socket path.

## How the sandbox uses it

`.sandbox/compose.yaml` defines the container, and `just sandbox run` starts it. `run` does not start the proxy. It stops with a message if the proxy socket is missing. Start the proxy first with `systemctl --user start sandbox-proxy.service`. The container has `network_mode: none`. It shares no network with the proxy. It mounts `$XDG_RUNTIME_DIR/sandbox` and `ca.crt`, and nothing else from this folder.

## Prerequisites

The proxy is iron-proxy and three systemd units. It needs **no Podman, no crun, no Docker and no socat**. `just sandbox build` and `just sandbox run` need Podman on the host. See the [README of the sandbox](../README.md).

| Need | Why | Check |
|---|---|---|
| A Linux host with a systemd user manager (tested with systemd 262) | It runs the units and decrypts the credential. | `systemctl --user is-system-running` |
| `systemd-creds` and `systemd-socket-proxyd` (in the `systemd` package) | The credential and the bridge. The unit uses `/usr/lib/systemd/systemd-socket-proxyd`. Change the path if your distribution puts the file elsewhere. | `command -v systemd-creds` and `ls /usr/lib/systemd/systemd-socket-proxyd` |
| `mise` | It installs iron-proxy and `bws`. | `mise --version` |
| `openssl` | It makes the CA. | `openssl version` |
| A Bitwarden Secrets Manager project and the access token of a machine account | The source of the real tokens. | Step 5 |
| Linger for your user (optional) | The proxy keeps running after you log out. | `loginctl enable-linger "$USER"`, then `loginctl show-user "$USER" -p Linger` |

You need `age` only if you keep the access token in an `age` file, as the `just msb` setup does.

## One-time setup

1. Make the folders: `mkdir -p ~/.local/state/sandbox ~/.config/sandbox`
2. Install the binaries. The iron-proxy releases have no signature, so the command pins the version.

   ```bash
   mise use -g github:ironsh/iron-proxy@0.56.0 bitwarden-secrets-manager
   ```

3. Make the CA. Skip this step if `ca.crt` and `ca.key` exist from the earlier setup. iron-proxy ends the TLS of every HTTPS call, so it can check the allowlist and replace the placeholder. The sandbox must trust this CA. The key never leaves the host. The sandbox gets only `ca.crt`, read-only.

   ```bash
   openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 365 \
     -subj '/CN=sandbox egress proxy CA' \
     -addext 'basicConstraints=critical,CA:TRUE,pathlen:0' \
     -addext 'keyUsage=critical,keyCertSign,cRLSign' \
     -keyout ~/.local/state/sandbox/ca.key -out ~/.local/state/sandbox/ca.crt \
     && chmod 0600 ~/.local/state/sandbox/ca.key && chmod 0644 ~/.local/state/sandbox/ca.crt
   ```

4. Link the config: `ln -s "$REPO/.sandbox/proxy/iron-proxy.yaml" ~/.config/sandbox/iron-proxy.yaml`
5. Prepare Bitwarden Secrets Manager in the Bitwarden web app. Make a project. Add one secret for each name in the column "Variable of the proxy" of the table below (`GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `QWEN_API_KEY`, `GITHUB_TOKEN`). `GITHUB_TOKEN` needs the scope `write:packages`, because `just sandbox build` uses it to push to `ghcr.io`. Make a machine account with read access to the project. Make an access token for it. Do not paste the token into a chat or a file.
6. Make the credential. You run this step. It asks for the token and shows nothing as you type.

   ```bash
   read -rsp 'Bitwarden access token: ' tok; echo
   printf '%s' "$tok" | systemd-creds --user encrypt --name=bws-token - ~/.config/sandbox/bws-token.cred
   unset tok; chmod 0600 ~/.config/sandbox/bws-token.cred
   ```

   If you keep the token in an `age` file, as the `just msb` setup does, use this pipe. `age` asks for your passphrase. Keep the file: `just msb` still uses it.

   ```bash
   age -d ~/.config/bws/access-token.age \
     | systemd-creds --user encrypt --name=bws-token - ~/.config/sandbox/bws-token.cred
   chmod 0600 ~/.config/sandbox/bws-token.cred
   ```

   Both commands are pipes, so they write no plaintext file. `systemd-creds` makes the `.cred` file with mode 0644, so you must run the `chmod`. A copy of the `.cred` file is useless on another machine. Code that runs as the same user here can decrypt it.

   Check the file. The command prints `ok` and does not show the token.

   ```bash
   systemd-creds --user decrypt --name=bws-token ~/.config/sandbox/bws-token.cred - >/dev/null && echo ok
   ```

   The error `Failed to read encrypted credential data: Invalid argument` means the file holds the plain token. `systemd-creds` has no password. Run the commands above again. Do not write the token into the file yourself. Only `systemd-creds encrypt` makes a file that `systemd-creds decrypt` can read.

7. Link and start the units:

   ```bash
   systemctl --user link "$REPO"/.sandbox/proxy/sandbox-{proxy.service,bridge.service,bridge.socket}
   systemctl --user enable --now sandbox-proxy.service
   ```

   The proxy unit starts the socket of the bridge (`Wants=`). You manage the proxy unit only. The socket has `PartOf=` the proxy, so a stop or a restart of the proxy reaches it.

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

Run `journalctl --user -u sandbox-proxy` and look for the text in the first column.

| Text | Cause | Fix |
|---|---|---|
| `Bad system call` | The proxy used a call that the filter bans. | Add the group that you need to `SystemCallFilter=`, for example `@network-io`. Keep the filter. |
| An address family error | The proxy needs a socket type that the list leaves out. | Add `AF_NETLINK` to `RestrictAddressFamilies=`. |
| `No such file or directory` for a path in `/home` | The path is not in a `BindReadOnlyPaths=` line. | Add a line for the path. |
| `mise ERROR No version is set for shim` | The tool is not in the global tool list. | Run `mise use -g github:ironsh/iron-proxy@0.56.0 bitwarden-secrets-manager` (step 2). |

## Migration from the running transient units

The running units are transient `systemd-run` units with the same names (`sandbox-proxy`, `sandbox-bridge`). They use the ports 1080, 8081, 8443, 9091 and 15353. The names clash with the new units. Run `systemctl --user stop sandbox-proxy sandbox-bridge` before step 7. Do not run the recipes of the old `sandbox-plain` branch next to the new units.

## Later

Not built yet. The gateway accepts a JWT. iron-proxy has no SPIFFE support and no upstream mTLS. A `file` source with a `ttl` can carry a JWT-SVID. A loop on the host would run `spire-agent api fetch jwt` and write the token to that file. The identity is then the identity of the proxy, not of one sandbox.
