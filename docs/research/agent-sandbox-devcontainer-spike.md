# Spike: the Compose sandbox with Docker internal networks

Question: Can the planned `.devcontainer/` sandbox keep iron-proxy as the only way out when the agent is on a Docker internal network, not `network none`? Can the proxy run hardened as a non-root user and get the bws token with no copy left behind?

Spike date: 2026-11-26. Host: rootful Docker (iptables firewall driver), Compose 5.6.1, runsc `release-20261102.0`, ufw active (default deny incoming). The spike files were throwaway Compose stacks in the session scratchpad. Decisions: [`docs/handoff/agent-sandbox-devcontainer-compose-2026-11-25.md`](../handoff/agent-sandbox-devcontainer-compose-2026-11-25.md), Decisions 11 to 25.

## Short answer

Yes, for S1, S2a and S2b. Only the proxy tunnel is reachable from the agent. The host is unreachable by three independent layers. The proxy runs as uid 10001 with no capabilities. The bws token file is gone after the proxy starts, and no token shows in `docker inspect`, the logs or the agent env.

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

## Pending

| Stage | What it proves | Pass checks |
|---|---|---|
| S3 builder | Builds through `builder-proxy` | `runsc-builder` (`--host-uds=all`) with `SETUID`, `SETGID`, `SYS_CHROOT`. A `RUN` step reaches `10.200.0.10:18080`. buildx in the agent works over the Unix socket. The builder healthcheck (`buildctl debug workers`) passes. |
| S4 agent | The real image with the full Compose env | `runsc-uds`, read-only root, limits in `docker inspect`. `$$GH_TOKEN` renders as a literal `$GH_TOKEN`. `GIT_CONFIG_*` gives `safe.directory=*` and the credential helper. `git push --dry-run` authenticates through the proxy. Claude Code and Qwen Code (`OPENAI_*` env, slim settings) answer through the proxy. `sandbox:start` writes `/tmp/sandbox-ready`. No real token in the agent env. |
| S5 devcontainer CLI | The owner's workflow | `devcontainer build`, `up`, `exec`. `name: sandbox` is the project name. The folder where `initializeCommand` runs. `pre-up` leaves no token file when the proxy runs. `postStartCommand` reaches healthy. `just apply` applies changes. `docker compose -p sandbox stop` and `devcontainer up` restart. |
| S6 bridge | Plannotator from the host | Host to agent port through `docker exec -i … socat` with `inhibit_ipv4` on |
