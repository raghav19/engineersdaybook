# Part 2 — Sandboxing local MCP servers

sandboxing local MCP servers

## Prerequisites

- Rootless Docker. See [`code/rootless-docker`](../../rootless-docker) for the setup this builds on.
- A [GitHub App](https://docs.github.com/en/apps/creating-github-apps)
- Once github app is registered, ensure to download the private key, installation ID and app ID. Refer [mise.toml](./mise.toml)

## Run it

**1. Start the proxy.** It must be running before the agent starts the server, and it stays up across sessions.

```shell
docker compose up -d
docker logs -f mcp-egress-proxy    # every outbound attempt, allowed or denied
```

**Optional — start it at boot.** The proxy is the long-lived half of the sandbox, so on a machine you use daily it is easier to hand it to systemd than to remember `compose up`. Rootless Docker runs in your *user* manager, so this is a user unit too:
> NOTE: ensure to change the `WorkingDirectory` to match your local setup

```ini
# ~/.config/systemd/user/mcp-egress-proxy.service
[Unit]
Description=MCP egress proxy (squid)
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=%h/path/to/part-2-sandboxing-local-mcp
Environment=DOCKER_HOST=unix://%t/docker.sock
ExecStart=/usr/bin/docker compose up -d --wait
ExecStop=/usr/bin/docker compose down

[Install]
WantedBy=default.target
```

```shell
loginctl enable-linger "$USER"   # user units at boot, not at login
systemctl --user daemon-reload
systemctl --user enable --now docker.service mcp-egress-proxy.service
```

**2. Refere to the [.mcp.json](../../../.mcp.json)** file for full config

**3. Update the permissions to make the key mountable inside rootless docker**

```shell
# ensure to copy the pem file to ~/.config/mcp-gh
docker run --rm -v ~/.config/mcp-gh:/mnt alpine chown 10001:10001 /mnt/mcp-gh-local.2026-09-19.private-key.pem
```

## What each flag is for

| flag | why |
|---|---|
| `--network mcp-egress-github` | sealed network, no route out — this is what makes the proxy unavoidable |
| `--read-only` + `--tmpfs /tmp` | the container filesystem is fixed |
| `--cap-drop ALL` | no Linux capabilities |
| `--security-opt no-new-privileges` | cannot gain privileges via setuid binaries |
| `--user 10001:10001` | unprivileged in-container, mapped into the unprivileged subuid range by rootless Docker |
| `--log-driver journald` | `--rm` deletes container logs on exit; journald keeps the record |
| `-v …:/key.pem:ro` | the signing key — read-only, and owned by the uid the container maps to |
| `-e HTTP(S)_PROXY` | routes traffic to the proxy. Not a security control on its own — the sealed network is |
