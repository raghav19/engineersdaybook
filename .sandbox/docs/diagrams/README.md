# Diagrams

| File | Use |
|---|---|
| `architecture.drawio` | Source of the architecture diagram. Shows your terminal, the repo, the agent sandbox, the builder, both proxies, the firewall rule, Bitwarden and the internet. Each container is three nested boxes: the sandbox, Podman and gVisor. Each has the same `socat relay` box with an `HTTPS_PROXY` arrow in and a `Unix socket` arrow out to its proxy. The agent sandbox reaches the builder with `docker` over `buildkitd.sock`. A Quadlet service holds the limits of each container. |
| `architecture.svg` | The diagram as a plain SVG with real `<text>` elements and a white background. Drawn from the coordinates of the `.drawio` file. |
| `architecture.png` | The PNG of the SVG, 2x with a white background. Make it with `rsvg-convert -z 2 -b white architecture.svg -o architecture.png`. |
| `sandbox-network.drawio` | Source of the network diagram. Shows two lanes, one for the agent sandbox and one for the builder. Each lane has the network namespace, the sentry with the `socat` relay, the gofer, `proxy.sock`, the bridge and its proxy. The host proxy ends TLS (`mitm`). The builder proxy passes TLS through (`sni-only`). An arrow shows `docker build` from the agent sandbox to `buildkitd` over `buildkitd.sock`. Each line names its carrier. A red box shows the firewall rule for both proxies. |
| `sandbox-network.svg` | The network diagram as a plain SVG, drawn in the same way. |
| `sandbox-network.png` | The PNG of that SVG, made with `rsvg-convert -z 2 -b white sandbox-network.svg -o sandbox-network.png`. |
| `build-push.drawio` | Source of the build and push diagram. Shows the path of `docker build` from the agent sandbox to the builder, the tar file, and the path of `crane push` through the host proxy to `ghcr.io`. |
| `build-push.svg` | The build and push diagram as a plain SVG, drawn in the same way. |
| `build-push.png` | The PNG of that SVG, made with `rsvg-convert -z 2 -b white build-push.svg -o build-push.png`. |
| `quadlet.drawio` | Source of the Quadlet diagram. Shows the two `.container` files, the Quadlet generator, and the two services. Each service is one cgroup with its limits, `podman run --cgroups=split`, `conmon` and the gVisor container. The agent service requires the builder. The builder is part of the agent service. |
| `quadlet.svg` | The Quadlet diagram as a plain SVG, drawn in the same way. |
| `quadlet.png` | The PNG of that SVG, made with `rsvg-convert -z 2 -b white quadlet.svg -o quadlet.png`. |

After an edit of a `.drawio` file, change the SVG in the same way, then make the PNG again. The flows are mermaid diagrams in `../internals.md`.
