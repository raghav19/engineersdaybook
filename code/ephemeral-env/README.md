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
| `platform/` | Everything in the OCI artifact. `sync.yaml` holds the Flux Kustomizations that apply `addons/` and `apps/` in order. A later PR adds `sandboxes/`. |
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

## Istio (PR 2)

`platform/addons/istio/` holds the namespace `istio-system`, the Istio `base` chart (the CRDs) and `istiod`. All three use Istio 1.31.1. The mesh is in sidecar mode and `istiod` is its CA. No SPIRE and no ingress gateway are in the project, because Traefik stays the ingress. Flux installs the charts after the artifact reaches the cluster. This PR changes no host step.

Checks, after you publish and Flux reconciles:

```sh
kubectl -n istio-system get helmrelease                 # istio-base and istiod, READY True
kubectl -n istio-system get deploy istiod                # 1/1 available
kubectl get crd | grep -c istio.io                       # more than 0
```

Undo: delete the Kustomization `addons-istio` from `platform/sync.yaml`, publish, and let Flux uninstall both releases. Flux never prunes the namespace or the CRDs. To delete them, run `kubectl delete ns istio-system` and delete the `istio.io` CRDs by hand. Deleting a CRD deletes every custom resource of its kind.

## Observability (PR 3)

`platform/addons/observability/` holds Prometheus and Kiali. Both files come from the Istio 1.31.1 sample add-ons and run in `istio-system`. The `HTTPRoute` `kiali` publishes Kiali through the Traefik Gateway.

- **Open Kiali** at `http://kiali.localhost/kiali` in a browser on the machine that runs the cluster. The route matches only the host `kiali.localhost`. A request by IP address gets a 404.
- **Read the risk.** The sample Kiali login is anonymous. Its ClusterRole can create, patch and delete Istio objects. This project sets `view_only_mode: true`, so Kiali shows the mesh and changes nothing. Anyone who reaches Traefik with the host name `kiali.localhost` can still see the mesh. The Host header is not a login. Do not open ports 80 and 443 of the host to an untrusted network.
- **Prometheus keeps its data in an `emptyDir`.** A pod restart loses the metrics.
- **The cluster pulls three images:** `quay.io/kiali/kiali`, `docker.io/prom/prometheus` and `ghcr.io/prometheus-operator/prometheus-config-reloader`.
- **No traffic yet.** The graph stays empty until PR 4 puts the Boutique in the mesh.

Checks, after you publish and Flux reconciles:

```sh
kubectl -n istio-system get deploy prometheus kiali        # both 1/1 available
kubectl -n istio-system get httproute kiali                 # Accepted True
curl -s -o /dev/null -w '%{http_code}\n' -H 'Host: kiali.localhost' http://127.0.0.1/kiali/api/status   # 200
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/kiali/api/status                               # 404
```

Undo: delete the Kustomization `addons-observability` from `platform/sync.yaml` and publish. Flux deletes both deployments, the route and the cluster roles.

## Baseline (PR 4)

`platform/apps/boutique/` runs Online Boutique v0.10.7 in the namespace `boutique`. The `kustomization.yaml` there lists the stock release file by its URL, pinned by commit hash. The artifact holds no copy of the release. `kustomize-controller` fetches the file from `raw.githubusercontent.com` on every reconcile. This is the one exception to "the cluster reads only the registry". The namespace has the label `istio-injection=enabled` from its creation, so every pod starts with its sidecar. The `HTTPRoute` `frontend` sends `/` from the Traefik Gateway to the Service `frontend`. The release includes a `loadgenerator`, so the Kiali graph shows traffic without a browser. A kustomize patch deletes the Service `frontend-external`, because Traefik holds node port 80.

**The order of the platform changed.** `platform/sync.yaml` holds three Flux Kustomizations: `addons-istio`, `addons-observability` and `apps-boutique`. Both of the last two wait for `addons-istio` to be Ready. `wait: true` makes "Ready" mean that the HelmReleases and the Deployments are healthy. Without this order, Boutique pods can start before the injection webhook exists. Such a pod runs without a sidecar, and I found no report of it. `just check` now builds every folder under `addons/` and `apps/`.

Checks, after you publish and Flux reconciles:

```sh
kubectl -n flux-system get kustomization                         # three Kustomizations, READY True
kubectl -n boutique get pods                                      # 12 pods, all Running
kubectl -n boutique get pods -o json | jq -r '.items[] | select([.spec.containers[].name, (.spec.initContainers // [])[].name] | index("istio-proxy") | not) | .metadata.name'   # prints nothing: every pod has a sidecar
kubectl -n boutique get httproute frontend                        # Accepted True
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1/        # 200, the shop
```

In Kiali (`http://kiali.localhost/kiali`), the graph for the namespace `boutique` shows the calls between the services.

Undo: delete the Kustomization `apps-boutique` from `platform/sync.yaml` and publish. Flux deletes the namespace `boutique` and everything in it.

## Not tested

- The Flux Operator 0.62.1 with Flux 2.10.0 on this cluster. `just check` tests only the schemas. No command here ran against a cluster.
- The k3s Traefik chart accepts the `HelmChartConfig` values on a fresh install. The idea comes from `code/platform-engineering/infrastructure/gateway/traefik-config.yaml`, which works on the current cluster.
- `flux push artifact` with `--creds` against GHCR, and the size of the GHCR rate limit.
- The Istio 1.31.1 charts on k3s 1.37, and the redirect from `blob.istio.io` that the `HelmRepository` follows. The chart index lists 1.31.1 for `base` and `istiod`.
- Kiali and Prometheus from the Istio 1.31.1 samples on k3s 1.37. Whether `view_only_mode` hides every write action of the Kiali UI. The Kiali version is v2.31.
- Boutique v0.10.7 with Istio 1.31.1 sidecars. The `loadgenerator` init container `frontend-check` needs the network before the main containers start. It works only if Istio injects the sidecar as a native sidecar. The cluster fetches the release file from `raw.githubusercontent.com`, and Flux has no flag set that forbids remote bases (`--no-remote-bases`). The cluster pulls the images from `us-central1-docker.pkg.dev` and `docker.io`. The memory of one node for 12 pods with sidecars is not measured.
