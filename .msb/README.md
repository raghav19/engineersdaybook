# The dev sandbox on microsandbox

A microVM for Claude Code and VS Code, on [microsandbox](https://docs.microsandbox.dev) (open source, Apache-2.0). It does the work of `.sbx/`, with no daemon and with one file that declares the whole VM: `sandbox.yaml`.

This branch is a trial. `.sbx/` stays as it is, and both run side by side (`just sandbox ...` is sbx, `just msb ...` is this).

## What is different from sbx

| | sbx (`.sbx/`) | microsandbox (`.msb/`) |
|---|---|---|
| Host service | sbx daemon (systemd unit) | none: `msb` starts the VM as a child process |
| Allowed hosts | policy kit + `sbx policy allow` + kit rebuild | `network.allow` in `sandbox.yaml` |
| VS Code | `sbx setup ssh` | `ProxyCommand msb ssh serve` in `ssh_config`, no sshd in the VM |
| GitHub token | proxy swap, plus the MCP gateway holds the OAuth token | proxy swap only (the VM holds a placeholder) |
| MCP servers | registered on the gateway (`sbx mcp add`) | `.mcp.json` in the repo root |
| Tool filter for GitHub MCP | the gateway removes the tools | a deny list in `.claude/settings.json`, which the client enforces (a soft limit) |
| Claude login | injected by the sbx proxy | you sign in with your subscription. The login is on the `claude-home` volume |
| Licence | proprietary | Apache-2.0, beta (v0.7) |

**Not ported yet:** the SPIRE agent, the kind kubeconfig, the Flux Operator UI, and the skills store.

## Prerequisites

1. **Install the tools.** You need [mise](https://mise.jdx.dev), VS Code, Docker (for the image build) and `/dev/kvm` access.

   ```shell
   mise trust && mise install
   eval "$(mise activate bash)"
   msb doctor        # every line must have a check mark
   ```

2. **Log in to GitHub with `gh`** (`gh auth login`). `run` passes the token of this login to the VM as a placeholder. It is your user token, which is broader than a one-repository token. To limit it, log in with a fine-grained token for this repository: `gh auth login --with-token`.

3. **Have an SSH key** at `~/.ssh/id_ed25519` (`ssh-keygen -t ed25519`). `ssh_config` uses it.

4. **Commit your work.** The VM clones the committed files only.

## Getting started

```shell
just msb setup         # 1. once per machine
just msb image-build   # 2. once, and after you change image/
just msb run           # 3. every day
```

| Step | Command | What it does for you |
|---|---|---|
| 1 | `setup` | Authorizes your SSH key for `msb ssh`. Installs the Remote-SSH extension. Sets the VS Code user settings, including `remote.SSH.configFile`, which points to `ssh_config`. |
| 2 | `image-build` | Builds `image/` with Docker (Debian, mise, the tools of `image/tools.toml`) and loads it into msb. The first build takes several minutes. |
| 3 | `run` | Creates the VM from `sandbox.yaml` or starts it. Makes it again if `sandbox.yaml` or the image changed. Waits for the clone. Opens VS Code on it. |

In VS Code, open a terminal and run `claude`. Sign in with your subscription the first time. The VM keeps the login on the `claude-home` volume.

Other recipes: `just msb shell` (a bash prompt in the VM), `just msb allow-host <host>`, `just msb rm` (`--volumes` also deletes the Claude login).

## How it works

- **One file.** `sandbox.yaml` declares the image, size, mounts, secrets and the egress allow list. `run` stores a hash of the file and of the image in the label `config-sha`. If the hash is different, `run` makes the VM again. The `claude-home` volume stays. `run` refuses first if the clone in the VM has work that is not pushed (set `SANDBOX_FORCE=1` to drop it).
- **The clone.** Only the `.git` directory of the host repo is mounted, read-only, at `/run/sandbox/source`. The VM cannot read your working tree: no untracked file, no `.env`. `image/sandbox-boot` clones it to the same path as on the host, on the branch that is checked out on the host, and sets `origin` to the GitHub URL. Commit on the host before `run`: uncommitted changes are not in the clone. Push a feature branch from the VM and open the pull request on GitHub. This works for a git worktree too.
- **The token.** The VM has only a placeholder in `GITHUB_TOKEN`. The host swaps it for your token on requests to `github.com`, `api.github.com` and `api.githubcopilot.com`. It is swapped for Bearer and Basic auth, so `git push` works. The token is blocked toward every other host.
- **Allowed hosts.** The VM can reach only the hosts in `network.allow`. HTTPS rules need TLS interception, which `sandbox.yaml` turns on. A blocked host fails at DNS. To add one: `just msb allow-host example.org`. This edits `sandbox.yaml` and makes the VM again. Commit the change.
- **Tools.** `image/tools.toml` lists the tools and their exact versions. The Dockerfile installs them with mise. Claude Code is one of them. After you edit the file, run `just msb image-build`, then `just msb run`.
- **MCP servers.** `.mcp.json` declares draw.io, the Flux schema catalog and GitHub. The GitHub entry sends `Bearer ${GITHUB_TOKEN}`, which is the placeholder, and the host swaps it. `enabledMcpjsonServers` in `.claude/settings.json` approves the three servers, so Claude Code does not ask. It applies only in a folder that you trust, so you answer the trust prompt once. In sbx the same `.mcp.json` loads next to the gateway servers.
- **The shell.** A plain bash with the mise shims on the `PATH` (`/etc/profile.d`), `EDITOR` set, and completions for the tools. There is no prompt theme and no fzf.
- **Git identity.** `sandbox.yaml` sets `GIT_AUTHOR_*` and `GIT_COMMITTER_*` from your host git config. The image holds the token helper and `safe.directory` in its system git config.
- **VS Code.** microsandbox has no sshd in the VM. The `msb` command on the host is the SSH server, and `ssh_config` starts it as a `ProxyCommand`. The VM must run before VS Code connects, and `run` makes sure of it.

## When something fails

| You see | Do this |
|---|---|
| `run` says the image does not exist | `just msb image-build` |
| `msb doctor` shows a red line | Read the line. For `/dev/kvm`: `sudo usermod -aG kvm "$USER"`, then log in again. |
| `run` says the clone is not ready | `msb logs sandbox-dev` shows the boot log (`sandbox-boot: ...`). |
| `msb ls` shows `crashed` or `stopped` | `just msb run` starts it. |
| `run` refuses to make the VM again | The clone has work that is not pushed. Push it, or run `SANDBOX_FORCE=1 just msb run`. |
| A site fails in the VM | It is not in `network.allow`. `just msb allow-host <host>`. |
| VS Code cannot connect | Run `just msb setup` again. Check that `msb ls` shows the VM as `running`. Close the VS Code window and open it again from `run`. |
| `claude` asks for a login again | Run `just msb rm` without `--volumes`. The volume keeps the login. |
| You want a clean start | `just msb rm --volumes`, then `just msb run`. |

More commands: `msb ls` (state), `msb logs sandbox-dev`, `msb inspect sandbox-dev` (the settings and the `config-sha` label), `msb <command> --help`.
