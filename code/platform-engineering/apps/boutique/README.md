# Online Boutique

Online Boutique is the microservices demo of Google. It has 11 services that talk over gRPC. A `redis-cart` pod stores the carts.

This folder runs release `v0.10.7` in the namespace `boutique`. It adds one `HTTPRoute`. The route sends all requests to the Service `frontend`.

## Files

| File | Content |
|---|---|
| `kustomization.yaml` | The release manifest, pinned by commit hash. A patch that removes the Service `frontend-external`. |
| `namespace.yaml` | The namespace `boutique`. |
| `httproute.yaml` | The route from the Gateway `traefik-gateway` to the Service `frontend`. |

The release makes `frontend-external` a `LoadBalancer` on port 80. Traefik already holds node port 80 through ServiceLB. So the patch removes that Service, and the route is the only way in.

## Catalog

The folder `catalog/` describes Online Boutique for Backstage. Its [README](catalog/README.md) explains the structure with a diagram. The setup of Backstage is in [infrastructure/backstage](../../infrastructure/backstage/README.md).

| File | Content |
|---|---|
| `catalog/catalog-info.yaml` | The System `online-boutique`, 11 Components, and the Resource `redis-cart`. |
| `catalog/org.yaml` | The Group `boutique-team` and the User `raghav19`. |

Each Component lists the services it calls in `dependsOn`. The list comes from the `*_ADDR` variables in the release manifest.

## Apply

```bash
kubectl apply -k .
```

## Check

```bash
kubectl get pods -n boutique                 # 12 pods, all 1/1 Running
kubectl get httproute frontend -n boutique \
  -o jsonpath='{range .status.parents[*].conditions[*]}{.type}={.status}{"\n"}{end}'
# Accepted=True
# ResolvedRefs=True
```

Open `http://192.168.178.188` in the browser on the host.

The sandbox VM cannot reach that address. Use the API server instead:

```bash
kubectl port-forward -n kube-system deploy/traefik 8000:8000 &
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/   # 200
```

## Undo

```bash
kubectl delete -k .
```

This removes the namespace `boutique` and everything in it.
