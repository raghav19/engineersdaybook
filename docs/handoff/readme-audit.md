# Handoff: README audit of the projects

Written on 2026-11-07. The index of all handoff documents is `docs/handoff.md`.

The audit is done. No fix from it is merged yet. Two fixes are drafted on branches. This handoff lets a fresh session continue without the old conversation. Read it, then read "Next steps".

## Goal

The user asked for three things:

1. Show in the root `README.md` which projects are done and which are work in progress (WIP), with an emoji or a label. Example: the node attestation of part 3.
2. Check the README of each project. Does it match what the project claims? Can someone reproduce it on a fresh workspace and a fresh system?
3. Report the fixes, and list the pull requests (PRs) to raise.

## Read these first (do not copy them here)

- The findings of the audit: `docs/research/readme-audit-2026-11.md`. It has a verdict for each project, the defects with file and line, and the evidence tag of each finding.
- Rules of the repo: `AGENTS.md`. Before a PR, read `docs/agents/pull-requests.md`. Before a topic doc, read `docs/agents/project-docs.md`.
- Before a Kubernetes manifest, read `docs/agents/kubernetes.md`. Before any text, run `/asd-ste100` and lint your added lines with `.claude/skills/asd-ste100/scripts/ste-lint.py`.

## What is done

- The audit of 11 items (see the table in the research note). Eight subagents did it in read-only mode. The research note says what they could not check: nothing ran on a clean host.
- Two fixes, each on its own branch, pushed, with no PR yet:
  - `docs/rootless-docker-readme-fixes`: `code/rootless-docker/README.md`.
  - `docs/devk8s-kind-readme-fixes`: `code/devk8s-kind-wsl2/README.md` and `addons/routes/dashboard.yaml` (a new `HTTPRoute` for Headlamp).
- PR #272 updated the skills `asd-ste100` and `aws-storage`. It has no link to the audit.

## Decisions of the user (do not reopen without a reason)

- Start with `devk8s-kind-wsl2` and `rootless-docker`. Show the exact changes. Then go to the next projects.
- Use a legend of ✅ done and 🚧 WIP in the root README. The status shown is what a project earns after its PR merges.
- Raise small PRs. Only the root README PR touches the root `README.md`, so the PRs cannot conflict.
- The user wants the agents to follow `AGENTS.md`: a git worktree for each task, Simplified Technical English, no secrets in text, never push to `main`.

## Open decisions (ask the user)

1. The Medium URLs of the two blog posts that moved. `configuration-heirarchies` and `env-config-management` both link a dead page. Without the URLs, remove the links.
2. The `docker-sbx` tag is immutable. Re-cut it, or leave it and add a note?
3. The Qwen Code settings have no deny list for the GitHub tools, and `.msb/README.md` decision 19 contradicts the code. Build what the docs say, or change the docs?
4. The JWT source of part 3: Dex (README) or Keycloak (`authn-jwt`)?
5. The values in `code/env-config-management/mise.toml:3-12` look like placeholders. Are they? The Bitwarden org and project IDs in part 3's `config/cloud/k3s/bitwarden.yaml` are committed. Should they stay?
6. One PR at a time with a review each, or all at once?

## The PR plan

| # | PR | State |
|---|---|---|
| 1 | Sandbox guard: `SANDBOX_NAME` should be `SANDBOX_WORKSPACE` in 3 justfiles | Not started. Recheck first (see below). |
| 2 | Root `README.md`: legend, markers, `ephemeral-env` row, honest rows for part 2, part 3, node attestation and `rootless-docker`, line 4, blog tagline | Not started |
| 3 | Part 3 docs: status banner, "What works today" table, "Quick start", tree, node attestation page, banners on `arch.md` and the workload page | Not started |
| 4 | Part 3 stale comments in 5 manifests (comment-only) | Not started |
| 5 | Part 1: "twice" wording, diagram, spec, prerequisites, scripts 01 to 04, `verify-no-leak.sh` | Not started |
| 6 | Part 2: restore the server-side config, fix the dead link, add prerequisites and a check step | Not started |
| 7 | `rootless-docker` | Drafted: branch `docs/rootless-docker-readme-fixes` |
| 8 | `devk8s-kind-wsl2` | Drafted: branch `docs/devk8s-kind-readme-fixes` |
| 9 | `configuration-heirarchies` and `env-config-management` | Not started. Needs decision 1. |
| 10 | `agent-sandbox` (microsandbox): README, `.msb/README.md`, `headroom-home` volume, stale comment in `msb.py` | Not started. Needs decision 3. |
| 11 | `ephemeral-env` README | Not started |
| 12 | Blog post: four text fixes | Not started |

Not PRs: fixes to the `docker-sbx` tag (decision 2), a README for `code/platform-engineering` (write it before you list the project), and housekeeping of issues #10 to #14.

- PR 6 and PR 7 both cover `loginctl enable-linger`. Make the `sudo` use the same in the part 2 README and the `rootless-docker` README.
- Each README branch has one commit on top of `origin/main` of 2026-11-07. Open its PR with `gh pr create` after you follow `docs/agents/pull-requests.md` in order.

## How the session worked (so you can repeat it)

- `herdr` had no server (`server_not_running`), so the session used `git worktree add -b <branch> <path> origin/main`. If `herdr` runs, use `herdr worktree create` as `AGENTS.md` says.
- The `flux-schema-catalog` MCP server was not available. The session checked manifests with `kustomize build <dir>` and `flux-schema validate <dir> --verbose` from `mise`. If the MCP server is available, use it first.
- Docker was not installed on the host that the session used. Nothing that needs Docker ran.
- A subagent cannot write its report to a file in the scratchpad. It returns the report as text. Save what you need.

## Do these before you fix

- **Recheck every finding.** The research note tags only a few as rechecked. Subagents can be wrong. Read the cited line, then fix.
- **Recheck the sandbox guard (PR 1) first.** If `SANDBOX_NAME` is empty in the msb VM, the guard that keeps the registry token out of the sandbox never fires. Read `.msb/vm/sandbox.yaml:18-30` and the three `_host` recipes. Run the recipe in the VM if you can. Do not change a guard without a test.
- **Run the steps on a clean host** for the projects that will get ✅: `rootless-docker` (Arch with the AUR package), `devk8s-kind-wsl2` (WSL2), `configuration-heirarchies` (five `ansible-inventory` commands, with a named `ansible-core` version). Compare each output with the README.
- **Run the port-80 demo** of `rootless-docker`. Then check the claim in the research note. Remove it if it is wrong.
- Do not change `addons/services/metrics.yaml:35-37` (the `limits` indent) without a test. The fix starts to enforce a 256Mi limit.

## Next steps

1. Ask the user the open decisions. Decisions 1 and 6 decide the order.
2. Open the PRs for the two drafted branches. Run the checks above first.
3. Do PR 1, then PR 2. PR 2 sets the status markers in the root `README.md`, so it needs the verdicts of the research note.
4. Do the other PRs in table order. Make one worktree and one branch for each.
5. When a PR merges, change its row in this document, or remove the document when all rows are done.
