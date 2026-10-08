# The sbx daemon, and what keeps it on a short leash

The sandbox is a VM, but the VM does not make every network call itself. The **sbx daemon** runs on your machine, outside the VM, and makes the MCP calls, kit pulls
and Docker sign-in for it. The VM's egress rules do not cover those calls, so they go through a small squid proxy with an allowlist, and systemd keeps both running.

## Where it sits

```mermaid
flowchart LR
    subgraph vm["microVM (one per sandbox)"]
        agent["Claude Code<br/>no real credential"]
    end
    subgraph host["your machine"]
        egress["sbx egress proxy<br/>AGENT POLICY<br/>.sbx/agent/dev-tools.yaml"]
        subgraph daemon["sbx daemon (sbx-daemon.service)"]
            gw["MCP gateway<br/>OAuth token, tool filter, tool-call log"]
        end
        squid["squid 127.0.0.1:3128<br/>DAEMON POLICY<br/>egress/squid.conf"]
    end
    agent -- "VM network calls" --> egress --> net1["internet:<br/>kit allow list"]
    agent -- "MCP tool calls" --> gw
    gw -- "MCP servers, kit pulls,<br/>Docker sign-in" --> squid --> net2["internet:<br/>squid allowlist"]
```

## How it starts

```mermaid
flowchart TD
    boot["login or boot<br/>(linger keeps user services up)"] --> docker["docker.service<br/>rootless Docker"]
    docker --> proxyunit["sbx-daemon-egress.service<br/>docker compose up -d --wait"]
    proxyunit --> squid["squid container<br/>healthy on 127.0.0.1:3128"]
    squid --> daemonunit["sbx-daemon.service<br/>sbx daemon start"]
    daemonunit --> setting["sbx setting proxy.daemon = http://127.0.0.1:3128<br/>the daemon's own calls go to squid"]
    proxyunit -. "stopping or restarting it<br/>also stops the daemon" .-> daemonunit
```

## Files

| File | What it is |
|---|---|
| `Taskfile.yml` | `sandbox:install-daemon` (once per machine; its comments hold the steps, checks, logs and undo) and `sandbox:install-mcp` |
| `systemd/sbx-daemon-egress.service` | starts the squid container and keeps it running |
| `systemd/sbx-daemon.service` | runs the sbx daemon, ordered after the proxy |
| `egress/compose.yaml` | the squid container, listening on `127.0.0.1:3128` only |
| `egress/squid.conf` | the allowlist: the file to edit to let the daemon reach another host |

## Install

```shell
task sandbox:install-daemon     # restarts the sbx daemon, which ends running sandboxes
```
