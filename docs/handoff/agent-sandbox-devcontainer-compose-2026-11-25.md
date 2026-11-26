# Handoff: move the agent sandbox to .devcontainer, Docker Compose and gVisor

Date: 2026-11-25. Repo: `raghav19/engineersdaybook`, main checkout `/home/rana/Projects/engineersdaybook`.
Read first: `AGENTS.md` (root), `.sandbox/AGENTS.md`, `docs/agents/pull-requests.md`, `docs/agents/diagrams.md`.

## Goal

The owner wants the whole agent sandbox in one declarative spec with a devcontainer-like experience. The plan replaces rootless Podman and Quadlet (`.sandbox/`) with rootful Docker, one `compose.yaml` and `.devcontainer/`. gVisor stays the runtime. iron-proxy stays the only way out. The team has not implemented this plan yet.

## What merged today (do not redo)

- PR #398: Starship and ble.sh in the sandbox image, `sandbox:shell`, `sandbox:herdr-plugins` mise tasks.
- PR #399: ble.sh removed from the image (a `$USER` warning at each start).
- PR #400: fzf added to `tools/dev.toml`. The commit also removed the tool comments in `dev.toml`.
- Host: ble.sh removed. Rootless Docker removed. `~/.bashrc` restored from backup.
- Memory file `sandbox-image-tasks-in-mise-toml-2026-11-25.md` is now out of date. See Decisions 6 and 7.

## Research and evidence (read, do not repeat)

- `docs/research/agent-sandbox-manifest-spec.md`: no ready-made standard covers the whole sandbox. It compares Compose, Dev Container, the kit spec, Quadlet and `kube play` against sources.
- `.sandbox/docs/adr/0001-quadlet-over-compose.md`: the old reasons for Quadlet. The owner now accepts Compose, so this needs a new ADR (0002) that supersedes it.
- Spike files, volatile, copy them if needed: `/tmp/claude-1000/-home-rana-Projects-engineersdaybook/328b81a0-7cd7-4681-a87e-98d791d9a561/scratchpad/spike/compose.yaml` (stub proxy and the real agent image).

## Spike results (rootful Docker 29.9.2, cgroup v2, systemd driver)

Works:
- `runsc` as a Docker runtime. `runsc-uds` is `--host-uds=open`.
- `--network none` gives a working loopback under default `runsc`. The sandbox needs no `network=host` flag and no `nsenter` step.
- Docker enforces memory, CPU and pids limits. gVisor counts host threads, so a pids limit of 20 stops the sandbox. Use a generous value (2048 today).
- These Compose features work: `depends_on` with `service_healthy`, `post_start`, `read_only` and `cap_drop`.
- `restart: true` restarts the agent when you restart the proxy through Compose.
- A unix socket in a named volume connects two services.
- The path from the agent to the proxy works through a `socat` relay.
- With `--network none` the agent has only `lo`, no route, no DNS, and no Docker socket.

Does not work or is a limit:
- Rootless Docker and rootless Podman cannot enforce limits under gVisor. `--systemd-cgroup` fails with "Access denied". Likely cause (my reading of `runsc/cgroup/systemd.go`): the driver uses the system manager bus, not the user bus. This is why the move needs the rootful daemon.
- Compose refuses `secrets` from an env var and `configs` with inline `content` in a read-only service. Only `file:` works. The Bitwarden token would be a tmpfs file, not a systemd in-memory credential.
- `docker compose publish --dry-run` accepted a bind mount. A real push was not tested (the local registry is HTTP).

## Host state to know

- Rootful Docker is active. The user is in the `docker` group, but old shells lack it. Use `newgrp docker <<< "cmd"` (there is no `sg`).
- `/etc/docker/daemon.json` has runtimes `runsc`, `runsc-suid`, `runsc-uds`. `runsc-builder` does not exist.
- Images loaded into rootful Docker by me: `localhost/sandbox-dev:latest` (6.6 GB), `busybox`, `alpine/socat`. Other images there are the owner's. Do not touch them.
- The Podman sandbox (four containers) was running and was never changed.
- `~/.config/docker/daemon.json` and the rootless daemon are gone.
- The owner's git credential helper points at a removed `gh` path. Pushes worked with `git -c credential.helper= -c credential.helper='!gh auth git-credential' push`. `gh auth setup-git` would fix it for good. GitHub also returned transient errors (retry once).
- A permission check denied starting a daemon from a downloaded script. Ask the owner to run host-root or daemon steps with `!`.

## Decisions (made with the owner)

1. Rootful Docker plus Compose, with gVisor runtimes. The plan drops rootless.
2. One `compose.yaml` holds the services: `proxy`, `builder-proxy`, `builder`, `agent`. Services, runtimes, limits, secrets and start order live there. The three small Containerfiles (proxies) are inline (`dockerfile_inline`).
3. No `.sandbox/` and no `sandbox` subfolder. Everything is in `.devcontainer/`. There is no top-level `devcontainer.json`. There are two named entries: `.devcontainer/agent/devcontainer.json` and `.devcontainer/builder/devcontainer.json`, both over `../compose.yaml`.
4. `sandbox-start` becomes a mise task `sandbox:start`, called by `postStartCommand`.
5. The bridge (`bridge.sh`, `bridge.service`, `ports`) becomes a `bridge` recipe in the `justfile`. It uses a transient `systemd-run --user` unit and `docker exec -i`.
6. Tools and tasks are split: `agent/tools.toml` (all tools, copied first) and `agent/tasks.toml` (tasks, env, hooks, copied last). This keeps the "tasks last" cache rule.
7. Configs stay as files under `agent/configs/{agents,editor,tools}`. The owner rejected a `rootfs/` overlay. Fresh plugin list and installer move into `tasks.toml`.
8. The builder gets its own folder (`builder/Dockerfile`, 5 lines, as a file).
9. Moving `.sandbox` is PR 1, a pure `git mv` plus reference updates. Compose and Docker are PR 2.
10. Quadlet files and both `runsc.conf` files go away after the Docker switch.

Target tree (23 non-docs files, from 38):

```text
.devcontainer/
├── compose.yaml            the spec: 4 services, runtimes, limits, secrets, start order
├── justfile                setup, run, rm, build, verify, bridge
├── README.md  AGENTS.md
├── policy/                 agent.yaml, builder.yaml (iron-proxy policies)
├── agent/
│   ├── devcontainer.json   service: agent, postStartCommand: mise run sandbox:start
│   ├── Dockerfile
│   ├── tools.toml          all tools (copied first)
│   ├── tasks.toml          tasks, env, hooks (copied last)
│   └── configs/            agents/  editor/  tools/
└── builder/
    ├── devcontainer.json   service: builder, runServices: [builder-proxy, builder]
    └── Dockerfile          BuildKit image
```

Start order: `builder-proxy`, then `builder`, then `proxy`, then `agent` (each `service_healthy`).

## Open questions for the owner

- Docs location. Proposal: ADRs, diagrams, internals and posts go to `docs/sandbox/`. `README.md` and `AGENTS.md` stay in `.devcontainer/`.
- Should `runsc-builder` keep `ignore-cgroups`? Rootful Docker enforces limits without it.
- The builder Dockerfile as a file (chosen) or inline.
- Handoff and research notes that mention `.sandbox`: leave as history (proposal) or rewrite.

## Not tested (do these in a spike before PR 2)

1. The real iron-proxy with `bws` and the two-process proxy (socat plus iron-proxy). The spike used a stub.
2. The builder: capabilities `SETUID`, `SETGID`, `SYS_CHROOT`, runtime `runsc-builder` (`host-uds=all`, `network=none`), and an equivalent of `HealthOnFailure=kill` (Compose has none).
3. The bridge through `docker exec -i ... socat - TCP:127.0.0.1:<port>` with `network none`.
4. `mise run sandbox:start` as `postStartCommand` under gVisor with a read-only root. The Compose healthcheck stays unhealthy until it runs.
5. The `devcontainer` CLI (`up`, `exec`, `runServices`, `build.context` from `.devcontainer/`) against the hardened agent.
6. `dockerfile_inline`, `docker compose publish` with a real push, the Docker `journald` log driver.
7. A `just verify` recipe: assert `runtime` is `runsc-uds` and not `runc`, `network_mode: none`, no privileged flag, `CapDrop` ALL, only the expected mounts. Inside the agent: only `lo`, no direct connection, no DNS.
8. Relay supervision. A `socat` started with `&` is not restarted. The proxy socket listener can be a sidecar with `network_mode: service:proxy`. The agent relay must stay inside the agent.

## Next steps

1. Ask which open question the owner answers first (docs location).
2. PR 1: create a worktree with `herdr worktree create --branch <name> --label <slug>`. Run `git mv .sandbox .devcontainer` and reshape per the target tree only if the owner wants it in PR 1. Otherwise move first, then restructure. Update `AGENTS.md`, `README.md`, `justfile` (`mod sandbox`), `prek.toml`, `docs/agents/sandbox-network.md`. The Quadlet links in `~/.config` point at the old path, so `just sandbox setup` must run again on the host.
3. Run the spike in the list above against the real services, then PR 2 with ADR 0002.
4. Update the memory file `sandbox-image-tasks-in-mise-toml-2026-11-25.md` (tasks now in `tasks.toml`).

## Suggested skills

- `research`: for any further spike notes saved under `docs/research/`.
- `prototype`: for the throwaway spike of the real proxy, builder and bridge.
- `asd-ste100`: AGENTS.md section 13 requires it before finishing any text, including PR bodies and comments.
- `pr`: for PR bodies. Also follow `docs/agents/pull-requests.md` step by step.
- `writing-for-agents`: when editing `AGENTS.md`, `.devcontainer/AGENTS.md` or files in `docs/agents/`.
- `domain-modeling`: for ADR 0002 (supersedes ADR 0001).
- `diagnosing-bugs`: if a Compose or gVisor start fails.

## Owner working style (from memory)

The owner wants few files and short commands. Comments are crisp STE. Docs describe the end state only, with no history. Flows are sequence diagrams. Diagrams are drawio, svg and png together. Never push to `main`. Check the state of a PR before you edit it. PRs #398 and #399 merged while the session still edited them.
