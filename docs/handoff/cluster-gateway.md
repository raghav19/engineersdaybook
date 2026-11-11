# Handoff: iron-proxy as the gateway to Kubernetes clusters

Written on 2026-11-11. The index of all handoff documents is `docs/handoff.md`. This document continues [podman-gvisor-sandbox.md](podman-gvisor-sandbox.md).

The owner wants the agent in the sandbox to reach Kubernetes clusters with native tools and no cluster credential. The clusters are a k3s on the host now and EKS later. iron-proxy is the gateway. A shared policy and the kubeconfig of each developer drive the setup. A fresh session continues with "Next steps".

## The design

- The sandbox kubeconfig has one context for each exposed cluster, with a placeholder token and no CA. `kubectl`, `flux`, `helm`, `k9s` and `kubectx` use it. The tools use the proxy because `HTTPS_PROXY` is set.
- `.sandbox/clusters.yaml` is the shared policy. It lists rules by context name and access profiles (`read-only`, `write-scratch`). It has no address and no secret.
- The name of a context is the name in the sandbox, in the placeholder and in the token file. A name looks like `k8s_dev`.
- `.sandbox/proxy/clusters.sh` reads the kubeconfig of the developer (public fields only) and writes the files. `just sandbox clusters` runs it. `just sandbox token NAME` makes a token.
- The proxy swaps the placeholder for the real token, from a file with a `ttl`, for the host of that cluster only. It checks the method (and path) of each request.

## What changed

| File | Change |
|---|---|
| `.sandbox/clusters.yaml` | New. The shared policy. |
| `.sandbox/proxy/clusters.sh` | New. The generator and the `token` mode. |
| `.sandbox/justfile` | `setup` runs `clusters.sh` in place of a link to `iron-proxy.yaml`. New recipes `clusters` and `token`. |
| `.sandbox/proxy/sandbox-proxy.service` | Sets `SSL_CERT_FILE` and binds `upstream-ca.pem` and the `tokens` folder. |
| `.sandbox/sandbox.container` | Mounts the folder `kube` read-only at `/etc/sandbox/kube`. |
| `.sandbox/image/sandbox-start` | Copies the kubeconfig to `~/.kube/config`. A writable copy lets `kubectx` change the context. |
| `.sandbox/image/tools/infra.toml` | Adds `kubectx` 0.11. |
| The READMEs | A "Clusters" section, the rules of the proxy explained, rows for daily use and failures. |

The live proxy config is now a generated file. After you edit `proxy/iron-proxy.yaml`, run `just sandbox clusters`. A plain restart does not read the edit.

## Evidence

The tests ran on the host of the owner on 2026-11-11 against the real k3s (`v1.37.1+k3s1`). They used scratch folders, a test CA, a test proxy on ports 19080 to 19084 and a renamed test sandbox. The live proxy, the live container and the real links were not touched.

| Fact | Result |
|---|---|
| The `allowlist` takes `domains` and `rules` together | Yes. A host of `domains` and a host of `rules` both pass. A host in neither gets `403`. |
| The `file` secret source takes a relative path | Yes, relative to the working directory. The real token was swapped in. |
| A `methods` rule must include `CONNECT` | Yes. The proxy judges the tunnel setup too. A rule with only `GET` blocks everything. |
| A client sends no SNI for an IP address | The proxy refuses the handshake: `no SNI provided`. Use a host name. |
| The proxy and upper-case host names | `curl` sends the SNI in lower case. The proxy compares the text and answers `SNI/Host mismatch`. `clusters.sh` writes the host in lower case. |
| The proxy and a private cluster CA | `502` and `x509: certificate signed by unknown authority`. `SSL_CERT_FILE` with the system CAs plus the cluster CA fixes it, for the proxy process only. |
| The upstream deny list | Loopback (`127.0.0.0/8`) and the cloud metadata addresses. A LAN address passes. `clusters.sh` rewrites a loopback server to the host name. |
| Token refresh with `ttl: 10s` | A bad token in the file gave `Unauthorized` after the ttl. The good token worked again after the next ttl. |
| Method and path rules | `POST` and `DELETE` got `403` with `rejected_by: allowlist`. A path rule allowed `GET /version` and refused `GET /api`. |
| The generator | `k8s_dev` exposed with `write-scratch`. A staging context exposed with `read-only`. `k8s_*_prod`, a kind context, an ARN name and an upper-case name were hidden or skipped. The output has no home path and no credential. |
| The generator and a link | It replaces an existing link at the config path. The file that the link pointed to did not change. |
| `token` mode | A token file with mode 0600, written to a new file and then renamed. The failures (bad name, missing context, an exec-plugin login) print a clear message. |
| The hardened unit | A transient unit with `ProtectHome=tmpfs`, the same binds, `SSL_CERT_FILE` and the syscall filter: `k8s_dev` gave `200`, and a staging `POST` gave `403`. |
| The end-to-end test in a renamed sandbox | `sandbox-start` copied the kubeconfig (mode 0600). `kubectl --context k8s_dev` returned the version and the identity `system:serviceaccount:sandbox-agent:sandbox-agent`. A context switch with `kubectl config use-context` worked. `get pods` and `get nodes` worked. `get secrets` was `Forbidden`. No token was in the sandbox. |
| The ServiceAccount of the owner | `sandbox-agent` in the namespace `sandbox-agent` already exists on the k3s (from the msb setup). `kubectl create token` worked for it. |
| A missing token file | The proxy logs `reading secret file ... no such file` and keeps running. The cluster then answers `401`. |

## What was not tested

- The `kubectx` binary. It is not on the host, and the image has no `kubectx` until the next build. The test used `kubectl config use-context`, which edits the same field. I did not check how `kubectx` behaves with the file, or whether it has a `completion` subcommand. The task `sandbox:completions` has no line for it.
- `just sandbox setup` and `just sandbox clusters` as real commands on the host. The generator and the units were tested in scratch folders.
- An image build with the new tool and the new `sandbox-start`.
- `kubectl exec`, `port-forward`, `logs -f` and watches. They need a pod and a Role.
- EKS and every exec-plugin login. `token` refuses them.
- Path rules for one namespace, such as `/api/v1/namespaces/sandbox-dev/*`.
- A timer that renews the tokens.

## Open decisions (ask the owner)

1. **Context names.** The policy needs `k8s_<name>`. The k3s context is `default` today. Make a renamed copy of its kubeconfig and name the context with `kubectx`.
2. **Token timers.** A user timer for each cluster, and a plan for the exec-plugin login of EKS.
3. **The agent identity for EKS.** A separate IAM identity with a view-only access entry, never the admin identity.
4. **Namespace limits.** Path rules that limit `write-scratch` to one namespace.
5. **A `path` unit** that runs `clusters.sh` when the kubeconfig changes.

## Next steps

1. Merge the PR. Run `just sandbox setup`, then `just sandbox token k8s_dev`, then `just sandbox run`.
   - check: `kubectl config get-contexts` in the sandbox lists `k8s_dev`. `kubectl get --raw /version` works. `kubectl get secrets -A` is `Forbidden`.
2. Build the image (`just sandbox build`), and check that `kubectx` runs in the sandbox.
3. Spike the streams with the approval of the owner: a test namespace, a ServiceAccount and a read-only Role, then `exec`, `port-forward` and `logs -f` through the gateway.
4. Build the token timers.

## Lessons

- A test with `curl` through the proxy is the fastest check of a proxy rule. It needs no sandbox.
- Run a transient unit with the same sandboxing flags to test a unit change before it reaches the real unit.
- Do not give a test the name of a real link. Use test names for every file and unit.
- Write the config with `mv` from a new file. A plain write follows a link and changes the file in the repo.
