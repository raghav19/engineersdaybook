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
| `security-controls.drawio` | Source of the security controls diagram. Two lanes mirror each other around a `Host kernel` box: the agent sandbox above it and the builder below it. Each lane goes from the sandbox through `proxy.sock` to a proxy container and the Internet. A legend at the bottom names the colors. The diagram is the list of controls in the section "Security controls" of `../../README.md`. When you edit it, keep the lanes mirrored in size, position and layout. Keep each title 10 px from the left edge and 8 px from the outer edge. Keep each arrow label 8 px from its line and each arrow 2 px thick. |
| `security-controls.svg` | The security controls diagram as a plain SVG, drawn in the same way. |
| `concepts.drawio` | Source of the concepts diagram. It follows the six numbered concepts of the guide that `../../README.md` links: 1 the sandbox, 2 the workspace, 3 the network gate, 4 the key holder, 5 the saved state and 6 you. The labels are generic, so the diagram applies to any agent sandbox. Do not add the names of this sandbox. The table under the diagram in `../../README.md` holds them. A dashed box is the sandbox. It holds the agent, the software, the workspace and the saved state. The network gate, the key holder and the outside services are on the right. |
| `concepts.svg` | The concepts diagram as a plain SVG, drawn in the same way. |
| `sandbox-architecture-and-controls.drawio` | Source of the combined diagram for a post. Stacks two diagrams in one image: `architecture.drawio` on top and `security-controls.drawio` below. Each keeps its own title and content. Every cell id has the prefix `arch-` or `sec-`. |
| `sandbox-architecture-and-controls.svg` | The combined diagram as a plain SVG. Each diagram sits in a nested `<svg>` with its original coordinates. |
| `sandbox-architecture-and-controls.png` | The PNG of that SVG, 2x with a white background. |

After you edit a `.drawio` file:

1. Change the SVG at the same coordinates.
2. Make the PNG: `rsvg-convert -z 2 -b white <name>.svg -o <name>.png`.
3. Read every label in the PNG, as `docs/agents/diagrams.md` requires.

The flows are mermaid diagrams in the section "Flows" of `../../README.md`.
