# Part 2.1: sandboxing the dev agent

Runs Claude Code inside an `sbx` microVM. The agent reaches GitHub through the hosted GitHub MCP server, with a
short-lived GitHub App token that the host mints and the sbx proxy injects.

## The Docker sandbox model

```text
HOST (your machine)
┌────────────────────────────────────────────────────────────────────────┐
│ sbx daemon: creates and manages the sandboxes                          │
│                                                                        │
│ ┌─ microVM: one per sandbox, own kernel, Docker daemon, packages ────┐ │
│ │ agent: Claude Code. Holds sentinel values, no real credential.     │ │
│ │ repo: a private clone; the host repo is read-only (virtiofs).      │ │
│ │ Nothing else of yours: no ~/.ssh, ~/.aws or host secrets.          │ │
│ └─────────────────────────────┬──────────────────────────────────────┘ │
│                               │  every outbound request                │
│                               ▼                                        │
│ ┌─ host proxy ───────────────────────────────────────────────────────┐ │
│ │ 1. egress policy: the kit's allow list + your sbx policy           │ │
│ │ 2. credential injection: only on the domains you approved in       │ │
│ │    credentials.yaml, swapping the sentinel for the real value      │ │
│ │    from the host secret store (never inside the VM)                │ │
│ └─────────────────────────────┬──────────────────────────────────────┘ │
│                               │                                        │
└────────────────────────────────────────────────────────────────────────┘
                                ▼
                        internet: allow-listed domains only
```

Only two things cross the boundary: the repo (mounted read-only, with the agent working on a private clone) and outbound requests, which go through the proxy.

## Directory structure

```text
code/mcp-sandbox/part-2.1-sandboxing-agents/
├── sbxenv.yaml           the sandbox: kit digest, secret, binding
├── agent-sandbox.yaml    the kit: Claude, egress rules, credential
├── mint-gh-app-token.sh  host minter: App key -> installation token
├── Taskfile.yml          sandbox:run, :build, :pin, :ide
├── mise.toml             tool versions: task, yq
└── README.md

Outside this directory
├── .mcp.json                       (repo root) GitHub MCP entry, no token
├── mise.toml                       (repo root) tools and sandbox:* tasks
├── .vscode/                        (repo root) extensions, settings
├── .sbx/                           (repo root) shell and extension setup
├── AGENTS.md                       (repo root) tells Claude to use MCP tools
├── ~/.config/mcp-gh/               (host) App private key
└── ~/.config/sbx/credentials.yaml  (host) approved bindings, no secrets
```

## How it works

```text
PUBLISH (maintainer, when the kit changes)

  task sandbox:build    kit image ──push──▶ ghcr.io ──digest──▶ sbxenv.yaml

RUN (developer)

  task sandbox:run      (sbx env run .)
    │
    ├─ 1. sbx reads sbxenv.yaml and prints the plan (kit digest, secret
    │     command) ──▶ you approve
    ├─ 2. sbx creates the microVM from kit@digest and clones the repo into it
    ├─ 3. sbx stores the `github-mcp` secret: command = mint-gh-app-token.sh
    │     (run on the host, from this directory), refresh 55m
    ├─ 4. sbx env run returns; task sandbox:ide opens VS Code on the sandbox
    ▼
  Claude starts inside the VM

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

- `sbxenv.yaml` declares the sandbox, including the kit digest that `task sandbox:pin` writes. The registry is fixed
  in the file, so a digest can only name an image from your repository.
- The minter, `mint-gh-app-token.sh`, runs on your host from the repo. The dev sandbox cannot change it: its repo
  is a read-only clone.
- `.mcp.json` only narrows the tool list. The proxy adds the `Authorization` header.
- Claude signs in through sbx's global OAuth login, so a new sandbox needs no login.

## Setup (once per machine)

1. Install the tools (`task`, `yq`):

```shell
mise install
```

2. Put the GitHub App private key at `~/.config/mcp-gh/<gh-private-key>` (or change `keyPath` in `sbxenv.yaml`).

3. Log in to ghcr.io once, with a personal access token that has `read:packages` and `write:packages`. The kit is a
   private package, so two tools need the login: docker pushes it (`task sandbox:build`) and sbx pulls it (`sbx env run`).
   Nothing logs in again after this.

```shell
read -rs -p "ghcr.io token: " PAT && echo
printf %s "$PAT" | docker login ghcr.io -u <github-user> --password-stdin                   # for the build: ~/.docker/config.json
printf %s "$PAT" | sbx secret set -f --registry ghcr.io --username <github-user> --password-stdin   # for sbx: host-only
unset PAT
```

4. Allow the kit's registry in sbx:

```shell
sbx settings set kit.allowedSources '["docker.io/","ghcr.io/raghav19/dev-agent-sandbox"]'
```

5. Turn off SSH agent forwarding (sbx forwards your agent into sandboxes by default):

```shell
sbx settings set ssh.agentForwardingEnabled false
sbx daemon restart    # needed to take effect; ends running sandbox sessions
```

6. For the IDE: set up SSH to sandboxes and add the VS Code extension:

```shell
sbx setup ssh                                          # adds an Include block to ~/.ssh/config; undo with `sbx setup ssh remove`
code --install-extension ms-vscode-remote.remote-ssh
```

## Run it and open VS Code

```shell
task sandbox:build   # maintainer, when the kit changes: build, push, then pin the digest in sbxenv.yaml
task sandbox:run     # developer: create or start the sandbox and open VS Code on it, then return
task sandbox:claude  # optional: attach Claude Code to the running sandbox in this terminal
```

`task sandbox:run` runs `sbx env run . --detached`, then `task sandbox:ide`. `sbx env run` reads `sbxenv.yaml`, prints a plan
and asks you to approve it, then creates the sandbox `dev-agent-sbx` from the pinned kit, clones the repo into it, stores
the GitHub secret and returns. The task then opens VS Code on the sandbox over Remote-SSH. The plan's one host command
is the GitHub token minter. Run Claude Code in the VS Code terminal, or attach it here with `task sandbox:claude`.
`task sandbox:ide` reopens the window.
`task sandbox:pin` is only the pin step of the build: it writes the registry's current digest for the kit tag into
`sbxenv.yaml`.

The window shows the **VM's clone**, the same folder the agent edits, so you see its changes live and it sees yours. Your
host working tree is not touched, and a VS Code window on the host shows only host files until you fetch. Terminals,
extensions and `.vscode/tasks.json` run inside the VM. Commit on a branch there and use the next section to bring the work
to your host.

If `code` is not on your PATH, `task sandbox:ide` fails after the sandbox is up: in VS Code run **Remote-SSH: Connect to Host...**, type
`dev-agent-sbx.sbx`, and open the repo folder (same path as on your host). SSH ends at the sbx daemon, there is no SSH
server in the VM, and a stopped sandbox starts when you connect. The generated SSH config forwards no agent and uses
your Docker login, not a key.

If VS Code reports "the remote host may not meet VS Code Server's prerequisites for glibc and libstdc++", the image has no
`/etc/ld.so.cache`, so `ldconfig` finds nothing. The `sandbox:system` task builds it at every boot (with `sudo`). A sandbox
created from an older kit gets it from its own hook, or once by hand: `ssh dev-agent-sbx.sbx -- sudo ldconfig`.

### Tools, shell and extensions in the sandbox

The sandbox is set up from files in the repo, so the kit stays small. At every boot its startup hook installs
[mise](https://mise.jdx.dev) if it is missing and runs `mise run sandbox:setup`:

| File | What it does |
|---|---|
| `mise.toml` `[tools]` | the tools (fzf, starship, fd, kubectl, helm, kustomize), installed by mise in parallel |
| `mise.toml` `sandbox:*` tasks | `sandbox:setup` runs `sandbox:system`, `sandbox:shell`, `sandbox:completions` and `sandbox:extensions` in parallel |
| `.sbx/shellrc` | sourced from `~/.bashrc`: tools on PATH, completions, fzf key bindings, the starship prompt |
| `.vscode/extensions.json` | the extensions, also recommended by your host VS Code |
| `.vscode/settings.json` | workspace settings: the terminal uses bash |

To change any of them: edit the file, **commit it** (the clone only has committed files), then `sbx stop` and
`task sandbox:run`. The kit does not need a rebuild. `.vscode/extensions.json` must be plain JSON (no comments), because the task reads it with `jq`. The first boot took about two minutes in my test, the six tools
take about 20 seconds of that, and the two extensions use about 300 MB.

**VS Code Server:** your first connect downloads the VS Code server (about 200 MB, 640 MB unpacked) into the VM's
`~/.vscode-server`. It stays on the VM's disk, so `sbx stop` and `task sandbox:run` reuse it and nothing is downloaded
again. `sbx rm` deletes it, so the next connect downloads a server again, and a VS Code update needs a new one for its
commit. `sandbox:extensions` keeps a server of its own in `~/.cache/vscode-server` (downloaded once, so a second
640 MB on disk) and runs its `--install-extension` for the ids in `.vscode/extensions.json`. The extensions are there before
you connect, and a later boot takes about 4 seconds.

**Memory:** `sbxenv.yaml` gives the sandbox 2 GiB. With 512 MiB the VM ran out of memory under VS Code, and SSH timed out.

Notes:
- **Not `mise activate`:** `.sbx/shellrc` puts the tools on PATH with `mise bin-paths`. Activating mise would also
  apply the `[env]` of `mise.toml` (`ANTHROPIC_BASE_URL`, a host-only proxy), which would break Claude in the VM.
- **bash:** the image's login shell is `/bin/sh`, so `sandbox:system` sets bash, and `.vscode/settings.json` selects it in the
  VS Code terminal. VS Code treats that setting as restricted, so it applies after you trust the folder. It also
  applies to terminals on your host in this repo.
- **Network:** the kit allows the hosts these steps use: `mise.run`, `mise.jdx.dev`, `github.com` (tool releases),
  `dl.k8s.io` (kubectl), `get.helm.sh` (helm), `update.code.visualstudio.com` and the marketplace
  (`**.vsassets.io`). A failed step only prints a warning in `/var/log/sbx-kit-startup.log`.
- **On the host:** `mise install` in the repo installs the same tools. The `sandbox:*` tasks refuse to run outside
  the sandbox.

## Getting the agent's work

The agent works on a private clone inside the VM, so nothing it does changes your working tree until you bring it over.
Your IDE sees changes only after you fetch and merge or check out. Only committed work comes over, so ask the agent to
commit on a branch.

```shell
git fetch sandbox-dev-agent-sbx                               # its branches show up as remote branches in your IDE's Git view
git worktree add ../review sandbox-dev-agent-sbx/<branch>     # review in a separate folder; your working tree is untouched
git merge --ff-only sandbox-dev-agent-sbx/<branch>            # or bring it into your working tree
```

Fetch again after the agent commits more. Before `sbx rm`, keep what you want with
`git branch review sandbox-dev-agent-sbx/<branch>`: removing the sandbox also removes the remote and its fetched branches.

## Threats and what stops them

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

### Notes

- **Data leaving:** the egress baseline is Docker's Balanced preset (194 allow rules in six `default-*` groups, applied
  by the sbx daemon, global to every sandbox). It is kept on purpose, because the agent needs those domains for
  research. Its wildcards let an unapproved S3 bucket through (`GET` and `PUT` tested), so the credential limits matter
  more than the domain list. Anthropic's advice is the same: treat an allow-list as a capability grant.
- **Credential:** the kit names the service `github-mcp`, not `github`. `github` is an sbx built-in whose default
  domains include `api.github.com`, so `gh` and `git` over https also got the token. With the custom name the token is
  injected only on `api.githubcopilot.com` (tested: `api.github.com` gets none, the MCP host does). A placeholder
  `GH_TOKEN` is still set in the VM but is useless. The binding in `~/.config/sbx/credentials.yaml` lists only that domain.
- **Clone mode:** `sbxenv.yaml` sets `clone: true`, so the host repo is mounted read-only and the agent works on a
  private clone. Tested: writes to `.git/hooks`, `.git/config`, `AGENTS.md` and `.github/` reached the clone, not the
  host. That also means the VM can no longer edit `.mcp.json`, the Taskfile or `sbxenv.yaml` on your
  host: a change reaches them only through a merge you review. Only committed files are in the clone, so commit before
  `sandbox:run`. Clone mode stops modification, not reading: untracked files such as `.env` stay readable.
- **The sandbox remote:** the agent's commits are served at `sandbox-<name>` on `127.0.0.1` at a random port. It is
  read-only (a push from the host was refused). Fetching from it is like fetching from any third-party remote, so
  review before you merge.
- **MCP guardrails need the gateway:** the kit's `DELETE /repos/**` deny on `api.github.com` is now defense in depth,
  since `gh` has no token there. The token goes only to the MCP host, where GitHub's server does the work after a `POST`,
  so an MCP `delete_file` or `merge_pull_request` call is invisible to the proxy (tested). Network rules cannot see
  tool names, and the `X-MCP-*` headers in `.mcp.json` are only client-side guidance. Enforcement has to sit at the
  gateway (Part 3) or on GitHub (App permissions, branch rules).
- **The App's permissions are the real boundary:** this token has write access to `contents`, `issues` and
  `pull_requests` on one repository.
- **Boot hooks trust the clone:** `mise.toml`, `.sbx/` and `.vscode/extensions.json` are read from the VM's clone,
  which the agent can edit, and `mise run sandbox:setup` runs them as the agent user at every boot (inside the
  VM, with its network access). They are no longer pinned by the kit digest. Nothing reaches your host until you
  merge, so read changes to those files in the diff.
- **The minter runs from the repo:** `mint-gh-app-token.sh` is run by sbx on your host every 55 minutes. The dev
  sandbox cannot edit it, because its repo is a read-only clone. Any other sandbox that mounts this repo read-write
  (the `ai-ops-*` ones do) could, so keep those on `--clone` as well.
- **SSH agent:** `ssh.agentForwardingEnabled` is turned off in Setup, so a client cannot forward your agent into the
  sandbox. It is separate from the IDE connection, which uses no agent (tested with it off). A `/run/ssh-agent.sock`
  socket still exists in the VM; your host agent has no keys loaded, so it offers nothing today.
- **Not done yet:** signed kits (`kit.requireSignature` is off, so a tampered pin is only caught by review), and live
  inspection of tool results, which needs a gateway.
- **Logs:** `sbx policy log` keeps per-host counts and the matching rule, with no method, path or tool name.
  agentgateway logs every MCP call with its tool name and session by default.
