# Handoff: ephemeral environments with Istio, Gateway API and Flux ResourceSet

Written on 2026-11-04. Updated on 2026-11-05 after the user chose the `ResourceSet` model and the six-PR series. The work so far is research and design. **No product code exists yet.** Nothing changed on the cluster. The next session builds PR 1.

**Where this document and older records disagree, this document wins.** The old plan and the first version of this file chose kro, an Istio gateway, and the namespace `boutique-baseline`. These choices are gone.

Other records. Do not copy them here:
- The old plan: `/home/agent/.claude/plans/tender-cuddling-scroll.md`. It is outside the repo and old. Do not use it.
- The full transcript: `/home/agent/.claude/projects/-home-agent-engineersdaybook/e5254244-9650-4012-8505-f178beffab88.jsonl`.
- The ResourceSet spike: `spike-resourceset/` in this folder.
- Prior art in this repo: `code/platform-engineering/apps/boutique/` (pinned Boutique v0.10.7 and its catalog), `code/mcp-sandbox/part-3-mcp-guardrails/` (Flux, Istio sidecar mode, SPIRE, OCI artifacts), `docs/research/manifest-diff-ci.md`, `docs/research/rendered-manifest-pattern.md`, `_archive/_wip/2025-11-13-enabling-preview-env-for-microservices-testing-part-1.md` (the user's earlier blog draft).

## Goal

Show that a team with many microservices does not need a full copy of the stack for each pull request. Keep one **baseline**. Deploy only the **changed services** in a **sandbox** namespace. Route a request that carries a sandbox key to the changed services. Send every other hop to the baseline. This saves cost and operations work.

The user wants:
- Online Boutique as the sample app. It has stateless services and one stateful service (`redis-cart`).
- Gateway API for the routes and Istio for the mesh.
- STRICT mTLS between services and JWT authorization with Istio policies.
- A kro `ResourceGraphDefinition` (RGD) that defines an `EphemeralEnv` custom resource. CI submits one instance file. Flux applies it. The environment appears.
- A GitHub Actions sample that changes one stateless and one stateful service.
- The user asks many "why" questions. Answer them, and say what you did not check.

## Decisions (do not reopen without a reason)

- New project folder `code/ephemeral-env/`. Do not use `platform-engineering` (it uses Traefik as the Gateway API provider).
- The cluster is the user's k3s (see "Cluster facts"). GitHub-hosted runners cannot reach it. See "Open prerequisite: the CI result check".
- **Generation: Flux `ResourceSet` with Go templates.** The plan drops kro. The user accepted the loss of CEL, of the typed contract and of a status for each environment. The spike in `spike-resourceset/` rendered 15 objects for a 2-service input and 9 for a 1-service input. All 24 pass `flux-schema validate`. That was an offline render only.
- **Traefik stays the ingress.** The repo is public, so Flux needs no deploy key. **The GHCR registry is private.** Credentials go in two places. Flux needs a Secret for `OCIRepository.spec.secretRef`. The kubelet needs auth for the sandbox images. The plan is k3s `registries.yaml` (from memory, not checked). The user creates each Secret on the host from an env var. No value goes into Git. The workflow file shows only names. Actions pushes with its own `GITHUB_TOKEN` (`packages: write`).
- **Istio is `istiod` only, in sidecar mode.** No Istio gateway, no `GatewayClass istio`, no extra host port. The sidecar of the receiving pod checks the JWT. Traefik is not in the mesh, so the frontend port must accept plaintext from Traefik.
- **The running `boutique` namespace is the baseline.** The plan meshes it in place: label `istio-injection=enabled` and restart the 12 pods. The user chose this over a second copy. Undo: remove the label and restart.
- **Fork two stateless services first:** `checkoutservice` and `productcatalogservice`. Both are Go and self-contained at Boutique v0.10.7 (`Dockerfile`, `go.mod`, `genproto/`). Vendor both folders into `code/ephemeral-env/services/<name>/` with the licence notice. The PR diff is the change. The sample PR changes the product name and a shipping text, and the smoke Job checks both.
- **Kiali and Prometheus** come from the Istio sample addons. The Kiali graph is a goal: it shows the baseline → sandbox → baseline hops.
- **Gitless GitOps.** All pointers are in the OCI registry. No Git branch for environments. This differs from part 3, which keeps pins in Git. Write an ADR for the break.
- **The sandbox flow comes first. Promotion comes later.** The PR check must fail if the sandbox fails. A required status check blocks the merge (a GitHub setting that the user makes). Build once, and promote the image digest that the sandbox tested. Record the image digests in the PR artifact so this stays possible.
- **Sandboxes need no rollback.** A new push replaces the sandbox. Closing the PR removes it. The platform artifacts need a pattern (see "Rollback and promotion notes").
- The contract is **name and image only**. Port, stateful flag, seed and peer addresses belong to a service catalog inside the `ResourceSet` template. The sandbox `checkoutservice` needs the baseline addresses of its peers in its `*_ADDR` variables.
- Delivery uses Flux Operator: `ResourceSetInputProvider` (type `OCIArtifactTag`) plus a delivery `ResourceSet` that makes one `OCIRepository` and one `Kustomization` for each tag. Each PR writes only its own tag (`pr-<n>`), so PRs do not conflict. This is reasoning, not a test.
- All text follows ASD-STE100 (`/asd-ste100`).

## Open prerequisite: the CI result check

**Deferred on 2026-11-05.** The user moved this to its own phase after PR 4. The cluster runs on the user's laptop, so any reporting to GitHub needs a connection that the laptop makes, or a runner on the laptop. Build PR 1 to PR 4 first.

The user wants the workflow to run `flux get kustomizations` for the sandbox and poll with a timeout, and to fail the check on a failure or timeout. **A GitHub-hosted runner cannot reach the cluster.** Two ways:
- **A self-hosted runner** that reaches the cluster API with a read-only ServiceAccount. A self-hosted runner on a public repo is a risk, because a fork PR can run code on it. Limit it to same-repo PRs and require approval for others.
- **A Flux commit status.** A Flux `Provider` and `Alert` post the status of the sandbox `Kustomization`. The cluster holds one token Secret with `statuses:write`. The workflow polls the status on GitHub and fails on `failure` or timeout.

The user has not chosen. Ask before PR 5.

## The six-PR series (approved by the user on 2026-11-05)

The user applies each PR by hand. Each PR has a README that holds the setup, the checks and the undo steps, as in `platform-engineering`.

| PR | Adds | Done when |
|---|---|---|
| 1. Add-ons | Flux Operator, a `FluxInstance` with no Git sync, `istiod` only, Prometheus, Kiali, and a `kiali.localhost` route. | Pods are Ready. The Kiali API answers. |
| 2. Baseline | Sidecars on `boutique`, in place. Explicit PERMISSIVE `PeerAuthentication`. | The shop loads. Kiali shows the baseline graph. |
| 3. ResourceSet by hand | The S1 route spike first. Then the `ResourceSet` with the catalog, fed by `Static` inputs, with the public upstream images. | The environment appears, and Flux prunes it on removal. Kiali shows baseline → sandbox → baseline. A broken input does not block two good ones (R1). |
| 4. Service build | Vendor the two folders. The workflow finds the changed folders, builds them, and pushes `eph-<name>:<sha>` to the private GHCR. | A PR that changes one folder builds one image. CI records the digest. |
| 5. Gitless sandbox flow | The `pr-<n>` artifact push. The delivery `ResourceSet`. A smoke Job. The result check (see above). Teardown on PR close. A scheduled sweep of orphan tags. | A good PR gets a green check. A broken `checkoutservice` gets a red check. Closing the PR removes the sandbox. A burst of 10 PRs works. |
| 6. Security | JWT on the frontend sidecar, the claim-versus-baggage DENY policy, STRICT mTLS, call-graph policies. The negative tests join the smoke Job. | 401 without a token, 403 for the wrong sandbox, 200 for the right one. |

Promotion is the next series. It is not planned yet.

PR 1 needs host allowlist entries (`docs/agents/sandbox-network.md`). Name the exact hosts first.

## The model

- **Routing key:** a W3C `baggage` entry `sandbox=<id>`. The app carries it. Istio matches it with a regular expression in each caller sidecar.
- **Why it works without code change (verified in source):** Boutique `frontend` and `checkoutservice` (Go) set the OTel propagator `TraceContext + Baggage`. They use `otelhttp` and `otelgrpc`. Python `recommendationservice` instruments gRPC on both sides. The only services that call others are those three. So all 11 services can be forked. Nothing forwards `Authorization`.
- **Peer addresses:** Boutique reads them from `*_ADDR` environment variables. A fork sets baseline FQDNs there.
- **Entry:** the Traefik Gateway and the existing hostless `frontend` route. The first slice forks no frontend, so Traefik passes the `baggage` header on unchanged. A later route on Traefik could send the key to a sandbox frontend (not planned).
- **Mesh hops:** for each changed service X, an `HTTPRoute` in the baseline namespace has `parentRef` kind `Service` (name X). It matches the baggage regex and sends the call to X in the sandbox namespace. A `ReferenceGrant` in the sandbox namespace allows this. A baseline catch-all route covers the other calls.
- **Edge JWT (PR 6):** `RequestAuthentication` and `AuthorizationPolicy` on the frontend sidecar, because Traefik is not in the mesh. A DENY policy for each sandbox blocks baggage `sandbox=X` unless the JWT claim `sandbox` is `X`. A user cannot enter a sandbox that the token does not name.
- **East-west:** STRICT `PeerAuthentication` in `boutique-*` namespaces. A per-service `AuthorizationPolicy` allows only the caller service accounts from the call graph. The call graph is the `dependsOn` list in `code/platform-engineering/apps/boutique/catalog/catalog-info.yaml`. Each Boutique service has its own service account.
- **Stateful:** a changed `cartservice` brings its own `redis-cart` in the sandbox (kro `includeWhen`). Boutique needs no seed. Carts appear at the first `AddItem` and the product catalog is a JSON file in `productcatalogservice`. A fixture seed Job is optional. A copy from baseline is not advised. Real databases need migrations and seed data, and the saving shrinks.
- **Shared library change** (for example `protos/demo.proto`, used by all 11 services): CI adds every consumer to the list. The sandbox becomes a full copy for that PR. No special RGD path. CI computes the affected set from a path-to-service map. kro stays simple.
- **Out of scope:** async and queue traffic, and apps that do not propagate baggage.
- **Rollback and promotion notes (research of 2026-11-05):** Flux has no rollback feature. A maintainer says rollbacks happen in Git (flux2 discussion 2916). `OCIRepository.spec.ref` takes `digest`, `semver` or `tag`, in that order of precedence. A rollback points the source at an earlier artifact. Find the current version with `flux trace` or `kubectl describe ocirepository` (digest and Git origin). Keep one immutable tag for each merge (`main-<sha8>`) and push with `--source` and `--revision`. A merge re-pushes `latest` and so overrides a manual retag, so the normal path is to revert the commit in Git. A promotion tag (`latest-stable`) moved only after a health gate is my suggestion, not from the docs. The registry keeps no tag history, so CI must record each promotion. Do not use a retention rule that removes old tags. Not checked: the output columns of `flux list artifacts`, whether `flux tag artifact` overwrites a tag, and how a manual pin behaves under a parent `Kustomization`. The old version of this note follows.
- **Old rollback note:** Flux applies what the tag points to. Move the pointer tag (`flux tag artifact`, not run) to an older digest. Keep an immutable tag (`<sha>`) for every release, because a registry can remove untagged manifests. Then revert the commit in the source repo, or the next release redeploys the bad one. A sandbox needs no rollback. An RGD change reaches all live sandboxes, so make RGD changes additive. Mitigate the loss of Git review: post the manifest diff on the source PR, sign artifacts with cosign, and set `OCIRepository.spec.verify`.

The layout below is the first idea. The six-PR series above replaces the phases. Short form of the layout: `code/ephemeral-env/{CONTEXT.md, README.md, docs/adr/, gitops/{clusters/k3s,addons,platform/rgd,baseline}, services/{productcatalogservice,cartservice}/patch.diff, tests/smoke.sh, justfile}`. CI downloads the upstream tarball at the pinned commit, applies the patch, builds, and pushes to GHCR. Phases: 0 docs, 1 spikes, 2 platform bootstrap (Flux, Istio 1.31.1, kro v0.9.4), 3 baseline, 4 RGD and samples, 5 CI, 6 write-up.

## Verified and unverified

| Claim | State |
|---|---|
| Go services and Python recommendation carry baggage | Go verified in source. Python relies on OTel default propagators. Not tested. |
| kro v0.9.4 is the latest stable. `v0.10.0-rc.0` exists. API `kro.run/v1alpha1`. Instance CRD can be `scope: Cluster`. | Verified (release page, schema catalog). |
| ResourceSet generation is Go template only. CEL only in `readyExpr`. v0.62.1 is the latest. | Verified (schema, docs, release notes). |
| ResourceSet renders the full contract offline | Verified (spike). |
| Istio 1.31 `HTTPRoute` with a Service parent in sidecar mode | **Not verified.** Spike S1. |
| Many `HTTPRoute` objects on one Service: header rules sort before the catch-all | **Not verified.** Top risk. Fallbacks: one route written for all sandboxes, or `VirtualService` with `delegate`. |
| kro creates objects in another namespace from a Cluster-scoped instance. kro RBAC. | **Not verified.** The `kro.run` docs host was unreachable. |
| One ResourceSet with many environments: one failure blocks the others | **Not tested.** |
| Removing a provider prunes its objects. `wait: true` treats a finished Job as healthy. | **Not tested.** Docs imply the first. |
| Gateway claim-versus-baggage DENY policy (`request.auth.claims`, baggage wildcard) | **Not tested.** Spike S4. |
| `OCIArtifactTag` input fields (tag, digest) | **Not checked.** The input has no services list, so each artifact must hold the instance file. |

## Cluster facts (checked 2026-11-04)

- One k3s node `omarchy`, v1.37.1+k3s1, IP `192.168.178.188`. `kubectl` works from the sandbox. The sandbox cannot reach the node IP. Use the API server or in-cluster tests.
- Running: Traefik (`GatewayClass traefik`, Gateway `traefik-gateway` in `kube-system`, port 8000 behind ServiceLB port 80), namespace `boutique` (12 pods, no sidecars), namespace `backstage`.
- **Not installed:** Flux, Flux Operator, Istio, kro, SPIRE.
- Gateway API CRDs are v1.6.1, standard channel. `HTTPRoute`, `GRPCRoute`, `ReferenceGrant` exist.
- The `boutique` namespace is the baseline (mesh it in place in PR 2). Traefik stays the ingress and holds port 80. Sandboxes live in `boutique-pr-<n>`.

## Facts that are easy to get wrong

- The Flux Operator `ResourceSet` needs `spec.inputsFrom` for the CLI to pass inputs. Without it `inputs` is `null` and the error is "map has no entry for key".
- Flux cannot dry-run an instance before its CRD exists. Use separate `Kustomization` objects for the RGD and the instances, with `dependsOn`.
- The sandbox blocks most hosts. `kro.run` gave a DNS error. `github.com` release downloads worked. Follow `docs/agents/sandbox-network.md`: the user runs `just msb allow-host <host>` on the host.
- `gh` is not installed in this sandbox. The GitHub MCP tools work. PR steps in `docs/agents/pull-requests.md` call `gh`, so check this first.
- Secrets: the JWT private key, a Flux deploy key (if the repo is private) and the GitHub status token never go into Git. The user creates them on the host.

## Next steps

1. Ask the user to choose the CI result check (before PR 5, not before PR 1).
2. For PR 1, name the hosts to allow and ask the user to run `just msb allow-host <host>` on the host. Then install Flux Operator, `istiod`, Prometheus and Kiali. Read `docs/agents/kubernetes.md` before each manifest.
3. Write `CONTEXT.md` and the ADRs with the first PR that needs them: routing key, gitless OCI, `ResourceSet` instead of kro, Traefik ingress with `istiod` only.
4. Record the result of each spike (S1, S2, R1 to R3, D1) in an ADR. On a failure, use the named fallback and tell the user.
5. These spikes remain open. S1: a header `HTTPRoute` on a Service parent while Traefik owns the Gateway. S2: baggage through `checkoutservice`. R1: one broken input must not block the others. The fallback is one `ResourceSet` for each environment. R2: prune on removal. R3: `wait: true` with a finished Job, and RBAC for objects in other namespaces. D1: the artifact holds the input provider and the delivery `ResourceSet` applies it.
6. The smoke Job writes to the baseline `cartservice`. Use a unique session ID for each run.
7. Memory on one node is not measured.
8. PR 1 needs no new host on the sandbox allowlist (checked on 2026-11-05). Flux Operator comes from `oci://ghcr.io/controlplaneio-fluxcd/charts/flux-operator` (0.62.1). The Istio charts come from `https://blob.istio.io/istio-release/charts`, which redirects to `istio-release.r2.istio.io`. The old host `istio-release.storage.googleapis.com` has no 1.31 chart. Istio 1.31.1 to 1.31.3 exist as Git tags and charts. The addons come from `raw.githubusercontent.com/istio/istio/<tag>/samples/addons/`. The k3s node pulls the images, not the sandbox.

## Suggested skills

- `asd-ste100`: all text.
- `gitops-knowledge`: Flux, `ResourceSet`, OCI delivery.
- `grilling`: if the user wants the decisions tested.
- `domain-modeling`: for `CONTEXT.md` and the ADRs.
- `tdd` or `diagnosing-bugs`: for the smoke tests and the spikes.
- `pr`: for the PR body.

## Rules from `AGENTS.md` to keep in mind

- Work in a Herdr worktree. Never push to `main`.
- Read `docs/agents/kubernetes.md` before you write a manifest. Look up every field in the `flux-schema-catalog` MCP server.
- Read `docs/agents/pull-requests.md` before you commit or push. Read `docs/agents/host-handoff.md` before you ask the user to run a host command. Read `docs/agents/diagrams.md` before a diagram.
- Do not commit secrets. Refer to them by name.

## Spike files and how to run them again

`spike-resourceset/resourceset.yaml` is the `ResourceSet`. The providers are `pr-123.yaml` (2 services) and `pr-124.yaml` (1 service). `both.yaml` holds the two providers.

```bash
# In a new empty directory. Version 0.62.1 was used.
curl -sSL -o fo.tgz https://github.com/controlplaneio-fluxcd/flux-operator/releases/download/v0.62.1/flux-operator_0.62.1_linux_amd64.tar.gz
tar -xzf fo.tgz flux-operator
./flux-operator build rset -f spike-resourceset/resourceset.yaml \
  --inputs-from-provider spike-resourceset/both.yaml \
  | /opt/mise/installs/github-fluxcd-flux-schema/0.17.0/flux-schema validate --schema-location default --schema-location ecosystem --verbose
# Expect: Summary: 24 resources found, Valid: 24, Invalid: 0
```

The spike catalog has 3 services and no peer-address wiring. The files are a spike, not product manifests.
