# Diagrams

| File | Use |
|---|---|
| `architecture.drawio` | Source of the architecture diagram. Shows your terminal, the repo, the agent sandbox, the builder, both proxies, the firewall rule, Bitwarden and the internet. Each container is three nested boxes: the sandbox, Podman and gVisor. Each has the same `socat relay` box with an `HTTPS_PROXY` arrow in and a `Unix socket` arrow out to its proxy. The agent sandbox reaches the builder with `docker` over `buildkitd.sock`. A Quadlet service holds the limits of each container. |
| `architecture.svg` | The diagram as a plain SVG with real `<text>` elements and a white background. Drawn from the coordinates of the `.drawio` file. |
| `architecture.png` | The PNG of the SVG, 2x with a white background. Make it with `rsvg-convert -z 2 -b white architecture.svg -o architecture.png`. |
| `sandbox-network.drawio` | Source of the network diagram. Shows the path of the agent sandbox to the internet. The path has the empty network namespace, the sentry with `socat`, the gofer, `proxy.sock`, the bridge, the host proxy and the allowed hosts. Each line names its carrier. A red box shows the firewall rule. |
| `sandbox-network.svg` | The network diagram as a plain SVG, drawn in the same way. |
| `sandbox-network.png` | The PNG of that SVG, made with `rsvg-convert -z 2 -b white sandbox-network.svg -o sandbox-network.png`. |

After an edit of a `.drawio` file, change the SVG in the same way, then make the PNG again. The flows are mermaid diagrams in `../internals.md`.
