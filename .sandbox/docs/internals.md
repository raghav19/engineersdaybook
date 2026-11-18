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

The architecture diagram names the files: the unit file of each container, the folder of its image, the proxy configs, the CA and the credential.

The network path of the agent sandbox and the builder, inside gVisor:

[![The network path of the sandbox with gVisor](diagrams/sandbox-network.png)](diagrams/sandbox-network.svg)

Quadlet turns each `.container` file into a systemd service. The service holds the limits of the whole sandbox, because gVisor ignores the limits of Podman:

[![How Quadlet controls the sandbox](diagrams/quadlet.png)](diagrams/quadlet.svg)

## The flows

### One call from the agent sandbox

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
        BK->>BK: run the step as root in the builder
        BK->>Relay: download a package
        Relay->>BP: through proxy.sock and socat
        BP->>Reg: only a host in the allowlist
    end
    BK-->>Agent: send the image as a tar on buildkitd.sock
    Agent->>Agent: write the tar file in the agent sandbox
```

A failed build gives a code other than 0. The builder proxy holds no token, so a base image comes from a public registry. For a private base image, the agent sandbox pulls it with `crane` through the host proxy. It then passes the image to `docker build` as an OCI layout.

### One push

The agent sandbox pushes the tar file. The builder takes no part in the push and holds no login.

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
