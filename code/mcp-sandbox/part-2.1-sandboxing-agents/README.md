# Part 2.1: sandboxing the dev agent

## The problem

A coding agent that runs on your machine runs as you: it can read what you can read and use what you can use. Anyone who can put text in front
of it can try to steer it, through a GitHub issue, a web page or a tool result, and the agent cannot reliably tell their text from yours.

Earlier parts: [Part 1](../part-1-lethal-trifecta/README.md) shows the attack and [Part 2](../part-2-sandboxing-local-mcp/README.md) contains the MCP server. This part moves the agent itself into a sandbox.

## The solution

Claude Code runs inside an `sbx` microVM, on a private clone of the repo, and holds no real credential. The MCP servers (GitHub, draw.io, the Flux schema catalog) are registered on the host's sbx MCP gateway, so the agent
reaches them only through it. The gateway holds GitHub's OAuth token and sets the tool filter headers where the agent cannot change them.
Every other outbound request goes through an egress allow list, with a deny list on top (both in `.sbx/agent/dev-tools.yaml`).

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
│ │ 2. MCP gateway: GitHub, draw.io and Flux go through it. It holds   │ │
│ │    the OAuth token (never inside the VM), sets the tool filter     │ │
│ │    headers and logs each tool call in sandboxd/mcp/mcp.log         │ │
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

2. Set up the GitHub App (`mcp-gh-local`) as the OAuth client for the gateway. In its settings, add the callback URL `http://127.0.0.1:8765/callback`,
   turn on **Expire user authorization tokens**, and generate a client secret into `.env.secrets.json` as `GITHUB_APP_CLIENT_SECRET`
   (`sops .env.secrets.json`). Install the App on only the repository the agent needs, with only the permissions it needs.
   The App's private key is no longer used.

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

7. Start the daemon's egress proxy and register the MCP servers. `task sandbox:run` does both before it starts the sandbox, so this step is
   only needed to run them alone, or to do the one-time GitHub consent (it opens a browser):

```shell
task sandbox:egress-preflight    # squid up and proven, then sbx's proxy.daemon pointed at it (restarts the sbx daemon once)
task sandbox:mcp                 # draw.io, Flux and GitHub on the sbx MCP gateway; GitHub's browser consent the first time
```

8. Keep the proxy running across reboots. See [the daemon's egress proxy](#the-daemons-egress-proxy) for the two systemd units.

## Run it

```shell
task sandbox:run        # proxy up, MCP servers registered, sandbox created or started, servers attached, VS Code opened
```

The first time, sbx shows its plan and asks you to approve it. Run Claude Code in the VS Code terminal: it runs inside the sandbox. Run the task again
to reopen the window.

Other tasks: `task sandbox:build` (maintainer: rebuild and push the tools image) and `task sandbox:update-skills` (refresh the skills).

Egress rules live in the kit image: after changing them, run `task sandbox:build` and create a new sandbox. An existing sandbox keeps the rules it was made with.

## Reference

### Directory structure

```text
.sbx/                               everything that spawns the sandbox
├── Taskfile.yml                    orchestration: sandbox:login and sandbox:run (the ordered start); includes the two folders below
├── sbxenv.yaml                     the sandbox: kits, size, clone workspace
├── agent/                          AGENT POLICY: what runs inside the VM
│   ├── Taskfile.yml                sandbox:build, :install-skills, :update-skills, :setup-vscode
│   ├── dev-tools.yaml              the kit: tools, completions, shell, egress allow and deny lists (+ its .dockerignore)
│   └── tools.toml                  the sandbox's tools at exact versions, Terraform cache settings, the completions task
└── daemon/                         DAEMON POLICY: what the sbx daemon and its MCP gateway may reach
    ├── Taskfile.yml                sandbox:mcp, :mcp-load, :egress-up/-check/-apply/-preflight/-status/-open/-log/-off
    └── egress/
        ├── compose.yaml            squid for the daemon on 127.0.0.1:3128
        └── squid.conf              the allowlist: the one file to edit to change what the daemon may reach
```

This folder keeps the README, `docs/` and the handoffs.

Repo-root files (`Taskfile.yml`, `mise.toml`, `.env.secrets.json`, `.vscode/`, `AGENTS.md`) and the host paths are listed in the [notes](docs/research/readme-notes.md).

### How it works

```text
EVERY GITHUB MCP CALL

  Claude (in the VM)
    │ tool call to the one MCP endpoint, mcp-gateway.docker.internal
    ▼
  host MCP gateway (sbx): logs "invokeTool server=github target=<tool>"
    │ adds the OAuth token (refreshed by sbx) and the X-MCP-* headers
    ▼
  GitHub's MCP server: unknown or excluded tool ──▶ "unknown tool" error
    │ allowed tool
    ▼
  runs with the App's permissions on the repositories it is installed on

  Direct route: the VM's request to api.githubcopilot.com ──▶ 403 (kit deny rule, no credential either)
```

The kit, egress policy and gateway setup are explained in the [notes](docs/research/readme-notes.md).

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
| Environment | Credential used outside its purpose | ⚠️ (gap: the server holds the key) | ✅ token stays on the host gateway, direct route denied | ✅ |
| Environment | Files that run on your host | ❌ | ⚠️ (gap: you must review what you merge) | ❌ |
| Environment | Tampered images or scripts | ✅ | ✅ | ❌ |
| Model | Injected instructions | ❌ | ❌ | ⚠️ (gap: limits reach, doesn't detect) |
| External content | Over-powered tools (delete, merge, per-repo, per-user) | ❌ | ⚠️ (gap: filter is by tool name only, no per-argument rules; `create_or_update_file` and `push_files` can still overwrite files) | ✅ |
| External content | Poisoned tool results | ❌ | ❌ | ⚠️ (gap: redacts secrets, doesn't detect injection) |
| External content | Poisoned memory (`AGENTS.md`, session history) | ❌ | ⚠️ (gap: persists in the VM until it is removed) | ❌ |
| Monitoring | Record of what the agent did | ⚠️ (gap: hosts only) | ⚠️ (gap: `mcp.log` has server and tool name, no arguments, session or sandbox) | ✅ |

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
- **MCP goes through the host gateway:** GitHub, draw.io and Flux are registered with `sbx mcp`, so the agent has one endpoint and no direct route. Tested:
  the VM's request to `api.githubcopilot.com` returns 403 (a kit deny rule overrides the host baseline, which allows `*.githubcopilot.com`), and the
  gateway call works. The network proxy still cannot see tool names, but the gateway logs them.
- **Where tool calls are logged:** `~/.local/state/sandboxes/sandboxes/sandboxd/mcp/mcp.log` has one line per call, such as
  `mcp policy: allowed action=invokeTool server=github target=list_issues`. `sbx policy log` shows only the gateway alias with a count, never tool names.
  Without paid org governance the gateway allows every tool, so these lines record decisions, they do not enforce anything.
- **Tool filter:** GitHub's server reads the `X-MCP-Toolsets`, `X-MCP-Exclude-Tools`, `X-MCP-Tools` (allow list) and `X-MCP-Readonly` headers and rejects a
  filtered tool at call time (`unknown tool`), whatever the token type. The gateway sets them, so the agent cannot remove them. `task sandbox:mcp` sets
  the toolsets and excludes `delete_repository`, `delete_file`, `merge_pull_request`, `create_repository` and `fork_repository`. An allow list (`X-MCP-Tools`) is stricter than an exclude list: a tool GitHub adds later is allowed by the latter.
- **GitHub authenticates with the App's OAuth flow:** `sbx mcp auth` refreshes the user token itself. An installation token from the minter cannot be
  used, because the gateway accepts only fixed header secrets and keeps the old value until a restart. The token is limited to the App's permissions on the
  repositories it is installed on, not to everything the user can do. `sbx` can narrow nothing else per request.
- **The daemon's egress proxy:** the sbx egress policy covers only the VM. The gateway's calls to the MCP servers, kit pulls and Docker sign-in leave from the
  sbx daemon on your host, so they go through a squid allowlist set with `sbx settings set proxy.daemon http://127.0.0.1:3128` (`proxy` and `proxy.sandbox` stay empty:
  `proxy` alone would send the VM's traffic through squid too). Edit `.sbx/daemon/egress/squid.conf` to change what the daemon may reach. Tested: with a host
  removed from the allowlist, squid denied it (403) and the gateway's call failed; the VM's own traffic never appears in squid's log. Squid sees the host and
  port of a tunnel, not paths or tool names, and logs a tunnel only when it closes: `task sandbox:egress-open` lists the ones open now, which is where the
  gateway's long-lived connections show up. `proxy.daemon` is an experimental sbx setting.
- **Fail closed, with a way out:** if the proxy is down while `proxy.daemon` is set, the daemon cannot pull kits, sign in or reach the MCP servers (tested: a gateway
  call failed while the proxy was stopped). `sandbox:run` starts and proves the proxy first, in order: up and healthy, allowed host tunnels and a denied host gets 403,
  then `proxy.daemon` is set and the daemon restarted, then the sandbox starts. `task sandbox:egress-off` unsets the setting without needing the proxy. Docker restarts
  squid after a crash (tested, about 7 s) but not after a manual `docker stop` or `docker kill`.
- **Dynamic MCP mode:** `sbx env run` has no `--static-mcp`, so the agent can attach any server registered on your host with the gateway's `mcp-add`. Registrations
  are host-global, so register only what any sandbox may use.
- **The App's permissions are the real boundary:** the App has write access to `contents`, `issues` and `pull_requests`, and no administration. The
  installation covers one repository.

### The daemon's egress proxy

Squid has to be running before the sbx daemon starts. Two systemd user units make that true at every boot and keep the daemon from starting without it.
They live outside the repo, in `~/.config/systemd/user/`. Change the paths to match your clone.

```ini
# ~/.config/systemd/user/sbx-daemon-egress.service
[Unit]
Description=Egress proxy (squid) for the sbx daemon
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
Environment=DOCKER_HOST=unix://%t/docker.sock
ExecStart=/usr/bin/docker compose -f %h/Projects/engineersdaybook/.sbx/daemon/egress/compose.yaml up -d --wait
ExecStop=/usr/bin/docker compose -f %h/Projects/engineersdaybook/.sbx/daemon/egress/compose.yaml down

[Install]
WantedBy=default.target
```

```ini
# ~/.config/systemd/user/sbx-daemon.service.d/egress.conf   (a drop-in for the existing sbx-daemon.service)
[Unit]
Requires=sbx-daemon-egress.service
After=sbx-daemon-egress.service
```

```shell
systemctl --user daemon-reload
systemctl --user enable --now sbx-daemon-egress.service
```

`Requires` means stopping or restarting the proxy unit also stops the daemon and ends running sandboxes; that is the fail-closed choice.

## What is left ahead

**Part 3, a gateway with rules.** The host gateway now routes the calls and logs each tool name, but it enforces nothing by itself: sbx's own per-tool
rules (Cedar policies) need a paid Docker org subscription, and the log has no arguments. A gateway of your own can limit each tool (delete, merge, per repo
or per user), look at the arguments and log every call in full.
