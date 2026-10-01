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
│ │ repo: mounted at the same path, read-write (virtiofs).             │ │
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

Only two things cross the boundary: the repo (read-write) and outbound requests, which go through the proxy.

| Rule | Declared in | Enforced by |
|---|---|---|
| Which domains the VM may reach | `agent-sandbox.yaml` (`network-policy@1`), plus your own `sbx policy` rules | host proxy |
| Which domain may receive the GitHub token | `agent-sandbox.yaml` (`credential@1`) and `sbxenv.yaml` (`bindings`), recorded in `~/.config/sbx/credentials.yaml` | host proxy |
| The GitHub token itself | `sbxenv.yaml` (`secrets.github`: the minter command) | sbx secret store on the host |


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
    ├─ 5. sbx creates the microVM from kit@digest and mounts the repo
    ├─ 6. sbx stores the `github` secret: command = the minter, refresh 55m
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

## Run

```shell
task sandbox:run
```

Read the plan that sbx prints (kit digest, host step, secret, binding) and approve it. The first run creates
`dev-agent-$USER`; later runs reattach. Extra arguments go to `sbx env run`: `task sandbox:run -- --detached`.

## Show that it is sandboxed

With the sandbox running, run these from a host terminal. `sbx exec` runs a command inside the VM.

```shell
VM=dev-agent-$USER

# 1. It has its own kernel: the VM reports a different version from the host
uname -r; sbx exec $VM uname -r

# 2. It is virtualized
sbx exec $VM grep -m1 -o hypervisor /proc/cpuinfo

# 3. The host runs a VM process for it
ps -eo pid,args | grep -E 'nerdbox|sbx daemon' | grep -v grep

# 4. Your host secrets are not there (every path: "No such file")
sbx exec $VM ls ~/.config/mcp-gh ~/.config/sops ~/.ssh ~/.aws

# 5. Only the repo is shared with the host (virtiofs mounts: the repo, skills, resolv.conf)
sbx exec $VM grep virtiofs /proc/mounts

# 6. Writes stay inside the VM, except in the shared repo
sbx exec $VM touch /tmp/demo; ls /tmp/demo          # not on the host
sbx exec $VM touch ./demo; ls ./demo; rm ./demo     # run from the repo root: it is on the host

# 7. Network access is allow-listed
sbx exec $VM curl -s -o /dev/null -w '%{http_code}\n' https://example.com               # 403
sbx exec $VM curl -s -o /dev/null -w '%{http_code}\n' https://api.githubcopilot.com     # reachable (404 on a plain GET)
```

Step 6 shows the limit as well: the repo is writable from the VM, so the agent can change your files.
Review `git diff` after a session.

## Publish a new kit or minter
> NOTE: i have used my gh repo

```shell
task sandbox:build          # build and push the kit, writes its digest to digests.json
task sandbox:build-minter   # push mint-gh-app-token.sh, writes its digest to digests.json
```

Run `build-minter` only when the script changes, and make its ghcr package public once. Then review and commit
`git diff digests.json`.


## Limits

- The GitHub App's installation permissions are the real boundary. The `X-MCP-*` headers only narrow the MCP tools.
- `gh` and `git` over https also use the token (the proxy injects it on `api.github.com`). `AGENTS.md` asks Claude to
use the MCP tools, but nothing enforces it.
- `digests.json` is writable from inside the VM. A tampered digest can only pick another digest of the two
  repositories, so read `git diff digests.json` before `sandbox:run`.
- See `HANDOFF.md` for what has and has not been verified.
