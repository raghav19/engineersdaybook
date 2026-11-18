# Handoff: docker build and crane push in the agent sandbox, and the build capability research

Written on 2026-11-18. The index of all handoff documents is `docs/handoff.md`. This document continues [agent-sandbox-session-2026-11-18.md](agent-sandbox-session-2026-11-18.md) and [agent-sandbox-buildkit-builder.md](agent-sandbox-buildkit-builder.md). Those documents record the builder and the proxy guard. This one records the change from `buildctl` to `docker`, the second proxy for the builder and the push with `crane`. It also records the rejected options, so that nobody offers them again.

## State of the work

- [PR #323](https://github.com/raghav19/engineersdaybook/pull/323) is in `main` (commit `b4c9525`). It holds the code, the three rewritten docs and the new diagram. The body of the PR has the test evidence.
- The host has not run the new setup, as far as this session knows. See "Next steps".
- The research note on build capability in agent sandboxes is in [PR #325](https://github.com/raghav19/engineersdaybook/pull/325). The file is `docs/research/agent-sandbox-build-capability.md`. The owner asked what sources recommend. The short answer: sources rarely cover builds. Code builds stay in the sandbox with a host allowlist. For image builds, sources ship from a trusted CI, or use a microVM with its own daemon. No source describes a separate disposable builder for an untrusted agent. Read the note for the ranking and the gaps of this design.
- The worktree `sandbox-docker-buildx` still holds a git stash, `option B: registry proxy for builder push`. The owner rejected that design. Do not apply it.

## The design in one view

The agent runs `docker build --output type=docker,dest=FILE` and then `crane push FILE REF`. For the picture and the flows, read `.sandbox/README.md` and `.sandbox/docs/internals.md`. The terms are in `.sandbox/docs/internals.md#the-names`.

- The agent sandbox has the `docker` client and the `buildx` plugin, with no daemon. The read-only folder `/etc/docker` selects the builder `sandbox`. Its endpoint is `buildkitd.sock`.
- The builder is a second gVisor container with BuildKit. It has no network device and no secret.
- Both containers use the same model for a call to the outside: a `socat` relay, a Unix socket, a bridge and a proxy.
- The host proxy swaps placeholders for real tokens. The builder proxy checks host names only and holds no token.
- The push runs in the agent sandbox. `crane` uses a placeholder login from `/etc/docker/config.json`. The host proxy swaps in the real token.

## How the decisions came about

The owner wanted `docker` commands that work as on any host, with no wrapper to maintain and a small attack surface. The Makefile or justfile of a repo must work with two small changes. The owner rejected the options below. Do not offer them again without a new reason.

| Topic | Path of the decision | Final choice |
|---|---|---|
| Client in the agent sandbox | `buildctl` with `--oci-layout` needs a translation of each Dockerfile. The owner called this a custom wrapper. | `docker` with the `buildx` remote driver. |
| Where the endpoint lives | A driver key in `~/.docker/config.json`, then an environment variable. `buildx create` reads `BUILDKIT_HOST` only once, at creation. | The instance file in `/etc/docker/buildx/instances/`, made at image build. The folder is read-only. |
| Network for the builder | Pre-pulled base images only, then one shared proxy. A shared proxy makes `RUN` steps fail on the CA. It lets a build step swap every token. | A second iron-proxy, the builder proxy, in `sni-only` mode. |
| Who pushes | The builder pushes through a registry proxy with a CA (option B, three proxies). The owner said "super complex". | The agent sandbox pushes. The builder holds no login. |
| Push tool | `skopeo` (a Debian stage to copy the binary), then `crane` from `mise`. | `crane`. It reads the login from the config of `docker`. |
| Output format | `type=oci` needs an unpack for `crane`. | `type=docker`. It supports one platform. |
| `docker push` | A wrapper that runs `crane`. | No wrapper. Use `crane push FILE REF`. |
| `buildx` install | A checksum download in the Dockerfile. | `mise` with `rename_exe` and `cliPluginsExtraDirs`. |
| Names | `sandbox` and `build proxy`. | `sandbox-agent`, `sandbox-builder`, `host proxy`, `builder proxy`. |
| Docs | Long prose. | Short text, mermaid diagrams, two-column tables and one table of terms. |
| File count | Template units for the two proxies. | Deferred by the owner. See "Open decisions". |

## Test status

The PR body has the list of results. In short: the new image builds an unchanged Dockerfile through the builder proxy. `crane push` works with the placeholder login. A blocked host fails. The read-only config stops a change. The test used renamed containers and units.

Not tested:

- `just sandbox setup` with `sudo`, and the live `sandbox-agent.service`.
- A real `npm install` or `pip install` in a `RUN` step, and `docker buildx bake`.
- `network=none` for the agent container (a TODO in `runsc.conf`).
- Parallel builds, a memory bomb and a fork bomb against the limits.

## Open decisions (ask the owner)

1. The builder proxy allowlist has `deb.debian.org`, `security.debian.org` and `dl-cdn.alpinelinux.org`. The host proxy does not allow them. Keep or remove them.
2. Apply or drop the git stash of option B in the worktree `sandbox-docker-buildx`. Then remove that worktree with `herdr worktree remove`.
3. Template units for the proxies (`sandbox-proxy@.service` and the bridge units). They save about 3 files. The owner deferred this. Do not start it without a request.
4. The Dockerfile stage numbers skip 8. This gap is old, and it is not part of this work.
5. The open decisions of the earlier handoff are still open. They are: three stale untracked files, two untracked handoffs to commit or keep, and the Go listener in `code/agent-sandbox/builder/`.
6. The research note lists ten open questions. The main ones: who signs a pushed image, and does the agent need to ship images or only test them.
7. The host proxy swaps the `ghcr.io` token for any path of `ghcr.io`. The earlier plan had a path rule for `/v2/raghav19/sandbox-builds/**`. Decide on a path rule in `proxy/iron-proxy.yaml`, and check the scope of the `GITHUB_TOKEN` behind the placeholder.

## Next steps

1. On the host, stop the old unit and remove its link: `systemctl --user stop sandbox.service`, then remove `~/.config/containers/systemd/sandbox.container`. Then run `just sandbox setup`, `just sandbox build` and `just sandbox run`. Remove a stale `$XDG_RUNTIME_DIR/sandbox/build.sock` if it exists.
2. Build and push a real repo from the agent sandbox with `docker build --output type=docker` and `crane push`. Check the proxy log for the token swap.
3. Remove the test package `sandbox-readme-validate` in the GitHub package settings. The token of the session cannot remove it.
4. Read the research note and its comparison with this design. Answer the open questions. Write the decision in an ADR.
5. Test `network=none` for the agent container and a real package install in a `RUN` step.

## Rules and traps for the next session

- The `AGENTS.md` rules apply. Use a Herdr worktree. Never push to `main`. Read `docs/agents/pull-requests.md` before a commit or a PR, and `docs/agents/diagrams.md` before a diagram. Write all text in Simplified Technical English. The linter is `.claude/skills/asd-ste100/scripts/ste-lint.py`. Run it with `python3 -I`.
- `git push` fails with the credential helper of the host. A one-time override works: `git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push`.
- Test in renamed units and containers. Never start the live `sandbox-agent.service` for a test.
- The socket folder of the builder belongs to a subuid, mode 0700. The host user gets `Permission denied` on `ls`. This is correct. Use `podman unshare` to change or remove it.
- `iron-proxy` needs `dns.proxy_ip`. Without a `metrics` key it opens `:9090` on all interfaces. Without `http_listen` and `https_listen` it uses `:80` and `:443`. Keep all keys in `iron-proxy-builder.yaml`.
- The placeholder login in `image/configs/tools/docker-config.json` must equal the `proxy_value` of `GHCR_PUSH_TOKEN` in `proxy/iron-proxy.yaml`. It is not a secret.
- `docker build` without `--output` leaves the result in the cache of the builder. `--push`, `--load`, `docker push` and `docker run` do not work. This is by design.
- The SVG of the architecture diagram is drawn from the coordinates of the `.drawio` file. The generator script was in the scratchpad of the session and is not saved. Edit both files in the same way. Make the PNG with `rsvg-convert -z 2 -b white`.
- The permission classifier blocked an `npm install` of a tool, and the run of a third-party binary. Do not work around it. Ask the owner.
- Comments in code are crisp one-liners in Simplified Technical English. They explain the line. They have no measurements, dates or test results. Docs describe only the end state.

## Suggested skills

- `pr`: the body of every PR.
- `asd-ste100`: before you finish any text.
- `research`: for more primary-source work. The research note has the format.
- `code-review`: to review a branch before the owner merges it.
- `diagnosing-bugs`: if the builder or a build fails on the host.
- `domain-modeling`: if the owner wants an ADR for the builder and push decision.
- `handoff`: at the end of the next session.

## References

- PR: [#323](https://github.com/raghav19/engineersdaybook/pull/323) (docker, crane and the builder proxy). Earlier: [#317](https://github.com/raghav19/engineersdaybook/pull/317) (the builder).
- Sandbox docs: `.sandbox/README.md`, `.sandbox/docs/internals.md`, `.sandbox/proxy/README.md`.
- Research: `docs/research/remote-buildkit-for-agent-sandbox.md` and `docs/research/agent-sandbox-build-capability.md` (PR #325).
- Memory of the project: `sandbox-buildkit-builder-2026-11-18` and `sandbox-owner-working-style`.
