# Part 2.1: sandboxing the dev agent

## The problem

A coding agent that runs on your machine runs as you: it can read what you can read and use what you can use. Anyone who can put text in front
of it can try to steer it, through a GitHub issue, a web page or a tool result, and the agent cannot reliably tell their text from yours.

Earlier parts: [Part 1](../part-1-lethal-trifecta/README.md) shows the attack and [Part 2](../part-2-sandboxing-local-mcp/README.md) contains the MCP server. This part moves the agent itself into a sandbox.

## The solution

Claude Code runs inside an `sbx` microVM, on a private clone of the repo, and holds no real credential. The host adds a short-lived GitHub token
only on requests to the GitHub MCP server. Every other outbound request goes through an egress allow list, with a deny list on top (both in `.sbx/dev-tools.yaml`).

This follows Anthropic's [How we contain Claude across products](https://www.anthropic.com/engineering/how-we-contain-claude) (May 25, 2026): enforce hard limits in the environment (sandbox, egress controls, credentials kept out) instead of relying on the model. The quotes and the layer-by-layer mapping are in the [notes](docs/research/readme-notes.md).

### How the sandbox is laid out

```text
HOST (your machine)
┌────────────────────────────────────────────────────────────────────────┐
│ sbx daemon: creates and manages the sandboxes                          │
│                                                                        │
│ ┌─ microVM: one per sandbox, own kernel, Docker daemon, packages ────┐ │
│ │ agent: Claude Code. Holds placeholders, no real credential.        │ │
│ │ repo: a private clone; the host repo is read-only.                 │ │
│ │ Nothing else of yours: no ~/.ssh, ~/.aws or host secrets.          │ │
│ └─────────────────────────────┬──────────────────────────────────────┘ │
│                               │  every outbound request                │
│                               ▼                                        │
│ ┌─ host proxy ───────────────────────────────────────────────────────┐ │
│ │ 1. egress policy: the allow and deny lists + your sbx policy       │ │
│ │ 2. credential injection: only on the domains you approved in       │ │
│ │    credentials.yaml, swapping the placeholder for the real value   │ │
│ │    from the host secret store (never inside the VM)                │ │
│ └─────────────────────────────┬──────────────────────────────────────┘ │
│                               │                                        │
└────────────────────────────────────────────────────────────────────────┘
                                ▼
                        internet: allow-listed domains only
```

Only two things cross the boundary: the repo (mounted read-only, with the agent working on a private clone) and outbound requests, which go through the proxy.

## Setup

You need sbx, [mise](https://mise.jdx.dev), VS Code, Docker (to build the kit), a GitHub App for the agent's token, and a GitHub token for the ghcr.io
image registry. Install sbx first.

### Install sbx first

Follow Docker's [install guide](https://docs.docker.com/ai/sandboxes/install/) for the requirements (virtualization, `/dev/kvm`, sign-in, disk) and run `sbx diagnose` to check them. On Ubuntu 24.04 or later:

```shell
curl -fsSL https://get.docker.com | sudo REPO_ONLY=1 sh
sudo apt install docker-sbx
```

On other distributions, use the tarball from [github.com/docker/sbx-releases](https://github.com/docker/sbx-releases). That is not a Docker-supported setup; this repo was built that way on Omarchy (Arch-based). When sbx asks for a default network policy, choose **Balanced**: the kit's allow and deny lists are applied on top.

### Then, in this repo

1. Install the host tools (`task`, `yq`, `jq`, `sops`):

```shell
mise trust && mise install
```

2. Put the GitHub App private key at `~/.config/mcp-gh/mcp-gh-local.2026-09-19.private-key.pem`. The App id and installation id are in `.sbx/sbxenv.yaml`.

3. Log in to the registry. The token is in the encrypted `.env.secrets.json`, and your age key decrypts it:

```shell
task sandbox:login
```

4. Set sbx once:

```shell
sbx settings set kit.allowedSources '["docker.io/","ghcr.io/raghav19/dev-agent-sandbox"]'
sbx settings set ssh.agentForwardingEnabled false    # do not forward your SSH agent into the sandbox
sbx daemon restart                                   # applies the setting and ends running sandboxes
```

5. Connect VS Code:

```shell
sbx setup ssh
code --install-extension ms-vscode-remote.remote-ssh
```

6. Install the agent skills:

```shell
task sandbox:install-skills
```

## Run it

```shell
task sandbox:run        # create or start the sandbox and open VS Code on it
```

The first time, sbx shows its plan and asks you to approve it. Run Claude Code in the VS Code terminal: it runs inside the sandbox. Run the task again
to reopen the window.

Other tasks: `task sandbox:build` (maintainer: rebuild and push the tools image) and `task sandbox:update-skills` (refresh the skills).

Egress rules live in the kit image: after changing them, run `task sandbox:build` and create a new sandbox. An existing sandbox keeps the rules it was made with.

## Reference

### Directory structure

```text
.sbx/                               everything that spawns the sandbox
├── Taskfile.yml                    sandbox:login, :install-skills, :update-skills, :build, :setup-vscode, :run
├── sbxenv.yaml                     the sandbox: kits, GitHub App secret, binding
├── dev-tools.yaml                  the kit: tools, completions, shell, egress allow and deny lists, credential (+ its .dockerignore)
├── tools.toml                      the sandbox's tools at exact versions, Terraform cache settings, the completions task
└── scripts/mint-gh-app-token.sh    host minter: App key -> installation token
```

This folder keeps the README, `docs/` and the handoffs.

Repo-root files (`Taskfile.yml`, `mise.toml`, `.env.secrets.json`, `.mcp.json`, `.vscode/`, `AGENTS.md`) and the host paths are listed in the [notes](docs/research/readme-notes.md).

### How it works

```text
EVERY GITHUB MCP CALL

  Claude (in the VM)
    │ request to api.githubcopilot.com
    ▼
  host proxy: domain on the allow list? ──no──▶ 403
    │ yes
    ▼
  token older than 55 min? ──yes──▶ minter runs on the host: signs a JWT with
    │ no                            the App key, gets a short-lived token
    ▼
  proxy adds `Authorization: Bearer <App token>` and forwards the request
```

The kit, egress policy and token minter are explained in the [notes](docs/research/readme-notes.md).

### Getting the agent's work

The agent works on a private clone inside the VM, so nothing it does changes your working tree until you bring it over.
Your IDE sees changes only after you fetch and merge or check out. Only committed work comes over, so ask the agent to
commit on a branch.

```shell
git fetch sandbox-sandbox-dev                               # its branches show up as remote branches in your IDE's Git view
git worktree add ../review sandbox-sandbox-dev/<branch>     # review in a separate folder; your working tree is untouched
git merge --ff-only sandbox-sandbox-dev/<branch>            # or bring it into your working tree
```

Fetch again after the agent commits more. Before `sbx rm`, keep what you want with
`git branch review sandbox-sandbox-dev/<branch>`: removing the sandbox also removes the remote and its fetched branches.

### Threats and what stops them

✅ stopped · ⚠️ partly (gap in brackets) · ❌ not stopped. Rows are grouped by the layers in Anthropic's
[How we contain Claude](https://www.anthropic.com/engineering/how-we-contain-claude): environment, model, external
content, plus monitoring. Part 2.1 describes this directory once the kit is rebuilt and the sandbox recreated. Part 3 is
planned, so its column shows what the design covers.

| Layer | Threat | Part 2: container + proxy | Part 2.1: microVM | Part 3: gateway |
|---|---|---|---|---|
| Environment | Compromised MCP server code | ✅ | ✅ | ✅ |
| Environment | Data leaving the sandbox | ✅ explicit allow-list | ⚠️ (gap: broad baseline domains) | ⚠️ (gap: gateway covers MCP only) |
| Environment | Credentials stolen | ⚠️ (gap: key inside the container) | ✅ | ✅ |
| Environment | Credential used outside its purpose | ⚠️ (gap: the server holds the key) | ✅ token only on the MCP host | ✅ |
| Environment | Files that run on your host | ❌ | ⚠️ (gap: you must review what you merge) | ❌ |
| Environment | Tampered images or scripts | ✅ | ✅ | ❌ |
| Model | Injected instructions | ❌ | ❌ | ⚠️ (gap: limits reach, doesn't detect) |
| External content | Over-powered tools (delete, merge, per-repo, per-user) | ❌ | ⚠️ (gap: MCP tools unrestricted, one shared token) | ✅ |
| External content | Poisoned tool results | ❌ | ❌ | ⚠️ (gap: redacts secrets, doesn't detect injection) |
| External content | Poisoned memory (`AGENTS.md`, session history) | ❌ | ⚠️ (gap: persists in the VM until it is removed) | ❌ |
| Monitoring | Record of what the agent did | ⚠️ (gap: hosts only) | ⚠️ (gap: hosts only) | ✅ |

Out of scope for every part: a VM or container escape, tool descriptions that lie, a compromised GitHub or model
provider.

Tested results and further detail: [notes](docs/research/readme-notes.md).

#### Notes

- **Clone mode:** `sbxenv.yaml` sets `clone: true`, so the host repo is mounted read-only and the agent works on a
  private clone. Tested: writes to `.git/hooks`, `.git/config`, `AGENTS.md` and `.github/` reached the clone, not the
  host. That also means the VM can no longer edit `.mcp.json`, the Taskfile or `sbxenv.yaml` on your
  host: a change reaches them only through a merge you review. Only committed files are in the clone, so commit before
  `sandbox:run`. Clone mode stops modification, not reading: untracked files such as `.env` stay readable.
- **The sandbox remote:** the agent's commits are served at `sandbox-<name>` on `127.0.0.1` at a random port. It is
  read-only (a push from the host was refused). Fetching from it is like fetching from any third-party remote, so
  review before you merge.
- **MCP guardrails need the gateway:** the `DELETE /repos/**` deny in `dev-tools.yaml` on `api.github.com` is now defense in depth,
  since `gh` has no token there. The token goes only to the MCP host, where GitHub's server does the work after a `POST`,
  so an MCP `delete_file` or `merge_pull_request` call is invisible to the proxy (tested). Network rules cannot see
  tool names, and the `X-MCP-*` headers in `.mcp.json` are only client-side guidance. Enforcement has to sit at the
  gateway (Part 3) or on GitHub (App permissions, branch rules).
- **The App's permissions are the real boundary:** this token has write access to `contents`, `issues` and
  `pull_requests` on one repository.

## What is left ahead

**Part 3, the gateway.** This setup cannot see tool calls: a network rule sees a request to the MCP host, not whether it is `delete_file` or
`merge_pull_request`. A gateway in front of the MCP server can limit each tool (delete, merge, per repo or per user) and log every call with its
tool name.
