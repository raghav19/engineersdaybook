# Diagrams

| File | Use |
|---|---|
| `architecture.drawio` | Source of the architecture diagram. Shows your terminal, the repo, the agent sandbox, the builder, both proxy containers, Bitwarden and the internet. Each container is three nested boxes: the sandbox, Podman and gVisor. Each has the same `socat relay` box with an `HTTPS_PROXY` arrow in. A `connect` arrow goes from the relay to a `proxy.sock` box, which is the shared file, and from the file to its proxy container. The agent sandbox reaches the builder with `docker` over `buildkitd.sock`. A Quadlet service holds the limits of each container. A grey box shows the services of the two proxies. |
| `architecture.svg` | The diagram as a plain SVG with real `<text>` elements and a white background. Drawn from the coordinates of the `.drawio` file. |
| `architecture.png` | The PNG of the SVG, 2x with a white background. |
| `sandbox-network.drawio` | Source of the network diagram. Shows two lanes, one for the agent sandbox and one for the builder. Each lane has the network namespace, the sentry with the `socat` relay, the gofer, `proxy.sock` and its proxy container. The proxy container has a `socat` and `iron-proxy`. An orange box shows the systemd credential that the host proxy mounts. The host proxy ends TLS (`mitm`) and applies the path rules. The builder proxy passes TLS through (`sni-only`). An arrow shows `docker build` from the agent sandbox to `buildkitd` over `buildkitd.sock`. Each line names its carrier. |
| `sandbox-network.svg` | The network diagram as a plain SVG, drawn in the same way. |
| `sandbox-network.png` | The PNG of that SVG. |
| `quadlet.drawio` | Source of the Quadlet diagram. Shows the four `.container` files, the Quadlet generator, and the four services in one box. Each service shows its limits. A `Requires` arrow joins each service to the service that it needs. Two notes say that the limits are in the service and that the builder and both proxies are part of the agent. |
| `quadlet.svg` | The Quadlet diagram as a plain SVG, drawn in the same way. |
| `quadlet.png` | The PNG of that SVG. |
| `security-controls.drawio` | Source of the security controls diagram. Shows two lanes that mirror each other around a `Host kernel` box in the middle: the agent sandbox above it and the builder below it. Each lane goes from the sandbox through `proxy.sock` to a proxy container and the Internet. Each sandbox is a rootless Podman container with a `gVisor: userspace kernel` box that holds the tools and the `socat` relay. Both sandbox titles say `rootless Podman + gVisor`. The proxy titles say `rootless Podman, no gVisor`. A line from each gVisor box leads to the host kernel, so the sandboxes reach the kernel only through gVisor. The proxy containers run without gVisor and their lines lead to the kernel as well. Bitwarden sends the real tokens to the agent proxy. The other docs call it the host proxy. Each `socat` box has TCP on one side and a Unix socket on the other. The arrow into the `socat` of a sandbox shows `HTTPS_PROXY` with `127.0.0.1:3128` (`3129` for the builder). The arrow out of the `socat` of a proxy shows `127.0.0.1:18080`. All four containers have the same layout and the same arrow thickness. The boxes of the way out are next to the kernel: gVisor in a sandbox, and `socat` with `iron-proxy` in a proxy container. The agent sandbox and both proxies show their hardening in one `Hardened container` box. The containers have 7, 9, 9 and 6 controls: the agent sandbox, the builder, the agent proxy and the builder proxy. A line at the left leads from `docker` in the agent sandbox to BuildKit in the builder, over `buildkitd.sock`. A legend at the bottom names the colors of the boxes. The diagram is the list of controls in the section "Security controls" of `../../README.md`. |
| `security-controls.svg` | The security controls diagram as a plain SVG, drawn in the same way. |

After you edit a `.drawio` file:

1. Change the SVG at the same coordinates.
2. Make the PNG: `rsvg-convert -z 2 -b white <name>.svg -o <name>.png`.
3. Read every label in the PNG, as `docs/agents/diagrams.md` requires.

The flows are mermaid diagrams in `../internals.md`.
