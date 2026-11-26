---
status: accepted
---

# Docker Compose and the devcontainer CLI, not Quadlet units

The sandbox has four services: the agent sandbox, the builder and two proxies. One `compose.yaml` holds all of them, and `devcontainer.json` starts them with the devcontainer CLI on rootful Docker. This replaces the Quadlet units of [ADR 0001](0001-quadlet-over-compose.md). The goal is one declarative spec and a devcontainer workflow.

## Decision

- `compose.yaml` holds the services, the two internal networks, the run-time env, the limits, the hardening and the mounts. The proxy image is inline (`dockerfile_inline`). The builder uses the upstream BuildKit image.
- The agent sandbox and the builder each sit on an internal network (`internal: true`, `inhibit_ipv4`). Each one reaches only its proxy, at a fixed IP. No relay and no socket file are needed.
- The proxies run on `runc` as a dedicated uid with no capabilities. The agent sandbox and the builder run on gVisor (`runsc-uds`, `runsc-builder`).
- `initializeCommand` decrypts the Bitwarden access token into RAM. The proxy reads the file and deletes it. `postStartCommand` runs the task `sandbox:start`.
- The devcontainer CLI has no stop. `just sandbox down` stops the sandbox, and `just sandbox apply` applies an edit (down, then up).

## Why the reasons of ADR 0001 no longer hold

- **Limits:** rootful Docker enforces memory, CPU and pids limits under gVisor. Rootless Docker and rootless Podman cannot (a systemd scope fails with "Access denied").
- **Start order:** `depends_on` with `service_healthy` holds the agent sandbox until both proxies and the builder are healthy. The proxy is healthy only after `bws` has fetched the secrets.
- **Steps without a key:** gVisor brings up the loopback by itself with `network none` or an internal network. The relays are gone. `sandbox:start` is a lifecycle command.
- **The secret:** the Bitwarden token stays encrypted at rest with systemd-creds. It is in RAM for a few seconds per start, and nothing holds it after a stop.

## Considered options

- **Keep Quadlet.** It works, but the spec stays spread over four units, two runsc flag files and the host bridge.
- **Rootless Docker or Podman with Compose.** They cannot enforce limits under gVisor.
- **`network none` with a Unix socket and socat on both sides.** No network device exists, so the guarantee holds by structure. The owner chose the internal network, because it has fewer parts. Three layers keep the host out: no host address on the bridge, no IPv6 address in gVisor, and ufw.
- **`userns-remap`.** It is daemon-wide, hides the images that exist and likely breaks `kind`. A dedicated non-root uid gives the proxies the same protection.
- **Builds on the host Docker daemon.** The Docker API is root on the host, so an agent with it can escape the sandbox.

## Consequences

- The `docker` group is root on the host. Only the user who runs the sandbox belongs in it.
- `devcontainer up` on stopped containers starts them as they were. An edit needs `just sandbox apply`.
- `docker compose restart proxy` fails, because the token file is gone. Start through `devcontainer up`.
- `devcontainer build` needs `BUILDX_BAKE_ENTITLEMENTS_FS=0` with Compose 5.6. The root `mise.toml` and the justfile set it.
