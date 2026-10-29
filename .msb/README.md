# The dev sandbox on microsandbox

This sandbox is a VM for Claude Code and VS Code. It uses [microsandbox](https://docs.microsandbox.dev) (open source, Apache-2.0, beta v0.7). It replaced the Docker sbx sandbox (tag `docker-sbx`) and has no daemon. One file, `sandbox.yaml`, declares the VM.

## What is different from sbx

| | sbx | microsandbox |
|---|---|---|
| Host service | sbx daemon | none. `msb` starts the VM as a child process |
| Allowed hosts | policy kit | `network.allow` in `sandbox.yaml` |
| VS Code | `sbx setup ssh` | `ProxyCommand msb ssh serve` in `ssh_config`. The VM has no sshd |
| Secrets | the sbx proxy holds them | the VM has placeholders. The host replaces them (see "The tokens") |
| Claude login | the proxy holds your login | a long-lived token from `claude setup-token` |
| MCP servers | registered on the gateway | `managedMcpServers` in a root-owned file of the image |
| GitHub MCP tool filter | the gateway removes the tools | a deny list in that file. The client enforces it (see "MCP servers and the deny list") |

**Not ported yet:** the SPIRE agent, Envoy and the kind kubeconfig. The VM can reach their ports on the host (see "Ports of the host").

**Not ported, on purpose:**
- The rule that blocks one HTTP method on `api.github.com/repos/**`. msb has rules for hosts only. The scope of the token is the limit.
- The policy kit, the MCP gateway and the git token sync. `network.allow`, the managed settings and the placeholders replace them.
- `policy-context.md` (in the tag `docker-sbx`). It names the sbx gateway tools, which do not exist here. `AGENTS.md` has the agent instructions.

## Prerequisites

1. **Install the tools.** You need [mise](https://mise.jdx.dev), VS Code (`code`), Docker (for the image build) and access to `/dev/kvm`.
   - `mise install` provides `msb`, `uv`, `bws` (the Bitwarden Secrets Manager CLI) and `age`.
   - You install `docker` and `code` yourself.
   - A recipe stops with a message if a tool is missing.

   ```shell
   mise trust && mise install
   eval "$(mise activate bash)"
   msb doctor        # each line must have a check mark
   ```

2. **Have an SSH key** at `~/.ssh/id_ed25519` (`ssh-keygen -t ed25519`). `ssh_config` uses it.

3. **Commit your work.** The VM clones the committed files only.

4. **Set up Bitwarden.** The recipes `run`, `build` and `github-login` use `bws run`. It puts each key of the Bitwarden project in the environment of one command. The project needs four keys:

   | Key | Value |
   |---|---|
   | `GH_TOKEN` | the token of the GitHub App (prerequisite 5) |
   | `CLAUDE_CODE_OAUTH_TOKEN` | the Claude token (prerequisite 6) |
   | `GITHUB_APP_CLIENT_SECRET` | the client secret of the GitHub App. `github-login` uses it |
   | `GITHUB_TOKEN` | a classic token with the scope `write:packages`. `build` pushes the image with it. `run` pulls the image with it |

   You keep one secret on the host: the Bitwarden access token. Encrypt it once with a passphrase. Use your own terminal, not an agent session:

   ```shell
   mkdir -p ~/.config/bws
   ( read -rsp 'Bitwarden access token: ' token && echo && printf %s "$token" | age -p -o ~/.config/bws/access-token.age )
   chmod 600 ~/.config/bws/access-token.age
   ```

   - The command asks for the token (not shown). Then `age -p` asks for a new passphrase. The subshell keeps the token out of your shell.
   - The passphrase is the only protection, because anyone can try guesses on the file. Use a long one. If you leave it empty, `age` makes one and shows it once. Save it.
   - Remove any plain copy, such as `~/.config/bws/access-token`. To change the token or the passphrase, run the commands again.
   - Each recipe that needs Bitwarden asks for the passphrase (see the variable `bws` in `.msb/justfile`). Nothing stores it.
   - If the environment has `BWS_ACCESS_TOKEN` (for example in CI), the recipes use it and do not ask.
   - Change `msb.py` and the justfile only through reviewed code. They run with your token.
   - For the EU cloud, set `BWS_SERVER_URL=https://vault.bitwarden.eu`.

5. **Make the GitHub token.** Run `just msb github-login`.
   - First, open the settings of the GitHub App (Optional features). Turn off "User-to-server token expiration". The token then does not end by itself.
   - The step opens GitHub in your browser. Click Authorize. GitHub sends the browser to `http://127.0.0.1:8765/callback`. The step waits 5 minutes.
   - The step saves the token to `~/.config/msb/github-app.json` (mode 600). Copy the access token to the Bitwarden key `GH_TOKEN`. Then remove the file.
   - You installed the app on this repository only. It has the permissions contents, issues and pull requests. It has no Administration permission.
   - There is no fallback to `gh`, because that token is broader.

6. **Make the Claude token.** Run `claude setup-token` on the host and sign in with your subscription. Copy the token to the Bitwarden key `CLAUDE_CODE_OAUTH_TOKEN`. You do not log in to Claude in the VM. This token is not the login of `claude` on the host, so a refresh on the host does not break the VM.

## Getting started

```shell
just msb setup         # 1. one time for each host
just msb build         # 2. one time, and after you change dev-tools/
just msb run           # 3. every day
```

| Step | Command | What it does |
|---|---|---|
| 1 | `setup` | Authorizes your SSH key for `msb ssh`. Installs the Remote-SSH extension. Writes the VS Code user settings, including `remote.SSH.configFile`. |
| 2 | `build` | Builds `dev-tools/` with Docker and pushes the image to ghcr.io. Pins its digest in `sandbox.yaml`. Commit that change. The first build takes several minutes. |
| 3 | `run` | Makes the VM, or starts it. Runs `sandbox-boot` in it. Opens VS Code on it. You can run it as often as you want. |

In a VS Code terminal, run `claude`. It uses the token from Bitwarden and does not ask you to sign in.

Other recipes: `just msb shell` (a bash prompt in the VM), `just msb allow-host <host>` and `just msb rm`. `just msb rm --volumes` also removes the volumes (see "Volumes").

## How it works

### The recipes

- The justfile lists the steps of each recipe in order. The private recipe `_need` stops a recipe with a message if a tool is not on the `PATH`.
- `msb.py` has the steps that need Python: `vscode-settings`, `github-login`, `ensure-vm` and `allow-host`. It is a `uv` script. `uv` installs its one dependency, `ruamel.yaml`, on the first run.
- To run a step alone, for example `.msb/msb.py ensure-vm`, set `MSB_NAME` and `MSB_WORKSPACE`.

### The VM and its fingerprint

- `sandbox.yaml` declares the image, the size, the mounts, the secrets and the egress allow list.
- It names four host values as `${NAME}`: `SANDBOX_GIT_DIR`, `SANDBOX_BRANCH`, `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL`. `run` reads them from git.
- When `run` makes the VM, it stores a hash in the label `config-sha`. The hash covers `sandbox.yaml` (it pins the image by digest) and the host values, except the branch.
- msb keeps the configuration from the time it made the VM. If the hash differs at the next `run`, `run` stops. It does not remove the VM, because that removes the clone.
- To get the new configuration, push your work. Then run `just msb rm && just msb run`. The volumes stay.
- At each `run`, `ensure-vm` runs `dev-tools/sandbox-boot` in the VM. A step of the script does nothing if its work exists. So `run` also repairs a stopped VM, a failed boot and a stopped Headroom. The clone stays.
- If a step fails, `run` prints the reason and exits with 1. The VM keeps running.

### The clone

- The VM mounts the `.git` directory of the host repo at `/run/sandbox/source`. It cannot write to the mount. It cannot read your working tree, untracked files or `.env`.
- `sandbox-boot` clones it to `/home/agent/engineersdaybook`, on the branch of the host checkout. `origin` is the GitHub URL.
- The clone lacks uncommitted changes. Commit on the host before you run `run`.
- Push a feature branch from the VM. Open the pull request on GitHub.

### The tokens

- The VM has placeholders only: `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN`.
- The host replaces `GH_TOKEN` in requests to `github.com`, `api.github.com` and `api.githubcopilot.com`. It does this in Bearer and Basic auth, so `git push` works.
- The host replaces `CLAUDE_CODE_OAUTH_TOKEN` in requests to `api.anthropic.com`. It blocks each token for every other host.
- Both tokens are Bitwarden keys. `bws run` puts them in the environment of `ensure-vm`, and msb reads them when it starts the VM.
- The VM has no Claude login file, because the environment token comes before a stored login.
- The secret is `GH_TOKEN`, not `GITHUB_TOKEN`, because the Bitwarden key `GITHUB_TOKEN` is another token (for `ghcr.io`).

### Token lifetime

- Neither token refreshes. The GitHub token has no expiry (prerequisite 5), and the Claude token is long-lived. Nothing runs on the host between two runs.
- A token without expiry stays valid until you revoke it. The GitHub token reaches this repository only. A rotation schedule is not decided yet.
- To change a token, make the new token and change the Bitwarden key. Revoke the old token. Run `msb stop sandbox-dev`, then `just msb run`.
- A running VM does not read a changed secret. A stopped VM reads it again.
- Revoke the old GitHub token alone. If you remove the app under Settings, Applications, Authorized GitHub Apps, GitHub also revokes the new token. Do that only for a leak.
- msb has no secret that refreshes. A new value reaches new connections only, so a client with an open connection (such as Headroom) keeps the old value. See `docs/research/microsandbox-credential-injection.md`.

### Add a secret

1. Add it under `secrets:` in `sandbox.yaml` with the hosts that can receive it.
2. Add those hosts to `network.allow`.
3. Add a key with the same name to the Bitwarden project.
4. Run `just msb rm && just msb run`. The change of `sandbox.yaml` needs a new VM.

- `run` starts only `ensure-vm` under `bws run`, so `code` and the other steps do not get the keys.
- msb stops with a message if a variable is missing.
- The VM has no `bws`, no `msb` and no key. The `msb` process on the host holds all the keys of the project while the VM runs.

### Allowed hosts

- The VM can reach only the hosts in `network.allow`. A blocked host fails at DNS.
- HTTPS rules need TLS interception. `sandbox.yaml` turns it on.
- `*.example.com` matches subdomains at any depth. msb rejects `**.example.com` and an entry with a port.
- To add a host, run `just msb allow-host example.org`. It refuses anything that is not a name or a wildcard.
- Then run `just msb rm && just msb run`, because the VM keeps its old configuration. Commit the change.

### Ports of the host

- The VM can reach three ports of the host at `host.microsandbox.internal:<port>`. They are 6444 (the kind API server), 18081 (the SPIRE server) and 19090 (the Flux Operator web UI).
- `sandbox.yaml` cannot express a rule for a port, so `msb.py` passes one `--net-rule` for each (`HOST_PORTS`).
- Nothing in the VM uses them yet, because the kubeconfig and the SPIRE agent are not ported.

### Headroom dashboard

- `sandbox.yaml` publishes the Headroom proxy of the VM (port 8787) on the loopback of the host (`network.ports`). Open `http://127.0.0.1:8787/dashboard`. `/stats` and `/health` work too.
- Host port 8787 must be free, or `just msb run` fails. To use another port, change the host side of the mapping (`127.0.0.1:8788:8787`).
- Headroom has no login. Only the host can reach the port, but any user of the host can.
- An existing VM does not have the port. Run `just msb rm && just msb run` once.

### Volumes

- `claude-home` keeps the settings, the history and the plugins of Claude Code (not a login).
- `terraform-providers` is the Terraform provider cache. `podman-storage` has the images that podman pulls and builds.
- The volumes stay when you remove the VM. A new VM does not download the providers or the images again.
- `just msb rm --volumes` removes them. `sandbox-boot` gives the folders to the agent user.

### Tools and the image

- The files of `dev-tools/tools/` list the tools and their exact versions in five groups: `runtimes`, `headroom`, `infra`, `dev` and `claude`. `dev-tools/mise.toml` has their settings.
- The Dockerfile installs each group in its own build stage. A new version in one file rebuilds only its stage.
- After you change a file, commit it. Run `just msb build`, because the image tag is the commit. Commit the new digest in `sandbox.yaml`. Then run `just msb rm && just msb run`.
- `build` pushes `ghcr.io/raghav19/engineersdaybook/dev-sbx` and writes its digest in `sandbox.yaml` (`image.oci: ...@sha256:...`). The digest is the pin. The tag is a label.
- The package is private. `sandbox.yaml` has a `registry` block with `password_env: GITHUB_TOKEN`, so msb pulls the image with the token from the environment. (`msb registry login` does not work in this msb build, which has no keyring.)
- `build` pipes `GITHUB_TOKEN` to `docker login` and runs `docker logout` at the end. If the build fails, the login stays in `~/.docker/config.json` until the next run ends.
- The same files give the same digest. The build gives every file the same timestamp and adds no provenance and no SBOM.
- The layers use zstd level 9, which unpacks about 9 times faster than gzip. The layers of each stage go to the registry (the tag `cache`).
- The first build prints `failed to configure registry cache importer ... not found`. The cache tag does not exist yet, and the build goes on.
- The image is 3.5 GiB. The largest part is `headroom-ai` (842 MiB).

### Containers (podman)

The VM has rootless podman. `docker` is an alias of podman, so `docker build`, `docker run` and `docker push` work. A container runs as the agent user. Four settings make it work:
- `sandbox-boot` gives the group `agent` access to `/dev/fuse` and `/dev/net/tun` (mode 660). The VM kernel makes them for root only, and they are not devices of the host. fuse-overlayfs needs `/dev/fuse`. The network of a container needs `/dev/net/tun`. A container sees them only with `--device`.
- `sandbox-boot` makes `/` a shared mount. Podman needs this for mounts in rootless containers.
- `/etc/containers/containers.conf.d/10-sandbox.conf` mounts `/etc/ssl/certs` (read-only) in each container. msb intercepts HTTPS and puts its CA in the trust store of the VM. Without the mount, an HTTPS download in a container fails with "connection reset".
- `sandbox.yaml` allows the Docker Hub hosts. The policy of the VM applies to a container too, with or without `--network=host`.

Risks:
- The agent user can open the two devices. This exposes the FUSE and TUN code of the VM kernel, and `fusermount3` is setuid root. The VM boundary limits what a bug there can do.
- Podman has no `ghcr.io` login. To push there, the VM needs a secret (see "Add a secret").
- To push to a registry on the host, allow its port in `HOST_PORTS`.

### MCP servers and the deny list

- `dev-tools/managed-settings.json` becomes `/etc/claude-code/managed-settings.json` in the VM. Root owns it. The agent can read it and cannot change it. Project and user settings cannot override it.
- The file declares draw.io, the Flux schema catalog and GitHub (`managedMcpServers`). It denies five GitHub tools (`merge_pull_request`, `delete_file` and others).
- The GitHub header has the placeholder `$MSB_GITHUB_TOKEN`. The host replaces it, so the file has no secret.
- Claude Code loads these servers without a prompt. `claude mcp remove` refuses to remove them. To change the file, run `just msb build`.
- The deny list stops mistakes only. The agent can still call the GitHub API with the placeholder token, and the host then uses the GitHub App token. The **scope of the token** sets what the agent can do. The app reaches this repository only (prerequisite 5).

### Small items

- **Ponytail.** `sandbox-boot` installs the plugin ponytail 5.3.2 for Claude Code. It is on the `claude-home` volume. A failed install prints a warning and does not stop the script.
- **The shell.** The shell is plain bash. `/etc/profile.d` puts the mise shims on the `PATH` and sets `EDITOR`. There is no prompt theme and no fzf.
- **Git identity.** `sandbox.yaml` sets `GIT_AUTHOR_*` and `GIT_COMMITTER_*` from your host git config.
- **VS Code.** The VM has no sshd. The `msb` command on the host is the SSH server, and `ssh_config` starts it as a `ProxyCommand`. The VM must run before VS Code connects. `run` makes sure of this.

## When something fails

| You see | Do this |
|---|---|
| `secret GH_TOKEN: host environment variable GH_TOKEN is not set` (or another key) | `bws run` did not give that key. Check that the key exists in the Bitwarden project and that your machine account can read the project. |
| `age: error: incorrect passphrase`, then `Missing access token` | You entered the wrong passphrase. Run the recipe again. |
| `run` cannot pull the image (`not found` or `unauthorized`) | `not found`: `sandbox.yaml` does not pin an image that exists. Run `just msb build`. `unauthorized`: the Bitwarden key `GITHUB_TOKEN` needs the scope `read:packages`. |
| `msb doctor` shows a red line | Read the line. For `/dev/kvm`, run `sudo usermod -aG kvm "$USER"`, then log in again. |
| `run` says that `sandbox-boot` failed | `run` prints the reason. Run `just msb run` again. This repairs a cause outside the VM, such as the network. If the cause is in `sandbox.yaml`, the image or a host value, run `just msb rm && just msb run`. |
| `msb ls` shows `crashed` or `stopped` | Run `just msb run`. The clone stays. If `run` still fails and the clone has work, push the work first. Then run `just msb rm && just msb run`. |
| `run` says that the VM does not match the configuration | `sandbox.yaml` or a host value changed. Push the work in the clone (`just msb shell`). Then run `just msb rm && just msb run`. |
| A site fails in the VM | The site is not in `network.allow`. Run `just msb allow-host <host>`. |
| VS Code cannot connect | Run `just msb setup` again. Check that `msb ls` shows the VM as `running`. Close the VS Code window. Open it again with `run`. |
| `claude` says the token is revoked or not valid (401) | The Bitwarden key `CLAUDE_CODE_OAUTH_TOKEN` has a wrong or old token, or you revoked it. Make a new token with `claude setup-token` and change the key. Run `msb stop sandbox-dev`, then `just msb run`. |
| You want a clean start | Run `just msb rm --volumes`, then `just msb run`. |

More commands: `msb ls` (state), `msb logs sandbox-dev`, `msb inspect sandbox-dev` (the settings and the `config-sha` label) and `msb <command> --help`.
