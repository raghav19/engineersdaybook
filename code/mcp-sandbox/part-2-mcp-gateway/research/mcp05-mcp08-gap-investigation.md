# Can agentgateway close MCP05 and MCP08? (Part 2 research)

Checked 2026-09-14, against agentgateway's own primary sources: the `agentgateway/agentgateway` GitHub repo (docs source, proto schema, code, GHSA advisories) and the rendered docs at `agentgateway.dev/docs`. Latest tagged release at time of writing: **v1.5.0** (published 2026-08-27); `main` is 128 commits ahead of that tag as of this check, and some findings below come from `main`-only, unreleased behavior — flagged explicitly where that's the case.

Builds on prior research already established for this series (not re-derived here): `mcpAuthorization`'s two enforcement points (discovery-time `tools/list` filtering, call-time `tools/call` re-check) and its identity+target authorization model, captured in project memory as `agentgateway-mcp-policy-model`.

---

## Question 1: Can agentgateway policy mitigate MCP05 (Command Injection & Execution)?

### Verdict: no, not with `mcpAuthorization` today — and the one mechanism that *could* do it is a component you build yourself, not a switch you flip. Name MCP05 as an accepted gap for Part 2's actual two servers.

### What's mechanically true

**1. The CEL *functions* needed exist — the *data* doesn't reach the rule.**

agentgateway's CEL environment genuinely has the string-matching surface a coarse mitigation would need: `contains`, `matches` (regex), `startsWith`, `endsWith`, plus a `regexReplace` helper and the full Go `cel-go` strings extension (`replace`, `split`, `substring`, etc.) — confirmed straight from the source-of-truth function table:
`agentgateway/agentgateway` → `schema/cel-functions.md` (auto-generated, last touched alongside the CEL schema on 2026-08-31).

But the actual argument *value* of a tool call is not present in the CEL context at the point `mcpAuthorization` rules evaluate. The project's own architecture doc says this in plain language:

> "Request-time CEL also includes `mcp.methodName` alongside the identity fields (`mcp.tool`, `mcp.prompt`, `mcp.resource`, `mcp.task`)... For post-request logging, tracing, and metrics CEL, MCP tool calls also expose payload fields such as `mcp.sessionId`, `mcp.tool.arguments`, `mcp.tool.result`, and `mcp.tool.error` — **these remain absent during RBAC evaluation**."
> — `agentgateway/agentgateway/architecture/cel.md`

The generated schema confirms the same boundary field-by-field: `mcp.tool.name` and `mcp.tool.target` are documented as available at request time; `mcp.tool.arguments` (and `.result`/`.error`) are documented only as post-request payload fields (`schema/cel.md`). So a rule like `mcp.tool.arguments.command.contains(";")` in `mcpAuthorization` isn't a "hasn't been tried" gap — it's mechanically inert: the field simply isn't populated when the RBAC check runs, so the expression fails to evaluate against real data at the moment it matters (before the call is forwarded).

This boundary is actively maintained, not neglected: a PR merged 2026-08-31 (`mcp: populate mcp.methodName during RBAC evaluation`, #3197 — not yet in the v1.5.0 tag) deliberately *added* one more identity field to the pre-request CEL context, while leaving `mcp.tool.arguments` still explicitly post-request-only. That's a team actively curating what's visible pre-request, and choosing not to expose argument values there (yet).

**2. There's no built-in "regex guard" for MCP traffic — only for LLM traffic.**

agentgateway does ship a genuinely built-in, no-external-server regex content filter — but it's scoped to `ai`-backend (LLM chat) traffic, via `promptGuard`/`RegexRules` with a `BuiltinRegexRule` enum (`SSN`, `CREDIT_CARD`, `PHONE_NUMBER`, `EMAIL`, `CA_SIN`) or a custom `regex` string, action `MASK`/`REJECT`/`AUDIT` (`agentgateway.dev/docs/kubernetes/latest/llm/guardrails/regex/`; confirmed in the proto schema around the `Ai`/`GuardrailBackend` messages in `crates/protos/proto/resource.proto`). This is real, but it inspects LLM prompts/completions, not MCP `tools/call` arguments — it is not wired into the MCP path at all.

For MCP traffic specifically, the schema is unambiguous that there is exactly one processor kind, and it is not a content filter — it's a delegation point:

> "McpGuardrails is a backend-phase policy for MCP traffic: an ordered chain of policy processors. **Today only the `remote` processor is defined** — a custom gRPC policy server (the ExtMcp service) modeled on Envoy ext_authz."
> "Processor is a single policy processor. **Today only `remote` is defined**."
> — `crates/protos/proto/resource.proto`, `McpGuardrails`/`Processor` messages

So "MCP guardrails" (ExtMCP) is a real, documented, shipped feature (`AgentgatewayPolicy` CRD wiring a `backend.mcp.guardrails.processors[].remote.backendRef` to a gRPC service, with `failureMode: FailClosed|FailOpen` and a `methods` map keyed by JSON-RPC method → phase — `agentgateway.dev/docs/kubernetes/main/mcp/guardrails/{about,setup}/`) — but the actual inspection logic (a shell-metacharacter regex check, in this case) is code *you* write and host, implementing the `ExtMcp` gRPC contract (`CheckRequest{method, tool, params, headers}` → `Pass`/`Mutate`/`Deny`). The docs' own demo server is explicitly labeled "sample server demonstration only," reinforcing that this is a build-it-yourself integration point, not a toggle.

**3. This exact failure class has already bitten agentgateway once, for real.**

Not in the Part 2 architecture's own path, but worth citing as evidence the surface is real: `CVE-2026-29791` / `GHSA-v2x6-wwfw-r2rq`, "Missing parameter sanitization in MCP to OpenAPI conversion" (medium, fixed in v0.12.0) — agentgateway's MCP-to-OpenAPI bridge feature took `tools/call` arguments and interpolated them unsanitized into outbound path/query parameters and headers, letting a malicious argument inject additional parameters/headers. That's the same shape of bug MCP05 describes, just one hop earlier (into agentgateway's own outbound HTTP construction rather than into `github-mcp-server`'s or `flux-operator-mcp`'s internal command construction) — and it's a reminder that "arguments pass through un-sanitized by default" is agentgateway's own stated design, confirmed by its own incident history, not just an inference from missing docs. Part 2 doesn't use the MCP-to-OpenAPI feature, so this specific CVE isn't directly exploitable in that architecture — cite it as corroboration, not as a live finding against Part 2's own config.

### What's honestly out of reach, even with ExtMCP built

Even a working, hand-built ExtMCP shell-metacharacter checker only ever sees **the literal arguments the MCP client sent in the `tools/call` request**. It has no visibility into what `github-mcp-server`'s or `flux-operator-mcp`'s own Go code does *after* accepting those arguments — e.g., content the server itself fetches (an issue body, a file, a Flux resource's status) and later feeds into its own internal command/query construction never passes back through the gateway as a "tool call argument" at all. That's the same class of blind spot already named for `mcpAuthorization` in this series' prior research (policy sees call/argument names, not a downstream server's internal code paths) — ExtMCP narrows it (it can now see argument *values*, not just names) but doesn't remove it. A regex check on argument strings is a real, coarse control against injection riding literally inside a client-supplied argument; it is not sanitization of untrusted content flowing into a server's own internal command construction, which is what MCP05's own wording actually describes.

### Recommendation for the write-up

State plainly: **MCP05 is a named, accepted gap for Part 2's two servers.** `mcpAuthorization` cannot see argument values at all today (mechanically confirmed, not assumed) — no CEL rule against it is possible, coarse or otherwise. A real (if coarse) mitigation is buildable via ExtMCP, but it requires standing up and operating an external gRPC service — sized more like "a small sidecar you write and maintain" than "a policy you turn on," and even then it only covers injection payloads that ride inside argument values the client sends, not the server's own internal handling of fetched content. Worth a one- or two-line honest callout in Part 2's OWASP table, matching Part 1's discipline of naming non-fits explicitly (MCP05/MCP09 there) rather than padding coverage.

---

## Question 2: Can agentgateway provide the audit/telemetry MCP08 names?

### Verdict: yes, largely — structured, MCP-aware decision logging is a real, built-in, config-only capability, and `kubectl logs` on the agentgateway pod is genuinely sufficient to capture it for a POC blog post. The one piece that's honestly short of OWASP's own wording is "immutable" — stdout logs are structured and real, but not immutable/durable beyond the pod's lifetime without one extra step.

### What's mechanically true

**Structured, MCP-specific logging is native, not bolted on.** agentgateway logs every request to stdout by default, and for MCP traffic the fields are genuinely protocol-aware (not generic HTTP access-log fields dressed up). A real example line from the docs:

```
protocol=mcp mcp.method.name=tools/call mcp.target=everything gen_ai.tool.name=echo mcp.session.id=6b497ee9-3710-428a-96d2-31ebeab73dcd trace.id=286cb6c44380a45e1f77f29ce4d146fd span.id=f7f30629c29d9089
```
— `agentgateway.dev/docs/standalone/main/mcp/mcp-observability/`

The schema (`schema/cel.md`) backs this with a documented `Logging` policy: `filter` (a CEL predicate to drop uninteresting lines), and `fields.add`/`fields.remove` (CEL-expression-named fields you opt into or strip), plus an optional `otlp_access_log` block to ship the same structured lines to an OTLP-compatible collector (`crates/protos/proto/resource.proto`, `TrafficPolicySpec.Logging` message). This is a policy object, attachable the same way as `mcpAuthorization` — config, not external tooling.

**Identity (JWT subject) is addable, not default.** `jwt` is one of the top-level CEL variables available in the `Logging` policy's evaluation context (same variable table cited in the CEL variables/functions reference), so a field like `tool_caller: 'jwt.sub'` is a one-line addition to the `Logging.fields.add` list. It is *not* in the example default log line above — that line is the "legacy/human-oriented preset," and identity has to be opted in explicitly.

**Tool arguments are addable too, with a stated cost.** Same mechanism: `mcp.tool.arguments` (post-request-only, as established in Q1) is exactly the kind of field the `Logging` policy's opt-in `fields.add` exists for — e.g. `tool_args: 'mcp.tool.arguments'`. The docs flag the honest tradeoff directly: reading tool-call arguments/results has a real performance cost on large payloads because the gateway has to hold the body to inspect it, so the stated guidance is to apply that field addition only on the routes that need argument-level evidence, not gateway-wide (`agentgateway.dev/docs/kubernetes/latest/llm/observability/`, describing the equivalent `llm.toolCalls` case — same mechanism, same caveat, applies to `mcp.tool.arguments`).

**MCP-specific metrics exist as a volume signal, not a decision record.** `mcp_requests_total` is a counter labeled by `server`, `method` (`tools/call`/`tools/list`), `resource`, and `resource_type` — useful for "how many calls happened," not "who called what and was it allowed," since it carries no identity or outcome label.

**Traces correlate, they don't replace logs.** OTLP tracing (`tracing.otlpEndpoint` + `randomSampling`, viewable in Jaeger) produces `call_tool`-shaped spans whose `trace.id`/`span.id` show up in the same stdout log line quoted above — genuinely useful for stitching a multi-hop demo narrative together after the fact, but the actual per-call decision content still lives in the log line/OTLP log export, not the trace.

**No single documented "was this allowed or denied" field.** Searching the generated CEL schema turns up no `authz.decision`/`mcp.authorized` field. The practical way to reconstruct a deny in the log is indirect: `mcp.tool.name`/`mcp.tool.target` are populated pre-request (so they're present on denied calls too, since RBAC evaluates against exactly those fields), and a denied call's `response.code` / resulting JSON-RPC error would show the rejection. This specific status-code/error-body shape wasn't pinned down verbatim in the docs retrieved for this pass — treat it as "confirm empirically" rather than "documented fact": trigger one real denied call in the POC and capture what the log line actually shows, the same evidence-over-assertion discipline Part 1 already used.

### What's buildable at POC scale (the actual ask: "capture real decision logs as evidence")

For a single ephemeral k3s VM, **`kubectl logs` on the agentgateway pod, with a small `Logging` policy addition, is genuinely enough** — no collector, no SIEM, no Loki/Tempo stack required to satisfy the ask:

1. Attach a `Logging` policy (flat YAML or `AgentgatewayPolicy` CRD) adding three fields: `tool_caller: 'jwt.sub'`, `tool_args: 'mcp.tool.arguments'` (only on the routes fronting the two demo MCP servers, per the perf caveat above), and `status: 'response.code'`.
2. During the live demo run, capture stdout directly: `kubectl logs -f deployment/<agentgateway-proxy> -n <ns> | tee part-2-run-log.txt` — the same "capture-then-verify" pattern Part 1 already used for GitHub API evidence, just pointed at the gateway pod instead of `gh api`.
3. That captured file *is* the evidence artifact for the blog post: structured, per-call lines naming tool, target, caller, arguments, and outcome — exactly the fields MCP08's own wording asks for ("detailed logs of tool invocations, context changes, and user-agent interactions").

The full documented "OTel stack" (`agentgateway.dev/docs/kubernetes/latest/observability/otel-stack/`: OTel Collector + Prometheus + Grafana Loki + Grafana Tempo + Grafana dashboards) is real and legitimately deployable in the same k3s cluster, but sizing it for this POC would be overkill relative to the actual ask — it's the right answer for "operate this gateway in production," not for "get one clean run of decision logs for a blog post."

### The one honest gap: "immutable"

OWASP's MCP08 wording specifically asks for "immutable audit trails." Captured stdout piped to a file is real and structured, but it is neither immutable nor durable beyond the demo session — a pod restart wipes the container's stdout scrollback, and a locally saved `.txt` file is trivially editable. Closing that specific word honestly would need the `otlp_access_log` export pointed at an append-only sink (even just an object-store bucket, or the OTel stack's Loki with retention/immutability settings) — buildable, and worth naming as the one genuine step beyond "`kubectl logs` is enough" if the write-up wants to claim the full OWASP wording rather than "structured decision logging, captured live."

### Recommendation for the write-up

Lead with the real win: MCP-aware structured logging (tool, target, session, and — once added — caller identity and arguments) is a config-only, built-in capability, confirmed against the actual schema rather than assumed. Show the captured `kubectl logs` output as the evidence artifact, sized correctly for a one-VM POC. Name "immutable" as the one word in OWASP's own description that isn't satisfied by the POC-sized approach, and say what would close it (OTLP export to durable storage) without actually building that for this series — same restraint Part 1 showed by not over-building past what the demo needed.

---

## Sources consulted directly (primary)

- `agentgateway/agentgateway` GitHub repo, `main` branch, checked 2026-09-14:
  - `architecture/cel.md` — CEL request-time vs. post-request field boundary (verbatim quote above)
  - `schema/cel.md` — full generated CEL variable schema (`mcp.*`, `Logging` policy variables, etc.)
  - `schema/cel-functions.md` — full CEL function/string-extension list
  - `crates/protos/proto/resource.proto` — `McpGuardrails`/`Processor` message (MCP guardrails' single `remote` processor kind), `GuardrailBackend`/`RegexRules`/`BuiltinRegexRule` (LLM-only built-in regex guard), `TrafficPolicySpec.Logging`/`OtlpAccessLog` (access-log policy schema)
  - `examples/mcp-authorization/README.md` — the `mcpAuthorization` worked example (the `echo`/`get-sum`/`get-env` rules already known from prior research)
  - GitHub Security Advisories: `GHSA-v2x6-wwfw-r2rq`/CVE-2026-29791 (missing parameter sanitization in MCP-to-OpenAPI conversion, fixed v0.12.0); `GHSA-mvgg-jvj2-4frq` (stateful MCP session/route policy mismatch, fixed v1.4.0 — worth pinning Part 2's deployment to v1.4.0+, ideally the current v1.5.0 tag, for this reason alone)
  - Release/tag metadata: latest tag `v1.5.0` (2026-08-27); `main` 128 commits ahead as of this check, including the `mcp.methodName`-during-RBAC change (#3197, merged 2026-08-31, not yet in a tagged release)
- `agentgateway.dev/docs/...` (rendered docs, both `standalone` and `kubernetes` doc trees):
  - `standalone/main/mcp/mcp-authz/`, `kubernetes/latest/reference/cel/`, `standalone/latest/reference/cel/variables/` — CEL/`mcpAuthorization` reference pages
  - `kubernetes/latest/mcp/guardrails/about/`, `kubernetes/main/mcp/guardrails/setup/` — MCP guardrails (ExtMCP) architecture and setup, including the CRD YAML shape
  - `kubernetes/latest/llm/guardrails/regex/` — the built-in LLM-only regex guard, for contrast
  - `standalone/main/mcp/mcp-observability/`, `kubernetes/latest/llm/observability/`, `kubernetes/latest/observability/otel-stack/` — MCP/LLM observability and the optional full OTel stack guide
- Secondary corroboration, not relied on for any load-bearing claim above: `learncloudnative.com/blog/2026-08-14-7-practical-mcp-policies-agentgateway` (Peter Jausovec, 2026-08-14) independently states "Name-based CEL rules cannot decide whether `deploy` targets staging or production, nor can they remove secrets from a tool result" for the same reason found in the primary schema — used only as a sanity check against the primary-source finding, not cited as authority.
