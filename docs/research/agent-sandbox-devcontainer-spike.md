# Spike: the Compose sandbox with Docker internal networks

Question: Can the planned `.devcontainer/` sandbox keep iron-proxy as the only way out when the agent is on a Docker internal network, not `network none`? Can the proxy run hardened as a non-root user and get the bws token with no copy left behind?

Spike date: 2026-11-26. Host: rootful Docker (iptables firewall driver), Compose 5.6.1, runsc `release-20261102.0`, ufw active (default deny incoming). The spike files were throwaway Compose stacks in the session scratchpad. Decisions: [`docs/handoff/agent-sandbox-devcontainer-compose-2026-11-25.md`](../handoff/agent-sandbox-devcontainer-compose-2026-11-25.md), Decisions 11 to 30.

## Short answer

Yes. All six stages pass. Only the proxy tunnel is reachable from the agent. The host is unreachable by three independent layers. The proxy runs as uid 10001 with no capabilities. The bws token file is gone after the proxy starts, and no token shows in `docker inspect`, the logs or the agent env. Builds run in the gVisor builder through the tokenless builder proxy. The devcontainer CLI runs the workflow with three design changes (see S5).

## S1: network model (pass)

Setup: network `sandbox` 10.200.0.0/29, `internal: true`, `inhibit_ipv4`. iron-proxy (runc) at .2 with the tunnel on `10.200.0.2:18080` only. The real agent image (runsc-uds) at .3. A busybox probe (runsc-uds) at .4. All with `cap_drop: ALL`, read-only root and no-new-privileges.

| Check | Result |
|---|---|
| Runtimes | proxy runc. Agent and probe runsc-uds. `CapDrop [ALL]`. |
| Network | `Internal=true`. Gateway "invalid IP" (inhibited). The host bridge has no IPv4 address, only `fe80::`. |
| Routes in the probe | Only `10.200.0.0/29` and `lo`. No default route. Under gVisor `eth0` has no IPv6 address. |
| `nc 1.1.1.1 443` | Fails |
| `ip route add default via 10.200.0.1` | `Operation not permitted` |
| Host `10.200.0.1:18999`, `172.17.0.1:53`, router `192.168.178.1:80` | All fail |
| Host link-local `fe80::…%eth0:18999` | Fails (the probe has no IPv6 address) |
| Proxy ports | 18080 open. 18081 to 18084 refused. |
| DNS | Fails in 61 ms (`write to '127.0.0.11': Connection refused`) |
| Allowed host through the proxy | 200 |
| Blocked host through the proxy | `CONNECT` 403, rejected by the allowlist |
| `curl --noproxy '*'` | Fails (cannot resolve) |
| Proxy audit log | `remote_addr 10.200.0.3`: the agent address is visible |

Controls:
- Without `inhibit_ipv4`, the host bridge gets `10.200.0.1/29`. The host still did not answer, because ufw denies incoming traffic.
- On a normal network, the probe gets a default route and reaches `1.1.1.1:443`. The method detects a working path. The host still did not answer (ufw).
- The ufw allow list: tcp and udp 53317 from anywhere (LocalSend), and udp 53 to `172.17.0.1` from Docker ranges.

Findings:
- Three independent layers protect the host. `inhibit_ipv4` removes the host IPv4 address from the bridge. gVisor gives `eth0` no IPv6 address, so no link-local path exists. ufw denies incoming traffic by default.
- Keep `inhibit_ipv4`. Without it, LocalSend on port 53317 is reachable from the agent.
- gVisor cannot use Docker DNS, so the proxy needs a fixed IP.

## S2a: hardened non-root proxy and token mechanics (pass)

Setup: the proxy image from `dockerfile_inline` (bws 2.1.0 and iron-proxy 0.56.0, both by digest, no socat). A throwaway CA. A dummy token. uid `10001:10001`. Access by POSIX ACL only: `setfacl -m u:10001:r ca.key` and `u:10001:rwx` on the secrets folder. No file mode widened (`group::---`).

| Check | Result |
|---|---|
| `docker inspect` | runc, user `10001:10001`, read-only root, `CapDrop [ALL]`, no-new-privileges, memory 512 MiB equal to memory plus swap, pids 256, core `0:0`, restart `no`. Policy, `ca.crt` and `ca.key` mounts `rw=false`. |
| `/proc/1/status` | uid and gid 10001, groups 10001 only, all capability sets 0, `NoNewPrivs 1`, `Seccomp 2` |
| Writes | Root file system and `ca.key` read-only. `/tmp` writable. A binary copied to `/tmp` cannot run (`noexec`). |
| cgroup inside | `memory.max` 536870912, `memory.swap.max` 0, `pids.max` 256, `ulimit -c` 0 |
| Agent through the hardened proxy | 200 |
| Token | Present before start, gone after start. bws exits 1 on the dummy token. The token string occurs 0 times in `docker inspect` and 0 times in the logs. |

The secrets folder is the only read-write mount. `dockerfile_inline` builds with Compose 5.6.1.

## S2b: real bws credential, real CA, real policy (pass)

Setup: the real policy with `tunnel_listen: "10.200.0.2:18080"`. The real CA with the ACL `user:10001:r--` on `ca.key` (mode stays 0600 for group and other). The token from `systemd-creds --user decrypt --name=bws-token` into a RAM folder (folder 0700 plus ACL `u:10001:rwx`, file 0600 plus ACL `u:10001:r`).

| Check | Result |
|---|---|
| Healthcheck | `wget -q -O /dev/null http://127.0.0.1:18083/healthz`. Healthy 6 s after `docker compose up --wait`. `/metrics` returns 404. |
| Without a healthcheck | `--wait` returns before bws starts iron-proxy. The first requests fail with "connection refused". |
| Token file | Gone after start |
| `GET api.github.com/user` with the placeholder | 200, login `raghav19` |
| `PATCH api.github.com/user` with `{}` | 403, audit `action: reject`, `remote_addr 10.200.0.3` |
| Leaks while the proxy runs | bws token in `docker inspect` 0, in the logs 0. GitHub token shapes in `docker inspect` 0, in the logs 0, in the agent env 0. |
| After `docker compose stop` | Secrets folder empty, proxy exited. bws token and GitHub token shapes in the stopped container config 0. |

## S3: gVisor builder behind a tokenless builder proxy (pass)

Setup: network `build` (internal, `inhibit_ipv4`) with builder-proxy .2 and builder .3. The builder is the upstream image `moby/buildkit:v0.35.0-rootless` by digest, with no Dockerfile (ENTRYPOINT `rootlesskit buildkitd`, user 1000:1000), on runtime `runsc-builder` (`--host-uds=all`). The builder proxy is the proxy image on runc, uid 10001, read-only, with the builder policy (`sni-only`). The agent (runsc-uds) uses a `docker-config.json` with `proxies` set to the builder proxy.

| Check | Result |
|---|---|
| Builder | Healthy (`buildctl … debug workers`). runsc-builder, user 1000:1000, `CapDrop [ALL]`, `CapAdd [SETGID SETUID SYS_CHROOT]`, no no-new-privileges, memory 2 GiB equal to memory plus swap, 2 CPUs, pids 1024. |
| buildx in the agent | `docker buildx inspect sandbox`: endpoint `unix:///run/sandbox/buildkit/buildkitd.sock`, status running, BuildKit v0.35.0 |
| Build | `FROM alpine:3.22`, `apk add curl` and `curl https://github.com`, exported with `--output type=docker` (6.2 MB). Cold 6 s. Second build 1 s from the cache. |
| Proxy audit | The agent proxy got only `auth.docker.io` (the registry token, from the agent). The builder proxy got `registry-1.docker.io`, `production.cloudfront.docker.com`, `dl-cdn.alpinelinux.org` and `github.com` (from the builder). |
| Blocked host in a `RUN` step | The build fails. curl gets `CONNECT tunnel failed, response 403`. The audit shows `example.com:443 CONNECT reject`. busybox wget gets `400 Bad Request`, because it sends GET, not CONNECT, for HTTPS through a proxy. |
| Bypass in a `RUN` step | `nc 1.1.1.1 443` fails (no route). The `RUN` step has only the `build` subnet route. |
| Builder to host or internet | Routes are the subnet and `lo` only. The host listener and `1.1.1.1:443` both fail. |
| Tokens | 0 token shapes in the env of the builder and the builder proxy |

Traps:
- **Socket folder owner.** Docker gives root as the owner of a named volume at a path that the image does not have, and buildkitd (uid 1000) fails with `permission denied`. Mount the volume at `/run/user/1000`, which has owner 1000 in the image, and use the socket `/run/user/1000/buildkit/buildkitd.sock`. The agent mounts only the subpath `buildkit`, read-only. The folder is 0700 with owner 1000, so the agent user must stay uid 1000.
- **Registry login runs in the agent.** buildx answers the auth request of buildkitd and gets the registry token itself. With `network_mode: none` the agent cannot reach `auth.docker.io`, and `FROM` fails. The agent needs its proxy. For a private GHCR image, the agent proxy swaps the placeholder, and a short-lived scoped registry token reaches the builder.
- **Two proxy settings for builds.** buildkitd uses its container env for pulls. `RUN` steps take the proxy from `proxies` in the agent's `docker-config.json`, which must point at the builder proxy (`10.200.0.10` in the final design).
- `runsc-builder` needs only `--host-uds=all`. The default gVisor network stack works on the internal network, and rootful Docker sets the limits.

## S4: the real agent with the full Compose env (pass)

Setup: the agent image built from `main` e37a7a4 (4.6 GB), the full planned env in `compose.yaml`, and the real proxy. `GIT_CONFIG_GLOBAL=/dev/null` hides the old `~/.gitconfig` of the image, so git reads its config only from the env. A slim `qwen-settings.json` (auth and `mcpServers` only) replaces the copy in the image, as a read-only mount.

| Check | Result |
|---|---|
| Start order | The proxy is healthy, then the agent is healthy |
| `docker inspect` | runsc-uds, read-only root, memory 3 GiB equal to memory plus swap, 4 CPUs, pids 2048, `CapDrop [ALL]` |
| `mise run sandbox:start` | `/tmp/sandbox-ready` present |
| Git config | `safe.directory=*` and the credential helper, both from scope "command line" (`GIT_CONFIG_*`). The helper holds a literal `$GH_TOKEN`. `docker compose config` prints `$$GH_TOKEN`, because its output keeps the escape. |
| `git push --dry-run` to a new branch | Success through the proxy with the placeholder. The dry run writes nothing. |
| `claude -p` | The model answered through the proxy, with no auth error. The Ponytail plugin context changed the text of the reply. |
| `qwen -p` with `OPENAI_BASE_URL` and `OPENAI_MODEL`, no `modelProviders` | `OK`. The MCP servers (GitHub Copilot, draw.io) connected through the proxy. |
| Env in a tool | `EDITOR=fresh`, `K9S_SKIN=tokyo-night`, `OPENAI_MODEL=qwen3.8-max` |
| Leaks | 0 GitHub or Anthropic token shapes in the agent env |

Not checked: the effect of `K9S_SKIN` in the k9s UI (interactive).

## S5: the devcontainer CLI workflow (pass with 3 design changes)

Setup: devcontainer CLI 0.91.0, Compose 5.6.1, a throwaway workspace with `devcontainer.json`, `compose.yaml` and a `pre-up.sh`. The real proxy and the real agent, as in S4.

| Check | Result |
|---|---|
| `devcontainer build` | Fails by default. Passes with `BUILDX_BAKE_ENTITLEMENTS_FS=0` (7 s). It builds only the agent. |
| Cold `devcontainer up` | 17 s. `initializeCommand` runs in the workspace root. The Compose `name` is the project name. The CLI runs `compose build` and `compose up -d` for the `runServices`. The proxy is healthy before the agent starts. `postStartCommand` runs. The agent is healthy, and the token file is gone. |
| What the CLI adds | No mounts, no container env. Three labels: `devcontainer.config_file`, `devcontainer.local_folder`, `devcontainer.metadata`. No `SSH_AUTH_SOCK`, no `docker.sock`, no credential helper. The CLI sets its own entrypoint, which runs the Compose `command`. |
| `devcontainer exec` | User `agent`, cwd `/home/agent`, `EDITOR=fresh`, origin `https://github.com/raghav19/engineersdaybook`. `api.github.com/zen` returns 200 through the proxy. |
| `up` while the agent runs | 1 s. Same containers, no Compose up, no `postStartCommand`. `pre-up` skips the decrypt, and no token file stays. |
| Restart: `docker compose stop`, then `up` | 9 s with `up -d --no-recreate`. `pre-up` decrypts, the proxy reads and removes the token, `postStartCommand` runs again. |
| A change in `compose.yaml` | `stop` and `up` ignore it. `down` and `up` apply it (15 s). The home volume keeps the clone and a marker file. |
| `--remove-existing-container` | Makes a new agent only. If the proxy config changed, Compose makes a new proxy too, but `pre-up` already skipped. The new proxy exits 1 (`cat: can't open '/run/bws/bws-token'`). |
| After `stop` | The secrets folder is empty. 0 token shapes in `docker inspect` of the proxy and the agent. |

Design changes:
1. The agent keeps `command: ["sleep", "infinity"]` with `"overrideCommand": false`. With the default, the CLI entrypoint runs the image CMD `bash`, and bash exits with no TTY.
2. `"workspaceFolder": "/home/agent"`. The CLI runs the lifecycle commands in `workspaceFolder`, and the clone does not exist before `sandbox:start` makes it (exit 127).
3. `devcontainer build` needs `BUILDX_BAKE_ENTITLEMENTS_FS=0` on the host. The CLI writes its wrapper Dockerfile to `/tmp/devcontainercli-<user>/`, and Compose 5.6.1 (bake) refuses that path. `COMPOSE_BAKE=false` was not tested.

## S6: the host port bridge (pass)

Setup: the agent (runsc-uds) on an internal network with `inhibit_ipv4` and no published port. A test server on `127.0.0.1` in the agent. `PLANNOTATOR_PORT` gives the port range.

The command, one transient user unit for each port. The spike used its own names. The command below has the names of the final design:

```bash
systemd-run --user --quiet --collect --unit "sandbox-bridge-$port" \
  socat "TCP-LISTEN:$port,bind=127.0.0.1,reuseaddr,fork,max-children=8" \
  "EXEC:docker exec -i sandbox-agent-1 socat - TCP\\:127.0.0.1\\:$port"
```

| Check | Result |
|---|---|
| Port range | Read from `docker compose -f compose.yaml config --format json` (`PLANNOTATOR_PORT`). The recipe holds no port number. |
| Bridge up | One active unit and one `127.0.0.1` listener for each port. A host `curl` gets 200. A second run stops the old units first. |
| Parallel requests | 2 parallel requests get 200 (30 ms each) |
| No server in the agent on a port | Fails fast (curl exit 52, 30 ms) |
| New agent container | The bridge needs no restart, because it uses the container name |
| Agent stopped | Requests fail fast. The units stay active. After a start, requests work again. |
| Stop | `systemctl --user stop 'sandbox-bridge-*.service'`: 0 units, 0 listeners |
| Agent to host | Fails. The agent has only the subnet route. The bridge works only from the host to the agent. |

Traps:
- Escape the colons in the `EXEC:` command (`TCP\:127.0.0.1\:<port>`). `systemd-run` passes the argument as it is.
- `docker compose config` needs `-f compose.yaml` or the project folder. The project name alone cannot render the config.
- The container name is `<project>-agent-1`, so `sandbox-agent-1` with `name: sandbox`.
- `systemctl --user list-units` hides inactive units. Add `--all` to see that no unit stays.
- In a plain `sh -c`, `python3` is not on the `PATH` of the image. `/opt/mise/shims/python3` works.
