# Flows of the agent sandbox

## The idea

- You build the agent image once for each change of `agent/`.
- Each session starts with `devcontainer up`. `init.sh` runs first, on the host.
- Each request of a tool goes through a proxy. Only the agent proxy holds tokens.
- Each build runs in the builder. Only the agent pushes an image.

## The picture

[![The agent sandbox, the builder and both proxies](diagrams/architecture.png)](diagrams/architecture.svg)

## Once: build the agent image

### Agent image flow

The host builds the agent image and pushes it. The commands are in [Update the agent image](../README.md#update-the-agent-image).

```mermaid
---
title: Agent image flow
---
sequenceDiagram
    participant You
    participant CLI as devcontainer CLI
    participant Docker as Docker on the host
    participant GHCR as ghcr.io
    You->>CLI: devcontainer build --push, tag = git tree sha of agent/
    CLI->>Docker: build agent/Dockerfile
    Docker->>GHCR: read the layer cache (tag cache)
    Docker->>GHCR: push the image and the layer cache
    You->>GHCR: docker buildx imagetools inspect
    GHCR-->>You: the digest
    You->>You: pin tag and digest in compose.yaml, then commit
```

## Each start

### Start flow

`devcontainer up` runs `init.sh` on the host, then starts the containers.

```mermaid
---
title: Start flow
---
sequenceDiagram
    participant You
    participant CLI as devcontainer CLI
    participant Init as init.sh
    participant BW as Bitwarden
    participant Compose as Docker Compose
    participant Agent as agent sandbox
    You->>CLI: devcontainer up
    CLI->>Init: initializeCommand, on the host
    alt the agent proxy runs
        Init-->>CLI: exit, the proxy has its CA and tokens
    else no agent proxy runs
        Init->>Init: make the secrets folder and a new CA
        Init->>BW: bws secret list, with the decrypted access token
        BW-->>Init: the API tokens
        Init->>Init: write one file for each token
    end
    CLI->>Compose: up
    Compose->>Compose: start both proxies and the builder, wait until healthy
    Compose->>Agent: start
    opt a new container
        CLI->>Agent: lifecycle/on-create.sh: home files, clone,<br/>config links, buildx builder
    end
    CLI->>Agent: lifecycle/post-start.sh: shell setup, then /tmp/sandbox-ready
    You->>CLI: devcontainer exec herdr
```

The agent starts only after both proxies and the builder are healthy. The agent is healthy after `lifecycle/post-start.sh` writes `/tmp/sandbox-ready`. A running proxy keeps the CA and the tokens that it read at its start.

## Each request

### Egress request flow

The agent sandbox and the builder follow this path. Only the proxy IP and the rule set differ. Only the agent proxy swaps a placeholder for a token.

```mermaid
---
title: Egress request flow
---
sequenceDiagram
    participant Tool
    participant Proxy as iron-proxy
    participant Host as Listed host
    Note over Tool: A tool that ignores HTTPS_PROXY<br/>gets network unreachable.
    Tool->>Proxy: CONNECT through HTTPS_PROXY<br/>agent 10.200.0.2:18080, builder 10.200.0.10:18080
    alt a rule matches the host, the method and the path
        Proxy->>Host: send the request on the network default
        Host-->>Proxy: the response
        Proxy-->>Tool: the response
    else no rule matches
        Proxy-->>Tool: 403
    end
```

### Request decision flow

The agent proxy judges each request in this order:

```mermaid
---
title: Request decision flow
---
sequenceDiagram
    participant Tool
    participant Proxy as agent proxy
    participant Host as The host
    Tool->>Proxy: CONNECT host:443
    alt the host is in neither domains nor a CONNECT rule
        Proxy-->>Tool: 403
    else the host is listed
        Proxy-->>Tool: the tunnel is open
        Tool->>Proxy: TLS with the proxy CA, then the request
        alt the method and the path match no rule
            Proxy-->>Tool: 403
        else a rule matches
            opt a placeholder is in a header and the host is in its rule
                Proxy->>Proxy: replace the placeholder with the real token
            end
            Proxy->>Host: send the request over a new TLS connection
            Host-->>Proxy: the response
            Proxy-->>Tool: the response
        end
    end
```

The proxy decides on the host at the `CONNECT`, before it sees a path. It reads the method and the path only after it ends TLS with its CA. A host in `domains` takes every method and every path. A host in `rules` takes only the methods and the paths of its rules, so a write goes to one GitHub repository only. The builder proxy has no path rules, because it cannot see a path.

## Each build

### Image build flow

The agent sandbox sends the build. The builder runs it. The builder reaches the internet only through the builder proxy.

```mermaid
---
title: Image build flow
---
sequenceDiagram
    participant Agent as docker in the agent sandbox
    participant BK as buildkitd in the builder
    participant BP as builder proxy
    participant Reg as registry and package hosts
    Agent->>BK: docker build, the context on buildkitd.sock<br/>(gVisor --host-uds=open)
    BK->>BP: FROM, pull the base image through HTTPS_PROXY
    alt the host is in the allowlist
        BP->>Reg: pull the layers
        Reg-->>BK: the layers
    else the host is not in the allowlist
        BP-->>BK: 403
    end
    loop each RUN step
        BK->>BK: run the step as root inside the rootless build
        BK->>BP: download a package through HTTP_PROXY of the step
        BP->>Reg: only a host in the allowlist
    end
    BK-->>Agent: send the image as a tar on buildkitd.sock
    Agent->>Agent: write the tar file in the agent sandbox
```

The docker config of the agent (`configs/docker-config.json`) gives each `RUN` step the builder proxy as `HTTP_PROXY` and `HTTPS_PROXY`.

Run `docker build` as on any host. A normal Dockerfile builds as it is. The agent sandbox has no Docker daemon, so the build writes a tar file:

```shell
docker build -t ghcr.io/raghav19/<NAME>:<TAG> --output type=docker,dest=/tmp/image.tar .
```

The builder proxy holds no token, so a base image comes from a public registry. For a private base image, the agent sandbox pulls it with `crane` through the agent proxy. It then passes the image to `docker build` as an OCI layout.

### Image push flow

Only the agent sandbox pushes the tar file:

```mermaid
---
title: Image push flow
---
sequenceDiagram
    participant crane as crane in the agent sandbox
    participant HP as agent proxy
    participant GH as ghcr.io
    crane->>HP: push the tar file through HTTPS_PROXY,<br/>login: the placeholder in ~/.docker/config.json
    alt the path is in the namespace raghav19
        HP->>HP: replace the placeholder with the real token
        HP->>GH: send each blob and the manifest
        GH-->>crane: the digest of the image
    else the path is in another namespace
        HP-->>crane: 403
    end
```

```shell
crane push /tmp/image.tar ghcr.io/raghav19/<NAME>:<TAG>
```

## Lifetimes

- **CA and tokens:** `init.sh` writes them for each new agent proxy. A running proxy keeps what it read at its start. A logout or a reboot deletes the files.
- **BuildKit cache:** a tmpfs in the builder. Each stop wipes it.
- **Volume `sandbox-home`:** the clone, the logins and the histories. `docker compose -p sandbox down` keeps it.

## Where each part is in the repo

- `../init.sh`: the CA and the tokens.
- `../compose.yaml`: the containers, the networks and the mounts.
- `../lifecycle/`: `on-create.sh` and `post-start.sh`.
- `../policy/agent.yaml` and `../policy/builder.yaml`: the rules of the proxies.
- `../agent/devcontainer.json`: the build config of the agent image.

## What comes next

- [Networking](networking.md)
- [Security controls](security-controls.md)
