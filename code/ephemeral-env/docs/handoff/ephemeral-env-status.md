# Handoff: ephemeral environments, status after the platform PRs

Date: 2026-11-05. Read this first. It tells a fresh session what is done, what is decided, what comes next and which traps to avoid.

## The goal

A pull request that changes one or two Online Boutique services gets its own short-lived sandbox. Istio and Kiali show the calls between the sandbox and a shared baseline. Flux delivers everything from one OCI artifact in a private registry (the gitless model). The project is `code/ephemeral-env/`. It is self-contained and needs a fresh k3s with its packaged Traefik.

Read these in this order:
1. [`README.md`](../../README.md): what the project is, how to set it up from scratch.
2. [`docs/platform.md`](../platform.md): the idea, the parts, the flow, the reasons for the design.
3. [`docs/research/ephemeral-env-platform-gaps.md`](../../../../docs/research/ephemeral-env-platform-gaps.md): what the commands checked and what they did not.

## What exists

These PRs merged into `main`:
- #242: foundation. The `FluxInstance` syncs one OCI artifact. `just check`, `just publish` and `just clusters/k3s/up`.
- #248: `istiod` 1.31.1 in sidecar mode.
- #249: Prometheus and Kiali from the Istio samples. Kiali is view-only and has the host name `kiali.localhost`.
- #250: the Boutique v0.10.7 baseline in the mesh, read from its pinned release URL. Ordered Flux Kustomizations in `platform/sync.yaml`.
- #255: the README as a setup guide, `docs/platform.md`, the ephemeral environments diagram and the research note.

**Nothing ran on a cluster.** Only `flux-schema` checks ran. No `publish`, no `up`, no deploy.

## What the user decided

- A separate project folder with a fresh k3s and the packaged Traefik. Do not change other projects.
- Git is the source. The cluster pulls one OCI artifact and never reads Git. The platform is in Git and in the artifact. Sandbox artifacts (`pr-<n>`) are never in Git.
- Layout: `platform/{addons,apps,sandboxes}` goes into the artifact. `clusters/k3s/` holds what the user applies from the host.
- The Boutique baseline comes from its pinned URL. This is the one exception to "the cluster reads only the registry".
- Sandboxes first, promotion later. Sandboxes need no rollback.
- No SPIRE, no Istio ingress gateway, no agentgateway.
- The user raises the PRs in a chain and deploys later, when the cluster is ready.
- Versions and settings will come from a central config with setters, as in part 3. This is the last PR.

## What comes next

1. **The `ResourceSet` by hand.** Run spike S1 first: does an Istio `HTTPRoute` with a Service parent match a `baggage` header? Then write the `ResourceSet` with a service catalog and `Static` inputs. Check that one bad input does not block the others (R1) and that Flux prunes on removal (R2).
2. **The service build.** Vendor `checkoutservice` and `productcatalogservice` under `services/`. A workflow lists the changed files, maps them to services, builds only those and pushes `eph-<name>:<sha>`.
3. **The sandbox flow.** The `pr-<n>` artifact, the delivery `ResourceSet`, a smoke Job, teardown on PR close and a sweep of orphan tags.
4. **Security.** A JWT check on the frontend sidecar, a deny policy that compares the claim with the baggage, STRICT mTLS and call-graph policies.
5. **The central config.**

The design behind steps 1 to 4 is in [`ephemeral-env-design.md`](ephemeral-env-design.md) in this folder. Its PR table lists the steps as PR 5 to PR 9. The folder `spike-resourceset/` holds the offline `ResourceSet` spike.

## Decisions that the user has not made

Ask before you start the step that needs each one:
- **The development cluster.** A fresh k3s, kind, or documentation only. Needed before any deploy.
- **The CI result check** (before step 3). The cluster runs on a laptop. A GitHub-hosted runner cannot reach it. The options are a self-hosted runner (a risk on a public repo) and a Flux commit status.
- **The central config approach** (before step 5). Reuse the Python tool and the recipes of part 3, or write a small `kustomize` setter.

## Open risks

The research note has the full list. These matter most:
- The header match on a mesh route (S1) and the header through `checkoutservice` (S2) are unproven. The fallbacks are in the design handoff.
- Flux may forbid remote bases (`--no-remote-bases`). Then `apps-boutique` fails to build.
- The `loadgenerator` init container needs a native Istio sidecar.
- Memory of one node for 12 pods with sidecars, and the GHCR rate limits, are not measured.

## Traps in the sandbox VM

- `gh` is not installed. Use the GitHub MCP tools for PRs. `docs/agents/pull-requests.md` still names `gh`.
- The permission classifier blocked a force-push. If a pushed branch needs a rebase, push the work under a new branch name.
- A restart of the VM loses the git metadata of the Herdr worktrees. The files stay. Prune the worktree, delete the stale folder, recreate it with `herdr worktree create --branch <branch> --label <slug>`, then copy the files back.
- `just publish` and `just clusters/k3s/up` refuse to run in the sandbox. The user runs them on the host. Follow `docs/agents/host-handoff.md`.
- The pre-commit hook `yamlfmt` rewrites vendored YAML. Compare the content as parsed YAML before and after.
- The diagram script is not in the repo. To change [`architecture.drawio`](../diagrams/architecture.drawio), edit it in draw.io and export the SVG and a 2x PNG. See [`docs/diagrams/README.md`](../diagrams/README.md).
- Read `docs/agents/project-docs.md` before you edit a doc in `docs/`, and `docs/agents/diagrams.md` before you edit a diagram.

## Files

- [`justfile`](../../justfile): `check` and `publish`.
- [`clusters/k3s/`](../../clusters/k3s): the Flux instance, the Traefik config and `up`.
- [`platform/`](../../platform): the content of the artifact.
