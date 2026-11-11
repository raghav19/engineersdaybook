# Handoff: iron-proxy as the gateway to the k3s cluster

Written on 2026-11-11. The index of all handoff documents is `docs/handoff.md`. This document continues [podman-gvisor-sandbox.md](podman-gvisor-sandbox.md).

The owner wants the agent in the sandbox to reach the k3s cluster on the host with a plain `kubectl`. The sandbox holds no cluster credential. iron-proxy is the gateway. The first version is one cluster and one declarative file. A fresh session continues with "Next steps".

## The design

```text
kubectl in the sandbox    KUBECONFIG=/etc/sandbox/cluster.yaml (a placeholder token, no CA)
  → socat → proxy.sock → bridge → iron-proxy
      the rule:    the host of k3s, and the methods that may pass
      the secret:  tokens/k8s_dev (a file on the host) replaces the placeholder
  → the k3s API on this host
```

- `.sandbox/cluster.yaml` is a plain kubeconfig with one context, `k8s_dev`. The server is `https://kubernetes.default.svc:6443`. The name is the same on each host.
- `just sandbox setup` links `iron-proxy.yaml`, `hosts` and `cluster.yaml` into `~/.config/sandbox`. It builds `upstream-ca.pem` from the system CAs and the CA in your kubeconfig. `.sandbox/proxy/hosts` has one line: `10.42.0.1 kubernetes.default.svc` (the address of `cni0`, the first address of the default pod range of k3s). The proxy unit binds it over `/etc/hosts`, so the system hosts file does not change.
- `.sandbox/proxy/iron-proxy.yaml` holds one allowlist rule and one secret for that host, as plain text.
- `just sandbox setup` makes a one-year token for the ServiceAccount `sandbox-agent` and writes it to `tokens/k8s_dev`, if the file does not exist. The proxy reads the file with a `ttl`.
- The container mounts `~/.config/sandbox/cluster.yaml` read-only and sets `KUBECONFIG`. There is no generator, no render step and no copy at start.

## Decisions of the owner

- No generator and no policy file for now. One cluster, one declarative file. A second cluster means a second block in two files.
- Mount the kubeconfig. Do not bake it into the image. Use a fixed name that points to the local k3s, so no file has a host-specific value. Rule edits need only a restart of the proxy, so there is no `config` recipe.
- Use a one-year token. The sandbox never holds it, so a short life adds little. A token that leaks from the host is the only risk, and deleting the ServiceAccount revokes it. A timer is not needed.
- Keep `kubectx` in the image. With one context it has nothing to switch, and the read-only mount blocks a switch.

## What changed

| File | Change |
|---|---|
| `.sandbox/cluster.yaml` | New. The kubeconfig of the sandbox. |
| `.sandbox/proxy/iron-proxy.yaml` | One allowlist rule and one secret for the k3s host. |
| `.sandbox/justfile` | `setup` links the three files, builds the CA bundle and makes the token once. |
| `.sandbox/proxy/sandbox-proxy.service` | Sets `SSL_CERT_FILE`. Binds `upstream-ca.pem`, the `tokens` folder and `hosts` (over `/etc/hosts`). |
| `.sandbox/sandbox.container` | Mounts `cluster.yaml` read-only and sets `KUBECONFIG`. |
| `.sandbox/image/tools/infra.toml` | Adds `kubectx` 0.11. |
| The READMEs | A "Clusters" section, the rules of the proxy explained, and the rows for daily use and failures. |

After you edit `proxy/iron-proxy.yaml`, run `systemctl --user restart sandbox-proxy`.

A generator for several clusters (a shared policy, access profiles, a script) was built and tested first. It is in the first commit of the branch `sandbox-clusters` (`a13dcb9`). Use it as the base when a second cluster comes.

## Evidence

The tests ran on the host of the owner on 2026-11-11 against the real k3s (`v1.37.1+k3s1`). They used scratch folders, a test CA, a test proxy on ports 19080 to 19084 and a renamed test sandbox. The live proxy, the live container and the real links were not touched.

| Fact | Result |
|---|---|
| The `allowlist` takes `domains` and `rules` together | Yes. A host of `domains` and a host of `rules` both pass. A host in neither gets `403`. |
| The `file` secret source takes a relative path | Yes, relative to the working directory. The real token was swapped in. |
| A `methods` rule must include `CONNECT` | Yes. The proxy judges the tunnel setup too. A rule with only `GET` blocks everything. |
| A client sends no SNI for an IP address | The proxy refuses the handshake: `no SNI provided`. Use a host name. |
| Upper-case host names | `curl` sends the SNI in lower case, and the proxy compares the text: `SNI/Host mismatch`. Use lower case. |
| The proxy and a private cluster CA | `502` and `x509: certificate signed by unknown authority`. `SSL_CERT_FILE` with the system CAs plus the cluster CA fixes it, for the proxy process only. |
| The upstream deny list | Loopback and the cloud metadata addresses. A LAN address and the name of the node pass. |
| Token refresh with `ttl: 10s` | A bad token in the file gave `Unauthorized` after the ttl. The good token worked again after the next ttl. |
| Method and path rules | `POST` and `DELETE` got `403` with `rejected_by: allowlist`. A path rule allowed `GET /version` and refused `GET /api`. |
| The hardened unit | A transient unit with `ProtectHome=tmpfs`, the same binds, `SSL_CERT_FILE` and the syscall filter gave `200` for the cluster and `403` for a refused method. |
| The fixed name | A transient unit with `ProtectHome=tmpfs` and the one-line `proxy/hosts` bound over `/etc/hosts` through a link gave `200` for `GET /version`. A `POST` of a self-subject review showed `system:serviceaccount:sandbox-agent:sandbox-agent`. The placeholder was swapped, the certificate matched the name, and `example.com` got `403`. |
| A symlinked kubeconfig as a file mount | In gVisor with `--network none`, `kubectl config view` read the file through a link on the host and showed the fixed server name. |
| The token command | `kubectl create token` under `umask 077` gives a file with mode 0600. k3s accepts `--duration=8760h` (the token has an expiry one year ahead). The ServiceAccount `sandbox-agent` already exists in the k3s. |
| The end-to-end test in a renamed sandbox | A plain `kubectl` with no flag: the version, `auth whoami` as `system:serviceaccount:sandbox-agent:sandbox-agent`, `get nodes` and `get pods -A` work. `get secrets -A` is `Forbidden`. `can-i create deployments` is `yes` in `sandbox-dev` and `no` in `default`. No token in the environment or the kubeconfig. |
| `kubectl config use-context` on the read-only file | `permission denied`. `kubectl` wants a lock file in the folder. |
| A missing token file | The proxy logs `reading secret file ... no such file` and keeps running. The cluster then answers `401`. |

## What was not tested

- The `kubectx` binary. It is not on the host, and the image has no `kubectx` until the next build. The task `sandbox:completions` has no line for it, because I could not check whether it has a `completion` subcommand, and a wrong line breaks the build.
- `just sandbox setup` as a real command on the host. Its new steps ran by hand with scratch paths.
- An image build with the new tool.
- `kubectl exec`, `port-forward`, `logs -f` and watches. They need a pod and a Role.
- A path rule for one namespace, such as `/api/v1/namespaces/sandbox-dev/*`.
- A machine with no k3s, or a k3s with another pod range. The address in `proxy/hosts` is then wrong.

## Open decisions (ask the owner)

1. **A second cluster.** Add a block, or bring back the generator (`a13dcb9`). EKS needs a token from `aws eks get-token`, with a separate IAM identity for the agent.
2. **Stricter methods.** The rule allows every method, and RBAC decides. The owner can remove methods for a read-only gateway.
3. **`kubectx`.** It does nothing with one context. Remove it, or give it a writable kubeconfig when a second cluster comes.

## Next steps

1. Merge the PR. Run `just sandbox setup`, then `just sandbox run`.
   - check: `kubectl config get-contexts` in the sandbox lists `k8s_dev`. `kubectl get --raw /version` works. `kubectl get secrets -A` is `Forbidden`.
2. Build the image (`just sandbox build`) and check that `kubectx` runs in the sandbox.
3. Spike the streams with the approval of the owner: a test namespace, a ServiceAccount and a read-only Role, then `exec`, `port-forward` and `logs -f` through the gateway.

## Lessons

- A test with `curl` through the proxy is the fastest check of a proxy rule. It needs no sandbox.
- Run a transient unit with the same sandboxing flags to test a unit change before it reaches the real unit.
- Do not give a test the name of a real link. Use test names for every file and unit.
- A plain write to a path that is a link changes the file in the repo. Write to a new name and move it, or write to a path that is not a link.
- Start with the smallest design. The generator was more than one cluster needed.
