# Diagrams

| File | Use |
|---|---|
| `architecture.drawio` | The source of the architecture diagram. It shows your terminal and the repo. It shows the agent container (rootless Podman, hardened, in gVisor) with the agent tools and the clone of the repo in the volume `sandbox-home`. The agent tools work in that clone. A Quadlet service holds the limits of the container. It shows the only way out, the host proxy (allowlist, TLS and token swap), Bitwarden Secrets Manager and the Internet. An nftables rule lets only your user connect to the ports of the proxy. The label of the only way out names the `socat` relay and the Unix socket. The path in detail is in `sandbox-network.drawio`. |
| `architecture.svg` | The diagram as a plain SVG: real `<text>` elements, a white background and no `foreignObject`. It is drawn from the coordinates of the `.drawio` file. The export of draw.io wraps each label in `foreignObject` and uses `light-dark()` colors. Many viewers do not draw them. |
| `architecture.png` | The PNG of the SVG, 2x with a white background. Make it with `rsvg-convert -z 2 -b white architecture.svg -o architecture.png`. |
| `sandbox-network.drawio` | The source of the network diagram. It shows the path from the agent tools to the internet. The path has the empty container network namespace, the gVisor sentry with `socat`, the gVisor gofer, the file `proxy.sock`, `sandbox-bridge.service`, iron-proxy and the allowed hosts. Each line has a label for its carrier (TCP, Unix socket or HTTPS). A red box shows the firewall rule on the proxy ports. |
| `sandbox-network.svg` | The network diagram as a plain SVG, drawn from the coordinates of the `.drawio` file in the same way as `architecture.svg`. |
| `sandbox-network.png` | The PNG of that SVG, made with `rsvg-convert -z 2 -b white sandbox-network.svg -o sandbox-network.png`. |

After an edit of the `.drawio` file, change the SVG in the same way, then make the PNG again. The developer workflow is a mermaid flowchart in `../../README.md`.
