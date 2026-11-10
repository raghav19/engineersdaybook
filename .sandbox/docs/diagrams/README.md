# Diagrams

| File | Use |
|---|---|
| `architecture.drawio` | The source of the architecture diagram. It shows the host and the sandbox container with its relay and the volume `sandbox-home`. It also shows the Unix socket, the socket unit with `systemd-socket-proxyd`, iron-proxy, the Bitwarden project and the allowed hosts. |
| `architecture.svg` | The diagram as a plain SVG: real `<text>` elements, a white background and no `foreignObject`. It is drawn from the coordinates of the `.drawio` file. The export of draw.io wraps each label in `foreignObject` and uses `light-dark()` colors. Many viewers do not draw them. |
| `architecture.png` | The PNG of the SVG, 2x with a white background. Make it with `rsvg-convert -z 2 -b white architecture.svg -o architecture.png`. |

After an edit of the `.drawio` file, change the SVG in the same way, then make the PNG again. The developer workflow is a mermaid flowchart in `../../README.md`.
