# The sbx daemon, and what keeps it on a short leash

The sandbox is a VM, but the VM does not make every network call itself. The **sbx daemon** runs on your machine, outside the VM, and makes the MCP calls, kit pulls
and Docker sign-in for it. The VM's egress rules do not cover those calls, so they go through a small squid proxy with an allowlist. Two separate things run it:
systemd keeps the daemon up, and a Docker container is the proxy. Recipes start them in order.

## Where it sits

```mermaid
flowchart LR
    subgraph vm["microVM (one per sandbox)"]
        agent["Claude Code<br/>no real credential"]
    end
    subgraph host["your machine"]
        egress["sbx egress proxy<br/>AGENT POLICY<br/>.sbx/kits/policy/policy.yaml"]
        subgraph daemon["sbx daemon (sbx-daemon.service)"]
            gw["MCP gateway<br/>OAuth token, tool filter, tool-call log"]
        end
        squid["squid 127.0.0.1:3128<br/>DAEMON POLICY<br/>proxy/squid.conf"]
    end
    agent -- "VM network calls" --> egress --> net1["internet:<br/>kit allow list"]
    agent -- "MCP tool calls" --> gw
    gw -- "MCP servers, kit pulls,<br/>Docker sign-in" --> squid --> net2["internet:<br/>squid allowlist"]
```

## How it starts

```mermaid
flowchart TD
    start["just sandbox host daemon-start"] --> egress["just sandbox host proxy-start<br/>docker compose up -d --wait<br/>squid healthy on 127.0.0.1:3128"]
    egress --> unit["systemctl --user start sbx-daemon.service<br/>sbx daemon start<br/>proxy.daemon = http://127.0.0.1:3128"]
    stop["just sandbox host daemon-stop"] --> unitstop["stop sbx-daemon.service"] --> egressstop["just sandbox host proxy-stop<br/>docker compose down"]
```

At login, linger starts `sbx-daemon.service` (after Docker), and Docker restarts the squid container because of `restart: unless-stopped`. Nothing orders the two
at login: the daemon can come up a few seconds before squid is healthy. After a `daemon-stop` the container is gone, so run `just sandbox host daemon-start` (not
a reboot) to bring both back.

## Files

| File | What it is |
|---|---|
| `host.just` | the recipes of `just sandbox host ...`: `login`, `proxy-install`, `proxy-start`, `proxy-stop`, `daemon-install` (once per machine; its comments hold the steps, checks and undo), `daemon-start`, `daemon-stop`, `daemon-restart` and `vscode-setup` |
| `systemd/sbx-daemon.service` | runs the sbx daemon, supervised and restarted on failure |
| `proxy/compose.yaml` | the squid container, listening on `127.0.0.1:3128` only |
| `proxy/squid.conf` | the allowlist: the file to edit to let the daemon reach another host |

## Install

sbx comes from mise (`mise install`); the daemon unit runs it from the mise install dir.

```shell
just sandbox host proxy-install      # step 2, once per machine: pulls the squid image
just sandbox host daemon-install     # step 3, once per machine, and after editing the unit: copies and enables it, sets proxy.daemon. Starts nothing
just sandbox host daemon-start       # step 4: starts the proxy, then the daemon; prints the journal if the daemon does not stay up
just sandbox host daemon-stop        # stops the daemon, then the proxy. Ends running sandboxes
just sandbox host daemon-restart     # stop then start, e.g. after editing squid.conf
```

If the daemon will not start, the reason is in `journalctl --user -u sbx-daemon.service`, not in `docker logs sbx-daemon-egress` (squid only).
The unit runs `sbx daemon start` in the foreground so systemd can supervise it; `--detach` would make it exit and the unit stop.
