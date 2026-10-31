# sandboxing agents

## What we are building

A coding agent you can run without handing it your machine.

- **The agent:** Claude Code, inside a [microsandbox](https://docs.microsandbox.dev) VM (open source, Apache-2.0), working on a private clone of the repo and holding no real token.
- **The MCP servers:** GitHub, draw.io and the Flux schema catalog. The VM loads them from a root-owned settings file that the agent cannot change.
- **The guardrails:** an egress allow list for the VM, token placeholders that the host replaces, and a deny list for the riskiest GitHub tools.

The setup needs a Linux host with `/dev/kvm`, one GitHub App on one repository, and secrets in Bitwarden Secrets Manager. There is no daemon: `msb` starts the VM as a child process, and one file, `.msb/sandbox.yaml`, declares it.

What it shows: a fooled agent is capped to what the sandbox allows. The VM holds no real credential, egress is an allow list, and the damage stays in one repo.

This follows Anthropic's [How we contain Claude across products](https://www.anthropic.com/engineering/how-we-contain-claude): enforce hard limits in the environment instead of relying on the model.

- **Limit what the agent is *able* to do, not what it does.** The VM reaches only the repo clone and the hosts in `network.allow`. A blocked host fails at DNS. A deny list removes five GitHub tools (`merge_pull_request`, `delete_file` and others).
- **Keep credentials out of the sandbox.** The VM holds the placeholders `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN`. The host swaps in the real value in requests to the hosts of that secret only, and blocks each token for every other host.
- **An allowed domain is a capability grant.** Anything in the VM can use every host on the allow list, a container included. Keep `network.allow` to what the work needs. Add a host with `just msb allow-host <host>`.

Earlier parts: [Part 1](../mcp-sandbox/part-1-lethal-trifecta/README.md) shows the attack and [Part 2](../mcp-sandbox/part-2-sandboxing-local-mcp/README.md) contains the MCP server. This part moves the agent itself into a sandbox.

## How it works

| Guardrail | What it limits | Where |
|---|---|---|
| Egress allow list | every host the VM connects to | `network.allow` in `.msb/sandbox.yaml` |
| Token placeholders | GitHub and Claude tokens: the VM never sees them | `secrets:` in `.msb/sandbox.yaml`, `.msb/msb.py` |
| GitHub App scope | what the GitHub token can do: one repository, contents, issues and pull requests, no administration | the app installation (see `.msb/README.md`, prerequisite 2) |
| Managed MCP settings and deny list | which MCP servers load and which GitHub tools are removed | `.msb/image/configs/agents/managed-settings.json` |
| Clone, not the working tree | which host files the VM can read | the VM mounts the `.git` directory read-only and clones from it |

Run it with `just msb setup`, `just msb build` and `just msb run`. The prerequisites, every step and the fixes for common failures are in [`.msb/README.md`](../../.msb/README.md).

## What stays open

- **The deny list is a soft limit.** The client enforces it. The agent can still call the GitHub API with the placeholder token, and the host then uses the token of the GitHub App. The scope of that token sets what the agent can do on GitHub.
- **No rule for a method or a path.** `network.allow` matches hosts only, so nothing at the proxy blocks one HTTP method on `api.github.com`. The App has no Administration permission, which stops a change to the repository settings. Branch protection on `main` (a pull request and one approval) is the control for merges.
- **Tokens last about 8 hours.** After that GitHub and Claude answer 401 to requests from the VM, until you run `just msb run` again.
- **The agent's writes can leave.** Writes reach the one repository the App covers. If it is public, what the agent writes there is public.
- **Prompt injection is not a sandbox control.** The sandbox limits the blast radius. It does not stop the model from following planted instructions.
- **SPIRE and kind are not ported yet.** Node attestation (the SPIRE agent and Envoy in the VM) and the kind kubeconfig come in a separate change. See [`.msb/README.md`](../../.msb/README.md).
