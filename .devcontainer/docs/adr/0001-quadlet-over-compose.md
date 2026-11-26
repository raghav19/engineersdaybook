---
status: superseded by ADR-0002
---

# Quadlet units, not Docker Compose or Podman Compose

The sandbox has four containers: the agent sandbox, the builder and two proxies. Each one is a Quadlet `.container` file. Quadlet turns each file into a systemd user service. A `compose.yaml` file does not run the sandbox.

## Decision

- Each container has one `.container` file in `agent/`, `builder/` or one of the two `proxy/` folders. `just sandbox setup` links the files into `~/.config/containers/systemd/`.
- systemd starts, stops and restarts the containers. `just sandbox run` restarts `sandbox-agent.service`, and systemd moves the builder and both proxies with it.
- The bridge on the host is a plain systemd user service. It uses the same tools as the four containers.
- The comments in each `.container` file name the Compose key of each setting. A reader who knows Compose can map each line.

## Considered options

- **Docker Compose.** It needs a Docker API socket. The sandbox is rootless Podman, so this adds a daemon to run and to protect.
- **Podman Compose, or `podman compose`.** Both need a separate Compose provider. The provider reads `compose.yaml` and calls Podman. This adds a tool to install.
- **Plain `podman run` in the `justfile`.** This has no start order, no restart rule and no limits that gVisor respects.

## Why Quadlet

- **The limits work.** gVisor ignores the limits of Podman, so the Compose keys `mem_limit`, `pids_limit` and `cpus` do nothing here. A service sets `MemoryMax`, `TasksMax` and `CPUQuota` on the cgroup of the service. These limits apply to gVisor.
- **The start order and the stop order are in the files.** `Requires=` and `After=` start the builder and the host proxy first. `PartOf=` makes a stop or a restart of the agent sandbox stop or restart them. A new session always gets a new builder and a new proxy. Compose `depends_on` does not do this.
- **The builder gates the start.** `Notify=healthy` holds the dependent units until the builder lists a worker.
- **The secret stays out of the container config.** `LoadCredentialEncrypted=bws-token` makes systemd decrypt the Bitwarden access token into memory for one service. Compose has no encrypted credential store.
- **Some steps have no Compose key.** After the agent container starts, three `ExecStartPost` steps raise the loopback interface, start the relay and run `sandbox-start`. A failed step fails the start.
- **The logs are in one place.** The audit log of the proxy goes to journald: `journalctl --user -u sandbox-proxy`.
- **Nothing extra to install.** Quadlet is part of Podman. systemd is already on the host.

## Consequences

- The sandbox runs only on a Linux host with a systemd user manager. It does not run on macOS or Windows.
- After you edit a `.container` file, run `systemctl --user daemon-reload`. `just sandbox setup` and `just sandbox run` do it for you.
- `podman compose up` does not start the sandbox. Use `just sandbox run`.
- `podman ps` and `podman logs` still work. `systemctl --user status sandbox-agent` shows a service that a limit killed.
