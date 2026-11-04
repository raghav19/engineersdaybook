# Backstage

Backstage is the developer portal. It shows what runs on the platform: who owns it, what it needs, and what state it is in.

The platform team owns this folder. It runs Backstage in the namespace `backstage`. The Helm chart is the official Backstage chart, version `2.10.2`. The image is the demo image `1.55.2`.

## Limits of the demo image

The chart runs the image that `npx @backstage/create-app` makes. You cannot add plugins to it. These limits follow:

- The image has the guest login only. It has no GitHub login. A GitHub login needs your own image.
- The image has the Kubernetes plugin and the MCP actions plugin. I expect it has no `AiResource` catalog kind. Check this when you need it.
- The route is open to every machine that can reach the host. See the section Security.

## Files

| File | Content |
|---|---|
| `namespace.yaml` | The namespace `backstage`. |
| `postgres.yaml` | Postgres with the official image `postgres:17.11-alpine` and a 2Gi volume. |
| `rbac.yaml` | A read-only `ClusterRole` and its binding to the ServiceAccount `backstage`. |
| `values.yaml` | The values for the Helm chart: image, database, login, catalog, Kubernetes plugin, and the `HTTPRoute` for `backstage.localhost`. |

## Apply

Run the steps in this order.

```bash
kubectl apply -f namespace.yaml

# The password is not in this repo. This command makes a random one and does not print it.
kubectl create secret generic postgres -n backstage \
  --from-literal=POSTGRES_USER=backstage \
  --from-literal=POSTGRES_PASSWORD="$(openssl rand -base64 24 | tr -d '/+=')"

kubectl apply -f postgres.yaml -f rbac.yaml

helm upgrade --install backstage oci://ghcr.io/backstage/charts/backstage \
  --version 2.10.2 -n backstage -f values.yaml
```

The chart repository `https://backstage.github.io/charts` also works on a host that can reach it.

## Check

```bash
kubectl get pods -n backstage        # backstage and postgres-0, both 1/1 Running
kubectl get httproute backstage -n backstage -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status}{"\n"}{end}'
# Accepted=True
# ResolvedRefs=True
```

The name `backstage.localhost` needs no entry in `/etc/hosts`. Browsers resolve every `*.localhost` name to the loopback address. Traefik answers on port 80 of the host, and the loopback address reaches it.

A name without a matching route shows Online Boutique, because the route of the shop has no hostname. If you see the shop, check the host name in the address bar. It must be exactly `backstage.localhost`.

Open `http://backstage.localhost` in the browser. Choose the guest login. Then check these pages. The page names come from the Backstage getting-started guide.

1. **Catalog (`Home`):** set the filter `Owner` to `All`. The default is `Owned`, and the guest owns nothing, so the list is empty until you change it. You see the 11 Components. Set `Kind` to `System`, `Resource`, `Group` or `User` to see the others.
2. **System `online-boutique`:** the cards `Has components` and `Has Resources`.
3. **Component `frontend`:** the card `About` shows the owner and the system. The card `Relations` shows the links. Select `View graph` to open the Catalog Graph.
4. **Component `frontend`, tab Kubernetes:** the pod, the Service, the Deployment and the ReplicaSet of `frontend`.
5. **User `raghav19`:** set `Kind` to `User` and select `raghav19`. Toggle `Aggregated Relations` to see the entities that the user owns through the group.

## How the catalog gets the Boutique

`values.yaml` holds two catalog locations. They are URLs of files in this repo on the branch `main`:

- `apps/boutique/catalog/catalog-info.yaml` holds the System, the 11 Components and the Resource.
- `apps/boutique/catalog/org.yaml` holds the Group `boutique-team` and the User `raghav19`.

The [README of the catalog](../../apps/boutique/catalog/README.md) explains how the entities link, with a diagram.

The app team owns these files. Backstage reads them again at intervals. A change on `main` shows in Backstage without a new install. The org file needs the rule `allow: [User, Group]` on its location.

## How the config files load

The image holds two config files: `app-config.yaml` and `app-config.production.yaml`. The chart passes its own ConfigMap as the only `--config` argument. That drops the image config. Three problems followed, one after the other:

| Problem | Cause |
|---|---|
| Backstage rejected the kind `System`. | The rule `catalog.rules` of the image config was missing. |
| The Kubernetes tab and the org pages were missing. | The key `app.packages: all` was missing. The frontend turns on the bundled plugins only with this key. |
| The UI stopped with `Missing required config value at 'app.title'`. | The key `app.title` was missing. The frontend needs it, and the image config holds it. |

`values.yaml` fixes all three with one setting: `backstage.args` loads `/app/app-config.yaml` first. The ConfigMap of the chart loads after it and overrides it. So the image gives the defaults: the title, the organization name, the plugin switch, and the rules. `values.yaml` holds only what is ours. That is the URLs, the database, the guest flag, the catalog locations, and the Kubernetes cluster.

An array in a later file replaces the array of an earlier file. So our `catalog.locations` replaces the example entities of the image.

## How the Kubernetes tab works

- Backstage runs in the cluster. It uses the token of its own ServiceAccount `backstage`. The cluster URL is `https://kubernetes.default.svc`.
- `rbac.yaml` gives that account read access. The rules come from the Backstage docs.
- Each Component has the annotation `backstage.io/kubernetes-label-selector: app=<name>`. The Boutique pods carry the label `app: <name>`. So the manifests of Boutique stay unchanged.

## Security

- The guest login is on outside development (`dangerouslyAllowOutsideDevelopment: true`). Anyone who reaches Backstage signs in as guest.
- Traefik listens on port 80 of all network interfaces of the host. A machine on your LAN can send the header `Host: backstage.localhost` and reach Backstage. The hostname is a name, not a lock.
- The Kubernetes plugin uses one account for all users. A guest sees what the role allows.
- The role allows reading pods, Services, Deployments, ConfigMaps, and more in all namespaces.
- The Kubernetes API of Backstage accepts only entities that exist in the catalog. A test with a forged entity for `kube-system` got the answer `403`. The permission policy of the image allows all actions. So I expect a guest can add an entity through the catalog API, with any namespace in its annotations. I did not test this.
- To close the gap, put the GitHub login in place. It needs your own image. Until then, use this setup on a trusted network only.

To switch the route off, set `httpRoute.enabled: false` in `values.yaml`. Set both `baseUrl` values back to `http://localhost:7007`. Run the `helm upgrade` again. Then use `kubectl port-forward -n backstage svc/backstage 7007:7007`.

## Undo

```bash
helm uninstall backstage -n backstage
kubectl delete -f rbac.yaml -f postgres.yaml
kubectl delete secret postgres -n backstage
kubectl delete -f namespace.yaml
```

The last command removes the namespace and the Postgres volume.
