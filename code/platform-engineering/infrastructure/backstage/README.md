# Backstage

Backstage is the developer portal. It shows what runs on the platform: who owns it, what it needs, and what state it is in.

The platform team owns this folder. It runs Backstage in the namespace `backstage`. The Helm chart is the official Backstage chart, version `2.10.2`. The image is the demo image `1.55.2`.

## Limits of the demo image

The chart runs the image that `npx @backstage/create-app` makes. You cannot add plugins to it. These limits follow:

- The image has the guest login only. It has no GitHub login. A GitHub login needs your own image.
- The image has the Kubernetes plugin and the MCP actions plugin. I expect it has no `AiResource` catalog kind. Check this when you need it.
- There is no `HTTPRoute` yet. You open Backstage with `kubectl port-forward`.

## Files

| File | Content |
|---|---|
| `namespace.yaml` | The namespace `backstage`. |
| `postgres.yaml` | Postgres with the official image `postgres:17.11-alpine` and a 2Gi volume. |
| `rbac.yaml` | A read-only `ClusterRole` and its binding to the ServiceAccount `backstage`. |
| `values.yaml` | The values for the Helm chart: image, database, login, catalog, Kubernetes plugin. |

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
kubectl port-forward -n backstage svc/backstage 7007:7007
```

Open `http://localhost:7007` in the browser. Choose the guest login. Then check these pages. The page names come from the Backstage getting-started guide.

1. **Catalog (`Home`):** set the filter `Owner` to `All`. The default is `Owned`, and the guest owns nothing, so the list is empty until you change it. You see the 11 Components. Set `Kind` to `System`, `Resource`, `Group` or `User` to see the others.
2. **System `online-boutique`:** the cards `Has components` and `Has Resources`.
3. **Component `frontend`:** the card `About` shows the owner and the system. The card `Relations` shows the links. Select `View graph` to open the Catalog Graph.
4. **Component `frontend`, tab Kubernetes:** the pod, the Service, the Deployment and the ReplicaSet of `frontend`.
5. **User `raghav19`:** set `Kind` to `User` and select `raghav19`. Toggle `Aggregated Relations` to see the entities that the user owns through the group.

The log has one expected warning: `backend.baseUrl is set to a localhost URL`. It is true, because you reach Backstage through the port-forward.

## How the catalog gets the Boutique

`values.yaml` holds two catalog locations. They are URLs of files in this repo on the branch `main`:

- `apps/boutique/catalog/catalog-info.yaml` holds the System, the 11 Components and the Resource.
- `apps/boutique/catalog/org.yaml` holds the Group `boutique-team` and the User `raghav19`.

The [README of the catalog](../../apps/boutique/catalog/README.md) explains how the entities link, with a diagram.

The app team owns these files. Backstage reads them again at intervals. A change on `main` shows in Backstage without a new install. The org file needs the rule `allow: [User, Group]` on its location.

The chart loads only the config it makes. It does not load the config file of the image. So `values.yaml` sets two keys that the image config would set:

- `catalog.rules`. Without it, Backstage rejects the kind `System`.
- `app.packages: all`. The image holds the plugins for Kubernetes, org pages, the catalog graph, and more. The frontend code turns on these plugins only when the key is `all`. Without it, you see the catalog pages only, and the Kubernetes tab is missing.

## How the Kubernetes tab works

- Backstage runs in the cluster. It uses the token of its own ServiceAccount `backstage`. The cluster URL is `https://kubernetes.default.svc`.
- `rbac.yaml` gives that account read access. The rules come from the Backstage docs.
- Each Component has the annotation `backstage.io/kubernetes-label-selector: app=<name>`. The Boutique pods carry the label `app: <name>`. So the manifests of Boutique stay unchanged.

## Security

- The guest login is on outside development (`dangerouslyAllowOutsideDevelopment: true`). Anyone who reaches the port signs in as guest.
- The Kubernetes plugin uses one account for all users. A guest sees what the role allows.
- So keep the access to the `kubectl port-forward` on your own machine. Do not add an `HTTPRoute` before the GitHub login exists.

## Undo

```bash
helm uninstall backstage -n backstage
kubectl delete -f rbac.yaml -f postgres.yaml
kubectl delete secret postgres -n backstage
kubectl delete -f namespace.yaml
```

The last command removes the namespace and the Postgres volume.
