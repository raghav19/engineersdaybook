# engineersdaybook
my dabbling with tech and perspectives

This repo holds my engineering projects and write-ups. Each project is independent. Open the README of a project to run it.

## Sandboxing agents and MCP

| Project | What it achieves | Kind |
|---|---|---|
| [agent-sandbox](code/agent-sandbox/README.md) | Runs Claude Code in an `sbx` microVM with no real credential. A fooled agent can do only what the sandbox allows. | setup guide |
| [mcp-sandbox, part 1](code/mcp-sandbox/part-1-lethal-trifecta/README.md) | Tests the "lethal trifecta" against real GitHub infrastructure. The agent recognized the injected instruction twice and refused. | proof of concept |
| [mcp-sandbox, part 2](code/mcp-sandbox/part-2-sandboxing-local-mcp/README.md) | Seals a local MCP server in rootless Docker. An egress proxy logs each outbound attempt. | series part |
| [mcp-sandbox, part 3](code/mcp-sandbox/part-3-mcp-guardrails/README.md) | Puts one gateway in front of three MCP servers. It checks identity, arguments and results against the OWASP MCP Top 10. | series part |
| [rootless-docker](code/rootless-docker/README.md) | Moves the Docker daemon to a non-root user. Three container-escape CVEs show where this blocks the escape. | setup guide |
| [.sbx](.sbx/README.md) | Docker sbx for agent sandboxing. `just sandbox` runs it. | tooling |

## Local infra and config

| Project | What it achieves | Kind |
|---|---|---|
| [devk8s-kind-wsl2](code/devk8s-kind-wsl2/README.md) | Builds a local Kubernetes stack with kind on WSL2. It adds operators, routes and four dashboards. | how-to |
| [configuration-heirarchies](code/configuration-heirarchies/README.md) | Shows how infra variables inherit from `DEV` to `dev01` to `user1`. Check it with `ansible-inventory`. | pattern sample |
| [env-config-management](code/env-config-management/README.md) | Applies the same pattern to local tools and env vars with `mise`. | pattern sample |

## Writing

- [How I went from idea to ship without writing a line of spec myself](blog/spec-driven-workflow/post.md): a spec-first workflow for coding agents.

## Licence

See [LICENSE.txt](LICENSE.txt).
