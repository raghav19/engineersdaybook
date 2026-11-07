# Host SPIRE agent

The SPIRE agent of the host attests the host to the SPIRE server in the cluster. Then it serves the Delegated Identity API on its admin socket to the delegate. The agent checks the pid that the delegate sends with the `msbvm` plugin.

Read the [workload attestation guide](../docs/workload-attestation.md) for the flow.

## Run it

Run these on the host, from the root of the repo:

```text
just msb host-register    once: the node certificate, the node entry and the delegate entry
just msb vm-register      for each VM: its entry
just msb agent-up         install and start the agent
just msb agent-status     is it running and healthy?
just msb agent-down       stop it
```

Then ask for the SVID of a running VM:

```text
~/.local/share/agent-workload-identity/bin/delegate \
  -vm sandbox-dev \
  -id spiffe://mcp.local/node/<host-name>/user/<github-id>/vm/sandbox-dev \
  -socket /run/user/<uid>/awi-spire-agent-admin/admin.sock
```

## What `agent-up` does

1. It gets the SPIRE agent 1.15.5. It downloads the release to `~/.cache/agent-workload-identity/` and checks it with `sha256sum -c`. It skips this if the checked files are there.
2. It builds the `msbvm` plugin and the delegate with Go. It installs them in `~/.local/share/agent-workload-identity/bin/`. The delegate entry has the path of the delegate as a selector, so the delegate must be there.
3. It fills in [`agent.conf.tmpl`](agent.conf.tmpl). It writes the result with mode 600 to `~/.local/state/agent-workload-identity/spire-agent/agent.conf`. The config holds the sha256 of the plugin binary. The agent starts the plugin only if the checksum matches.
4. It starts the agent as the user unit `awi-spire-agent`, with `systemd-run --user`. There is no unit file to keep. The unit ends when you run `agent-down`.
5. It waits until the admin socket exists and the health check answers.

The agent attests with the node identity that `host-register` wrote to `~/.config/msb/host-node`. The agent in the VM has its own identity. The two agents do not clash.

## Files and sockets

| Path | What it is |
|---|---|
| `~/.config/msb/host-node/` | `node.key` (mode 600), `node.crt` and `bundle.json` of the host |
| `~/.local/state/agent-workload-identity/spire-agent/` | `agent.conf` and the data of the agent (its SVID and key) |
| `$XDG_RUNTIME_DIR/awi-spire-agent/agent.sock` | The Workload API socket |
| `$XDG_RUNTIME_DIR/awi-spire-agent-admin/admin.sock` | The admin socket. It is in another folder, because the agent refuses to start if both sockets share a folder. |
| `~/.local/share/agent-workload-identity/bin/` | `msbvm` and `delegate` |

The log is in the journal: `journalctl --user -u awi-spire-agent`.

## What to know

- **The agent runs as your user.** It reads the node key, which only your user can read. The VM never gets the key or a socket of the agent.
- **Only the delegate can use the admin socket.** The agent attests the caller with the `unix` attestor: the uid and the path of its binary. A copy of the delegate at another path gets `PermissionDenied`. The ID of the delegate must also be in `authorized_delegates`.
- **A new entry takes a few seconds.** The controller manager copies it to the server, and the agent syncs it. After `vm-register`, the delegate gets zero SVIDs for about 8 seconds. Ask again. A step that asks for the SVID must retry.
- **The delegate entry has the path of the binary.** If you move the delegate, run `host-register` again with the new path.
- **The agent does not start with the VM yet.** Run `agent-up` yourself until `just msb run` does it.

## Files

- `agent.conf.tmpl`: the config of the agent, with the values that `agent-up` fills in.
