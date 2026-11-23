# Handoff: agent-sandbox vs Agent Substrate on one k3s node (plan done, nothing built)

Written on 2026-11-23. The index of all handoff documents is `docs/handoff.md`.

## State of the work

- The research is done. The owner has not approved the plan yet. Nothing is built, and the cluster has not changed.
- Branch `agent-k8s-bench-handoff` holds the three research notes and this document. No PR exists.
- The plan below is the last version that the owner reviewed. The owner asked for this handoff in place of an approval. Show the plan again and get approval before step 1 of "Steps".

## The goal

The owner is new to agent platforms on Kubernetes. The owner wants to know what `kubernetes-sigs/agent-sandbox` and Agent Substrate each add, and which one to use when. Numbers from the owner's own k3s node must support each answer. The final output is a "what to use when" table in the README of a new project.

## Research notes

Read these before you change the plan. Each claim in them has a source.

- [`docs/research/agent-substrate.md`](../research/agent-substrate.md): what Agent Substrate is, its components, the plain-Kubernetes issues it solves and what stays unsolved, and its benchmark harness.
- [`docs/research/kubernetes-agent-sandbox.md`](../research/kubernetes-agent-sandbox.md): the four agent-sandbox CRDs, what they add, gVisor on k3s, metrics, published numbers, a starter glossary, and the relationship to Substrate.
- [`docs/research/agent-benchmark-low-memory.md`](../research/agent-benchmark-low-memory.md): the fixed and per-agent memory of each stack, and the k3s metrics for API server load. It also says how to measure start latency, and the minimum agent count for clear numbers.

## Decisions of the owner

Do not offer the rejected options again without a new reason.

| Topic | Path of the decision | Final choice |
|---|---|---|
| Project form | New project, part 4 of mcp-sandbox, or a throwaway spike | New project in `code/` with Flux GitOps, same pattern as `code/ephemeral-env` |
| Variants | Two (plain vs Substrate), then three (plain, agent-sandbox, Substrate) | Two: agent-sandbox and Agent Substrate. No plain-Kubernetes benchmark. |
| Cluster | Suspend mcp-sandbox during runs, or a clean cluster | A clean cluster. Remove the mcp-sandbox stack and install a fresh k3s for this project. |
| Scale goal | Density + start latency, churn, or both | Density + start latency + API server load |
| Host runtime | KVM or no KVM | No KVM. gVisor (`systrap`) for both variants. No microVM class. |
| Wording | The owner rejected text that says a k3s install path is undocumented | Do not write or say that in the plan, the README or the project docs |

## Facts about the host

- Node name `omarchy`, k3s `v1.37.1+k3s1`.
- `kubectl top node` on 2026-11-23: CPU 1226m (6 %), memory 6195 Mi (45 %). So the node has about 13.4 GiB RAM and about 20 cores. This was with mcp-sandbox running.
- The agent sandbox cannot reach the k3s API (no kubeconfig). The owner runs every cluster command on the host.

## Open points

1. The owner must approve the plan below.
2. Step 3 destroys the current k3s and all mcp-sandbox data. Ask the owner again before that step.
3. Two source conflicts stay open. Step 3 and the Substrate docs settle them. See "Facts that shape the benchmark" in the plan.

## Next step

Show the plan to the owner. After approval, start at step 1. The research notes are already saved, so step 1 only needs the lint check.

---

# The plan (last reviewed version)

## Context

The owner read posts about Agent Substrate and agent-sandbox for AI agents on Kubernetes. The owner wants two answers:

1. What does each project add for agent workloads, and how does each fit on a cluster?
2. Which one to use when? Numbers measured on the owner's own k3s node must support each answer.

## Short form of the research

**The two projects are peers, not layers.** agent-sandbox is not the foundation of Substrate. A design doc in the agent-sandbox repo (`examples/multi-cluster-fleet/ARCHITECTURE.md`) calls Substrate "a peer OSS project. Not a layer above or below agent-sandbox".

| Point | Sandbox (agent-sandbox v1.0.12) | Substrate (Agent Substrate v1.0.1) |
|---|---|---|
| Owner | SIG Apps subproject | `agent-substrate` org, Google + Solo, CNCF Sandbox |
| Unit | `Sandbox` CR = 1 Pod | Many actors on 1 worker Pod |
| Agent state | Kubernetes API (~10 KB per Sandbox in etcd) | Own API server + PostgreSQL. 0 Kubernetes objects per actor. |
| CRDs | `Sandbox`, `SandboxTemplate`, `SandboxWarmPool`, `SandboxClaim` | `WorkerPool`, `SandboxConfig`, `CSIDriverConfig` |
| Isolation | Host gVisor through `RuntimeClass` | Downloads `runsc` and runs it in a privileged worker Pod |
| Idle agent | `Suspended`: Pod deleted, PVC kept, memory lost | Memory snapshot to node disk + S3, worker freed |
| Warm start | `SandboxWarmPool` + `SandboxClaim` | Warm `WorkerPool` + golden snapshot |
| Fixed overhead (requests) | 0 (the controller has no requests). Router: +1 GiB, skip it. | ~1.78 GiB (PostgreSQL 1 GiB, egress `sdsmint` 512 MiB, atelet 256 MiB) |
| Per agent (tiny app) | ~24 MB gVisor overhead (runsc `sleep`) + the app | 64 MiB booked while running (counter actor peaks ~50 MiB). ~0 RAM while suspended. Plus 64 MiB per worker. |
| Main costs | Object count grows with agents. Auto suspend and scale to zero are "Planned". | Privileged workers, PostgreSQL is the limit, no GPU, HTTP only on non-default ports |

**Vendor claims:** Substrate: resume < 500 ms, 10x density (no method published). agent-sandbox: warm claim p90 ≤ 200 ms at ~300/s (method published, GKE/kops scale).

**Facts that shape the benchmark:**

- k3s puts all components in one process. One `kubectl get --raw /metrics` call gives API server, kubelet and kine metrics.
- The kubelet `maxPods` default is 110. Sandbox uses one Pod per agent, so the run sets `max-pods` to 250 for N = 200.
- API object count shows at 1 agent. The memory slope shows at 20 agents. A p99 latency needs ~100 samples. Get the samples by repetition.
- "Start" means different things. Sandbox cold: a new Pod. Sandbox warm: a claim takes a running Pod. Sandbox resume: a new Pod for a suspended Sandbox, with its PVC. Substrate create: a new actor from the golden snapshot. Substrate resume: a restore of a suspended actor. The table reports each one as its own row.
- Source conflict: one note says that the Substrate certificate APIs (`ClusterTrustBundle`, `ClusterTrustBundleProjection`, `PodCertificateRequest`) are off by default. The other note says that they are GA in 1.37. Step 3 checks this on the cluster.
- Source conflict: the agent-sandbox doc says that Substrate stores actors in Redis. Substrate's own v1.0.1 docs say PostgreSQL. The plan uses Substrate's own docs.

## Approach

1. One shared agent image for both variants. First try `registry.k8s.io/e2e-test-images/agnhost` (`netexec`). Build a tiny Go HTTP server only if Substrate needs a probe path that agnhost does not serve.
2. One variant runs at a time. The node keeps only k3s, Flux and the variant under test.
3. Flux owns the platform: the gVisor `RuntimeClass` and the agent-sandbox controller. Just recipes run the benchmarks, because a benchmark is an action, not a desired state.
4. Substrate installs with its own `ate-setup` tool from a just recipe, because `ate-setup` generates config and waits for each part in order. TODO: check if the rendered `ate-setup` output can go into the Flux artifact. The check: `flux diff` of the rendered output shows no drift after one reconcile.
5. Memory method from gVisor's own docs: read node `MemAvailable` before and after N agents, then divide by N. Also record `kubectl top pod` for each control-plane pod.

## Project layout (new: `code/agent-k8s-bench/`)

```
code/agent-k8s-bench/
├── README.md                 # what each project is, the results table, "what to use when"
├── justfile                  # publish (Flux artifact), bench-sandbox, bench-substrate, collect
├── clusters/k3s/
│   ├── justfile              # create, up, destroy (from ephemeral-env and mcp-sandbox, reduced)
│   ├── k3s-config.yaml       # disable traefik + servicelb, max-pods 250, feature gates if step 3 needs them
│   ├── containerd-runsc.toml.tmpl   # k3s config-v3.toml.tmpl with the runsc runtime
│   └── flux-instance.yaml    # FluxInstance, OCI sync of ./platform
├── platform/                 # the Flux artifact
│   ├── kustomization.yaml
│   ├── runtimeclass-gvisor.yaml
│   └── agent-sandbox/        # v1.0.12 release manifests, SandboxTemplate, SandboxWarmPool
├── bench/
│   ├── sandbox/              # kube-burner config + SandboxClaim template
│   ├── substrate/            # ate-setup values, ActorTemplate, WorkerPool, kubectl-ate loop script
│   └── collect.py            # scrape /metrics before/after, compute per-agent deltas, write CSV
└── results/                  # one CSV per run, checked in
```

Reuse these existing files and do not write new versions of them:

- `code/ephemeral-env/clusters/k3s/justfile`: `up` (Flux Operator Helm install, `ghcr-pull` Secret, FluxInstance apply) and `_host`.
- `code/ephemeral-env/clusters/k3s/flux-instance.yaml`: the FluxInstance with OCI sync.
- The `publish` recipe in `code/ephemeral-env/justfile` (OCI artifact push).
- `code/mcp-sandbox/part-3-mcp-guardrails/clusters/k3s/justfile`: `create` (k3s install from a config file) and `destroy`.

## Steps

Each step ends with a check. Do not start the next step before the check passes.

1. **Save the research.** Write three notes in `docs/research/`: `agent-substrate.md`, `kubernetes-agent-sandbox.md` and `agent-benchmark-low-memory.md`. The text is the output of the background agents. Run `scripts/ste-lint.py` on each note.
   - Check: the linter has 0 hard findings, and each note has a Sources section.
2. **Create the worktree.** Run `herdr worktree create --branch agent-k8s-bench --label agent-k8s-bench`. Read `docs/agents/pull-requests.md`, `docs/agents/python.md`, `docs/agents/diagrams.md` and `docs/agents/project-docs.md` before the first commit.
   - Check: `git branch --show-current` prints `agent-k8s-bench`.
3. **Prepare a fresh cluster (host, the owner runs it).**
   1. Run `just clusters/k3s/destroy` in mcp-sandbox. This removes all mcp-sandbox workloads and data. The owner confirms again before this step.
   2. Install `runsc` and `containerd-shim-runsc-v1` on the host. Pin the gVisor release that Substrate uses (`20261102.0`), so both variants run the same gVisor.
   3. Set `net.ipv4.conf.all.proxy_arp=1` on the host (Substrate needs it for gVisor networking).
   4. Run `just clusters/k3s/create` in the new project.
   5. Record `free -m` and `nproc`.
   - Check: the node is `Ready`. `kubectl api-resources | grep -iE 'podcertificaterequest|clustertrustbundle'` shows both kinds. If not, add the gates to `k3s-config.yaml` and install again.
   - Check: a test Pod with `runtimeClassName: gvisor` runs, and `dmesg` in the Pod shows the gVisor banner.
4. **Hand the cluster to Flux.** Run `just publish`, then `just clusters/k3s/up`. Look up every CRD field with the `flux-schema-catalog` MCP server before you write it.
   - Check: `flux get kustomizations` shows all Ready. `kubectl get crd sandboxes.agents.x-k8s.io` works.
5. **Record the baseline.** With no variant installed, run `collect.py baseline`. It saves `MemAvailable`, object counts per resource, `apiserver_longrunning_requests{verb="WATCH"}` and `apiserver_request_total`.
   - Check: the CSV has one row and no empty column.
6. **Sandbox run.** Use a SandboxTemplate with `runtimeClassName: gvisor` and the shared image. Run kube-burner `podLatency` for N = 1, 20, 50, 100, 200.
   1. Cold: claims with no warm pool.
   2. Warm: a `SandboxWarmPool` of 10, then claims.
   3. Suspend and resume: set `operatingMode: Suspended` on 50 Sandboxes, measure the freed memory, then resume them and measure the time to Ready.
   4. Read `agent_sandbox_creation_latency_ms`, `agent_sandbox_claim_startup_latency_ms` (`launch_type` cold/warm) and `agent_sandbox_resume_latency_ms` from the controller's `:8080/metrics`.
   5. Repeat each start test until there are 100 samples. Delete everything, then wait until `MemAvailable` is back within 100 MiB of the baseline.
   - Check: `results/sandbox-*.csv` has density (MiB/agent), objects/agent, watches, requests/s, and p50/p99 for cold, warm and resume.
7. **Substrate install.**
   1. Confirm that no Sandbox objects or Pods remain.
   2. Deploy `ate-system` with `ate-setup` and an S3 store (rustfs, `ATE_STORAGE_BACKEND=s3`). Set `OTEL_*_EXPORTER=none` and use no Jaeger or Prometheus.
   3. Label the worker namespace with the Pod Security level `privileged`.
   4. Record `kubectl top pod -n ate-system` and the new `MemAvailable`. This is the fixed overhead of Substrate.
   - Check: `kubectl ate create actor` for the counter demo returns, and a request through `atenet-router` gets a reply.
8. **Substrate run.** Use an ActorTemplate with 64 MiB and MEMORY fidelity, and 1 WorkerPool replica with a 1 GiB limit.
   1. Create N = 1, 20, 50, 100, 200 actors. Suspend all of them after each create.
   2. Measure `MemAvailable` for running actors and for suspended actors.
   3. Measure resume latency with a `kubectl ate resume`/`suspend` loop (100 samples). Do not use Locust, because it needs 768 MiB.
   4. Read `ate.actor.lifecycle.operation.duration` and `ate.actor.restore.duration` from `:9090/metrics`.
   - Check: `results/substrate-*.csv` has the same columns as the Sandbox CSV. The objects/agent column must be 0.
9. **Write the README.** Include the comparison table, the measured numbers, a crossover chart (memory vs N for both variants), and the "what to use when" table. Draft rows (the numbers fill them in):

    | Workload shape | Use | Why (number from results/) |
    |---|---|---|
    | A few long-lived sessions, each with its own disk | Sandbox | No fixed overhead. Stable name + PVC. |
    | Bursty sessions where start time matters | Sandbox + warm pool, or Substrate | Sandbox warm claim p50/p99 vs Substrate resume p50/p99 |
    | Many mostly idle agents | Substrate | RAM per suspended actor vs RAM per running Sandbox. Objects per agent: 0 vs measured. |
    | Agent memory must survive idle time | Substrate | Memory snapshot restore. Sandbox suspend loses memory (except on GKE). |
    | Small agent count on a small node | Sandbox | Substrate fixed overhead (measured) is larger than its saving below the crossover N |
    | GPU agents | Sandbox | Substrate does not pass devices to actors (from docs, not measured) |
    | No privileged Pods allowed on nodes | Sandbox | Substrate workers need UID 0, `SYS_ADMIN`, Unconfined seccomp (from docs) |
    | Raw TCP or non-HTTP protocols to the agent | Sandbox | Substrate reaches non-default ports over HTTP(S) only (from docs) |

    - Check: every number in the README comes from a CSV in `results/`. Run `/asd-ste100` and the linter on the README. Read `docs/agents/diagrams.md` before the chart.
10. **Commit and open a PR** to `main` from the branch, per `docs/agents/pull-requests.md`. Never push to `main`.

## Verification (end to end)

- Each variant has CSVs in `results/` with the same columns: `variant, n, state, mem_per_agent_mib, objects_per_agent, watches, requests_per_s, start_kind, start_p50_ms, start_p99_ms`.
- The baseline check passes before and after each variant (`MemAvailable` within 100 MiB). This proves that one variant did not leak into the next.
- Run the API object count twice for each variant. It is deterministic, so both runs must give the same value.
- `flux get all -A` shows no failed object at the end.
- `just bench-sandbox` and `just bench-substrate` run again from a clean cluster. Their numbers are within 10 % of the checked-in CSVs.

## Risks

- **Destroying the current k3s deletes all mcp-sandbox data.** Its config stays in Git. The Bitwarden and ghcr secrets come back with its `up` recipe.
- **The idle RSS of Substrate and of the agent-sandbox controller is not published.** Step 7 measures it. With ~13.4 GiB RAM, the ~1.78 GiB of Substrate requests fits.
- **Flux overhead** (~200–300 MiB) is the same for both variants, so it does not change the per-agent slopes.
- **Scope.** One node cannot show the "millions of agents" claims. The project shows the slopes and the crossover point, and says that.
