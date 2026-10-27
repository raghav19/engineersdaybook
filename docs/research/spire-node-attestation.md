# Node attestation of the sandbox microVM with a SPIRE join token

Question: Is it in line with zero trust to attest the microVM as a node with a SPIRE join token and an alias? What does the repo do today, and what must follow so that the node identity becomes a guardrail of the gateway?

Source: SPIRE and SPIFFE documentation (fetched), NIST CSWP 20 (fetched through a search result), the repo files (read), and the live agent in the sandbox (checked). Research date: 2026-10-23. Local repo state: `main` at `77a8744`.

Evidence tags: **[spire]** is a SPIRE document on GitHub. **[spiffe]** is the spiffe.io concepts page. **[nist]** is NIST CSWP 20, which repeats the tenets of SP 800-207. **[repo]** is a file in this repo. **[live]** is something I ran in the sandbox. **[inference]** is my own conclusion.

## Verdict

1. The node attestation exists and works. The agent is healthy and its SVID rotates. [live] [repo]
2. The approach is in line with zero trust as the first control. It proves that an operator allowed the node. It does not prove the state of the node. [inference]
3. The node identity blocks no call yet. No workload entry exists. The client hop carries no SVID. No policy checks a microVM SPIFFE ID. [live] [repo]
4. Next: workload entry for Envoy, Envoy in the microVM, an SVID on the client hop, a gateway policy on the SPIFFE ID.

## 1. What the repo does today

| Claim | Source |
|---|---|
| The server accepts join tokens (`nodeAttestor.joinToken.enabled: true`). | [repo] `platform/addons/spire/spire.yaml` |
| The server API is on NodePort 30081, host port 18081. The VM reaches it as `host.docker.internal:18081`. | [repo] `platform/addons/spire/service.yaml`, `clusters/kind/kind-config.yaml`, `/etc/spire/agent.conf` |
| The host script makes a token with a TTL of 600 s and the alias `spiffe://<trust domain>/microvm/<github id>`. It writes the token with mode 600. It skips a new token while a node owns the alias and its SVID has not expired. `SPIRE_ENROLL_FORCE=1` forces a token. | [repo] [`.sbx/agent/spire.py`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/agent/spire.py) |
| The sandbox runs `enroll` at `lifecycle.initialize`. Nothing evicts the node when the sandbox ends. The folder `~/.sbx/spire` is a read-only mount. | [repo] [`.sbx/sbxenv.yaml`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/sbxenv.yaml) |
| The agent starts with `-trustBundle` and `-joinTokenFile`. The kit comment says that an agent with a valid SVID ignores the token. | [repo] [`.sbx/kits/dev-tools/dev-tools.yaml`](https://github.com/raghav19/engineersdaybook/blob/docker-sbx/.sbx/kits/dev-tools/dev-tools.yaml) |
| The agent is healthy. It loaded the SVID of `spiffe://mcp.local/spire/agent/join_token/...`. It creates the SVID of the alias and rotates both. | [live] `spire-agent healthcheck`, `~/.spire/agent.log` |
| The server port is open from the VM. | [live] TCP connect to `host.docker.internal:18081` |
| No workload receives an SVID: `spire-agent api fetch x509` returns `no identity issued`. | [live] |
| The agent has the `unix` workload attestor and serves the Workload and SDS APIs. The socket allows all users (`srwxrwxrwx`). | [repo] `/etc/spire/agent.conf`, [live] `ls -l` |

## 2. How join token attestation works

| Claim | Source |
|---|---|
| The plugin "attests a node based on a pre-shared, one-time-use join token". The server must generate the token first. | [spire] `doc/plugin_server_nodeattestor_jointoken.md` |
| The agent ID is `spiffe://<trust_domain>/spire/agent/join_token/<token>`. | [spire] same file |
| The CLI `token generate` has `-ttl` (default 600) and `-spiffeID` ("Additional SPIFFE ID to assign the token owner"). It "creates a registration entry for it". | [spire] `doc/spire_server.md` |
| `agent evict` de-attests a node by its SPIFFE ID. Evicting a join-token node also removes its `CreateJoinToken` alias entry. | [spire] `doc/spire_server.md` |
| A join token is "a pre-shared key between a SPIRE Server and Agent". It expires immediately after use. Join tokens serve when no platform can identify a node. | [spiffe] https://spiffe.io/docs/latest/spire-about/spire-concepts/ |
| The agent ID becomes the parent of the workloads that it manages. The server finds the entries of an agent by the parent ID and by the node selectors. | [spiffe] same page |
| The alias is a second SPIFFE ID of the node. The workload entries use it as their parent. One alias belongs to one GitHub id, so two microVMs of one user share it. | [inference] from the `token generate` text and `spire.py` |

## 3. Zero trust assessment

| Claim | Source |
|---|---|
| Tenet III: access is decided by dynamic policy. The policy includes the state of the client identity, the application and the requesting asset. The default is to deny all connections. | [nist] https://nvlpubs.nist.gov/nistpubs/CSWP/NIST.CSWP.20.pdf (as found by search) |
| The node proof is in line with the tenet in two ways: no network position gives trust, and each node needs an operator approval. | [inference] |
| A join token does not prove the state or the image of the node. | [inference] |
| `x509pop` attests nodes "provisioned with an x509 identity through an out-of-band mechanism". It checks the chain and a proof of possession. It gives selectors (subject CN, CA fingerprint, serial number, URI SAN, group, extension). | [spire] `doc/plugin_server_nodeattestor_x509pop.md` |
| Extension values "are only as trustworthy as the CA's issuance policy". | [spire] same file |

## 4. Workload attestation limits

| Claim | Source |
|---|---|
| The `unix` attestor gives the selectors `unix:uid`, `unix:user`, `unix:gid` and `unix:group`. | [spire] `doc/plugin_agent_workloadattestor_unix.md` |
| `unix:path` and `unix:sha256` need `discover_workload_path = true`. The default is false. | [spire] same file |
| A negative `workload_size_limit` turns off the hash. Hashing large binaries can cause denial of service. | [spire] same file |
| Every process of one user matches `unix:uid`. So Envoy must run as its own user. | [inference] |

## 5. How to state the problem in zero trust terms

| Claim | Source |
|---|---|
| Zero trust moves defenses "from static, network-based perimeters to focus on users, assets, and resources". | [nist] SP 800-207 abstract (seen in a search result, https://csrc.nist.gov/pubs/sp/800/207/final) |
| It assumes "no implicit trust granted to assets or user accounts based solely on their physical or network location" or on asset ownership. | [nist] same abstract |
| "Authentication and authorization (both subject and device) are discrete functions performed before a session to an enterprise resource is established." The subjects include end users, applications and other non-human entities. | [nist] same abstract and its scope text (search result) |
| Tenet: all communication is secured regardless of network location. The network is always considered contested. Tenet: access is granted per session. | [nist] CSWP 20 draft, https://nvlpubs.nist.gov/nistpubs/CSWP/NIST.CSWP.08042021-draft.pdf (search result) |
| SPIFFE says that "network policies that only allow traffic between particular IP addresses" struggle to scale in dynamic environments. It gives workloads short-lived identity documents so that systems can "mutually authenticate wherever they are running". It never uses the words "zero trust". | [spiffe] https://spiffe.io/docs/latest/spiffe-about/overview/ (fetched) |
| Zero trust means "eliminating implicit trust and continuously validating access based on identity, context, and risk". It assumes a breach has already occurred. | [cisa] joint guide on zero trust for OT (search result, not the maturity model) |
| Today the gateway verifies the user (JWT) and, between hops in the cluster, the workload (mTLS with an SVID). It verifies no identity for the caller machine of the client hop. | [repo] `docs/arch.md` sections 3 and 5 |
| So the gap is the workload half of the NIST sentence ("both subject and device"). The user half exists. | [inference] |

## 6. Next steps

1. Done: workload entry for Envoy. Parent: the alias. Selector: `unix:user:envoy`, the Unix user of Envoy, and not a uid.
2. Done: Envoy in the `dev-tools` kit. It reads the SVID through SDS. Restricting the agent socket is open.
3. Choose how the client hop enforces the SVID. Research the Istio ingress options first.
4. Add a gateway rule on the source SPIFFE ID. Keep the JWT check.
5. Add `unix:path` and `unix:sha256`.
6. Optional: move to `x509pop`.

## Gaps and conflicts

- The CISA Zero Trust Maturity Model PDF returned HTTP 403. The CISA text above comes from a different CISA guide (OT) found by search. I did not read the maturity model.
- NIST SP 800-207 returned HTTP 403 (both the PDF and the csrc page). The tenet text comes from NIST CSWP 20, as shown in a search result. I did not read the PDF. The tenet number may differ in the original.
- The SPIFFE concepts page does not use the word "alias". The meaning comes from the `token generate` text and `spire.py`.
- I did not check `k8s_psat` in a primary source. The repo guide names it.
- I did not check how the Istio ingress can require a client SVID. The sandbox has no cluster access, so I could not list the entries on the server.
- Two spiffe.io pages returned HTTP 404 (`spire-about/security/` and the registering page). The notes on join token security come from the SPIRE plugin docs only.
