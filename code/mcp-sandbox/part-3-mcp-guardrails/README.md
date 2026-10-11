# Part 3: MCP guardrails with agentgateway on kind

Part 1 showed the attack. Part 2 contained one local MCP server. [agent-sandbox](../../agent-sandbox/README.md) put the agent in a microVM. This part puts a **policy point on the MCP path**: every call to a remote MCP server goes through [agentgateway](https://agentgateway.dev) running in a local kind cluster, where tool, argument and response rules apply, mapped to the [OWASP MCP Top 10](https://owasp.org/www-project-mcp-top-10/).

> **Status (foundation, stage A).** Manifests, CRD layer, secrets function, profiles, Taskfile, ext-mcp rules and two attack cases are written and **render offline** (`kustomize build`, phase-1 verified with a shimmed `sops`). **Not yet run against a cluster**: kind and cloud-provider-kind were not available where this was written, and the rootless-Docker LoadBalancer question below is the first thing to prove. Stage B (chaining the sbx gateway to this one, sandbox-driven tests, Keycloak) follows a spike.

## What this builds

- **A gateway in front of three remote MCP servers**: GitHub, draw.io and the Flux schema catalog, federated behind one `/mcp` endpoint with target-prefixed tool names.
- **Two profiles you can compare**: `baseline` (gateway in path, nothing enforced) and `phase-1` (every guardrail on). Same attacks, two results.
- **Declarative end to end**: kustomize only. Values through `configMapGenerator` + `replacements`, charts through kustomize's Helm support, secrets through an exec KRM function over the repo's sops file. Taskfile only orchestrates.

## Architecture

```mermaid
flowchart LR
  subgraph host["Laptop (rootless Docker)"]
    cli["MCP client / test runner<br/>(stage B: via the sbx gateway)"]
    subgraph kind["kind cluster, Kubernetes 1.37"]
      subgraph agw["ns agentgateway-system"]
        gw["Gateway :8080 + HTTPRoute /mcp<br/>Service type NodePort 30080"]
        pol["AgentgatewayPolicy<br/>JWT, tool RBAC, rate limit, ExtMCP"]
        be["AgentgatewayBackend mcp-federated<br/>github | drawio | flux"]
        sec[("Secret github-upstream<br/>rendered by the sops function")]
      end
      subgraph g["ns mcp-guardrails"]
        ext["ext-mcp (Python, gRPC h2c :4445)<br/>arguments, redaction, pinning"]
      end
    end
  end
  cli -- "LB address :8080" --> gw
  gw --> pol --> be
  pol -- "tools/call Full, lists Response" --> ext
  sec -. "Authorization header" .-> be
  be -- "HTTPS" --> up["api.githubcopilot.com<br/>mcp.draw.io<br/>schemas.fluxoperator.dev"]
```

## One request, step by step

```mermaid
sequenceDiagram
    autonumber
    participant C as MCP client
    participant G as agentgateway
    participant P as policies
    participant X as ext-mcp
    participant U as upstream MCP server

    C->>G: tools/call github.merge_pull_request (JWT)
    G->>P: authn (JWT strict)
    alt no or bad token
        P-->>C: 401   (MCP01/07)
    end
    G->>P: tool RBAC (CEL on target + name)
    alt tool excluded
        P-->>C: Unknown tool   (MCP02)
    end
    G->>P: rate limit keyed on jwt.sub
    alt over the limit
        P-->>C: 429
    end
    G->>X: ExtMCP request phase (arguments)
    alt path traversal, sensitive file, secret in args
        X-->>C: -32001 + rule id   (MCP05)
    end
    G->>U: call, upstream credential injected from the Secret
    U-->>G: result
    G->>X: ExtMCP response phase
    X-->>G: redacted / flagged result   (MCP06/10)
    G-->>C: result
```

## How the manifests are composed

```mermaid
flowchart TB
  crds["crds/<br/>Gateway API + agentgateway CRDs<br/>(applied first, on their own)"]
  base["platform/base<br/>controller (helmCharts), gateway, backend, defaults"]
  comp["platform/components<br/>values-wiring, secrets-sops, authn-jwt,<br/>tool-rbac, rate-limit, extmcp, hardening"]
  prof["profiles/<br/>baseline  |  phase-1"]
  fn["functions/sops-secret<br/>exec KRM function"]
  svc["services/ext-mcp/deploy"]
  base --> prof
  comp --> prof
  svc --> comp
  fn --> comp
  prof -- "kustomize build | kubectl apply" --> cluster[(cluster)]
  crds -. "separately, first" .-> cluster
```

### How a secret gets in

```mermaid
sequenceDiagram
    participant T as task gateway:apply
    participant K as kustomize build
    participant F as sops-secret function
    participant S as sops (age key)
    participant A as kubectl apply

    T->>K: build profiles/$PROFILE (--enable-alpha-plugins --enable-exec)
    K->>F: ResourceList + SopsSecret config
    F->>S: sops -d --extract '["GITHUB_TOKEN"]' .env.secrets.json
    S-->>F: value (in this process only)
    F-->>K: Secret github-upstream
    K-->>A: stream (plaintext, never written to disk)
    A->>A: server-side apply
```

The agent never holds this value. The gateway reads it from the Secret and sets the upstream `Authorization` header.

## Directory structure

```text
part-3-mcp-guardrails/
├── README.md
├── research.md                  background research (versions there predate the pins below)
├── Taskfile.yml                 orchestration only; PROFILE= picks the profile (default baseline)
├── tasks/                       checks.yml (prechecks), cluster.yml, platform.yml, tests.yml; included by Taskfile.yml
├── crds/                        installed separately, first: gateway-api/ and agentgateway/
├── platform/
│   ├── base/                    namespaces, controller (helmCharts), gateway, backend, defaults
│   └── components/              values-wiring, secrets-sops, authn-jwt, tool-rbac, rate-limit, extmcp, hardening
├── profiles/                    baseline, phase-1: which guardrails are on (no region/env data)
├── kind-config.yaml             the kind cluster: control-plane + 2 workers, pinned API server port, host port 8080 -> gateway NodePort
├── functions/sops-secret/       exec KRM function over .env.secrets.json
├── services/ext-mcp/            rules.py (+ tests), Dockerfile, deploy/ (kustomization)
└── tests/
    ├── attacks/                 one folder per OWASP id: run.sh, driven by lib.sh
    └── servers/evil-mcp/        fixture server (stub)
```

There is one environment, the kind cluster. `task gateway:apply PROFILE=phase-1` switches the guardrails; a value comes from `platform/base/defaults/values.env`. A second environment would be a new overlay on top of `profiles/`; it is not built.

## Versions

Latest stable at 2026-10-10, checked against the GitHub release APIs, for Kubernetes **1.37**:

| Component | Pin | Where |
|---|---|---|
| Kubernetes (kind node image) | `v1.37.0@sha256:a1ed56cf…` (kind v0.33.0 default) | `kind-config.yaml` |
| kind | 0.33.0 | root `mise.toml` |
| Gateway API (experimental channel) | v1.6.3 | `crds/gateway-api/` |
| agentgateway (CRDs and controller) | v1.6.0 | `crds/agentgateway/`, `platform/base/controller/` |
| kubectl / kustomize / helm | 1.37 / 5.8.3 / 4.3.0 | root `mise.toml` |

agentgateway v1.6.0 lists Kubernetes 1.32 to 1.37 and Gateway API 1.4 to 1.6 as supported ([research.md](research.md)). Bump a CRD version in `crds/` and the matching controller version together.

## Getting started

Prerequisites: rootless Docker as in [`code/rootless-docker`](../../rootless-docker), `mise install` at the repo root, and your age key for `sops`.

1. **Upstream credential.** The gateway uses the existing `GITHUB_TOKEN` from `.env.secrets.json` (`platform/components/secrets-sops/sops-secret.yaml`). Check on the host that it can call the GitHub MCP server (`tools/list` in step 6 returns the `github_*` tools). It was created for pulling the kit image, so if it lacks the repo permissions you need, add a dedicated key (for example `GITHUB_MCP_PAT`, a fine-grained PAT on the one repo) and change the mapping in that file.
2. **Create the cluster and apply everything.** `task bootstrap` (cluster, CRDs, platform with profile `baseline`), or step by step: `task cluster:up`, `task crds:apply`, `task gateway:apply`.
3. **Check the gateway.** It answers on `http://127.0.0.1:8080/mcp` (host port 8080 -> NodePort 30080, set in `kind-config.yaml`); `tools/list` with the MCP Inspector should show `github_*`, `drawio_*` and `flux_*` tools.
4. **Run the attacks on baseline:** `task tests:run`.
5. **Switch to phase-1 and run them again:** `task gateway:apply PROFILE=phase-1`, then `task tests:run PROFILE=phase-1`.
6. **Tear down.** `task cluster:down`.

Every task that touches the cluster (`crds:apply`, `gateway:*`, `tests:run`) refuses to run unless `kubectl`'s current context is `kind-mcp-guardrails`. `cluster:up` and `cluster:down` run before that context exists, so they check for the tools instead.


## Guardrails and what they map to

| Control | Component | OWASP MCP | Test |
|---|---|---|---|
| JWT, strict | `authn-jwt` | MCP01, MCP07 | `MCP07-no-token` |
| Upstream credential held by the gateway | `secrets-sops` + backend `auth.secretRef` | MCP01 | (inspect: nothing client-side) |
| Tool deny list (CEL, target + name) | `tool-rbac` | MCP02 | `MCP02-destructive-tool` |
| Rate limit per `jwt.sub` | `rate-limit` | MCP02, MCP10 | to write |
| Argument and response checks, pinning | `extmcp` + `services/ext-mcp` | MCP03, 05, 06, 10 | `rules.py` unit tests; attack cases to write |
| Only the gateway may call ext-mcp | `hardening` | MCP04, MCP09 | to write |
| Access logs and traces | not wired | MCP08 | to write |

MCP04 (supply chain) and MCP06 (intent flow subversion) are reduced here, not solved.

## Known gaps and open risks

- **The gateway is reached through a NodePort, not a LoadBalancer, and that path is not yet verified end to end.** cloud-provider-kind does not work on rootless Docker with the pasta network: its proxy container gets an ephemeral host port, and pasta does not forward 32768-60999 (see `kind-config.yaml`). `kind-config.yaml` instead maps host `127.0.0.1:8080` to NodePort 30080, which `platform/base/gateway/parameters.yaml` pins. The manifests render and the mapping is created; a request through the gateway has not been made yet.
- Both OCI Helm charts now render offline (`kustomize build --enable-helm`): 17 CRDs plus the Gateway API safe-upgrades admission policy, and the controller.
- **`GITHUB_TOKEN` as the MCP credential is untested**: it could not be decrypted where this was written, so its permissions against the GitHub MCP server are unknown.
- **Not verified against a live controller**: the CRD field names are checked against the v1.6.0 schemas, but `Gateway` Programmed status, the secret key convention (`Authorization`, raw token) and how two `AgentgatewayPolicy` objects on one backend merge need a cluster.
- **JWKS is a placeholder** (`{"keys":[]}` in `authn-jwt`) until a key is minted; Keycloak replaces it in stage B.
- **ext-mcp has rules but no server yet**: the gRPC contract is to be vendored at the pinned tag.
- Argument-level CEL is unreliable in agentgateway ([#3092](https://github.com/agentgateway/agentgateway/issues/3092)), which is why argument checks live in ext-mcp.
- Exec KRM functions run with your privileges; the one here is 40 lines and in this repo. Kustomize has no built-in sops support.
