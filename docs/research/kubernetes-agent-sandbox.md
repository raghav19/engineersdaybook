# Agent Sandbox (`kubernetes-sigs/agent-sandbox`) for a starter, and its relationship to Agent Substrate

Question: What is `kubernetes-sigs/agent-sandbox`? What is its API? What does it give agent workloads that plain Kubernetes does not give? How does it run on a local single-node k3s without KVM? Which metrics, benchmarks and scale settings does it have? How does it relate to "Agent Substrate"?

Research date: 2026-11-23. Local repo state: `main` at `160d789`.

Versions read (all primary sources):

- `kubernetes-sigs/agent-sandbox` tag `v1.0.12` (tag commit `4863a629`, dated 2026-11-18). The GitHub release page shows "20 Nov" with no year. I read the Go API types, `README.md`, `roadmap.md`, `docs/`, `docs/keps/`, `sandbox-router/README.md`, `helm/README.md`, `packages/sandboxd/USER_GUIDE.md`, `site/content/docs/` and `dev/load-test/`.
- `kubernetes-sigs/agent-sandbox` `main` at `5c0e127d` (2026-11-23). I used it only for the Agent Substrate search. It is 19 commits after `v1.0.12`. My clone was shallow, so I could not see who wrote older files.
- **Newer release:** the notes [agent-sandbox-build-capability.md](agent-sandbox-build-capability.md) and [remote-buildkit-for-agent-sandbox.md](remote-buildkit-for-agent-sandbox.md) cite `v1.0.11` (tag commit `890de53a`, 2026-11-11). `v1.0.12` is newer.
- `agent-substrate/substrate` at commit `8368e765` (from GitHub code search) and its README (read on 2026-11-23).
- gVisor `master` at `168b84e6` (`g3doc/user_guide/containerd/quick_start.md`, `g3doc/user_guide/platforms.md`).
- k3s docs page [Advanced Options](https://docs.k3s.io/advanced). The page has no version.
- Kubernetes blog: [Running Agents on Kubernetes with Agent Sandbox](https://kubernetes.io/blog/2026/03/20/running-agents-on-kubernetes-with-agent-sandbox/) (2026-03-20, Janet Kuo and Justin Santa Barbara). Both are in `OWNERS` as approvers (`janetkuo`, `justinsb`).

Evidence tags:

- **[doc]**: an official documentation page, README, design doc (KEP) or maintainer blog. A URL or a file path is given.
- **[src]**: Go source or a generated manifest at `v1.0.12`. The file path is given.
- **[inference]**: my own conclusion from the sources. No source says it.
- **UNVERIFIED**: I did not find a source, or I did not test it.

I ran no cluster. Every statement comes from reading files and pages. In this note, "AS" means `https://github.com/kubernetes-sigs/agent-sandbox/blob/v1.0.12/`.

Related notes: [agent-substrate.md](agent-substrate.md) and [agent-benchmark-low-memory.md](agent-benchmark-low-memory.md).

## Answer

1. **What it is.** Agent Sandbox is a Kubernetes controller plus CRDs for "isolated, stateful, singleton workloads". It is a subproject of SIG Apps. The license is Apache-2.0. The latest release is `v1.0.12` (tag 2026-11-18). All CRDs serve only `v1beta1`. [doc] (AS`README.md`, AS`roadmap.md`, AS`LICENSE`)
2. **The API has four CRDs in two groups.** `Sandbox` is the core, in group `agents.x-k8s.io/v1beta1`. `SandboxTemplate`, `SandboxClaim` and `SandboxWarmPool` are extensions, in group `extensions.agents.x-k8s.io/v1beta1`. One controller binary reconciles all four. The `--extensions` flag turns on the three extension reconcilers. [src]
3. **What it adds over plain Kubernetes.** It gives one Pod with a stable name, owned PVCs that survive suspend, a `Suspended` mode and expiry. It also gives warm pools with claim adoption, and a default-deny NetworkPolicy per template. The project says that StatefulSet (size 1) + Service + PVC can approximate this, but "is cumbersome and lacks specialized lifecycle management like hibernation". [doc] [src]
4. **What it does not solve.** It does no isolation itself. It delegates isolation to gVisor or Kata through `runtimeClassName`. Suspend deletes the Pod, so memory state is lost. Memory snapshots need GKE Pod Snapshots. Auto suspend, auto resume and scale to zero are "Planned". [doc]
5. **Local k3s without KVM.** gVisor `runsc` uses the `systrap` platform by default, and that platform needs no KVM. k3s does not detect `runsc` by itself. You add a containerd template and a `RuntimeClass` with `handler: runsc`. Then you `kubectl apply` the release YAML. Kubernetes 1.25 is the minimum and 1.29 is recommended. SDKs exist for Python (`k8s-agent-sandbox`), Go and TypeScript. The docs say that the sandbox router is necessary for SDK traffic on gVisor. [doc] Not yet tested on this repo's k3s. UNVERIFIED.
6. **Metrics and scale.** The controller exposes 14 `agent_sandbox_*` Prometheus metrics. The published numbers are about 300 claims/s for a burst from a ready warm pool (p90 ≤ 200 ms), and 70–85 sandboxes/s refill for each pool. Each `Sandbox` object takes about 10 KB in etcd. One design doc gives a ceiling of about 50k sandboxes for each cluster. [doc]
7. **Relationship to Agent Substrate.** One primary source states it. A design doc in the agent-sandbox repo calls Substrate "a peer OSS project. Not a layer above or below agent-sandbox". Substrate does not build on agent-sandbox. An agent-sandbox example adapts code from an `agent-substrate` repo. [doc] The Substrate repo does not reference agent-sandbox CRDs. [src]

## 1. What agent-sandbox is

| Item | Fact | Source |
|---|---|---|
| Owner | "under the umbrella of SIG Apps". Approvers: `janetkuo`, `justinsb`, `soltysh`, `barney-s`. | AS`README.md`, AS`OWNERS` [doc] |
| Problem statement | "agent-sandbox enables easy management of isolated, stateful, singleton workloads, ideal for use cases like AI agent runtimes and reinforcement learning." | AS`README.md` [doc] |
| Scope | "Agent Sandbox is a *sandbox orchestrator*. It delegates low-level container isolation to secure 'Sandbox Runtimes' (like gVisor or Kata Containers)". | AS`README.md` [doc] |
| Motivation | Deployments and StatefulSets do not fit. StatefulSet (size 1) + Service + PVC "is cumbersome and lacks specialized lifecycle management like hibernation". | AS`README.md` "Motivation" [doc] |
| Maturity | "Alpha to Beta API Versioning ✅ Done". `v1beta1` is the only served version. `v1alpha1` was removed in `v1.0.0`. | AS`roadmap.md`, AS`docs/api-migration-guide.md` [doc] |
| Latest release | `v1.0.12`, tag commit `4863a629`, 2026-11-18. The release page shows "20 Nov". Python SDK `k8s-agent-sandbox==1.0.12`, Helm chart 0.1.5. | `git tag`, [release page](https://github.com/kubernetes-sigs/agent-sandbox/releases/tag/v1.0.12) [doc] |
| License | Apache-2.0 | AS`LICENSE` [src] |
| Blog | The project is "currently in development under SIG Apps". | [kubernetes.io blog 2026-03-20](https://kubernetes.io/blog/2026/03/20/running-agents-on-kubernetes-with-agent-sandbox/) [doc] |
| SIG view | A SIG Apps chair drives "new subprojects like the Agent Sandbox". The SIG prefers to add them "as CRDs first rather than bloating the core APIs". | [Spotlight on SIG Apps, 2026-09-22](https://kubernetes.io/blog/2026/09/22/sig-apps-spotlight/) [doc] |

Changes in `v1.0.12` (from the release page): SDK suspend and resume, a per-pool `readinessGracePeriodSeconds`, Ed25519 v2 tokens in the router, and `sandboxd` fixes. The release notes say: "Upgrade all replicas first, because older ones reject these tokens with 403." [doc]

## 2. The API

API groups (from AS`api/v1beta1/groupversion_info.go` line 32 and AS`extensions/api/v1beta1/groupversion_info.go` line 34) [src]:

- Core: `agents.x-k8s.io/v1beta1`
- Extensions: `extensions.agents.x-k8s.io/v1beta1`

All four CRDs are namespaced and have a `status` subresource. Only `SandboxWarmPool` has a `scale` subresource, so an HPA can scale it. [src] (`+kubebuilder` markers in the type files)

### 2.1 `Sandbox` (core)

- **Purpose.** It manages "a single, stateful pod with a stable identity and persistent storage". [doc] (AS`README.md`)
- **Short name:** `sandbox`. [src] (AS`api/v1beta1/sandbox_types.go` line 445)
- **Key spec fields** (AS`api/v1beta1/sandbox_types.go`) [src]:
  - `podTemplate` (required): a full `corev1.PodSpec` and label/annotation metadata. After creation, only labels and annotations go to the running Pod. Other changes take effect at the next Pod creation.
  - `volumeClaimTemplates`: at most 128 entries. They cannot change after creation. Each PVC is named `<template>-<sandbox>` and is owned by the Sandbox. The PVC "is kept while the Sandbox is suspended". It is deleted with the Sandbox.
  - `service` (`*bool`): it creates a headless Service. When the field is unset, the controller "does not create new ones".
  - `failedPodPolicy`: `Retain` (default) or `Recreate`. `Recreate` uses a backoff that starts at 5 s and doubles to a maximum of 5 min.
  - `operatingMode`: `Running` (default) or `Suspended`. Suspended "terminates the backing Pod while retaining the Sandbox object and its volumes".
  - `shutdownTime` and `shutdownPolicy` (`Retain` default, or `Delete`): expiry deletes the Pod and the Service, then applies the policy to the object.
- **Status:** `serviceFQDN`, `service`, `conditions` (`Ready`, `Suspended`, `PodScheduled`, `Finished`), `selector`, `podIPs`, `nodeName`. [src]
- **Reconciler:** `controllers/sandbox_controller.go`. It watches `Sandbox` and owns `Pod` and `Service` (lines 2442–2447). It creates PVCs (lines 2219–2271). [src]

### 2.2 `SandboxTemplate` (extension)

- **Purpose.** It is a "reusable template for creating Sandboxes". [doc] (AS`README.md`)
- **Short name:** `sandboxtemplate`.
- **Key spec fields** (AS`extensions/api/v1beta1/sandboxtemplate_types.go`) [src]:
  - The same `SandboxBlueprint` as `Sandbox` (`podTemplate`, `volumeClaimTemplates`, `service`, `failedPodPolicy`).
  - `networkPolicy` (ingress and egress rules) and `networkPolicyManagement` (`Managed` default, or `Unmanaged`). In `Managed` mode with no rules, the default allows ingress "only from the Sandbox Router". Egress goes to the "Public Internet only" and blocks RFC1918 ranges and the metadata server. The controller makes one shared NetworkPolicy for each template.
  - `envVarsInjectionPolicy` (`Disallowed` default, `Allowed`, `Overrides`) controls `env` in a claim.
  - `volumeClaimTemplatesPolicy` (`Disallowed` default) controls the PVCs that a claim adds.
- **Default.** Sandboxes made from a template get `automountServiceAccountToken: false` when the field is omitted. [src] (the comment on `PodTemplate`)
- **Reconciler:** `extensions/controllers/sandboxtemplate_controller.go`. It watches `SandboxTemplate` and owns `NetworkPolicy` (lines 261–262). [src]

### 2.3 `SandboxWarmPool` (extension)

- **Purpose.** It "Manages a pool of pre-warmed Sandboxes that can be quickly allocated to users". [doc] (AS`README.md`)
- **Short name:** `swp`. It has a scale subresource on `.spec.replicas`. [src]
- **Key spec fields** (AS`extensions/api/v1beta1/sandboxwarmpool_types.go`) [src]:
  - `replicas` (default 1, minimum 0). The source comment says "controlled by an HPA if specified".
  - `sandboxTemplateRef` (required).
  - `updateStrategy.type`: `OnReplenish` (default) leaves old unclaimed members in place. `Recreate` deletes them. "Claimed Sandboxes are never replaced."
  - `readinessGracePeriodSeconds`: minimum 30. The controller default is 300 s. This field is new in `v1.0.12`.
- **Status:** `replicas`, `readyReplicas`, `selector`, `observedGeneration`.
- **Reconciler:** `extensions/controllers/sandboxwarmpool_controller.go`. It watches `SandboxWarmPool`, `Sandbox` and `SandboxTemplate` (lines 1468–1475). [src]

### 2.4 `SandboxClaim` (extension)

- **Purpose.** It "Allows users to create Sandboxes from a `SandboxWarmPool`". [doc] (AS`README.md`)
- **Short name:** `sandboxclaim`.
- **Key spec fields** (AS`extensions/api/v1beta1/sandboxclaim_types.go`) [src]:
  - `warmPoolRef.name` (required). At `v1.0.12` a claim refers to a pool, not to a template.
  - `lifecycle`: `shutdownTime`, `ttlSecondsAfterFinished`, and `shutdownPolicy` (`Retain` default, `Delete`, `DeleteForeground`).
  - `additionalPodMetadata`: label keys must use an allowed domain (default `sandbox.users.io`).
  - `env` and `volumeClaimTemplates`: either field "forces a cold start".
- **Reconciler:** `extensions/controllers/sandboxclaim_controller.go`. It watches `SandboxClaim`, owns `Sandbox`, and watches `SandboxWarmPool` and `SandboxTemplate` (lines 2752–2778). The controller waits for a warm candidate, then falls back to a cold create (`--sandbox-claim-warm-candidate-grace-period`). [src]
- **Doc drift.** The March 2026 blog says a claim goes "against a SandboxTemplate". The `v1.0.12` type requires `warmPoolRef`. Use the Go types. [doc] [src]

### 2.5 Controller packaging

- One binary: `cmd/agent-sandbox-controller`. `--extensions` (default `false`) registers the three extension reconcilers (lines 105, 515–590 of `main.go`). The extensions manifest sets `--leader-elect=true` and `--extensions`. It runs in namespace `agent-sandbox-system`. Metrics are on port 8080. [src] (AS`k8s/extensions.controller.yaml`)

## 3. What it solves that plain Kubernetes does not

| Need | Agent Sandbox | Plain Kubernetes | Source |
|---|---|---|---|
| Singleton stateful session | One `Sandbox` = one Pod. The `MultiplePods` reason blocks Ready if two Pods match. | StatefulSet size 1 + Service + PVC, which the project calls "cumbersome". | AS`README.md` [doc], AS`api/v1beta1/sandbox_types.go` [src] |
| Stable identity / hostname | "Each Sandbox has a stable hostname and network identity." The Pod uses the Sandbox name. A headless Service is optional (`service: true`). | StatefulSet gives `name-0`. | AS`README.md` [doc], `sandbox_types.go` [src] |
| Persistent storage | `volumeClaimTemplates`. The PVC is kept on suspend and on retained expiry, then reattached on resume. | StatefulSet PVC. | `sandbox_types.go` [src] |
| Pause / resume | `operatingMode: Suspended` deletes the Pod and keeps the object and the PVCs. Resume makes a new Pod. KEP-694 has status "implemented". | Scale a StatefulSet to 0 by hand. | `sandbox_types.go` [src], AS`docs/keps/694-.../kep.yaml` [doc] |
| Memory hibernation | Only on GKE. `PodSnapshotSandboxClient` (Python only) uses GKE `podsnapshot.gke.io` with gVisor. | None. | AS`site/content/docs/sandbox/snapshots/_index.md` [doc] |
| Warm pool / cold start | `SandboxWarmPool` + `SandboxClaim` adopt a running Sandbox. `env` or PVCs in a claim force a cold start. | None. | AS`docs/performance-tuning.md` [doc] |
| Scale to zero | Per sandbox: manual `Suspended`. Per pool: `replicas: 0`. "Scale to Zero" and "Auto Suspend/Resume" are "📅 Planned". | Manual. | AS`roadmap.md` [doc] |
| Expiry / TTL | `shutdownTime` on Sandbox. `shutdownTime` + `ttlSecondsAfterFinished` on claim. | Job `ttlSecondsAfterFinished` only. | type files [src] |
| Isolation runtime | Not implemented. Set `runtimeClassName` (gVisor or Kata) in `podTemplate`. | Same `RuntimeClass`. | AS`docs/security/threat_model.md` [doc] |
| Tenant network isolation | `SandboxTemplate` managed NetworkPolicy (default deny ingress except the router, internet-only egress). | Write it yourself. | `sandboxtemplate_types.go` [src] |
| API token exposure | A template defaults `automountServiceAccountToken` to `false`. A bare `Sandbox` does not get this default. | Manual. | threat model [doc] |

**Still unsolved (stated by primary sources):**

- Isolation itself: "Agent Sandbox itself does not implement isolation". [doc] (threat model)
- These items are all "📅 Planned" [doc] (AS`roadmap.md`): auto suspend on idle, resume on traffic, scale to zero, and multiple sandboxes in one Pod. Identity at claim time, network policy at claim time, and an MCP server are also "Planned".
- The router default authorizer is `AllowAll`. The IP-class check is "currently the *only* SSRF defense". The Go router has no connection limits for WebSockets. [doc] (threat model)
- A bare `Sandbox` gets no NetworkPolicy and no token default. Admins "should use admission control". [doc]
- Memory-state suspend works only on GKE. [doc]
- Updates to a template do not reach claimed sandboxes. "Claimed Sandboxes are never replaced." [src]

## 4. Running on a local single-node k3s without KVM

**gVisor without KVM.** `runsc` selects `systrap` by default. KVM is optional ("For best performance, use the KVM platform on bare-metal machines only"). [doc] ([platforms.md](https://github.com/google/gvisor/blob/master/g3doc/user_guide/platforms.md)) The agent-sandbox gVisor page says gVisor "does not require nested virtualization support on the host". [doc] (AS`site/content/docs/use-cases/gvisor-isolation/_index.md`)

**k3s and runsc.** k3s detects only `crun, lunatic, nvidia, nvidia-cdi, nvidia-experimental, slight, spin, wasmedge, wasmer, wasmtime, wws`. `runsc` is not on the list. [doc] ([k3s Advanced Options](https://docs.k3s.io/advanced)) So you must:

1. Install `runsc` and `containerd-shim-runsc-v1` in the `PATH` of the k3s service. [doc] (gVisor containerd quick start)
2. Add a containerd template. For containerd 2.x, k3s reads `/var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.tmpl`. For containerd 1.7 and earlier, it reads `config.toml.tmpl`. [doc] (k3s)
3. Add a runtime with `runtime_type = "io.containerd.runsc.v1"`. gVisor shows the `version = 2` form `[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]`. For containerd 2.x it says to "Consider using the version header `version = 3`". [doc] ([quick_start.md](https://github.com/google/gvisor/blob/master/g3doc/user_guide/containerd/quick_start.md)) The exact v3 plugin path for k3s is UNVERIFIED.
4. Apply a `RuntimeClass`: `apiVersion: node.k8s.io/v1`, `kind: RuntimeClass`, `metadata.name: gvisor`, `handler: runsc`. [doc] (gVisor)
5. Set `runtimeClassName: gvisor` in the `podTemplate.spec` of the `Sandbox` or the `SandboxTemplate`. [doc] (agent-sandbox gVisor page)

The install guide covers kind and GKE. One example (`examples/urunc-sandbox`) has a k3s overlay for urunc, not for gVisor. [doc] The k3s + gVisor steps above are not yet tested in this repo. UNVERIFIED.

**Install methods.** [doc] (AS`README.md`, AS`helm/README.md`)

- kubectl: `kubectl apply -f https://github.com/kubernetes-sigs/agent-sandbox/releases/download/${VERSION}/sandbox-with-extensions.yaml`. Selective files: `sandbox.yaml` (core) and `extensions.yaml`.
- Helm: `helm install agent-sandbox ./helm/ --namespace agent-sandbox-system --create-namespace --set image.tag=<version> --set controller.extensions=true`. "Helm does not upgrade CRDs placed in `crds/` automatically."
- The repo also has an OLM bundle (`olm/`). [src]
- Verify: `kubectl get crd sandboxes.agents.x-k8s.io` and `kubectl get deploy agent-sandbox-controller -n agent-sandbox-system`.

**Kubernetes version.** "1.25 or later" with CRD CEL validation. "Kubernetes 1.29 or later is recommended". The Gateway API v1.5.0 bundle needs 1.31 or later. [doc] (AS`README.md`)

**Clients.** [doc] (AS`README.md`, `clients/`)

- Python: `pip install k8s-agent-sandbox`. It has "Gateway Mode" and a "Tunnel Mode" (`kubectl port-forward` to the router) for local tests.
- Go: `go get sigs.k8s.io/agent-sandbox/clients/go/sandbox@latest`. The Go SDK version is the repo tag.
- TypeScript: `clients/typescript/agentic-sandbox-client` (package version `0.1.0`). The roadmap marks it "⏳ In Progress". [src]
- Integrations in `clients/integrations/`: deepagents, gymnasium, mcp-server, nemo-gym, openai, openhands. [src]

**Extra components.** [doc]

- **Sandbox router** (`sandbox-router/`): a stateless reverse proxy. It routes by the headers `X-Sandbox-ID`, `X-Sandbox-Namespace` and `X-Sandbox-Port` (default `8888`). The gVisor page says: "With gVisor or Kata runtimes, direct pod port-forwarding is not compatible. Use the Sandbox Router". I did not check whether this applies to k3s with `runsc`. UNVERIFIED. The install guide sets `ALLOW_UNAUTHENTICATED_ROUTER=true` "Use only for local testing". It uses the image `sandbox-router:latest-main` from the staging registry.
- **`sandboxd`** (`packages/sandboxd/`): a runtime daemon inside the sandbox Pod. It serves gRPC `:9090` for processes and HTTP `:8080` for files (KEP-539.2). [doc] (AS`packages/sandboxd/USER_GUIDE.md`)

## 5. Metrics, benchmarks and scale settings

**Controller metrics** (AS`docs/metrics.md`) [doc]:

`agent_sandbox_build_info`, `agent_sandbox_claim_controller_startup_latency_ms`, `agent_sandbox_claim_creation_total`, `agent_sandbox_claim_startup_latency_ms`, `agent_sandbox_client_claim_startup_latency_ms`, `agent_sandbox_creation_latency_ms`, `agent_sandbox_expired_total`, `agent_sandbox_finished_total`, `agent_sandbox_resume_latency_ms`, `agent_sandbox_resume_total`, `agent_sandbox_suspend_latency_ms`, `agent_sandbox_suspend_total`, `agent_sandbox_warmpool_size`, `agent_sandboxes`.

The `launch_type` label separates `cold` from `warm`. Latency histograms have second-level precision for creation. [doc] The router has separate Prometheus and OpenTelemetry output. [doc] (AS`sandbox-router/README.md`)

**Published numbers** (AS`docs/performance-tuning.md`) [doc]:

| Measure | Value | Test setup |
|---|---|---|
| Burst warm adoption | ~300 claims/s for each cluster, p90 ≤ 200 ms | 3,600 claims in 12 s from a 3,700-replica pool |
| Sustained refill for each pool | ~70–85 sandboxes/s | limited by kube-scheduler `--kube-api-qps=50` |
| Warm adoption, sustained profile | p50 92 ms, p90 182 ms, p99 376 ms | 45/s Poisson, 4 pools, kops, k8s 1.35.6 |
| Cold start (GKE) | ~42–50 s p50 | 75-claim burst, k8s 1.36.2, 20 nodes |
| `max-refill-rate` effect | ~15 % lower p50/p90 | GKE A/B |
| Write-behind window 250 ms | 44 % fewer 409 conflicts, sustained p50 +58 % | 12-node kops |

The roadmap sets a target of "1000+ claims per second" and "200ms ➔ 100ms ➔ 50ms" claim latency. Both are "📅 Planned". [doc] I found no published density number (sandboxes per node) and no gVisor-specific startup number. UNVERIFIED.

**Warm pool sizing.** [doc] (performance-tuning)

- "For sustained claim rates above ~30 claims/s or warm pools larger than ~500–1,000 replicas", split capacity across several pools.
- Set `--sandbox-warm-pool-concurrent-workers` to the number of pools. The work queue handles one pool at a time.
- Set `--sandbox-warm-pool-max-refill-rate` (for example `50`–`100`). The default `0` means no pacing, with batches up to `--sandbox-warm-pool-max-batch-size` (default 300).
- Do not use `--sandbox-warm-pool-replenish-delay` unless claim creation never fails. In one test it drained the pool and gave a p90 of 205 s.
- `SandboxWarmPool` has a `/scale` subresource for an HPA. [src]

**Controller defaults** (AS`docs/configuration.md`) [doc]: `--sandbox-concurrent-workers` 100, `--sandbox-claim-concurrent-workers` 50, warm-pool workers 1, template workers 1. `--kube-api-qps` -1 (no client rate limit). `--cache-label-selectors` false.

**API server load.** [src] [doc]

- Objects for each sandbox: 1 `Sandbox`, 1 `Pod`, an optional headless `Service`, N `PVC`s, and 1 `SandboxClaim` if you use extensions. There is one shared `NetworkPolicy` for each template.
- "each `Sandbox` object is ~10 KB in etcd (inlined `podTemplate` + `managedFields`)". [doc]
- Watches: the controller watches Sandbox, Pod, Service, SandboxClaim, SandboxWarmPool, SandboxTemplate and NetworkPolicy. Without `--cache-label-selectors`, the Pod and Service caches cover the whole cluster. The flag reduces "informer scope from O(cluster pods) to O(sandbox pods)". [src] [doc]
- The router with `--cache-enabled=true` adds one Pod informer, filtered on the label `agents.x-k8s.io/sandbox-name-hash`. [doc]
- Large refill bursts "spike etcd MVCC growth, saturates the API server watch ring buffer". An opt-in APF overlay (`examples/apf-insulation/`) reserves API server capacity for claims. [doc] (AS`docs/apf-insulation.md`)
- Scale ceiling: "~50k/cluster ceiling", from `examples/multi-cluster-fleet/ARCHITECTURE.md`. That doc is an example design doc, not a release doc. [doc] The capacity-cliff recipe uses ClusterLoader2 and kwok to find the limit. [doc] (AS`dev/load-test/test-recipes/README-capacity-cliff.md`)

## 6. Relationship to Agent Substrate

**A primary source exists.** It is in the agent-sandbox repo, not in the Substrate repo.

- `examples/multi-cluster-fleet/ARCHITECTURE.md`, section "Substrate compatibility" (`v1.0.12` and `main`) [doc]:
  - "**Substrate** (github.com/agent-substrate/substrate) is a peer OSS project. Not a layer above or below agent-sandbox — an independent Google-adjacent system for stateful 'actor' workloads on Kubernetes."
  - It maps the concepts. `SandboxWarmPool` ↔ `WorkerPool` and `SandboxTemplate` ↔ `ActorTemplate` are on the "Same code path". `Sandbox` (a CR for each instance) ↔ Actor ("Redis record via `ate-api-server` gRPC") is "**Fundamentally different**". It names the Substrate group `substrate.ate.dev/v1alpha1`.
  - "Substrate's whole design deliberately keeps per-instance state out of etcd (actors live in Redis) to avoid the CRD scale cliff sandbox is currently hitting."
  - A shared `WorkloadKind` interface for a fleet controller is proposed. "None of this is implemented".
  - The parent KEP-1434 is by `@vicentefb`, and four maintainers approved it. That KEP does not mention Agent Substrate. UNVERIFIED that a maintainer wrote the Substrate section.
- **Conflict with Substrate's own docs.** This design doc says Redis and `substrate.ate.dev/v1alpha1`. Substrate's own `v1.0.1` docs say PostgreSQL and `ate.dev/v1`. See [agent-substrate.md](agent-substrate.md). Use Substrate's own docs. This design doc is probably out of date. [inference]
- `examples/managed-agents/claude-managed-agents/README.md` (on `main` only, commit `8dbbec0f`, 2026-11-19) [doc]: it "adapts agent-substrate/claude-managed-agents (Apache-2.0) from Agent Substrate actors to the Agent Sandbox CRDs and Go SDK". The acknowledgement says "Copyright 2026 Google LLC".
- Substrate side (code search in org `agent-substrate` at `8368e765`) [src]:
  - The term "kubernetes-sigs" appears only in a lint config. The term `agents.x-k8s.io` does not appear.
  - `site/README.md` says the site theme "follows the Agent Sandbox site".
  - `docs/concepts/architecture.md` calls actors "(Agent Sandboxes)" as a general term. Its control plane "relies on the Kubernetes control plane for infrastructure and worker (Pods) provisioning".
- Issue search: `is:issue substrate` in agent-sandbox found two PRs (#1435, #1307). The titles do not mention Substrate, and I found no Substrate text in the visible part of #1435. [doc]

**Conclusion.** Substrate does not build on agent-sandbox. The two projects solve the same problem with different state models. Agent Sandbox uses one CR for each sandbox in the Kubernetes API. Substrate keeps actors outside the Kubernetes API, behind its own API server. [doc] They are alternatives. Some ideas and code move between them (examples, theme, a shared pool/template shape). [inference]

## Starter glossary

- **CRD (CustomResourceDefinition):** an object that adds a new kind of resource to the Kubernetes API.
- **Controller:** a program that watches resources and changes the cluster until it matches each spec.
- **`Sandbox`:** one Pod with a stable name, optional disks and a lifecycle (run, suspend, expire).
- **`SandboxTemplate`:** a reusable recipe for a Sandbox, with a default network policy.
- **`SandboxWarmPool`:** a set of Sandboxes that run before anyone asks, so a request gets one fast.
- **`SandboxClaim`:** a request that takes one Sandbox from a warm pool, or makes a new one if the pool is empty.
- **Warm adoption:** the claim takes a Sandbox that already runs, so no new Pod must start.
- **Cold start:** the controller must create and schedule a new Pod for the claim.
- **`operatingMode: Suspended`:** the controller deletes the Pod but keeps the Sandbox object and its disks.
- **`volumeClaimTemplates`:** disk requests that the controller turns into PVCs owned by the Sandbox.
- **`RuntimeClass`:** a Kubernetes object that tells the node which container runtime to use for a Pod.
- **gVisor (`runsc`):** a runtime that runs a kernel in user space between the container and the host.
- **`systrap`:** the default gVisor platform. It needs no KVM.
- **Kata Containers:** a runtime that puts each Pod in a small VM. It needs hardware virtualization.
- **Sandbox router:** a proxy that sends HTTP or gRPC traffic to the correct sandbox Pod by header.
- **`sandboxd`:** a daemon inside the sandbox Pod that runs commands and moves files for the SDKs.
- **APF (API Priority and Fairness):** an API server feature that divides request capacity between clients.
- **Agent Substrate:** a separate project that runs agent "actors" on Kubernetes and keeps their state outside the Kubernetes API.

## Sources

- https://github.com/kubernetes-sigs/agent-sandbox/tree/v1.0.12: `README.md`, `OWNERS`, `LICENSE`, `roadmap.md`, `api/v1beta1/groupversion_info.go`, `api/v1beta1/sandbox_types.go`, `extensions/api/v1beta1/{groupversion_info,sandboxtemplate_types,sandboxclaim_types,sandboxwarmpool_types}.go`, `controllers/sandbox_controller.go`, `extensions/controllers/{sandboxtemplate,sandboxclaim,sandboxwarmpool}_controller.go`, `cmd/agent-sandbox-controller/main.go`, `k8s/extensions.controller.yaml`, `k8s/crds/`, `docs/{metrics,performance-tuning,configuration,apf-insulation,api-migration-guide}.md`, `docs/security/threat_model.md`, `docs/keps/*/kep.yaml`, `helm/README.md`, `sandbox-router/README.md`, `packages/sandboxd/USER_GUIDE.md`, `site/content/docs/getting_started/install_prerequisites/_index.md`, `site/content/docs/use-cases/gvisor-isolation/_index.md`, `site/content/docs/sandbox/snapshots/_index.md`, `dev/load-test/test-recipes/README-capacity-cliff.md`, `examples/multi-cluster-fleet/ARCHITECTURE.md`, `clients/`
- https://github.com/kubernetes-sigs/agent-sandbox/blob/main/examples/managed-agents/claude-managed-agents/README.md (commit `8dbbec0f`)
- https://github.com/kubernetes-sigs/agent-sandbox/releases/tag/v1.0.12
- https://github.com/kubernetes-sigs/agent-sandbox/issues?q=substrate and https://github.com/kubernetes-sigs/agent-sandbox/pull/1435
- https://agent-sandbox.sigs.k8s.io/ (the same content as `site/content/` in the repo)
- https://kubernetes.io/blog/2026/03/20/running-agents-on-kubernetes-with-agent-sandbox/
- https://kubernetes.io/blog/2026/09/22/sig-apps-spotlight/
- https://github.com/agent-substrate/substrate (README, `site/README.md`, `docs/concepts/architecture.md` at `8368e765`)
- https://github.com/google/gvisor/blob/master/g3doc/user_guide/containerd/quick_start.md and https://github.com/google/gvisor/blob/master/g3doc/user_guide/platforms.md (at `168b84e6`)
- https://docs.k3s.io/advanced ("Alternative Container Runtime Support", "Configuring containerd")
