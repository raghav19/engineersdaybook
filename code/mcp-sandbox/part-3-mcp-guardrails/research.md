# MCP Guardrails for the Docker Sandbox: agentgateway's MCP Gateway on Kind with Gateway API

Make the agentgateway proxy in your Kind cluster the only MCP endpoint your Claude Code sandbox can reach. Pin agentgateway **v1.6.0**, released 02 Oct 2026, which supports Gateway API 1.4–1.6, Kubernetes 1.32–1.37 and MCP spec 2026-07-28.\[1\] Federate every in-cluster and remote MCP server behind one `AgentgatewayBackend`. Then add guardrails in layers: CEL tool authorization, JWT auth, gateway-held credentials, rate limits, and a custom ExtMCP gRPC service for argument and response inspection and rug-pull pinning. Finally, turn off sbx's built-in host MCP gateway and allow only the gateway's port in `sbx policy`. The gateway handles identity, authorization, credentials, audit and shadow-server problems natively. Tool poisoning, prompt injection, command injection and supply chain still need your ExtMCP code plus the microVM sandbox, image pinning and scanning.

## TL;DR

- **Build it on agentgateway v1.6 OSS with Gateway API v1.6.0 experimental CRDs on Kind.** The pieces are a `Gateway` (class `agentgateway`), an `HTTPRoute` for `/mcp`, and an `AgentgatewayBackend` with static targets for remote MCP servers and label-selector targets for in-cluster ones. `AgentgatewayPolicy` attached to the backend carries `spec.backend.mcp.authorization` (CEL allowlists), `spec.backend.mcp.guardrails` (ExtMCP processors, `FailClosed` by default) and `spec.traffic.*` (JWT, rate limits). Built-in today: tool-level RBAC, which both hides tools in `tools/list` and blocks direct `tools/call`; federation with target-prefixed tool names; credential injection; local and global rate limits; and OTel traces, metrics and access logs. Not built in: argument inspection, response scanning for MCP, and description pinning. You write those as an ExtMCP server.
- **The networking path from sandbox to gateway is fixed by how the sbx proxy works.** The agent dials `http://host.docker.internal:8080/mcp`. The sbx host proxy rewrites that destination to `localhost`, so the allow rule must be `sbx policy allow network localhost:8080`, not `host.docker.internal:8080`.\[2\] On the host, `kubectl port-forward` (or a Kind `extraPortMappings` NodePort) exposes the gateway on 127.0.0.1:8080. Your current setup goes through sbx's built-in MCP gateway (sbx ≥0.38.0, Aug 2026). docker/sbx-releases issue #612 (opened 21 Sep 2026) reports that "the MCP gateway cannot be disabled, and the list of MCP servers exposed by it cannot be filtered/configured," and that it exposes the servers registered in the host's own Claude Code even when `sbx mcp ls` is empty. Disable it and register only the agentgateway URL so the gateway is the single MCP egress.
- **Demo order: insecure baseline first, then one guardrail per phase, each tied to an OWASP MCP Top 10 ID.** The current list is MCP01–MCP10:2025. The OWASP project page says "Phase 3 – Beta Release and Pilot Testing - We are here right now," and ToolMesh reports the next release is scheduled for October 2026. Each phase re-runs the same attack suite, which comes from the Invariant Labs tool-poisoning, shadowing and rug-pull patterns and from MCPTox/MCPSecBench-style cases.\[3\]\[4\]\[5\] Show before and after through the gateway's JSON-RPC errors (`-32001` on ExtMCP deny, `Unknown tool` on RBAC), access logs and OTel traces. State plainly that MCP06 (intent flow subversion) and MCP04 (supply chain) can only be reduced, not solved, at the gateway.

## Assumptions

- One laptop (macOS or Linux), Docker Desktop or Docker Engine, one Kind cluster, dev scale with one gateway replica.
- Claude Code runs inside an sbx microVM built from your v3 kit. Kits are now plain OCI images under Docker's open Sandbox Kit Specification v3, Apache 2.0, `docker/sandbox-kit-spec`.\[6\]
- You run a mix of local stdio servers, local HTTP servers and remote HTTPS MCP servers, some of which use OAuth.
- I could not read your blog post. The share.google link blocks automated access. Everything about your current setup comes from your description: host-run MCP reached through the sbx proxy.

## Key Findings

1. **agentgateway is the right control point, and it is moving fast.** Releases went v1.3.0 (Jun 2026) → v1.5.0 (27 Aug 2026) → v1.6.0 (02 Oct 2026),\[1\] and a 1.6.0-alpha/rc cycle preceded GA.\[7\]\[8\]\[9\]\[10\] Field names have changed between versions. In kgateway v2.2, MCP auth was `spec.backend.mcp.authentication`.\[11\] In the 1.6 docs it lives at `spec.traffic.jwtAuthentication` with an `mcp:` sub-block (`provider`, `resourceMetadata`). Pin chart versions and treat every YAML here as 1.6-specific.\[12\]
2. **Authorization is enforced twice.** agentgateway filters list responses (`tools/list`, prompts, resources) per caller, then re-authorizes every `tools/call`, `prompts/get` and `resources/read`.\[13\] A tool the policy forbids comes back as `{"code":-32602,"message":"Unknown tool: …"}`.\[14\] Rules have three effects: `deny` (any match rejects), `require` (all must be true) and `allow` (at least one must match once any allow rule exists). Evaluation order is deny → require → allow.\[13\]
3. **Argument-level CEL is unreliable. Use ExtMCP for it.** agentgateway issue #3092 shows that a rule like `mcp.tool.name == "get-sum" && mcp.tool.arguments.a == 1` is Accepted and Attached but returns 400 `"mcp: Unknown tool: get-sum"` for both `{"a":1}` and `{"a":2}`. In other words, request-time MCP authorization rules that reference `mcp.tool.arguments` never match and end up denying everything. ExtMCP is the documented route for argument and result decisions. It is a gRPC callout modeled on Envoy `ext_authz`. It receives the JSON-RPC method, target backend, params or result, and selected headers. It can Pass, Mutate or Deny in the `Request`, `Response` or `Full` phase.\[13\]\[15\]
4. **The LLM prompt guards are LLM-shaped, not MCP-shaped.** The guard set covers regex, OpenAI moderation, Bedrock Guardrails, Google Model Armor and webhooks.\[12\] As of v1.5 these can also scan tool inputs and outputs inside *LLM* traffic through `scope`. They attach under `spec.backend.ai.promptGuard`.\[16\]\[17\] A maintainer-tracked feature request states plainly that the webhook API is `/request`/`/response`-shaped and not JSON-RPC. For MCP traffic, ExtMCP is the hook.\[18\]
5. **sbx already has its own MCP gateway, and that is your current gap.** sbx 0.38.0 added `sbx mcp add/load/ls` and a per-sandbox gateway that keeps OAuth tokens on the host. Its docs warn that local stdio servers registered with `--command` "run on the host, outside sandbox isolation, with your host user's permissions".\[19\] Org-level Cedar MCP policies exist, but only under Docker AI Governance.\[19\]\[20\]
6. **cloud-provider-kind ships its own Gateway API controller and CRDs.** That is useful for LoadBalancer IPs.\[21\]\[22\] It can also collide with the Gateway API v1.6.0 experimental CRDs agentgateway expects. On a laptop, port-forward or NodePort with `extraPortMappings` is the more deterministic choice.

## Architecture

```
┌──────────────────────────── Laptop (host) ─────────────────────────────────────┐
│                                                                                │
│  VS Code ──► sbx microVM (Claude Code, v3 kit)                                 │
│               │  .mcp.json → http://host.docker.internal:8080/mcp              │
│               ▼                                                                │
│        sbx host proxy (deny-by-default; allow localhost:8080; logs; may inject │
│        a gateway token as a custom secret — verify)                            │
│               │  (host.docker.internal rewritten → localhost)                  │
│               ▼                                                                │
│   127.0.0.1:8080  (kubectl port-forward  OR  Kind extraPortMapping→NodePort)   │
│               │                                                                │
│  ┌──────────── Kind cluster ───────────────────────────────────────────────┐   │
│  │  ns agentgateway-system                                                  │  │
│  │   Gateway(agentgateway-proxy) ─ HTTPRoute /mcp ─► AgentgatewayBackend    │  │
│  │      ▲ AgentgatewayPolicy: jwtAuthentication, rateLimit,                 │  │
│  │      │   backend.mcp.authorization (CEL), backend.mcp.guardrails ─► ExtMCP│ │
│  │      │                                    (your gRPC svc: arg checks,    │  │
│  │      │                                     response scan, pin hashes,    │  │
│  │      │                                     Presidio/Llama Guard calls)   │  │
│  │   targets:                                                               │  │
│  │    • selector app-label → in-cluster MCP pods (ns mcp-servers)           │  │
│  │    • static → remote HTTPS MCP (GitHub etc.), TLS SNI + injected creds   │  │
│  │    • stdio servers wrapped as HTTP pods (see §3)                         │  │
│  │   OTel collector → Jaeger/Tempo, Prometheus, Grafana                     │  │
│  │   NetworkPolicy: MCP pods ingress only from gateway; egress allowlist    │  │
│  └──────────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────────┘
```

## Details

### 1. agentgateway: what exists today (v1.6)

- **Project.** The data plane is written in Rust, and there is a Kubernetes control plane. It is a Linux Foundation project that has joined the Agentic AI Foundation.\[12\]\[14\] Images: `cr.agentgateway.dev/agentgateway:v1.6.0` and `controller`. Helm charts: `oci://cr.agentgateway.dev/charts/agentgateway` and `agentgateway-crds`. A separate `agentgateway-standalone` chart also exists.\[10\] The kgateway docs still host agentgateway pages, but agentgateway.dev is now canonical.
- **MCP features verified in the docs:**
  - Static, dynamic (label selector) and virtual (multiplexed) MCP.\[12\]\[23\]
  - Transports: SSE and StreamableHTTP for Kubernetes targets. Kubernetes `path` defaults to `/sse` or `/mcp`.\[24\]
  - Stdio and OpenAPI-to-MCP targets in *standalone* config.\[25\]\[26\] I found no Kubernetes CRD field for stdio. Assume it is unsupported in K8s mode until you check the AgentgatewayBackend API reference.
  - Stateful sessions by default, with `sessionRouting: Stateless` as an option.\[11\]\[27\]
  - `prefixMode` (Conditional/Always) and target `failureMode`.\[24\]
  - MCP Apps.\[10\]\[12\]
  - 1.6 additions: list pagination with a combined `nextCursor` across federated targets, a request-size limit that returns 413, and an automatic `mcp.methodName` CEL variable.\[17\]
  - MCP auth with OAuth protected-resource metadata. There are guides for Keycloak, Auth0, authentik, Descope, Entra and Okta.\[12\]\[23\]
  - Token exchange for MCP servers, JWT bearer grant (RFC 7523), Cross App Access (ID-JAG), and API-key auth.\[12\]\[23\]
- **CEL variables:** `mcp.tool.name`, `mcp.tool.target`, `mcp.prompt.name`, `mcp.resource.name`, `mcp.methodName`, `jwt.<claim>`, `source.address`.\[13\]\[14\]
- **Behavior changes in 1.6 that affect you:**
  - When policies conflict, the oldest by creationTimestamp wins.\[17\]
  - Server-side CRD defaults are no longer written back, so `kubectl get -o yaml` shows only the fields you set.\[17\]
  - Streaming guardrails now fail closed.\[17\]
  - Policy-service timeouts default to 2s for ext authz and 10s for rate-limit and ext-proc.\[17\]
  - JWT gains `validation.requiredClaims`, and `nbf` is enforced with 60s skew.\[17\]\[28\]

### 2. Gateway API integration: manifests

**Install** (versions pinned):

```bash
export GWAPI_VERSION=1.6.0 AGW_VERSION=v1.6.0
kubectl apply --server-side --force-conflicts \
  -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v${GWAPI_VERSION}/experimental-install.yaml
helm upgrade -i agentgateway-crds oci://cr.agentgateway.dev/charts/agentgateway-crds \
  --create-namespace -n agentgateway-system --version ${AGW_VERSION}
helm upgrade -i agentgateway oci://cr.agentgateway.dev/charts/agentgateway \
  -n agentgateway-system --version ${AGW_VERSION} --wait
```

Use the experimental channel. The MCP auth guide's prerequisites use it,\[12\] and CORS and some filters need it.\[29\] Experimental Gateway API features are gated by `AGW_ENABLE_EXPERIMENTAL_GATEWAY_API_FEATURES`, which the docs say is enabled by default in 1.6.\[1\] Older tutorials used `KGW_ENABLE_GATEWAY_API_EXPERIMENTAL_FEATURES`, so don't copy that flag forward.\[14\]\[30\]

**Gateway + route:**

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: agentgateway-proxy, namespace: agentgateway-system }
spec:
  gatewayClassName: agentgateway
  listeners:
  - { name: http, protocol: HTTP, port: 80, allowedRoutes: { namespaces: { from: Same } } }
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: mcp, namespace: agentgateway-system }
spec:
  parentRefs: [{ name: agentgateway-proxy }]
  rules:
  - matches: [{ path: { type: PathPrefix, value: /mcp } }]
    backendRefs: [{ group: agentgateway.dev, kind: AgentgatewayBackend, name: mcp-federated }]
```

**In-cluster servers** (label-selector discovery). The Service must set `appProtocol: agentgateway.dev/mcp`:\[31\]\[32\]\[33\]\[34\]

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mcp-everything
  namespace: agentgateway-system   # same-ns keeps it simple; cross-ns needs care
  labels: { app: mcp-everything, mcp-federation: "true" }
spec:
  selector: { app: mcp-everything }
  ports: [{ port: 80, targetPort: 3001, appProtocol: agentgateway.dev/mcp }]
```

**Federated backend** combining a label selector with a remote static target:\[35\]

```yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayBackend
metadata: { name: mcp-federated, namespace: agentgateway-system }
spec:
  mcp:
    targets:
    - name: local
      selector: { services: { matchLabels: { mcp-federation: "true" } } }
    - name: github
      static:
        host: api.githubcopilot.com
        port: 443
        path: /mcp/
        policies: { tls: { sni: api.githubcopilot.com } }
```

With more than one target, tool names are prefixed with the target name (Conditional `prefixMode`).\[24\]\[33\] That prevents cross-server name collisions, which is part of the shadowing defense.\[36\] Policies aimed at one target inside a multiplexed backend select it with `targetRefs[].sectionName`.\[24\]\[37\]

**Remote credentials stay in the gateway.** The pattern the community tutorial verified injects the header on the route:\[14\]

```yaml
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        set: [{ name: Authorization, value: "Bearer ${GH_PAT}" }]   # rendered from a Secret at apply time
```

For production-grade hygiene, prefer a Secret-backed backend auth policy (`backendAuth`/`spec.backend.auth`) or token exchange over a literal in the route. Token passthrough is the anti-pattern the MCP spec forbids: tokens must be issued for the MCP server and not forwarded downstream.\[38\]

**Tool allowlist** (CEL, built in):\[14\]

```yaml
apiVersion: agentgateway.dev/v1alpha1
kind: AgentgatewayPolicy
metadata: { name: tool-rbac, namespace: agentgateway-system }
spec:
  targetRefs: [{ group: agentgateway.dev, kind: AgentgatewayBackend, name: mcp-federated }]
  backend:
    mcp:
      authorization:
        action: Allow
        policy:
          matchExpressions:
          - 'mcp.tool.target == "github" && mcp.tool.name in ["get_me","list_issues","get_issue"]'
          - 'mcp.tool.target == "local" && mcp.tool.name in ["echo","get-sum"]'
          - 'has(jwt.sub) && jwt.sub == "claude-sbx" && mcp.tool.name == "search_repositories"'
```

**MCP auth** (1.6 shape, abridged from the Keycloak guide):

```yaml
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: HTTPRoute, name: mcp }]
  traffic:
    jwtAuthentication:
      mode: Strict
      providers:
      - issuer: "${ISSUER}"
        audiences: ["${MCP_RESOURCE}"]
        jwks: { remote: { backendRef: { name: keycloak, kind: Service, namespace: keycloak, port: 8080 }, jwksPath: "/realms/mcp/protocol/openid-connect/certs" } }
      mcp:
        provider: Keycloak
        resourceMetadata: { resource: "${MCP_RESOURCE}", scopesSupported: [mcp.tools], bearerMethodsSupported: [header] }
```

The HTTPRoute must also match `/.well-known/oauth-protected-resource/mcp` and `/.well-known/oauth-authorization-server/mcp`.\[12\] For a laptop demo, a static inline JWKS with a locally minted JWT is enough and avoids running Keycloak.\[12\] The tool-access guide uses `jwks.inline` with `issuer: solo.io`.\[23\]\[39\]

**Rate limits:**

```yaml
spec:
  targetRefs: [{ group: gateway.networking.k8s.io, kind: HTTPRoute, name: mcp }]
  traffic:
    rateLimit:
      local:
      - { requests: 60, unit: Minutes, burst: 10, key: 'jwt.sub' }   # `key` is new in 1.6
```

One tool call costs roughly 5 HTTP requests (initialize, notifications, list, call), so size limits by session and not by raw request count.\[40\] True per-tool limits use global rate limiting. That means CEL descriptors that extract the JSON-RPC method and `params.name`, an Envoy rate-limit service and Redis.\[41\]\[42\] In 1.6 you can probably key on `mcp.methodName`, but I could not see an exact 1.6 YAML example for it.\[17\]

**ExtMCP guardrails:**

```yaml
spec:
  targetRefs: [{ group: agentgateway.dev, kind: AgentgatewayBackend, name: mcp-federated }]
  backend:
    mcp:
      guardrails:
        processors:
        - remote: { backendRef: { name: ext-mcp, port: 4445 }, failureMode: FailClosed }
          methods: { "tools/call": Full, "tools/list": Response, "resources/read": Response, "prompts/get": Response }
```

The ExtMCP Service needs `appProtocol: kubernetes.io/h2c`. The contract is `crates/protos/proto/ext_mcp.proto` in the agentgateway repo.\[15\]\[43\] Behaviors to design around:
- Processors run in order, and the first deny short-circuits the chain.\[15\]
- MCP authentication runs *before* request processors and is not re-run after mutation.\[15\]
- CEL RBAC evaluates the *original* tool name and backend, not the mutated one.\[15\]
- `tools/list` fan-out calls your server once per backend, with un-prefixed names and the backend passed as metadata.\[15\]
- ExtMCP denies map to JSON-RPC `-32001` (PERMISSION_DENIED) and `-32003` (RESOURCE_EXHAUSTED).\[15\]
- Since 1.6, access-log CEL can read the dynamic metadata your processor returns.\[17\] Use that for audit fields such as `guardrail.rule_id`.

### 3. Kind on the laptop

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
name: agw
nodes:
- role: control-plane
  extraPortMappings:
  - { containerPort: 30080, hostPort: 8080, listenAddress: "127.0.0.1", protocol: TCP }
```

`kind create cluster --config kind-config.yaml`, then install as in §2.

Exposure options, in order of preference:
- **(a) `kubectl port-forward deploy/agentgateway-proxy -n agentgateway-system 8080:80`.** Simplest, and binds 127.0.0.1. It dies when the terminal closes, so wrap it in a `make` target or launchd/systemd unit.
- **(b) NodePort 30080 via the `extraPortMappings` above.** Survives restarts. Patch the generated proxy Service to NodePort through `AgentgatewayParameters` (the "Customize the gateway" docs). Verify the exact field name in your version.
- **(c) cloud-provider-kind.** Gives real LoadBalancer IPs on the Kind Docker network.\[44\] It also installs its own Gateway API controller (GatewayClass `cloud-provider-kind`) and CRDs, so install agentgateway's v1.6.0 CRDs *after* it and check `kubectl get crd gateways.gateway.networking.k8s.io -o yaml` for the bundle version.\[21\] On macOS, Docker-network IPs are not routable from the host without extra plumbing, which is one more reason to prefer (a) or (b). MetalLB has the same reachability caveat.

**Stdio servers.** The K8s CRD exposes SSE and StreamableHTTP targets only, so containerize each stdio server behind an HTTP adapter. Option one: run a tiny standalone agentgateway sidecar per pod with a `stdio:` target, which is the pattern one community EKS design uses for the stdio-only GitHub App server.\[45\] Option two: use an stdio→Streamable HTTP bridge. Either way the stdio process now runs in a pod you can constrain with securityContext, NetworkPolicy and no host mounts. That is better than sbx's host-run `--command` servers.

**Remote MCP servers.** Use a static target on port 443 with `tls.sni`, and inject credentials from a Secret. For OAuth-only remotes such as Notion or Linear, the gateway needs a token it can refresh. The agentgateway docs warn that when users must complete a browser OAuth flow per upstream, you should expose separate paths and not multiplex them.\[13\]

**Testing.**

```bash
npx @modelcontextprotocol/inspector --cli http://localhost:8080/mcp --transport http --method tools/list
```

Then call an allowed tool and a forbidden one. The agentgateway admin UI and `agctl proxy trace` show per-request policy evaluation.\[12\]

**NetworkPolicy.** Confirm your Kind CNI enforces NetworkPolicy. If it doesn't, create the cluster with `disableDefaultCNI: true` and install Calico or Cilium. Cilium is required if you want FQDN egress rules for the remote-MCP allowlist.

### 4. Wiring the sbx sandbox to the gateway

1. **Network policy (host terminal):**

   ```bash
   sbx policy allow network localhost:8080
   ```

   Then restart the sandbox.\[46\] varlock.dev's Docker Sandboxes guide and the Collabnix Docker Workshop Lab 8 both report this proxy quirk: the gateway rewrites `host.docker.internal` to `localhost` and matches policy against the rewritten destination, or in Collabnix's words, "the sbx proxy normalizes the target to localhost… even when you'll reach it via host.docker.internal." `sbx policy check network host.docker.internal:8080` can report *Allowed* even though the request returns 403. Inside the VM, `localhost` is the VM itself, so always dial `host.docker.internal`.\[46\]
2. **Claude Code config (inside the sandbox, or baked into the kit's `files/home/.claude.json` / repo `.mcp.json`):**

   ```bash
   claude mcp add --transport http agw http://host.docker.internal:8080/mcp \
     --header "Authorization: Bearer ${AGW_TOKEN}"
   ```

   Equivalent `.mcp.json`:

   ```json
   { "mcpServers": { "agw": { "type": "http", "url": "http://host.docker.internal:8080/mcp" } } }
   ```

3. **Make the gateway the single MCP egress:**
   - Remove every other `mcpServers` entry.
   - Strip the auto-injected `mcp-gateway` entry from `/home/agent/.claude.json` in your kit. That is the workaround suggested in sbx issue #612, which reports the built-in gateway "cannot be disabled" and exposes all host-registered servers.\[47\] Alternatively, create sandboxes with `--static-mcp` and an empty list.\[19\] Verify which one your sbx version honors.
   - Unregister host stdio servers (`sbx mcp rm`).\[48\]
   - Keep the network policy at deny-all plus `api.anthropic.com` (or your model endpoint) plus `localhost:8080`. A remote MCP host the agent tries to reach directly then gets a 403 and shows up in `sbx policy log`.
   - Optionally push Claude Code managed settings (`/etc/claude-code/managed-settings.json` in the kit image) with an MCP server allowlist naming only `agw`.\[49\] Check the current key names in Claude Code docs.
4. **Agent identity without exposing the secret.** sbx can inject custom secrets on the wire for named hosts (`sbx secret set-custom --host … --env …`), and the agent sees only a placeholder.\[19\]\[50\]\[51\] If that works for a `localhost` target, the gateway JWT never enters the VM. That would be the strongest MCP01 story, but it is unverified for localhost destinations, so test it. Fallback: a short-lived (≤15 min), audience-bound JWT minted per session.
5. **Gotchas:**
   - Policy changes need a sandbox restart.\[46\]
   - sbx 0.47.0 blocks DNS when no rule permits it and fails closed on policy-evaluation errors.\[52\]
   - The sbx proxy may intercept TLS. Keep the gateway on plain HTTP over loopback, or trust its CA in the kit.
   - MCP spec 2026-07-28 is stateless: it removes `Mcp-Session-Id` and adds `Mcp-Method`/`Mcp-Name` headers.\[53\]\[54\] agentgateway 1.6 lists support for it, but its stateful session routing is still the default.\[27\] If your Claude Code build negotiates the new revision, test both `sessionRouting` modes.

### 5. Docker MCP Gateway / sbx MCP gateway vs agentgateway

| | Docker MCP Gateway (`docker mcp gateway run`, Toolkit) | sbx built-in MCP gateway (≥0.38) | agentgateway |
|---|---|---|---|
| Where it runs | Host or container; spawns servers as containers through the Docker socket | Per-sandbox, managed by sbx on the host | Kubernetes (Gateway API) or standalone binary |
| Server isolation | Strong: each server in a container, `--cpus`/`--memory`, `--block-network` | Remote servers proxied; local stdio servers run **on the host**\[19\] | Only what you give the pods (K8s) |
| Secrets | Docker Desktop secrets or `.env`; `--block-secrets` defaults to true | OAuth tokens in the host store, injected on the way out\[19\] | K8s Secrets, header injection, token exchange |
| Tool policy | `--tools server:tool` filters, `--interceptor before/after`, `--verify-signatures`, `--log-calls` | Cedar MCP policies (register/invokeTool/readResource/getPrompt) **only with Docker AI Governance**\[20\]\[55\] | CEL RBAC on tool, target and JWT; ExtMCP gRPC; rate limits |
| Gateway API / K8s-native | No | No | Yes |
| Observability | Call logging | `sbx policy log`, governance audit | OTel traces, Prometheus metrics, structured access logs, UI |

**Positioning.** Docker's tools are strongest at running untrusted MCP servers in containers and at desktop and org governance.\[56\]\[57\] agentgateway is strongest as a protocol-aware policy enforcement point with Kubernetes-native config and real telemetry. For your demo, agentgateway is the PEP. If you want container isolation for stdio servers without Kubernetes, the Docker MCP Gateway can sit *behind* agentgateway as one more static target. The two layer; they do not compete. Note that the sbx MCP gateway is a separate product from the Docker Desktop MCP Toolkit, and their settings aren't shared.\[58\]

### 6. OWASP MCP Top 10 mapping

The list below is the current OWASP list (v0.1). The project page says "Phase 3 – Beta Release and Pilot Testing - We are here right now," and ToolMesh reports the next release is scheduled for October 2026. According to ToolMesh's analysis, the owasp.org summary table lists MCP06:2025 as "Intent Flow Subversion", while a fuller listing further down the same page titles the same entry "Prompt Injection via Contextual Payloads".

| ID | Attack vector → threat | Gateway + K8s control (mitigates) | Not mitigated → other layer |
|---|---|---|---|
| MCP01 Token Mismanagement & Secret Exposure | PATs in `.mcp.json`, tokens echoed in tool output or logs, prompt-injected exfil | Credentials live only in gateway Secrets and are injected per target; agent holds a short-lived audience-bound JWT (`requiredClaims`, `audiences`); ExtMCP response redaction of credential patterns; K8s RBAC on Secrets | Token lifecycle and rotation (IdP / External Secrets); secrets on the host FS (sbx mount policy) |
| MCP02 Privilege Escalation via Scope Creep | Server exposes `delete_repo`; new tools appear upstream | Allowlist CEL (fallback deny once any allow exists); per-identity rules on `jwt.sub`/`jwt.groups`; target-scoped rules; read-only upstream tokens | Upstream token scope design; server-side authz |
| MCP03 Tool Poisoning | Hidden instructions in descriptions; rug pull after approval; shadowing\[59\]\[60\] | Target prefixing (anti-shadowing); ExtMCP on `tools/list` Response: hash name+description+inputSchema per target against a pinned manifest, strip or deny on drift, scan descriptions for injection patterns | Pre-admission scanning (mcp-scan style); signed manifests (not standard in MCP)\[61\]\[62\] |
| MCP04 Supply Chain & Dependency Tampering | Malicious npm/PyPI server update; typosquat | Only images you deploy are reachable; allowlisted static targets; digest-pinned images; admission policy (Kyverno/OPA) for signed images | SBOM and signature verification, dependency review: outside the gateway |
| MCP05 Command Injection & Execution | `raw_command: "rm -rf /"`, path traversal, SSRF via args | ExtMCP request-phase argument validation (deny lists, schema and regex, path canonicalization); pod securityContext (non-root, read-only rootfs, no host mounts); NetworkPolicy egress deny | The server must still validate; the sbx microVM contains agent-side execution |
| MCP06 Prompt Injection via Contextual Payloads (Intent Flow Subversion) | Malicious issue or web page content in tool *results* steers the agent | ExtMCP Response phase: classifier call (Llama Guard / Prompt Guard model, Lakera API, NeMo) and quarantine or annotate; least-privilege tools cap the blast radius | Cannot validate intent; needs model-side defenses, human-in-the-loop for sensitive tools, Claude Code permission prompts |
| MCP07 Insufficient Authentication & Authorization | Unauthenticated gateway; confused deputy; token passthrough | `jwtAuthentication mode: Strict`; OAuth protected-resource metadata; per-call re-authorization; token exchange in place of passthrough; listener bound to loopback only | IdP configuration; per-client consent (spec requirement for proxies) |
| MCP08 Lack of Audit & Telemetry | No record of which tool ran with which args | Access logs with CEL-enriched fields (incl. ExtMCP metadata), OTel traces with outbound spans for policy calls, Prometheus metrics; ship to Loki/Tempo | Immutability (WORM storage); agent-side transcript logging |
| MCP09 Shadow MCP Servers | Dev adds an ad-hoc server in `.mcp.json` or on the host | sbx deny-by-default egress plus only `localhost:8080`; strip the sbx auto gateway; Claude managed MCP allowlist; the gateway is the sanctioned path | Discovery across the org's network; developer machines outside sbx |
| MCP10 Context Injection & Over-Sharing | Data from one tool or tenant leaks into another call | Per-identity tool and target scoping; ExtMCP PII masking (Presidio) on results; separate routes or backends per trust zone | The agent's context window is beyond gateway reach |

### 7. Guardrail catalogue by maturity

**Built-in / GA in 1.6:**
- CEL tool, prompt and resource authorization with list filtering.
- JWT/OAuth MCP auth and protected-resource metadata.
- Backend auth: header injection, token exchange, jwtSign.
- Local rate limits (keyed in 1.6) and global rate limits through an Envoy RLS.
- ExtMCP processor framework with failure modes.
- TLS to remote targets; CORS/CSRF.
- Access logs, OTel traces and metrics, `agctl` tracing.
- LLM-side prompt guards (regex with Luhn-checked card detection, OpenAI moderation, Bedrock, Model Armor, webhook), including tool-input and tool-output scopes on LLM traffic.\[16\]\[17\]

**Experimental / version-sensitive:**
- Gateway API experimental-channel filters.
- An in-process CEL MCP guardrail processor (`kind: expression`, which sees `mcp.params`/`mcp.result`). It shows up in a community demo against a specific build;\[63\] I did not find it in the 1.6 K8s docs.
- Argument-based CEL authorization (broken per #3092).
- Stateless MCP 2026-07-28 interplay.

**Custom code you write (an ExtMCP gRPC service, Python or Go, about 300 lines to start):**
- Argument validators.
- A tool-manifest pinning and rug-pull detector, backed by a ConfigMap of SHA-256 hashes per target and tool.
- A description and response injection scanner. It can call Presidio, Llama Guard / Prompt Guard through vLLM or Ollama in the cluster, a Lakera API or NeMo Guardrails as sub-services.
- Response PII masking.
- Audit metadata emission.

Add a fixture "evil" MCP server with poisoned descriptions, a rug-pull toggle and injection payloads in results.\[4\]

### 8. Phased roadmap

| Phase | Build | Attack demo (OWASP) | Expected result / evidence |
|---|---|---|---|
| 0 Baseline | Current setup: sbx auto MCP gateway plus host stdio servers plus the evil server | Poisoned `add` tool reads `~/.ssh` (MCP03);\[4\] PAT in `.mcp.json` leaked through output (MCP01); `rm -rf` arg (MCP05); injected issue text (MCP06); ad-hoc server (MCP09) | Attacks succeed; minimal logs |
| 1 Gateway in path | Kind plus agentgateway, federated backend, port-forward, sbx allow `localhost:8080` only, strip other MCP entries | Shadow server (MCP09); direct remote call | 403 in `sbx policy log`; every call in gateway access logs and traces (MCP08) |
| 2 AuthN + creds | JWT Strict, credentials moved to Secrets and injected, agent gets a placeholder or short-lived token | Token theft, unauthenticated call (MCP01/07) | 401 without token; no PAT inside the VM |
| 3 Tool RBAC + rate limits | Allowlist CEL per target and identity, keyed local rate limit | Call `delete_*` or a hidden tool (MCP02); loop or DoS | `Unknown tool`; 429 |
| 4 ExtMCP request guards | Argument validator, FailClosed | Command or path injection (MCP05) | JSON-RPC `-32001`, rule ID in logs |
| 5 ExtMCP response guards | Pinning, rug-pull detection on `tools/list`; injection and PII scan on results | Rug pull on second load, poisoned description (MCP03);\[4\] injected result (MCP06); PII (MCP10) | Tool stripped or denied; redacted output; trace span for each guard call |
| 6 Platform hardening | NetworkPolicy, pod securityContext, digest pins, Kyverno signature check, stdio servers moved into pods | Malicious image (MCP04); SSRF egress | Admission denial; dropped egress |
| 7 Observability | OTel collector, Tempo/Jaeger, Prometheus, Grafana dashboard: blocks per OWASP ID, latency added per guard | n/a | Before/after scoreboard |

**Measure:**
- Attack success rate per test case, before and after.
- p50/p95 added latency per guardrail. Watch the 10s ext-proc default timeout.
- False positives on a benign task suite.
- Tool-catalog size exposed to the model (context reduction).
- Time-to-detect from trace and log.

**Repo layout:**

```
mcp-guardrails-lab/
  cluster/kind-config.yaml  cluster/install.sh (pinned versions)
  gateway/{gateway,route,backend}.yaml
  policies/phase-{2..5}/*.yaml        # one AgentgatewayPolicy per guardrail
  guardrails/extmcp/{server.py,ext_mcp.proto,pins.yaml,Dockerfile}
  mcp-servers/{everything,filesystem,evil-server}/
  sandbox/kit/ (spec.yaml, files/home/.claude.json, managed-settings.json)
  attacks/MCP0X-*/{prompt.md,expected.json}  attacks/run.sh (Inspector CLI + claude -p)
  observability/{otel-collector,grafana-dashboards}/
  docs/threat-model.md (your OWASP mapping)
```

## Caveats

- **Version churn is the main risk.** CRD paths moved between kgateway 2.x, agentgateway 1.2–1.6 and the 1.6 docs. Policy-conflict semantics, CRD defaults and streaming fail-closed behavior all changed in 1.6. Pin chart, image, Gateway API and sbx versions, and re-validate after each upgrade with `agentgateway --validate-only` (standalone) or controller status conditions.
- **Unverified items:**
  - Kubernetes-mode stdio targets.
  - The exact 1.6 YAML for `mcp.methodName`-keyed rate limits.
  - Whether sbx custom-secret injection applies to `localhost` destinations.
  - Which mechanism reliably disables the sbx auto MCP gateway in your sbx version.
  - cloud-provider-kind CRD interplay.
  - Claude Code's support for the stateless MCP revision.
- **The gateway does not sanitize meaning.** Response-side prompt-injection detection is probabilistic, so the demo should say "reduced", not "blocked", for MCP06. Your ExtMCP service becomes a trusted component that can rewrite params, so test it like security code.\[15\]
- **Laptop scale.** One replica keeps local rate limits accurate. They multiply with replicas.\[64\]\[65\]\[66\]
- **The OWASP MCP Top 10 is beta.** ToolMesh reports the next release is scheduled for October 2026, so expect wording and ordering changes, and version-stamp your mapping.

## Decisions / Questions for You

1. **Identity model.** A static JWT minted locally (simplest), or Keycloak in Kind (shows OAuth discovery and the MCP spec flow)?
2. **Stdio servers.** Move them into pods behind an adapter (recommended), or keep a few on the host through the Docker MCP Gateway as a static target?
3. **Exposure.** port-forward (fastest) or NodePort with `extraPortMappings` (persistent)?
4. **Classifier for MCP06.** Local (Llama Guard / Prompt Guard on Ollama, offline-friendly) or a SaaS such as Lakera (better detection, adds egress)?
5. **LLM traffic.** Should Claude Code's model traffic also go through agentgateway, so you get LLM-side prompt guards with `ToolOutput` scope and cost telemetry? Check the 1.6 Anthropic→Responses conversion change first. It only applies when an Anthropic Messages request is routed to a non-Anthropic provider.\[10\]\[17\]
6. **Blog post access.** Can you share the post's text? I couldn't read it, and specifics of your v3 kit, such as whether it already strips the `mcp-gateway` entry, change step 4.3.

## Sources

1. [Version support](https://agentgateway.dev/docs/kubernetes/main/reference/versions/)
2. [Docker Sandboxes](https://varlock.dev/sandboxes/docker-sandboxes/)
3. [MCPTox: A Benchmark for Tool Poisoning Attack on Real-World MCP Servers](https://arxiv.org/pdf/2508.14925)
4. [GitHub - invariantlabs-ai/mcp-injection-experiments: Code snippets to reproduce MCP tool poisoning attacks. · GitHub](https://github.com/invariantlabs-ai/mcp-injection-experiments)
5. [MCPSecBench: A Systematic Security Benchmark and Playground for Testing Model Context Protocols](https://arxiv.org/pdf/2508.13220)
6. [Docker Sandbox Kit Spec: Authority as Code](https://www.docker.com/blog/docker-sandbox-kit-spec/)
7. [Release v1.6.0-alpha.1 · agentgateway/agentgateway](https://github.com/agentgateway/agentgateway/releases/tag/v1.6.0-alpha.1)
8. [Release v1.6.0-rc.1 · agentgateway/agentgateway](https://github.com/agentgateway/agentgateway/releases/tag/v1.6.0-rc.1)
9. [Agentgateway v1.3.0: LLM Consumption, Reimagined](https://agentgateway.dev/blog/2026-06-17-agentgateway-v1.3.0/)
10. [Releases · agentgateway/agentgateway](https://github.com/agentgateway/agentgateway/releases)
11. [kgateway v2.2 release blog](https://kgateway.dev/blog/kgateway-v2.2-release-blog/)
12. [Set up MCP auth](https://agentgateway.dev/docs/kubernetes/latest/documentation/mcp/auth/setup/)
13. [7 practical MCP policies with agentgateway | Learn Cloud Native](https://learncloudnative.com/blog/2026-08-14-7-practical-mcp-policies-agentgateway)
14. [agentgateway on Kubernetes: Control Which MCP Tools Agents Use](https://blog.kubesimplify.com/controlling-mcp-tools-with-agentgateway-on-kubernetes)
15. [About MCP guardrails](https://agentgateway.dev/docs/kubernetes/latest/mcp/guardrails/about/)
16. [chore(deps): Update dependency agentgateway/agentgateway to v1.5.0 by renovate\[bot\] · Pull Request #41 · fjudith/salt-devops-tools](https://github.com/fjudith/salt-devops-tools/pull/41)
17. [Release notes](https://agentgateway.dev/docs/kubernetes/latest/release-notes/release-notes/)
18. [Feature: A2A protocol guardrails (parity with MCP ExtMCP) · Issue #3610 · agentgateway/agentgateway](https://github.com/agentgateway/agentgateway/issues/3610)
19. [What's new in Docker Sandboxes 0.38.0](https://www.ajeetraina.com/whats-new-in-docker-sandboxes-0-38-0/)
20. [docs/content/manuals/ai/sandboxes/mcp-gateway.md at main · docker/docs](https://github.com/docker/docs/blob/main/content/manuals/ai/sandboxes/mcp-gateway.md)
21. [Experimenting with Gateway API using kind](https://kubernetes.io/blog/2026/01/28/experimenting-gateway-api-with-kind/)
22. [Experimenting with Gateway API using kind · CloudScoop](https://www.cloudscoop.io/updates/kubernetes-2026-01-28-experimenting-with-gateway-api-using-kind)
23. [Tool access](https://agentgateway.dev/docs/kubernetes/latest/documentation/mcp/tool-access/)
24. [API reference (single page)](https://agentgateway.dev/docs/kubernetes/latest/reference/api/)
25. [Stdio](https://agentgateway.dev/docs/standalone/latest/integrations/mcp/servers/stdio/)
26. [OpenAPI](https://agentgateway.dev/docs/standalone/latest/mcp/connect/openapi/)
27. [Stateful MCP](https://agentgateway.dev/docs/kubernetes/latest/documentation/mcp/session/)
28. [feat(deps): update vendir https://github.com/agentgateway/agentgateway (v1.5.0 → v1.6.0) by sticky-gecko\[bot\] · Pull Request #644 · home-operations/k8s-schemas](https://github.com/home-operations/k8s-schemas/pull/644)
29. [Install agentgateway](https://agentgateway.dev/docs/kubernetes/latest/documentation/quickstart/install/)
30. [Global rate limiting](https://agentgateway.dev/docs/kubernetes/2.2.x/security/rate-limit-global/)
31. [agentgateway on Kubernetes: A Platform Engineer’s Deep Dive](https://medium.com/@simonjday/agentgateway-on-kubernetes-a-platform-engineers-deep-dive-c1cc7fab4d94)
32. [AgentGateway — For MCP implementation](https://medium.com/@krishnan.srm/agentgateway-for-mcp-implementation-cb5fe744df08)
33. [Virtual MCP](https://agentgateway.dev/docs/kubernetes/latest/documentation/mcp/virtual/)
34. [Dynamic MCP](https://agentgateway.dev/docs/kubernetes/2.2.x/mcp/dynamic-mcp/)
35. [MCP Multiplexing with AgentGateway](https://agentgateway.dev/blog/2026-02-20-mcp-multiplexing-tool-access-agentgateway/)
36. [MCPGuard : Automatically Detecting Vulnerabilities in MCP Servers](https://arxiv.org/pdf/2510.23673)
37. [MCP connectivity](https://agentgateway.dev/docs/standalone/latest/documentation/mcp/)
38. [Authorization - Model Context Protocol](https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization)
39. [JWT auth for services](https://agentgateway.dev/docs/kubernetes/latest/documentation/mcp/mcp-access/)
40. [Rate limiting for MCP](https://docs.solo.io/agentgateway/kubernetes/latest/mcp/rate-limit/)
41. [Rate limiting for MCP](https://agentgateway.dev/docs/kubernetes/1.1.x/mcp/rate-limit/)
42. [Rate limiting for MCP](https://agentgateway.dev/docs/kubernetes/1.3.x/mcp/rate-limit/)
43. [Set up MCP guardrails](https://agentgateway.dev/docs/kubernetes/main/mcp/guardrails/setup/)
44. [Routing and load balancing · Issue #4 · UNDP-Data/geo-careatlas](https://github.com/UNDP-Data/geo-careatlas/issues/4)
45. [mcp-sandbox Part 3: guardrailed MCP platform on EKS (parent spec) · Issue #10 · raghav19/engineersdaybook](https://github.com/raghav19/engineersdaybook/issues/10)
46. [Network Policy](https://dockerlabs.collabnix.com/docker-workshop/lab8/projects/network-policy)
47. [Security risk of the MCP gateway exposing all host MCP servers unconditionally · Issue #612 · docker/sbx-releases](https://github.com/docker/sbx-releases/issues/612)
48. [sbx mcp](https://docs.docker.com/reference/cli/sbx/mcp/)
49. [Claude Code Docker Setup: Containers and Dev Environments (2026)](https://fast.io/resources/claude-code-docker-container-setup-guide/)
50. [Docker Sandboxes (docker-sbx) - Agent Sandbox - Kubernetes](https://agent-sandbox.sigs.k8s.io/docs/use-cases/examples/docker-sbx/)
51. [GitHub - protyposis/sbx-kits: Kits for Docker Sandbox · GitHub](https://github.com/protyposis/sbx-kits)
52. [Docker Sandboxes release notes](https://docs.docker.com/ai/sandboxes/release-notes/)
53. [MCP Explained in 2026: Model Context Protocol, Servers, Tools, Security & How It Works - GyanAangan Blog](https://gyanaangan.in/blog/mcp-explained-in-2026-model-context-protocol-servers-tools-security-how-it-works)
54. [Model Context Protocol prepares to break with its stateful past](https://www.theregister.com/devops/2026/07/23/model-context-protocol-prepares-to-break-with-its-stateful-past/5276722)
55. [MCP policy reference](https://docs.docker.com/ai/sandboxes/governance/reference/mcp-policy)
56. [GitHub - docker/mcp-gateway: docker mcp CLI plugin / MCP Gateway · GitHub](https://github.com/docker/mcp-gateway)
57. [MCP Security: Risks, Challenges, and How to Mitigate](https://www.docker.com/blog/mcp-security-explained/)
58. [MCP gateway - Docker Sandboxes](https://docs.docker.com/ai/sandboxes/mcp-gateway/)
59. [Parasites in the Toolchain: A Large-Scale Analysis of Attacks on the MCP Ecosystem](https://arxiv.org/pdf/2509.06572)
60. [A Formal Security Framework for MCP-Based AI Agents: Threat Taxonomy, Verification Models, and Defense Mechanisms](https://arxiv.org/pdf/2604.05969)
61. [MCP Tool Poisoning: Adversarial Hijacking of AI Agent Workflows](https://labs.cloudsecurityalliance.org/research/csa-research-note-mcp-tool-poisoning-ai-agent-exfiltration-2/)
62. [What is an MCP Rug Pull Attack? Threats & Prevention](https://securew2.com/blog/mcp-rug-pull-attack)
63. [GitHub - themsquared/tool-call-guardrails · GitHub](https://github.com/themsquared/tool-call-guardrails)
64. [Local rate limiting](https://agentgateway.dev/docs/kubernetes/latest/security/rate-limit-http/)
65. [Rate limiting](https://agentgateway.dev/docs/standalone/latest/documentation/configuration/resiliency/rate-limits/)
66. [Agentgateway rate limiting for agents](https://learncloudnative.com/blog/2026-07-16-agentgateway-rate-limiting)