# Daemon setup (do this once, before the other tasks)

## What this is

The sandbox is a VM, but the VM does not make every network call itself. The **sbx daemon** runs on your machine, outside the VM, and makes the calls on its behalf:
it talks to the MCP servers (GitHub, draw.io, the Flux catalog), pulls the kit images, and signs in to Docker. The egress rules in `../agent/dev-tools.yaml` only cover the VM,
so none of them apply to those calls.

This setup sends the daemon's calls through a small proxy (squid) that only lets through a list of hosts you control. The proxy runs as a container in your
rootless Docker, and systemd keeps it running and makes sure the daemon never starts without it.

## What gets set up on your machine

| What | Where | What it does |
|---|---|---|
| a squid container `sbx-daemon-egress` | rootless Docker, listening on `127.0.0.1:3128` only | the allowlist proxy. Files: `egress/compose.yaml`, `egress/squid.conf` |
| a systemd user unit `sbx-daemon-egress.service` | `~/.config/systemd/user/` | starts the container at login and keeps it up |
| a systemd user unit `sbx-daemon.service` | `~/.config/systemd/user/` | runs the sbx daemon, but only after the proxy is up. Stopping the proxy unit stops the daemon. It also gives the daemon a temp folder on disk (`~/.cache/sbx-tmp`) because kit images can fill a RAM-disk `/tmp` |
| the sbx setting `proxy.daemon` | sbx's settings (`sbx settings get proxy.daemon`) | tells the daemon to use the proxy |

The unit files are in `systemd/` in this folder. The install task copies them to `~/.config/systemd/user/` (it fills in the path of this clone, which is why they are
copies and not links). Nothing here touches the VM's own egress policy.

## Before you start

Check these three, the install task checks the first two for you:

```shell
systemctl --user is-enabled docker.service     # rootless Docker runs as your user service ("enabled")
loginctl show-user "$USER" -p Linger           # Linger=yes, so your user services start at boot
ls ~/.docker/sbx/bin/sbx                       # sbx is installed (see the main README)
```

## Install

```shell
task sandbox:install-daemon
```

This **restarts the sbx daemon, which ends any running sandbox**. Run it again any time you change the files in `systemd/`


## Check that it worked

```shell
systemctl --user is-active sbx-daemon-egress sbx-daemon      # both "active"
docker ps --filter name=sbx-daemon-egress                    # "healthy"  (with DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock)
sbx settings get proxy.daemon                                # http://127.0.0.1:3128
```

## Day to day

- **See what the daemon reaches, allowed and denied:** `docker logs -f sbx-daemon-egress`. A line appears when a connection closes, so long-lived ones (the MCP servers) show up late.
- **Allow another host:** add a `dstdomain` line to `egress/squid.conf`, then `docker compose -f .sbx/daemon/egress/compose.yaml restart`. `up -d` alone does **not** pick up an edit to the file.
- **If the proxy is stopped by hand** (`docker stop`), Docker will not bring it back, and the daemon cannot pull kits, sign in or reach the MCP servers until you do:
  `docker compose -f .sbx/daemon/egress/compose.yaml up -d`. If squid itself crashes, Docker restarts it in a few seconds.
- **Restarting `sbx-daemon-egress.service` also restarts the daemon** and ends running sandboxes. That is on purpose: the daemon should never run without the proxy.

## Undo

```shell
sbx settings unset proxy.daemon
systemctl --user disable --now sbx-daemon-egress.service
rm ~/.config/systemd/user/sbx-daemon-egress.service
# put back a plain sbx-daemon.service without Requires=/After=, or delete it and start the daemon with `sbx daemon start`
systemctl --user daemon-reload
```
