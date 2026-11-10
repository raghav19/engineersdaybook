# Diagrams

| File | Use |
|---|---|
| `architecture.drawio` | The source of the architecture diagram. It shows your terminal and the repo. It shows the agent container (rootless Podman, hardened) with the agent tools and the clone of the repo in the volume `sandbox-home`. The agent tools work in that clone. It shows the only way out, the host proxy (allowlist, TLS and token swap), Bitwarden Secrets Manager and the Internet. The label of the only way out names the `socat` relay and the Unix socket. The socket bridge is in the text of `../../README.md`. |
| `architecture.svg` | The diagram as a plain SVG: real `<text>` elements, a white background and no `foreignObject`. It is drawn from the coordinates of the `.drawio` file. The export of draw.io wraps each label in `foreignObject` and uses `light-dark()` colors. Many viewers do not draw them. |
| `architecture.png` | The PNG of the SVG, 2x with a white background. Make it with `rsvg-convert -z 2 -b white architecture.svg -o architecture.png`. |

After an edit of the `.drawio` file, change the SVG in the same way, then make the PNG again. The developer workflow is a mermaid flowchart in `../../README.md`.
