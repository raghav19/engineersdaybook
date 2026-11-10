# Diagrams

| File | Use |
|---|---|
| `architecture.drawio` | The source of the architecture diagram. It shows the agent container (rootless Podman, hardened) with the agent tools, the relay and the clone of the repo in the volume `sandbox-home`. It shows the repo in clone mode and the Unix socket as the only way out. It shows the socket bridge and iron-proxy with the allowlist, the TLS and the token swap. It also shows Bitwarden Secrets Manager and the Internet. |
| `architecture.svg` | The diagram as a plain SVG: real `<text>` elements, a white background and no `foreignObject`. It is drawn from the coordinates of the `.drawio` file. The export of draw.io wraps each label in `foreignObject` and uses `light-dark()` colors. Many viewers do not draw them. |
| `architecture.png` | The PNG of the SVG, 2x with a white background. Make it with `rsvg-convert -z 2 -b white architecture.svg -o architecture.png`. |

After an edit of the `.drawio` file, change the SVG in the same way, then make the PNG again. The developer workflow is a mermaid flowchart in `../../README.md`.
