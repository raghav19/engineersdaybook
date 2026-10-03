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
├── sbxenv.yaml           the sandbox: kits, secret, binding
├── dev-tools/            the kit: tools, completions, shell, egress policy, credential
├── scripts/              host minter: mint-gh-app-token.sh (App key -> installation token)
├── Taskfile.yml          sandbox:run, :build
├── mise.toml             host env: GH_APP_* for sbx, and loads .env.secrets.json
├── .env.secrets.json     sops-encrypted GITHUB_TOKEN, loaded by mise.toml (rules in the repo-root .sops.yaml)
└── README.md

Outside this directory
├── .mcp.json                       (repo root) GitHub MCP entry, no token
├── mise.toml                       (repo root) exact tool versions
├── .vscode/                        (repo root) extensions, settings
├── AGENTS.md                       (repo root) tells Claude to use MCP tools
├── ~/.config/mcp-gh/               (host) App private key
└── ~/.config/sbx/credentials.yaml  (host) approved bindings, no secrets
```

## How it works

```text
PUBLISH (maintainer, when the kit changes)

  task sandbox:build
    dev-tools kit ──push──▶ ghcr.io ──digest──▶ sbxenv.yaml

RUN (developer)

  task sandbox:run      (sbx env run .)
    │
    ├─ 1. sbx reads sbxenv.yaml and prints the plan (kit digest, secret
    │     command) ──▶ you approve
    ├─ 2. sbx creates the microVM from the kits and clones the repo into it
    ├─ 3. sbx stores the `github-mcp` secret: command = scripts/mint-gh-app-token.sh
    │     (run on the host, from this directory), refresh 55m
    ├─ 4. sbx env run returns; task sandbox:run opens VS Code on the sandbox
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

- `sbxenv.yaml` declares the sandbox: the Docker shell workload and Claude mixin (by tag), and your `dev-tools` kit, which carries the egress
  policy and the GitHub credential. `task sandbox:build` writes the `dev-tools` digest. The registry is fixed in the file, so a digest
  can only name an image from your repository.
- The minter, `mint-gh-app-token.sh`, runs on your host from the repo. The dev sandbox cannot change it: its repo
  is a read-only clone.
- `.mcp.json` only narrows the tool list. The proxy adds the `Authorization` header.
- Claude signs in through sbx's global OAuth login, so a new sandbox needs no login.

## Setup (once per machine)

1. Install the tools (`task`, `yq`):

```shell
mise install
```

2. Put the GitHub App private key at `~/.config/mcp-gh/<gh-private-key>` (or change `GH_APP_KEY_PATH` in `mise.toml`).

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
task sandbox:build   # maintainer, when the kit or the tools change: build and push the dev-tools kit, pin its digest
task sandbox:run     # developer: create or start the sandbox and open VS Code on it, then return
```

`task sandbox:run` runs `sbx env run . --detached`, then opens VS Code on the sandbox. sbx cannot read host environment variables, so
the task passes the values `mise.toml` loads (`GH_APP_ID`, `GH_APP_INSTALLATION_ID`, `GH_APP_KEY_PATH`) as `--env-arg appId=…`, `installationId=…` and `keyPath=…`.
Run `mise trust` in this directory once. If you call `sbx env run` or `sbx env plan` yourself, pass the same `--env-arg` flags, or sbx stops with
"requires 3 arguments". `sbx env run` reads `sbxenv.yaml`, prints a plan
and asks you to approve it, then creates the sandbox `dev-agent-sbx` from the pinned kit, clones the repo into it, stores
the GitHub secret and returns. The task then opens VS Code on the sandbox over Remote-SSH. The plan's one host command
is the GitHub token minter. Run Claude Code in the VS Code terminal.
Run `task sandbox:run` again, or connect to `dev-agent-sbx.sbx` with Remote-SSH, to reopen the window.
`task sandbox:build` also pins: after the push it writes the registry's digest for the tag into `sbxenv.yaml`. An existing sandbox keeps
its old kit, so remove it and run `task sandbox:run` again to get the new one.

**Secret:** `.env.secrets.json` is sops-encrypted, and `mise.toml` loads it with mise's native sops support (`_.file`). mise decrypts it with the
age key at `~/.config/mise/age.txt`, so `GITHUB_TOKEN` is in the environment of every process mise starts in this folder. Do not start an agent
session here with mise active, and note that `redact` only hides the value in task output, not in `mise env`. Without the key every mise call here
fails. To edit the file run sops from the repo root, so the root `.sops.yaml` applies: `sops .env.secrets.json`. The sops CLI finds the key at
`~/.config/sops/age/keys.txt`, a symlink to the mise path.

The window shows the **VM's clone**, the same folder the agent edits, so you see its changes live and it sees yours. Your
host working tree is not touched, and a VS Code window on the host shows only host files until you fetch. Terminals,
extensions and `.vscode/tasks.json` run inside the VM. Commit on a branch there and use the next section to bring the work
to your host.

If `code` is not on your PATH, `task sandbox:run` fails to open the window after the sandbox is up: in VS Code run **Remote-SSH: Connect to Host...**, type
`dev-agent-sbx.sbx`, and open the repo folder (same path as on your host). SSH ends at the sbx daemon, there is no SSH
server in the VM, and a stopped sandbox starts when you connect. The generated SSH config forwards no agent and uses
your Docker login, not a key.

If VS Code reports "the remote host may not meet VS Code Server's prerequisites for glibc and libstdc++", the image has no
`/etc/ld.so.cache`, so `ldconfig` finds nothing. The `dev-tools` startup command runs `ldconfig` at every boot. A sandbox
created from an older kit needs it once by hand: `ssh dev-agent-sbx.sbx -- sudo ldconfig`.

### Tools, shell and extensions in the sandbox

The developer environment is **baked into the `dev-tools` kit**, an OCI image that `task sandbox:build` builds and pushes,
so a boot installs nothing. The image is built from files in this repo, so they stay the single source:

| File | What it does |
|---|---|
| `mise.toml` | the tools in `[tools]`, at exact versions (fzf, starship, fd, kubectl, helm, kustomize, Node, Python 3.13, uv, task, yq), installed into `/opt/mise` at build. It is also copied to `/etc/mise/config.toml`, so the tools resolve from any directory |
| `.vscode/extensions.json` | the extensions your host VS Code recommends. They are not baked into the image: see **VS Code Server and extensions** below |
| `dev-tools/dev-tools.yaml` | the kit in one file: the descriptor (egress policy, GitHub credential, agent context), the build recipe, and the boot setup. The shell setup is a `files` entry, `~/.dev-tools-shellrc` (completions, fzf key bindings, the starship prompt), and one inline startup command (root, every boot) runs `ldconfig`, sets bash as the login shell and sources that file from `~/.bashrc` |
| `dev-tools/tasks.toml` | the build's mise task, loaded by `task_config` in `mise.toml`: `sandbox:completions` writes the bash completions |
| `.vscode/settings.json` | workspace settings: the terminal uses bash |

To change a tool version or the shell setup (inline in `dev-tools.yaml`): edit the file, **commit it**, run `task sandbox:build` and
`task sandbox:run` on a new sandbox, because the image is built, not read from the clone. Pin every tool in `mise.toml` to an
exact version, since the image carries those versions and the shims in the VM use them as they are.

What a boot does now, measured in a scratch sandbox with the same image content (2 vCPU, 2 GiB):

| Step | Time |
|---|---|
| VM created and answering | 3 to 25 s (the first create extracts the image) |
| `dev-tools` startup command | 4 s, measured with the older script that also linked the VS Code files; not re-measured |

The image was **2.7 GB uncompressed** before the VS Code server and extensions were left out of it, and its new size is not
measured. It builds in about 2.5 minutes (2 m 24 s locally), once per change, instead of on every sandbox.

**VS Code Server and extensions:** neither is in the image. Remote-SSH downloads the server on the first connect (about 215 MB,
from `update.code.visualstudio.com`, which the kit allows), and the boot command only runs `ldconfig` so that server can start.
The extensions come from `remote.SSH.defaultExtensions` in your **host user settings**, which installs them on every SSH host at connect time.
It is read only from user settings (reports say a workspace `.vscode/settings.json` or a non-default profile is ignored), so it is
set once on your machine, with the IDs from `.vscode/extensions.json`, and is not part of this repo. Reconnect to a running sandbox to
install them.

**Memory:** `sbxenv.yaml` gives the sandbox 2 GiB. With 512 MiB the VM ran out of memory under VS Code, and SSH timed out.

**Python tools with uv:** `[settings] pipx.uvx = true` makes mise install `pipx:` tools with uv, as the
[mise cookbook](https://mise.jdx.dev/mise-cookbook/python.html) recommends, and `uv` is in `[tools]`. The image installs
`mise.toml` as it is. The host's headroom CLI (`pipx:headroom-ai`, about 550 MB) is declared in `~/mise.toml`, not in this repo,
so the image never installs it.

Notes:
- **Skills:** this repo commits its skills (`.claude/skills`, `skills-lock.json`), so every clone and sandbox already has them and
  the sandbox installs nothing at boot. To refresh them, run `mise run setup-skills` on the host (it fetches the latest upstream and
  rewrites the tracked files, so review and commit the diff). Tested on this repo: running it over the committed skills changed 31 files,
  and `npx skills experimental_install` took about 3 minutes, reported "No valid skills found", edited the lock file and created
  1052 untracked files under `.agents/`.
- **Shims, and no `[env]`:** the image's `ENV` puts `/opt/mise/shims` on PATH, so mise picks each tool's version. Shims apply the
  `[env]` of `mise.toml`, which sets `ANTHROPIC_BASE_URL=http://localhost:8787` for the host's headroom proxy and would reach every tool
  in the VM, where nothing listens on that port. So the image sets `MISE_NO_ENV=1` (tested: Node sees no `ANTHROPIC_BASE_URL`). Do not
  drop it. `MISE_TRUSTED_CONFIG_PATHS` trusts the clone's `mise.toml`, at the `workspace` build arg of `dev-tools/dev-tools.yaml`
  (the repo's path on your host). A `mise.toml` in any other directory is untrusted and its tools fail with a trust error.
- **bash:** the image's login shell is `/bin/sh`, and VS Code's terminal follows `$SHELL`, which is `/bin/sh` over SSH. So
  the boot command sets bash as the login shell, and `.vscode/settings.json` selects bash in the VS Code terminal. VS Code
  treats that setting as restricted, so it applies once you trust the folder (it asks when you open it). It also applies to
  terminals on your host in this repo.
- **Network:** nothing is installed at boot, so the kit no longer allows the install hosts (`mise.run`, `mise.jdx.dev`,
  `github.com` release assets, `dl.k8s.io`, `get.helm.sh`). It keeps `update.code.visualstudio.com`, the VS Code server download host and
  the marketplace (`**.vsassets.io`), which Remote-SSH needs on the first connect and for the extensions. A tool the image lacks, such as
  a version you bump in `mise.toml` without a rebuild, fails to run in the VM.
- **Not tested:** the published path end to end (this README's numbers come from a scratch sandbox built from the same image,
  because sbx needs an HTTPS registry for v3 kits); a real Remote-SSH connection to a sandbox built from this image, which covers the
  server download, `remote.SSH.defaultExtensions` and the shims on the sandbox's PATH. The tools were run in a plain Debian container as
  a non-root user with the image's `ENV`. Also untested in a running VM: the `files` entry (`~/.dev-tools-shellrc`), which sbx accepts
  (`sbx kit inspect` counts 1 init file) but which I have not seen written, and the startup command appending to `~/.bashrc`.
- **On the host:** `mise install` in the repo installs the same tools. `sandbox:completions` only works inside the image build.

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
- **No boot hooks from the clone:** the tools, completions and shell come from the digest-pinned `dev-tools` image, so the agent
  cannot change them by editing the clone, and the kit runs nothing from the clone at boot.
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
