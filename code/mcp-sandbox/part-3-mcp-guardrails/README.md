# Part 3: MCP guardrails with agentgateway on kind

Part 1 showed the attack. Part 2 contained one local MCP server. [agent-sandbox](../../agent-sandbox/README.md) put the agent in a microVM.
This part puts a policy point on the MCP path. Every call to a remote MCP server goes through [agentgateway](https://agentgateway.dev) in a local kind cluster.

## What we are building

### Problem

An agent that calls MCP tools holds real authority. Parts 1 and 2 of this series showed two ways that authority goes wrong. Each fix left a gap.

**Part 1: the model was the only control.** [Part 1](../part-1-lethal-trifecta/README.md) built the "lethal trifecta" on purpose: private data, untrusted content and a way to publish.
It gave a coding agent one fine-grained GitHub token. The token covered a public repo and a private repo.
A planted issue told the agent to copy a private file into a public pull request. The model refused twice.
Nothing else would have stopped the copy. The token scope allowed the read. The injected text entered the agent's context and tried to redirect its plan.
A model's judgment changes with the model and with the wording. You cannot enforce it or audit it.

**Part 2: a sandbox does not govern the calls.** [Part 2](../part-2-sandboxing-local-mcp/README.md) sealed one local MCP server in rootless Docker.
The container has a read-only filesystem, no capabilities and a sealed network. Its only route out is an egress proxy that logs every outbound attempt.
That limits what the server process can reach. It does not limit what the agent asks the server to do. It does not inspect what a result carries back.
The server runs every call it receives.

**The MCP path itself stays open.** Remote servers run outside any sandbox that we own. Four questions on that path have no owner today:

1. Who is calling, and may that user use this server and this tool?
2. What do the arguments of the call contain?
3. What does the result carry back into the agent's context?
4. Which workload is on the other end of each hop, and is there a record of the call?

The [OWASP MCP Top 10](https://owasp.org/www-project-mcp-top-10/) names the risks. Parts 1 and 2 touched some of them. This part maps all ten.

| ID | Risk | What goes wrong on this path |
|---|---|---|
| MCP01 | Token Mismanagement and Secret Exposure | The agent holds a long-lived token, or a secret appears in a call or a result. |
| MCP02 | Privilege Escalation via Scope Creep | One credential reaches more than the task needs, and every call gets the same rights. |
| MCP03 | Tool Poisoning | A server changes a tool description after the user approved it. |
| MCP04 | Software Supply Chain Attacks | An MCP server that you did not write or review runs behind the call. |
| MCP05 | Command Injection and Execution | Arguments carry path traversal, a sensitive file name or a credential. |
| MCP06 | Intent Flow Subversion | Content in a result redirects the plan of the agent. |
| MCP07 | Insufficient Authentication and Authorization | A call arrives with no identity, or with an identity that nobody checks. |
| MCP08 | Lack of Audit and Telemetry | Nobody can tell which user called which tool. |
| MCP09 | Shadow MCP Servers | An agent reaches a server that nobody registered or reviewed. |
| MCP10 | Context Injection and Over-Sharing | Injected text or a secret moves between the server and the model. |

### Solution

- One gateway gives one `/mcp` endpoint for three MCP servers: GitHub, draw.io and the Flux schema catalog.
- The gateway checks each request and each response against policy.
- A user gets access by a merged pull request, then logs in with GitHub through Dex. The gateway accepts only calls with a valid token.
- Each workload has a SPIFFE identity. Traffic in the cluster uses mTLS.
- The gateway holds the upstream credential. The agent never sees it.

The [policies table](#policies-and-what-they-map-to) lists the control for each risk.

![High-level architecture](docs/diagrams/architecture.drawio.svg)

The flows are in [docs/arch.md](docs/arch.md): login, workload identity, mTLS and the guardrails.

## Status

- This is stage A. The manifests, the Flux stack, the cluster folder and the justfiles exist.
- `just <component>/build` renders and checks each component.
- The `clusters/kind/*` recipes and `push` run on the host only. They need the ghcr.io token and your sops key. They refuse to run in the sandbox.
- ext-mcp has rules but no gRPC server yet.
- Stage B chains the sbx gateway to this one and adds Dex. It follows a spike.

## How the repo works

- Each addon, route set, MCP server registration and policy is its own OCI artifact.
- The artifact is the rendered manifest. Charts render at build time. Nothing renders in the cluster.
- `clusters/kind/sync/stack.yaml` pins the artifact each cluster runs. A rollout or a rollback is a Git edit of the pin.
- A baseline run is `stack.yaml` without the policy entries and `ext-mcp-isolation`. Compare it with a run that has every policy.

### Commands

Name the folder to run a recipe, for example `just platform/routes/build`. Run `just` for the list.

| Command | What it does |
|---|---|
| `just <c>/build` | Applies the config values, renders the folder with its charts, checks the schemas, writes `out/<c>/manifests.yaml`. |
| `just <c>/diff` | Prints the change against the artifact that `origin/main` pins. Use `just --set base <rev> <c>/diff` for another revision. |
| `just <c>/push` | Builds, then pushes `ghcr.io/raghav19/mcp-guardrails/<c>:<commit>` (host). |
| `just <c>/pin` | Writes the pushed tag and digest into `stack.yaml`. Commit it in a pull request. |

The push sends only `out/<c>/manifests.yaml`. Git ignores `out/`.

- Every CRD in an artifact carries `kustomize.toolkit.fluxcd.io/prune: disabled`. Flux never deletes a CRD. Delete CRDs with `just clusters/kind/delete-crds`.
- `kustomization.yaml` in a folder is only a build index. A Flux `Kustomization` in `stack.yaml` applies one artifact.
- flate 0.6.5 puts a namespace on some cluster-scoped kinds. `cluster_scoped` in `lib/workflow/workflow.just` lists them and the build deletes it.

### Values

The default of a value is the manifest. `config/` holds only the overrides that differ per cloud, env or region.

| File | Job |
|---|---|
| `<component>/setters.yaml` | Names the fields that `config/` may override (`object: Kind/name` and a dotted `path`). |
| `config/*.yaml` | Overrides that are the same on every cloud. |
| `config/cloud/<cloud>/<env>/<region>/*.yaml` | Overrides for one placement. The build skips a level that does not exist. |
| `clusters/<name>/cluster.yaml` | Says which placement the cluster uses (`cloud/local` for kind). |

- Every build reads `config/` and writes the result to `out/values.yaml`. A lower level wins.
- The build copies the folder, sets the fields from `out/values.yaml` and renders the copy. The source is never edited.
- `trust_domain` and `cluster_name` have no default. The build fails without them.
- The build also fails in three cases:
  - A name that no `setters.yaml` lists.
  - Two names that write one field.
  - A value that is a map or a list.
- Config names are one flat namespace. Prefix them (`gateway_port`, not `port`).
- Keep `clusters/kind/kind-config.yaml` (host port 8080 to NodePort 30080) and the default URL of `tests/justfile` equal to the gateway port by hand.

### Build functions

`config-builder` and `value-injector` are Python scripts in `tools/`. Each one is a pinned binary in its own OCI artifact.

- `config/tools/manifest.yaml` holds the digest and the binary sha256 of each function.
- A build pulls the pinned binary once and checks the sha256. It never runs the script from the working tree.
- After a script edit, run `just tools/<name>/push` on the host. Put the block it prints into `config/tools/manifest.yaml`.
- Roll back with `git revert` of that block.

### Secrets

- The upstream credential is a SOPS-encrypted Secret in `clusters/<name>/sync/secrets`.
- Flux decrypts it with the `sops-age` Secret and applies `github-upstream`.
- The gateway reads it and sets the upstream `Authorization` header. The agent and the sandbox VM never hold it.
- Setup steps are in [`clusters/kind/sync/secrets/README.md`](clusters/kind/sync/secrets/README.md).

## Directory structure

```text
part-3-mcp-guardrails/
├── docs/                 arch.md and diagrams/ (the draw.io diagram)
├── lib/workflow/         shared just recipes: build, diff, push, pin
├── tools/                config-builder and value-injector
├── config/               overrides only, by cloud, env and region
├── platform/
│   ├── addons/           gateway-api, agentgateway, spire, istio, istio-ingress
│   ├── mcp-servers/      the three servers behind /mcp (one AgentgatewayBackend)
│   ├── routes/           Gateway, AgentgatewayParameters, HTTPRoute
│   ├── ext-mcp/          rules.py, tests, Dockerfile, deploy/
│   └── policies/         authn-jwt, tool-rbac, rate-limit, ext-mcp-checks, ext-mcp-isolation, mcp-mtls
├── clusters/kind/        cluster.yaml, kind-config.yaml, justfile, sync/ (stack.yaml, secrets/)
├── tests/                attack cases, one folder per OWASP id
└── out/                  build output, gitignored
```

The artifact names are `gateway-api`, `agentgateway`, `spire`, `istio`, `istio-ingress`, `mcp-servers`, `routes`, `ext-mcp`, `ext-mcp-isolation`, `mcp-mtls`, `authn-jwt`, `rate-limit`, `tool-rbac` and `ext-mcp-checks`.
`secrets` comes from Git and is not an artifact.

## Identity and mesh

- `spire` is the CA of trust domain `mcp.local`. The node agents attest to the server with `k8s_psat`. A join token is on for a microVM agent later.
- A workload gets an SVID only when a `ClusterSPIFFEID` selects it. The chart's default entries are off.
- `istio` runs in sidecar mode only. There is no ambient mode, `istio-cni` or `ztunnel`.
- A namespace takes part with the label `istio-injection: enabled`, the pod annotation `inject.istio.io/templates: sidecar,spire`, a `ClusterSPIFFEID` and its own `PeerAuthentication`.
- Only `mcp-guardrails` takes part today (`ext-mcp`). There is no mesh-wide policy on purpose.
- The `istio-ingress` gateway receives no traffic yet. Host port 30080 still reaches agentgateway.
- `mcp-mtls` (STRICT) needs the client half in agentgateway first. The flows are in [docs/arch.md](docs/arch.md).
- A second cluster is a new `clusters/<name>/` folder with its own `stack.yaml`. Several clusters can pin one artifact.

## Versions

| Item | Pin | Where |
|---|---|---|
| Kubernetes (kind node image) | v1.37.0 (kind 0.33.0 default) | `clusters/kind/kind-config.yaml` |
| Gateway API (standard channel) | v1.6.1 | `platform/addons/gateway-api/kustomization.yaml` |
| agentgateway (CRDs and controller) | v1.6.0. `just build` fails if the two tags differ. | `platform/addons/agentgateway/` |
| SPIRE (CRD chart and spire chart) | spire-crds 0.6.1, spire 0.30.3 (SPIRE 1.15.3) | `platform/addons/spire/` |
| Istio (base, istiod, gateway: one release) | 1.31.1 (Kubernetes 1.32 to 1.37) | `config/versions.yaml` (`istio_version`) |
| Flux (through the Flux Operator) | 2.9.6, operator chart 0.61.0 | `clusters/kind/sync/flux-instance.yaml`, `clusters/kind/justfile` |
| just / flate / kind / helm | 1.58 / 0.6.5 / 0.33.0 / 4.3.0 | root `mise.toml` |
| What a cluster runs | One tag (the commit) and one digest per artifact | `clusters/kind/sync/stack.yaml` |

## Getting started

You need rootless Docker ([`code/rootless-docker`](../../rootless-docker)), `mise install` at the repo root and your age key for `sops`. Steps marked **host** run on your machine.

1. **Look at what a cluster gets (anywhere).** Run `just platform/routes/build`, then `just platform/routes/diff`. The schema catalog needs the network.
2. **Add the secret and the keys (host, once).** Follow [`clusters/kind/sync/secrets/README.md`](clusters/kind/sync/secrets/README.md). Add `GHCR_USER`, `GHCR_PULL_TOKEN` and `GHCR_PUSH_TOKEN` to `.env.secrets.json`.
3. **Push the artifacts (host).** Run `sops exec-env .env.secrets.json 'just platform/routes/push'`, then `just platform/routes/pin`. Commit `stack.yaml`, open the pull request and make the registry packages private.
4. **Create the cluster (host).** Run `just clusters/kind/up`, then `just clusters/kind/credentials`. Watch with `kubectl -n flux-system get kustomizations`.
5. **Check the gateway.** Open `http://127.0.0.1:8080/mcp`. `tools/list` shows `github_*`, `drawio_*` and `flux_*`.
6. **Run the attacks.** Run `just tests/run`. It refuses unless the `kubectl` context is `kind-mcp-guardrails`.
7. **Tear down.** Run `just clusters/kind/down`.

To change a unit, run `just <c>/diff`, edit, then `build`, `push` and `pin`, and open a pull request. Merging makes Flux apply the new pin.
To roll one unit back, run `git revert` on the commit that pinned it.

## Policies and what they map to

Each policy is its own artifact, so one policy rolls out or back alone.

| Control | Folder | OWASP MCP | Test |
|---|---|---|---|
| JWT, strict | `platform/policies/authn-jwt` | MCP01, MCP07 | `MCP07-no-token` |
| Upstream credential held by the gateway | SOPS Secret and `platform/mcp-servers` | MCP01 | inspect: nothing client-side |
| Tool deny list (CEL, target and name) | `platform/policies/tool-rbac` | MCP02 | `MCP02-destructive-tool` |
| Rate limit per `jwt.sub` | `platform/policies/rate-limit` | MCP02, MCP10 | to write |
| Argument and response checks, pinning | `platform/policies/ext-mcp-checks` and `platform/ext-mcp` | MCP03, MCP05, MCP06, MCP10 | `rules.py` unit tests |
| Only the gateway may call ext-mcp | `platform/policies/ext-mcp-isolation` | MCP04, MCP09 | to write |
| Access logs and traces | not wired | MCP08 | to write |

The design reduces MCP04 (supply chain) and MCP06 (intent flow subversion). It does not solve them.

## Known gaps

- **Gateway reachability is not proven.** cloud-provider-kind does not work on rootless Docker with pasta. `kind-config.yaml` maps host `127.0.0.1:8080` to NodePort 30080, set in `platform/routes/parameters.yaml`.
- **ext-mcp has no server.** Argument-level CEL is unreliable in agentgateway ([#3092](https://github.com/agentgateway/agentgateway/issues/3092)), so the argument checks live in ext-mcp.
- **The JWKS is a placeholder.** The default in `platform/policies/authn-jwt/policy.yaml` is empty. Dex replaces it.
- **The upstream token has no test yet.** No run used `GITHUB_TOKEN` against the GitHub MCP server.
- **Four points are not checked against a live controller:**
  - The status conditions of `AgentgatewayPolicy` and `AgentgatewayBackend`, and the `Programmed` gate of `Gateway`.
  - The secret key convention (`Authorization`, raw token).
  - The merge of two policies on one backend.
  - Whether an `OCIRepository` prefers `ref.digest` over `ref.tag`.
- **The first push of `agentgateway` changes its format.** The old pin holds two HelmReleases. The new pin holds the rendered objects. Check this cut-over on a cluster that runs the old pin.
- **A USB device that you unplug while the cluster runs can break new privileged pods.** `kind-config.yaml` sets `privileged_without_host_devices = true`. If it happens, recreate the cluster.
- **There is no CI and no signing.** `push` is a host recipe and the registry is the trust root. CI (`just <c>/diff` as a pull request comment), cosign and SBOM come next.
