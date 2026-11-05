# ephemeral-env

Preview environments for the Boutique microservices. Each pull request gets a sandbox. The sandbox holds only the services that the PR changes. The other services come from a shared baseline. Istio and Kiali show the calls between the two.

The project grows in small PRs. This is PR 1, the foundation. It installs Flux, makes Flux pull one OCI artifact, and applies a minimal stack. It installs no Istio and no Boutique yet.

## How the delivery works

- **Git is the source.** You write, review and merge `platform/` in Git.
- **The registry is what Flux pulls.** `just publish` pushes `platform/` as one OCI artifact. Flux in the cluster reads only the registry. The cluster never reads Git. This is the gitless model.
- **The pointer is a tag.** `spec.sync.ref` of the `FluxInstance` names the tag or digest that Flux pulls.
- **Sandboxes never touch Git.** A later PR makes CI push one artifact for each pull request. Many PRs write to the registry at the same time, and no Git merge conflicts happen.

## Layout

| Path | Purpose |
|---|---|
| `platform/` | Everything in the OCI artifact. Later PRs add `addons/`, `apps/` and `sandboxes/`. |
| `clusters/k3s/` | Files that you apply from the host. They are not in the artifact. A bad artifact cannot delete Flux. |
| `justfile` | `check` and `publish`. |
| `clusters/k3s/justfile` | `up`. |

## The cluster contract

This project assumes a fresh k3s with its packaged components. It must not depend on what another project left on the cluster.

- k3s v1.37 or later, with the default Traefik and the default Gateway API CRDs. Do not pass `--disable traefik`.
- A kubeconfig on the host. The default context name is `default`. Set `KUBE_CONTEXT` for another name.
- Tools on the host: `just`, `kubectl`, `helm`, `yq`, `flux` and `kustomize`.
- No other project on the cluster uses the namespaces `flux-system` and `ephemeral-env`.

`up` checks the node, the Gateway API CRDs and the Traefik Deployment. It stops when one is missing.

## Setup (host)

Do not run these commands in the sandbox. The recipes refuse to run there, because the registry tokens must stay on the host.

1. Create two GitHub tokens and keep their values in your shell, never in a file in the repo:
   - `GHCR_TOKEN` with `write:packages`. `just publish` uses it.
   - `GHCR_PULL_TOKEN` with `read:packages`. `up` puts it in the cluster Secret `ghcr-pull`.
2. Check the manifests, with no cluster: `just check`.
3. Publish the artifact from the checkout of this branch: `just publish`. The command prints the tag, for example `ephemeral-env-foundation-1a2b3c4d`. On `main`, it also moves the tag `latest`.
4. Hand the cluster to Flux. Before the first merge, pass the tag from step 3: `just clusters/k3s/up <tag>`. After the merge and a publish from `main`, `just clusters/k3s/up` uses `latest`.

## Checks

Each command must print the value in the comment.

```sh
kubectl -n flux-system get fluxinstance flux          # READY True
kubectl -n flux-system get ocirepository flux-system  # READY True, with the tag as the revision
kubectl -n flux-system get kustomization flux-system  # READY True
kubectl get ns ephemeral-env                          # Active
kubectl get gatewayclass traefik                      # ACCEPTED True
kubectl -n kube-system get gateway traefik-gateway    # PROGRAMMED True
flux trace namespace ephemeral-env                         # shows the artifact and the Git source and revision
```

## Undo

```sh
kubectl delete fluxinstance flux -n flux-system   # deletes the Flux controllers
helm uninstall flux-operator -n flux-system
kubectl delete ns flux-system ephemeral-env       # also deletes the Secret ghcr-pull
kubectl delete -f clusters/k3s/traefik-config.yaml  # Traefik returns to the k3s defaults
```

Delete the old tags in the registry on the GitHub packages page.

## Not tested

- The Flux Operator 0.62.1 with Flux 2.10.0 on this cluster. `just check` tests only the schemas. No command here ran against a cluster.
- The k3s Traefik chart accepts the `HelmChartConfig` values on a fresh install. The idea comes from `code/platform-engineering/infrastructure/gateway/traefik-config.yaml`, which works on the current cluster.
- `flux push artifact` with `--creds` against GHCR, and the size of the GHCR rate limit.
