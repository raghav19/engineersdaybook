# engineersdaybook
my dabbling with tech and perspectives

This repo holds my engineering projects and write-ups. Each project is independent. Open the README of a project to run it.

The Status column shows how far each project has come. **Done** means the project works as its README says. **In progress** means the project is not finished. Its README says what is missing.

## Sandboxing agents and MCP

| Project | Status | What it achieves |
|---|---|---|
| [agent-sandbox with Docker sbx](https://github.com/raghav19/engineersdaybook/tree/docker-sbx/code/agent-sandbox) | Done | Runs Claude Code in an `sbx` microVM with no real credential. A fooled agent can do only what the sandbox allows. This is the git tag `docker-sbx`. |
| [agent-sandbox with microsandbox](code/agent-sandbox/README.md) | Done | Runs Claude Code in a microsandbox VM with no real token. A fooled agent can do only what the sandbox allows. SPIRE node attestation and the kind kubeconfig are not ported yet. |
| [mcp-sandbox, part 1](code/mcp-sandbox/part-1-lethal-trifecta/README.md) | Done | Tests the "lethal trifecta" against real GitHub infrastructure. The agent recognized the injected instruction twice and refused. |
| [mcp-sandbox, part 2](code/mcp-sandbox/part-2-sandboxing-local-mcp/README.md) | Done | Seals a local MCP server in rootless Docker. An egress proxy logs each outbound attempt. |
| [mcp-sandbox, part 3](code/mcp-sandbox/part-3-mcp-guardrails/README.md) | **In progress** | Puts one gateway in front of three MCP servers. It checks identity, arguments and results against the OWASP MCP Top 10. Not finished: access logs and traces (MCP08) are not wired, and the guardrail suite is still being built. |
| [rootless-docker](code/rootless-docker/README.md) | Done | Moves the Docker daemon to a non-root user. Three container-escape CVEs show where this blocks the escape. |

## Zero trust

| Project | Status | What it achieves |
|---|---|---|
| [zero trust: node attestation](code/mcp-sandbox/part-3-mcp-guardrails/docs/zero-trust-node-attestation.md) | **In progress** | The sandbox microVM proves who it is to a SPIRE server before anyone trusts it. This is the first guardrail of part 3. It follows the zero trust rule of no implicit trust. Five of six parts are done. The cleanup of the other pages is planned. |
| [agent workload identity](code/agent-workload-identity/README.md) | **In progress** | Gives each agent microVM its own SPIFFE ID, with the private key on the host. The plugin and the delegate exist, with unit tests. The host agent config, the registration entries and the end-to-end test do not. |

## GitOps

| Project | Status | What it achieves |
|---|---|---|
| [app of apps pattern](code/mcp-sandbox/part-3-mcp-guardrails/docs/app-of-apps-pattern.md) | Done | Groups the 13 units of part 3 into three Flux groups. One object shows the health of each chain, for example the mesh that runs SPIRE. |
| [rendered manifest pattern](code/mcp-sandbox/part-3-mcp-guardrails/docs/rendered-manifest-pattern.md) | Done | Renders the manifests of part 3 in CI. A pull request shows the rendered diff. Flux applies plain YAML from an OCI artifact. |

## Local infra and config

| Project | Status | What it achieves |
|---|---|---|
| [devk8s-kind-wsl2](code/devk8s-kind-wsl2/README.md) | Done | Builds a local Kubernetes stack with kind on WSL2. It adds operators, routes and four dashboards. |
| [configuration-heirarchies](code/configuration-heirarchies/README.md) | Done | Shows how infra variables inherit from `DEV` to `dev01` to `user1`. Check it with `ansible-inventory`. |
| [env-config-management](code/env-config-management/README.md) | Done | Applies the same pattern to local tools and env vars with `mise`. |

## Writing

- [How I went from idea to ship without writing a line of spec myself](blog/spec-driven-workflow/post.md): a spec-first workflow for coding agents.

## Licence

See [LICENSE.txt](LICENSE.txt).
