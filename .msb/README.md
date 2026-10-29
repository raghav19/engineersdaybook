# The dev sandbox on microsandbox

This sandbox is a VM for Claude Code and VS Code. It uses [microsandbox](https://docs.microsandbox.dev) (open source, Apache-2.0, beta v0.7). It replaced the Docker sbx sandbox (tag `docker-sbx`). One file, `sandbox.yaml`, declares the VM.

The VM holds no secrets, only placeholders. The host replaces a placeholder with the real value when the VM calls an allowed host. The "Decision records" at the end explain why the sandbox works this way.

**Not ported yet:** the SPIRE agent, Envoy and the kind kubeconfig.

## Prerequisites

1. **Install the tools.** You need [mise](https://mise.jdx.dev), VS Code (`code`), Docker (for the image build) and access to `/dev/kvm`.
   - Run the commands in the root of the repository. `mise install` provides `just`, `msb`, `uv`, `bws` (the Bitwarden Secrets Manager CLI), `age`, `jq` and `yq`.
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

   - The command asks for the token (not shown). Then `age -p` asks for a new passphrase. Use a long one.
   - Remove any plain copy, such as `~/.config/bws/access-token`. To change the token or the passphrase, run the commands again.
   - Each recipe that needs Bitwarden asks for the passphrase. Nothing stores it.
   - If the environment has `BWS_ACCESS_TOKEN` (for example in CI), the recipes use it and do not ask.
   - For the EU cloud, set `BWS_SERVER_URL=https://vault.bitwarden.eu`.

5. **Make the GitHub token.** Run `just msb github-login`.
   - First, open the settings of the GitHub App (Optional features). Turn off "User-to-server token expiration".
   - The step opens GitHub in your browser. Click Authorize. GitHub sends the browser to `http://127.0.0.1:8765/callback`. The step waits 5 minutes.
   - The step saves the token to `~/.config/msb/github-app.json` (mode 600). Copy the access token to the Bitwarden key `GH_TOKEN`. Then remove the file.
   - You installed the app on this repository only. It has the permissions contents, issues and pull requests.

6. **Make the Claude token.** Run `claude setup-token` on the host and sign in with your subscription. Copy the token to the Bitwarden key `CLAUDE_CODE_OAUTH_TOKEN`. You do not log in to Claude in the VM.

## Getting started

```shell
just msb setup         # 1. one time for each host
just msb build         # 2. one time, and after you change dev-tools/
just msb run           # 3. every day
```

| Step | Command | What it does |
|---|---|---|
| 1 | `setup` | Authorizes your SSH key for `msb ssh`. Installs the Remote-SSH extension. Writes the VS Code user settings, including `remote.SSH.configFile`. Your `settings.json` must have no comments, because the step cannot read them. |
| 2 | `build` | Builds `dev-tools/` with Docker and pushes the image to ghcr.io. Pins its digest in `sandbox.yaml`. Commit that change. The first build takes several minutes. |
| 3 | `run` | Makes the VM, or starts it. Runs `sandbox-boot` in it. Opens VS Code on it. You can run it as often as you want. |

In a VS Code terminal, run `claude`. It uses the token from Bitwarden and does not ask you to sign in.

## Daily use

| You want to | Run |
|---|---|
| Start or repair the VM | `just msb run` |
| Open a bash prompt in the VM | `just msb shell` |
| Allow one more host | `just msb allow-host example.org`, then `just msb rm && just msb run`, then commit |
| Change a token | Change the Bitwarden key, revoke the old token, then `msb stop sandbox-dev` and `just msb run` |
| Add another secret | Add it under `secrets:` in `sandbox.yaml`, add its hosts to `network.allow`, add a Bitwarden key with the same name, then `just msb rm && just msb run` |
| Change a tool of the image | Edit a file in `dev-tools/`, commit, `just msb build`, commit the new digest, then `just msb rm && just msb run` |
| Remove the VM | `just msb rm`. Add `--volumes` to remove the volumes too |

More commands: `msb ls` (state), `msb logs sandbox-dev`, `msb inspect sandbox-dev` and `msb <command> --help`.

## How it works

- **The clone.** The VM mounts the `.git` directory of the host repo at `/run/sandbox/source`. It cannot write to the mount. It cannot read your working tree, untracked files or `.env`. `sandbox-boot` clones it to `/home/agent/engineersdaybook`, on the branch of the host checkout. Commit on the host before `run`. Push a feature branch from the VM and open the pull request on GitHub.
- **The fingerprint.** `run` stores a hash in the label `config-sha`. It covers `sandbox.yaml` and the host values `SANDBOX_GIT_DIR`, `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL` (`run` reads them from git). If the hash differs at the next `run`, `run` stops and keeps the VM. Push your work, then run `just msb rm && just msb run`. The volumes stay.
- **The boot.** At each `run`, `ensure-vm` runs `dev-tools/sandbox-boot` in the VM. A step of the script does nothing if its work exists. So `run` also repairs a stopped VM, a failed boot and a stopped Headroom. If a step fails, `run` prints the reason and exits with 1. The VM keeps running.
- **The tokens.** The VM has the placeholders `GH_TOKEN` and `CLAUDE_CODE_OAUTH_TOKEN`. The host replaces `GH_TOKEN` in requests to `github.com`, `api.github.com` and `api.githubcopilot.com` (Bearer and Basic auth, so `git push` works). It replaces `CLAUDE_CODE_OAUTH_TOKEN` in requests to `api.anthropic.com`. It blocks each token for every other host. `bws run` puts both in the environment of `ensure-vm`, and msb reads them when it starts the VM. A running VM does not read a changed secret.
- **Allowed hosts.** The VM reaches only the hosts in `network.allow`. A blocked host fails at DNS. `*.example.com` matches subdomains at any depth. msb rejects `**.example.com` and an entry with a port.
- **Ports of the host.** The VM reaches three ports of the host at `host.microsandbox.internal:<port>`: 6444 (the kind API server), 18081 (the SPIRE server) and 19090 (the Flux Operator web UI). `msb.py` passes one `--net-rule` for each (`HOST_PORTS`). Nothing in the VM uses them yet.
- **Headroom dashboard.** Open `http://127.0.0.1:8787/dashboard` (`/stats` and `/health` work too). Host port 8787 must be free, or `just msb run` fails. To use another port, change `network.ports` in `sandbox.yaml` (`127.0.0.1:8788:8787`). Headroom has no login, so any user of the host can open it. An existing VM needs `just msb rm && just msb run` once.
- **Volumes.** `claude-home` keeps the settings, the history and the plugins of Claude Code (not a login). `terraform-providers` is the Terraform provider cache. `podman-storage` has the images that podman pulls and builds. They stay when you remove the VM.
- **The image.** The files of `dev-tools/tools/` list the tools and their exact versions in five groups: `runtimes`, `headroom`, `infra`, `dev` and `claude`. `build` pushes `ghcr.io/raghav19/engineersdaybook/dev-sbx`, tagged with the commit, and writes the digest in `sandbox.yaml` (`image.oci: ...@sha256:...`). The package is private. `sandbox.yaml` has a `registry` block with `password_env: GITHUB_TOKEN`, so `run` pulls with the token from Bitwarden. The first `build` prints `failed to configure registry cache importer ... not found`. The build goes on.
- **MCP servers.** `dev-tools/managed-settings.json` becomes `/etc/claude-code/managed-settings.json` in the VM. Root owns it, and project and user settings cannot override it. It declares draw.io, the Flux schema catalog and GitHub. It denies five GitHub tools (`merge_pull_request`, `delete_file` and others). To change it, run `just msb build`.
- **Podman.** The VM has rootless podman. `docker` is an alias of podman. `sandbox-boot` gives the group `agent` access to `/dev/fuse` and `/dev/net/tun`, makes `/` a shared mount, and `/etc/containers/containers.conf.d/10-sandbox.conf` mounts `/etc/ssl/certs` in each container. The policy of the VM applies to a container too. To push to a registry on the host, allow its port in `HOST_PORTS`.
- **The recipes.** The justfile lists the steps of each recipe in order. `_need` stops a recipe if a tool is not on the `PATH`. `msb.py` has the steps that need Python (`vscode-settings`, `github-login`, `ensure-vm`, `allow-host`). It is a `uv` script. On the first run, `uv` installs Python 3.13 and the one dependency, `ruamel.yaml` (this needs the network).
- **Small items.** `sandbox-boot` installs the plugin ponytail 5.3.2. The shell is plain bash. `sandbox.yaml` sets the git identity from your host git config. The VM has no sshd: `ssh_config` starts `msb ssh serve` as a `ProxyCommand`, so the VM must run before VS Code connects. `ssh_config` expects `msb` in the default mise data directory (`~/.local/share/mise`).

## When something fails

| You see | Do this |
|---|---|
| `secret GH_TOKEN: host environment variable GH_TOKEN is not set` (or another key) | `bws run` did not give that key. Check that the key exists in the Bitwarden project and that your machine account can read the project. |
| `age: error: incorrect passphrase`, then `Missing access token` | You entered the wrong passphrase. Run the recipe again. |
| `age: error: failed to open input file`, then `Missing access token` | The encrypted token file does not exist. Do prerequisite 4. |
| `run` cannot pull the image (`not found` or `unauthorized`) | `not found`: `sandbox.yaml` does not pin an image that exists. Run `just msb build`. `unauthorized`: the Bitwarden key `GITHUB_TOKEN` needs the scope `read:packages`. |
| `msb doctor` shows a red line | Read the line. For `/dev/kvm`, run `sudo usermod -aG kvm "$USER"`, then log in again. |
| `run` says that `sandbox-boot` failed | `run` prints the reason. Run `just msb run` again. This repairs a cause outside the VM, such as the network. If the cause is in `sandbox.yaml`, the image or a host value, run `just msb rm && just msb run`. |
| `msb ls` shows `crashed` or `stopped` | Run `just msb run`. The clone stays. If `run` still fails and the clone has work, push the work first. Then run `just msb rm && just msb run`. |
| `run` says that the VM does not match the configuration | `sandbox.yaml` or a host value changed. Push the work in the clone (`just msb shell`). Then run `just msb rm && just msb run`. |
| A site fails in the VM | The site is not in `network.allow`. Run `just msb allow-host <host>`. |
| VS Code cannot connect | Run `just msb setup` again. Check that `msb ls` shows the VM as `running`. Close the VS Code window. Open it again with `run`. |
| `claude` says the token is revoked or not valid (401) | The Bitwarden key `CLAUDE_CODE_OAUTH_TOKEN` has a wrong or old token, or you revoked it. Make a new token with `claude setup-token` and change the key. Run `msb stop sandbox-dev`, then `just msb run`. |
| You want a clean start | Run `just msb rm --volumes`, then `just msb run`. |

## Decision records

Each record says what we decided, why, and what it costs. Newer records go at the end.

### 1. Use microsandbox, not Docker sbx

- **Decision.** The dev sandbox is a microsandbox VM. The sbx version stays in the tag `docker-sbx`.
- **Why.** microsandbox is open source (Apache-2.0). It needs no daemon, because `msb` starts the VM as a child process. One file, `sandbox.yaml`, declares the VM, the allowed hosts and the secrets.
- **Cost.** microsandbox is beta. It has host rules only, so it cannot block one HTTP method on `api.github.com` (sbx did). The scope of the GitHub token is the limit. We did not port the policy kit, the MCP gateway or the git token sync. `network.allow`, the managed settings and the placeholders replace them.

### 2. The VM holds placeholders, not secrets

- **Decision.** The VM gets a placeholder for each secret. The host replaces it with the real value in requests to the hosts listed for that secret.
- **Why.** A process in the VM, such as an agent, cannot read or leak a value that the VM never has. The host also blocks a token for every other host.
- **Cost.** The VM can still use a token by calling an allowed host. The scope of the token limits the damage. While the VM runs, the host `msb` process holds all the project keys in its environment, and a process of your user can read them. Run agents in the VM.

### 3. Long-lived tokens in Bitwarden, and no refresh on the host

- **Decision.** Two tokens do not expire by themselves: the GitHub App user token (expiration turned off) and the Claude token from `claude setup-token`. Both live in Bitwarden. `bws run` hands them to msb when it starts the VM.
- **Why.** msb cannot refresh a secret. It has no refresh hook, and a new value reaches new connections only. A client with an open connection, such as Headroom, keeps the old value and gets 401. We first read the login of `claude` on the host and rotated it into the VM. That needed a watcher and a Headroom restart after each change. See `docs/research/microsandbox-credential-injection.md`.
- **Cost.** A leaked token stays valid until someone revokes it. The GitHub token reaches this repository only. We rotate by hand: make a new token, change the Bitwarden key, revoke the old token, then `msb stop` and `just msb run`. A schedule is not decided yet.

### 4. Encrypt the Bitwarden access token with a passphrase, with no envelope

- **Decision.** The Bitwarden access token is the one secret on the host. It sits in `~/.config/bws/access-token.age`, encrypted with a passphrase.
- **Why.** An agent on the host can read every file of your user, but it cannot type your passphrase. We first planned an envelope (a passphrase protects an age key, and the key protects the token). Both layers rest on the same passphrase, so the envelope adds files and no strength.
- **Cost.** The passphrase is the only protection. Anyone can try guesses on the file, so use a long passphrase. You type it for each recipe that needs Bitwarden. While `bws run` works, the token is in the environment of that process.

### 5. The justfile decrypts the token with the `age` command

- **Decision.** The variable `bws` at the top of `.msb/justfile` runs `age -d`. The recipes use it. `msb.py` does not handle the Bitwarden token.
- **Why.** The `age` command already does the prompt and the decryption. A short shell line is easier to read than Python code with a library.
- **Cost.** A wrong passphrase shows two messages: the error of `age`, then `Missing access token` from `bws`. `age -p` has no minimum length for the passphrase.

### 6. Keep GitHub and ghcr.io tokens apart

- **Decision.** `GH_TOKEN` is a GitHub App user token for the repository. `GITHUB_TOKEN` is a classic token with `write:packages`, only for the registry. The VM never gets `GITHUB_TOKEN`.
- **Why.** The GitHub docs say GitHub Packages supports only a classic personal access token. A GitHub App cannot cover the registry. The App token stays narrow (contents, issues, pull requests, one repository).
- **Cost.** The classic token reaches all packages of the account. Only the host uses it.

### 7. The VM mounts only `.git` and clones it

- **Decision.** The VM mounts the `.git` directory of the host repo, read-only, and clones it.
- **Why.** The VM cannot read your working tree, untracked files or `.env`. It cannot write to the host repo.
- **Cost.** The clone lacks uncommitted changes. Commit before `run`. Work leaves the VM through a pushed branch.

### 8. Allow hosts in `network.allow`, with TLS interception on

- **Decision.** The VM reaches only the hosts in `network.allow`. msb reads HTTPS so it can replace placeholders.
- **Why.** The allow list is the egress policy, and the placeholder replacement needs to read the request.
- **Cost.** Each new site needs `just msb allow-host` and a new VM. Tools that use their own trust store need the msb CA.

### 9. Pin the image by digest, and build it the same way each time

- **Decision.** `sandbox.yaml` pins the image by digest. `build` gives every file the same timestamp and adds no provenance and no SBOM. Layers use zstd level 9, and each stage caches in the registry.
- **Why.** The same files give the same digest, so a commit does not change every layer. A pin means that a VM does not change when someone pushes a tag. zstd unpacks faster than gzip.
- **Cost.** After a change you run `build`, commit the new digest and make a new VM.

### 10. The deny list for GitHub MCP tools is a soft limit

- **Decision.** A root-owned `managed-settings.json` declares the MCP servers and denies five risky GitHub tools.
- **Why.** The file stops mistakes, and the agent cannot edit it.
- **Cost.** The client enforces the list. The agent can still call the GitHub API with the placeholder token. The scope of the token is the real limit.

### 11. Rootless podman in the VM

- **Decision.** The VM has rootless podman for container builds. The group `agent` can open `/dev/fuse` and `/dev/net/tun`.
- **Why.** fuse-overlayfs and the network of a container need these devices. The VM kernel makes them for root only.
- **Cost.** The agent user can reach the FUSE and TUN code of the VM kernel, and `fusermount3` is setuid root. The VM boundary limits what a bug there can do.

### 12. The VM has no command of its own

- **Decision.** `ensure-vm` runs `sandbox-boot` in the VM at each `run`, for a new VM and for an old VM.
- **Why.** Each step of the script does nothing if its work exists. So the next `run` repairs a stopped VM, a failed boot or a stopped Headroom. The clone stays.
- **Cost.** `run` takes a few seconds even when nothing changed.
