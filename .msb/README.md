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
| Other secrets (Bitwarden) | `bws-secret.sh` and `secrets-sync` make an sbx custom secret | `msb.py` reads the Bitwarden project and gives msb the value. The VM has a placeholder |
| MCP servers | registered on the gateway (`sbx mcp add`) | `managedMcpServers` in a root-owned file of the image |
| Tool filter for GitHub MCP | the gateway removes the tools | a deny list in the same file. The client enforces it. It is a soft limit (see the token below) |
| Claude login | the sbx proxy supplies it | you sign in with your subscription. The `claude-home` volume keeps the login |
| Licence | proprietary | Apache-2.0, beta (v0.7) |

**Not ported yet:** the SPIRE agent (and Envoy) and the kind kubeconfig. The VM can already reach their ports on the host, and the Flux Operator web UI (host port 19090). The skills are in `.claude/skills` of the repository.

**Not ported, on purpose:**
- The egress rule on `api.github.com/repos/**` that blocks one HTTP method (the one that removes a repository). msb has rules for hosts only, not for methods or paths. The scope of the token is the limit (see below).
- The policy kit, the MCP gateway and the git token sync. `network.allow`, the managed settings and the token placeholder do their work.
- `policy-context.md`. It told the agent to use the sbx gateway tools. That text is wrong for msb. The agent instructions are in `AGENTS.md`.

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

5. **Bitwarden (only if you add a secret that comes from it).** `sandbox.yaml` has no such secret now. For one, `run` needs the access token of a Bitwarden machine account. Use one of these: set `BWS_ACCESS_TOKEN`, save the token in `~/.config/bws/access-token` (mode 600 or 400), or type it at the prompt. The prompt does not echo. For the EU cloud, set `BWS_SERVER_URL=https://vault.bitwarden.eu`.

## Getting started

```shell
just msb setup         # 1. one time for each host
just msb image-build   # 2. one time, and after you change dev-tools/
just msb run           # 3. every day
```

| Step | Command | What it does |
|---|---|---|
| 1 | `setup` | Authorizes your SSH key for `msb ssh`. Installs the Remote-SSH extension. Changes the VS Code user settings. This includes `remote.SSH.configFile`, which points to `ssh_config`. |
| 2 | `image-build` | Builds `dev-tools/` with Docker (Debian, mise and the tools of `dev-tools/mise.toml`). Loads the image into msb. The first build takes several minutes. |
| 3 | `run` | Makes the VM from `sandbox.yaml` if none exists. Leaves the VM as it is if it runs and is current. Stops with a message if the VM is not current. Then you remove it with `just msb rm`. Waits for the boot. Opens VS Code on the VM. You can run it as often as you want. |

In VS Code, open a terminal and run `claude`. The first time, sign in with your subscription. The VM keeps the login on the `claude-home` volume.

Other recipes: `just msb shell` (a bash prompt in the VM), `just msb allow-host <host>` and `just msb rm` (`--volumes` also removes the Claude login and the Terraform provider cache).

## How it works

- **The recipes and the steps.** The justfile lists the steps of each recipe in order. `msb.py` has the logic of the steps that need logic: `preflight`, `ensure-vm`, `wait-boot`, `ssh-key`, `vscode-settings` and `check-host`. It is a `uv` script with no dependencies. `just msb run` runs it for you. You can also run a step alone, for example `.msb/msb.py preflight`, if the environment has `MSB_NAME`, `MSB_IMAGE` and `MSB_WORKSPACE`.
- **One file.** `sandbox.yaml` declares the image, the size, the mounts, the secrets and the egress allow list. When `run` makes the VM, it stores a hash in the label `config-sha`. The hash covers the file, the image and the host values (the git directory and the git identity). If the hash is different at the next `run`, the VM is not current. msb fixes the config of a VM when it makes the VM. A VM that does not run is not current. msb does not run `sandbox-boot` when it starts a stopped VM, so the clone step and Headroom are missing. `run` does not remove a VM that is not current, because that removes the clone in it. `run` tells you to push your work and run `just msb rm && just msb run`. The volumes `claude-home` and `terraform-providers` stay.
- **The host values.** `sandbox.yaml` names five host values as `${NAME}`. The step `ensure-vm` of `msb.py` reads them from git and `gh` and puts them in the environment of `msb run`. The values are `GITHUB_TOKEN`, `SANDBOX_GIT_DIR`, `SANDBOX_BRANCH`, `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL`. These values change with the host. `sandbox.yaml` fixes the other settings: the path of the clone (`/home/agent/engineersdaybook`) and the URL of origin.
- **The clone.** The VM mounts only the `.git` directory of the host repo, at `/run/sandbox/source`. The VM cannot write to the mount. The VM cannot read your working tree, so it cannot read untracked files or `.env`. `dev-tools/sandbox-boot` clones the directory to `/home/agent/engineersdaybook`, on the branch of the host checkout. It sets `origin` to the GitHub URL. If the clone, the pre-commit hook or Headroom fails, `sandbox-boot` exits with an error. This stops the VM. Then `run` prints the boot log. Commit on the host before you run `run`, because the clone lacks uncommitted changes. Push a feature branch from the VM and open the pull request on GitHub. This also works for a git worktree.
- **The token.** The VM has only a placeholder in `GITHUB_TOKEN`. The host replaces it with your token in requests to `github.com`, `api.github.com` and `api.githubcopilot.com`. The host replaces it in Bearer auth and in Basic auth, so `git push` works. The host blocks the token for every other host.
- **Allowed hosts.** The VM can reach only the hosts in `network.allow`. HTTPS rules need TLS interception, and `sandbox.yaml` turns it on. A blocked host fails at DNS. `*.example.com` matches subdomains at any depth. msb rejects `**.example.com` and an entry with a port. To add a host, run `just msb allow-host example.org`. This command changes `sandbox.yaml`. Then run `just msb rm && just msb run` to make the VM again. Commit the change.
- **Volumes.** The VM has two named volumes. `claude-home` keeps the Claude login and settings. `terraform-providers` is the Terraform provider cache (`TF_PLUGIN_CACHE_DIR`). Both stay when you remove the VM, so a new VM keeps your login and does not download the providers again. `just msb rm --volumes` removes them. `sandbox-boot` gives the cache folder to the agent user.
- **Tools.** `dev-tools/mise.toml` lists the tools and their exact versions. The Dockerfile installs them with mise. Claude Code is one of them. After you change the file, run `just msb image-build`, then `just msb rm && just msb run`.
- **The size of the image.** The image is 3.5 GiB. The step that installs the tools removes the uv cache (about 880 MiB), because no tool reads it. The largest parts are `headroom-ai` (842 MiB), Claude Code (280 MiB), node (204 MiB), Terraform (116 MiB) and Python (108 MiB).
- **Publishing the image (maintainer).** Run `just msb image-login` one time. It logs docker in to `ghcr.io` with the Bitwarden secret `GITHUB_TOKEN`, which needs the scope `write:packages`. Then run `just msb image-publish`. It pushes `ghcr.io/raghav19/engineersdaybook/dev-sbx`. The tags are the commit, `latest` (only on `main`) and the git tag of the commit (if it has one). The layers use zstd at level 9, as the sbx kits do. zstd unpacks about 9 times faster than gzip. It also makes the large layer 10% smaller. The timestamps are the date of the last commit of `dev-tools/`. The build adds no provenance and no SBOM. So the same files give the same digest. The recipe stops if `dev-tools/` differs from the commit, because the tag is the commit. `sandbox.yaml` still uses the image that `just msb image-build` makes on your host.
- **MCP servers and the deny list.** `dev-tools/managed-settings.json` becomes `/etc/claude-code/managed-settings.json` in the VM. Root owns the file. The agent can read it and cannot change it. Project settings and user settings cannot override it. It declares draw.io, the Flux schema catalog and GitHub (`managedMcpServers`). It denies five GitHub tools (`merge_pull_request`, `delete_file` and others). The GitHub header has the placeholder `$MSB_GITHUB_TOKEN`. The host replaces it, so the file has no secret. Claude Code loads these servers without a prompt. `claude mcp remove` refuses to remove them. To change the file, run `just msb image-build`.
- **Secrets from Bitwarden.** To give the VM a secret, do three things. Add it under `secrets:` in `sandbox.yaml` with the hosts that can receive it. Add the hosts to `network.allow`. Add a key with the same name to the Bitwarden project. When `run` makes a VM, `msb.py` reads the Bitwarden project once and puts each value in the environment of `msb run`. The VM has a placeholder, and the host swaps in the value for those hosts only. The VM never has the value or the Bitwarden token. A key that is missing or not unique stops `run`. `GITHUB_TOKEN` (for `github.com`) comes from your `gh` login, not from Bitwarden. A `run` that leaves a running VM as it is does not call Bitwarden.
- **Ports of the host.** The VM can reach three ports of the host at `host.microsandbox.internal:<port>`. They are 6444 (the kind API server), 18081 (the SPIRE server) and 19090 (the Flux Operator web UI). `sandbox.yaml` cannot express a rule for a port, so `msb.py` passes one `--net-rule` for each (`HOST_PORTS`). The services are in the kind cluster. Nothing in the VM uses them yet, because the kubeconfig and the SPIRE agent are not ported.
- **Ponytail.** `sandbox-boot` installs the plugin ponytail 5.3.2 for Claude Code, as in sbx. The plugin is on the `claude-home` volume, so a new VM finds it. A failed install prints a warning and does not stop the boot.
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
