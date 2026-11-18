# Handoff: the 2026-11-18 session on the sandbox builder, the proxy guard and the docs

Written on 2026-11-18. The index of all handoff documents is `docs/handoff.md`. This document continues [agent-sandbox-buildkit-builder.md](agent-sandbox-buildkit-builder.md). That document has the design and the test results of the builder. This one records how the session reached its decisions, what the owner rejected, and what a fresh session must know.

## State of the work

- [PR #317](https://github.com/raghav19/engineersdaybook/pull/317) (the BuildKit builder) and [PR #318](https://github.com/raghav19/engineersdaybook/pull/318) (the handoff index and the builder handoff) are merged into `main`.
- The host has not run the new setup, as far as this session knows. The owner must run `just sandbox setup` and `just sandbox build`.
- The main checkout has untracked files that nobody decided on. See "Open decisions".

## How the decisions came about

The first question was whether the sandbox could keep `krun` by using a remote BuildKit. The research note `docs/research/remote-buildkit-for-agent-sandbox.md` answers it. The short answer: `podman build` cannot use BuildKit, a remote BuildKit would reopen the `krun` network wall, and gVisor with a local builder is simpler.

The owner then steered these points. Do not offer the rejected options again without a new reason.

| Topic | Path of the decision | Final choice |
|---|---|---|
| Builder lifetime | Per build, per session or long lived | Per sandbox session. One builder for all Herdr sessions. |
| Resource limits | 4 GB, 4 CPUs, 2048 tasks, then lower | 2 GB, 2 CPUs, `TasksMax` 1024. The owner removed measurements from comments. |
| Failure handling | A `builder-check` recipe | The Podman health check fails the start and kills a builder that becomes unhealthy. |
| Build queue and listener | Valkey, Go listener, systemd socket | Dropped. `buildctl` is synchronous, so the agent needs no queue. |
| `nftables` rule | Owner asked to remove it, compared other projects, then reverted | Kept. The owner will revisit with a proxy container. |
| Proxy in a container | Socat sidecar, published port, internal network | Deferred. See "Proxy in a container". |

The `nftables` comparison with other projects had a limit. The microsandbox source shows an in-process network stack, so it has no host port to guard (an inference). The Docker Sandboxes pages do not say how the proxy is exposed. Neither source shows a user check. This does not prove that they have no guard.

## Proxy in a container

The owner liked the idea of managing containers in place of host units. The session found these facts:

- `iron-proxy` 0.56.0 cannot listen on a Unix socket. A test with three address forms failed with `listen tcp`.
- A TCP path from the host into a container is a port. A port has no user check. So a published port needs the `nftables` rule again.
- The simplest design is an internal Podman network (`Internal=true`) that holds the sandbox, the builder and the proxy. It needs no `socat`, no bridge and no host port. The proxy has a second network for its way out.
- The costs: gVisor with a real network device is untested, the sandbox gets a network interface, and the real tokens must reach the container. The owner rejected tokens in Podman storage before.
- A Quadlet unit could mount the encrypted credential with the `%d` specifier. This is untested.

## Open decisions (ask the owner)

1. Remove or move three stale untracked files: `docs/handoff/agent-microsandbox-handoff.md`, `docs/handoff/agent-sandbox-iron-proxy-handoff.md` and `docs/research/podman-gvisor-caddy-sandbox.md`. They describe the rejected `krun` and OpenBao design, or they copy a tracked file. Deleting them cannot be undone.
2. Commit or keep local: `docs/handoff/go-build-socket-listener.md` and `docs/handoff/spiffe-identity-podman-sandbox.md`. The first has a supersession banner, and its link to `go-build-listener-course.md` is broken.
3. Split `.sandbox/` into `agent/`, `builder/`, `proxy/` and `runtime/`. Do it as its own PR.
4. The sandbox Dockerfile installs `podman`. Decide if it stays.
5. The untracked Go listener in `code/agent-sandbox/builder/` and the Go course look obsolete. Ask before you continue them.

## Next steps

1. Run `just sandbox setup`, `just sandbox build` and `just sandbox run` after the merge. Run a real build from the sandbox with `buildctl`.
2. Open the README of `.sandbox/` on GitHub and check that the four mermaid diagrams render. The session could not run a parser, because the install of `mermaid-cli` was blocked. Chromium is at `/usr/bin/chromium`.
3. The items in "Next steps" of the builder handoff: the push test, the relay for `FROM` pulls, `network=none` for the agent, and the proxy container spike.
4. `internals.md` and the README both have a setup and run flow. Remove one set, or shorten it to a link, so that they cannot drift.

## Rules and traps for the next session

- The `AGENTS.md` rules apply. Use a Herdr worktree. Never push to `main`. Read `docs/agents/pull-requests.md` before a commit or a PR. Read `docs/agents/diagrams.md` before a diagram. Write all text in Simplified Technical English. The linter is `.claude/skills/asd-ste100/scripts/ste-lint.py`. Run it with `python3 -I`.
- The git credential helper of the host points to a `gh` version that no longer exists, so `git push` fails. A one-time override works: `git -c credential.helper= -c 'credential.helper=!gh auth git-credential' push`. `gh auth setup-git` fixes it for good.
- Comments in code are crisp one-liners that explain the line. They have no measurements, dates or test results.
- A design change needs the diagram updated. The files are `.drawio`, `.svg` and `.png`, in `.sandbox/docs/diagrams/`. The SVG is drawn by hand from the coordinates of the `.drawio` file, and the PNG comes from `rsvg-convert -z 2 -b white`.
- Test in renamed units. This session started the live `sandbox.service` twice. Do not do this.
- A permission classifier blocked an `npm install` of a tool in a scratch folder. Do not work around it. Ask the owner.
- The memory notes of the project hold the decisions above. See `sandbox-buildkit-builder-2026-11-18` and `sandbox-owner-working-style`.

## Suggested skills

- `pr`: the template for the body of every PR.
- `asd-ste100`: before you finish any text.
- `research`: for the proxy container spike, to read primary sources and save a note in `docs/research/`.
- `code-review`: to review a branch before the owner merges it.
- `diagnosing-bugs`: if the builder fails to start on the host.
- `domain-modeling`: if the owner wants a glossary or an ADR for the builder decision.

## References

- Builder design and tests: [agent-sandbox-buildkit-builder.md](agent-sandbox-buildkit-builder.md).
- Research: `docs/research/remote-buildkit-for-agent-sandbox.md`.
- The sandbox docs: `.sandbox/README.md` and `.sandbox/docs/internals.md`.
- Earlier handoffs: [podman-gvisor-sandbox.md](podman-gvisor-sandbox.md), [podman-sandbox-merged.md](podman-sandbox-merged.md).
