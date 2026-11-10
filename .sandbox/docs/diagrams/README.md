# Diagrams

| File | Use |
|---|---|
| `architecture.drawio` | The source of the architecture diagram. It shows the host and the sandbox container with its limits (user `agent`, no capabilities, `--network none`, read-only root), its relay and the volume `sandbox-home`. It shows the Unix socket as the only way out, the socket unit with `systemd-socket-proxyd`, and iron-proxy with its three steps: the allowlist, the TLS CA and the token swap. It also shows the Bitwarden project, the systemd credential and the allowed hosts. |
| `architecture.svg` | The diagram as a plain SVG: real `<text>` elements, a white background and no `foreignObject`. It is drawn from the coordinates of the `.drawio` file. The export of draw.io wraps each label in `foreignObject` and uses `light-dark()` colors. Many viewers do not draw them. |
| `architecture.png` | The PNG of the SVG, 2x with a white background. Make it with `rsvg-convert -z 2 -b white architecture.svg -o architecture.png`. |

After an edit of the `.drawio` file, change the SVG in the same way, then make the PNG again. The developer workflow is a mermaid flowchart in `../../README.md`.
