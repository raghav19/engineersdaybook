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

`iron-proxy.yaml` has the allowlist and the secret rules. `sandbox-proxy.service` starts iron-proxy with the real tokens from Bitwarden. `sandbox-bridge.socket` makes `$XDG_RUNTIME_DIR/sandbox/proxy.sock` (mode 0600). `sandbox-bridge.service` joins the socket to the tunnel. Use the path of your main checkout for `$REPO` below.

## Why there is a bridge

The sandbox has no network, so only a Unix socket file can reach the host. iron-proxy 0.56.0 listens on TCP only. A `unix://` address in `tunnel_listen` fails with `listen tcp: ... unknown port`. `systemd-socket-proxyd` joins the socket to the tunnel. If iron-proxy later listens on a Unix socket itself, delete `sandbox-bridge.socket` and `sandbox-bridge.service` and set `tunnel_listen` to the socket path.

## How the sandbox uses it

The sandbox PR declares the container as a Podman Quadlet unit with `Requires=sandbox-proxy.service`. `systemctl --user start sandbox` then starts the proxy, the socket and the container in this order. The container has `Network=none`. It shares no network with the proxy. It mounts `$XDG_RUNTIME_DIR/sandbox` and `ca.crt`, and nothing else from this folder.

## Prerequisites

The host runs only iron-proxy and three systemd units. It needs **no Podman, no crun, no Docker and no socat**. These belong to the sandbox PR. See its README.

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
5. Prepare Bitwarden Secrets Manager in the Bitwarden web app. Make a project. Add one secret for each name in the column "Variable of the proxy" of the table below (`GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `QWEN_API_KEY`, `GITHUB_TOKEN`). Make a machine account with read access to the project. Make an access token for it. Do not paste the token into a chat or a file.
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

## Migration from the running transient units

The running units are transient `systemd-run` units with the same names (`sandbox-proxy`, `sandbox-bridge`). They use the ports 1080, 8081, 8443, 9091 and 15353. The names clash with the new units. Run `systemctl --user stop sandbox-proxy sandbox-bridge` before step 7. Do not run the recipes of the old `sandbox-plain` branch next to the new units.

## Later

Not built yet. The gateway accepts a JWT. iron-proxy has no SPIFFE support and no upstream mTLS. A `file` source with a `ttl` can carry a JWT-SVID. A loop on the host would run `spire-agent api fetch jwt` and write the token to that file. The identity is then the identity of the proxy, not of one sandbox.
