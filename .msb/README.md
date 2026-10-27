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
| Other secrets (Bitwarden) | `bws-secret.sh` and `secrets-sync` make an sbx custom secret | `bws run` puts the Bitwarden keys in the environment of one command, and msb gives the VM a placeholder |
| MCP servers | registered on the gateway (`sbx mcp add`) | `managedMcpServers` in a root-owned file of the image |
| Tool filter for GitHub MCP | the gateway removes the tools | a deny list in the same file. The client enforces it. It is a soft limit (see the token below) |
| Claude login | the sbx proxy holds your login and adds it to requests | `msb.py` reads the access token of the login that `claude` keeps on the host. msb gives the VM a placeholder and replaces it on the network. You do not log in to Claude in the VM |
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

2. **Log in to GitHub with the GitHub App** (`just msb github-login`). This is the web flow of the app, with its client ID and client secret. The step opens GitHub in your browser, and you click Authorize. GitHub then sends the browser to a small server on port 8765 of this host (the callback address of the app, `http://127.0.0.1:8765/callback`). The step waits 5 minutes for you. The client secret is the Bitwarden key `GITHUB_APP_CLIENT_SECRET` (prerequisite 5). You installed the app on this repository only, and it has the permissions contents, issues and pull requests. It has no Administration permission, so GitHub refuses a change to the settings of the repository, whatever the agent sends. The tokens go to `~/.config/msb/github-app.json` (mode 600). The access token lasts 8 hours, and `run` refreshes it. If the refresh token is lost or too old (about 6 months), `run` tells you to log in again. There is no fallback to `gh`, because that token is broader.

3. **Have an SSH key** at `~/.ssh/id_ed25519` (`ssh-keygen -t ed25519`). `ssh_config` uses it.

4. **Commit your work.** The VM clones the committed files only.

6. **Log in to Claude on the host** (run `claude` and sign in with your subscription). The VM takes this login: you do not log in again in the VM. `run` stops with a message if the login is missing, or if its access token lasts less than 30 minutes. Then start `claude` on the host, which refreshes it.

5. **Bitwarden.** `run` and `image-publish` use `bws run`, which puts each key of the Bitwarden project in the environment of one command. `bws` reads the access token of the machine account from `BWS_ACCESS_TOKEN`, so set it in your shell, for example `export BWS_ACCESS_TOKEN=$(cat ~/.config/bws/access-token)`. If the token is missing, `bws` stops the recipe with `Missing access token`. If `bws` is not installed, the shell says `command not found`. The project needs two keys. `GITHUB_APP_CLIENT_SECRET` is the client secret of the GitHub App: the login and the refresh of the GitHub token use it. `GITHUB_TOKEN` is a classic token with the scope `write:packages`, and only `image-publish` uses it. For the EU cloud, set `BWS_SERVER_URL=https://vault.bitwarden.eu`.

## Getting started

```shell
just msb setup         # 1. one time for each host
just msb image-build   # 2. one time, and after you change dev-tools/
just msb run           # 3. every day
```

| Step | Command | What it does |
|---|---|---|
| 1 | `setup` | Authorizes your SSH key for `msb ssh`. Installs the Remote-SSH extension. Changes the VS Code user settings. This includes `remote.SSH.configFile`, which points to `ssh_config`. |
| 2 | `image-build` | Builds `dev-tools/` with Docker (Debian, mise and the tools of `dev-tools/tools/`). Loads the image into msb. The first build takes several minutes. |
| 3 | `run` | Makes the VM from `sandbox.yaml` if none exists. Leaves the VM as it is if it runs and is current. Stops with a message if the VM is not current. Then you remove it with `just msb rm`. Waits for the boot. Opens VS Code on the VM. You can run it as often as you want. |

In VS Code, open a terminal and run `claude`. It starts with the login of the host, so it does not ask you to sign in.

Other recipes: `just msb shell` (a bash prompt in the VM), `just msb allow-host <host>` and `just msb rm` (`--volumes` also removes the Claude settings, the Terraform provider cache and the podman images).

## How it works

- **The recipes and the steps.** The justfile lists the steps of each recipe in order. Bash does the small jobs in the justfile: `msb` on the `PATH`, the SSH key, the name of a host, and the tags of the image. Bash also writes the VS Code settings. They are the variable `vscode_settings`, and `setup` merges them into your user settings with `jq`. Your other settings stay. `msb.py` has only what needs Python: `github-login`, `ensure-vm` and `wait-boot`. It is a `uv` script with no dependencies. `just msb run` runs it for you. You can also run a step alone, for example `.msb/msb.py wait-boot`, if the environment has `MSB_NAME`, `MSB_IMAGE` and `MSB_WORKSPACE`. Every function has a docstring. The helpers start with `_` and stand at the top of the file. The steps follow, in the order of the cases in `main()`.
- **One file.** `sandbox.yaml` declares the image, the size, the mounts, the secrets and the egress allow list. When `run` makes the VM, it stores a hash in the label `config-sha`. The hash covers the file, the image and the host values (the git directory and the git identity). If the hash is different at the next `run`, the VM is not current. msb fixes the config of a VM when it makes the VM. A VM that does not run is not current. msb does not run `sandbox-boot` when it starts a stopped VM, so the clone step and Headroom are missing. `run` does not remove a VM that is not current, because that removes the clone in it. `run` tells you to push your work and run `just msb rm && just msb run`. The volumes `claude-home`, `terraform-providers` and `podman-storage` stay.
- **The host values.** `sandbox.yaml` names four host values as `${NAME}`: `SANDBOX_GIT_DIR`, `SANDBOX_BRANCH`, `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL`. The step `ensure-vm` of `msb.py` reads them from git and puts them in the environment of `msb run`. These values change with the host. `sandbox.yaml` fixes the other settings: the path of the clone (`/home/agent/engineersdaybook`) and the URL of origin.
- **The clone.** The VM mounts only the `.git` directory of the host repo, at `/run/sandbox/source`. The VM cannot write to the mount. The VM cannot read your working tree, so it cannot read untracked files or `.env`. `dev-tools/sandbox-boot` clones the directory to `/home/agent/engineersdaybook`, on the branch of the host checkout. It sets `origin` to the GitHub URL. If the clone, the pre-commit hook or Headroom fails, `sandbox-boot` exits with an error. This stops the VM. Then `run` prints the boot log. Commit on the host before you run `run`, because the clone lacks uncommitted changes. Push a feature branch from the VM and open the pull request on GitHub. This also works for a git worktree.
- **The tokens.** The VM has only placeholders: `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN`. The host replaces `GH_TOKEN` in requests to `github.com`, `api.github.com` and `api.githubcopilot.com`, in Bearer auth and in Basic auth, so `git push` works. It replaces `CLAUDE_CODE_OAUTH_TOKEN` in requests to `api.anthropic.com`. The host blocks each token for every other host. `GH_TOKEN` is the token of the GitHub App (`_github_token()`). `CLAUDE_CODE_OAUTH_TOKEN` is the access token of your Claude login on the host (`_claude_token()`). The VM has no Claude login file, because the environment token comes before a stored login. The secret is `GH_TOKEN`, not `GITHUB_TOKEN`, because the Bitwarden key `GITHUB_TOKEN` is another token (for `ghcr.io`). With that name, `bws run` would give the wrong token to msb.
- **Allowed hosts.** The VM can reach only the hosts in `network.allow`. HTTPS rules need TLS interception, and `sandbox.yaml` turns it on. A blocked host fails at DNS. `*.example.com` matches subdomains at any depth. msb rejects `**.example.com` and an entry with a port. To add a host, run `just msb allow-host example.org`. This command changes `sandbox.yaml`. Then run `just msb rm && just msb run` to make the VM again. Commit the change.
- **Volumes.** The VM has three named volumes. `claude-home` keeps the settings, the history and the plugins of Claude Code (not a login). `terraform-providers` is the Terraform provider cache (`TF_PLUGIN_CACHE_DIR`). `podman-storage` has the images that podman pulls and builds. All three stay when you remove the VM, so a new VM keeps its settings and does not download the providers or the images again. `just msb rm --volumes` removes them. `sandbox-boot` gives the cache folder to the agent user.
- **Tools.** The files of `dev-tools/tools/` list the tools and their exact versions, in five groups: `runtimes`, `headroom`, `infra`, `dev` and `claude`. `dev-tools/mise.toml` has the settings of the tools and the completions task. The Dockerfile installs each group with mise in its own build stage. Claude Code is one of them. After you change a file, run `just msb image-build`, then `just msb rm && just msb run`. A new version in one file rebuilds only its stage. `image-publish` keeps the layers of each stage in the registry (the tag `cache`), so a new machine or a CI run rebuilds only the stage that changed.
- **The size of the image.** The image is 3.5 GiB. The step that installs the tools removes the uv cache (about 880 MiB), because no tool reads it. The largest parts are `headroom-ai` (842 MiB), Claude Code (280 MiB), node (204 MiB), Terraform (116 MiB) and Python (108 MiB).
- **Publishing the image (maintainer).** Run `just msb image-publish`. The token comes from the Bitwarden key `GITHUB_TOKEN` only: `bws run` gives it to the login command and to nothing else. The login goes to a temporary Docker config folder, which the recipe removes at the end. So no login stays on disk, and your `~/.docker/config.json` is not used or changed. The recipe pushes `ghcr.io/raghav19/engineersdaybook/dev-sbx`. The tags are the commit, `latest` (only on `main`) and the git tag of the commit (if it has one). The layers use zstd at level 9, as the sbx kits do. zstd unpacks about 9 times faster than gzip. It also makes the large layer 10% smaller. All files get one fixed timestamp, and the build adds no provenance and no SBOM. So the same files give the same digest. A timestamp from the last commit would give every layer a new digest after each commit, and no layer could be reused. The recipe stops if `dev-tools/` differs from the commit, because the tag is the commit. `sandbox.yaml` still uses the image that `just msb image-build` makes on your host.
- **Containers (podman).** The VM has rootless podman, for container builds and pushes. `docker` is an alias of podman (the `podman-docker` package), so `docker build`, `docker run` and `docker push` work. A container runs as the agent user: root in a container is uid 1000 of the VM. The image adds 242 MiB. Four settings make it work:
  - `sandbox-boot` gives the group `agent` access to `/dev/fuse` and `/dev/net/tun` (mode 660). These are device nodes of the VM, which its own kernel creates for root only. They are not devices of the host. fuse-overlayfs needs `/dev/fuse`, because the root file system of the VM is already an overlay file system. The network of a container needs `/dev/net/tun`. A container does not see these devices, unless you start it with `--device`.
  - `sandbox-boot` makes `/` a shared mount, which podman needs for mounts in rootless containers.
  - `/etc/containers/containers.conf.d/10-sandbox.conf` mounts `/etc/ssl/certs` (read-only) in each container. msb intercepts HTTPS and puts its CA in the trust store of the VM. Without this mount, a download over HTTPS in a container or a `RUN` step fails with "connection reset".
  - `sandbox.yaml` allows the Docker Hub hosts. The policy of the VM applies to a container too: a container cannot reach a host that is not in `network.allow`, with or without `--network=host`.

  Risks: the agent user can open the two devices. That exposes the FUSE and TUN code of the VM kernel to the agent, and `fusermount3` is setuid root. The VM boundary limits what a bug there can do. Podman has no `ghcr.io` login: pushing there needs a secret (see the section on Bitwarden). To push to a registry on the host, allow its port in `HOST_PORTS`.
- **MCP servers and the deny list.** `dev-tools/managed-settings.json` becomes `/etc/claude-code/managed-settings.json` in the VM. Root owns the file. The agent can read it and cannot change it. Project settings and user settings cannot override it. It declares draw.io, the Flux schema catalog and GitHub (`managedMcpServers`). It denies five GitHub tools (`merge_pull_request`, `delete_file` and others). The GitHub header has the placeholder `$MSB_GITHUB_TOKEN`. The host replaces it, so the file has no secret. Claude Code loads these servers without a prompt. `claude mcp remove` refuses to remove them. To change the file, run `just msb image-build`.
- **Secrets from Bitwarden.** To give the VM another secret, do three things. Add it under `secrets:` in `sandbox.yaml` with the hosts that can receive it. Add the hosts to `network.allow`. Add a key with the same name to the Bitwarden project. The recipe `run` starts only the step `ensure-vm` under `bws run`, so `code` and the other steps do not get the keys. msb reads the value of each secret from its environment, and it stops with a message when a variable is missing. The VM has a placeholder, and the host swaps in the value for those hosts only. The VM has no `bws`, no `msb` and no key. The `msb` process on the host holds all the keys of the project while the VM runs. A change to a Bitwarden secret reaches the VM when you make the VM again: `just msb rm && just msb run`.
- **Token refresh.** `ensure-vm` calls `_github_token()` and `_claude_token()`. `_github_token()` returns the saved access token if it has more than 30 minutes left. Otherwise it sends the refresh token and the client credentials to GitHub. It saves the new access token and the new refresh token. Each refresh makes the old refresh token useless. `_claude_token()` only reads the access token of the login on the host. It never refreshes it. `claude` on the host does that and rotates the refresh token. A second refresh from here would make the refresh token of `claude` useless. If the Claude token lasts less than 30 minutes, `run` stops and tells you to start `claude` on the host. If the VM runs and is current, `ensure-vm` gives it both tokens with `msb modify --secret`. The placeholders in the VM do not change, and the VM does not restart. There is no timer. After about 8 hours without `just msb run`, GitHub and Claude answer 401 to requests from the VM. Run `just msb run` again to fix this.
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
