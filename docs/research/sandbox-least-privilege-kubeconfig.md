# Least-privilege cluster access for the msb sandbox

Question: How does the AI agent in the msb VM get minimum-privilege access to the host k3s cluster? It must read cluster state, deploy services and add-ons, and publish artifacts to an OCI registry. Today the VM holds the k3s admin kubeconfig.

Source: Research date 2026-11-05. Versions and commits:

- Kubernetes docs: `kubernetes/website` at `main` (the pages show v1.37). The RBAC good practices page last changed on 2026-08-18 (`3a6acc56d7`). Kubernetes source: `kubernetes/kubernetes` at `master`, commit `dd676c8680` (2026-11-05). We did not read the `v1.37.1` tag.
- k3s: `k3s-io/docs` at `main`. `k3s-io/k3s` at `main`, commit `f5cba99ac7` (2026-11-05). The newest release is `v1.37.2+k3s1` (2026-11-03). The live host runs `v1.37.1+k3s1`.
- Flux: `flux2` v2.10.0, `source-controller` v1.10.1, `kustomize-controller` v1.10.1, `notification-controller` v1.10.0 (all 2026-10 releases). `FluxInstance` in this repo pins Flux 2.9.6. Flux Operator schema: v0.62.1.
- microsandbox: git tag `v0.7.10` and its `docs/` folder. `msb` is not installed in this VM, so we ran no live test.
- GitHub docs: `github/docs` at `main`. The packages page last changed on 2026-07-09 (`4250a7b9dc`).
- Repo: `8cd1073`.

Evidence tags: **documented** means an official doc page says it. **source** means the code says it. **inferred** means we derived it and no source states it. **observed** means we saw it on the live cluster or in this repo. Paths in the Source column are in the repo named in this list. `k8s-web` is `kubernetes/website` `content/en/`. `k3s-docs` is `k3s-io/docs` `docs/`. `msb` is `superradcompany/microsandbox` at `v0.7.10`.

Cluster check: the live k3s cluster answered. `kubectl auth whoami` showed the user `system:admin` in the groups `system:masters` and `system:authenticated`. The cluster has no `flux-system` namespace and no Flux CRDs. Part 3 is not applied yet. No secret value or kubeconfig body was printed.

## Verdict

1. Remove the admin kubeconfig from the VM. A read-only mount does not limit the credential. The admin identity is in `system:masters`. RBAC cannot restrict that group. k3s cannot revoke the admin client certificate without a full replacement of the cluster CA. The copy that the VM already holds stays valid until the certificate expires (365 days).
2. Give the agent one ServiceAccount with a custom ClusterRole. List the resources by name. Use only `get`, `list` and `watch`. Leave out Secrets and every escalation resource. Use a short-lived token from `kubectl create token`. The Kubernetes docs recommend TokenRequest tokens. They discourage long-lived token Secrets. Deleting the ServiceAccount revokes the token at once. A CSR client certificate cannot be revoked.
3. "Read-only" and "deploy" do not conflict if "deploy" means GitOps. Part 3 already works this way. The agent pushes an artifact and opens a pull request that changes the digest pin in the stack. A human merges it. Flux in the cluster applies it. The agent needs no write access to the cluster for this path.
4. Recommended design: option 3. Use option 1 for all real deployments. Add one namespace Role in one scratch namespace (`sandbox-dev`) for quick tests. Do not use option 2 alone. A write Role for the add-on namespaces is cluster-admin by another name, because add-ons own CRDs, webhooks and RBAC.
5. Flux is not installed on the live cluster. "Set up all the add-ons" starts with `just clusters/k3s/up` on the host. That recipe needs the admin kubeconfig and the Bitwarden token. It refuses to run in the VM. After it runs, the agent needs no admin right.
6. Delivery into the VM: decided on 2026-11-05. The host always replaces the token (option B). The VM holds only the placeholder `$MSB_K8S_TOKEN`, and a token file in the VM is not allowed. The msb source supports this for `host.microsandbox.internal`. It needs TLS interception on port 6443, which is off by default. The YAML `network.tls` block has no key for ports or for an upstream CA (`deny_unknown_fields`). So `msb.py` passes `--tls-intercept-port` and `--tls-upstream-ca-cert-for` as flags. A port flag replaces the default list `[443]`, so the flags name 443 again. Nobody tested the swap. Test it with the five steps in section 4. Option A below stays as the fallback that we do not use.
7. msb cannot limit HTTP verbs at the network layer. Its rules have destination, protocol, port and action only. The remaining controls are on the API server: RBAC, `anonymous-auth=false` (k3s default), admission and audit. Turn on audit at the `Metadata` level.
8. Two token findings. First, `ghcr.io` accepts only classic personal access tokens. The `write:packages` scope covers every package that the account can write. Second, `_seed` in `clusters/k3s/justfile` puts the same classic token in the cluster Secret `ghcr-pull`. Anyone who reads that Secret can push. Create a separate `read:packages` token for the cluster. Never grant `patch` on Flux objects to the agent. `patch` can change `spec.ref` and `spec.url`, so it equals deploy rights.

## 1. A least-privilege kubeconfig for an automation client

| Claim | Tag | Source |
|---|---|---|
| Assign minimal RBAC rights. Use namespace-level rights where possible. Use RoleBindings, not ClusterRoleBindings. Avoid wildcards. | documented | `k8s-web/docs/concepts/security/rbac-good-practices.md` ("Least privilege") |
| Do not use `cluster-admin` except where specifically needed. Do not add accounts to `system:masters`. That group bypasses all RBAC checks. Removing bindings cannot revoke it. | documented | same page |
| The best-practice way to grant a role to an app: a ServiceAccount made for that app. Granting to `default` or to all ServiceAccounts is worse. | documented | `k8s-web/docs/reference/access-authn-authz/rbac.md` ("ServiceAccount permissions") |
| TokenRequest API is "recommended". Projected token volumes are "also recommended". Service account token Secrets are "not recommended". They "don't expire and don't rotate". | documented | `k8s-web/docs/concepts/security/service-accounts.md` ("Manually retrieve ServiceAccount credentials") |
| For a client outside the cluster, the project recommends that you avoid a long-lived token Secret. It names three alternatives: a key and certificate, an authentication webhook, or short-lived TokenRequest tokens. | documented | same page, note after "Node audience restriction" |
| `kubectl create token NAME` has `--duration`, `--audience`, and `--bound-object-kind` (Node, Pod or Secret). The server can return a shorter or longer lifetime. | documented | `k8s-web/docs/reference/kubectl/generated/kubectl_create/kubectl_create_token.md`, `k8s-web/docs/tasks/configure-pod-container/configure-service-account.md` |
| A request must ask for at least 600 seconds. A request with no value gets 3600 seconds. | source | `pkg/apis/authentication/validation/validation.go` (`MinTokenAgeSec`), `pkg/apis/authentication/v1/defaults.go` |
| Without `--audience`, the token has the audiences of the API server. A token with another audience does not pass the API server unless that audience is in `--api-audiences`. | documented | `k8s-web/docs/tasks/configure-pod-container/configure-service-account.md` ("api-audiences"), `kubectl_create_token.md` |
| A token that is bound to a Secret stops working when you remove that Secret. This gives the host an extra revoke switch. | documented | `k8s-web/docs/reference/access-authn-authz/service-accounts-admin.md` ("Bound service account tokens") |
| A token for a deleted ServiceAccount fails. `--service-account-lookup` defaults to true. | documented | `kube-apiserver` reference (`--service-account-lookup`), `k8s-web/docs/reference/access-authn-authz/authentication.md` |
| A client certificate stays valid until it expires. "Kubernetes does not support certificate revocation." | documented | `authentication.md` ("X.509 client certificates") |
| The CSR route: signer `kubernetes.io/kube-apiserver-client`. The CN is the user. Each O is a group. The minimum `expirationSeconds` is 600. Someone must approve the CSR. | documented | `k8s-web/docs/reference/access-authn-authz/certificate-signing-requests.md`, `k8s-web/docs/tasks/tls/certificate-issue-client-csr.md` |
| RBAC grants are additive and attach to the user name. Deleting the RoleBinding of a CSR user removes its rights even though the certificate stays valid. | inferred | `rbac.md` ("Permissions are purely additive") |
| `view` allows read-only access to most namespaced objects. It does not show Roles or RoleBindings. It does not show Secrets. Reason in the doc: Secret contents give access as any ServiceAccount in the namespace. | documented | `rbac.md` ("User-facing roles") |
| `view` is an aggregated ClusterRole. Any ClusterRole with the label `rbac.authorization.k8s.io/aggregate-to-view: "true"` adds its rules to `view`. | documented | `rbac.md` ("User-facing roles", "Aggregated ClusterRoles") |
| The Flux ClusterRole `flux-view` has that label. It grants `get`, `list`, `watch` on `*` in six Flux API groups. | source | `fluxcd/flux2` `manifests/rbac/view.yaml` |
| On the live cluster `view` lists 62 resource entries. They include `configmaps`, `serviceaccounts` and `pods/log`. A custom ClusterRole keeps a fixed list when add-ons install. This is the reason to prefer it. The second part is a conclusion, not a doc claim. | observed, inferred | `kubectl get clusterrole view` (read-only) |
| Do not give `escalate`, `bind` or `impersonate`. | documented | `rbac-good-practices.md` ("Escalate verb", "Bind verb", "Impersonate verb") |
| `kubectl auth can-i --list` lists the allowed actions. `--as` checks another identity. `--as` needs impersonation rights. `--subresource` checks a subresource. | documented | `k8s-web/docs/reference/kubectl/generated/kubectl_auth/kubectl_auth_can-i.md`, `k8s-web/docs/reference/access-authn-authz/authorization.md` ("Checking API access") |
| `kubectl auth whoami` shows how the API server identifies the client. | documented | `authentication.md` ("API access to authentication information for a client") |

Order of preference, from the table: (1) ServiceAccount with a custom ClusterRole and a short-lived TokenRequest token. (2) CSR client certificate. (3) Long-lived token Secret, which the docs discourage. Do not use (3).

## 2. Secret exposure

Read access to Secrets equals credential theft. The role must exclude the resources below.

| Resource or verb | Why | Tag | Source |
|---|---|---|---|
| `secrets`: `get`, `list`, `watch` | `list` and `watch` also return the contents. `kubectl get secrets -A -o yaml` returns all values. | documented | `rbac-good-practices.md` ("Listing secrets"), `authorization.md` (caution: "list on secrets will reveal the data attributes"), `k8s-web/docs/concepts/security/secrets-good-practices.md` |
| `serviceaccounts/token`: `create` | The holder issues tokens for existing ServiceAccounts. | documented | `rbac-good-practices.md` ("Token request") |
| `pods/exec`, `pods/attach`, `pods/portforward` | These subresources exist. They run or attach to code in a pod. The pod can hold Secrets in its environment or mounts. No doc page lists them as dangerous. The evidence is the code. | source, inferred | `pkg/registry/core/rest/storage_core.go`, `pkg/registry/core/pod/storage/storage.go` |
| `pods/proxy`, `services/proxy` | The proxy accepts GET, POST, PUT, PATCH, DELETE. A `get` on it is not a read-only right. This follows the `nodes/proxy` rule below. | source, inferred | `pkg/registry/core/pod/rest/subresources.go` (`proxyMethods`) |
| `nodes/proxy` | Access to the kubelet API. It runs commands in any container on the node. A `get` is enough. "get permission on nodes/proxy is not a read-only permission." It skips audit and admission. | documented | `rbac-good-practices.md` ("Access to proxy subresource of Nodes"), `k8s-web/docs/reference/access-authn-authz/kubelet-authn-authz.md` |
| Verbs `impersonate`, `bind`, `escalate` | They bypass the escalation checks of RBAC. | documented | `rbac-good-practices.md`, `rbac.md` ("Privilege escalation prevention") |
| `certificatesigningrequests`: `create`. `certificatesigningrequests/approval`: `update` | The holder mints client certificates with any name. | documented | `rbac-good-practices.md` ("CSRs and certificate issuing") |
| `validatingwebhookconfigurations`, `mutatingwebhookconfigurations` | The holder reads or changes every admitted object. | documented | `rbac-good-practices.md` ("Control admission webhooks") |
| `namespaces`: `patch` | The holder changes Pod Security and NetworkPolicy labels. | documented | `rbac-good-practices.md` ("Namespace modification") |
| `roles`, `rolebindings`, `clusterroles`, `clusterrolebindings`: read | `view` hides Roles and RoleBindings. The doc states the exclusion and gives no reason. The bindings show which accounts hold power. | documented, inferred | `rbac.md` ("User-facing roles") |
| Create Pods or workloads | A user who can create a Pod that uses a Secret can see its value. A Pod runs as any ServiceAccount in the namespace. Isolate with separate namespaces. | documented | `rbac-good-practices.md` ("Workload creation"), `secrets-good-practices.md` |
| Create PersistentVolumes | `hostPath` volumes give access to the node filesystem. | documented | `rbac-good-practices.md` ("Persistent volume creation") |
| Wildcards in `resources` or `verbs` | They include every future resource type. | documented | `rbac-good-practices.md` ("Least privilege") |

Leaks through objects that the read role still allows:

| Leak | Tag | Source |
|---|---|---|
| Pod specs show plain `env.value` fields. Pod logs show what the app prints. Both are outside Secret objects. The recommended role omits `pods/log` cluster-wide. The `sandbox-dev` Role allows it. | inferred | no doc states this |
| ConfigMaps are for non-confidential data. The doc says to use a Secret for confidential data. A mistake still puts a secret in a ConfigMap, and the role reads ConfigMaps. | documented, inferred | `k8s-web/docs/concepts/configuration/configmap.md` |
| `HelmRelease` has inline `.spec.values` and `.spec.valuesFrom`. Inline values appear in `get -o yaml`. Keep credentials in `valuesFrom` Secrets. | documented | `fluxcd/helm-controller` `docs/spec/v2/helmreleases.md` ("Values") |
| `kubectl apply` stores the full applied manifest in the annotation `kubectl.kubernetes.io/last-applied-configuration`. A Secret that the host created with `kubectl apply` (the two Secrets in `_seed`) carries its data there. The annotation is on the Secret, so excluding Secrets covers it. | documented | `k8s-web/docs/tasks/manage-kubernetes-objects/declarative-config.md` |
| Flux `OCIRepository.spec.secretRef` and `ExternalSecret` hold names of Secrets, not values. | observed | `sync/local-k3s/infra/*/stack.yaml`, `schema OCIRepository.spec.secretRef` |
| SPIRE objects (`ClusterSPIFFEID`) hold selectors and templates, not keys. We did not check the SPIRE CRD fields for inline key material. | inferred | `platform/addons/spire` |

## 3. k3s specifics

| Claim | Tag | Source |
|---|---|---|
| The admin kubeconfig is `/etc/rancher/k3s/k3s.yaml`. It authenticates as `system:admin` in `system:masters`. Kubernetes hardcodes unrestricted rights for that group. | documented | `k3s-docs/cluster-access.md` |
| The live identity of the agent is `system:admin` with `system:masters`. | observed | `kubectl auth whoami` |
| The file is owned by root with mode 600 by default. Mode 644 lets other host users read it. `--write-kubeconfig-group` with a mode lets one group read it. | documented | `k3s-docs/cli/server.md` (`--write-kubeconfig-mode`, `--write-kubeconfig-group`) |
| This repo sets `write-kubeconfig-mode: "0644"` so the VM can read the file. Remove that setting when the mount goes away. | observed | `clusters/k3s/k3s-config.yaml` |
| k3s rewrites the client certificate in the admin kubeconfig at each start. Copies must be updated by hand. | documented | `k3s-docs/cluster-access.md` |
| Client and server certificates last 365 days. k3s renews those with fewer than 120 days left at each start. | documented | `k3s-docs/cli/certificate.md` |
| To revoke a certificate, "for example, due to a compromised admin kubeconfig", replace the whole cluster CA. | documented | `k3s-docs/cli/certificate.md` ("Kubernetes does not support use of Certificate Revocation Lists") |
| k3s starts the API server with its own signing key. The issuer is `https://kubernetes.default.svc.<cluster-domain>`. `api-audiences` is that URL plus `k3s`. So `kubectl create token` with the default audience works with no k3s-specific step. The last point is a conclusion. | source, inferred | `pkg/daemons/control/server.go` (`apiServer`) |
| k3s sets `authorization-mode=Node,RBAC` and `anonymous-auth=false`. It sets them only if you pass no `authorization-config` or `authentication-config` file. It enables the admission plugin `NodeRestriction`. | source | `pkg/daemons/control/server.go` |
| An unauthenticated request to `/version` on port 6443 returned a failure status. | observed | `curl -sk https://host.microsandbox.internal:6443/version` |
| The serving certificate lists `host.microsandbox.internal`, `kubernetes`, `kubernetes.default*`, `localhost`, `omarchy`, five IP addresses, and the issuer `k3s-server-ca`. The SAN is already present. Only the SAN list was printed. | observed | `openssl s_client ... \| openssl x509 -ext subjectAltName` |
| `tls-san` adds names or IPs to the serving certificate. In `config.yaml` it is a YAML list. `tls-san-security` (default true) refuses SANs that you did not list in `tls-san`. | documented | `k3s-docs/cli/server.md`, `k3s-docs/installation/configuration.md` |
| The `sed` rewrite changes only the URL. The kubeconfig still carries the k3s CA. The client checks the chain and the host name `host.microsandbox.internal` against the SAN. Without the SAN the check fails. The need for `tls-san` is therefore met by `clusters/k3s/k3s-config.yaml`. | inferred, observed | `clusters/k3s/k3s-config.yaml`, `client-go/tools/clientcmd/api/v1/types.go` (`tls-server-name` exists as an override) |
| The supervisor and the API server share port 6443. | documented | `k3s-docs/installation/requirements.md` |
| Unauthenticated supervisor routes: `/cacerts`, `/ping`, a static path. The `/v1-k3s/*` routes need a role from the agent, node, bootstrap or server groups. `CONNECT /` (the tunnel) needs `system:masters`. A ServiceAccount token cannot reach those routes. The admin kubeconfig can reach the tunnel. The last sentence is a conclusion from the group check. | source, inferred | `pkg/server/handlers/router.go`, `pkg/server/auth/auth.go`, `k8s.io/apiserver/pkg/authentication/user/user.go` (`SystemPrivilegedGroup = "system:masters"`) |
| `--service-account-max-token-expiration` caps TokenRequest lifetimes. It must be between 1 hour and 2^32 seconds. k3s takes it through `kube-apiserver-arg`. | documented, source | `kube-apiserver` reference, `pkg/controlplane/apiserver/options/options.go`, `k3s-docs/cli/server.md` (`--kube-apiserver-arg`) |
| `--service-account-extend-token-expiration` (default true) extends tokens that the admission plugin injects into Pods to one year. It ignores the cap above. It applies to a Pod-bound token with the 3607 s request and the API audience only. It does not change `kubectl create token`. The k3s hardening guide sets it to false. | documented, source | `kube-apiserver` reference, `pkg/registry/core/serviceaccount/storage/token.go`, `k3s-docs/security/hardening-guide.md` |

Advice on the cap: do not set `service-account-max-token-expiration` now. It applies to every TokenRequest in the cluster. The agent cannot request tokens (no `serviceaccounts/token` right). The host sets the lifetime with `--duration`. The cap adds little.

## 4. Delivery into the msb VM

| Claim | Tag | Source |
|---|---|---|
| The guest gets a placeholder (`$MSB_<NAME>`). The real value stays on the host. The host replaces it at the network boundary for allowed hosts only. | documented | `msb/docs/sandboxes/secrets.mdx`, `msb/docs/security/secrets.mdx` |
| A substitution needs an SNI match, a DNS pin, intercepted TLS and a matching `Host`. Header substitution is the default. `Authorization` is a header. | documented | `msb/docs/security/secrets.mdx` ("What gates a substitution"), `msb/docs/sandboxes/secrets.mdx` |
| The docs do not mention `host.microsandbox.internal` for secrets. The code does. When the SNI equals `host.microsandbox.internal`, the DNS-pin check becomes a check that the destination is the gateway IP. A unit test substitutes `Authorization: Bearer $KEY` for that name. | source | `crates/network/lib/engine/secrets/handler.rs` (`host_alias_matches`, test `host_alias_matches_gateway_without_dns_pin`), `crates/network/lib/lib.rs` (`HOST_ALIAS`) |
| TLS interception covers port 443 only by default. Port 6443 goes through the plain TCP proxy. The bytes of a TLS session are opaque there, so no substitution happens today. | source | `packages/microsandbox-types/rust/lib/domain.rs` (`default_intercepted_ports`), `crates/network/lib/engine/netstack/poll.rs` |
| The CLI has `--tls-intercept-port`. The serde field is `intercepted_ports`. The YAML example in the docs does not list it. `msb.py` passes `--net-rule` only. | source | `crates/cli/lib/commands/common.rs`, `domain.rs`, `msb/docs/cli/configuration.mdx` |
| The proxy verifies the upstream certificate by default. The k3s CA is not a public CA. msb has `scoped_upstream_ca_cert` (host pattern and PEM path) and `scoped_verify_upstream`. | source | `domain.rs` (`TlsConfig`) |
| The guest trusts the msb CA. agentd installs it and sets `SSL_CERT_FILE`. | documented, source | `msb/docs/networking/tls.mdx`, `crates/agentd/lib/tls.rs` |
| A kubeconfig with `certificate-authority-data` makes that CA "the ONLY information used". For interception, the kubeconfig must carry no CA data, or it must carry the msb CA. | source | `client-go/transport/transport.go` (`rootCertPool`) |
| msb offers no ALPN to the guest. kubectl then falls back to HTTP/1.1, where header substitution works. We did not test it. | inferred | `docs/research/microsandbox-credential-injection.md` section 4 |
| A client-certificate kubeconfig is not injectable. Substitution rewrites text in headers, the query and the body. A client certificate is part of the TLS handshake, and its private key must stay in the guest. Under interception the guest would present it to the msb proxy and not to the API server. A bearer token is injectable. | documented, inferred | `msb/docs/sandboxes/secrets.mdx` ("Choose substitution locations") |
| Rotation: `msb modify NAME --secret K8S_TOKEN@host.microsandbox.internal` changes the value for new connections only. A connection that is open keeps the old value. kubectl runs are short, so they pick up the new value. A long `kubectl get -w` keeps the old one until it closes. A new secret needs a restart (`just msb rm && just msb run`). | source, documented | `crates/network/lib/engine/secrets/handle.rs`, `msb/docs/sandboxes/tuning.mdx`, `docs/research/microsandbox-credential-injection.md` |
| A placeholder in a prompt sent to a model API gets `403` unless the secret has `passthrough` for that API. The repo uses that pattern for its four secrets. | observed | `.msb/vm/sandbox.yaml` (`secrets:`) |
| The placeholder keeps the token out of the VM. It does not limit what the agent does. The agent calls the API through the VM with the same rights. RBAC is the control for that. | documented | `msb/docs/security/secrets.mdx` ("What this does not protect") |
| The repo already follows "the VM holds no secrets, only placeholders" for GitHub and Claude tokens. | observed | `.msb/README.md` ("Decision records": the VM gets a placeholder for each secret) |

Options, in the order that we recommend:

| Option | What the VM holds | Status |
|---|---|---|
| A. Token file with `tokenFile`, lifetime 1 hour, refreshed from the host | A token that works for at most 1 hour | Not used. The user decided that the host must always replace the token. |
| B. Secret placeholder `K8S_TOKEN`, host replaces it at port 6443 | A placeholder only | Chosen. Source supports it. Nobody tested it. Implemented in `.msb/msb.py`, `.msb/vm/sandbox.yaml` and `.msb/image/sandbox-boot`. |
| C. CSR client certificate | A private key and a certificate (up to the signer limit) | Not injectable. No revocation. Use only if A and B fail. |
| D. Admin kubeconfig mount (today) | The admin identity | Remove. |

`tokenFile` in a kubeconfig user entry: the client reads the file again and again, and the last good value wins over `token`. So the host refreshes one file and no kubeconfig changes. Source: `client-go/tools/clientcmd/api/v1/types.go` (`TokenFile`).

Test plan for option B (all on a scratch VM). Run it before you adopt B.

1. Add `secrets: K8S_TOKEN: {allow: [host.microsandbox.internal], passthrough: [<the two model APIs>]}` to `vm/sandbox.yaml` and `--tls-intercept-port 6443` to the `msb run` call in `msb.py`. Check that `msb` accepts both together with `--conf`.
2. Pass the CA of the k3s server as `scoped_upstream_ca_cert` for `host.microsandbox.internal`. Check that the upstream connection works.
3. In the VM run `kubectl --server https://host.microsandbox.internal:6443 --token "$K8S_TOKEN" get ns` with no `certificate-authority-data`. Expect a list of namespaces.
4. Run `curl -sk https://host.microsandbox.internal:6443/version -H "Authorization: Bearer $K8S_TOKEN"` and the same with a wrong token. Expect `401` for the wrong one.
5. On the host run `msb modify NAME --secret K8S_TOKEN@host.microsandbox.internal` with a new token. Check that a new `kubectl get ns` works and that the old token no longer reaches the API after you delete the ServiceAccount.

## 5. Network layer and API-server controls

| Claim | Tag | Source |
|---|---|---|
| An msb network rule has a direction, a destination, a protocol set, a port set and an action. It has no HTTP method and no path. | source | `crates/network/lib/model/policy/types.rs` (`Rule`) |
| The TLS page says interception "enables URL policy checks". We found no URL or method field in the rule type at `v0.7.10`. | documented, source | `msb/docs/networking/tls.mdx`, `types.rs` |
| `host.microsandbox.internal` is blocked by default. The `host` group allows it. `msb.py` adds `allow@host:tcp:<port>` for each port in `HOST_PORTS`. | documented, observed | `msb/docs/networking/overview.mdx` ("Reaching the host"), `.msb/msb.py` |
| A verb filter in front of the API server is not a boundary. A `get` on `pods/proxy` or `nodes/proxy` is not read-only, and WebSocket upgrades use GET. No tool in the msb docs or the k3s docs does this. | inferred | section 2 |
| Remaining controls: RBAC and `Node` authorization (k3s default). `anonymous-auth=false` (k3s default). Admission (`NodeRestriction`, and the Kubernetes defaults). `ValidatingAdmissionPolicy` for field-level limits. Audit. | source, observed | `pkg/daemons/control/server.go`. The live cluster lists `validatingadmissionpolicies` in `kubectl api-resources` |
| k3s does not enable audit by default. You pass `audit-log-path` and `audit-policy-file` through `kube-apiserver-arg`. The log folder should be mode 700, because the log can hold sensitive data. | documented | `k3s-docs/security/hardening-guide.md` ("API Server audit configuration") |
| A policy rule can match `users` (authenticated user name). The first matching rule sets the level. `Metadata` logs the user, time, resource and verb but no bodies. The ServiceAccount user name is `system:serviceaccount:<namespace>:<name>`. | documented | `k8s-web/docs/tasks/debug/debug-cluster/audit.md`, `k8s-web/docs/reference/config-api/apiserver-audit.v1.md`, `authentication.md` |

Recommendation: turn on audit with the starter policy from the k3s hardening guide (one rule, level `Metadata`). Filter the log for the agent identity. See "Recommended design". The catalog has no `audit.k8s.io` schema, so we checked the policy against the Kubernetes API reference only.

## 6. Publishing artifacts

| Claim | Tag | Source |
|---|---|---|
| "GitHub Packages only supports authentication using a personal access token (classic)." `ghcr.io` does not accept fine-grained tokens. | documented | `github/docs` `data/reusables/package_registry/packages-classic-pat-only.md`, used in `content/packages/learn-github-packages/about-permissions-for-github-packages.md` |
| Scopes: `read:packages` (download), `write:packages` (upload), `delete:packages`. The account must also have the right on the package. | documented | same page ("About scopes and permissions for package registries") |
| The Container registry supports granular permissions that attach to a user or organization, not to a repository. A bot account with write access to one package limits `write:packages`. We did not read the access-control page. | documented, inferred | same page ("Granular permissions for user/organization-scoped packages") |
| `GITHUB_TOKEN` in Actions can publish packages of the workflow repository. Here the packages are not open to it, so CI also uses the Bitwarden token. | documented, observed | same page, `.github/workflows/manifest-diff.yaml` |
| The repo token `GITHUB_TOKEN` is a classic token with `write:packages`. The VM gets the placeholder `GHCR_PUSH_TOKEN`. The host replaces it for `ghcr.io`. `flux push artifact` runs with `--creds user:$MSB_GHCR_PUSH_TOKEN`. | observed | `.msb/README.md`, `.msb/vm/sandbox.yaml`, `lib/workflow/common.just` |
| The same classic token goes into the cluster Secret `ghcr-pull` (`_seed`). The cluster only needs `read:packages` to pull. | observed, documented | `clusters/k3s/justfile`, `about-permissions-for-github-packages.md` |
| To pull, Flux uses an `OCIRepository` with `secretRef` to a `kubernetes.io/dockerconfigjson` Secret. `flux create secret oci` makes it. | documented | `fluxcd/website` `content/en/flux/cheatsheets/oci-artifacts.md` ("Authentication"), schema `OCIRepository.spec.secretRef` |
| source-controller pulls from `ghcr.io` over the network of the node. The host must reach `ghcr.io` on port 443. | inferred | `OCIRepository.spec.url` is `oci://...` |
| `OCIRepository.spec.verify` (cosign or notation) checks an artifact signature. Every `OCIRepository` in the stack also has `ref.digest`. A pushed tag cannot change what runs. | observed | schema `OCIRepository`, `sync/local-k3s/infra/*/stack.yaml` |

Finding, no redesign: keep `flux push artifact` with the placeholder. Create a second classic token with only `read:packages` for `ghcr-pull`. Think about a bot account with write access to the one package, so a leaked `write:packages` token reaches less.

## 7. The deploy path with a read-only agent

What part 3 installs (observed): `FluxInstance` `flux` in `flux-system`. Flux 2.9.6. Components: source-controller, kustomize-controller, helm-controller. No notification-controller. Sync from `GitRepository` `refs/heads/main`, path `code/mcp-sandbox/part-3-mcp-guardrails/sync/local-k3s`. Three group Kustomizations (`secrets`, `mesh`, `gateway`) apply 13 units. Each unit is an `OCIRepository` (with `ref.digest`) and a `Kustomization`. The live cluster does not have any of this yet.

| Claim | Tag | Source |
|---|---|---|
| `FluxInstance.spec.sync.interval` defaults to 1 minute. A merged pin change reaches the cluster in about a minute. | observed | schema `FluxInstance.spec.sync.interval` (default `1m`) |
| The flow of a change: `package-artifact`, `publish-artifact`, `compose-stack`, a pull request, a human merge, Flux applies. Rollback is `git revert` of the pin. | observed | `docs/orchestration.md` (Flow B) |
| The VM cannot merge. Claude Code settings deny `merge_pull_request`. | observed | `.msb/README.md` ("MCP servers") |
| By default a Kustomization applies as cluster admin. `.spec.serviceAccountName` makes Flux impersonate a ServiceAccount. `--default-service-account` enforces it. | documented | `fluxcd/kustomize-controller` `docs/spec/v1/kustomizations.md` ("Role-based access control", "Enforcing impersonation") |
| The Flux install binds `kustomize-controller` and `helm-controller` to `cluster-admin`. | source | `fluxcd/flux2` `manifests/rbac/reconciler.yaml` |
| `FluxInstance.spec.cluster.multitenant` and `tenantDefaultServiceAccount` turn on the lock-down. The units in part 3 create CRDs, webhooks and cluster RBAC. An impersonated account would need those rights. Use impersonation for later app workloads, not for add-ons. The last two sentences are conclusions. | documented, inferred | schema `FluxInstance.spec.cluster`, `fluxcd/website` `content/en/flux/security/best-practices.md` |
| To force a reconcile, annotate the object with `reconcile.fluxcd.io/requestedAt: <value>`. The value must differ from `.status.lastHandledReconcileAt`. | documented | `fluxcd/source-controller` `docs/spec/v1/ocirepositories.md` ("Triggering a reconcile"), `kustomizations.md` |
| `flux reconcile source oci NAME` does a `get`, then a merge `patch` that sets the annotation, then reads the object again until it is handled. Minimum rights: `get` and `patch` on the object. | source | `fluxcd/flux2` `cmd/flux/reconcile.go` (`requestReconciliation`, `reconciliationHandled`) |
| RBAC rules have `apiGroups`, `resources`, `resourceNames` and `verbs`. They have no field filter. A `patch` right on an `OCIRepository` also allows a patch of `spec.url` and `spec.ref`. That equals deploy rights. | documented, inferred | schema `ClusterRole.rules[]`, `rbac.md` |
| A Flux `Receiver` of type `generic`, `generic-hmac` or `generic-oidc` triggers a reconcile from an HTTP call. It needs notification-controller and an Ingress to the `webhook-receiver` Service. Neither exists in part 3. | documented, observed | `fluxcd/notification-controller` `docs/spec/v1/receivers.md`, `clusters/k3s/flux-instance.yaml` |

Advice: give the agent no trigger. The 1-minute sync is fast enough. If you add a trigger later, use a Role in `flux-system` with `get` and `patch`, limited by `resourceNames`. Add a `ValidatingAdmissionPolicy` that allows only the annotation change for that user. Do not add notification-controller for this.

Comparison of the three options in the question:

| Option | Agent rights in the cluster | Result |
|---|---|---|
| 1. GitOps and OCI push | Read-only | The deploy gate is the human merge. The agent has no kubectl write. A bad artifact does not run unless a merged pin names its digest. |
| 2. Namespace write Roles for a few namespaces | Write in those namespaces | Add-ons need cluster-scoped rights. A Pod right in a namespace reads its Secrets. The agent can drift from Git, and Flux prunes or reverts it. |
| 3. Both | Read-only, plus write in one scratch namespace | Recommended. The scratch namespace holds no Secret and no sensitive ServiceAccount. Real deploys go through Git. |

## Recommended design

The agent identity is the ServiceAccount `sandbox-agent`. It has the ClusterRole `sandbox-agent-reader` cluster-wide and the Role `sandbox-agent-deployer` in `sandbox-dev` only.

What the manifests leave out on purpose: Secrets, `pods/log` (cluster-wide), `pods/exec`, `pods/attach`, `pods/portforward`, every `*/proxy`, `serviceaccounts/token`, Roles and bindings, CSRs, webhook configurations, `impersonate`, `bind`, `escalate`, wildcards, and any write on `externalsecrets`. An `ExternalSecret` that names a `ClusterSecretStore` could pull any Bitwarden secret into a namespace. We did not check whether the store limits namespaces, so the agent gets no write right on it.

Every manifest below passed `flux-schema validate` (7 resources, 0 invalid) against schemas from the `flux-schema-catalog` (`rbac.authorization.k8s.io/v1`, `v1`). The resource names in the ClusterRole come from `kubectl api-resources` on the live cluster and from the catalog for the add-on kinds. The `ServiceAccount` has `automountServiceAccountToken: false` because no Pod needs the token.

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: sandbox-agent
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sandbox-agent
  namespace: sandbox-agent
automountServiceAccountToken: false
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: sandbox-agent-reader
rules:
  - apiGroups: [""]
    resources:
      - namespaces
      - nodes
      - pods
      - services
      - endpoints
      - configmaps
      - events
      - persistentvolumeclaims
      - persistentvolumes
      - serviceaccounts
      - resourcequotas
      - limitranges
    verbs: [get, list, watch]
  - apiGroups: [apps]
    resources: [deployments, statefulsets, daemonsets, replicasets]
    verbs: [get, list, watch]
  - apiGroups: [batch]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch]
  - apiGroups: [discovery.k8s.io]
    resources: [endpointslices]
    verbs: [get, list, watch]
  - apiGroups: [networking.k8s.io]
    resources: [ingresses, ingressclasses, networkpolicies]
    verbs: [get, list, watch]
  - apiGroups: [apiextensions.k8s.io]
    resources: [customresourcedefinitions]
    verbs: [get, list, watch]
  - apiGroups: [kustomize.toolkit.fluxcd.io]
    resources: [kustomizations]
    verbs: [get, list, watch]
  - apiGroups: [source.toolkit.fluxcd.io]
    resources: [ocirepositories, gitrepositories, helmrepositories]
    verbs: [get, list, watch]
  - apiGroups: [helm.toolkit.fluxcd.io]
    resources: [helmreleases]
    verbs: [get, list, watch]
  - apiGroups: [fluxcd.controlplane.io]
    resources: [fluxinstances, fluxreports]
    verbs: [get, list, watch]
  - apiGroups: [gateway.networking.k8s.io]
    resources: [gatewayclasses, gateways, httproutes, referencegrants]
    verbs: [get, list, watch]
  - apiGroups: [external-secrets.io]
    resources: [externalsecrets, clustersecretstores]
    verbs: [get, list, watch]
  - apiGroups: [cert-manager.io]
    resources: [certificates, issuers, clusterissuers]
    verbs: [get, list, watch]
  - apiGroups: [spire.spiffe.io]
    resources: [clusterspiffeids]
    verbs: [get, list, watch]
  - apiGroups: [agentgateway.dev]
    resources: [agentgatewaybackends, agentgatewaypolicies, agentgatewayparameters]
    verbs: [get, list, watch]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: sandbox-agent-reader
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: sandbox-agent-reader
subjects:
  - kind: ServiceAccount
    name: sandbox-agent
    namespace: sandbox-agent
---
# Optional: the scratch namespace for quick tests. Pod Security "restricted" follows the RBAC good practices page.
apiVersion: v1
kind: Namespace
metadata:
  name: sandbox-dev
  labels:
    pod-security.kubernetes.io/enforce: restricted
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: sandbox-agent-deployer
  namespace: sandbox-dev
rules:
  - apiGroups: [""]
    resources: [pods, pods/log, services, configmaps, persistentvolumeclaims]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [apps]
    resources: [deployments, statefulsets]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [batch]
    resources: [jobs, cronjobs]
    verbs: [get, list, watch, create, update, patch, delete]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: sandbox-agent-deployer
  namespace: sandbox-dev
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: sandbox-agent-deployer
subjects:
  - kind: ServiceAccount
    name: sandbox-agent
    namespace: sandbox-agent
```

Rules for `sandbox-dev`: keep no Secret and no other ServiceAccount in it. A Pod there can run as any ServiceAccount of the namespace. A user who can create a Pod can read the Secrets that it mounts (`rbac-good-practices.md`, `secrets-good-practices.md`). Put these manifests in a file that only the host applies, for example `clusters/k3s/sandbox-agent-rbac.yaml`. Do not put them in the Flux sync folder, because the agent can open pull requests that change that folder.

### k3s changes (host)

In `/etc/rancher/k3s/config.yaml` (from `clusters/k3s/k3s-config.yaml`):

```yaml
# Back to the k3s default. Nothing but the host reads the admin kubeconfig after the mount goes away.
# Use write-kubeconfig-group with mode 0640 if a host group needs the file (k3s-docs/cli/server.md).
write-kubeconfig-mode: "0600"
kube-apiserver-arg:
  - 'audit-log-path=/var/lib/rancher/k3s/server/logs/audit.log'
  - 'audit-policy-file=/var/lib/rancher/k3s/server/audit.yaml'
  - 'audit-log-maxage=30'
  - 'audit-log-maxbackup=10'
  - 'audit-log-maxsize=100'
```

The audit policy `/var/lib/rancher/k3s/server/audit.yaml` (the starter policy of the k3s hardening guide). Create the log folder first: `sudo mkdir -p -m 700 /var/lib/rancher/k3s/server/logs`.

```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
```

Keep `tls-san: [host.microsandbox.internal]`. The live certificate already has it. Restart k3s after the change. The existing `sandbox-boot` and the `msb` mount depend on the old file mode, so make this change together with the VM change below.

### Host command sequence

All commands run on the host. The agent in the VM does not run them. `ctx` is `default`, as in `clusters/k3s/justfile`.

```bash
# 1. Apply the identity and the rights (admin kubeconfig, host only).
kubectl --context default apply -f clusters/k3s/sandbox-agent-rbac.yaml

# 2. Check the rights before the VM gets a token. Expected result in the comment.
as=system:serviceaccount:sandbox-agent:sandbox-agent
kubectl --context default auth can-i --list --as="$as"                                  # reads only, plus self-review
kubectl --context default auth can-i get pods -A --as="$as"                             # yes
kubectl --context default auth can-i get secrets -A --as="$as"                          # no
kubectl --context default auth can-i create pods --subresource=exec -n sandbox-dev --as="$as"   # no
kubectl --context default auth can-i get nodes --subresource=proxy --as="$as"           # no
kubectl --context default auth can-i create serviceaccounts --subresource=token -n sandbox-agent --as="$as"   # no
kubectl --context default auth can-i create deployments -n sandbox-dev --as="$as"       # yes
kubectl --context default auth can-i create deployments -n default --as="$as"           # no
kubectl --context default auth can-i patch ocirepositories.source.toolkit.fluxcd.io -n flux-system --as="$as"  # no

# 3. Make a token with a one-hour lifetime and write it into the VM. No file is made on the host.
#    `ssh_config` and `MSB_NAME` are the variables of .msb/justfile (run this as a recipe there).
#    The kubeconfig has the public CA of k3s, the server name and a tokenFile. It has no secret.
ca=$(kubectl --context default config view --raw --minify -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
token=$(kubectl --context default -n sandbox-agent create token sandbox-agent --duration 1h)
ssh -F "$ssh_config" "$MSB_NAME.msb" 'umask 077 && mkdir -p ~/.kube && cat > ~/.kube/token' <<<"$token"
ssh -F "$ssh_config" "$MSB_NAME.msb" 'umask 077 && cat > ~/.kube/config' <<EOF
apiVersion: v1
kind: Config
clusters:
  - name: k3s
    cluster:
      server: https://host.microsandbox.internal:6443
      certificate-authority-data: $ca
users:
  - name: sandbox-agent
    user:
      tokenFile: /home/agent/.kube/token
contexts:
  - name: default
    context: {cluster: k3s, user: sandbox-agent}
current-context: default
EOF

# 4. In the VM, check the identity.
#    kubectl auth whoami            -> system:serviceaccount:sandbox-agent:sandbox-agent
#    kubectl get secrets -A         -> Forbidden

# 5. Refresh before the hour ends: repeat the `token=` line and the first `ssh` line only.
# 6. Revoke at once: kubectl --context default -n sandbox-agent delete serviceaccount sandbox-agent
#    then apply the manifests again. Old tokens fail (--service-account-lookup).
```

Step 3 shows the token-file path (option A). We do not use it. The implementation uses option B: `msb.py` makes the token with `kubectl create token` and gives it to msb in the environment, and `sandbox-boot` writes a kubeconfig that holds the placeholder `$MSB_K8S_TOKEN`. The VM never holds the token, and `sync-kubeconfig` is gone (`just msb rotate-kube-token` replaces it).

### VM changes (for the implementer)

1. Delete the mount `/etc/rancher/k3s/k3s.yaml:/run/sandbox/kubeconfig/k3s.yaml:ro` from `.msb/vm/sandbox.yaml`.
2. Delete the kubeconfig block of `.msb/image/sandbox-boot` (the `src_kube` lines). Keep `KUBECONFIG=/home/agent/.kube/config` in `sandbox.yaml`.
3. Replace `sync-kubeconfig` with `rotate-kube-token`. Step 3 above is not used (see the note under it).
4. Update the "Ports of the host" bullet in `.msb/README.md`. Keep port 6443 in `HOST_PORTS`.
5. Treat the admin credential that the VM already holds as exposed. It stays valid until it expires. The only revocation is a replacement of the cluster CA (`k3s-docs/cli/certificate.md`). For a single-user host cluster you can decide to accept that risk until the next certificate rotation.

### Reading the audit log for the agent

```bash
sudo jq -c 'select(.user.username=="system:serviceaccount:sandbox-agent:sandbox-agent")
  | {t:.requestReceivedTimestamp, v:.verb, u:.requestURI, c:.responseStatus.code}' \
  /var/lib/rancher/k3s/server/logs/audit.log
```

### Add-ons: the order of work

1. Host: `just clusters/k3s/create` (or check that the live cluster matches `k3s-config.yaml`), then `just clusters/k3s/up`.
2. Agent (read-only): `kubectl get kustomizations -A`, `kubectl get ocirepositories -A` to watch the units become Ready.
3. Agent: change a component, `just <component>/publish-artifact`, `just <component>/compose-stack`, open a pull request.
4. Human: merge. Flux applies in about a minute.

## Open questions and unverified items

- Option B is untested. Unknown: whether the YAML key for intercepted ports exists, whether `--tls-intercept-port` combines with `--conf`, and whether upstream verification with `scoped_upstream_ca_cert` works for the alias. The VM already has interception on for port 443, and the host gateway on 443 carries the SPIRE TLS. `sandbox.yaml` has no bypass entry. We did not find out how that traffic passes.
- We read the Kubernetes source at `master`, not at the `v1.37.1` tag. The 600-second minimum, the 3600-second default and the 1-hour lower bound of the cap should match the tag. Nobody checked.
- Whether the feature gate `AuthorizePodWebsocketUpgradeCreatePermission` is on by default in v1.37. Exclude `pods/exec`, `pods/attach` and `pods/portforward` for every verb, so the answer does not change the role.
- No Kubernetes doc page names `pods/exec`, `pods/attach` or `pods/portforward` as dangerous. Our evidence is the source and general knowledge of what they do.
- The live `view` role may differ from the one in your tag. We counted its entries once.
- We did not check whether the `ClusterSecretStore` `bitwarden` can serve any namespace. If it can, a write right on `externalsecrets` in any namespace pulls any Bitwarden secret into the cluster.
- We did not check the SPIRE and agentgateway CRD fields for inline credentials. Review each group before you add it to the read role.
- The live cluster does not match `k3s-config.yaml`. It still has Traefik CRDs and a `boutique` namespace, and no Flux. Someone installed it another way. Check this before you run `just clusters/k3s/up`.
- The CSR route (option C) was not tested. The VM already makes a key and a CSR for SPIRE (`x509pop`), so the pattern exists.
- Whether a bot GitHub account with write access to one package works for `flux push` was not tested.
- Flux docs and source are v2.10.0. The `FluxInstance` pins 2.9.6. Not installed here, so no live check.
- Sizing of the token lifetime: one hour is our choice. The minimum is ten minutes. A shorter value costs more refreshes. Choose with the length of an agent session in mind.
