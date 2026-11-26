# Handoff: move the agent sandbox to .devcontainer, Docker Compose and gVisor

Date: 2026-11-25, updated 2026-11-26. Repo: `raghav19/engineersdaybook`, main checkout `/home/rana/Projects/engineersdaybook`.
Read first: `AGENTS.md` (root), `.devcontainer/AGENTS.md`, `docs/agents/pull-requests.md`, `docs/agents/diagrams.md`.

## Goal

The owner wants the whole agent sandbox in one declarative spec with a devcontainer-like experience. The plan replaces rootless Podman and Quadlet with rootful Docker, one `compose.yaml` and the devcontainer CLI. gVisor stays the runtime of the agent and the builder. iron-proxy stays the only way out.

## What merged (do not redo)

| PR | Change |
|---|---|
| #398 | Starship and ble.sh in the sandbox image, `sandbox:shell`, `sandbox:herdr-plugins` mise tasks |
| #399 | ble.sh removed from the image (a `$USER` warning at each start) |
| #400 | fzf added to `tools/dev.toml` |
| #402 | `git mv .sandbox .devcontainer` and the path updates. The sandbox still runs on Podman and Quadlet. |
| #403 | Image `mise.toml` is now `tasks.toml` (env, hook, tasks). `sandbox-start` is the task `sandbox:start`. The Fresh package list is in the task `fresh:plugins`. |

## Research and evidence (read, do not repeat)

- `docs/research/agent-sandbox-devcontainer-spike.md`: spike S1 to S6, all pass. S1 is the network model. S2a and S2b are the hardened proxy and the real bws token. S3 is the builder, S4 the agent with the full env. S5 is the devcontainer CLI workflow, S6 the host port bridge. Each stage lists its traps.
- `docs/research/agent-sandbox-manifest-spec.md`: no ready-made standard covers the whole sandbox.
- `.devcontainer/docs/adr/0001-quadlet-over-compose.md`: the old reasons for Quadlet. ADR 0002 must supersede it in PR 3.

## Spike results of 2026-11-25 (rootful Docker 29.9.2, cgroup v2, systemd driver)

Works:
- `runsc` as a Docker runtime. `runsc-uds` is `--host-uds=open`.
- Docker enforces memory, CPU and pids limits. gVisor counts host threads, so a pids limit of 20 stops the sandbox. Use a generous value (2048 today).
- These Compose features work: `depends_on` with `service_healthy`, `post_start`, `read_only` and `cap_drop`.

Does not work or is a limit:
- Rootless Docker and rootless Podman cannot enforce limits under gVisor. `--systemd-cgroup` fails with "Access denied". This is why the move needs the rootful daemon.
- Compose refuses `secrets` from an env var and `configs` with inline `content` in a read-only service. Decision 17 avoids Compose `secrets` for this reason.

## Host state to know

- Rootful Docker is active. The user is in the `docker` group. ufw is active with a default deny for incoming traffic.
- `/etc/docker/daemon.json` has runtimes `runsc`, `runsc-builder` (`--host-uds=all`), `runsc-suid`, `runsc-uds`.
- `~/.local/state/sandbox/ca.key` has a POSIX ACL `user:10001:r--` (Decision 15). Undo: `setfacl -x u:10001 ~/.local/state/sandbox/ca.key`.
- The host has the devcontainer CLI 0.91.0 from mise (`npm:@devcontainers/cli`).
- After #402 and #403 the Quadlet links still point to `.sandbox/` until the owner runs `just sandbox setup`, then `just sandbox build`.
- The owner's git credential helper points at a removed `gh` path. Push with `git -c credential.helper= -c credential.helper='!gh auth git-credential' push`.
- Ask the owner to run host-root steps with `!`.

## Decisions of 2026-11-25 (made with the owner)

1. Rootful Docker plus Compose, with gVisor runtimes. The plan drops rootless.
2. One `compose.yaml` holds the services: `proxy`, `builder-proxy`, `builder`, `agent`. (Changed by Decisions 21 and 23: one inline proxy image, no builder Dockerfile.)
3. Everything is in `.devcontainer/`. (Changed by Decision 20: one `.devcontainer/devcontainer.json`, no builder entry.)
4. `sandbox-start` becomes a mise task `sandbox:start`, called by `postStartCommand`. (Done in #403.)
5. The bridge (`bridge.sh`, `bridge.service`, `ports`) becomes a `bridge` recipe in the `justfile`. It uses a transient `systemd-run --user` unit and `docker exec -i`.
6. One `tools.toml`. (Changed by Decision 25: `tools/` keeps 5 files.)
7. Configs stay as files under `agent/configs/{agents,editor,tools}`. The owner rejected a `rootfs/` overlay. (Changed by Decision 12: env replaces `gitconfig` and `k9s-config.yaml`.)
8. The builder has its own folder. (Changed by Decision 23: no builder folder.)
9. PR order. (Changed: see the PR order below.)
10. Quadlet files and both `runsc.conf` files go away after the Docker switch.

## Decisions of 2026-11-26 (made with the owner)

11. **Env only in `compose.yaml`**, per service, under one comment heading per group: wiring, base, git, runtimes, infra, dev, agents, lsp. No mise `[env]`, no `containerEnv` or `remoteEnv`. The Dockerfile `ENV` keeps only build-time vars (`PATH`, `LANG`, `MISE_*`, `COMPLETIONS_DIR`). Write `$$` for a literal `$`, and write literal `/home/agent` paths, because Compose interpolates from the host.
12. Env replaces files: `gitconfig` (`GIT_CONFIG_COUNT`, `GIT_CONFIG_KEY_n`, `GIT_CONFIG_VALUE_n`), `k9s-config.yaml` (`K9S_SKIN`), `agent/ports` (`PLANNOTATOR_PORT`), the Qwen model block (`OPENAI_BASE_URL`, `OPENAI_MODEL`, `OPENAI_API_KEY` with the Qwen placeholder). `qwen-settings.json` keeps auth and `mcpServers`. `managed-settings.json` stays a file (policy). `EDITOR=fresh`.
13. **Only the devcontainer CLI**: `devcontainer build`, `up`, `exec`. The CLI has no stop or down command (devcontainers/cli PRs #1339 and #1041 are open). Stop is `docker compose -p sandbox stop|down`. `name: sandbox` in `compose.yaml` fixes the project name. `just apply` is `down`, then `devcontainer up`. See the traps below.
14. **Egress by Docker internal networks.** No socat relay and no `proxy.sock`. Network `sandbox` 10.200.0.0/29 (proxy .2, agent .3) and network `build` 10.200.0.8/29 (builder-proxy .10, builder .11). Both are `internal: true` with `com.docker.network.bridge.inhibit_ipv4: "true"`. The proxies are also on the Compose `default` network. The proxy IPs are fixed, because gVisor cannot use Docker DNS. iron-proxy binds `tunnel_listen` to the internal IP only. The other listeners stay on `127.0.0.1`. The BuildKit socket stays a Unix socket, so the agent keeps `runsc-uds`. The socket model (network none, socat, `proxy.sock`) is the fallback if a spike check fails.
15. **Proxies on runc**, not runsc. Hardening: uid `10001:10001`, read-only root, `cap_drop: ALL`, no-new-privileges, init, `restart: "no"`, `/tmp` tmpfs with `noexec,nosuid,nodev`, `mem_limit` equal to `memswap_limit`, `pids_limit`, `cpus`, `ulimits: core: 0`. Access to `ca.key` by POSIX ACL only (`setfacl -m u:10001:r`). All mounts are read-only except the secrets folder.
16. **Proxy healthcheck**: `wget -q -O /dev/null http://127.0.0.1:18083/healthz`. iron-proxy starts after `bws` fetches the secrets, so the agent waits with `service_healthy`. `/metrics` returns 404.
17. **Token flow** (bws now, OpenBao later). `initializeCommand` runs `just pre-up` on the host. If the proxy does not run, `pre-up` decrypts the bws token with `systemd-creds --user decrypt` into `$XDG_RUNTIME_DIR/sandbox-secrets/` (folder 0700 plus ACL `u:10001:rwx`, file 0600 plus ACL `u:10001:r`). The proxy reads the file, removes it and runs `exec bws run -- env -u BWS_ACCESS_TOKEN iron-proxy`. No Compose `secrets`, no token in `environment:`.
18. No userns-remap. It is daemon-wide, it hides the existing images and it can break kind. The non-root proxy uid gives the same result for the proxy.
19. No `just verify` recipe. The owner's reason: the setup is declarative and the agent cannot change it.
20. One `.devcontainer/devcontainer.json` (the agent): `runServices` lists all four services, `updateRemoteUserUID: false`, `overrideCommand: false`, `initializeCommand: just -f .devcontainer/justfile pre-up`, `postStartCommand: mise run sandbox:start`. The agent keeps `command: ["sleep", "infinity"]` in `compose.yaml`. With the default `overrideCommand`, the CLI entrypoint runs the image CMD `bash`, and bash exits with no TTY (spike S5).
21. One inline proxy image (iron-proxy plus bws, by digest, no socat) for both proxies. `builder-proxy` runs it without a token.
22. The policies are mounted read-only from `.devcontainer/policy/`. No copy into `~/.config/sandbox/`.
23. The builder uses the upstream rootless BuildKit image by digest. No `builder/` folder. Runtime `runsc-builder` with `--host-uds=all` only (no `network=none`, no `ignore-cgroups`).
24. Rejected: builds on the host Docker daemon, also through the proxy. The Docker API is root on the host.
25. `tools/` keeps 5 files, one Docker stage each (per-group cache, parallel build).
26. `workspaceFolder: /home/agent`. The CLI runs the lifecycle commands in `workspaceFolder`. The clone `/home/agent/engineersdaybook` does not exist before `sandbox:start` makes it (spike S5).
27. `devcontainer build` needs `BUILDX_BAKE_ENTITLEMENTS_FS=0` on the host. The CLI writes its wrapper Dockerfile to `/tmp/devcontainercli-<user>/`, and Compose 5.6.1 (bake) refuses that path. PR 3 decides where to set the variable (spike S5).
28. The BuildKit socket: the builder mounts the volume `buildkit-sock` at `/run/user/1000`. That folder has owner 1000 in the image, so Docker gives the volume the same owner. The socket is `/run/user/1000/buildkit/buildkitd.sock`. The agent mounts only the subpath `buildkit`, read-only, at `/run/sandbox/buildkit`. The folder is 0700 with owner 1000, so the agent user must stay uid 1000 (spike S3).
29. Registry login runs in the agent. buildx (the client) fetches the registry token, so the agent needs its proxy for the token endpoints (`auth.docker.io`, the GHCR `/token`). buildkitd pulls the layers with the proxy of its container env. `RUN` steps take the proxy from `proxies` in `docker-config.json`: `http://10.200.0.10:18080` (spike S3).
30. `devcontainer up --remove-existing-container` is not used. It makes a new agent only. If the proxy config changed, Compose also makes a new proxy, but `pre-up` already skipped the decrypt, and the proxy exits 1 with no token. To apply a change, use `just apply` (spike S5).

## Traps of the devcontainer CLI

Source: devcontainers/cli `src/spec-node/dockerCompose.ts`.

| State at `devcontainer up` | What the CLI does |
|---|---|
| No containers | `docker compose build` and `up -d` for all `runServices`. Changes apply. |
| Stopped | `up -d --no-recreate`, no build. Changes do not apply. |
| Agent runs | Attaches only. `initializeCommand` still runs, so `pre-up` must skip the decrypt. |
| `--remove-existing-container` | Removes the agent only. A new proxy has no token (Decision 30). |

`docker compose restart proxy` fails, because the proxy removed its token. Use `just apply`. Never use `down -v`: it removes the home volume.

## Target tree (19 files outside docs)

```text
.devcontainer/
├── devcontainer.json       the agent: runServices, initializeCommand, postStartCommand
├── compose.yaml            2 internal networks, 4 services, all run-time env, limits, hardening, inline proxy image
├── justfile                setup · pre-up · apply · down · bridge · publish
├── README.md  AGENTS.md
├── policy/                 agent.yaml (tunnel 10.200.0.2:18080), builder.yaml (tunnel 10.200.0.10:18080)
└── agent/
    ├── Dockerfile
    ├── tools/              runtimes, infra, dev, agents, lsp (.toml)
    ├── tasks.toml          tasks and the shell hook, no [env]
    └── configs/
        ├── agents/         managed-settings.json, qwen-settings.json
        ├── editor/         fresh-config.json, omarchy-terminal.json
        └── tools/          docker-config.json, herdr-config.toml, starship.toml, 2 k9s skins
```

`docker-config.json` sends build steps to `http://10.200.0.10:18080`. `publish` is the old `build` recipe (GHCR login with `GITHUB_TOKEN` from bws, then push). Start order: `builder-proxy`, `builder`, `proxy`, `agent`.

Host side, outside the repo: the `daemon.json` runtimes, `~/.config/credstore.encrypted/bws-token`, the CA with its ACL, the `~/.config/sandbox/repo.git` link, `$XDG_RUNTIME_DIR/sandbox-secrets/` (per start), the devcontainer CLI.

## PR order

| PR | Scope | State |
|---|---|---|
| 1 | Move `.sandbox` to `.devcontainer` | Merged (#402) |
| 2 | Image setup steps into `tasks.toml` | Merged (#403) |
| A | This handoff and the spike note (S1, S2) | Merged (#404) |
| B | Spike S3 to S6, the fix of Decision 20, Decisions 26 to 30 | Open |
| 3 | Docker switch: `compose.yaml`, `devcontainer.json`, justfile, policies, ADR 0002. Remove the Quadlet units, `runsc.conf`, `ports`, `bridge.*`, `gitconfig`, `k9s-config.yaml` and the Qwen model block. | In progress (spike S1 to S6 pass) |
| 4 | Docs end state: README, `.devcontainer/AGENTS.md`, internals, diagrams, `docs/agents/sandbox-network.md` | After PR 3 |

## Open questions for the owner

- Docs location. Proposal: ADRs, diagrams, internals and posts go to `docs/sandbox/`. `README.md` and `AGENTS.md` stay in `.devcontainer/`.

## Next steps

1. PR 3, then PR 4.
2. Update the memory file `sandbox-image-tasks-in-mise-toml-2026-11-25.md`: the tasks are in `tasks.toml`, and the env moves to `compose.yaml`.

## Suggested skills

- `prototype`: for the spike stages.
- `asd-ste100`: AGENTS.md section 13 requires it before finishing any text, including PR bodies and comments.
- `pr`: for PR bodies. Also follow `docs/agents/pull-requests.md` step by step.
- `writing-for-agents`: when editing `AGENTS.md`, `.devcontainer/AGENTS.md` or files in `docs/agents/`.
- `domain-modeling`: for ADR 0002 (supersedes ADR 0001).
- `diagnosing-bugs`: if a Compose or gVisor start fails.

## Owner working style (from memory)

The owner wants few files and short commands. Comments are crisp STE. Docs describe the end state only, with no history. Flows are sequence diagrams. Diagrams are drawio, svg and png together. Never push to `main`. Check the state of a PR before you edit it. The owner reviews PRs on GitHub.
