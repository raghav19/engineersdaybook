# Agent Substrate: agents on Kubernetes

Question: LinkedIn posts and blogs talk about an "agent substrate" for AI agents on Kubernetes. What is it? What problems does plain Kubernetes have with agent workloads? What does the project add, and how does it fit on an existing cluster? Can it run on a local single-node k3s cluster? Which knobs test it at scale, and are there published numbers?

Research date: 2026-11-23. Local repo state: `main` at `160d789`.

Versions read (all primary sources):

- `agent-substrate/substrate` `main` at `8368e76` (2026-11-22). The latest tag is `v1.0.1` (`20778a6`). I cite docs at `main`. Since `v1.0.1`, the docs I read changed in `benchmarking.md` and `api-guide.md` only, by 72 lines.
- `kubernetes-sigs/agent-sandbox` `main` at `5c0e127`. The latest tag is `v1.0.12` (`4863a62`, 2026-11-18). The earlier note read `v1.0.11`.
- `kagent-dev/kagent` `main` at `deaeb86` (2026-11-23).
- Google Cloud blog post of 2026-09-16, read on 2026-11-23.
- GitHub release pages and issue #3060 of `agent-substrate/substrate`, read on 2026-11-23.

Evidence tags:

- **[doc]**: an official doc page, README or maintainer blog. A URL is given.
- **[src]**: source code or a manifest at the commit above. File and line are given.
- **[issue]**: a GitHub issue or release page of the project.
- **[inference]**: my own conclusion. No source says it.
- **UNVERIFIED**: I found no primary source, or I could not read the page.

I read these pages and ran no cluster. The sandbox proxy blocked these pages: the NVIDIA blog, kagent.dev, cncf.io, the GKE install guide, the Google Open Source blog and the Solo.io blog. Claims that come only from those pages are UNVERIFIED.

Related notes: [kubernetes-agent-sandbox.md](kubernetes-agent-sandbox.md) (the peer project) and [agent-benchmark-low-memory.md](agent-benchmark-low-memory.md) (footprint and benchmark method).

## Summary

1. **"Agent Substrate" is a real project, not a generic term.** The repo is `github.com/agent-substrate/substrate`, under the Apache-2.0 license. Google started it. Google and Solo engineers maintain it. I found no other project with this name. [src] [doc]
2. **Status.** The first commit and tag `v0.0.0` are from 2026-05-19. `v0.1.0` ("The First Release") came out on 2026-09-10. `v1.0.0` came out on 2026-11-05. The latest release is `v1.0.1` (2026-11-20). [src] [issue]
3. **CNCF.** Issue #3060 says the project "has been formally accepted into the CNCF Sandbox following the TOC vote pass". Onboarding is still open. [issue]
4. **Core idea.** Substrate keeps many stateful "actors" on a small pool of warm "worker" Pods. It checkpoints idle actors to object storage and restores them on the next request. Its own control plane and a PostgreSQL store do this, not the Kubernetes API server. [doc]
5. **It is a different project from `kubernetes-sigs/agent-sandbox`.** Agent Sandbox gives one Pod per sandbox through `RuntimeClass`. Substrate puts many actors on one Pod and runs `runsc` or Cloud Hypervisor inside the worker Pod. The GKE blog says the two "continue to work side by side". [doc]
6. **Local use.** The documented local path is kind on Docker. gVisor needs no host install. The cluster must have three certificate APIs turned on. The microVM class needs `/dev/kvm`. [src]
7. **Numbers.** The project states "less than 500ms" resume, "more than 500 activations per second" and "10x higher density". No primary source that I could read publishes the method, the hardware or a raw result. The repo has a large benchmark harness that you can run yourself. [doc] [inference]

## What the project is

### Identity

| Field | Value | Source |
|---|---|---|
| Name | Agent Substrate ("ate" in binaries, CRDs and `kubectl-ate`) | [README.md](https://github.com/agent-substrate/substrate/blob/8368e76/README.md) [src] |
| Owner org | `agent-substrate` on GitHub | [repo](https://github.com/agent-substrate/substrate) [src] |
| Tagline | "Zero-trust sandboxing for millions of agents on Kubernetes." | README.md line 9 [src] |
| License | Apache License 2.0 | `LICENSE` [src] |
| Maintainers | 19 people: 16 Google, 3 Solo | [MAINTAINERS.md](https://github.com/agent-substrate/substrate/blob/8368e76/MAINTAINERS.md) [src] |
| First commit and tag | `af3c6508` and `v0.0.0`, 2026-05-19, "This is the initial commit." | git log, [releases page 2](https://github.com/agent-substrate/substrate/releases?page=2) [src] [issue] |
| First release | `v0.1.0` "The First Release", 2026-09-10. It says Substrate "will continue to make breaking changes for the immediate future". | releases page 2 [issue] |
| 1.0 | `v1.0.0` "Fully armed and operational", 2026-11-05 | [releases](https://github.com/agent-substrate/substrate/releases) [issue] |
| Latest | `v1.0.1`, published 2026-11-20. It is a security and bug-fix release. | releases [issue] |
| CNCF | Issue [#3060](https://github.com/agent-substrate/substrate/issues/3060), opened 2026-10-21, open: "formally accepted into the CNCF Sandbox following the TOC vote pass". It points to `cncf/sandbox#523` and `#542`. | [issue] |
| Docs site | `ate.dev` (not read, the repo `docs/` folder is the same source) | README [src] |

Notes on the dates:

- The release page shows no year. I took the year from the tag commit dates in git. [inference]
- A search summary says the CNCF page gives 2026-09-28 as the acceptance date and 2026-05-13 as the first commit. I could not open cncf.io. UNVERIFIED.

### Maturity, as the sources state it

- The README says "Agent Substrate has reached 1.0". It promises no breaking API or config change without a major version. [README.md, "Status and compatibility"](https://github.com/agent-substrate/substrate/blob/8368e76/README.md) [src]
- The same README says "the project is VERY young" in the "Developing" section. [src]
- The version skew policy applies "from 1.0.0". Patch releases "add no API fields". [docs/reference/version-skew-policy.md](https://github.com/agent-substrate/substrate/blob/8368e76/docs/reference/version-skew-policy.md) [src]
- GKE: "open source and available to all GKE customers for non-production workloads. GA support for production is available via allowlist." [GKE blog, 2026-09-16](https://cloud.google.com/blog/products/containers-kubernetes/agent-substrate-available-on-gke) [doc]
- Some features need preview gates (`--preview`). Examples are `GoldenEgressPolicy`, `ExternalVolumes` and `PerTemplateSnapshotLocation`. [docs/reference/api-guide.md](https://github.com/agent-substrate/substrate/blob/8368e76/docs/reference/api-guide.md) [src]
- Many security principles have the status "In Progress" or "Future". See "Mapping table". [src]

### What the buzz refers to

- The LinkedIn and blog buzz refers to this project. The GKE launch blog (2026-09-16, by Alex Zakonov and Tim Hockin) links `ate.dev`. [doc]
- The Substrate README names two consumers. These are Google **Agent Executor** (`github.com/google/ax`) and **kagent**. [src]
- **kagent** runs its agents on Substrate. Its README says "Substrate runs the agents and manages their lifecycle, including suspension, resumption, and snapshots" ([README.md line 106](https://github.com/kagent-dev/kagent/blob/deaeb86/README.md)). [src]
- kagent pins a **fork**: `replace go.ate.dev/substrate => github.com/kagent-dev/substrate v1.1.0-alpha1` ([go/go.mod line 516](https://github.com/kagent-dev/kagent/blob/deaeb86/go/go.mod)). [src]
- Search results say that kagent docs use Substrate `v0.0.6` and claim a 150 ms wake. I could not open kagent.dev. UNVERIFIED.
- Search results say an NVIDIA blog pairs Substrate with KAI Scheduler and Dynamo. I could not open it. UNVERIFIED.
- Third-party posts (DoiT, Solo.io topic pages, Signadot) helped me find the name only. I use none of them as a source.

### Core model

- **Actor**: a stateful workload instance, such as an agent. It lives in an **atespace** (`<atespace>/<actor>`). [docs/get-started/overview.md](https://github.com/agent-substrate/substrate/blob/8368e76/docs/get-started/overview.md) [src]
- **Worker**: a pre-started sandbox Pod in a **WorkerPool**. Actors move between workers. [src]
- **ActorTemplate**: an immutable definition of image, resources and snapshot policy. Substrate makes a "golden snapshot" from it so that new actors start fast. It is **not** a Kubernetes object. You manage it through the Substrate gRPC API and `kubectl ate`. [docs/concepts/architecture.md lines 173 to 221](https://github.com/agent-substrate/substrate/blob/8368e76/docs/concepts/architecture.md) [src]
- **Lifecycle**: `SUSPENDED → RESUMING → RUNNING → SUSPENDING → SUSPENDED`. A request to `atenet-router` with the header `ate-target-actor: <atespace>/<actor>` resumes a suspended actor. [architecture.md lines 402 to 443] [src]
- **Suspend comes from the caller.** The architecture doc says Phase 3 is "Triggered by an explicit `SuspendActor` call". The Claude Code demo "suspends it when the task ends". [architecture.md line 499], [demos/claude-code-multiplex/README.md](https://github.com/agent-substrate/substrate/blob/8368e76/demos/claude-code-multiplex/README.md) [src]
- The quickstart says "When the actor becomes idle, Substrate checkpoints its memory". I found no idle timer in the docs. Automatic idle suspend is UNVERIFIED.

## Plain-Kubernetes issues for agent workloads

This list has only issues that a primary source states. Each item names its source.

1. **Idle Pods cost money.** "Idle Pods still consume resources... agent-like workloads are terrible for efficiency." [Substrate architecture.md line 147] [src]
2. **The API server does not scale to millions of agents.** "The Kubernetes API server is not designed to handle millions of resources... or for handling a huge volume of write traffic." [architecture.md line 151] [src]
3. **Pod start is too slow for short work.**
   - Substrate: "Getting a Pod running in a couple of seconds is great when that Pod will run for hours or days." For millisecond-to-second work, "that latency is unacceptable". [architecture.md lines 155 to 159] [src]
   - GKE blog: "routing each sub-second tool invocation through the standard Kubernetes Pod lifecycle adds seconds of delay to each request." [doc]
4. **PersistentVolumes do not fit many small states.** PVs are "not designed for millions of volumes... being attached and detached at high Speed." [architecture.md line 160] [src]
5. **No primitive for a singleton stateful session.** Deployments and StatefulSets do not fit. "StatefulSets (size 1), Services, and PersistentVolumeClaims" can approximate it. That "is cumbersome and lacks specialized lifecycle management like hibernation." [agent-sandbox README.md, "Motivation"](https://github.com/kubernetes-sigs/agent-sandbox/blob/5c0e127/README.md) [src]
6. **A plain container is not enough for untrusted code.**
   - Agent Sandbox wants gVisor or Kata, which is "crucial for running untrusted code or multi-tenant scenarios". [agent-sandbox README.md, "Desired Sandbox Characteristics"] [src]
   - Substrate: "A linux container is not sufficient or supported." [docs/security/security.md](https://github.com/agent-substrate/substrate/blob/8368e76/docs/security/security.md) [src]
   - The earlier note [podman-sandbox-runtimes.md](podman-sandbox-runtimes.md) covers the runtimes themselves (gVisor, krun).
7. **No stable identity without extra objects.** Agent Sandbox lists a "stable hostname and network identity" as a feature. It names "efficient traffic routing without per-sandbox Services" as a goal. [agent-sandbox README.md] [src]
8. **Warm pools and fast claims.** Agent Sandbox names "low-latency warm-pool claims" for RL and evaluation loops. Substrate pre-starts worker Pods "to avoid the latency of going through the Kubernetes scheduler". [agent-sandbox README.md], [architecture.md line 49] [src]
9. **Agents are bursty, untrusted and many.** "Because they often run untrusted logic... they are usually single-tenant instances, and there are a great many of them." [architecture.md lines 23 to 28] [src]

These items are **not stated by any primary source as a plain-Kubernetes gap**:

- **Per-agent credentials and egress control.** Substrate states these as its own goals ("Zero Ambient Credentials", "Fail-Closed Policy-Enforced Egress Gateway"). It does not say that plain Kubernetes fails at them. [src]
- **Observability of sessions.** Substrate says that multiplexing **creates** this need: "with actors multiplexed onto and off of workers, operators need actor-level and pool-level visibility" (architecture.md line 90). It is a cost of the design, not a plain-Kubernetes gap. [src]
- **Data loss from memory checkpoints.** The Agent Sandbox suspend KEP lists the opposite risk. If a controller writes memory dumps silently, those dumps "can quickly fill cloud storage buckets". [docs/keps/694-kep-for-suspend-and-resume-for-beta/README.md line 77](https://github.com/kubernetes-sigs/agent-sandbox/blob/5c0e127/docs/keps/694-kep-for-suspend-and-resume-for-beta/README.md) [src]

## Mapping table

Columns: the issue, what plain Kubernetes gives, the Substrate feature, and what stays unsolved. All Substrate paths are under `https://github.com/agent-substrate/substrate/blob/8368e76/`.

| Issue | Plain K8s | Substrate feature | Still unsolved |
|---|---|---|---|
| Cost of many idle agents | One Pod per agent stays resident while idle (issue 1). | Suspend writes a snapshot to GCS or S3 and frees the worker. Many actors share a WorkerPool. The README claims "10x–30x Oversubscription". [README.md] | The caller must call `SuspendActor`. An idle timer is UNVERIFIED. Snapshots create "a large data management problem" (architecture.md line 74). |
| Cold start | Scheduler, image pull and start take "a couple of seconds" (issue 3). | Warm worker Pods, a golden snapshot for each template, and a node-local snapshot copy after suspend. The hot path does not use the Kubernetes API. [architecture.md] | The <500 ms claim has no published method. The target is 100 ms at p95 (architecture.md line 104). "Substrate does not steer restores away from busy nodes" (benchmarking.md line 815). |
| Untrusted code | `runc` by default. Sources say that a plain container is not enough (issue 6). | Every actor runs in gVisor (`runsc`) or a Kata guest on Cloud Hypervisor. Plain containers are "not supported". [security.md] | Workers run as UID 0 with `SYS_ADMIN` and `NET_ADMIN`. Seccomp and AppArmor are `Unconfined` for the outer worker. They "still require trusted nodes" (api-guide.md, "Worker security"). "Delete Guarantee" is In Progress. gVisor ignores per-container limits (sandbox-classes.md). |
| Hibernation and checkpoint/restore | No hibernation (issue 5). PVs do not fit (issue 4). | Three snapshot fidelities: `VOLUMES`, `ROOTFS`, `MEMORY` (default). gVisor uses `runsc` checkpoint. The microVM class uses a Cloud Hypervisor memory snapshot and `userfaultfd`. [architecture.md lines 345 to 347, 537 to 545] | An async suspend (the default) can lose state "if the node fails before background upload completes". A `MEMORY` restore needs the same runtime version, or it falls back to `ROOTFS`. Per-actor encryption and restore authorization are Future. Per-actor S3 scoping is "planned". A GKE Spot VM gives 15 s by default, so the actor can crash first (api-guide.md line 722). |
| Singleton stateful session with stable identity | StatefulSet of 1, Service and PVC, which is "cumbersome" (issue 5). | An actor record with a UID in PostgreSQL. Callers reach it by `ate-target-actor: <atespace>/<actor>` through `atenet-router`. [api-guide.md, "Workload Connectivity"] | No per-actor DNS name or fixed IP. The actor moves between workers. Only HTTP(S) reaches a non-default port. "raw TCP or other non-HTTP protocols on a non-default port are not yet reachable" (architecture.md line 374). Actor networking is IPv4-only (network-egress.md line 19). |
| API server scale | Not built for millions of objects or high write rates (issue 2). | Actors, templates and workers live in `ate-api-server` with PostgreSQL. Only WorkerPool, SandboxConfig and CSIDriverConfig are CRDs. [docs/reference/resource-model.md] | PostgreSQL becomes the limit. The guide lists connection slots, probe timeouts and `max_connections` (benchmarking.md "Running at scale"). Isolate mode exists to measure this limit. |
| Per-agent identity and credentials | No source states the gap. | A 1 h SPIFFE X.509 certificate for each actor, actor JWTs on demand and an OIDC issuer. `atenet-egress` injects credentials outside the sandbox. Worker Pods "never get a ServiceAccount token". [security.md, api-guide.md] | Actor-to-actor authorization is Future. Sub-actor provenance and human-to-actor authentication are Out of Scope. The quickstart credential provider is default-deny until you grant namespaces. |
| Egress control | No source states the gap. | Default-deny egress. A DNS relay answers `NXDOMAIN` for names that no policy allows. A fail-closed egress PEP that can do MITM and header injection. [docs/guides/egress-traffic.md] | WebSocket, CONNECT, other TCP and UDP other than DNS are blocked. A `tls_passthrough` rule is the only exception. One shared egress proxy serves all actors. Per-actor or per-atespace proxies are "Not Currently Supported". Egress bandwidth quotas are Future. |
| Warm pools | Pods go through the scheduler on demand (issue 8). | `WorkerPool.spec.replicas` keeps N warm Pods. The CRD has a `scale` subresource. The SLO doc says it "can be autoscaled via HPA". [src: `api/infra/k8s/ate/v1/workerpool_types.go` line 260, docs/guides/slos-and-alerts.md line 196] | No built-in pool autoscaler is documented. Request parking holds requests for `--parked-request-budget` (default 5 s) when the pool is full (docs/concepts/request-parking.md). |
| Scale to zero | An idle Pod stays scheduled (issue 1). | A suspended actor uses no worker. | Workers stay warm at `replicas`. PostgreSQL, the router, the egress gateway, `atelet` and the controllers always run. Worker scale to zero is not documented. UNVERIFIED. |
| Observability of sessions | The source frames this as a need that multiplexing creates. | `ate.*` attributes on actor logs, `kubectl ate logs`, OTel metrics and head-sampled traces (10 %, 1 % at the router). [docs/guides/observability.md] | Actor-level correlation for metrics and traces is on the "roadmap". Actor telemetry needs an egress rule. OOMs inside a microVM guest "are invisible" (benchmarking.md). |
| GPUs | Device plugins exist. | None. "Substrate does not pass devices through to actors." [api-guide.md, "Devices (GPUs)"] | GPU workloads in actors are not supported. |

## Fit on an existing cluster

### Kubernetes objects

- **CRDs** in group `ate.dev/v1` [src: `api/infra/k8s/ate/v1/`]:
  - `WorkerPool`: namespaced, with `status` and `scale` subresources (`workerpool_types.go` lines 258 to 260). `atecontroller` turns each pool into a Deployment of worker Pods.
  - `SandboxConfig`: cluster-scoped. It lists the sandbox runtime versions and the asset URLs with sha256 for each CPU architecture (`sandboxconfig_types.go` line 190).
  - `CSIDriverConfig`: cluster-scoped. It gives atelet access to CSI drivers without PV or PVC (`csidriverconfig_types.go` line 78).
- **Other Kubernetes objects:** Secrets that carry trust bundles, a `StorageClass`, `PodCertificateRequest` objects for worker mTLS identity, a DaemonSet for `atelet`, and NetworkPolicies for `ate-system`. [slos-and-alerts.md lines 191 to 206](https://github.com/agent-substrate/substrate/blob/8368e76/docs/guides/slos-and-alerts.md) [src]
- **No `RuntimeClass`.** The worker image runs `runsc`, or Kata with Cloud Hypervisor, inside the worker Pod. `atelet` downloads the sandbox binaries from the `SandboxConfig` URLs into a node cache. The gVisor default comes from the public `gs://gvisor` bucket. [docs/concepts/sandbox-asset-cache.md](https://github.com/agent-substrate/substrate/blob/8368e76/docs/concepts/sandbox-asset-cache.md), [manifests/ate-install/sandboxconfig-gvisor.yaml](https://github.com/agent-substrate/substrate/blob/8368e76/manifests/ate-install/sandboxconfig-gvisor.yaml) [src]
  - This is the main difference from Agent Sandbox, which "delegates low-level container isolation" through `RuntimeClass`. [agent-sandbox README.md] [src]
- **Not Kubernetes objects:** Atespace, ActorTemplate, Actor, Tag, Worker, EgressPolicy and AccessPolicy. They live in `ate-api-server` (gRPC) and PostgreSQL. OpenFGA authorizes them for each atespace, not Kubernetes RBAC. [resource-model.md, architecture.md lines 251 to 257] [src]

### Components installed

From README "Tour", version-skew-policy.md and the quickstart [src]:

| Component | Kind | Role |
|---|---|---|
| `ate-api-server` (`cmd/ateapi`) | Deployment | gRPC API, scheduler, suspend and resume workflow. It has an `objectstore-plugin` sidecar. |
| PostgreSQL | StatefulSet (bundled), or Cloud SQL | State of actors and workers |
| `ate-controller` (`cmd/atecontroller`) | Deployment | Turns WorkerPools into Deployments |
| `atelet` | DaemonSet | Node supervisor, checkpoint and restore, asset cache, snapshot moves |
| Worker Pods (`ateworker-gvisor` or `ateworker-microvm`) | Deployment for each WorkerPool | Sandbox host, `atunnel` |
| `atenet-router`, `atenet-egress` | Deployments (Envoy or agentgateway) | Ingress with resume and parking. Egress PEP with credential injection. |
| `ate-idp-server` | Deployment | OIDC discovery and keys for actor JWTs |
| `podcertificate-controller` | Deployment | A "polyfill" signer for Pod certificates |
| Credential provider (`{"name":"k8s.io"}`) | Deployment | Reads Kubernetes Secrets for egress injection |
| Object storage | GCS or S3, `rustfs` on kind | Snapshots and microVM assets |
| OTel collector, Prometheus, Jaeger | Optional on kind | Telemetry |

### Kubernetes version and cluster prerequisites

- **Kubernetes versions:** "the latest stable release of Kubernetes, and the previous minor release." [README.md, "Supported Kubernetes Releases"] [src]
- **Certificate APIs.** `podcertcontroller` "depends on ClusterTrustBundle & PodCertificateRequest. They are not enabled by default as of Kubernetes v1.36". The kind script turns on `ClusterTrustBundle`, `ClusterTrustBundleProjection`, `PodCertificateRequest` and the runtime config `certificates.k8s.io/v1beta1`. [hack/create-kind-cluster.sh lines 105 to 113](https://github.com/agent-substrate/substrate/blob/8368e76/hack/create-kind-cluster.sh) [src] The note [agent-benchmark-low-memory.md](agent-benchmark-low-memory.md) says that all three are GA and on by default in 1.37. Check the cluster with `kubectl api-resources`.
- **Worker privileges.** Workers need UID 0 and `SYS_ADMIN`, `NET_ADMIN` and other capabilities. Seccomp and AppArmor are `Unconfined`. Workers "require trusted nodes". [api-guide.md, "Worker security"] [src]
  - A namespace with Pod Security Admission `baseline` or `restricted` rejects such Pods. You need `privileged` for the worker namespace. [inference]
- **Node isolation (optional).** `--cordon-system-infra-components` keeps the control plane on tainted nodes of its own. [architecture.md lines 386 to 398] [src]

### Comparison with Agent Sandbox

| Point | Agent Sandbox (`kubernetes-sigs`) | Agent Substrate |
|---|---|---|
| Unit | One `Sandbox` = one Pod | Many actors on one worker Pod (`--max-actors` default 1000) |
| Isolation | `RuntimeClass` (gVisor, Kata) | `runsc` or Cloud Hypervisor inside a privileged worker Pod |
| State store | Kubernetes API (CRDs) | PostgreSQL behind its own gRPC API |
| Warm pool | `SandboxWarmPool`, `SandboxClaim` | `WorkerPool` |
| Min Kubernetes | 1.25, with 1.29 recommended | latest stable and previous minor, plus the certificate APIs |
| Extra infra | Controller only (router optional) | PostgreSQL, object storage, router, egress gateway, DaemonSet |

Sources: [agent-sandbox README.md](https://github.com/kubernetes-sigs/agent-sandbox/blob/5c0e127/README.md), Substrate docs above. [src]

## Local cluster requirements

**Install paths:**

1. **kind (local):**
   - `hack/create-kind-cluster.sh`, then `export ATE_INSTALL_KIND=true`.
   - Then `go run ./cmd/ate-setup deploy ate-system --credential-provider='{"name":"k8s.io"}' --ingress-allowed-spiffe-ids=spiffe://cluster.local/ns/ate-system/sa/atenet-client`.
   - Then `go run ./cmd/ate-setup deploy demo counter`, `go install ./cmd/kubectl-ate` and `kubectl ate create actor ...`.
   - Source: [docs/get-started/quickstart.md](https://github.com/agent-substrate/substrate/blob/8368e76/docs/get-started/quickstart.md). [src]
   - The install brings PostgreSQL and `rustfs` snapshot storage into the cluster.
2. **GKE:** the GKE installation guide and [`ai-on-gke/substrate-gke`](https://github.com/ai-on-gke/substrate-gke). [README.md] [src] I could not open the GKE guide. UNVERIFIED.
3. **Other clusters with pre-built images:** `ate-setup deploy ate-system --storage-bucket-name=BUCKET --image-repo ... --image-tag vX.Y.Z`. [cmd/ate-setup/README.md](https://github.com/agent-substrate/substrate/blob/8368e76/cmd/ate-setup/README.md) [src]

Notes for a k3s target:

- The `--kind` profile sets the kube context to `kind-<name>` ([cmd/ate-setup/internal/config/load.go line 344](https://github.com/agent-substrate/substrate/blob/8368e76/cmd/ate-setup/internal/config/load.go)). So a k3s target uses the "other clusters" path. [src]
- The non-kind path wants an object storage bucket. GCS is the default. S3 is selected with `ATE_STORAGE_BACKEND=s3` on the `objectstore-plugin` sidecar. [architecture.md line 337] [src]
- A k3s target needs these items [inference, UNVERIFIED as a complete list]:
  - The certificate APIs above, turned on with `--kube-*-arg` if 1.37 does not have them by default.
  - `proxy_arp` on the host.
  - An S3 store such as `rustfs` or MinIO, with `ATE_STORAGE_BACKEND=s3`.
  - The Pod Security level `privileged` for the worker namespace.
  - Pre-built images, or `ko` images, in a registry that k3s can pull from.

**Hard requirements found:**

| Requirement | Detail | Source |
|---|---|---|
| Host tools | Go, `kubectl`, Docker. The quickstart fetches kind through Go. | quickstart.md [src] |
| Certificate APIs | `ClusterTrustBundle`, `ClusterTrustBundleProjection`, `PodCertificateRequest`, and API `certificates.k8s.io/v1beta1` | create-kind-cluster.sh lines 105 to 113 [src] |
| Kubernetes version | Latest stable or previous minor | README.md [src] |
| gVisor | **No host `runsc` and no RuntimeClass.** `atelet` downloads the gVisor release for the node's CPU architecture. Default `v7` = release `20261102.0`. The backend needs a `runsc` with `--allow-connected-on-save`. | sandboxconfig-gvisor.yaml, architecture.md line 335 [src] |
| Node network | `net.ipv4.conf.all.proxy_arp=1` on each node "for gVisor loopback pod-to-pod networking". Above about 1000 sandboxes on a host, raise `gc_thresh1/2/3` to 4096/16384/32768. | create-kind-cluster.sh lines 186 to 204 [src] |
| cgroups | cgroup v2 `cpu.max` sets CPU limits. PSI must be on for a per-actor kill at the memory limit. | sandbox-classes.md, api-guide.md [src] |
| Kernel | The gVisor class drops `MKNOD` because "since Linux 5.8, 0:0 overlay whiteouts do not require it". This implies Linux 5.8 or later. | api-guide.md "Worker security" [src] [inference] |
| CPU arch | `amd64` and `arm64` assets for both classes. The pools a template selects "must also share a CPU architecture". | sandboxconfig-gvisor.yaml, docs/dev/microvm-local.md, api-guide.md [src] |
| microVM class | `/dev/kvm` on the node. atelet advertises it as resource `ate.dev/kvm`. Cloud VMs need nested virtualization. Actors need at least 128 MiB. | [docs/dev/microvm-local.md](https://github.com/agent-substrate/substrate/blob/8368e76/docs/dev/microvm-local.md), sandbox-classes.md [src] |
| containerd version | Not stated. | UNVERIFIED |
| RAM and CPU | No minimum is stated. The kind install pulls "~570MB of third-party images". The agent-session benchmark needs `--actor-memory 1Gi`. Above a few hundred sandboxes on a node, reserve CPU for the kubelet. | create-kind-cluster.sh lines 116 and 128 to 138, benchmarking.md [src] |
| Outbound network at install | `gs://gvisor` (public) for gVisor assets. GitHub for microVM assets. The registry for images. | sandbox-asset-cache.md, cmd/ate-setup/README.md [src] |

## Scale-test knobs and published numbers

### Knobs in the product

| Knob | Where | Default | Effect | Source |
|---|---|---|---|---|
| `WorkerPool.spec.replicas` | CRD | required | Number of warm worker Pods. HPA can target it through the `scale` subresource. | api-guide.md, workerpool_types.go line 260 [src] |
| `WorkerPool.spec.template.resources.limits` | CRD | unset (unconstrained) | Capacity of each worker that its actors share | api-guide.md "Worker Capacity" [src] |
| ateworker `--max-actors` | worker flag | 1000 | Most actors on one worker | api-guide.md [src] |
| `ActorTemplate.resources.limits` | ate API | required | Actor size, which sets density | api-guide.md [src] |
| `snapshotConfig.preferredFidelity` | ate API | `MEMORY` | `VOLUMES`, `ROOTFS` or `MEMORY`. Larger fidelity gives larger snapshots. | architecture.md lines 537 to 541 [src] |
| Durability mode | `SuspendActor` | async | Sync uploads before return. Async can lose state on node failure. | architecture.md lines 445 to 461 [src] |
| `--snapshot-detach-delay`, `--snapshot-upload-delay` | atelet | not read | Local snapshot life and upload delay | architecture.md [src] |
| `--parked-request-budget` | router | 5 s | How long the router holds a request for a full pool | benchmarking.md "Running at scale" [src] |
| `--extproc-max-requests` | router | not read | Envoy ext_proc circuit breaker | benchmarking.md [src] |
| `--ateapi-postgres-pool-max-conns`, `--cluster-size size10` | ate-setup | node CPU count, `size0` | PostgreSQL connection sizing | benchmarking.md, cmd/ate-setup/commands.md [src] |
| `--fake-data-plane`, `FAKE_ATELET_DELAY` | ate-setup | off | Measures the control plane without real nodes | benchmarking.md "Isolate Mode" [src] |
| `ATE_KIND_RESERVED_CPU` | kind script | none | Reserves CPU for the kubelet | create-kind-cluster.sh line 131 [src] |

### Benchmark harness

Source: [docs/guides/benchmarking.md](https://github.com/agent-substrate/substrate/blob/8368e76/docs/guides/benchmarking.md) [src]. The doc calls the harness "the nascent suite". It uses Locust with Go "boomer" workers. Deploy it with `./benchmarking/deploy_locust.sh --deploy`, which has the flags `--worker-count N` (default 1), `--worker-memory`, `--sandbox-class gvisor|microvm` and `--actor-memory`.

| Test | Knobs | Metrics |
|---|---|---|
| Spawn | `--total-actors` (100), `--spawn-concurrency` (1), `--actor-deadline` (120 s) | `ActorTimeToReady`, `TimeToReady_<k>pct`, `TimeToAllReady`, `CrashCount` |
| ResumePaused | `--target-rps`, `--burst-size`, `--ladder` (for example `200:3m@1000`) | `ResumeActorCold`, `SuspendActorAsync`, rows for each ladder step |
| Agent-session | `--agentsession-script`, `--agentsession-think-scale`, `--resume-mode implicit\|explicit`, `--lifecycle-mode sync\|async\|none`, `--agentsession-snapshot-steps`, `--agentsession-phase-in`, `--agentsession-awake` (turnover) | `TimeToWake`, `WakeFirstTouch`, step latencies |
| DurDir, Sweperf, ate-env | Not read in detail | See the guide |

The agent-session test drives a 20-step coding session. It suspends the actor during each "think" gap and wakes it through the router. It needs 1 GiB actors. [benchmarking.md lines 321 to 365] [src]

**Density output** (`trial_summary`): `actors_per_node`, `actors_per_vcpu`, `actors_per_gb_ram`, `actors_per_pod_p50/p90/p99`, `cluster_packing`, node and pod PSI, snapshot size, restore/checkpoint p50 to p99, working set and OOM events. The guide warns that "Actors are derived, not counted". It also says that "The denominators are read once, after the run". [benchmarking.md lines 855 to 1025] [src]

**Limits met at scale** ("Running at scale") [src]:

- port-forward resets under load
- PostgreSQL slots and probe timeouts
- the parking budget and synchronized bursts
- the neighbor table
- restores on saturated nodes
- kubelet heartbeat starvation

**Phase breakdown.** `benchmarking/analysis/phase_report.py` splits suspend and resume latency into phases from node logs. [benchmarking.md line 1027] [src]

### Published numbers (all vendor claims, no method)

| Claim | Source |
|---|---|
| "fast resume operations in less than 500ms, with more than 500 activations per second" | README.md, architecture.md line 12 [src] |
| "10x higher density than standard containers" | README.md [src], GKE blog [doc] |
| "~250 stateful actors across just 8 physical pods" (demo video) | README.md [src] |
| "10x–30x Oversubscription" | README.md [src] |
| "pack over 1,000 dormant agents per host" | GKE blog [doc] |
| Targets, not results: activation 100 ms at p95, 1 billion agents, 1000 wakeups per second in one cluster | architecture.md lines 99 to 110 [src] |
| "150ms" wake (kagent) | Search snippet only. UNVERIFIED. |

The GKE blog gives "no benchmark methodology, hardware specs, or test conditions". It also gives two rates: "over 500 … activations per second" and "hundreds of suspend/resume operations per second". [doc] The nightly automation writes results to a GCS bucket (`gcloud storage cat "$RUN/stats.jsonl"`). I found no public copy. UNVERIFIED.

## Open questions

1. Does Substrate suspend an idle actor without a `SuspendActor` call? The quickstart says yes. The architecture doc and demos say the caller drives it.
2. Which exact Kubernetes minor versions did the `v1.0.1` CI test? The README says "latest stable and previous minor" with no number.
3. Does the bundled PostgreSQL fit a small single-node cluster without `size10`? How much RAM does the full `ate-system` take while idle?
4. Can the WorkerPool go to zero replicas? What happens to a request when no worker exists?
5. Do the 500 ms and 500/s claims come from gVisor or from microVM, on which machine types? Is there a public run of `trial_summary`?
6. How far does the kagent fork (`v1.1.0-alpha1`) differ from upstream?
7. Does the worker's `SYS_ADMIN` and `Unconfined` profile fit your threat model? A worker escape reaches the node as root.
8. Is an image build in an actor possible? I did not check. The note [agent-sandbox-build-capability.md](agent-sandbox-build-capability.md) covers builds for Agent Sandbox only.

## Sources

Agent Substrate repo, `main` at `8368e76` (paths under `https://github.com/agent-substrate/substrate/blob/8368e76/`):

- `README.md`, `LICENSE`, `MAINTAINERS.md`
- `docs/get-started/overview.md`, `docs/get-started/quickstart.md`
- `docs/concepts/architecture.md`, `docs/concepts/sandbox-asset-cache.md`, `docs/concepts/request-parking.md` (headings only)
- `docs/reference/api-guide.md`, `docs/reference/resource-model.md`, `docs/reference/sandbox-classes.md`, `docs/reference/version-skew-policy.md`
- `docs/security/security.md`
- `docs/guides/benchmarking.md`, `docs/guides/egress-traffic.md`, `docs/guides/network-egress.md`, `docs/guides/node-storage.md`, `docs/guides/observability.md`, `docs/guides/operator-install.md`, `docs/guides/slos-and-alerts.md`
- `docs/dev/microvm-local.md`, `docs/dev/release-notes.md`
- `api/infra/k8s/ate/v1/workerpool_types.go`, `sandboxconfig_types.go`, `csidriverconfig_types.go`
- `manifests/ate-install/sandboxconfig-gvisor.yaml`, `manifests/ate-install/sandboxconfig-microvm.yaml.tmpl`
- `hack/create-kind-cluster.sh`
- `cmd/ate-setup/README.md`, `cmd/ate-setup/commands.md`, `cmd/ate-setup/differences.md`, `cmd/ate-setup/internal/config/load.go`
- `demos/counter/README.md`, `demos/claude-code-multiplex/README.md`

Agent Substrate project pages:

- https://github.com/agent-substrate/substrate/releases and `?page=2`
- https://github.com/agent-substrate/substrate/issues/3060

Google:

- https://cloud.google.com/blog/products/containers-kubernetes/agent-substrate-available-on-gke (2026-09-16)

Agent Sandbox, `main` at `5c0e127`:

- https://github.com/kubernetes-sigs/agent-sandbox/blob/5c0e127/README.md
- `docs/keps/694-kep-for-suspend-and-resume-for-beta/README.md`

kagent, `main` at `deaeb86`:

- https://github.com/kagent-dev/kagent/blob/deaeb86/README.md
- `go/go.mod` line 516
- `contrib/cncf/technical-review.md`

Not read (proxy refused), so their claims are UNVERIFIED:

- https://developer.nvidia.com/blog/agent-substrate-advancing-kubernetes-for-agents-at-scale/
- https://kagent.dev/docs/kagent/0.x/concepts/agent-substrate/
- https://www.cncf.io/projects/agent-substrate/
- https://docs.cloud.google.com/kubernetes-engine/ai-ml/install-overview-substrate
- https://opensource.googleblog.com/2026/11/sandboxing-untrusted-ai-agents-at-scale.html
- https://www.solo.io/blog/announcing-kagent-1-0-ga

Used only to find the name: DoiT, Solo.io topic page, Signadot blog, web search summaries.
