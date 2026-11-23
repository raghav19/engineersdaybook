# Agent benchmark on one low-memory k3s node

Question: The owner plans to compare agent workloads on one k3s node without KVM. What does each stack cost when idle? What does each agent cost? Which metrics show API server load on k3s? How do you measure cold start? At what scale do the differences show clearly?

The research covered three variants: A is plain Kubernetes, B is agent-sandbox with gVisor, and C is Agent Substrate with gVisor. After the research, the owner dropped variant A from the benchmark. The data for A stays here as context. The owner's node has about 13.4 GiB of RAM and about 20 cores (`kubectl top node` on 2026-11-23: 6195 Mi at 45 %, 1226m at 6 %). So the 16 GiB column of the verdict table is the nearest fit.

Research date: 2026-11-23. Local repo state: branch `main` at `160d789`.

Versions read (all primary sources):

- Agent Substrate `main` at `8368e765b5ede1f601cde3d8f03fd920eda0e481` (2026-11-22). Tag `v1.0.1` was released 2026-11-20. I compared the resource values at `v1.0.1` and at `8368e76`. These files have the same values at both refs: `postgres.yaml`, `atenet-egress.yaml`, `atelet.yaml`, `kind/postgres`, the counter template and `ateworker-gvisor/memory.go`.
- `kubernetes-sigs/agent-sandbox` tag `v1.0.12` (commit `4863a62`, released 2026-11-20).
- gVisor `master` at `168b84e`. The gVisor density CSV has no date or release.
- k3s docs (no version). The resource profiling page tested k3s `v1.26.5`. The newest k3s release is `v1.37.2+k3s1` (2026-11-03). The owner runs `v1.37.1+k3s1`.
- Kubernetes metrics reference v1.37 (`kubernetes/website` `main`, last change `8d7b470`, 2026-08-28).
- kube-burner `v2.8.7` (2026-10-26).

Evidence tags:

- **[doc]**: an official documentation page or README. A URL is given.
- **[src]**: source code or a manifest at the version above. File and line are given.
- **[inference]**: my own conclusion. No source says it.
- **UNVERIFIED**: I found no source.

I ran no cluster. All numbers come from reading files and pages.

Related notes: [agent-substrate.md](agent-substrate.md) and [kubernetes-agent-sandbox.md](kubernetes-agent-sandbox.md).

## Answer

1. **Variant C has the largest fixed overhead by far.** Its memory requests are about 1.78 GiB before any worker. PostgreSQL alone requests 1 GiB. The egress token minter requests 512 MiB. [src] Variants A and B add almost nothing to k3s. The agent-sandbox controller has no requests. [src]
2. **k3s itself needs about 1.6 GB.** The k3s profiling page measured 1596 MB for a single-node server with a workload on SQLite. That test used `v1.26.5`. [doc]
3. **gVisor adds about 20 MB per sandbox for a trivial process, and more for real apps.** gVisor's own density data gives 23.7 MB (runsc) against 4.1 MB (runc) for `sleep`. For a `node` app the values are 124 MB against 77 MB. [src]
4. **A suspended Substrate actor uses no worker memory.** Suspend checkpoints the actor and frees the worker. The snapshot stays on the node disk and also goes to object storage. [doc]
5. **Actor memory can be far below 1 GiB.** The gVisor class enforces no minimum `memoryBytes`. [doc] The Locust default is 256 MiB. [src] A sample counter actor record shows 38 MiB in use. [doc] Thus 64 MiB is plausible for an echo or counter agent, and 32 MiB is risky. [inference]
6. **There is no small Substrate profile.** `size0` is the shipped default and the smallest profile. `size10` is larger. [src] `ate-setup` always deploys and waits for `atenet-egress` and `ate-idp-server`. [src] You can turn off the OTel export. You can shrink other parts only with your own patches. [inference]
7. **On k3s, one `kubectl get --raw /metrics` call returns most API server metrics.** k3s runs all components in one process with one metric registry. [doc] Kine metrics are on the same endpoint since PR #12831. [doc] Use `apiserver_request_total`, `apiserver_resource_objects`, and `apiserver_longrunning_requests{verb="WATCH"}`. [doc]
8. **Measure cold start with kube-burner `podLatency` for A and B, and with Substrate's own metrics for C.** For B, also use `agent_sandbox_creation_latency_ms` and `agent_sandbox_claim_startup_latency_ms` (label `launch_type`). [src] For C, use `ActorTimeToReady` (Spawn), `ResumeActor`, and `ate.actor.lifecycle.operation.duration`. [doc]
9. **The kubelet pod limit binds before memory does for A and B.** The default `maxPods` is 110. [doc] With tiny agents, A and B cannot reach memory pressure on one node at any RAM tier. You must measure density as a slope (MiB for each added agent), not as maximum capacity. [inference]
10. **At 20 agents these differences already show: API object count, memory slope, and median cold start.** Object count shows at one agent. The 99th percentile needs about 100 cold-start samples. Get them by repetition, not by more agents. [inference]

## 1. Fixed overhead per stack

### k3s baseline [doc]

| Item | Value | Source |
| :--- | :--- | :--- |
| Minimum for server | 2 cores, 2 GB RAM | k3s requirements |
| Single-node server with a workload, Intel 8375C | 6% of a core, 1596 MB (SQLite), 1606 MB (etcd) | k3s resource profiling |
| Cluster with one agent | 1428 MB (SQLite) | k3s resource profiling |
| Test version | `v1.26.5` with all packaged components | k3s resource profiling |
| Scope | Datastore and control plane only. Image management and workload are not included. | k3s resource profiling |

SQLite is the default datastore for a single server. [doc] You can turn off `traefik` and `servicelb` with `--disable`. Keep `local-storage`, because PVCs need it. [doc] [inference]

### Variant A: plain Kubernetes

There is no fixed overhead beyond k3s. The StatefulSet, Service and PVC controllers are part of the k3s process. [inference]

### Variant B: agent-sandbox v1.0.12 [src]

| Workload | Replicas | Memory request / limit | CPU request / limit | Source |
| :--- | :--- | :--- | :--- | :--- |
| `agent-sandbox-controller` | 1 | none | none | `k8s/controller.yaml` L52–89 |
| Helm `resources` | — | `{}` (default). The commented example is 64Mi / 128Mi. | commented example 10m / 500m | `helm/values.yaml` L70–76 |
| `sandbox-router` (optional) | 2 | 512Mi / 1Gi each | 250m / 1000m each | `clients/python/agentic-sandbox-client/sandbox-router/sandbox_router.yaml` L22, L83–88 |

Total without the router: 0 requested. The actual RSS of the controller is UNVERIFIED. The Helm comment suggests that it fits below 128 MiB. [inference] Do not deploy the router. Its two replicas request 1 GiB. [src]

### Variant C: Agent Substrate `8368e76` [src]

All paths are under `manifests/ate-install/`.

| Workload | Replicas | Container: memory request / limit, CPU request | Source |
| :--- | :--- | :--- | :--- |
| `postgres` StatefulSet | 1 | `postgres`: 1Gi / 2Gi, CPU 2 (limit 16) | `postgres/postgres.yaml` L214–220 |
| | | `tls-reloader` sidecar: 32Mi, 10m | `postgres/postgres.yaml` L122–124, L145–148 |
| | | kind overlay: CPU 250m / 2 only. Memory stays the same. PVC 1Gi. | `kind/postgres/kustomization.yaml` L35–48 |
| | | PVC 500Gi (base) | `postgres/postgres.yaml` L259 |
| `atenet-egress` | 1 | `sdsmint`: 512Mi / 768Mi, 200m, `GOMEMLIMIT=640MiB`. `envoy` and `ext-proc`: none. | `atenet-egress.yaml` L1248, L1279–1353, L1369, L1447 |
| `atelet` DaemonSet | 1 per node | `atelet`: 128Mi, 50m, no limit | `atelet.yaml` L308–311 |
| | | `objectstore-plugin` sidecar: 128Mi, 50m, no limit | `atelet.yaml` L181–217 |
| `ate-api-server` | 2 | `ateapi` and `objectstore-plugin`: none | `ate-api-server.yaml` L65, L92–177 |
| `ate-idp-server` | 2 | none | `ate-idp-server.yaml` L30 |
| `ate-controller` | 1 | none | `ate-controller.yaml` L92 |
| `atenet-router` | 1 | `atenet` and `envoy`: none | `atenet-router.yaml` L181, L202, L318 |
| `podcertificate-controller` | 1 | none | `pod-certificate-controller.yaml` L138–149 |
| kind: `rustfs` | 1 | none | `kind/rustfs.yaml` L50–66 |
| kind: `opentelemetry-collector`, `jaeger` | 1 each | none | `kind/otel-collector.yaml` L165–180, L234–245 |
| kind: `prometheus` | 1 | 128Mi / 512Mi, 100m | `kind/prometheus.yaml` L199–203 |
| Counter demo `WorkerPool` | 3 | 1Gi / 1Gi, 250m / 1 CPU each | `demos/counter/counter.yaml.tmpl` L39, L57–63 |

Totals for variant C [inference, sum of the rows above]:

- Memory requests without workers and without kind Prometheus: 1024 + 32 + 512 + 128 + 128 = **1824 MiB (about 1.78 GiB)**.
- CPU requests: 560m with the kind PostgreSQL overlay, or 2310m with the base manifest.
- About 14 pods and about 19 containers before workers. Ten or more containers have no request, so their actual RSS is UNVERIFIED. Measure it with `kubectl top pod -n ate-system`.
- The counter demo pool adds 3 GiB of requests. On a small node, set `replicas: 1`.

Prerequisites on k3s:

- Substrate needs `ClusterTrustBundle`, `ClusterTrustBundleProjection` and `PodCertificateRequest`. The kind script turns them on (`hack/create-kind-cluster.sh` L105–111). [src] All three are GA and on by default in 1.37. [doc] The note [agent-substrate.md](agent-substrate.md) quotes a Substrate comment that says they are off by default as of 1.36. Check the cluster with `kubectl api-resources`.
- The kind profile needs Docker and a `kind-registry:5000` replacement (`config/kindcheck.go` L30–38, `kind/atelet/kustomization.yaml` L34). [src] k3s needs its own overlay with the rustfs S3 settings. [inference]

### Totals per variant, above the k3s baseline (about 1.6 GB) and the OS

| Variant | Requested memory | Actual idle RSS |
| :--- | :--- | :--- |
| A | 0 | 0 |
| B | 0 (+1 GiB with router) | controller, UNVERIFIED, probably below 128 MiB [inference] |
| C | about 1.78 GiB + workers | UNVERIFIED. Probably about 0.8 to 1.5 GiB for about 19 containers [inference] |

## 2. Per-agent cost

### runc and gVisor overhead [src]

The gVisor doc, `g3doc/architecture_guide/performance.md` L80–105, describes the method. It runs 50 containers (5 for redis). It measures host available memory before and after, and divides the difference by the count. The Sentry memory has "a fixed component, plus an amount that varies with the usage of operating system resources". Data from `website/performance/density.csv` L2–9:

| App | runc | runsc | Difference |
| :--- | :--- | :--- | :--- |
| `sleep` (empty) | 4.09 MB | 23.70 MB | +19.6 MB |
| `node` | 76.7 MB | 124.1 MB | +47.4 MB |
| `ruby` | 45.7 MB | 106.1 MB | +60.4 MB |

These are Docker containers. A Kubernetes runc pod also has a pause container and a shim. Their exact size is UNVERIFIED. Use the 4 MB figure as an approximation. [inference]

The Kubernetes Pod Overhead example uses `podFixed` 120Mi and 250m for a Kata RuntimeClass (`pod-overhead.md` L46–53). It does not give a figure for gVisor. [doc]

### Variant B: suspend [src]

`spec.operatingMode: Suspended` terminates the Pod and keeps the Sandbox object and its volumes (`api/v1beta1/sandbox_types.go` L253–257). An idle Sandbox can thus free its memory. Resume is a new Pod start without a memory snapshot. [inference]

### Variant C: RUNNING and SUSPENDED

- **RUNNING:**
  - `memoryBytes` sets the sandbox cgroup limit and the memory that the Sentry reports (`docs/reference/sandbox-classes.md` L36–38). [doc]
  - The Sentry is inside the actor's cgroup (`cmd/ateworker-gvisor/memory.go` L32–35). [src] Thus the gVisor overhead counts inside the actor limit.
  - The gVisor class has no separate per-actor overhead. Only the microVM class reports `ActorOverhead`. [src] [inference]
- **Worker reserve:** `memoryReservedBytes = 32<<20 + 2*16<<20` = **64 MiB for each worker** (`memory.go` L27–35). [src]
- **Worker capacity:** capacity is a shared budget. Each actor subtracts its limits from it (`docs/reference/api-guide.md` L88–95). [doc] The default `--max-actors` is 1000 (`cmd/ateworker-gvisor/main.go` L110). [src]
- **Running actors per worker:** (worker limit − 64 MiB) / actor `memoryBytes`. Example: a 1 GiB worker with 64 MiB actors holds 15 running actors. [inference]
- **SUSPENDED:**
  - "The Actor is checkpointed on its Worker, which is then freed" (`docs/reference/glossary.md` L112–119). [doc]
  - The snapshot files stay on the node, under `/var/lib/ate/snapshots` (`docs/guides/node-storage.md` L18). They also go to object storage. [doc]
  - The local copy stays until `--snapshot-detach-delay` (`docs/concepts/architecture.md` L78–81). [doc]
  - Thus a suspended actor uses **no worker RAM**. It uses disk on the node and in rustfs or MinIO, plus a PostgreSQL row. [inference]

### Minimum actor memory

- gVisor: "None enforced by worker". microVM: 128 MiB (`sandbox-classes.md` L23). [doc]
- `ApplyToOCISpec` sets no minimum value (`internal/sizing/sizing.go` L91–97). [src]
- Counter demo values:
  - The ActorTemplate sets `memoryBytes: 536870912` (512Mi) and `cpuMillicores: 1000`. The comment says "an actor occupies its whole worker" (`demos/counter/counter-template.yaml.tmpl` L47–52). [src]
  - The comment describes this demo's sizing choice, not a platform rule. The API guide says that workers share capacity. [inference]
  - `preferredFidelity: SNAPSHOT_FIDELITY_MEMORY` (L53–59). [src]
- A sample `ate-demo-counter` gVisor record shows usage 39,845,888 B (38 MiB), working set 30 MiB and peak 50 MiB (`docs/guides/observability.md` L247–255). [doc] It can be an illustrative sample.
- Locust default is `ACTOR_MEMORY="256Mi"` (`benchmarking/workloads/deploy.sh` L57). [src]
- `personal-assistant-light` uses "about 40 to 95 MB per pause under gVisor". It "fits a 256Mi actor" (`docs/guides/benchmarking.md` L519–525). [doc]
- The 1Gi value in the agent-session test comes from its script needs: "~320Mi" peak, and 512Mi gives OOM (`benchmarking.md` L364–370). It is not a platform minimum. [doc]
- Verdict: 64 MiB is plausible for a tiny echo or counter. 32 MiB is below the observed peak of the sample counter. [inference]
- `/tmp` is a tmpfs that holds at most half of `memoryBytes`. Files in it count against the limit (`sandbox-classes.md` L52). [doc]

## 3. Small-cluster profile and optional components

- Only `size0` and `size10` exist. "size0 is the shipped footprint". `size10` is for a dedicated PostgreSQL node (`cmd/ate-setup/internal/config/config.go` L49–53, `cmd/ate-setup/commands.md` L25). [src]
- The `size10` patch sets `shared_buffers = 35GB` for a 140 GiB container (`postgres-size10/postgres-config-patch.yaml` L37–41). [src]
- The base `postgresql.conf` sets no memory parameters. PostgreSQL thus uses its compiled-in defaults (`postgres/postgres.yaml` L21–27). [src]
- The kind overlay reduces only the PostgreSQL CPU and PVC. The 1Gi memory request stays (`kind/postgres/kustomization.yaml` L35–48). [src]
- `deploy ate-system` always applies `atenet-egress`. It waits for `ate-api-server`, `ate-idp-server`, `ate-controller`, `atenet-router`, `atenet-egress` and `atelet` (`steps/deploy.go` L173–206). [src] No flag skips egress or idp. [inference]
- `--credential-provider '{"enabled":false}'` turns off credential injection only. It does not remove the egress gateway (`commands.md` L32). [doc]
- OTel: `OTEL_*_EXPORTER=none` stops the push (`observability.md` L410). [doc] The collector, Jaeger and Prometheus come from the kind profile only (`kind/kustomization.yaml`). [src]
- You can patch these values yourself [inference]:
  - Set `ate-api-server` and `ate-idp-server` replicas to 1.
  - Lower the PostgreSQL memory request to about 256Mi. This changes only scheduling, not the actual RSS.
  - Lower the `sdsmint` request. The manifest comment warns that the request is "measured steady state" at 10,000 secrets (`atenet-egress.yaml` L1329–1337).

## 4. API server load metrics on k3s

- **Metrics on k3s (all from one registry)** [doc]:
  - "K3s runs all Kubernetes components in the main K3s process". k3s uses "a single Prometheus metric registry per process" (k3s metrics page). Thus `kubectl get --raw /metrics` returns metrics from the API server, kubelet, scheduler and controller-manager in one response. [doc] [inference]
  - `supervisor-metrics: true` also exposes them on port 6443 of each node. [doc]
  - Kine metrics are on the regular `/metrics` since PR #12831, backported in September 2025. The k3s 1.35 blog says that the embedded kine metrics are on. [doc]
  - RBAC needs `get` on the non-resource URL `/metrics` (`system-metrics.md` L52–53). The k3s admin kubeconfig has it. [doc] [inference]
- **Metrics to use** (Kubernetes v1.37 reference, `metrics.md`) [doc]:

| Metric | Stability | Use | Line |
| :--- | :--- | :--- | :--- |
| `apiserver_request_total` | stable | Request rate by verb and resource. Take the difference between two scrapes. | L63 |
| `apiserver_resource_objects` | alpha | Object count by resource | L1568 |
| `apiserver_storage_objects` | stable, deprecated in 1.34 | Same data. It is still present. | L84–89 |
| `apiserver_longrunning_requests` | stable | Open watches: `{verb="WATCH"}` | L49 |
| `apiserver_watch_events_total` | beta | Watch event fan-out | L420 |
| `apiserver_current_inflight_requests` | stable | Concurrency | — |
| `etcd_request_duration_seconds` | alpha | Storage latency through kine | L2135 |

- **Not in v1.37:** `apiserver_registered_watchers` is not in the v1.37 list. [doc]
- **Per-client attribution:** `apiserver_request_total` has no user label. Scrape `rest_client_requests_total` from each controller's own `/metrics` endpoint instead [inference]:
  - agent-sandbox controller on `:8080`.
  - Substrate `ateapi`, `atelet` and `atenet-router` on `:9090` (`observability.md` L410).
- **Object count is deterministic** [inference]:
  - A: StatefulSet, ControllerRevision, Pod, Service, EndpointSlice (and Endpoints), PVC, PV. That is about 7 or 8 objects per agent.
  - B: Sandbox, Pod, optional headless Service (`controllers/sandbox_controller.go` L1472–1500), EndpointSlice, PVC, PV. Add a SandboxClaim with a warm pool. That is about 3 to 7 objects per agent. Warm-pool pods add more.
  - C: 0 objects per actor. Actors, workers and templates live in PostgreSQL (`docs/reference/kubectl-ate.md` L105). Only worker pods and the 3 CRD kinds are in the Kubernetes API.
- **Watches** come from informers. Their number is mostly fixed for each variant and does not grow with agents. [inference]

## 5. Cold-start measurement

- **SLI definition:** the pod startup SLI is measured from pod creation to "all its containers are reported as started and observed via watch". It excludes image pulls and init containers (`sig-scalability/slos/pod_startup_latency.md` L7). [doc]
- **Kubelet metrics (alpha):** `kubelet_pod_start_sli_duration_seconds` (L2919) and `kubelet_pod_start_total_duration_seconds` (L2926). [doc] On k3s these are in the same `/metrics` scrape. [inference]
- **kube-burner `podLatency`** reports `PodScheduled`, `PodReadyToStartContainers`, `Initialized`, `ContainersReady` and `Ready` in ms, with quantiles (`docs/measurements/index.md` L36–115, v2.8.7). [doc] It is one binary and can run outside the node. [inference]
- **clusterloader2:** agent-sandbox's load test uses `PodStartupLatency`. It warns: "this only measures the downstream Pod latency, not the end-to-end Sandbox lifecycle" (`dev/load-test/agent-sandbox-load-test.yaml` L14–20). [src]
- **Variant B controller metrics** (`internal/metrics/metrics.go`) [src]:
  - `agent_sandbox_creation_latency_ms` measures from creation to first Ready. It has `launch_type` warm or cold, and second-level precision (L146–150).
  - `agent_sandbox_claim_startup_latency_ms` and `agent_sandbox_claim_controller_startup_latency_ms` measure warm and cold claims (L89–111).
- **Variant C** [doc]:
  - Spawn benchmark: `ActorTimeToReady` measures from the first `CreateActor` to the first successful ping. It also gives `TimeToReady_<k>pct`, `TimeToAllReady` and `--total-actors` (default 100) (`benchmarking.md` L561–590).
  - ResumePaused: `ResumeActorCold` (L644–647). This test "runs on the fake data plane", so it is not an end-to-end restore (L608–610).
  - Server-side metrics: `ate.actor.lifecycle.operation.duration` (ateapi) and `ate.actor.restore.duration` (atelet) (`docs/metrics/registry/metrics.yaml` L914–931, L1021–1031).
- **Definitions differ between variants.** Cold start for A and B means a Pod start. A warm start for B means claim adoption of a warm pod. A cold start for C means a snapshot restore of a suspended actor. Report them as separate rows. [inference]

## 6. Verdict and low-memory mode

### Scale at which differences show [inference]

Assumptions:

- About 0.5 GiB for the OS and 1.6 GiB for k3s.
- A tiny agent with about 10 MiB RSS.
- A costs about 15 MiB per agent. B costs about 30 to 60 MiB.
- C books about 64 MiB while running and uses about 0 MiB when suspended.
- The memory noise floor is about ±100 MiB.

| Metric | 8 GiB | 16 GiB | 32 GiB |
| :--- | :--- | :--- | :--- |
| Free for agents | about 5.9 GiB | about 13.9 GiB | about 29.9 GiB |
| Limit for A and B | `maxPods` 110 minus system pods. Memory is not the limit. | same | same |
| Density (MiB per agent) | Clear at 20 agents. The B−A gap is about 400 MiB. C idle is flat. | same | same |
| Memory pressure | Only with bigger agents (256Mi or more), or with C running actors in a 1 to 2 GiB pool | Needs `--kubelet-arg=max-pods=250` or more | Needs `max-pods` 500 or more |
| C break-even against B (idle) | about 20 to 40 agents (C fixed overhead divided by B per-agent cost) | same | same |
| API objects | Show at 1 agent | same | same |
| Cold start p50 / p99 | 20 / about 100 samples, by repetition | same | same |

- **8 GiB fits variant C, but with little room.** About 1.8 GiB of requests, plus 1 worker at 1 GiB, plus Locust at 768 MiB, gives about 3.6 GiB of requests. k3s uses about 1.6 GiB of actual memory on top of that.
- **Run one variant at a time.**

### Low-memory mode [inference unless tagged]

1. **k3s:** start it with `--disable=traefik,servicelb`. [doc] Keep `local-storage` and `metrics-server`.
2. **One variant at a time:**
   - Delete the namespaces, the PVCs and the CRDs.
   - Wait until `MemAvailable` comes back to the baseline before the next run.
3. **One agent image for all variants:**
   - Use a small static Go HTTP echo or counter with a `/readyz` endpoint. Substrate's `wakeupProbe` uses `/readyz` (counter template L39–42). [src]
   - Pin the same gVisor release in B and C. C uses `20261102.0` from `sandboxconfig-gvisor.yaml` L54–60. [src]
   - k3s does not detect runsc automatically. [doc] For B, add a runsc handler to the containerd config template and create a RuntimeClass.
4. **Variant C settings:**
   - ActorTemplate: `memoryBytes` 64Mi, MEMORY fidelity.
   - WorkerPool: 1 replica with a 1 GiB limit. That allows 15 running actors.
   - `OTEL_*_EXPORTER=none`, no Jaeger or Prometheus, and 1 replica for api-server and idp.
   - Create 50 actors and suspend 50. Compare node `MemAvailable` with B at 50 running Sandboxes.
5. **Variant B settings:** a `SandboxWarmPool` of 2 to 5 replicas, because warm pods use full memory. No router.
6. **Harness:**
   - kube-burner `podLatency` for A and B, run from outside the node.
   - For C, Substrate's Locust needs 512Mi (master) and 256Mi (`boomer-worker`) of requests (`benchmarking/locust/manifests/locust.yaml` L84–86, L163–165). [src] On a small node, use a `kubectl ate create`/`resume`/`suspend` loop from the host instead (`kubectl-ate.md` L202–217). [doc] Read the server-side histograms from `/metrics`.
7. **Memory method:** use the same method as gVisor. Compare node `MemAvailable` before and after N agents, and divide by N. [doc] Also record `kubectl top pod` for each control-plane pod.

## Sources

- Agent Substrate `8368e76`: `manifests/ate-install/{postgres/postgres.yaml, kind/postgres/kustomization.yaml, postgres-size10/postgres-config-patch.yaml, atenet-egress.yaml, atelet.yaml, ate-api-server.yaml, ate-idp-server.yaml, ate-controller.yaml, atenet-router.yaml, pod-certificate-controller.yaml, kind/*.yaml, ate-otel-config.yaml, sandboxconfig-gvisor.yaml}`, `cmd/ate-setup/{commands.md, README.md, internal/config/config.go, internal/config/kindcheck.go, internal/steps/deploy.go}`, `cmd/ateworker-gvisor/{memory.go, main.go}`, `internal/sizing/sizing.go`, `demos/counter/*`, `benchmarking/{deploy_locust.sh, workloads/deploy.sh, locust/manifests/locust.yaml}`, `docs/{guides/benchmarking.md, guides/observability.md, guides/node-storage.md, reference/sandbox-classes.md, reference/api-guide.md, reference/glossary.md, reference/kubectl-ate.md, concepts/architecture.md, metrics/registry/metrics.yaml}`, `hack/create-kind-cluster.sh`. https://github.com/agent-substrate/substrate/tree/8368e765b5ede1f601cde3d8f03fd920eda0e481
- agent-sandbox `v1.0.12`: `k8s/controller.yaml`, `helm/values.yaml`, `clients/python/agentic-sandbox-client/sandbox-router/sandbox_router.yaml`, `api/v1beta1/sandbox_types.go`, `controllers/sandbox_controller.go`, `internal/metrics/metrics.go`, `dev/load-test/agent-sandbox-load-test.yaml`. https://github.com/kubernetes-sigs/agent-sandbox/tree/v1.0.12
- gVisor `168b84e`: `g3doc/architecture_guide/performance.md`, `website/performance/density.csv`. https://github.com/google/gvisor
- k3s docs: https://docs.k3s.io/installation/requirements, https://docs.k3s.io/reference/resource-profiling, https://docs.k3s.io/reference/metrics, https://docs.k3s.io/datastore, https://docs.k3s.io/installation/packaged-components, https://docs.k3s.io/advanced
- k3s kine metrics: https://github.com/k3s-io/k3s/pull/12831, https://github.com/k3s-io/k3s/issues/12595, https://docs.k3s.io/blog/2026/01/15/K3s-1.35-release
- Kubernetes: https://kubernetes.io/docs/reference/instrumentation/metrics/ (source `content/en/docs/reference/instrumentation/metrics.md`), https://kubernetes.io/docs/concepts/cluster-administration/system-metrics/, https://kubernetes.io/docs/concepts/scheduling-eviction/pod-overhead/, https://kubernetes.io/docs/reference/config-api/kubelet-config.v1beta1/ (`maxPods` default 110), feature-gate pages for `PodCertificateRequest`, `ClusterTrustBundle` and `ClusterTrustBundleProjection`.
- https://github.com/kubernetes/community/blob/master/sig-scalability/slos/pod_startup_latency.md
- kube-burner `v2.8.7` `docs/measurements/index.md`: https://github.com/kube-burner/kube-burner
