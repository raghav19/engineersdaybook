# How the sandbox works in detail

## The idea

- The agent sandbox and the builder have `Network=none`. Only a Unix socket leads to the host.
- A relay in each of them turns the proxy address that tools expect into that socket.
- Each proxy runs in its own container, with the default Podman network. A `socat` in that container joins the socket to `iron-proxy`.
- The host proxy holds the real tokens. The builder proxy holds none. The diagram of the security controls calls the host proxy the agent proxy.
- Both proxies allow listed hosts only.
- The host proxy ends the TLS with its CA, so it can read each request. The builder proxy passes the TLS through.
- The agent sandbox sends a build to the builder through a socket in a shared folder.
- Quadlet turns each container file into a systemd service. The service limits memory, CPU and threads, because gVisor ignores the limits of Podman.

## The picture

[![The agent sandbox and the builder](diagrams/architecture.png)](diagrams/architecture.svg)

The network path of the agent sandbox and the builder, inside gVisor:

[![The network path of the sandbox with gVisor](diagrams/sandbox-network.png)](diagrams/sandbox-network.svg)

How Quadlet controls the sandbox:

[![How Quadlet controls the sandbox](diagrams/quadlet.png)](diagrams/quadlet.svg)

The controls of each container are in the diagram in the section "Security controls" of `../README.md`.

## The flows

### One call from a container

Both containers follow this path. Only the relay port, the proxy and the rule set differ.

```mermaid
sequenceDiagram
    participant Tool
    participant Relay as relay socat
    participant gVisor
    participant Socat as socat in the proxy container
    participant Proxy as iron-proxy
    participant Host as Listed host
    Tool->>Relay: connect to 127.0.0.1:3128 (agent sandbox) or 127.0.0.1:3129 (builder)
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
    alt the host is in neither domains nor rules
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

A host in `domains` takes every method and every path. A host in `rules` takes only the methods and the paths of its rules, so a write goes to one GitHub repository only. The builder proxy has no path rules, because it cannot see a path.

### One build

The agent sandbox sends the build. The builder runs it. The builder reaches the internet only through its own proxy.

```mermaid
sequenceDiagram
    participant Agent as docker in the agent sandbox
    participant BK as buildkitd in the builder
    participant Relay as relay in the builder
    participant BP as builder proxy
    participant Reg as registry and package hosts
    Agent->>BK: docker build, send the context on buildkitd.sock
    BK->>Relay: FROM, pull the base image
    Relay->>BP: through proxy.sock and socat
    alt the host is in the allowlist
        BP->>Reg: pull the layers
        Reg-->>BK: the layers
    else the host is not in the allowlist
        BP-->>BK: 403
    end
    loop each RUN step
        BK->>BK: run the step as root inside the rootless build
        BK->>Relay: download a package
        Relay->>BP: through proxy.sock and socat
        BP->>Reg: only a host in the allowlist
    end
    BK-->>Agent: send the image as a tar on buildkitd.sock
    Agent->>Agent: write the tar file in the agent sandbox
```

The builder proxy holds no token, so a base image comes from a public registry. For a private base image, the agent sandbox pulls it with `crane` through the host proxy. It then passes the image to `docker build` as an OCI layout.

### One push

Only the agent sandbox pushes the tar file.

```mermaid
sequenceDiagram
    participant crane as crane in the agent sandbox
    participant Relay as relay in the agent sandbox
    participant HP as host proxy
    participant GH as ghcr.io
    crane->>Relay: push the tar file, login with the placeholder
    Relay->>HP: through proxy.sock and socat
    alt the path is in the namespace raghav19
        HP->>HP: replace the placeholder with the real token
        HP->>GH: send each blob and the manifest
        GH-->>crane: the digest of the image
    else the path is in another namespace
        HP-->>crane: 403
    end
```
