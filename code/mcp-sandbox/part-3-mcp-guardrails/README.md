# Part 3: MCP guardrails

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

One gateway sits in front of the three MCP servers (GitHub, draw.io and the Flux schema catalog). The agent sees one `/mcp` endpoint.
Every call and every result passes through the gateway. The design answers the four questions of the problem, one by one.

**1. Who is calling?** A user gets access through a merged pull request. The pull request names the user and the servers that the user may call.
The user then logs in with GitHub through Dex and receives a JWT. The gateway accepts only a call that carries a valid JWT.
It then checks the grant of that user for the target server and the tool. A call without a token fails. A call with a token and no grant fails.

**2. What do the arguments contain?** The ext-mcp guardrail service checks the arguments of each tool call.
It denies path traversal, sensitive file names and credentials. Each denial returns a rule ID, never the value that triggered it.

**3. What does the result carry?** ext-mcp checks each result before it reaches the agent.
It redacts secrets and flags a tool description that changed after approval.

**4. Who is on each hop, and is there a record?** SPIRE gives each workload a SPIFFE identity.
The traffic between the ingress gateway, agentgateway and ext-mcp uses mTLS, so each hop proves who it is.
The gateway holds the upstream credential and sets it on the outbound call. The agent never sees it.

| ID | Control | Where |
|---|---|---|
| MCP01 | The gateway holds the upstream credential. ext-mcp redacts secrets. | `platform/mcp-servers`, `ExternalSecret` from Bitwarden, `platform/ext-mcp` |
| MCP02 | A grant per user for each server and tool. A rate limit per user. | `platform/policies/tool-rbac`, `platform/policies/rate-limit` |
| MCP03 | Tool names carry the target name. ext-mcp pins tool descriptions. | `platform/mcp-servers`, `platform/ext-mcp` |
| MCP04 | One list of registered targets. This reduces the risk. It does not solve it. | `platform/mcp-servers` |
| MCP05 | Argument checks in ext-mcp. | `platform/policies/ext-mcp-checks` |
| MCP06 | Result checks in ext-mcp. This reduces the risk. It does not solve it. | `platform/policies/ext-mcp-checks` |
| MCP07 | A JWT on every call. mTLS between hops. | `platform/policies/authn-jwt`, `platform/policies/mcp-mtls` |
| MCP08 | Access logs and traces. Not wired yet. | not in the repo |
| MCP09 | One registered path. Only the gateway may call ext-mcp. | `platform/routes`, `platform/policies/ext-mcp-isolation` |
| MCP10 | Result checks: redaction and flagging. | `platform/policies/ext-mcp-checks` |

## Architecture

![High-level architecture](docs/diagrams/architecture.drawio.svg)

## Guides

Each guide covers one part of the design. Start with the architecture, then read the others in any order.

| Guide | What it covers |
|---|---|
| [Architecture](docs/arch.md) | The components and the four flows: login and onboarding, workload identity (SPIFFE), mTLS between hops and the MCP guardrails. It also covers the L7 policy chain of the gateway. It also covers the egress policies. |
| [Orchestration](docs/orchestration.md) | How Flux applies the units: the sync model, the bring-up of the cluster, how a change reaches the cluster, and how to enable or disable a component. |
| [The rendered manifest pattern](docs/rendered-manifest-pattern.md) | Why part 3 renders the manifests in CI and not in the cluster. Two diagrams (without and with), a comparison table, and the steps to see the rendered manifest in a pull request and on your machine. |
| [Diagrams](docs/diagrams/README.md) | The draw.io sources of the diagrams, their image files and how to open them. |

The research behind the rendered manifest pattern is in [docs/research/rendered-manifest-pattern.md](../../../docs/research/rendered-manifest-pattern.md).

## Repo structure

```text
part-3-mcp-guardrails/
├── docs/                 arch.md, orchestration.md, rendered-manifest-pattern.md and diagrams/ (the draw.io sources and their SVGs)
├── lib/workflow/         shared just recipes: package-artifact, diff, publish-artifact, compose-stack
├── tools/                config-builder, value-injector and stack-composer
├── config/               overrides only, by cloud, env and region
├── platform/
│   ├── addons/           gateway-api, agentgateway, spire, istio, istio-ingress, cert-manager, external-secrets (each component has flux/stack.yaml)
│   ├── secret-store/     the ClusterSecretStore `bitwarden`: ESO reads the Bitwarden project `ai-infra` with it
│   ├── mcp-servers/      the three servers behind /mcp (one AgentgatewayBackend)
│   ├── routes/           Gateway, AgentgatewayParameters, HTTPRoute
│   ├── ext-mcp/          rules.py, tests, Dockerfile, deploy/
│   └── policies/         authn-jwt, tool-rbac, rate-limit, ext-mcp-checks, ext-mcp-isolation, mcp-mtls
├── clusters/kind/        cluster.yaml, kind-config.yaml, flux-instance.yaml, justfile (bring-up of the cluster and of Flux, and the two Secrets from the host)
├── sync/local-kind/      what Flux reconciles for the cluster: infra-stack.yaml
├── tests/                attack cases, one folder per OWASP id
└── out/                  build output, gitignored
```

## The manifest

`out/manifest.yaml` is next to `out/values.yaml`. It is local, and Git ignores it. `publish-artifact` writes the components, and the `push` of a tool writes the tools. `compose-stack` reads the components. One file holds both kinds of pin:

```yaml
tools:                        # just tools/<name>/push
  stack-composer: { tag: sha256-3c91…, digest: 'sha256:51d0…' }
components:                   # just <component>/publish-artifact
  local-kind:                 # sync: of clusters/<cluster>/cluster.yaml
    istio: { tag: 60b6d97d2498, digest: 'sha256:9f68…' }
```

- The write is one assignment of one key. It adds the entry or replaces the one of the last publish.
- The durable pin of an artifact is the stack in Git. The manifest is what this machine published last.
- A tool needs no step of its own. The first `package-artifact` or `compose-stack` builds and pushes the tools it runs. The next runs skip them. A skipped tool has a cached binary, and the manifest has its tag: the sha256 of the binary. `out/` is local, so a fresh clone does this once.
