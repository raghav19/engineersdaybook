# Handoff: agent-sandbox part 1 on k3s, state, memory, warm start and cold start (research done, plan not approved, nothing built)

Written on 2026-11-24. The index of all handoff documents is `docs/handoff.md`. This document continues [`agent-k8s-bench-2026-11-23.md`](agent-k8s-bench-2026-11-23.md).

## State of the work

- The research is done. The owner has not approved the plan below. Nothing is built, and the cluster has not changed.
- Branch `agent-sandbox-part1-handoff` holds this document, the new section 7 of the research note and the index entry. No PR exists.
- Show the plan to the owner and get approval before step 1 of "Steps". Ask the owner again before step 3 (it destroys the current k3s).

## The goal

The owner wants to start with `kubernetes-sigs/agent-sandbox` only. The owner wants to know:

1. Where does agent-sandbox keep state and memory?
2. How do warm start, cold start and resume work?

Labs on the owner's own k3s node must prove each answer. The Sandbox half of the benchmark from the earlier handoff then gives the numbers. Agent Substrate is part 2.

## Research notes

Read these before you change the plan.

- [`docs/research/kubernetes-agent-sandbox.md`](../research/kubernetes-agent-sandbox.md). Section 7 has the new facts of 2026-11-24, each with a source. It covers suspend and resume, the survival table, memory snapshots, warm and cold paths, metrics, gVisor effects, manifests and SDK calls. It also lists 5 conflicts between docs and source.
- [`docs/research/agent-benchmark-low-memory.md`](../research/agent-benchmark-low-memory.md). Memory and API-load methods.
- [`docs/research/agent-substrate.md`](../research/agent-substrate.md). For part 2 only.

## Decisions of the owner

Do not offer the rejected options again without a new reason. The decisions of the [2026-11-23 handoff](agent-k8s-bench-2026-11-23.md) still apply. They are: Flux GitOps, gVisor `systrap`, no KVM and no plain-Kubernetes variant. Also, do not write that a k3s install path is undocumented.

| Topic | Final choice (2026-11-24) |
|---|---|
| Order | agent-sandbox first. Substrate is part 2. |
| Cluster | A fresh k3s now. Destroy mcp-sandbox. Ask the owner again before the destroy step. The rejected options: keep the cluster and add gVisor, or keep it and suspend mcp-sandbox. |
| Deliverable | Labs plus the Sandbox half of the benchmark (handoff steps 5–6). The rejected options: labs only, or benchmark only. |
| Memory lab | Add the checkpoint labs 04a and 04b. They show what agent-sandbox lacks outside GKE. |

## Facts that shape part 1

- The agent sandbox has no kubeconfig. The agent writes files. The owner runs every cluster and host command. Read `docs/agents/host-handoff.md` before the first request to the owner.
- Host: node `omarchy`, k3s `v1.37.1+k3s1`, about 13.4 GiB RAM and about 20 cores. See the 2026-11-23 handoff.
- The v1.0.12 state model, from the research (section 7):
  - The `Sandbox` object survives everything except deletion of the Sandbox or its claim.
  - A PVC from `volumeClaimTemplates` survives a Pod restart, a suspend and a `Retain` expiry. It is deleted with the Sandbox.
  - `emptyDir`, rootfs writes and process memory are lost on every Pod restart, suspend and expiry.
  - Suspend is a plain Pod delete. The Service and the PVCs stay. The only signal to the agent is normal termination (`preStop`, SIGTERM, grace period).
  - Resume makes a new Pod with the same name from the current `podTemplate`. The IP is new.
  - A warm claim adopts a running pool member, which keeps its `<pool>-xxxxx` name. A cold claim makes a Sandbox with the name of the claim. `env` or `volumeClaimTemplates` in a claim forces a cold start.
  - Memory snapshots exist only on GKE. The `runsc` containerd shim returns "not implemented" for the standard checkpoint call.
- One agent-sandbox example gives about 370 MiB host RSS for each gVisor Pod. The earlier handoff assumed about 24 MB. N = 200 may not fit in 13.4 GiB.

## Open points

1. The owner must approve the plan below.
2. Step 3 destroys the current k3s and all mcp-sandbox data. Ask the owner again before that step.
3. The density conflict (370 MiB against about 24 MB). Step 6 measures it and limits N.
4. Lab 04a (kubelet checkpoint API with `runsc`) is expected to fail. This is an inference, and the lab tests it.
5. UNVERIFIED in the research: that GKE snapshots use `runsc checkpoint`, the first-bind time of a PVC, and any gVisor cold-start number.

## Next step

Show the plan to the owner. After approval, start at step 1.

---

# The plan

## The model that part 1 must prove on the cluster

The facts in "Facts that shape part 1" are from source files. The labs check each one on the cluster. A lab that contradicts a fact goes back into section 7 of the research note.

## Project layout (new: `code/agent-k8s-bench/`)

```
code/agent-k8s-bench/
├── README.md, CONTEXT.md              # part 1 results; glossary per docs/agents/domain.md
├── justfile                           # publish, lab-*, bench-sandbox, collect
├── clusters/k3s/                      # justfile (create/up/destroy), k3s-config.yaml (max-pods 250),
│                                      # containerd config-v3.toml.tmpl (runsc), flux-instance.yaml
├── platform/                          # Flux artifact: runtimeclass-gvisor.yaml, agent-sandbox v1.0.12
│                                      # release YAML, SandboxTemplate (gvisor + 1 PVC), SandboxWarmPool (replicas 0)
├── labs/
│   ├── counter.sh                     # busybox loop: counter in memory, written to /data (PVC) and /tmp each second;
│   │                                  # on SIGTERM writes the memory counter to /data/flushed
│   ├── 01-state/  02-flush/  03-starts/  # Sandbox / Claim manifests for each lab
│   └── 04-checkpoint/                 # kubelet checkpoint call + runsc bundle (config.json) for the host lab
├── bench/sandbox/                     # kube-burner config + SandboxClaim template
├── bench/collect.py                   # scrape /metrics + MemAvailable, write CSV
├── docs/agent-sandbox-state-and-start.md  # topic doc (docs/agents/project-docs.md structure)
└── results/                           # lab outputs (text) and bench CSVs, checked in
```

Reuse these files and do not rewrite them:

- `code/ephemeral-env/clusters/k3s/justfile`: the `up` and `_host` recipes.
- `code/ephemeral-env/clusters/k3s/flux-instance.yaml`.
- The `publish` recipe in `code/ephemeral-env/justfile`.
- The `create` and `destroy` recipes in `code/mcp-sandbox/part-3-mcp-guardrails/clusters/k3s/justfile`, which pin `v1.37.1+k3s1`.

The lab image is `busybox` with `counter.sh` from a ConfigMap, so no image build is needed. The benchmark image is `agnhost`, as in the earlier handoff.

## Steps

Each step ends with a check. Do not start the next step before its check passes.

1. **Save the research.** Done in this branch: section 7 of `docs/research/kubernetes-agent-sandbox.md`.
   - Check: `.agents/skills/asd-ste100/scripts/ste-lint.py` gives 0 hard findings.
2. **Create the worktree.** Run `herdr worktree create --branch agent-k8s-bench --label agent-k8s-bench`. Before the first commit, read `docs/agents/{pull-requests,python,diagrams,project-docs,kubernetes,domain}.md`.
   - Check: `git branch --show-current` prints `agent-k8s-bench`.
3. **Prepare a fresh cluster (the owner runs it on the host).**
   1. Get the confirmation of the owner again.
   2. Run `just clusters/k3s/destroy` in mcp-sandbox.
   3. Install `runsc` and `containerd-shim-runsc-v1` at gVisor `20261102.0`.
   4. Run `just clusters/k3s/create` in the new project.
   5. Record `free -m` and `nproc`.
   - Check: the node is `Ready`. A Pod with `runtimeClassName: gvisor` runs, and `dmesg` in it shows the gVisor banner.
   - Leave `proxy_arp` and the certificate-API check for part 2.
4. **Hand the cluster to Flux.** Run `just publish`, then `just clusters/k3s/up`. Look up every field with the `flux-schema-catalog` MCP server before you write it.
   - Check: `flux get kustomizations` shows all Ready. `kubectl get crd sandboxes.agents.x-k8s.io sandboxwarmpools.extensions.agents.x-k8s.io` works.
5. **Labs.** Each lab is a `just lab-NN` recipe. The output goes to `results/lab-NN.txt` and shows the expected result and the observed result.
   1. **Lab 01, where state lives.** Run one Sandbox with a PVC and `counter.sh`. Read `/data`, `/tmp` and the memory counter after each action:
      - delete the Pod, with `failedPodPolicy: Recreate`
      - suspend, then resume
      - a `shutdownTime` expiry with `Retain`
      - delete the Sandbox

      Also record the Pod name, the IP, the PVC UID and the Service before and after each action.
   2. **Lab 02, graceful flush.** Suspend, and check that the SIGTERM handler wrote the memory counter to `/data/flushed`. Resume, and check that the counter starts from it. Then set `terminationGracePeriodSeconds: 1` with a slow handler, and show that the flush is lost. This is the only way to keep memory state on k3s.
   3. **Lab 03, start paths.**
      - Cold: a claim with pool replicas 0.
      - Warm: a pool of 3 Ready, then a claim. Record the name, the labels and the ownerRefs before and after adoption. Watch the refill.
      - Forced cold: a claim with `env`.
      - Resume: as in Lab 01.

      Read `launch_type` and the resume metric from the controller `:8080/metrics`.
   4. **Lab 04a, kubelet checkpoint.** Send `POST /checkpoint/{ns}/{pod}/{container}` to the kubelet for a gVisor Pod. Record the error. The research expects "not implemented". Use the k3s admin certificate from `/var/lib/rancher/k3s/server/tls/`, and do not print it.
   5. **Lab 04b, runsc checkpoint (host, no Kubernetes).** Run the busybox counter with plain `runsc run`. Then run `runsc checkpoint --image-path`, then `runsc restore`. Show that the memory counter continues. Record the image size, the checkpoint time and the restore time. This lab needs root. Run it in a scratch directory.
   - Check: each result file exists. Each fact in "Facts that shape part 1" has a result: true or false.
6. **Sandbox benchmark.** Use steps 5 and 6 of the earlier handoff, with these changes:
   1. Record the baseline (`collect.py baseline`).
   2. Measure the memory per agent at N = 1 and N = 5. Calculate `N_max = (MemAvailable − 2 GiB) / per-agent`.
   3. Run N = 1, 20, 50 and 100, but only the values that are at most `N_max`. Always include `N_max`.
   4. Run cold claims, warm claims (pool of 10), and suspend and resume of `min(50, N_max)` Sandboxes. Repeat each until there are 100 samples.
   5. Delete everything. Wait until `MemAvailable` is within 100 MiB of the baseline.
   - Check: `results/sandbox-*.csv` has the columns `variant, n, state, mem_per_agent_mib, objects_per_agent, watches, requests_per_s, start_kind, start_p50_ms, start_p99_ms`, with no empty value.
7. **Docs.**
   1. Write the topic doc `docs/agent-sandbox-state-and-start.md` with the structure of `docs/agents/project-docs.md`. Add a mermaid `sequenceDiagram` for suspend and resume, warm claim and cold claim, and a "lifetimes" list from Lab 01.
   2. Write the README: what agent-sandbox is, how to run the labs, and the measured table. In "what to use when", fill only the Sandbox rows. The rest waits for part 2.
   3. Write `CONTEXT.md` with the glossary.
   4. Write a handoff for part 2 and add it to `docs/handoff.md`.
   - Check: run `/asd-ste100` and the linter on each doc. A parser accepts each mermaid block. Each number comes from `results/`.
8. **Commit and open a PR** from `agent-k8s-bench` to `main`. Follow `docs/agents/pull-requests.md`. Never push to `main`.

## Verification (end to end)

- Each lab result file marks each fact in "Facts that shape part 1" as true or false.
- `MemAvailable` comes back within 100 MiB of the baseline after the labs and after the benchmark.
- The object count per agent gives the same value in two runs.
- `flux get all -A` shows no failed object.
- From a clean cluster, `just bench-sandbox` gives numbers within 10 % of the checked-in CSVs.

## Risks

- **Step 3 deletes all mcp-sandbox data.** Its config stays in Git. The Bitwarden and ghcr secrets come back with its `up` recipe.
- **The 370 MiB gVisor RSS can be correct.** Then the benchmark covers a smaller N than the earlier handoff planned. The README says so.
- **Lab 04b needs root and plain `runsc` on the host.** The owner runs it.
- **The kubelet checkpoint API needs a client certificate.** Never print the certificate.
- **Scope.** One node cannot show the "millions of agents" claims. The project shows slopes and says that.
