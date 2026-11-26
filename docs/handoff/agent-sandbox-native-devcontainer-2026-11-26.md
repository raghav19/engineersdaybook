# Handoff: the native devcontainer sandbox (PRs #407 to #416)

Date: 2026-11-26. Repo: `raghav19/engineersdaybook`, main checkout `/home/rana/Projects/engineersdaybook`.
Read first: `.devcontainer/README.md` (prerequisites, commands, "Update the agent image"), `.devcontainer/AGENTS.md`, root `AGENTS.md` (sections 13 and 16), `docs/agents/pull-requests.md`.
Earlier handoff: [`agent-sandbox-devcontainer-compose-2026-11-25.md`](agent-sandbox-devcontainer-compose-2026-11-25.md) (Decisions 11 to 30, still the base design).

## Goal

The owner wants a sandbox that runs with the native devcontainer workflow: `devcontainer build`, `devcontainer up` and `devcontainer exec`. Custom scripts stay only where the spec or the CLI has no feature. Comments and docs use plain words (see root `AGENTS.md` section 16).

## Next step (blocks the first start)

`main` pins the agent image `ghcr.io/raghav19/engineersdaybook/sandbox-dev:97a22d03cd2b99e6ab7e8cb792cdd826df20e77b`. That image is not in `ghcr.io`. `devcontainer up` fails to pull it.

1. Check the ghcr.io login as the normal user: `docker manifest inspect ghcr.io/raghav19/engineersdaybook/sandbox-dev:0c26051303b4013f538aeb86830ee799e94e056c`. On 2026-11-26 the owner reported a login, but `~/.docker/config.json` had no `ghcr.io` entry and this command failed. Ask the owner to run `docker login ghcr.io -u raghav19` again without `sudo`.
2. Run the commands of README "Update the agent image" for the tree on `main` (`git rev-parse HEAD:.devcontainer/agent`). The first push also fills the tag `:cache`.
3. Open a one-line PR that adds `@sha256:<digest>` to the `image` line of the service `agent` in `compose.yaml`.
4. After the merge, run the first real `devcontainer up --workspace-folder .` in the main checkout. Nobody ran a full `up` on Docker yet. Check: four services healthy, `devcontainer exec --workspace-folder . herdr` works, `claude plugin list` shows ponytail and TokenEconomizer enabled, a call to `api.github.com` through the proxy returns `200`.

## What merged in this session

| PR | Change |
|---|---|
| #407 | Comments in `compose.yaml` for the networks, limits and BuildKit flags |
| #408 | `init.sh` as `initializeCommand`. One-time host steps moved to README prerequisites. gVisor pinned in the root `mise.toml`. |
| #409 | Agent image from `ghcr.io` (private), tag = git tree sha of `agent/`. `build` and `publish` split. |
| #410 | Root `AGENTS.md` section 16: lead with the effect in plain words, a trade-off on its own line |
| #411 | Plain `docker compose -p sandbox stop` and `down` in place of `just` recipes. Host port bridge and Plannotator parked. |
| #412 | `tasks.toml` gone. Plugins in a build stage `stage8-plugins`. Fresh packages by `ADD` of a pinned git folder. |
| #413 | One `devcontainer.json`, lifecycle scripts in the image, no justfile, agent image pinned inline in `compose.yaml` |
| #414 | `agent/devcontainer.json` as the build config: `devcontainer build --push`, hooks in the image label |
| #415 | `init.sh` fetches the API tokens into RAM files. Both proxies run the upstream iron-proxy image. |
| #416 | iron-proxy 0.61.0, BuildKit v0.35.1 (index digest), gVisor 20261123 |

## The design now

```text
.devcontainer/
├── devcontainer.json        # run: Compose, runServices, initializeCommand (no lifecycle hooks here)
├── compose.yaml             # 4 services, each image pinned on its own line
├── init.sh                  # host: checks, then the API token files for a new proxy
├── policy/agent.yaml        # iron-proxy: allowlist, file sources in /run/secrets
├── policy/builder.yaml
└── agent/
    ├── devcontainer.json    # build: Dockerfile, cacheFrom. onCreateCommand, postStartCommand go into the image label
    ├── Dockerfile           # tool stages, stage8-plugins, final stage
    ├── lifecycle/on-create.sh, post-start.sh
    ├── tools/*.toml
    └── configs/
```

Start: `devcontainer up` runs `init.sh`, then Compose starts builder-proxy, builder and proxy, then the agent. The CLI then runs `sandbox-on-create` (new container only) and `sandbox-post-start` (each start) from the image label.

## Decisions of the owner (with the reason)

| Decision | Reason |
|---|---|
| systemd-creds keeps the Bitwarden access token. The owner rejected the OS keyring (`secret-tool`). | systemd-creds is TPM2-bound on this host. The keyring gives no extra protection. |
| `bws` runs on the host in `init.sh`. iron-proxy reads one file per token (`file` source). | No `bws` and no custom image in the proxy. iron-proxy has no Bitwarden source. |
| Accepted: the host user can read the token files in `$XDG_RUNTIME_DIR` during a session. | The files are tmpfs. Swap is zram, then a swap file in LUKS. Confidential computing is not possible (i7-13700H, no TDX or SEV). |
| The `bws run` parent fix ("fetch once, then exec") is not needed now | #415 removed `bws` from the proxy. |
| Fetch at run time (`vault_kv`) waits for OpenBao | iron-proxy then holds a store token. A restart per session is enough today. |
| `devcontainer build --push` with a build-only `agent/devcontainer.json` | The owner wants the native build. The CLI refuses `--push` and `--cache-to` for Compose configs (`devContainersSpecCLI.ts`). |
| Lifecycle hooks only in `agent/devcontainer.json` | The CLI merges the hooks of the image label and of the run config. A hook in both runs twice. |
| Image pin inline in `compose.yaml`, committed. No `.env`. | The running image must be in git, on the same kind of line as the other images. |
| Tag = `git rev-parse HEAD:.devcontainer/agent` | A squash merge drops the branch commit. The tree sha stays. |
| The `ghcr.io` package stays private. `docker login ghcr.io` is a host prerequisite. | A host setting, like the `gh` login |
| The clone stays (on-create clones the read-only `.git`) | A writable host `.git` lets the agent run code on the host through hooks and `core.*` config. |
| `--oci-worker-no-process-sandbox` stays | A per-step PID namespace needs `systempaths=unconfined`. The agent owns every build. |
| No justfile, no host port bridge, no Plannotator | The devcontainer CLI and `docker compose` cover the rest. Plannotator is separate work. |

## Parked and open

- **CA as a Compose service.** README prerequisite 4 has a TODO: a one-shot service that writes the CA into a tmpfs volume. Spike it under gVisor first.
- **Host port bridge and Plannotator.** Parked. The devcontainer CLI has no `forwardPorts` (devcontainers/cli #186, #22, #1308).
- **Snapshotter.** `--oci-worker-snapshotter=native` has a TODO: overlayfs passed a 2-step build under gVisor. Test it with a build of the agent image.
- **Trap comment.** #407 removed the comment "no-new-privileges stays off on the builder: with it, rootlesskit hangs". Offer to put it back.
- **Docs end state (PR 4 of the earlier handoff).** `.devcontainer/README.md` still has the Podman flows and troubleshooting rows (`just sandbox run`, `journalctl`, `proxy.sock`). `.devcontainer/docs/internals.md` and the diagrams are stale.
- **CI for the agent image.** A workflow could run the build and the push for each PR that touches `agent/`.
- **Token hygiene.** Scope each API token and give it an expiry. The Bitwarden machine account reads only the sandbox project.
- **TokenEconomizer is not pinned.** `stage9-token-economizer` clones `TE_REPO` at the default branch.

## Traps found in this session

- The devcontainer CLI runs lifecycle commands inside the container (`/bin/sh -c` in `remoteWorkspaceFolder`). A script path works only if the image or a mount has the file.
- The `onCreateCommand` marker is `$HOME/.devcontainer/.onCreateCommandMarker` with the creation time of the container. The home is a volume, but a new container still runs the hook again.
- `yq -i` reformats the whole Compose file. Edit the image line by hand.
- `docker compose -p <name> ps`, `stop` and `down` work without `-f`.
- A directory default ACL (`setfacl -m d:u:10001:r`) gives each new file the read access, also with `umask 077`.
- gVisor ships as `gvisor.tar.bz2` (runsc and `gvisor-bin/`). The URL of the single `runsc` file gives 404. `runsc install --runtime=<name> -- <flags>` and `runsc uninstall --runtime=<name>` edit `daemon.json`.
- Docker uses the containerd image store here, so the default builder can write a registry cache.
- The Claude plugins: keep only `~/.claude/plugins` in the image. `enabledPlugins` in `managed-settings.json` enables them.

## Host state on 2026-11-26

- `/usr/local/bin/runsc` is `release-20261123.1`. `daemon.json` has only `runsc-uds` (`--host-uds=open`) and `runsc-builder` (`--host-uds=create`).
- This session removed the Podman Quadlet links in `~/.config`.
- `$XDG_RUNTIME_DIR/sandbox-secrets` holds the 4 token files from the tests. Logout empties it.
- `~/.config/git/config` points the GitHub credential helper at a `gh` path that no longer exists. `gh auth setup-git` fixes it.
- The remote branch `sandbox-init-script` came back after #408 merged. It holds no new work. Remove it.
- About 40 old Herdr worktrees exist (Podman era and other work). Ask before you remove them.
