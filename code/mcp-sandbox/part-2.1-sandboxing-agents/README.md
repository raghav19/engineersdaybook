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
├── sbxenv.yaml           the sandbox: kit, secret, host step, binding
├── digests.json          kit and minter digests, written by build tasks
├── agent-sandbox.yaml    the kit: Claude, egress rules, credential
├── mint-gh-app-token.sh  host minter: App key -> installation token
├── Taskfile.yml          sandbox:run, sandbox:build, sandbox:build-minter
├── mise.toml             tool versions: task, sops, age, oras
├── .secrets.env          ghcr.io token, sops-encrypted, safe to commit
├── .sops.yaml            age public key for .secrets.env
└── README.md

Outside this directory
├── .mcp.json                       (repo root) GitHub MCP entry, no token
├── AGENTS.md                       (repo root) tells Claude to use MCP tools
├── ~/.config/mcp-gh/               (host) App private key, pulled minter
└── ~/.config/sbx/credentials.yaml  (host) approved bindings, no secrets
```

## How it works

```text
PUBLISH (maintainer, rarely)

  task sandbox:build          kit image ──push──▶ ghcr.io ──digest──┐
  task sandbox:build-minter   minter    ──push──▶ ghcr.io ──digest──┤
                                                                    ▼
                                             digests.json (review, commit)

RUN (developer)

  task sandbox:run
    │
    ├─ 1. store the ghcr pull credential in sbx's host secret store
    ├─ 2. sbx env run . reads sbxenv.yaml and digests.json
    ├─ 3. sbx prints the plan (kit digest, host step, secret) ──▶ you approve
    ├─ 4. host step: oras pull minter@digest into ~/.config/mcp-gh/
    ├─ 5. sbx creates the microVM from kit@digest and clones the repo into it
    ├─ 6. sbx stores the `github-mcp` secret: command = minter, refresh 55m
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

- `sbxenv.yaml` declares the sandbox. `digests.json` pins the kit and the minter, and each must match
  `sha256:<64 hex>`. The registries are fixed in `sbxenv.yaml`.
- The minter that runs on the host is the pinned copy pulled in step 4, not the file in the repo.
- `.mcp.json` only narrows the tool list. The proxy adds the `Authorization` header.
- Claude signs in through sbx's global OAuth login, so a new sandbox needs no login.

## Setup (once per machine)

1. Install the tools: 
```shell
mise install
```

2. Put the GitHub App private key at `~/.config/mcp-gh/<gh-private-key>` (or change `keyPath` in `sbxenv.yaml`).

3. Create an age key, add its public key to `.sops.yaml`, and re-encrypt the ghcr.io token:
```shell
mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt   # back this key up
printf 'GITHUB_TOKEN=%s\n' "$TOKEN" | sops --encrypt --filename-override .secrets.env \
                                           --input-type dotenv \
                                           --output-type dotenv /dev/stdin > .secrets.env
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

## Open the sandbox in VS Code

```shell
task sandbox:run     # create the sandbox if it does not exist (in a second terminal, or with -- --detached)
task sandbox:ide     # opens VS Code on the sandbox's clone over Remote-SSH
```

By hand: in VS Code run **Remote-SSH: Connect to Host...**, type `dev-agent-<user>.sbx`, then open the repo folder (same
path as on your host). SSH ends at the sbx daemon, there is no SSH server in the VM, and a stopped sandbox starts when
you connect. No key or agent is involved: the generated SSH config forwards no agent and uses your Docker login.

What the IDE shows is the **VM's clone**, the same folder the agent edits, so you see its changes live and your edits
are visible to the agent. Your **host** working tree is not touched. A host window on the repo shows the host files and
tracks nothing from the VM until you fetch. Terminals, extensions and `.vscode/tasks.json` run inside the VM. Commit on
a branch in the VM and use the next section to bring the work to your host.

## Getting the agent's work

The agent works on a private clone inside the VM, so nothing it does changes your working tree until you bring it over.
Your IDE sees changes only after you fetch and merge or check out. Only committed work comes over, so ask the agent to
commit on a branch.

```shell
git fetch sandbox-dev-agent-$USER                               # its branches show up as remote branches in your IDE's Git view
git worktree add ../review sandbox-dev-agent-$USER/<branch>     # review in a separate folder; your working tree is untouched
git merge --ff-only sandbox-dev-agent-$USER/<branch>            # or bring it into your working tree
```

Fetch again after the agent commits more. Before `sbx rm`, keep what you want with
`git branch review sandbox-dev-agent-$USER/<branch>`: removing the sandbox also removes the remote and its fetched branches.

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
  host. That also means the VM can no longer edit `digests.json`, `.mcp.json`, the Taskfile or `sbxenv.yaml` on your
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
- **SSH agent:** `ssh.agentForwardingEnabled` is turned off in Setup, so a client cannot forward your agent into the
  sandbox. It is separate from the IDE connection, which uses no agent (tested with it off). A `/run/ssh-agent.sock`
  socket still exists in the VM; your host agent has no keys loaded, so it offers nothing today.
- **Not done yet:** signed kits (`kit.requireSignature` is off, so a tampered pin is only caught by review), and live
  inspection of tool results, which needs a gateway.
- **Logs:** `sbx policy log` keeps per-host counts and the matching rule, with no method, path or tool name.
  agentgateway logs every MCP call with its tool name and session by default.
