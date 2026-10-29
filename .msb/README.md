# The dev sandbox on microsandbox

This sandbox is a VM for Claude Code and VS Code. It uses [microsandbox](https://docs.microsandbox.dev) (open source, Apache-2.0). It replaced the Docker sbx sandbox and has no daemon. One file, `sandbox.yaml`, declares the whole VM.

## What is different from sbx

| | sbx (tag `docker-sbx`) | microsandbox (`.msb/`) |
|---|---|---|
| Host service | sbx daemon (systemd unit) | none. `msb` starts the VM as a child process |
| Allowed hosts | policy kit, `sbx policy allow` and a kit rebuild | `network.allow` in `sandbox.yaml` |
| VS Code | `sbx setup ssh` | `ProxyCommand msb ssh serve` in `ssh_config`. The VM has no sshd |
| GitHub token | proxy replacement. The MCP gateway holds the OAuth token | proxy replacement only. The VM has a placeholder |
| Other secrets (Bitwarden) | `bws-secret.sh` and `secrets-sync` make an sbx custom secret | `bws run` puts the Bitwarden keys in the environment of one command. msb gives the VM a placeholder |
| MCP servers | registered on the gateway (`sbx mcp add`) | `managedMcpServers` in a root-owned file of the image |
| Tool filter for GitHub MCP | the gateway removes the tools | a deny list in the same file. The client enforces it. It is a soft limit (see "The limit of the deny list") |
| Claude login | the sbx proxy holds your login and adds it to requests | a long-lived token from `claude setup-token`, in Bitwarden. msb gives the VM a placeholder. You do not log in to Claude in the VM |
| Licence | proprietary | Apache-2.0, beta (v0.7) |

**Not ported yet:** the SPIRE agent (and Envoy) and the kind kubeconfig. The VM can already reach their ports on the host, and the Flux Operator web UI (host port 19090). The skills are in `.claude/skills` of the repository.

**Not ported, on purpose:**
- The egress rule on `api.github.com/repos/**` that blocks one HTTP method (the one that removes a repository). msb has rules for hosts only, not for methods or paths. The scope of the token is the limit.
- The policy kit, the MCP gateway and the git token sync. `network.allow`, the managed settings and the token placeholder do their work.
- `policy-context.md` (in the tag `docker-sbx`). It told the agent to use the sbx gateway tools. That text is wrong for msb. The agent instructions are in `AGENTS.md`.

## Prerequisites

1. **Install the tools.** You need [mise](https://mise.jdx.dev), VS Code (`code`), Docker (for the image build) and access to `/dev/kvm`.
   - `mise install` provides `msb`, `uv`, `bws` (the Bitwarden Secrets Manager CLI), `age` and `sops`.
   - You install `docker` and `code` yourself.
   - A recipe stops with a message if one of its tools is missing.

   ```shell
   mise trust && mise install
   eval "$(mise activate bash)"
   msb doctor        # each line must have a check mark
   ```

2. **Log in to GitHub with the GitHub App.** Run `just msb github-login`. This is the web flow of the app.
   - The step opens GitHub in your browser. You click Authorize.
   - GitHub sends the browser to port 8765 of this host (`http://127.0.0.1:8765/callback`). The step waits 5 minutes for you.
   - The client secret is the Bitwarden key `GITHUB_APP_CLIENT_SECRET` (prerequisite 6).
   - You installed the app on this repository only. It has the permissions contents, issues and pull requests. It has no Administration permission, so GitHub refuses a change to the settings of the repository.
   - In the settings of the app (Optional features), turn off "User-to-server token expiration". The token then has no refresh token and does not end by itself. You rotate it every 90 days ("Token lifetime").
   - The step saves the token to `~/.config/msb/github-app.json` (mode 600). Copy the access token to the Bitwarden key `GH_TOKEN` (prerequisite 6). Then delete the file.
   - There is no fallback to `gh`, because that token is broader.

3. **Have an SSH key** at `~/.ssh/id_ed25519` (`ssh-keygen -t ed25519`). `ssh_config` uses it.

4. **Commit your work.** The VM clones the committed files only.

5. **Make a Claude token.** Run `claude setup-token` on the host and sign in with your subscription. Copy the token to the Bitwarden key `CLAUDE_CODE_OAUTH_TOKEN` (prerequisite 6). The VM uses this token, so you do not log in to Claude in the VM. The login of `claude` on the host is a different token. It can refresh without breaking the VM.

6. **Set up Bitwarden.** `run`, `github-login` and `build` use `bws run`. It puts each key of the Bitwarden project in the environment of one command.
   - The Bitwarden access token is the one secret you keep on the host. Keep it encrypted, so that a process of your user cannot read it. Every recipe that needs Bitwarden (`run`, `build`, `github-login`) calls the step `bws-run` of `msb.py`. It asks for your passphrase, decrypts the token and starts `bws run`. Nothing stores the passphrase. You enter it once for each recipe.
   - Set it up once, in your own terminal (not in an agent session). `age -p` and `sops` need to be on the PATH (`mise install`).
     ```shell
     mkdir -p ~/.config/sops/age && cd ~/.config/sops/age
     rm -f keys.txt                     # a symlink or an old plain key. age would write through a symlink
     age-keygen 2>pub.txt | age -p -o keys.txt            # a new age key, encrypted with a passphrase you enter twice
     printf '{"BWS_ACCESS_TOKEN":"%s"}' "$(cat ~/.config/bws/access-token)" \
       | sops encrypt --age "$(awk '{print $3}' pub.txt)" --input-type json --output-type json /dev/stdin > ~/.config/bws/access-token.sops.json
     rm pub.txt ~/.config/bws/access-token                # the plain token
     ```
   - `keys.txt` is the default key file of sops, but here it holds an **encrypted** key. `msb.py` refuses to go on if it holds a plain key, because then any process of your user could decrypt the token. Other uses of `sops` with the default key file will not work with this file.
   - If `BWS_ACCESS_TOKEN` is set in the environment (for example in CI), `bws-run` uses it and does not ask. If neither exists, `bws` stops with `Missing access token`.
   - Run these commands from reviewed code. `msb.py` and the justfile run with your token, so check changes to them before you run them.
   - The project needs four keys. `GH_TOKEN` is the token of the GitHub App (prerequisite 2). `CLAUDE_CODE_OAUTH_TOKEN` is the Claude token (prerequisite 5). `GITHUB_APP_CLIENT_SECRET` is the client secret of the GitHub App, and `github-login` uses it. `GITHUB_TOKEN` is a classic token with the scope `write:packages`. `build` pushes the image with it, and `run` pulls the private image with it (`registry` in `sandbox.yaml`).
   - For the EU cloud, set `BWS_SERVER_URL=https://vault.bitwarden.eu`.

## Getting started

```shell
just msb setup         # 1. one time for each host
just msb build         # 2. one time, and after you change dev-tools/
just msb run           # 3. every day
```

| Step | Command | What it does |
|---|---|---|
| 1 | `setup` | Authorizes your SSH key for `msb ssh`. Installs the Remote-SSH extension. Writes the VS Code user settings, including `remote.SSH.configFile`, which points to `ssh_config`. |
| 2 | `build` | Builds `dev-tools/` with Docker (Debian, mise and the tools of `dev-tools/tools/`). Pushes the image to ghcr.io. Pins its digest in `sandbox.yaml`. Commit that change. The first build takes several minutes. |
| 3 | `run` | Makes the VM, or starts it, and gives it the new tokens. Runs `sandbox-boot` in it. Opens VS Code on it. You can run it as often as you want. |

In VS Code, open a terminal and run `claude`. It uses the token from Bitwarden, so it does not ask you to sign in.

Other recipes: `just msb shell` (a bash prompt in the VM), `just msb allow-host <host>` and `just msb rm`. `just msb rm --volumes` also removes the Claude settings, the Terraform provider cache and the podman images.

## How it works

### The recipes and the steps

- The justfile lists the steps of each recipe in order. Bash does the small jobs.
- Each recipe starts with the private recipe `_need`. It stops with a message if a tool of the recipe is not on the `PATH`.
- The top of the justfile has variables for the SSH key, the VS Code settings file, the VM user and the registry.
- `msb.py` has only what needs Python: `vscode-settings`, `github-login`, `ensure-vm` and `allow-host`. It is a `uv` script. Its one dependency is `ruamel.yaml`, and `uv` installs it on the first run.
- You can run a step alone, for example `.msb/msb.py ensure-vm`, if the environment has `MSB_NAME` and `MSB_WORKSPACE`.
- Every function has a docstring. The helpers start with `_` and stand at the top of the file. The steps follow, in the order of the cases in `main()`.

### The VM and its fingerprint

- `sandbox.yaml` declares the image, the size, the mounts, the secrets and the egress allow list.
- When `run` makes the VM, it stores a hash in the label `config-sha`. The hash covers the file (it pins the image by digest) and the host values (the git directory and the git identity).
- msb fixes the configuration of a VM when it makes the VM. If the hash is different at the next `run`, `run` stops with a message. It does not remove the VM, because that removes the clone in it.
- Then push your work and run `just msb rm && just msb run`. The volumes `claude-home`, `terraform-providers` and `podman-storage` stay.
- The VM has no command of its own. At each `run`, `ensure-vm` runs `dev-tools/sandbox-boot` in the VM with `msb exec`. This is the same for a new VM and for an old VM.
- Each step of the script does nothing if its work exists. It clones only if there is no clone. It starts Headroom only if Headroom does not answer.
- So the next `run` fixes a VM that you stopped, a boot that failed and a Headroom that stopped. The clone stays.
- If a step fails, the script prints the reason and `run` exits with 1. The VM keeps running.

### The host values

- `sandbox.yaml` names four host values as `${NAME}`: `SANDBOX_GIT_DIR`, `SANDBOX_BRANCH`, `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL`.
- The recipe `run` reads them from git with four `[env]` lines. These lines apply to `run` only.
- `ensure-vm` puts three of them in the fingerprint (not the branch). A new author name gives the VM another fingerprint.
- `sandbox.yaml` fixes the other settings: the path of the clone (`/home/agent/engineersdaybook`) and the URL of origin.

### The clone

- The VM mounts only the `.git` directory of the host repo, at `/run/sandbox/source`. The VM cannot write to the mount.
- The VM cannot read your working tree, so it cannot read untracked files or `.env`.
- `sandbox-boot` clones the directory to `/home/agent/engineersdaybook`, on the branch of the host checkout. It sets `origin` to the GitHub URL.
- The clone lacks uncommitted changes, so commit on the host before you run `run`.
- Push a feature branch from the VM and open the pull request on GitHub. A git worktree works too.

### The tokens

- The VM has only placeholders: `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN`.
- The host replaces `GH_TOKEN` in requests to `github.com`, `api.github.com` and `api.githubcopilot.com`. It does this in Bearer auth and in Basic auth, so `git push` works.
- The host replaces `CLAUDE_CODE_OAUTH_TOKEN` in requests to `api.anthropic.com`. The host blocks each token for every other host.
- `GH_TOKEN` is the token of the GitHub App. `CLAUDE_CODE_OAUTH_TOKEN` is the token of `claude setup-token`. Both are Bitwarden keys, and `bws run` puts them in the environment of `ensure-vm`.
- The VM has no Claude login file, because the environment token comes before a stored login.
- The secret is `GH_TOKEN`, not `GITHUB_TOKEN`, because the Bitwarden key `GITHUB_TOKEN` is another token (for `ghcr.io`). With that name, `bws run` would give the wrong token to msb.

### Token lifetime

- Neither token refreshes by itself. The GitHub App does not expire user tokens (prerequisite 2), and `claude setup-token` makes a long-lived token. Nothing runs on the host between two runs of `just msb run`.
- A token that does not expire is a risk: a leak stays valid until you revoke it. So rotate both tokens **every 90 days**.
- A workflow cannot rotate them. The GitHub App token needs your approval in a browser, and `claude setup-token` is interactive. The workflow `.github/workflows/msb-token-rotation.yaml` opens an issue with the steps on the 1st of January, April, July and October. It has no secret.
- To rotate: make the new token, change the Bitwarden key, revoke the old token, then run `msb stop sandbox-dev` and `just msb run`. msb reads a secret when the VM starts. A running VM does not read a changed secret. A VM that you stopped reads it again. The clone and the volumes stay.
- Revoke the old GitHub token alone. If you delete the app under Settings, Applications, Authorized GitHub Apps, GitHub revokes the new token too. Use that only for a leak.
- Why not a proxy like sbx: msb has no secret that refreshes, and the docs and the code give no hook for one. A new value reaches new connections only. A client that keeps a connection open, such as Headroom, keeps the old value until it restarts. See `docs/research/microsandbox-credential-injection.md`.

### Secrets from Bitwarden

To give the VM another secret, do three things:
1. Add it under `secrets:` in `sandbox.yaml` with the hosts that can receive it.
2. Add the hosts to `network.allow`.
3. Add a key with the same name to the Bitwarden project.

- `run` starts only the step `ensure-vm` under `bws run`, so `code` and the other steps do not get the keys.
- msb reads the value of each secret from its environment. It stops with a message when a variable is missing.
- The VM has a placeholder. The host swaps in the value for the hosts of that secret only.
- The VM has no `bws`, no `msb` and no key. The `msb` process on the host holds all the keys of the project while the VM runs.
- A running VM does not read a changed secret. Make the VM again (`just msb rm && just msb run`). A VM that you stopped reads the secrets again when `run` starts it.

### Allowed hosts

- The VM can reach only the hosts in `network.allow`. A blocked host fails at DNS.
- HTTPS rules need TLS interception, and `sandbox.yaml` turns it on.
- `*.example.com` matches subdomains at any depth. msb rejects `**.example.com` and an entry with a port.
- To add a host, run `just msb allow-host example.org`. It accepts a name or a wildcard and refuses anything else before it changes `sandbox.yaml`.
- Then run `just msb rm && just msb run`, because the VM keeps its old configuration. Commit the change.

### Ports of the host

- The VM can reach three ports of the host at `host.microsandbox.internal:<port>`. They are 6444 (the kind API server), 18081 (the SPIRE server) and 19090 (the Flux Operator web UI).
- `sandbox.yaml` cannot express a rule for a port, so `msb.py` passes one `--net-rule` for each (`HOST_PORTS`).
- The services are in the kind cluster. Nothing in the VM uses them yet, because the kubeconfig and the SPIRE agent are not ported.

### Volumes

- `claude-home` keeps the settings, the history and the plugins of Claude Code (not a login).
- `terraform-providers` is the Terraform provider cache (`TF_PLUGIN_CACHE_DIR`).
- `podman-storage` has the images that podman pulls and builds.
- All three stay when you remove the VM. A new VM keeps its settings and does not download the providers or the images again.
- `just msb rm --volumes` removes them. `sandbox-boot` gives the folders to the agent user.

### Tools and the image

- The files of `dev-tools/tools/` list the tools and their exact versions, in five groups: `runtimes`, `headroom`, `infra`, `dev` and `claude`.
- `dev-tools/mise.toml` has the settings of the tools and the completions task.
- The Dockerfile installs each group with mise in its own build stage. A new version in one file rebuilds only its stage.
- After you change a file, run `just msb build`. Commit the new digest in `sandbox.yaml`. Then run `just msb rm && just msb run`.
- The image is 3.5 GiB. The step that installs the tools removes the uv cache (about 880 MiB), because no tool reads it.
- The largest parts are `headroom-ai` (842 MiB), Claude Code (280 MiB), node (204 MiB), Terraform (116 MiB) and Python (108 MiB).

### Building and publishing the image

- Run `just msb build`. It pushes `ghcr.io/raghav19/engineersdaybook/dev-sbx`. The tag is the commit.
- Then it writes the digest of the pushed image in `sandbox.yaml` (`image.oci: ...@sha256:...`). The digest is the pin. The tag is only a label.
- A new digest gives the VM another fingerprint. The next `run` tells you to run `just msb rm && just msb run`.
- The package is private. `sandbox.yaml` has a `registry` block with `password_env: GITHUB_TOKEN`. `run` runs msb under `bws run`, so msb reads the token from the environment when it pulls the image. There is no login step. (`msb registry login` does not work in this msb build: it has no keyring.)
- The token is the Bitwarden key `GITHUB_TOKEN` only. `bws run` pipes it to `docker login`, so no variable holds it. `docker logout` removes the login at the end.
- If the build fails, the login stays in `~/.docker/config.json` until the next run of the recipe ends.
- The layers use zstd at level 9, as the sbx kits do. zstd unpacks about 9 times faster than gzip. It also makes the large layer 10% smaller.
- All files get one fixed timestamp, and the build adds no provenance and no SBOM. So the same files give the same digest. A timestamp from the last commit would give every layer a new digest after each commit.
- The layers of each stage go to the registry (the tag `cache`). A new machine or a CI run then rebuilds only the stage that changed.
- The first run prints the error `failed to configure registry cache importer ... not found`. The cache tag does not exist yet, and the build goes on.
- The recipe does not check `dev-tools/` for changes that you did not commit. Commit them first, because the tag is the commit.

### Containers (podman)

The VM has rootless podman, for container builds and pushes. `docker` is an alias of podman (the `podman-docker` package), so `docker build`, `docker run` and `docker push` work. A container runs as the agent user. Root in a container is uid 1000 of the VM. The image adds 242 MiB. Four settings make it work:
- `sandbox-boot` gives the group `agent` access to `/dev/fuse` and `/dev/net/tun` (mode 660). These are device nodes of the VM. Its own kernel creates them for root only. They are not devices of the host.
  - fuse-overlayfs needs `/dev/fuse`, because the root file system of the VM is already an overlay file system.
  - The network of a container needs `/dev/net/tun`.
  - A container does not see these devices, unless you start it with `--device`.
- `sandbox-boot` makes `/` a shared mount. Podman needs this for mounts in rootless containers.
- `/etc/containers/containers.conf.d/10-sandbox.conf` mounts `/etc/ssl/certs` (read-only) in each container. msb intercepts HTTPS and puts its CA in the trust store of the VM. Without this mount, a download over HTTPS in a container or a `RUN` step fails with "connection reset".
- `sandbox.yaml` allows the Docker Hub hosts. The policy of the VM applies to a container too. A container cannot reach a host that is not in `network.allow`, with or without `--network=host`.

Risks:
- The agent user can open the two devices. This exposes the FUSE and TUN code of the VM kernel to the agent, and `fusermount3` is setuid root. The VM boundary limits what a bug there can do.
- Podman has no `ghcr.io` login. To push there, the VM needs a secret (see "Secrets from Bitwarden").
- To push to a registry on the host, allow its port in `HOST_PORTS`.

### MCP servers and the deny list

- `dev-tools/managed-settings.json` becomes `/etc/claude-code/managed-settings.json` in the VM. Root owns the file. The agent can read it and cannot change it. Project settings and user settings cannot override it.
- The file declares draw.io, the Flux schema catalog and GitHub (`managedMcpServers`). It denies five GitHub tools (`merge_pull_request`, `delete_file` and others).
- The GitHub header has the placeholder `$MSB_GITHUB_TOKEN`. The host replaces it, so the file has no secret.
- Claude Code loads these servers without a prompt. `claude mcp remove` refuses to remove them.
- To change the file, run `just msb build`.

### The limit of the deny list

- The agent can still call the GitHub API with the placeholder token. The host then uses the token of the GitHub App.
- The deny list stops mistakes. The **scope of the token** sets what the agent can do on GitHub. The app has access to this repository only (prerequisite 2).

### Small items

- **Ponytail.** `sandbox-boot` installs the plugin ponytail 5.3.2 for Claude Code, as in sbx. The plugin is on the `claude-home` volume, so a new VM finds it. A failed install prints a warning and does not stop the script.
- **The shell.** The shell is plain bash. `/etc/profile.d` puts the mise shims on the `PATH` and sets `EDITOR`. Completions for the tools are available. There is no prompt theme and no fzf.
- **Git identity.** `sandbox.yaml` sets `GIT_AUTHOR_*` and `GIT_COMMITTER_*` from your host git config. The image has the token helper and `safe.directory` in its system git config.
- **VS Code.** The VM has no sshd. The `msb` command on the host is the SSH server, and `ssh_config` starts it as a `ProxyCommand`. The VM must run before VS Code connects. `run` makes sure of this.

## When something fails

| You see | Do this |
|---|---|
| `run` cannot pull the image (`not found` or `unauthorized`) | `not found`: `sandbox.yaml` does not pin an image that exists. Run `just msb build`. `unauthorized`: the Bitwarden key `GITHUB_TOKEN` needs the scope `read:packages` (it has `write:packages` for `build`). |
| `msb doctor` shows a red line | Read the line. For `/dev/kvm`, run `sudo usermod -aG kvm "$USER"`, then log in again. |
| `run` says that `sandbox-boot` failed | `run` prints the reason (`sandbox-boot: ...`). The clone, the hook or Headroom failed. Run `just msb run` again. This fixes a cause outside the VM, such as the network. If the cause is in `sandbox.yaml`, the image or a host value (for example the branch that the VM stores), run `just msb rm && just msb run`. |
| `msb ls` shows `crashed` or `stopped` | Run `just msb run`. It starts the VM and runs `sandbox-boot` again. The clone stays. If `run` still fails and the clone has work, push the work first. Then run `just msb rm && just msb run`. |
| `run` says that the VM does not match the configuration | `sandbox.yaml` (it pins the image) or a host value changed. Push the work in the clone (`just msb shell`). Then run `just msb rm && just msb run`. |
| A site fails in the VM | The site is not in `network.allow`. Run `just msb allow-host <host>`. |
| VS Code cannot connect | Run `just msb setup` again. Check that `msb ls` shows the VM as `running`. Close the VS Code window. Open it again with `run`. |
| `claude` says the token is revoked or invalid (401) | The Bitwarden key `CLAUDE_CODE_OAUTH_TOKEN` is wrong, revoked or old. Make a new one with `claude setup-token` and update the key. Then run `msb stop sandbox-dev` and `just msb run`. |
| You want a clean start | Run `just msb rm --volumes`, then `just msb run`. |

More commands: `msb ls` (state), `msb logs sandbox-dev`, `msb inspect sandbox-dev` (the settings and the `config-sha` label) and `msb <command> --help`.
