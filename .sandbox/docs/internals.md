# How the sandbox works in detail

## The idea

- Each container has no network. Only a file can cross to the host.
- A relay in the container turns the proxy address that tools expect into that file.
- Each proxy runs in its own container. A `socat` there joins the file to the proxy.
- The host proxy holds the real tokens. The builder proxy holds none.
- Both proxies allow listed hosts only. The host proxy also checks the method and the path, so a write goes to one GitHub repository only.
- The agent sandbox sends a build to the builder through a socket in a shared folder.
- Quadlet turns each container file into a systemd service. The service limits memory, CPU and threads.

## The picture

[![The agent sandbox and the builder](diagrams/architecture.png)](diagrams/architecture.svg)

The network path of the agent sandbox and the builder, inside gVisor:

[![The network path of the sandbox with gVisor](diagrams/sandbox-network.png)](diagrams/sandbox-network.svg)

Quadlet turns each `.container` file into a systemd service. The service holds the limits of the whole sandbox, because gVisor ignores the limits of Podman:

[![How Quadlet controls the sandbox](diagrams/quadlet.png)](diagrams/quadlet.svg)

## The cast

In the agent sandbox:

| Part | Job |
|---|---|
| `sleep infinity` | The command of the container. It keeps the container alive. An init process passes the stop signal to it. |
| relay (`socat`) | Started by `ExecStartPost`. Listens on `127.0.0.1:3128`. Copies the bytes to `proxy.sock`. |
| `sandbox-start` | Runs with `podman exec` from `ExecStartPost`. Prepares the home and the clone, starts Headroom, writes `/tmp/sandbox-ready`. |
| `docker` and `buildx` | The client of the builder. The read-only folder `/etc/docker` holds its settings. |
| `crane` | Pushes the tar of a build. Reads the placeholder login from `/etc/docker/config.json`. |

In the builder:

| Part | Job |
|---|---|
| `buildkitd` | BuildKit, rootless. Runs each build step as root in the builder. |
| relay (`socat`) | Started by `ExecStartPost`. Listens on `127.0.0.1:3129`. Copies the bytes to the socket of the builder proxy. |
| cache | A 1 GB `tmpfs`. Holds the layers of the build. |

In gVisor, on the host, as your user:

| Part | Job |
|---|---|
| sentry | The guest kernel. Runs the system calls. |
| gofer | A helper. Opens host files for the sentry. |

In each proxy container:

| Part | Job |
|---|---|
| `socat` | Started by `ExecStartPost`. Listens on `proxy.sock`. Copies the bytes to the tunnel port `127.0.0.1:18080` of `iron-proxy`. |
| `iron-proxy` | The proxy. The host proxy holds the real tokens. The builder proxy checks host names only. |
| `bws` | In the host proxy only. Gets the real tokens from Bitwarden. It reads the credential `bws-token`. |

On the host:

| Part | Job |
|---|---|
| `sandbox-agent.service` | The Quadlet unit of the agent sandbox. Requires the builder and the host proxy. |
| `sandbox-builder.service` | The Quadlet unit of the builder. Requires the builder proxy. |
| `sandbox-proxy.service` | The Quadlet unit of the host proxy container. |
| `sandbox-builder-proxy.service` | The Quadlet unit of the builder proxy container. It uses the mode `sni-only` and holds no token. |

Each unit is a Quadlet `.container` file. The dependencies of the units:

```mermaid
sequenceDiagram
    participant Agent as sandbox-agent.service
    participant HP as sandbox-proxy.service
    participant Builder as sandbox-builder.service
    participant BP as sandbox-builder-proxy.service
    Note over Agent,BP: A start of the agent sandbox
    Agent->>HP: Requires, After: start the host proxy first
    Agent->>Builder: Requires, After: start the builder first
    Builder->>BP: Requires, After: start the builder proxy first
    Note over Agent,BP: A stop or a restart of the agent sandbox
    Agent-->>HP: PartOf: stop or restart the host proxy
    Agent-->>Builder: PartOf: stop or restart the builder
    Agent-->>BP: PartOf: stop or restart the builder proxy
```

`Requires` and `After` start the target first. `PartOf` passes a stop or a restart of the target to the unit. A stop of the agent sandbox stops the builder and both proxies. The real tokens are in memory only while a sandbox runs.

## The flow in phases

### Setup, once

```mermaid
sequenceDiagram
    participant You
    participant just
    participant Files as Your files
    participant systemd
    You->>just: just sandbox setup
    just->>Files: make the CA in ~/.local/state/sandbox if it is missing
    just->>Files: link the two configs of the proxies into ~/.config/sandbox
    opt the credential is missing
        just->>You: ask for the Bitwarden access token
        You-->>just: the token
        just->>Files: encrypt it with systemd-creds into bws-token
    end
    just->>Files: link the four container units, the gVisor flags and repo.git
    just->>systemd: daemon-reload
```

`setup` needs no root and starts no container. Run `just sandbox build` next.

### Build the images

```mermaid
sequenceDiagram
    participant You
    participant just
    participant bws as Bitwarden
    participant podman
    participant ghcr as ghcr.io
    You->>just: just sandbox build
    just->>bws: read GITHUB_TOKEN
    just->>podman: log in to ghcr.io
    just->>podman: build the agent sandbox image
    podman->>ghcr: pull and push the stage cache
    just->>podman: build the builder image
    just->>podman: build the two proxy images
    just->>ghcr: push the commit tag of the agent sandbox image
    just->>podman: log out of ghcr.io
```

### Each run

```mermaid
sequenceDiagram
    participant You
    participant just
    participant systemd
    participant Proxies as Proxy containers
    participant Builder
    participant Agent as Agent sandbox
    You->>just: just sandbox run
    just->>systemd: daemon-reload, restart sandbox-agent.service
    systemd->>Proxies: start both proxies, ExecStartPost: socat on proxy.sock
    systemd->>Builder: start a new builder
    Builder-->>systemd: the health check passes
    systemd->>Builder: ExecStartPost: start the relay
    systemd->>Agent: podman run --replace, runsc, no network
    systemd->>Agent: ExecStartPost: bring up lo, start the relay, run sandbox-start
    systemd-->>just: the service is active
    just->>Agent: check the health, then run herdr
```

The proxies and the builder start first. A failed health check fails the start. The start of each unit has `ExecStartPost` steps, and a failed step fails the start. The agent sandbox is active after `sandbox-start` ends. It is healthy after `sandbox-start` writes `/tmp/sandbox-ready`.

### One call to the outside

Both containers follow this path. Only the relay port, the proxy and the rule set differ.

```mermaid
sequenceDiagram
    participant Tool
    participant Relay as relay socat
    participant gVisor
    participant Socat as socat in the proxy container
    participant Proxy as iron-proxy
    participant Host as Listed host
    Tool->>Relay: connect to 127.0.0.1:3128 or :3129
    Relay->>gVisor: connect to proxy.sock
    gVisor->>Socat: the gofer opens proxy.sock
    Socat->>Proxy: copy the bytes to 127.0.0.1:18080
    alt a rule matches the host, the method and the path
        Proxy->>Host: send the request, host proxy swaps the placeholder
    else no rule matches
        Proxy-->>Tool: 403
    end
```

The host proxy judges each request in this order:

```mermaid
sequenceDiagram
    participant Tool
    participant Proxy as host proxy
    participant Host as The host
    Tool->>Proxy: a request in the tunnel
    alt the host is not in the allowlist or in a rule
        Proxy-->>Tool: 403
    else the method and the path match no rule
        Proxy-->>Tool: 403
    else a rule matches
        opt a placeholder is in a header and the host is in its rule
            Proxy->>Proxy: replace the placeholder with the real token
        end
        Proxy->>Host: send the request
        Host-->>Proxy: the response
        Proxy-->>Tool: the response
    end
```

A host in `domains` takes every method and every path. A host in `rules` takes only the methods and the paths of its rules. The builder proxy has no path rules, because it cannot see a path.

The bytes stay the same. The carrier changes three times: TCP to the relay, a Unix socket to the `socat` in the proxy container, and TCP to the proxy. The host proxy ends the TLS with its CA. The builder proxy passes the TLS through.

### One build

```mermaid
sequenceDiagram
    participant Agent as Agent sandbox
    participant docker
    participant buildkitd
    participant Step as Build step
    participant BP as Builder proxy
    Agent->>docker: docker build --output type=docker
    docker->>buildkitd: send the context on buildkitd.sock
    buildkitd->>BP: pull each FROM image
    buildkitd->>Step: run each RUN step as root in the builder
    Step->>BP: download packages
    buildkitd-->>docker: send the tar of the image
    docker-->>Agent: exit code 0, the tar is in the agent sandbox
```

A failed build gives a code other than 0. The registry token for a pull comes from `docker` in the agent sandbox, through the host proxy.

### One push

```mermaid
sequenceDiagram
    participant crane
    participant HP as Host proxy
    participant GH as ghcr.io
    crane->>HP: push with the placeholder login
    HP->>GH: swap in the real token, send the push
    GH-->>crane: the image is in the registry
```

The builder never pushes and holds no login.
