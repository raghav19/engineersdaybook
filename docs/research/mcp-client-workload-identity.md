# Workload identity for the MCP client in the sandbox microVM

Question: What is the best practice to give the MCP client (the agent in the sandbox microVM) a workload identity, so that the gateway sees which machine calls, and not only which user? Where should the SVID and the user JWT live?

Source: the MCP authorization specification (read on GitHub), the Envoy credential injector API (read on GitHub), the SPIFFE Workload Endpoint specification (read on GitHub), and search results for RFC 8705 and the SPIRE Envoy tutorial. Research date: 2026-10-23. Local repo state: `main` at `77a8744`.

Evidence tags: **[mcp]** is the MCP authorization spec, `modelcontextprotocol/modelcontextprotocol` on GitHub. **[envoy]** is `credential_injector.proto` in `envoyproxy/envoy`. **[spiffe]** is the SPIFFE Workload Endpoint spec. **[search]** is a paraphrase from a search result for a page I could not open. **[repo]** is a file in this repo. **[inference]** is my own conclusion.

## Verdict

1. Keep two identities and join them at the gateway. The SVID says which workload calls. The JWT says which user calls. The gateway requires both. [inference]
2. Envoy in the microVM is the right holder of the SVID. It fetches the SVID from the SPIRE agent over SDS, so the SVID key stays in Envoy and not in the coding agent. [search]
3. A token bound to a client certificate is the standard way to stop a stolen token (RFC 8705). It conflicts with short-lived SVIDs, because each new certificate has a new hash. [search] [inference]
4. A simpler join that survives rotation: put the GitHub id in the SPIFFE ID of the microVM, and make the gateway compare it with the GitHub id in the JWT. The alias already holds the GitHub id. [repo] [inference]
5. Do not use the Envoy credential injector for the user JWT without care. Its own text says it is for workload authentication and "does not handle end user authentication". [envoy]

## 1. What the sources say

| Claim | Source |
|---|---|
| The MCP client obtains the token. Servers must accept only tokens issued for them (audience check). Tokens that leak are a named risk: "Attackers who obtain tokens stored by the client ... can access protected resources". | [mcp] `docs/specification/2025-06-18/basic/authorization.mdx`, "Token Theft" |
| Authorization servers "SHOULD issue short-lived access tokens to reduce the impact of leaked tokens". Clients and servers "MUST implement secure token storage". | [mcp] same section |
| Token passthrough is forbidden. An MCP server "MUST NOT" pass on the token it received. | [mcp] same file, "Token Passthrough" section |
| The SPIRE agent serves Envoy over SDS on the same Unix socket as the Workload API. Envoy asks for the X.509-SVID by the SPIFFE ID as the secret name. The SPIRE server needs a registration entry for each Envoy. | [search] https://spiffe.io/docs/latest/microservices/envoy-x509/readme/ |
| The Workload Endpoint does not authenticate the caller with a secret. It uses out-of-band checks "such as kernel introspection". The service answers `PermissionDenied` when no identity matches the caller. | [spiffe] `standards/SPIFFE_Workload_Endpoint.md`, section 5 |
| The Envoy credential injector puts a Basic or Bearer credential in the `Authorization` header, from an SDS secret. It is "intended to be used for workload authentication". "this filter does not handle end user authentication". It has an `overwrite` option. | [envoy] `api/envoy/extensions/filters/http/credential_injector/v3/credential_injector.proto` |
| With RFC 8705, the token holds `cnf` with `x5t#S256`, the hash of the client certificate. The resource server compares it with the certificate of the mTLS connection and rejects a mismatch. Only the holder of the private key can use the token. | [search] RFC 8705 section 3, https://www.rfc-editor.org/rfc/rfc8705.html |
| Today the client reaches the ingress at L4, with a JWT and no SVID. The JWT and the MCP config stay on the host. The agent in the microVM does not hold the token. | [repo] `docs/arch.md` sections 3 and 5 |
| The alias of the node holds the GitHub id: `spiffe://mcp.local/microvm/<github id>`. The `tool-rbac` rule uses the GitHub id of the JWT. | [repo] `.sbx/agent/spire.py`, `docs/arch.md` |

## 2. Options for the JWT

| Option | How | Good | Bad |
|---|---|---|---|
| A. Keep the JWT as is | The JWT stays on the host. Envoy only adds the SVID and mTLS. | Smallest change. No new place for the token. | A stolen JWT still works from any machine that can also present a valid SVID. The two are not tied. |
| B. Match the two identities at the gateway | The SPIFFE ID of the Envoy contains the GitHub id. The gateway rule requires the GitHub id of the JWT to equal the one in the SPIFFE ID. | Survives SVID rotation. Uses what exists (the alias). No change to Dex. | The match is a gateway rule that you write and test. |
| C. Certificate-bound token (RFC 8705) | Dex issues a JWT with `cnf.x5t#S256`. The gateway compares it with the client certificate. | The standard answer to a stolen token. | Each SVID rotation changes the hash, so the token must be re-issued each time. Dex support was not checked. |
| D. Envoy injects the JWT | Envoy reads the JWT from a file as an SDS secret and sets the header. The agent never sees it. | The JWT is out of the agent's reach. | The Envoy docs say the filter is for workload authentication, not for end users. The token expires, so a refresh path is needed. |

## 3. Recommendation

1. Start with A and B together: the workload entry, Envoy with the SVID, mTLS to the ingress, and the gateway rule that matches the GitHub id of the SPIFFE ID to the GitHub id of the JWT. [inference]
2. Run Envoy as its own user. The agent socket must be reachable only by that user. [spiffe] [inference]
3. Keep the JWT where it is until the first two parts work. Then decide on D. [inference]
4. Treat C as a later hardening step. It needs an identity provider that issues bound tokens. [inference]

## Gaps and conflicts

- The MCP site, the Envoy docs and the IETF pages returned HTTP 403. I read the MCP spec, the Envoy proto and the SPIFFE spec from GitHub. The Envoy proto is the API text, not the docs page. The RFC 8705 and SPIRE Envoy tutorial claims come from search results.
- I did not check DPoP (RFC 9449), the other sender-constrained token method.
- I did not check whether Dex can issue `cnf` claims, or whether agentgateway can compare `source.spiffeId` with a JWT claim in one CEL rule. The existing rules use both inputs separately.
- "Each SVID rotation changes the certificate hash" is my inference from how certificates work.
- Where the MCP call starts (host or microVM) is not settled in `docs/arch.md`. This note assumes a client in the microVM that reaches the gateway through Envoy.
