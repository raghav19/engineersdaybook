# Diagrams

| File | Use |
|---|---|
| `architecture.drawio` | Source of the architecture diagram. Shows your terminal, the repo, the agent sandbox, the builder, both proxy containers, Bitwarden and the internet. Each container is three nested boxes: the sandbox, Podman and gVisor. Each has the same `socat relay` box with an `HTTPS_PROXY` arrow in. A `connect` arrow goes from the relay to a `proxy.sock` box, which is the shared file, and from the file to its proxy container. The agent sandbox reaches the builder with `docker` over `buildkitd.sock`. A Quadlet service holds the limits of each container. A grey box shows the services of the two proxies. Small mentions name the files: the unit file, the image folder and the config of each part. Two notes name the files that `setup` makes and the files that hold the placeholders. |
| `architecture.svg` | The diagram as a plain SVG with real `<text>` elements and a white background. Drawn from the coordinates of the `.drawio` file. |
| `architecture.png` | The PNG of the SVG, 2x with a white background. Make it with `rsvg-convert -z 2 -b white architecture.svg -o architecture.png`. |
| `sandbox-network.drawio` | Source of the network diagram. Shows two lanes, one for the agent sandbox and one for the builder. Each lane has the network namespace, the sentry with the `socat` relay, the gofer, `proxy.sock` and its proxy container. The proxy container has a `socat` and `iron-proxy`. An orange box shows the systemd credential that the host proxy mounts. The host proxy ends TLS (`mitm`) and applies the path rules. The builder proxy passes TLS through (`sni-only`). An arrow shows `docker build` from the agent sandbox to `buildkitd` over `buildkitd.sock`. Each line names its carrier. |
| `sandbox-network.svg` | The network diagram as a plain SVG, drawn in the same way. |
| `sandbox-network.png` | The PNG of that SVG, made with `rsvg-convert -z 2 -b white sandbox-network.svg -o sandbox-network.png`. |
| `build-push.drawio` | Source of the build and push diagram. Shows the path of `docker build` from the agent sandbox to the builder, the tar file, and the path of `crane push` through the host proxy to `ghcr.io`. |
| `build-push.svg` | The build and push diagram as a plain SVG, drawn in the same way. |
| `build-push.png` | The PNG of that SVG, made with `rsvg-convert -z 2 -b white build-push.svg -o build-push.png`. |
| `quadlet.drawio` | Source of the Quadlet diagram. Shows the four `.container` files, the Quadlet generator, and the four services in one box. Each service shows its limits. A `Requires` arrow joins each service to the service that it needs. Two notes say that the limits are in the service and that the builder and both proxies are part of the agent. |
| `quadlet.svg` | The Quadlet diagram as a plain SVG, drawn in the same way. |
| `quadlet.png` | The PNG of that SVG, made with `rsvg-convert -z 2 -b white quadlet.svg -o quadlet.png`. |

After an edit of a `.drawio` file, change the SVG in the same way, then make the PNG again. The flows are mermaid diagrams in `../internals.md`.
