# Platform engineering

A lab to learn Backstage on a local k3s cluster. The test app is Online Boutique, the microservices demo of Google.

The repo has two parts:

- `infrastructure/` holds the shared platform. The platform team owns it.
- `apps/` holds what runs on the platform. Each app team owns its folder.

## Map

```text
code/platform-engineering/
├── README.md
├── infrastructure/
│   └── gateway/        # Traefik with the Gateway API, and the CRD pin
├── apps/               # next PR: Online Boutique and its HTTPRoute
└── docs/               # last PR: one document per topic, with diagrams
```

The Backstage portal goes in `infrastructure/backstage/`. It is a shared service. The catalog files of an app stay in the folder of the app.

## Steps

| PR | Content | Status |
|---|---|---|
| 1 | [Gateway](infrastructure/gateway/README.md): Traefik with the Gateway API | this PR |
| 2 | Online Boutique and its `HTTPRoute` | planned |
| 3 | Backstage and the catalog of Online Boutique | planned |
| 4 | Docs and diagrams | planned |

## Cluster

One k3s node on the host. Traefik and the Gateway API CRDs come with k3s. The sandbox VM reaches only the API server of the cluster (port 6443). To open an app, use the browser on the host, or use `kubectl port-forward` in the sandbox.
