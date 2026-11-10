# The host proxy of the sandbox

iron-proxy runs on the host. It is the only way out of the sandbox. It checks each request against an allowlist. It replaces placeholders with real tokens. The sandbox has no network and holds no real token.

The sandbox reaches the proxy through a Unix socket. A bridge on the host joins the socket to the tunnel listener of the proxy. The sandbox part is in a separate change. This change is the host part.

```text
sandbox (no network) -> relay in the sandbox -> proxy.sock -> bridge (socat) -> iron-proxy (127.0.0.1) -> allowed hosts
```

## What is here

| Path | Content |
|---|---|
| `iron-proxy.yaml` | The template of the config: the allowlist and the secret rules. |
| `justfile` | The recipes. The root `justfile` loads them as `just sandbox-proxy <recipe>`. |
| `selftest.sh` | The checks that `just sandbox-proxy selftest` runs. |

## Prerequisites

Install these on the host:

- `podman`. The proxy binary comes from a pinned image.
- `socat`, `openssl`, `just` and `systemd` (user services).
- `bws` and `age`, with the encrypted Bitwarden token. See `.msb/README.md`, prerequisite 4.
- `/etc/ssl/certs/ca-certificates.crt`. The CA bundle for the sandbox starts from this file.

The Bitwarden project needs a key for each of these names: `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `QWEN_API_KEY` and `GITHUB_TOKEN`.

## First run

1. Run `just sandbox-proxy up`.
2. Type the passphrase of the Bitwarden token when `age` asks for it.
3. Run `just sandbox-proxy status`. The proxy and the bridge must show `active`.
4. Check the rules with `selftest`. It refuses to run next to a live proxy of the same namespace. See "Test next to a live proxy".

`up` does these steps. It skips a step that is already done.

1. It makes a CA, if there is none.
2. It writes the CA bundle: the system CAs plus the CA of the proxy.
3. It takes the proxy binary from the pinned image, if the binary is not in the state folder.
4. It writes the config with the ports.
5. It starts the proxy with the tokens in its environment. Then it starts the bridge.
6. It waits until the tunnel listens and the socket exists.

## Where the files are

| Path | Content |
|---|---|
| `~/.local/state/sandbox/ca.key` | The private key of the CA. Mode 0600. It never leaves the host. |
| `~/.local/state/sandbox/ca.crt` | The certificate of the CA. |
| `~/.local/state/sandbox/ca-bundle.crt` | The system CAs plus `ca.crt`. The sandbox mounts this file read-only. |
| `~/.local/state/sandbox/iron-proxy.yaml` | The config that the proxy reads. `up` and `reload` write it. |
| `~/.local/state/sandbox/bin/` | The proxy binary. The name has the first 12 characters of the image digest. |
| `$XDG_RUNTIME_DIR/sandbox/proxy.sock` | The socket of the bridge. Mode 0600, owner is the host user. |

## Daily use

| Recipe | What it does |
|---|---|
| `just sandbox-proxy up` | Starts what is not running. It asks for the passphrase only when the proxy is not running. |
| `just sandbox-proxy status` | Shows the services, the socket and the listeners. |
| `just sandbox-proxy log` | Follows the audit log. Each request is one JSON line. |
| `just sandbox-proxy reload` | Writes the config again and restarts the proxy. It asks for no passphrase. |
| `just sandbox-proxy down` | Stops the proxy and the bridge. |
| `just sandbox-proxy ca` | Makes a new CA. |
| `just sandbox-proxy selftest` | Starts a proxy with dummy tokens and checks the rules. |

## How the secrets map

The sandbox holds a placeholder. The proxy holds the real token, from the environment that `bws run` gives it. The proxy replaces the placeholder in a request to a host of the rule. It does this only in the `Authorization` header.

| Placeholder in the sandbox | Variable of the proxy | Hosts |
|---|---|---|
| `sandbox-placeholder-GH_TOKEN` | `GH_TOKEN` | `github.com`, `api.github.com`, `api.githubcopilot.com` |
| `sandbox-placeholder-CLAUDE_CODE_OAUTH_TOKEN` | `CLAUDE_CODE_OAUTH_TOKEN` | `api.anthropic.com` |
| `sandbox-placeholder-QWEN_API_KEY` | `QWEN_API_KEY` | `token-plan.ap-southeast-1.maas.aliyuncs.com` |
| `sandbox-placeholder-GHCR_PUSH_TOKEN` | `GITHUB_TOKEN` | `ghcr.io` |

The placeholders in the sandbox must equal the `proxy_value` lines in `iron-proxy.yaml`.

A request to a host that is not on the allowlist gets 403 at the CONNECT. The proxy reads the real tokens once, at the start. It does not write them to the audit log.

## Change the allowlist

1. Edit `iron-proxy.yaml` in this folder.
2. Run `just sandbox-proxy reload`.
3. Run `just sandbox-proxy log` and repeat the request. A line with `"action":"allow"` shows that the change works.

Keep the `@NAME@` markers for the ports. The recipes replace them.

## Rotate a secret

- **A token.** Change it in Bitwarden. Run `just sandbox-proxy down`, then `just sandbox-proxy up`. A `reload` keeps the old token.
- **The CA.** Run `just sandbox-proxy down`, `just sandbox-proxy ca`, then `just sandbox-proxy up`. Restart the sandbox. It reads the new bundle at the start.

## Test next to a live proxy

Two variables change the namespace. Set both to run a second copy next to a live proxy.

| Variable | Default | Effect |
|---|---|---|
| `SANDBOX_NS` | `sandbox` | The prefix of the two user services and of the two folders. |
| `SANDBOX_PORT_BASE` | `0` | A number that the recipes add to each port. |

Example:

```bash
SANDBOX_NS=sbxtest SANDBOX_PORT_BASE=30000 just sandbox-proxy selftest
```

The default ports are 15353 (DNS), 8081 (HTTP), 8443 (HTTPS), 1080 (tunnel) and 9091 (metrics). All of them listen on `127.0.0.1`. The sandbox uses the tunnel only.

`selftest` uses dummy tokens and needs no `bws`. It needs the internet for one request to `api.github.com`. It refuses to run if a proxy of the same `SANDBOX_NS` runs. It checks these points:

- The socket has mode 600 and belongs to the host user.
- Each port listens on `127.0.0.1` and on no other address.
- A CONNECT to an allowed host gets 200.
- A CONNECT to a host that is not allowed gets 403.
- A request through the proxy CA works.
- The audit log shows the swap of `GH_TOKEN`.
- No token value is in the audit log.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `the proxy does not listen` | The proxy stopped or the port is in use. | Run `just sandbox-proxy log`. Set `SANDBOX_PORT_BASE` if the port is in use. |
| `bws and age must be on the PATH` | A tool is missing. | Install both. See `.msb/README.md`, prerequisite 4. |
| 403 at the CONNECT for a host that you need | The host is not on the allowlist. | Add it to `iron-proxy.yaml`. Run `reload`. |
| 401 from the upstream host with the real token | The token is wrong, or the Bitwarden key has another name. | Check the four key names. Run `down`, then `up`. |
| Certificate error in a tool | The tool does not use the bundle. | Point the tool at `ca-bundle.crt`. See the sandbox README. |
| The sandbox cannot open the socket | The socket belongs to another user, or the bridge stopped. | Run `status`. The socket must be mode 600 and belong to the host user. |

## Security notes

- **The proxy sees the traffic in clear text.** It ends the TLS of each allowed host with its own CA. It can read each request and each token.
- **The CA key stays on the host.** The sandbox gets only `ca-bundle.crt`. A tool in the sandbox trusts the CA, so protect `ca.key`.
- **The allowlist limits the host, not the data.** An agent can send any data to an allowed host. Allow only the hosts that the agent needs.
- **Domain fronting.** The proxy checks the host name of the CONNECT, the SNI and the `Host` header. An earlier spike showed 400 or 403 for a mismatch. It is not tested through the tunnel of this change.
- **HTTP and TLS only.** SSH and raw TCP fail. Use `https` remotes for `git`.
- **The tokens are in memory.** systemd keeps them in the environment of the user service. A process of the same user can read them with `systemctl --user show`. Treat the host user as trusted.
- **The audit log has names, not values.** A line shows the name of the secret and where the proxy replaced it.
- **The management API is off.** `reload` restarts the proxy. It does not use the API.

## Later

These parts are not built yet.

- **A JWT-SVID for the gateway.** The gateway of the owner accepts a JWT. iron-proxy has no SPIFFE support and no upstream mTLS. A `file` source with a `ttl` can carry a JWT. A loop on the host would run `spire-agent api fetch jwt` and write the token to the file. The identity is then the identity of the proxy, not of one sandbox.
- **Another secret store.** The proxy has a `vault_kv` source. It is not tested with OpenBao.
