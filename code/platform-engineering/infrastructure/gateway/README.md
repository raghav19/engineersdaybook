# Gateway

The gateway is the Traefik that k3s ships. It reads the Gateway API objects. Istio is not used.

## Who owns what

| Part | Owner | Where |
|---|---|---|
| Gateway API CRDs | k3s | `HelmChart gateway-api-crd` in `kube-system` |
| Traefik (version `3.7.13`, k3s chart `41.4.2+up41.4.0`) | k3s | `HelmChart traefik` in `kube-system` |
| Traefik settings for the Gateway API | platform team | [`traefik-config.yaml`](traefik-config.yaml) |
| `GatewayClass` `traefik` and `Gateway` `traefik-gateway` | the Traefik chart | `kube-system` |
| `HTTPRoute` of an app | the app team | the app folder under `apps/` |

## This repo pins the CRDs and does not apply them

k3s installs the Gateway API CRDs. A second copy from this repo would fight with the k3s copy over the same objects. So this repo pins the version and checks it.

Expected: bundle `v1.6.1`, channel `standard`.

```bash
kubectl get crd gateways.gateway.networking.k8s.io \
  -o jsonpath='{.metadata.annotations.gateway\.networking\.k8s\.io/bundle-version}{" "}{.metadata.annotations.gateway\.networking\.k8s\.io/channel}{"\n"}'
# v1.6.1 standard
```

A k3s upgrade can change this version. Run the check after each upgrade. The Traefik docs name the Gateway API version that each Traefik release supports.

Keep `providers.kubernetesGateway.experimentalChannel` off. The experimental channel needs other CRDs.

## Apply

```bash
kubectl apply -f traefik-config.yaml
```

The k3s helm-controller upgrades the Traefik release. The Traefik pod restarts. Port 80 is down for a few seconds.

## Check

```bash
kubectl get gatewayclass                      # traefik, ACCEPTED True
kubectl get gateway -n kube-system            # traefik-gateway, PROGRAMMED True, ADDRESS 192.168.178.188
kubectl get gateway traefik-gateway -n kube-system \
  -o jsonpath='{range .status.listeners[*]}{.name}{" attachedRoutes="}{.attachedRoutes}{"\n"}{end}'
# web attachedRoutes=0   (no app route yet)
```

The sandbox VM cannot reach `192.168.178.188`. Test through the API server instead:

```bash
kubectl port-forward -n kube-system deploy/traefik 8000:8000 &
curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:8000/   # 404, because no route exists yet
```

From the host, `curl http://192.168.178.188/` also returns `404`.

## Why port 8000

The Traefik entry point `web` listens on port 8000 in the pod. The Service maps port 80 to it. A Gateway listener port must match an entry point port. So the listener uses 8000.

## Undo

```bash
kubectl delete -f traefik-config.yaml
```

The Gateway API provider turns off. The `GatewayClass` and the `Gateway` disappear. The Ingress and CRD providers of Traefik keep working.
