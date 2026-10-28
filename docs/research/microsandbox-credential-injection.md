# microsandbox secret injection and live rotation

Question: Does microsandbox (`msb`) have a built-in credential proxy like Docker sbx, where the host holds the Claude OAuth login, refreshes it and injects it into VM requests? Does `msb modify --secret` reach connections that are already open?

Source: microsandbox git tag `v0.7.10` (commit `c4ad9c6`, the installed `msb 0.7.10`), and the docs in that tag's `docs/` folder. Research date: 2026-10-28.

Evidence tags: **documented** means the official docs say it. **source** means the code in the repo says it. **inferred** means we derived it and no source states it. Paths are in `github.com/superradcompany/microsandbox` at tag `v0.7.10` unless noted.

## Verdict

1. microsandbox has secret injection, but not a login-holding proxy. It substitutes a host value for a guest placeholder. It does not refresh, fetch or watch anything.
2. A live rotation reaches only connections that the guest opens after the rotation. A connection that is already open keeps the old value for its whole life. The source states this twice.
3. This explains the Headroom symptom. A pooled keep-alive connection that was opened before the rotation keeps sending the revoked token. A new `curl` opens a new connection and works.
4. The docs for `v0.7.10` and `v0.7.11` do not mention this limit. It appears only in code comments.

## 1. How secrets work

| Claim | Tag | Source |
|---|---|---|
| The guest gets a placeholder, `$MSB_<NAME>` by default. The real value stays on the host and is substituted at the network boundary. | documented | `docs/sandboxes/secrets.mdx` ("Add a secret"), `docs/security/secrets.mdx` ("The data flow") |
| Declaration: `secrets:` in `sandbox.yaml`, `--secret NAME[:OPTIONS]@HOST[,HOST...]` on `create`, `run` and `modify`, or an SDK builder. Every secret needs a non-empty host allow list. | documented | `docs/cli/configuration.mdx:320-342`, `docs/sandboxes/secrets.mdx` |
| YAML `value: ${NAME}` (exact form) records `NAME` as a host environment reference. Without `value`, the env var with the same name is used. | documented | `docs/cli/configuration.mdx:322` |
| The CLI never reads the value at parse time. It stores `{kind: env, var}`. The host env is read at start time (`create`, `run`) or apply time (`modify`). Inline `NAME=VALUE@HOST` is rejected. | source | `crates/cli/lib/commands/common.rs:3057-3083`, `sdk/rust/lib/sandbox/modify.rs:1687-1700` |
| Default substitution is headers only (including Basic auth). Query and body are off. | documented | `docs/sandboxes/secrets.mdx` ("Choose substitution locations") |
| Options: `no-headers` turns headers off. `headers=[a,b]` limits headers to those names. `query` and `body` turn those on. `no-headers` and `headers=` cannot be combined. On `modify`, any of these options replaces the whole rule. Without them the current rule stays. | source | `crates/cli/lib/commands/common.rs:3102-3140`, `crates/cli/lib/commands/modify.rs:96-101` |
| Body substitution: fixed-length HTTP/1 up to 16 MiB and chunked HTTP/1. HTTP/2 body substitution is not supported and a matching placeholder is blocked. | documented | `docs/sandboxes/secrets.mdx` ("Substitution limits") |
| Substitution needs an allowed host that matches the SNI, a DNS-pin check, intercepted TLS (default) and a matching `Host` or `:authority`. A placeholder sent elsewhere is blocked, logged or passed through, by the violation action. | documented | `docs/security/secrets.mdx` ("What gates a substitution") |

## 2. Live rotation and established connections

Flow of `msb modify NAME --secret X@HOST`: the CLI or SDK reads the host env var and sends a `Rotate` change to the sandbox runtime. The runtime calls `SecretsHandle::rotate_value`. This swaps an `Arc` snapshot in an `RwLock`. Source: `sdk/rust/lib/sandbox/modify.rs:1678-1700`, `crates/runtime/lib/runner/control/handler.rs:393`, `crates/network/lib/engine/secrets/handle.rs:63-69`.

| Claim | Tag | Source |
|---|---|---|
| "Swapping the snapshot makes rotation ... take effect for all future guest connections ... In-flight connections keep the snapshot they started with." | source | `crates/network/lib/engine/secrets/handle.rs:1-6` |
| TLS path: `tls_state.secrets.load()` runs once at the start of `intercept_relay`. It builds one `SecretsHandler` for the connection. Comment: "Per-connection snapshot: live secret updates apply to later connections." | source | `crates/network/lib/engine/tls/proxy.rs:486-492` |
| The same handler serves every request on that connection. `forward_plaintext` takes `&mut SecretsHandler` and the relay loop reuses it. There is no reload per request. | source | `crates/network/lib/engine/tls/proxy.rs:540-552`, `:686-711` |
| Plain-HTTP/TCP path: the snapshot is loaded when the TCP flow is created. Comment: "Load the current snapshot per connection so live secret updates apply to traffic the guest starts afterwards." | source | `crates/network/lib/engine/netstack/poll.rs:687-690` |
| The handler copies the secret value (`secret.value.clone()`) into the connection when it is built. A later swap cannot change that copy. | source | `crates/network/lib/engine/secrets/handler.rs:673-677` |
| The unit test `rotate_swaps_value_for_future_loads` checks that a snapshot taken before the rotation still holds the old value. | source | `crates/network/lib/engine/secrets/handle.rs:123-136` |
| The user docs say rotation is live "because substitution happens at the host network boundary". They say nothing about open connections. | documented | `docs/sandboxes/tuning.mdx:339`, live page `https://docs.microsandbox.dev/sandboxes/tuning` (checked 2026-10-28) |
| `v0.7.11` (the newest tag) keeps the same comments. Its diff in `crates/network`, the control runner and `docs/sandboxes` touches only job and idle code and a lifecycle page. No fix for this. | source | `git diff v0.7.10 v0.7.11` |

Answer: rotation applies to new connections only. An already-established keep-alive TLS connection keeps substituting the old value until it closes. The Headroom 401 `OAuth access token has been revoked` fits this. The connection pool in httpx or requests reused sockets that were opened before the rotation. Restarting Headroom closed them.

## 3. Hooks, callbacks and refreshing sources

There is none. We found no hook, callback, command source, file source, watcher, OAuth refresh or TTL in the config, the CLI or the SDKs.

| Claim | Tag | Source |
|---|---|---|
| `SecretSource` has two variants: `Env { var }` and `Store { reference }`. | source | `packages/microsandbox-types/rust/lib/modify.rs:182-194` |
| `Store` is rejected everywhere: "store-backed secret sources are not supported yet". The TypeScript docs call it "reserved ... currently unsupported". | source, documented | `sdk/rust/lib/sandbox/modify.rs:1514`, `:1705`, `docs/sdk/typescript/sandbox.mdx:2966` |
| An open issue asks for runtime-resolved store-backed secrets (example `file:///run/...`). Opened 2026-07-18, last update 2026-10-07, still open. | source | `https://github.com/superradcompany/microsandbox/issues/1183` |
| The env value is read once per apply, by the CLI or SDK process. The runtime keeps the value in memory. Nothing re-reads the env var later. | source | `sdk/rust/lib/sandbox/modify.rs:1687-1700`, `crates/network/lib/model/config/resolver.rs:160-172` |
| A search of the repo for OAuth or refresh-token handling finds none in the secret code. The only hit is a cloud-backend comment that says no OAuth is honored. | source | `sdk/rust/lib/backend/cloud/mod.rs:11` |

## 4. TLS interception behavior

| Claim | Tag | Source |
|---|---|---|
| Interception loads a CA, adds it to the guest trust store, makes a certificate per host and opens a separate verified TLS connection upstream. The default CA is `~/.microsandbox/tls/ca.{crt,key}`. | documented | `docs/networking/tls.mdx` ("How it works") |
| agentd sets `SSL_CERT_FILE` and `REQUESTS_CA_BUNDLE` in the guest. Apps with their own trust store need `msb-trust.sh`. | source, documented | `crates/agentd/lib/tls.rs:84-85`, `docs/networking/tls.mdx` |
| Substitution is per connection. The handler is built once, then it parses each HTTP/1 request or HTTP/2 stream on that connection and rewrites headers. The secret list is fixed at build time. | source | `crates/network/lib/engine/secrets/handler.rs:80-160`, `tls/proxy.rs:489-492` |
| The guest-facing TLS server config sets no ALPN (`ServerConfig::builder().with_no_client_auth().with_single_cert(..)`). No `alpn` string appears in `crates/`. | source | `crates/network/lib/engine/tls/certgen.rs:78-81` |
| Because of that, guest clients cannot negotiate `h2` through ALPN and should use HTTP/1.1 keep-alive. The handler also parses an HTTP/2 preface, so prior-knowledge h2 is handled. We did not test this. | inferred | `handler.rs:35-36`, `:787` |
| Pooled connections therefore stay on one `SecretsHandler` for as long as the client keeps them. There is no idle limit or forced close in the relay we read. | inferred | `tls/proxy.rs:540-600` |

## 5. Keeping a secret current, and the sbx comparison

| Claim | Tag | Source |
|---|---|---|
| The documented way to change a secret value is `msb modify NAME --secret X@HOST` (live) or `--restart`. The docs say "Guest code keeps using the same placeholder". They give no way to reset open connections. | documented | `docs/sandboxes/tuning.mdx:335-393`, `docs/sandboxes/secrets.mdx` ("Update secrets") |
| Adding a secret or changing its placeholder needs a restart. Rotating the value of an existing secret does not. | documented | `docs/sandboxes/tuning.mdx:23`, `:393` |
| Updating a sandbox secret "does not rotate or revoke it at the issuing service". | documented | `docs/sandboxes/secrets.mdx` ("Update secrets") |
| There is no equivalent of the sbx proxy that holds and refreshes a login. Whoever calls `msb modify` must supply the new value from the host. | source | sections 2 and 3 |
| Workarounds that keep the old connection from sending a stale token are all guest-side or restart-based, and none is documented by microsandbox: close the pool (no keep-alive, or `Connection: close`), restart the client, or restart the VM. | inferred | section 2 |

## Version check

- Installed: `msb 0.7.10` (`msb --version`). Tag `v0.7.10` exists and is dated 2026-10-23. The repo `main` is at 0.7.11 (`Cargo.toml`). The docs folder in the tag matches the live site on the checked page (`/sandboxes/tuning`).
- The relevant code is the same in `v0.7.10` and `v0.7.11`.
- Not verified: behavior of a live VM. We read the code and did not reproduce the 401 with a controlled test.

## Could not verify

- Whether any client library in the guest (httpx, requests, Node) closes idle sockets early. This sets how long the stale value lives.
- Whether a rotation closes TCP flows. We found no code that does this.
- The exact YAML keys for secrets in the config schema beyond the documented ones (`value`, `allow`, `substitution`, `passthrough`, `violation_action`, `require_tls_identity`). We found no `file` or `command` key.
- The docs-site version label. The repo docs have no version string, so we matched by tag.

## Implications for `.msb/`

1. The sync option (a systemd path unit that runs `msb modify --secret` when the host token file changes) is valid for new connections. It does not fix connections that are already open.
2. Each rotation must be followed by a restart of every guest process that pools connections to `api.anthropic.com`. For Headroom, that is a restart after each `msb modify`. Order matters: run `msb modify` first, then restart Headroom, or the new Headroom connections can still open before the swap.
3. A cheaper guest-side fix is to stop Headroom from reusing sockets: set the upstream client to no keep-alive. This costs a TLS handshake per request. It is inferred, not tested, and it depends on Headroom exposing the setting.
4. The host side holds no refresh logic. The unit must read the token that `claude` refreshes on the host, then call `msb modify`. If the token changes while a request is in flight, that request may fail once. This is the same limit as the current `msb.py` read.
5. If long-lived streaming connections matter, the only complete fix is to restart the VM with `msb modify --restart`, which drops all connections. Watch issue 1183 for a `Store` source. Even if it lands, the per-connection snapshot may still apply to open connections.
