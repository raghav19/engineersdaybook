# Part 2.1: sandboxing the dev agent

## The problem

A coding agent that runs on your machine runs as you: it can read what you can read and use what you can use. Anyone who can put text in front
of it can try to steer it, through a GitHub issue, a web page or a tool result, and the agent cannot reliably tell their text from yours.

Earlier parts: [Part 1](../part-1-lethal-trifecta/README.md) shows the attack and [Part 2](../part-2-sandboxing-local-mcp/README.md) contains the MCP server. This part moves the agent itself into a sandbox.

## The solution

Claude Code runs inside an `sbx` microVM, on a private clone of the repo, and holds no real credential. The MCP servers (GitHub, draw.io, the Flux schema catalog) are registered on the host's sbx MCP gateway, so the agent
reaches them only through it. The gateway holds GitHub's OAuth token and sets the tool filter headers where the agent cannot change them.
Every other outbound request goes through an egress allow list, with a deny list on top (both in `.sbx/agent/dev-tools.yaml`).
The sbx daemon runs on the host, outside the VM, and makes the MCP calls and kit pulls itself, so its own outbound calls go through a squid allowlist
that systemd keeps running (`.sbx/daemon/`).

This follows Anthropic's [How we contain Claude across products](https://www.anthropic.com/engineering/how-we-contain-claude) (May 25, 2026): enforce hard limits in the environment (sandbox, egress controls, credentials kept out) instead of relying on the model. The quotes and the layer-by-layer mapping are in the [notes](docs/research/readme-notes.md).

### How it is laid out

```text
HOST (your machine)
┌────────────────────────────────────────────────────────────────────────────────────────────┐
│ ┌─ microVM: one per sandbox, own kernel ─────────────────────────────────────────────────┐ │
│ │ agent: Claude Code. No real credential. Works on a private clone of the repo.          │ │
│ │ The host repo is read-only. Nothing else of yours: no ~/.ssh, ~/.aws or host secrets.  │ │
│ └────────────────────┬───────────────────────────────────────────────┬───────────────────┘ │
│                      │ VM network calls                              │ MCP tool calls      │
│                      │ (everything the VM does)                      │ (only MCP endpoint) │
│                      ▼                                               ▼                     │
│ ┌─ sbx egress proxy ─────────────────────┐      ┌─ sbx MCP gateway ──────────────────────┐ │
│ │ AGENT POLICY                           │      │ holds GitHub's OAuth token             │ │
│ │ kit allow and deny lists               │      │ sets the X-MCP-* tool filter           │ │
│ │ .sbx/agent/dev-tools.yaml              │      │ logs each tool call (mcp.log)          │ │
│ │ applies to the VM only                 │      │ runs inside the sbx daemon             │ │
│ └────────────────────┬───────────────────┘      └────────────────────┬───────────────────┘ │
│                      │                           daemon's own calls: │                     │
│                      │                           MCP, kit pulls,     │                     │
│                      │                           Docker sign-in      ▼                     │
│                      │                          ┌─ squid proxy 127.0.0.1:3128 ───────────┐ │
│                      │                          │ DAEMON POLICY                          │ │
│                      │                          │ allowlist: egress/squid.conf           │ │
│                      │                          │ systemd keeps it running; the          │ │
│                      │                          │ sbx daemon starts only after it        │ │
│                      │                          └────────────────────┬───────────────────┘ │
└──────────────────────┬───────────────────────────────────────────────┬─────────────────────┘
                       ▼                                               ▼
        internet: hosts on the kit                      draw.io, Flux, GitHub MCP, registries
        allow list only                                 (hosts on the squid allowlist only)
```

| Who controls what | Applies to | Where to change it |
|---|---|---|
| Agent policy: the kit's egress allow and deny lists | what the VM itself connects to | `.sbx/agent/dev-tools.yaml` |
| MCP gateway: OAuth token, tool filter, tool-call log | every MCP call from the agent | `.sbx/daemon/Taskfile.yml` (vars), `task sandbox:install-mcp` |
| Daemon policy: squid allowlist | what the sbx daemon itself connects to (MCP servers, kit pulls, Docker sign-in) | `.sbx/daemon/egress/squid.conf` |

## Prerequisites

Have these in place before the first command in [Getting started](#getting-started).

1. **Host tools.** [mise](https://mise.jdx.dev) (installs `task`, `yq`, `jq` and `sops` from the root `mise.toml`), VS Code, and Docker (to build the kit).
2. **sbx.** Follow Docker's [install guide](https://docs.docker.com/ai/sandboxes/install/) for the requirements (virtualization, `/dev/kvm`, sign-in, disk) and run `sbx diagnose`.
   On Ubuntu 24.04 or later:

   ```shell
   curl -fsSL https://get.docker.com | sudo REPO_ONLY=1 sh
   sudo apt install docker-sbx
   ```

   On other distributions, use the tarball from [github.com/docker/sbx-releases](https://github.com/docker/sbx-releases). That is not a Docker-supported setup; this repo was built that way on Omarchy (Arch-based). When sbx asks for a default network policy, choose **Balanced**: the kit's allow and deny lists are applied on top.
3. **Rootless Docker as a user service, and linger.** The daemon's proxy runs in it and user services must start at boot.
   See [`code/rootless-docker`](../../rootless-docker). Check:

   ```shell
   systemctl --user is-enabled docker.service     # enabled
   loginctl show-user "$USER" -p Linger           # Linger=yes
   ```

4. **A GitHub App** (`mcp-gh-local`), set up once in GitHub. The agent's GitHub access is this App's OAuth token, held by the gateway, never in the VM.
   - Install it on only the repository the agent needs, with only the permissions it needs (today: contents, issues, pull requests: write; no administration).
   - Add the callback URL `http://127.0.0.1:8765/callback`, turn on **Expire user authorization tokens**, and generate a client secret.
   - Its client id is in `.sbx/daemon/Taskfile.yml` (not a secret). The App's private key is not used.
5. **Secrets.** Two live in the sops-encrypted `.env.secrets.json` at the repo root; edit it with `sops .env.secrets.json`.

   | Secret | Stored in | Used by |
   |---|---|---|
   | `GITHUB_TOKEN`, a token for the ghcr.io kit image | `.env.secrets.json` | `task sandbox:login`, once |
   | `GITHUB_APP_CLIENT_SECRET`, the App's client secret | `.env.secrets.json` | `task sandbox:install-mcp`, piped into sbx's secret store, never printed |
   | GitHub's OAuth token | sbx's host credential store, created by the browser consent | the gateway; never inside the VM |
   | your age key (decrypts the file) | `~/.config/sops/age/keys.txt` | `sops` |

## Getting started

Run these in order, from the repo root.

1. Install the host tools, and activate mise in your shell so `task` is on the PATH (add the `eval` line to your shell rc to keep it; a new shell needs it too):

   ```shell
   mise trust && mise install
   eval "$(mise activate bash)"      # zsh: eval "$(mise activate zsh)"
   task --list                       # the sandbox:* tasks appear when you are in the repo root
   ```

2. Set sbx once:

   ```shell
   sbx settings set kit.allowedSources '["docker.io/","ghcr.io/raghav19/dev-agent-sandbox"]'
   sbx settings set ssh.agentForwardingEnabled false    # do not forward your SSH agent into the sandbox
   ```

3. Log in to the registry (reads `GITHUB_TOKEN`, needs your age key):

   ```shell
   task sandbox:login
   ```

4. Set up the daemon's proxy and units on the host. This restarts the sbx daemon, so do it before you start a sandbox. How the parts fit:
   [`.sbx/daemon/README.md`](../../../.sbx/daemon/README.md). The steps, checks, logs and undo are the comments above `sandbox:install-daemon` in `.sbx/daemon/Taskfile.yml`.
   The daemon unit runs `~/.docker/sbx/bin/sbx`: if `command -v sbx` prints another path, change `ExecStart` in `.sbx/daemon/systemd/sbx-daemon.service` to it first.

   ```shell
   task sandbox:install-daemon
   ```

5. Install the agent skills:

   ```shell
   task sandbox:install-skills
   ```

6. Connect VS Code:

   ```shell
   sbx setup ssh
   code --install-extension ms-vscode-remote.remote-ssh
   ```

7. Start the sandbox. Commit first: only committed files are in the clone.

   ```shell
   task sandbox:run
   ```

   The first time, sbx shows its plan and asks you to approve it. Run Claude Code in the VS Code terminal: it runs inside the sandbox. Run the task again
to reopen the window. The first run also opens a browser once for GitHub's consent. Run Claude Code in the VS Code terminal: it runs inside the sandbox.

Day to day: run `task sandbox:run` again to reopen the window. `task sandbox:build` (maintainer) rebuilds and pushes the tools image, `task sandbox:update-skills`
refreshes the skills. Egress rules for the VM live in the kit image, so after changing them run `task sandbox:build` and create a new sandbox.

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
    ├── README.md                   what is set up on the host and how (read first: it is a prerequisite for the tasks)
    ├── Taskfile.yml                sandbox:install-daemon (once per machine), sandbox:install-mcp
    ├── systemd/                    the two user units: the proxy and the sbx daemon (installed by sandbox:install-daemon)
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
content, plus monitoring. Part 2.1 describes this directory once the kit is rebuilt and the sandbox recreated, and its column was
checked against a running sandbox on 2026-10-08 ([evidence](docs/research/threat-table-verification.md)). The Part 2 column was audited on 2026-10-06. Part 3 is
planned, so its column is the design, not tested.

| Layer | Threat | Part 2: container + proxy | Part 2.1: microVM | Part 3: gateway |
|---|---|---|---|---|
| Environment | Compromised MCP server code | ✅ | ⚠️ (gap: no MCP code runs locally, but the hosted servers are trusted) | ✅ |
| Environment | Data leaving the sandbox | ✅ explicit allow-list | ⚠️ (gap: 194 baseline allow rules; `registry.terraform.io` and an S3 wildcard accepted a body in testing; the daemon's own calls are on a squid allowlist) | ⚠️ (gap: gateway covers MCP only) |
| Environment | Credentials stolen | ⚠️ (gap: key inside the container) | ✅ only placeholders in the VM (`GH_TOKEN` returns 401) | ✅ |
| Environment | Credential used outside its purpose | ⚠️ (gap: the server holds the key) | ⚠️ (cannot be used outside the gateway, but through it the token writes: see exfiltration below) | ✅ |
| Environment | Files that run on your host | ❌ | ⚠️ (gap: you must review what you merge, including `.sbx/`: the unit files, `squid.conf`, `compose.yaml` and the Taskfiles run on the host) | ❌ |
| Environment | Tampered images or scripts | ✅ | ⚠️ (kit and squid image pinned by digest, not signed: `kit.requireSignature` is off) | ❌ |
| Model | Injected instructions | ❌ | ❌ (Part 1's two refusals were the model, not a control) | ⚠️ (gap: limits reach, doesn't detect) |
| External content | Over-powered tools (delete, merge, per-repo, per-user) | ❌ | ⚠️ (gap: filter is by tool name only, no per-argument rules; `issue_write`, `push_files`, `create_or_update_file`, `create_pull_request`, `add_issue_comment` and `update_pull_request` stay open) | ✅ |
| External content | Poisoned tool results | ❌ | ❌ | ⚠️ (gap: redacts secrets, doesn't detect injection) |
| External content | Poisoned memory (`AGENTS.md`, session history) | ❌ | ⚠️ (gap: persists across stop and start, until `sbx rm`) | ❌ |
| Environment | Host files the agent can read | ❌ | ⚠️ (gap: untracked and git-ignored files in the repo directory are readable through a read-only mount; nothing outside it) | ❌ |
| Environment | Sending data out through MCP write tools | ❌ | ❌ (a host-only file was published to a public issue in testing) | ✅ |
| Monitoring | Record of what the agent did | ⚠️ (gap: hosts only) | ⚠️ (gap: allowed tool calls are in `mcp.log` by name; rejected calls leave no line; no arguments, session or sandbox; squid logs the daemon's hosts) | ✅ |

Out of scope for every part: a VM or container escape, tool descriptions that lie, a compromised GitHub or model
provider.

#### The lethal trifecta: what the sandbox contains

The trifecta is private data, untrusted content and a way to send data out, all in one agent. Tested on 2026-10-08 with canary strings and a canary GitHub issue
([details](docs/research/threat-table-verification.md)). The sandbox shrinks it; it does not break it.

| Leg | What the sandbox does | Still open |
|---|---|---|
| Private data | Your home, `~/.ssh`, `~/.aws` and every real credential are out of reach. | The repo directory: untracked and git-ignored files are readable. |
| Untrusted content | Nothing. | Issues, tool results and pages reach the agent as before. |
| A way out | Direct routes to the MCP servers and the GitHub API are blocked (403/401). | MCP write tools: the agent read a host-only file and published it in a public issue. Two policy-allowed hosts accepted a body. |

So the sandbox limits the **blast radius**, and the open channel is the GitHub write tools. To close more of it: allow-list the tools (`X-MCP-Tools`) or run read-only
(`X-MCP-Readonly`), keep secrets out of the repo directory, and log rejected calls (Part 3).

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
  filtered tool at call time (`unknown tool`), whatever the token type. The gateway sets them, so the agent cannot remove them. `task sandbox:install-mcp` sets
  the toolsets and excludes `delete_repository`, `delete_file`, `merge_pull_request`, `create_repository` and `fork_repository`. An allow list (`X-MCP-Tools`) is stricter than an exclude list: a tool GitHub adds later is allowed by the latter.
- **GitHub authenticates with the App's OAuth flow:** `sbx mcp auth` refreshes the user token itself. An installation token from the minter cannot be
  used, because the gateway accepts only fixed header secrets and keeps the old value until a restart. The token is limited to the App's permissions on the
  repositories it is installed on, not to everything the user can do. `sbx` can narrow nothing else per request.
- **The daemon's egress proxy:** the sbx egress policy covers only the VM. The daemon's own calls (MCP servers, kit pulls, Docker sign-in) go through a squid allowlist
  set with the experimental sbx setting `proxy.daemon`; `proxy` and `proxy.sandbox` stay empty, or the VM's traffic would go through squid too. Tested: a host removed from the
  allowlist is denied (403) and the gateway's call fails, and the VM's traffic never appears in squid's log. Squid sees the host and port of a tunnel, not paths or tool names.
  How it fits together: [`.sbx/daemon/README.md`](../../../.sbx/daemon/README.md). Logs, adding a host and undo: comments in `.sbx/daemon/Taskfile.yml` and `egress/squid.conf`.
- **Fail closed:** systemd starts the proxy at login and orders the daemon after it, and the daemon stops with it. If squid is down while `proxy.daemon` is set, the daemon cannot
  pull kits, sign in or reach the MCP servers until it is back; Docker restarts it after a crash but not after a manual stop.
- **Dynamic MCP mode:** `sbx env run` has no `--static-mcp`, so the agent can attach any server registered on your host with the gateway's `mcp-add`. Registrations
  are host-global, so register only what any sandbox may use.
- **The App's permissions are the real boundary:** the App has write access to `contents`, `issues` and `pull_requests`, and no administration. The
  installation covers one repository.

## What is left ahead

**Part 3, a gateway with rules.** The host gateway now routes the calls and logs each tool name, but it enforces nothing by itself: sbx's own per-tool
rules (Cedar policies) need a paid Docker org subscription, and the log has no arguments. A gateway of your own can limit each tool (delete, merge, per repo
or per user), look at the arguments and log every call in full.
