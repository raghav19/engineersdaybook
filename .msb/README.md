# The dev sandbox on microsandbox

This sandbox is a VM for Claude Code and VS Code. It uses [microsandbox](https://docs.microsandbox.dev) (open source, Apache-2.0). It does the work of `.sbx/`. It has no daemon. One file declares the whole VM: `sandbox.yaml`.

This branch is a trial. `.sbx/` does not change. Both sandboxes can run at the same time. `just sandbox ...` uses sbx. `just msb ...` uses this sandbox.

## What is different from sbx

| | sbx (`.sbx/`) | microsandbox (`.msb/`) |
|---|---|---|
| Host service | sbx daemon (systemd unit) | none. `msb` starts the VM as a child process |
| Allowed hosts | policy kit, `sbx policy allow` and a kit rebuild | `network.allow` in `sandbox.yaml` |
| VS Code | `sbx setup ssh` | `ProxyCommand msb ssh serve` in `ssh_config`. The VM has no sshd |
| GitHub token | proxy replacement. The MCP gateway holds the OAuth token | proxy replacement only. The VM has a placeholder |
| MCP servers | registered on the gateway (`sbx mcp add`) | `managedMcpServers` in a root-owned file of the image |
| Tool filter for GitHub MCP | the gateway removes the tools | a deny list in the same file. The client enforces it. It is a soft limit (see the token below) |
| Claude login | the sbx proxy supplies it | you sign in with your subscription. The `claude-home` volume keeps the login |
| Licence | proprietary | Apache-2.0, beta (v0.7) |

**Not ported yet:** the SPIRE agent, the kind kubeconfig and the Flux Operator UI. The skills are in `.claude/skills` of the repository.

## Prerequisites

1. **Install the tools.** You need [mise](https://mise.jdx.dev), VS Code, Docker (for the image build) and access to `/dev/kvm`.

   ```shell
   mise trust && mise install
   eval "$(mise activate bash)"
   msb doctor        # each line must have a check mark
   ```

2. **Log in to GitHub with `gh`** (`gh auth login`). `run` gives the VM a placeholder for the token of this login. This token is your user token. It is broader than a token for one repository. To limit it, log in with a fine-grained token for this repository: `gh auth login --with-token`.

3. **Have an SSH key** at `~/.ssh/id_ed25519` (`ssh-keygen -t ed25519`). `ssh_config` uses it.

4. **Commit your work.** The VM clones the committed files only.

## Getting started

```shell
just msb setup         # 1. one time for each host
just msb image-build   # 2. one time, and after you change image/
just msb run           # 3. every day
```

| Step | Command | What it does |
|---|---|---|
| 1 | `setup` | Authorizes your SSH key for `msb ssh`. Installs the Remote-SSH extension. Changes the VS Code user settings. This includes `remote.SSH.configFile`, which points to `ssh_config`. |
| 2 | `image-build` | Builds `image/` with Docker (Debian, mise and the tools of `image/tools.toml`). Loads the image into msb. The first build takes several minutes. |
| 3 | `run` | Makes the VM from `sandbox.yaml` if none exists. Leaves the VM as it is if it runs and is current. Stops with a message if the VM is not current. Then you remove it with `just msb rm`. Waits for the boot. Opens VS Code on the VM. You can run it as often as you want. |

In VS Code, open a terminal and run `claude`. The first time, sign in with your subscription. The VM keeps the login on the `claude-home` volume.

Other recipes: `just msb shell` (a bash prompt in the VM), `just msb allow-host <host>` and `just msb rm` (`--volumes` also removes the Claude login).

## How it works

- **One file.** `sandbox.yaml` declares the image, the size, the mounts, the secrets and the egress allow list. When `run` makes the VM, it stores a hash in the label `config-sha`. The hash covers the file, the image and the host values (the git directory and the git identity). If the hash is different at the next `run`, the VM is not current. msb fixes the config of a VM when it makes the VM. A VM that does not run is not current. msb does not run `sandbox-boot` when it starts a stopped VM, so the clone step and Headroom are missing. `run` does not remove a VM that is not current, because that removes the clone in it. `run` tells you to push your work and run `just msb rm && just msb run`. The `claude-home` volume stays.
- **The host values.** `sandbox.yaml` names five host values as `${NAME}`. `run` puts them in its environment with `[env]` lines in the justfile. The values are `GITHUB_TOKEN`, `SANDBOX_GIT_DIR`, `SANDBOX_BRANCH`, `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL`. These values change with the host. `sandbox.yaml` fixes the other settings: the path of the clone (`/home/agent/engineersdaybook`) and the URL of origin.
- **The clone.** The VM mounts only the `.git` directory of the host repo, at `/run/sandbox/source`. The VM cannot write to the mount. The VM cannot read your working tree, so it cannot read untracked files or `.env`. `image/sandbox-boot` clones the directory to `/home/agent/engineersdaybook`, on the branch of the host checkout. It sets `origin` to the GitHub URL. If the clone, the pre-commit hook or Headroom fails, `sandbox-boot` exits with an error. This stops the VM. Then `run` prints the boot log. Commit on the host before you run `run`, because the clone lacks uncommitted changes. Push a feature branch from the VM and open the pull request on GitHub. This also works for a git worktree.
- **The token.** The VM has only a placeholder in `GITHUB_TOKEN`. The host replaces it with your token in requests to `github.com`, `api.github.com` and `api.githubcopilot.com`. The host replaces it in Bearer auth and in Basic auth, so `git push` works. The host blocks the token for every other host.
- **Allowed hosts.** The VM can reach only the hosts in `network.allow`. HTTPS rules need TLS interception, and `sandbox.yaml` turns it on. A blocked host fails at DNS. To add a host, run `just msb allow-host example.org`. This command changes `sandbox.yaml`. Then run `just msb rm && just msb run` to make the VM again. Commit the change.
- **Tools.** `image/tools.toml` lists the tools and their exact versions. The Dockerfile installs them with mise. Claude Code is one of them. After you change the file, run `just msb image-build`, then `just msb rm && just msb run`.
- **MCP servers and the deny list.** `image/managed-settings.json` becomes `/etc/claude-code/managed-settings.json` in the VM. Root owns the file. The agent can read it and cannot change it. Project settings and user settings cannot override it. It declares draw.io, the Flux schema catalog and GitHub (`managedMcpServers`). It denies five GitHub tools (`merge_pull_request`, `delete_file` and others). The GitHub header has the placeholder `$MSB_GITHUB_TOKEN`. The host replaces it, so the file has no secret. Claude Code loads these servers without a prompt. `claude mcp remove` refuses to remove them. To change the file, run `just msb image-build`.
- **The limit of the deny list.** The agent can still call the GitHub API with the placeholder token. The host then uses your token. The deny list stops mistakes. The **scope of the token** sets what the agent can do on GitHub. Use a fine-grained token for this repository (prerequisite 2).
- **The shell.** The shell is plain bash. `/etc/profile.d` puts the mise shims on the `PATH` and sets `EDITOR`. Completions for the tools are available. There is no prompt theme and no fzf.
- **Git identity.** `sandbox.yaml` sets `GIT_AUTHOR_*` and `GIT_COMMITTER_*` from your host git config. The image has the token helper and `safe.directory` in its system git config.
- **VS Code.** microsandbox has no sshd in the VM. The `msb` command on the host is the SSH server. `ssh_config` starts it as a `ProxyCommand`. The VM must run before VS Code connects. `run` makes sure of this.

## When something fails

| You see | Do this |
|---|---|
| `run` says the image does not exist | Run `just msb image-build`. |
| `msb doctor` shows a red line | Read the line. For `/dev/kvm`, run `sudo usermod -aG kvm "$USER"`, then log in again. |
| `run` says the VM did not finish its boot | `run` prints the end of the boot log (`sandbox-boot: ...`). The clone, the hook or Headroom failed. `msb logs sandbox-dev` shows all of the log. |
| `msb ls` shows `crashed` or `stopped` | If the clone has work, push it first. For a stopped VM, run `msb start sandbox-dev` first. Then run `just msb rm && just msb run`. |
| `run` says the VM is not current | `sandbox.yaml`, the image or a host value changed, or the VM stopped. Push the work in the clone (`just msb shell`). Then run `just msb rm && just msb run`. |
| A site fails in the VM | The site is not in `network.allow`. Run `just msb allow-host <host>`. |
| VS Code cannot connect | Run `just msb setup` again. Make sure that `msb ls` shows the VM as `running`. Close the VS Code window. Open it again with `run`. |
| `claude` asks for a login again | Run `just msb rm` without `--volumes`. The volume keeps the login. |
| You want a clean start | Run `just msb rm --volumes`, then `just msb run`. |

More commands: `msb ls` (state), `msb logs sandbox-dev`, `msb inspect sandbox-dev` (the settings and the `config-sha` label) and `msb <command> --help`.
