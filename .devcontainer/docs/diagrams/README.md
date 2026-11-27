# Diagrams

| File | Use |
|---|---|
| `architecture.drawio` | Source of the architecture diagram. Shows the host, the two internal Docker networks and the Internet. On the host: Bitwarden, `init.sh`, the tmpfs folder `$XDG_RUNTIME_DIR/sandbox-secrets`, your terminal and the repo. Each arrow starts at the part that acts: `init.sh` fetches from Bitwarden and writes the folder, and the agent and the agent proxy read the folder with straight arrows up into it. The network `sandbox` holds the agent container and the agent proxy. The network `build` holds the builder container and the builder proxy. Each gVisor container is two nested boxes: the Docker container with its IP and limits, then "gVisor: userspace kernel". The volume `buildkit-sock` sits between the two networks. It is the only link between the agent and the builder. Each proxy reaches the Internet on the Compose network `default`. |
| `architecture.svg` | The diagram as a plain SVG with real `<text>` elements and a white background. Drawn from the coordinates of the `.drawio` file. |
| `architecture.png` | The PNG of the SVG, 2x with a white background. |
| `network.drawio` | Source of the network diagram. A host box holds the three Docker networks: `sandbox` and `build` (internal, /29) on the left, `default` (the Compose bridge) on the right. Each proxy box crosses from its internal network into the network `default`, because one container has an address on both. Two tags on the edges of the box name the two addresses: the fixed one on the left, the Docker pool one on the right. The arrow from the agent or the builder enters the left tag, and the arrow to the Internet leaves the right tag. Each proxy box lists its tunnel address and its loopback listeners. Red notes in each internal network name the two blocked routes: to the Internet (`internal: true`) and to the host (`inhibit_ipv4`). The volume `buildkit-sock` sits between the internal networks: a folder on the host that holds a Unix socket, not a network. Each arrow is straight or has right-angle bends with rounded corners (`curved=0`). |
| `network.svg` | The network diagram as a plain SVG, drawn in the same way. |
| `network.png` | The PNG of that SVG, 2x with a white background. |
| `workflow.drawio` | Source of the workflow diagram. Two lanes of five boxes each. The lane "Build" goes from an edit of `agent/` to the digest pin in `compose.yaml`. The lane "Use" goes from `devcontainer up` to your review and merge on GitHub. One arrow joins the pin to `devcontainer up`, which pulls the pinned image. It enters "Start" right of the lane title. |
| `workflow.svg` | The workflow diagram as a plain SVG, drawn in the same way. |
| `workflow.png` | The PNG of that SVG, 2x with a white background. |
| `security-controls.drawio` | Source of the security controls diagram. Two lanes mirror each other around a `Host kernel` box: the agent sandbox above it and the builder below it. Each lane goes from the sandbox through its internal network to a proxy container and the Internet. At the top right, `init.sh` fetches the tokens from Bitwarden and writes the tmpfs folder, and the agent proxy reads that folder. Each arrow starts at the part that acts. A legend at the bottom names the colors. Each arrow is straight or has right-angle bends with rounded corners (`curved=0`). The diagram is the list of controls in the section "Security controls" of `../../README.md`. When you edit it, keep the lanes mirrored in size, position and layout. Keep each title 10 px from the left edge and 8 px from the outer edge. Keep each arrow label 8 px from its line and each arrow 2 px thick. |
| `security-controls.svg` | The security controls diagram as a plain SVG, drawn in the same way. |
| `security-controls.png` | The PNG of that SVG, 2x with a white background. |
| `concepts.drawio` | Source of the concepts diagram, titled "How to design an agent sandbox". It shows the six numbered concepts of the design pattern: 1 the wall, 2 the workspace, 3 the network gate, 4 the key holder, 5 the saved state and 6 you. Keep each label generic, so the diagram applies to any agent sandbox. The names of this sandbox go in the table under the diagram in `../../README.md`. A grey box is the host computer. In it, a thick blue box is the wall: a user-space kernel or a microVM. The wall holds the agent, the software, the workspace and the saved state in a 2x2 grid. The network gate is on the host, outside the wall. The key holder is an outside secret manager: it sits outside the host, below the outside services. The gate sends requests to the services and gets the real keys from the key holder. Each arrow is straight or has right-angle bends with rounded corners (`curved=0`). |
| `concepts.svg` | The concepts diagram as a plain SVG, drawn in the same way. |
| `sandbox-architecture-and-controls.drawio` | Source of the combined diagram for a post. It shows the Podman design of the posts `../linkedin-post.md` and `../medium-post.md`. Stacks two diagrams in one image: `architecture.drawio` on top and `security-controls.drawio` below. Each keeps its own title and content. Every cell id has the prefix `arch-` or `sec-`. |
| `sandbox-architecture-and-controls.svg` | The combined diagram as a plain SVG. Each diagram sits in a nested `<svg>` with its original coordinates. |
| `sandbox-architecture-and-controls.png` | The PNG of that SVG, 2x with a white background. |

After you edit a `.drawio` file:

1. Change the SVG at the same coordinates.
2. Make the PNG: `rsvg-convert -z 2 -b white <name>.svg -o <name>.png`.
3. Read every label in the PNG, as `docs/agents/diagrams.md` requires.

The flows are mermaid diagrams in the section "Flows" of `../../README.md`.
