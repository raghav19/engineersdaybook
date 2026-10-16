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
| MCP01 | The gateway holds the upstream credential. ext-mcp redacts secrets. | `platform/mcp-servers`, host-created Secret, `platform/ext-mcp` |
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

The flows are in [docs/arch.md](docs/arch.md): login, workload identity, mTLS and the guardrails.
The L7 policy chain of the gateway is in [docs/arch.md](docs/arch.md#l7-policy-chain).

## Repo structure

```text
part-3-mcp-guardrails/
├── docs/                 arch.md and diagrams/ (the draw.io source and its SVG)
├── lib/workflow/         shared just recipes: build, diff, push, pin
├── tools/                config-builder, value-injector and stack-composer
├── config/               overrides only, by cloud, env and region
├── platform/
│   ├── addons/           gateway-api, agentgateway, spire, istio, istio-ingress (each component has flux/stack-entry.yaml)
│   ├── mcp-servers/      the three servers behind /mcp (one AgentgatewayBackend)
│   ├── routes/           Gateway, AgentgatewayParameters, HTTPRoute
│   ├── ext-mcp/          rules.py, tests, Dockerfile, deploy/
│   └── policies/         authn-jwt, tool-rbac, rate-limit, ext-mcp-checks, ext-mcp-isolation, mcp-mtls
├── clusters/kind/        cluster.yaml, kind-config.yaml, flux-instance.yaml, justfile (bring-up of the cluster and of Flux)
├── sync/local-kind/      what Flux reconciles for the cluster: infra-stack.yaml, app-stack.yaml
├── tests/                attack cases, one folder per OWASP id
└── out/                  build output, gitignored
```

## How provisioning works

A short note. The orchestration moves to its own doc later.

```text
component folder ──build──► out/<c>/manifests.yaml ──push──► ghcr.io ──pin──► infra-stack.yaml / app-stack.yaml ──► Flux applies
```

- **One artifact per unit.** Each addon, route set, MCP server registration and policy is its own OCI artifact. The artifact is the rendered manifest. Charts render at build time.
- **A pin selects what runs.** `sync/local-kind/infra-stack.yaml` and `app-stack.yaml` pin one tag and one digest per artifact. A rollout or a rollback is a Git edit of the pin. `just <c>/pin` writes the stacks (see "Disable a component"): do not edit them by hand.
- **Flux applies the pins in order.** Each `Kustomization` in a stack applies one artifact. It starts when every unit in its `dependsOn` is Ready. See the apply order below.
- **Commands.** Run `just <c>/build`, `diff`, `push` and `pin`. `diff` prints the change against the artifact that `origin/main` pins.
- **Values.** The default of a value is in the manifest. `config/` holds only the overrides that differ per cloud, env or region. Each `setters.yaml` names the fields that an override may set.
- **Build functions.** `config-builder`, `value-injector` and `stack-composer` are binaries that `just tools/<name>/push` pushes by digest. It records the digest and the sha256 of each one in `out/manifest.yaml` (see "The manifest"), and the build checks the sha256. `out/` is local: on a fresh clone, run `push` of each tool once (the build is deterministic, so the digest is the same).
- **Disable.** A config flag `<component>_enabled: false` disables a component. See "Disable a component" below.
- **Secrets.** No secret is in Git, in an artifact or in the registry. `just clusters/kind/credentials` (host) creates them in the cluster from `.sbx/secrets.json`, with your age key: `ghcr-pull` and `sops-age` in `flux-system`, and `github-upstream` (the upstream GitHub credential) in `agentgateway-system`. The gateway sets `github-upstream` on the outbound call. After `kind delete`, run the recipe again.
- **Baseline run.** A baseline is the app stack without the policy entries. Compare it with a run that has every policy.

### Apply order

Flux applies the units in six steps. Units in one step apply in parallel. A step starts when every unit it waits for is Ready.

```mermaid
flowchart LR
  s0["<b>Step 0</b><br/>gateway-api<br/>spire"] --> s1["<b>Step 1</b><br/>agentgateway<br/>istio"]
  s1 --> s2["<b>Step 2</b><br/>istio-ingress<br/>ext-mcp *"]
  s2 --> s3["<b>Step 3</b><br/>mcp-servers<br/>ext-mcp-isolation *<br/>mcp-mtls *"]
  s3 --> s4["<b>Step 4</b><br/>routes<br/>tool-rbac<br/>ext-mcp-checks *"]
  s4 --> s5["<b>Step 5</b><br/>authn-jwt<br/>rate-limit"]
```

A unit waits only for units in earlier steps. The stacks in `sync/local-kind/` hold the exact `dependsOn` of each unit. Examples:

- `istio-ingress` and `ext-mcp` need the injection webhook of istiod and an identity from `spire`.
- `mcp-servers` refers to the Secret `github-upstream` by name. `just clusters/kind/credentials` creates it. Flux does not wait for it.
- `istio` takes its CA from `spire` (trust domain `mcp.local`, sidecar mode only, no ambient).
- `ext-mcp-checks` uses `FailClosed`. Without a running ext-mcp every tool call fails.

A `*` marks the ext-mcp group. These units are out of the kind stack for now. They return in the order above.

### The sync folder of a cluster

Flux reconciles one folder for each cluster: `sync/<full name>/`. Its name is the `sync:` value in `clusters/<cluster>/cluster.yaml`. It is `local-kind` now. A later region is for example `aws-dev-us-east-1`, for the placement `cloud/aws/dev/us-east-1`.

```text
sync/local-kind/                what Flux reconciles
├── kustomization.yaml          lists the two stacks
├── infra-stack.yaml            the infrastructure: CRDs, controllers, gateways
└── app-stack.yaml              what runs on it: the MCP servers, the routes, the policies
clusters/kind/
└── flux-instance.yaml          Flux itself: the version, and the path of this sync. Not in the folder above.
```

- **Flux itself is apart from what it reconciles.** `clusters/<cluster>/flux-instance.yaml` is applied only by `just clusters/kind/up` (host). A merge cannot remove it, and deleting the object would uninstall Flux. A Flux upgrade is an edit of `distribution.version`, then `just clusters/kind/up`. The object has the annotation `kustomize.toolkit.fluxcd.io/prune: disabled`, so a sync that once held it never prunes it. The reasons and the sources are in [docs/flux-sync-layout.md](docs/flux-sync-layout.md).
- **The tier of a component** is its folder: a component in `platform/addons/` is infrastructure and goes to `infra-stack.yaml`. Every other component goes to `app-stack.yaml`. `just <c>/pin` picks the stack by that rule.
- The `Kustomization` of an app waits (`dependsOn`) for the ones of the infrastructure, so the order is the same as with one file.
- **Another cluster:** add `clusters/<name>/cluster.yaml` with its `placement` and its `sync:` name, and its own `flux-instance.yaml` with its own sync path. Run the recipes with `CLUSTER=<name>`. It gets its own pins and its own flags (`config/`), so its own stacks.

**Move the sync folder of a running cluster (once, from `clusters/kind/sync` to `sync/local-kind`).** The `flux-system` sync of the cluster has the old path, and it holds the `FluxInstance` in its inventory. The new folder does not list the `FluxInstance`, so protect it first, and change the path with the new file:

1. On the host, before the merge: `kubectl annotate fluxinstance flux -n flux-system kustomize.toolkit.fluxcd.io/prune=disabled`. Without it, the next prune removes the `FluxInstance` and uninstalls Flux.
2. Merge the change. Until step 3, the sync reports that the old path is missing. That is an error, and it removes nothing.
3. On the host, at once: `just clusters/kind/up`. It applies `clusters/kind/flux-instance.yaml`, and the operator changes the path of the sync.
4. Check that `kubectl get kustomization flux-system -n flux-system` shows the new path, Ready. The objects are the same in both folders, so nothing is removed.

I did not test steps 1 to 4 on a cluster. They follow the Flux documentation: an object with that annotation is skipped by garbage collection.

### Disable a component

A flag in `config/` disables one component. Flux then removes its objects. The flag is `<component>_enabled`, with `-` written as `_`.
A name that no config sets means enabled. A lower level overrides a higher level.

```yaml
# config/cloud/kind/kind.yaml
istio_ingress_enabled: false
```

1. Set the flag. The value must be `true` or `false`, not a string.
2. Run `just platform/addons/istio-ingress/diff`. It lists every object that Flux will remove.
3. Run `just platform/addons/istio-ingress/pin`. It removes the pair of `istio-ingress` from `infra-stack.yaml`.
4. Commit the flag and the stack. After the merge, Flux removes the objects.

For a disabled component, `build` renders nothing (`out/<c>/manifests.yaml` is empty) and `push` pushes nothing.

To enable the component again, remove the flag. Run `build`, `push` and `pin`. The pin of a disabled component left the stack, so the pair returns with the pin of the last `push` (`out/manifest.yaml`). Run `push` first when the code changed.

**How `pin` changes the stack.** `stack-composer` (`tools/stack-composer`) does it with `kustomize`. The kustomize files are in its `model/` folder, and the binary carries them.

- Each component has an entry file, `<component>/flux/stack-entry.yaml`: its `OCIRepository` and `Kustomization`, with `tag: unpinned`. It is the contract. Nothing writes it.
- The pin (`out/manifest.yaml`, written by `push`: `components: <cluster>: <component>: {tag, digest}`) becomes a patch of the entry: only `spec.ref` of the `OCIRepository`. Entry plus patch is the pinned entry, in memory.
- The pinned entry then patches the stack of its tier (`infra-stack.yaml` or `app-stack.yaml`): each document overrides the fields of the document of the same kind, name and namespace. A document that is not in the stack is added.
- With the flag `false`, a delete patch (`$patch: delete`, made from the entry) removes the documents from the stack.
- Without an entry in `out/manifest.yaml` (a fresh clone, or no `push` yet), the pin in the stack stays. A pair that is new in the stack is added unpinned.
- It checks that every `dependsOn` names a `Kustomization` of the result or of the other stack, and it writes the stack only if the checks pass. It refuses a bad flag, an entry without the pair, a bad `out/manifest.yaml` and invalid YAML.

`pin` changes only the pair of its own component, and the pins live only in the stacks of `sync/<full name>/`, so they belong to the cluster.
To disable a chain, pin the dependents first (`istio-ingress`, then `istio`, then `spire`). The error message names the components that still wait.
`kustomize` sorts the documents and the keys, and it drops the comments, so the stacks have none. The comments are in the entry files.

Limits:

- CRDs stay. Flux does not prune them, and Helm does not delete them. Run `just clusters/kind/delete-crds` afterward.
- Removing a namespace removes its volumes. Mark an object that must stay with `kustomize.toolkit.fluxcd.io/prune: disabled` first.
- A flag change alone does not change a stack. Run `pin`.
- A patch overrides fields and never removes one. A field that you remove from an entry stays in the stack, and so does a field that someone adds there by hand. To reset a pair, disable the component, pin, then enable it and push and pin again.
- Do not edit a stack by hand. Roll back with `git revert`.
- Disabling a component removes its pin from the stack. `out/manifest.yaml` is local: it keeps the last push, and a fresh clone has none. Enabling again returns the pin of that push, so run `push` first when the code changed.

### The manifest

`out/manifest.yaml` is next to `out/values.yaml`. It is local, and Git ignores it. `push` writes it, and `pin` and the build read it. One file holds both kinds of pin:

```yaml
tools:                        # just tools/<name>/push
  stack-composer: { digest: 'sha256:51d0…', binary: 'sha256:3c91…' }
components:                   # just <component>/push
  local-kind:                 # sync: of clusters/<cluster>/cluster.yaml
    istio: { tag: 60b6d97d2498, digest: 'sha256:9f68…' }
```

- The write is one assignment of one key. It adds the entry or replaces the one of the last push.
- The durable pin of an artifact is the stack in Git. The manifest is what this machine pushed last.
- The pin of a tool is only here. A fresh clone has none: run `just tools/<name>/push` once for each tool.
