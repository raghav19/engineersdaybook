# Handoff: ephemeral environments with Istio, Gateway API and kro

Written on 2026-11-04. The work so far is research and design. **No product code exists yet.** Nothing changed on the cluster. The next session finishes the plan, then builds it phase by phase.

Other records. Do not copy them here:
- The plan: `/home/agent/.claude/plans/tender-cuddling-scroll.md`. It is outside the repo and partly old. The sections "Decisions" and "Plan edits still to write" below replace its old parts.
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
- The cluster is the user's k3s (see "Cluster facts"). The CI sample is pull-based. GitHub-hosted runners cannot reach the cluster.
- JWT depth: **edge JWT plus mTLS identity**. No JWT on each hop. No Boutique code change.
- **Gitless GitOps.** All pointers are in the OCI registry. Flux reconciles from OCI only. No Git branch for environments. This differs from part 3, which keeps tag and digest pins in Git (`stack.yaml`). Write an ADR for the break.
- The user prefers Kubernetes **CEL** to Go templates for generation. Only kro uses CEL to generate objects.
- The contract is **name and image only**. Port, stateful flag, seed and peer addresses belong to a service catalog inside the RGD. They are facts of the service. They are not facts of the PR.
- Delivery uses Flux Operator: `ResourceSetInputProvider` (type `OCIArtifactTag`) plus a `ResourceSet` that makes one `OCIRepository` and one `Kustomization` for each environment tag. `FluxInstance.spec.sync.kind` accepts `OCIRepository`.
- All text follows ASD-STE100 (`/asd-ste100`).

## Open decision: kro or ResourceSet for generation

The user asked for kro and for CEL. Then the user asked whether `ResourceSet` alone can do the same with Go templates.

- **Result: yes.** The spike in `spike-resourceset/` renders 15 objects for a 2-service input (with Redis) and 9 for a 1-service input. All 24 pass `flux-schema validate`. `range`, `if` and a `dict` catalog all work. This was an offline render. Nothing ran on a cluster.
- **ResourceSet gaps:** no CEL (only `dependsOn[].readyExpr`), the template is a string, the contract has no typed schema, and there is no status for each environment.
- **kro gaps:** `v1alpha1`, and no offline render that I found.
- **Lean:** stay with kro for the showcase. Keep the ResourceSet as the fallback. The contract file is the same for both.
- The user has not made the final choice. Ask once, then go on.

## The model

- **Routing key:** a W3C `baggage` entry `sandbox=<id>`. The app carries it. Istio matches it with a regular expression in each caller sidecar.
- **Why it works without code change (verified in source):** Boutique `frontend` and `checkoutservice` (Go) set the OTel propagator `TraceContext + Baggage`. They use `otelhttp` and `otelgrpc`. Python `recommendationservice` instruments gRPC on both sides. The only services that call others are those three. So all 11 services can be forked. Nothing forwards `Authorization`.
- **Peer addresses:** Boutique reads them from `*_ADDR` environment variables. A fork sets baseline FQDNs there.
- **Entry:** an Istio `Gateway` (`GatewayClass istio`). A route per sandbox sends the key to the sandbox frontend, but only if the frontend changed.
- **Mesh hops:** for each changed service X, an `HTTPRoute` in the baseline namespace has `parentRef` kind `Service` (name X). It matches the baggage regex and sends the call to X in the sandbox namespace. A `ReferenceGrant` in the sandbox namespace allows this. A baseline catch-all route covers the other calls.
- **Edge JWT:** `RequestAuthentication` and `AuthorizationPolicy` on the gateway. A DENY policy for each sandbox blocks baggage `sandbox=X` unless the JWT claim `sandbox` is `X`. A user cannot enter a sandbox that the token does not name.
- **East-west:** STRICT `PeerAuthentication` in `boutique-*` namespaces. A per-service `AuthorizationPolicy` allows only the caller service accounts from the call graph. The call graph is the `dependsOn` list in `code/platform-engineering/apps/boutique/catalog/catalog-info.yaml`. Each Boutique service has its own service account.
- **Stateful:** a changed `cartservice` brings its own `redis-cart` in the sandbox (kro `includeWhen`). Boutique needs no seed. Carts appear at the first `AddItem` and the product catalog is a JSON file in `productcatalogservice`. A fixture seed Job is optional. A copy from baseline is not advised. Real databases need migrations and seed data, and the saving shrinks.
- **Shared library change** (for example `protos/demo.proto`, used by all 11 services): CI adds every consumer to the list. The sandbox becomes a full copy for that PR. No special RGD path. CI computes the affected set from a path-to-service map. kro stays simple.
- **Out of scope:** async and queue traffic, and apps that do not propagate baggage.
- **Rollback:** Flux applies what the tag points to. Move the pointer tag (`flux tag artifact`, not run) to an older digest. Keep an immutable tag (`<sha>`) for every release, because a registry can delete untagged manifests. Then revert the commit in the source repo, or the next release redeploys the bad one. A sandbox needs no rollback. An RGD change reaches all live sandboxes, so make RGD changes additive. Mitigate the loss of Git review: post the manifest diff on the source PR, sign artifacts with cosign, and set `OCIRepository.spec.verify`.

Layout and phases are in the plan file. Short form: `code/ephemeral-env/{CONTEXT.md, README.md, docs/adr/, gitops/{clusters/k3s,addons,platform/rgd,baseline}, services/{productcatalogservice,cartservice}/patch.diff, tests/smoke.sh, justfile}`. CI downloads the upstream tarball at the pinned commit, applies the patch, builds, and pushes to GHCR. Phases: 0 docs, 1 spikes, 2 platform bootstrap (Flux, Istio 1.31.1, kro v0.9.4), 3 baseline, 4 RGD and samples, 5 CI, 6 write-up.

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
- Leave the `boutique` namespace and Traefik alone. The new baseline is `boutique-baseline`. The Istio gateway needs its own host port, because Traefik holds 80.

## Facts that are easy to get wrong

- The Flux Operator `ResourceSet` needs `spec.inputsFrom` for the CLI to pass inputs. Without it `inputs` is `null` and the error is "map has no entry for key".
- Flux cannot dry-run an instance before its CRD exists. Use separate `Kustomization` objects for the RGD and the instances, with `dependsOn`.
- The sandbox blocks most hosts. `kro.run` gave a DNS error. `github.com` release downloads worked. Follow `docs/agents/sandbox-network.md`: the user runs `just msb allow-host <host>` on the host.
- `gh` is not installed in this sandbox. The GitHub MCP tools work. PR steps in `docs/agents/pull-requests.md` call `gh`, so check this first.
- Secrets: the JWT private key, a Flux deploy key (if the repo is private) and the GitHub status token never go into Git. The user creates them on the host.

## Plan edits still to write

1. Contract is name and image. The catalog moves into the RGD.
2. CI computes the affected set from a path-to-service map.
3. Gitless OCI delivery replaces the `ephemeral-envs` Git branch.
4. Add the rollback section and a signing step.
5. Add the ADR for the break from the part 3 Git pins, and the ADR for the routing key.
6. Record the kro versus ResourceSet decision.

## Next steps

1. Ask the user to pick kro or ResourceSet. Then write the plan edits above.
2. Bootstrap Flux, Flux Operator, Istio and kro on the k3s. Ask the user for the host allowlist first.
3. Run spikes S1 to S4 in a scratch namespace. Record each result. Use the named fallback on a failure and tell the user.
4. Build the baseline, then the RGD (or ResourceSet) and the two samples, then CI, then the write-up.

Is `raghav19/engineersdaybook` public? A private repo needs a Flux deploy key and public GHCR packages. Ask.

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
