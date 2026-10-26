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
| MCP servers | registered on the gateway (`sbx mcp add`) | `managedMcpServers` in a root-owned file of the image |
| Tool filter for GitHub MCP | the gateway removes the tools | a deny list in the same file, which the client enforces (a soft limit: see the token below) |
| Claude login | injected by the sbx proxy | you sign in with your subscription. The login is on the `claude-home` volume |
| Licence | proprietary | Apache-2.0, beta (v0.7) |

**Not ported yet:** the SPIRE agent, the kind kubeconfig, and the Flux Operator UI. (The skills are in `.claude/skills` of the repository.)

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
| 3 | `run` | Makes the VM from `sandbox.yaml` if there is none. Leaves a VM alone if it runs and is current. Stops with a message if the VM is not current (you remove it with `just msb rm`). Waits for the boot. Opens VS Code on it. You can run it as often as you like. |

In VS Code, open a terminal and run `claude`. Sign in with your subscription the first time. The VM keeps the login on the `claude-home` volume.

Other recipes: `just msb shell` (a bash prompt in the VM), `just msb allow-host <host>`, `just msb rm` (`--volumes` also deletes the Claude login).

## How it works

- **One file.** `sandbox.yaml` declares the image, size, mounts, secrets and the egress allow list. `run` stores a hash of the file, the image and the host values (repo path, git directory, origin URL, git identity) in the label `config-sha` when it makes the VM. At the next `run`, a different hash means the VM is out of date, because msb fixes the config of a VM when it makes it. A VM that is not running is out of date too: when msb starts a stopped VM it does not run `sandbox-boot`, so the clone step and Headroom would be missing. `run` does not remove such a VM, because that deletes the clone in it. It tells you to push your work and run `just msb rm && just msb run`. The `claude-home` volume stays.
- **The clone.** Only the `.git` directory of the host repo is mounted, read-only, at `/run/sandbox/source`. The VM cannot read your working tree: no untracked file, no `.env`. `image/sandbox-boot` clones it to the same path as on the host, on the branch that is checked out on the host, and sets `origin` to the GitHub URL. If the clone, the pre-commit hook or Headroom fails, `sandbox-boot` exits with an error, which stops the VM. `run` then prints the boot log. Commit on the host before `run`: uncommitted changes are not in the clone. Push a feature branch from the VM and open the pull request on GitHub. This works for a git worktree too.
- **The token.** The VM has only a placeholder in `GITHUB_TOKEN`. The host swaps it for your token on requests to `github.com`, `api.github.com` and `api.githubcopilot.com`. It is swapped for Bearer and Basic auth, so `git push` works. The token is blocked toward every other host.
- **Allowed hosts.** The VM can reach only the hosts in `network.allow`. HTTPS rules need TLS interception, which `sandbox.yaml` turns on. A blocked host fails at DNS. To add one: `just msb allow-host example.org`. This edits `sandbox.yaml`. Then `just msb rm && just msb run` makes the VM again. Commit the change.
- **Tools.** `image/tools.toml` lists the tools and their exact versions. The Dockerfile installs them with mise. Claude Code is one of them. After you edit the file, run `just msb image-build`, then `just msb rm && just msb run`.
- **MCP servers and the deny list.** `image/managed-settings.json` goes to `/etc/claude-code/managed-settings.json`. Root owns the file, so the agent in the VM can read it and cannot change it, and project and user settings cannot override it. It declares draw.io, the Flux schema catalog and GitHub (`managedMcpServers`), and denies five GitHub tools (`merge_pull_request`, `delete_file` and others). The GitHub header holds the placeholder `$MSB_GITHUB_TOKEN`, and the host swaps it, so the file holds no secret. Claude Code loads these servers without a prompt, and `claude mcp remove` refuses to remove them. A change needs `just msb image-build`.
- **The limit of the deny list.** The agent can still call the GitHub API with the placeholder token, and the host swaps in your token. So the deny list stops mistakes. What the agent can really do with GitHub is set by the **scope of the token**: use a fine-grained token for this repository (prerequisite 2).
- **The shell.** A plain bash with the mise shims on the `PATH` (`/etc/profile.d`), `EDITOR` set, and completions for the tools. There is no prompt theme and no fzf.
- **Git identity.** `sandbox.yaml` sets `GIT_AUTHOR_*` and `GIT_COMMITTER_*` from your host git config. The image holds the token helper and `safe.directory` in its system git config.
- **VS Code.** microsandbox has no sshd in the VM. The `msb` command on the host is the SSH server, and `ssh_config` starts it as a `ProxyCommand`. The VM must run before VS Code connects, and `run` makes sure of it.

## When something fails

| You see | Do this |
|---|---|
| `run` says the image does not exist | `just msb image-build` |
| `msb doctor` shows a red line | Read the line. For `/dev/kvm`: `sudo usermod -aG kvm "$USER"`, then log in again. |
| `run` says the sandbox did not finish its boot | It prints the end of the boot log (`sandbox-boot: ...`): the clone, the hook or Headroom failed. `msb logs sandbox-dev` shows all of it. |
| `msb ls` shows `crashed` or `stopped` | Push the work in the clone if it has any (for a stopped VM: `msb start sandbox-dev` first). Then `just msb rm && just msb run`. |
| `run` says the VM is not current | `sandbox.yaml`, the image or a host value changed, or the VM stopped. Push the work in its clone (`just msb shell`), then `just msb rm && just msb run`. |
| A site fails in the VM | It is not in `network.allow`. `just msb allow-host <host>`. |
| VS Code cannot connect | Run `just msb setup` again. Check that `msb ls` shows the VM as `running`. Close the VS Code window and open it again from `run`. |
| `claude` asks for a login again | Run `just msb rm` without `--volumes`. The volume keeps the login. |
| You want a clean start | `just msb rm --volumes`, then `just msb run`. |

More commands: `msb ls` (state), `msb logs sandbox-dev`, `msb inspect sandbox-dev` (the settings and the `config-sha` label), `msb <command> --help`.
