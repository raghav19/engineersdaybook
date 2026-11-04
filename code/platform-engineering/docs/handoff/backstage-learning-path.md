# Handoff: learn Backstage on a local k3s with Online Boutique

Written on 2026-11-04. The next session continues the Backstage learning path. Read this file first. It holds what a PR or a README does not. That is the cluster state, the traps, the way the user works, and the open questions.

Other records. Do not copy them here:
- The setup, the checks, and the undo steps: `code/platform-engineering/infrastructure/backstage/README.md` and `code/platform-engineering/apps/boutique/README.md`.
- The catalog kinds, links, annotations, and the API definition, with a diagram: `code/platform-engineering/apps/boutique/catalog/README.md`.
- The Gateway setting: `code/platform-engineering/infrastructure/gateway/traefik-config.yaml` (its comments say why).
- The reasons for each change: the PR descriptions (table below).
- The first plan: `/home/agent/.claude/plans/unified-greeting-wilkinson.md`. It is old. The table below replaces its "4 PRs" idea.
- The full transcript: `/home/agent/.claude/projects/-home-agent-engineersdaybook/dce83f41-09e0-4ec2-9835-ee7b73309546.jsonl` (11 MB, do not read it whole).

## Goal

The user is new to Backstage. They want to learn it for platform engineering, in the AI era, with Online Boutique on their own k3s (EKS later). They ask: "what is the point, and what does an agent do with it". Answer with sources, and say what you did not check.

## How the user works

- Small steps and small PRs. They ask for a PR after each step ("raise a PR"). Stop at a check and let them look.
- They say "this is overwhelming" when a plan or a diagram is too big. Use one idea, a table, and a high-level diagram. They rejected a 16-arrow diagram and a 9-stage plan.
- They want you to check their understanding against sources and fix what is wrong. Do not just agree.
- They decide. Give a recommendation and one question. They often answer with a different idea. Ask what they mean, do not guess.
- A message that is only "w" is a stray key. Ignore it.
- All text follows ASD-STE100 (`/asd-ste100`, `AGENTS.md` section 13).

## Status

| Part | PR | State |
|---|---|---|
| Gateway API provider of the k3s Traefik | #216 | merged |
| Online Boutique and its HTTPRoute | #224 | merged |
| Backstage (Helm chart), the catalog, the route | #227 | merged |
| `backstage.localhost` and the image config (`backstage.args`) | #232 | **open**. The cluster already runs it. |
| Step A: source links, the gRPC API, and the diagram with the API box | #233 | **open**. `main` does not hold the files, so the UI does not show them yet. |
| Docs PR and the research note `docs/research/backstage-ai-platform-engineering.md` | none | not started. The READMEs cover most of the docs. The research findings are in this file, section "Findings". |

Both open PRs show `blocked` in the API. For #227 (before it merged) I saw no check runs and no reviews. I did not check these two. The cause is unknown.

After the user merges #233, wait a few minutes for the catalog refresh. Then check through the API three facts. `frontend` has the relation `consumesApi`. The API `online-boutique-grpc` exists. Nine Components have `providesApi`. Then ask what the pages show.

## Cluster state (2026-11-04)

- k3s `v1.37.1`, one node `omarchy`, `192.168.178.188`. Traefik `3.7.13` (k3s chart `41.4.2`). The Gateway API CRDs (`v1.6.1`, standard) belong to k3s. The repo applies none.
- Gateway `traefik-gateway` in `kube-system`. Listener `web` on port 8000 (the Service maps port 80 to it).
- Namespace `boutique`: 12 pods. The route `frontend` has no hostname, so it answers every host that has no other route.
- Namespace `backstage`: Helm release `backstage` (chart `2.10.2`, image `1.55.2`, pinned by digest), revision 8. Postgres is a StatefulSet. I made the Secret `postgres` by hand with the command in the README. It is not in the repo. The route `backstage` has the hostname `backstage.localhost`.
- The user opens `http://backstage.localhost`. A `*.localhost` name needs no hosts entry.
- Nothing applies the repo to the cluster. There is no Flux. I applied each change by hand with `kubectl apply` or `helm upgrade`, before the PR.
- Apply the Backstage values: `cd code/platform-engineering/infrastructure/backstage && helm upgrade --install backstage oci://ghcr.io/backstage/charts/backstage --version 2.10.2 -n backstage -f values.yaml`.
- If the user installs k3s again: the VM kubeconfig goes stale (new CA). The host runs `just msb rm && just msb run`. A host-only recipe `just msb sync-kubeconfig` exists (PR #213, in `.msb/justfile`). I did not test it. After a reinstall, apply again: `traefik-config.yaml`, then Boutique, then Backstage (README order).

## Sandbox rules that cost time

- A VM restart removes uncommitted work, the git metadata of Herdr worktrees, the scratchpad, and `/tmp`. Commit and push early. The restart also dropped the diagram script and the catalog edit script. They are not in the repo.
- `gh` is not installed. Use the GitHub MCP tools: `get_me`, `list_pull_requests`, `create_pull_request`, `update_pull_request`, `pull_request_read`. The steps are in `docs/agents/pull-requests.md`.
- Worktrees: `herdr worktree create --branch <b> --label <l>`. If the branch exists on the remote, run `git branch <b> origin/<b>` first. Remove with `herdr worktree remove --workspace <id>`. Do not remove the worktrees of other sessions (`msb-*`, `spire-*`, `docs-handoff-*`).
- The sandbox cannot reach `192.168.178.188`. It reaches only the host ports in `HOST_PORTS` of `.msb/msb.py` (only 6443 on 2026-11-04). Test a route like this: `kubectl port-forward -n kube-system deploy/traefik 18000:8000`, then send `Host: backstage.localhost`. A guest token comes from `GET /api/auth/guest/refresh` with the headers `X-Requested-With: XMLHttpRequest` and `Origin: http://backstage.localhost`.
- The sandbox cannot open a browser. Say so, and ask the user what the page shows.
- `helm` works with `oci://ghcr.io/...`. `backstage.github.io` and `docs.k3s.io` do not resolve from the sandbox. `doc.traefik.io` works. The GitHub MCP tools and `raw.githubusercontent.com` are the main source for docs.
- A helm render for `flux-schema validate`: write it to a file first. Do not merge `stderr` into the pipe, or the `Pulled:` line counts as an invalid resource.
- Before you write a Kubernetes manifest, read `docs/agents/kubernetes.md` (schema catalog). Python follows `docs/agents/python.md` (type hints, `ruff`, `ty`, pinned `uv` scripts). Diagrams follow `docs/agents/diagrams.md`.
- The STE linter: `python3 -I .claude/skills/asd-ste100/scripts/ste-lint.py <files>`. It reads YAML comments too. The usual hits: passive voice, sentences over 25 words, and two words for one action in one file.

## Decisions (do not reopen without a reason)

- The gateway is the Traefik of k3s with the Gateway API only. Istio is out: the Istio docs say a gateway needs istiod.
- The repo has two parts: `infrastructure/` (gateway, backstage) and `apps/` (boutique and its catalog). The `HTTPRoute` of an app lives with the app.
- Backstage uses the official chart and the stock demo image. The image has the guest login only and no way to add plugins.
- The catalog files live with the app. Backstage reads them from `main` by URL (`values.yaml`).
- One `API` entity holds `demo.proto`. The file is a copy in `apps/boutique/catalog/`.
- No `CONTEXT.md` or `docs/adr/` upfront (`docs/agents/domain.md`).
- The diagram shows kinds and the links between kinds. It does not show the links between the 11 services.

## Findings (each one cost time, none is in the code comments)

- The chart passes only its own ConfigMap as `--config`. That drops the `app-config.yaml` of the image. Three errors followed: Backstage rejected the kind `System`, the plugins (Kubernetes tab, org pages, graph) were off (`app.packages`), and the UI stopped on `app.title`. `backstage.args: [--config, /app/app-config.yaml]` fixes all three. A later config file replaces an array, so our `catalog.locations` replaces the example entities.
- The catalog starts with the filter `Owner = Owned`. The guest owns nothing, so the list is empty until the user sets `Owner` to `All`.
- `backstage.local` did not open on the host. `.local` is for mDNS. `*.localhost` works, and Traefik answers on port 80 of the loopback address.
- A host name without a route shows the shop (a hostless route catches it). When the user says "I only see Boutique", check the host name first.
- A `$text` placeholder on GitHub may read only files of the same repo as the catalog file. That is why `demo.proto` is a copy.
- The annotation `github.com/user-id` must hold the GitHub node ID (`MDQ6VXNlcjIxMDc1MDU5`), not the number. The GitHub sign-in resolver needs it.
- The stock image cannot do the GitHub login: its backend loads the guest module only. The login needs your own image.
- The pod has no `docker`, `python3`, or `mkdocs`. TechDocs cannot build docs in this image.
- Security: Traefik listens on all interfaces of the host, and the guest login is open. A machine on the LAN can send `Host: backstage.localhost` and get in. A forged entity for `kube-system` got `403`, because Backstage checks the entity in the catalog. I did not test whether a guest can add an entity through the catalog API. The README says so. The user chose the route knowing this.
- Research, from the Backstage docs (`backstage/backstage` repo, `docs/ai/`): Backstage has three AI layers. The catalog can model skills and rules (`AiResource`, since v1.51, module `catalog-backend-module-ai-model`). The MCP actions backend exposes catalog and scaffolder actions as tools (alpha). Auth is a static token, or CIMD, which needs the new frontend system. Published skills help people who build Backstage, not people who build services. The stock image has the MCP actions plugin. I expect it has no `AiResource` kind. I did not check it. Competitor opinion (a Port blog post) is not a source.
- The AWS plugins repo (`awslabs/backstage-plugins-for-aws`) has no EKS plugin. For EKS use the Kubernetes plugin of Backstage.

## Roadmap the user accepted (step by step)

1. Step A: make the service pages useful. PR #233. Done in code. Waiting for the merge and a look at the UI.
2. Step B: docs. A design choice comes first, because TechDocs cannot build here. Options: build the docs in CI and publish them to storage, or use your own image with `mkdocs`, or use `links` only. Ask the user.
3. Step C: a Software Template for a new service, registered in the catalog. Publishing to GitHub needs a token, so start with a dry run.
4. Step D: agent access through MCP actions (token setup, alpha).
5. Later: your own image with the GitHub login and, if needed, `AiResource`. Then the exposure risk can close. Optionally give the shop a hostname too (`boutique.localhost`), so a wrong URL shows `404`, not the shop. EKS last.

## Open questions for the user

1. What do the pages show: the `frontend` page, the Kubernetes tab, the graph, and (after #233) the API page and the source link? I could not see any of them.
2. Merge #232 and #233. Why are they `blocked`?
3. Commit the diagram generator to the repo? It reads the two catalog files and draws the `.drawio`, `.svg`, and `.png`. It is lost with the scratchpad.
4. Remove the merged remote branches that are not from this work: `docs/x509pop-node-attestation` (#208) and `msb-ghcr-push-secret` (#220)? I asked. No answer.
5. After the merge of #232 and #233, remove the Herdr worktrees `platform-engineering-backstage-localhost` and `platform-engineering-catalog-api-source`.

## Suggested skills

Call the Skill tool for these:
- `asd-ste100`: before you finish any text or PR body.
- `pr`: for every PR body.
- `teach`: the user learns by questions and short explanations. Use it for the Backstage sessions.
- `wait-what`: when the user says a message did not land, or the plan is "overwhelming".
- `research`: for the research note, if the user wants it.
- `diagnosing-bugs`: when a page shows an error, as with `app.title`.
- `security-review`: before the route or the login image changes the exposure.
- `wizard`: for steps only the user can do (the browser, a GitHub OAuth app).
- `domain-modeling`: only if the user wants a `CONTEXT.md` or an ADR for `code/platform-engineering/`.
- `writing-for-agents`: if you edit `AGENTS.md` or a skill.
