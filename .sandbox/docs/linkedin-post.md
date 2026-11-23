# LinkedIn post: the agent sandbox

## Post

```text
I built my own agent sandbox. Here is why.

Your coding agent has your repo, your tokens and a network connection.

One poisoned issue or web page can make it use all three.

Three things together make an agent risky:

1. It reads text that you did not write: web pages, issues, packages.
2. It reaches private data: your repo, your files, your tokens.
3. It can send data out: a git push, an API call, a web request.

A filter that stops most attacks is not enough. One missed attack is enough. The agent has to read, so I cannot remove the first one.

So I limit the damage. My agent sandbox:

1. Has no network device. The only way out is a Unix socket file that leads to a proxy.
2. Holds placeholders, not tokens. The real tokens stay in the proxy.
3. Checks each request. The proxy allows listed hosts, methods and paths. A merge, a file removal, a gist, a fork and GraphQL get a 403.
4. Builds images in a second container. That container has no token, no network device and its own proxy.
5. Runs in rootless Podman and gVisor. Each container has memory and CPU limits.

The agent can still be fooled. But it has no real token to steal, and it has one narrow door.

The limits, in plain words:

• gVisor is not a microVM.
• A bug in the proxy can expose the real tokens.
• The sandbox does not stop prompt injection. It limits the damage.

The picture shows the architecture on top and the security controls below.

What can your agent reach today?

#AIAgents #PromptInjection #AppSec #Podman #gVisor
```

## Image

Upload `diagrams/sandbox-architecture-and-controls.png`.

## Alt text

Two diagrams in one image. The top diagram shows the agent sandbox, the builder, the two proxies and the Internet. The bottom diagram lists the security controls of each container.
