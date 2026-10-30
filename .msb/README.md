# The dev sandbox on microsandbox

This sandbox is a VM for Claude Code and the [Fresh](https://github.com/sinelaw/fresh) editor. It uses [microsandbox](https://docs.microsandbox.dev) (open source, Apache-2.0, beta v0.7). It replaced the Docker sbx sandbox (tag `docker-sbx`). One file, `sandbox.yaml`, declares the VM.

The VM holds no secrets, only placeholders. The host replaces a placeholder with the real value when the VM calls an allowed host. The "Decision records" at the end explain why the sandbox works this way.

**Not ported yet:** the SPIRE agent, Envoy and the kind kubeconfig.

## Prerequisites

1. **Install the tools.** You need [mise](https://mise.jdx.dev), Docker (for the image build) and access to `/dev/kvm`.
   - Run the commands in the root of the repository. `mise install` provides `just`, `msb`, `uv`, `bws` (the Bitwarden Secrets Manager CLI), `age`, `jq` and `yq`.
   - You install `docker` yourself. The editor runs in the VM, so the host needs no editor.
   - Every recipe stops with a message if a tool is missing.

   ```shell
   mise trust && mise install
   eval "$(mise activate bash)"
   msb doctor        # each line must have a check mark
   ```

2. **Have an SSH key** at `~/.ssh/id_ed25519` (`ssh-keygen -t ed25519`). `ssh_config` uses it. `edit` and `shell` connect with ssh.
   - Fresh opens in a new window of a terminal on the host (`foot` by default, see `SANDBOX_TERMINAL` below). Use a terminal with mouse and 256-color support. Most modern terminals have both.

3. **Commit your work.** The VM clones the committed files only.

4. **Set up Bitwarden.** The recipes `run`, `build` and `github-login` use `bws run`. It puts each key of the Bitwarden project in the environment of one command. The project needs five keys:

   | Key | Value |
   |---|---|
   | `GH_TOKEN` | the token of the GitHub App (prerequisite 5) |
   | `CLAUDE_CODE_OAUTH_TOKEN` | the Claude token (prerequisite 6) |
   | `GITHUB_APP_CLIENT_SECRET` | the client secret of the GitHub App. `github-login` uses it |
   | `QWEN_API_KEY` | the key of the Qwen Token Plan, international (prerequisite 7) |
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

7. **Make the Qwen key.** In the Alibaba Cloud Model Studio console, subscribe to the Token Plan (the international site, Singapore region) and make an API key. The key and the endpoint must be of the same plan and region, or the call fails with 401 or 403. Copy it to the Bitwarden key `QWEN_API_KEY`. The VM gets a placeholder. The host swaps it for the key in requests to `token-plan.ap-southeast-1.maas.aliyuncs.com` only. Qwen OAuth ended on 2026-04-15, so there is no login in the VM.

## Getting started

```shell
just msb setup         # 1. one time for each host
just msb build         # 2. one time, and after you change dev-tools/
just msb run           # 3. every day
```

| Step | Command | What it does |
|---|---|---|
| 1 | `setup` | Authorizes your SSH key for `msb ssh`. |
| 2 | `build` | Builds `dev-tools/` with Docker and pushes the image to ghcr.io. Pins its digest in `sandbox.yaml`. Commit that change. The first build takes several minutes. |
| 3 | `run` | Makes the VM, or starts it. Runs `sandbox-boot` in it. Opens the Fresh editor in it, in a new terminal window. You can run it as often as you want. |

Fresh shows a menu bar (File, Edit, View, Selection, Go, LSP, Help), tabs and a status bar. You can use the mouse. Fresh does not ask whether to trust the clone: `sandbox-boot` records the answer "trusted" for it (the file that the key `T` writes), so the language servers start at once. To open the editor again in a running VM, run `just msb edit`. It opens a new normal window with the terminal in `SANDBOX_TERMINAL` (default: `foot --title sandbox-dev`). For full screen at launch run `just msb edit full`. To switch a window to full screen or back at any time, press `SUPER+F` (Hyprland). Another terminal works if it takes the command as its last arguments, for example `SANDBOX_TERMINAL='alacritty -e'`. For `edit full`, set `SANDBOX_FULLSCREEN_FLAG` to the flag of that terminal (default `--fullscreen`, which `foot` and `ghostty` take). If there is no display or no such terminal, or to use the terminal you are in, run `just msb edit-here`. More room inside Fresh: `Ctrl+Alt+T` opens a terminal that fills the editor area, and `F11` maximizes the pane that has focus (and restores it). For even more rows, hide the bars with the palette commands "Toggle Menu Bar", "Toggle Status Bar" and "Toggle Tab Bar".

The config uses the VS Code keys wherever a terminal can send them (`active_keybinding_map` is `vscode`, plus 25 keys in `keybindings`). The theme is `solitude.json` (`dev-tools/fresh-theme-solitude.json`): the exact colors of Omarchy Solitude, with real colors for diffs (green for added lines, red for removed), errors, warnings and syntax. The `terminal` theme used the ANSI colors of the terminal, and Solitude is almost gray, so its added and removed lines were both gray and its comments had only 2.2:1 contrast. `edit` sets `COLORTERM=truecolor` in the VM, because ssh does not send it and Fresh then falls back to 256 colors. To try another theme, use the palette: "Select Theme" (built in: dark, dracula, gruvbox, high-contrast, light, nord, nostalgia, solarized-dark, terminal, tokyo-night). To change a color, use "Edit Theme". The terminal in the dock runs `/bin/bash --login -i`.

| You want to | VS Code key | Notes |
|---|---|---|
| Command palette (commands) | `Ctrl+Shift+P` | or `Ctrl+P`, then `>` |
| Open a file by name | `Ctrl+P` | type `:` for a line, `#` for an open tab |
| **Search the open tabs** | `Ctrl+T` | or `Ctrl+P`, then `#`. Also `Ctrl+;` |
| **Open a terminal** (bottom dock) | `` Ctrl+` `` | or `` Alt+` `` |
| **Terminal full size**: open a terminal as a tab that fills the whole editor area | `Ctrl+Alt+T` | the dock stays free; close it like any tab (`Ctrl+W`) |
| **Terminal full size**: make the focused pane (for example the dock terminal) fill the window, and back | `F11` | `` Ctrl+` `` first, then `F11`; `F11` again restores the layout |
| Show or hide the dock; move focus dock or editor | `` Ctrl+Shift+` ``, `Alt+J`; `Alt+O` | |
| In a terminal: scroll, search and copy, and back | `Ctrl+Space` | `Ctrl+]` also works |
| In a terminal: send **every** key to the program | `F9` | use it for `claude`, then `F9` again |
| Show or hide the file explorer; focus it | `Ctrl+B`; `Ctrl+Shift+E` | |
| Search in all files | `Ctrl+Shift+F` | or `Alt+/` |
| Save, save as, open, new file, quit | `Ctrl+S`, `Ctrl+Shift+S`, `Ctrl+O`, `Ctrl+N`, `Ctrl+Q` | |
| Find, next, previous | `Ctrl+F`, `F3`, `Shift+F3` | |
| Replace | `Ctrl+R` | VS Code uses `Ctrl+H`. A terminal cannot tell it from Backspace |
| Go to a line | `Ctrl+G` | |
| Close a tab; next tab; previous tab | `Ctrl+W`; `Ctrl+Tab`; `Ctrl+Shift+Tab` | `Ctrl+PageDown` and `Ctrl+PageUp` also work |
| Split the editor; move between splits | `Ctrl+\`; `Alt+]`, `Alt+[` | |
| Move a line; copy a line up or down | `Alt+Up`, `Alt+Down`; `Alt+Shift+Up`, `Alt+Shift+Down` | |
| Delete a line; comment a line; wrap long lines | `Ctrl+Shift+K`; `Ctrl+/`; `Alt+Z` | |
| **See your git changes**: staged, unstaged and new files with their diffs; stage or discard | `Ctrl+Shift+G` | in that view: `n`/`p` next or previous hunk, `s` stage, `u` unstage, `d` discard, `c` comment, `1`/`2` unified or split, `Enter` jump to the line, `q` close |
| Git history with a live diff of the selected commit | `Ctrl+Alt+G` | palette: "Git Log: Current File" for one file |
| Who changed this line (blame) | `Ctrl+Alt+B` | |
| Jump to the next or previous changed region of the file | `F7`, `Shift+F7` | |
| Add a cursor at the next match | `Ctrl+D` | |
| Undo, redo, select all | `Ctrl+Z`, `Ctrl+Y`, `Ctrl+A` | |
| Go to the definition, references, rename | `F12`, `Shift+F12`, `F2` | |
| Hover, code actions, completion | `Alt+K`; `Ctrl+.`; `Ctrl+Space` | `Alt+.` also gives code actions |
| Settings; menu bar; help | `Ctrl+,`; `F10`; `F1` | |

Git in Fresh: changed lines are marked in the gutter, and the file explorer (`Ctrl+B`) marks each file `M` (modified) or `U` (untracked). The palette also has "Review Diff: Range (Commit or Branch)" (for example `main..HEAD`, to review a whole branch), "Review Diff: Stash" and "Live Diff: vs HEAD". Fresh has no commit or push command. For those use the terminal (`` Ctrl+` ``) or Claude.

The keys with `Shift`, `Ctrl+Tab`, `` Ctrl+` ``, `Ctrl+.` and `Ctrl+,` need a terminal with the kitty keyboard protocol. Fresh turns the protocol on. `foot` 1.28 supports it. In a terminal without it, use the other key in the Notes column. Your window manager can also take a key before Fresh sees it. To change a key, use the palette: "Keybinding Editor".

To run `claude`, open a terminal in Fresh (command palette: "Open Terminal") or use `just msb shell`. It uses the token from Bitwarden and does not ask you to sign in.

## Daily use

| You want to | Run |
|---|---|
| Start or repair the VM | `just msb run` |
| Open a bash prompt in the VM | `just msb shell` |
| Allow one more host | `just msb allow-host example.org`, then `just msb rm && just msb run`, then commit |
| Change a token | Change the Bitwarden key, revoke the old token, then `msb stop sandbox-dev` and `just msb run` |
| Add another secret | Add it under `secrets:` in `sandbox.yaml`, add its hosts to `network.allow`, add a Bitwarden key with the same name, add the name to `# --- Required environment variables ---` in `.msb/justfile`, then `just msb rm && just msb run` |
| Change a tool of the image | Edit a file in `dev-tools/`, commit, `just msb build`, commit the new digest, then `just msb rm && just msb run` |
| Remove the VM | `just msb rm`. Add `--volumes` to remove the volumes too |

More commands: `msb ls` (state), `msb logs sandbox-dev`, `msb inspect sandbox-dev` and `msb <command> --help`.

## How it works

- **The clone.** The VM mounts the `.git` directory of the host repo at `/run/sandbox/source`. It cannot write to the mount. It cannot read your working tree, untracked files or `.env`. `sandbox-boot` clones it to `/home/agent/engineersdaybook`, on the branch of the host checkout. Commit on the host before `run`. Push a feature branch from the VM and open the pull request on GitHub.
- **The fingerprint.** `run` stores a hash in the label `config-sha`. It covers `sandbox.yaml` and the host values `SANDBOX_GIT_DIR`, `GIT_AUTHOR_NAME` and `GIT_AUTHOR_EMAIL` (`run` reads them from git). If the hash differs at the next `run`, `run` stops and keeps the VM. Push your work, then run `just msb rm && just msb run`. The volumes stay.
- **The boot.** At each `run`, `ensure-vm` runs `dev-tools/sandbox-boot` in the VM. A step of the script does nothing if its work exists. So `run` also repairs a stopped VM, a failed boot and a stopped Headroom. If a step fails, `run` prints the reason and exits with 1. The VM keeps running.
- **The tokens.** The VM has the placeholders `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN` and `QWEN_API_KEY`. The host replaces `GH_TOKEN` in requests to `github.com`, `api.github.com` and `api.githubcopilot.com` (Bearer and Basic auth, so `git push` works). It replaces `CLAUDE_CODE_OAUTH_TOKEN` in requests to `api.anthropic.com`. It replaces `QWEN_API_KEY` in requests to `token-plan.ap-southeast-1.maas.aliyuncs.com`. It blocks each token for every other host, except that each placeholder (never the token) may reach the model API of the other agents (`passthrough`): `GH_TOKEN` reaches `api.anthropic.com` and the Qwen host, `CLAUDE_CODE_OAUTH_TOKEN` reaches the Qwen host, and `QWEN_API_KEY` reaches `api.anthropic.com`. Without that, a conversation that contains the text `$MSB_GH_TOKEN` (for example after the agent reads this file) fails with `403 Request blocked by secret policy`. Qwen Code shows this as `API Error: 403 status code (no body)`, and the session keeps failing, because it sends the whole history with each request. `bws run` puts both in the environment of `ensure-vm`, and msb reads them when it starts the VM. A running VM does not read a changed secret.
- **Allowed hosts.** The VM reaches only the hosts in `network.allow`. A blocked host fails at DNS. `*.example.com` matches subdomains at any depth. msb rejects `**.example.com` and an entry with a port.
- **Ports of the host.** The VM reaches three ports of the host at `host.microsandbox.internal:<port>`: 6444 (the kind API server), 18081 (the SPIRE server) and 19090 (the Flux Operator web UI). `msb.py` passes one `--net-rule` for each (`HOST_PORTS`). Nothing in the VM uses them yet.
- **Headroom dashboard.** Open `http://127.0.0.1:8787/dashboard` (`/stats` and `/health` work too). Host port 8787 must be free, or `just msb run` fails. To use another port, change `network.ports` in `sandbox.yaml` (`127.0.0.1:8788:8787`). Headroom has no login, so any user of the host can open it. An existing VM needs `just msb rm && just msb run` once.
- **Volumes.** `claude-home` keeps the settings, the history and the plugins of Claude Code (not a login). `terraform-providers` is the Terraform provider cache. `podman-storage` has the images that podman pulls and builds. They stay when you remove the VM.
- **The image.** The files of `dev-tools/tools/` list the tools and their exact versions in six groups: `runtimes`, `headroom`, `infra`, `dev`, `agents` and `lsp`. `agents` has Claude Code and Qwen Code (the command `qwen`). `dev-tools/qwen-settings.json` becomes `~/.qwen/settings.json`: one provider, the Token Plan (international, Singapore), model `qwen3.8-max`, with the key in `QWEN_API_KEY` (prerequisite 7). Every tool has an exact version, except `claude` and `qwen-code`: they are `2.1` and `0.26`, so a build takes the newest 2.1.x and 0.26.x. Docker caches that stage by the text of the file, so run `just msb build refresh` to install a newer one. A new VM (`just msb rm && just msb run`) then has it. For 2.2 or 0.27 or later, edit `tools/agents.toml`. `build` pushes `ghcr.io/raghav19/engineersdaybook/dev-sbx`, tagged with the commit, and writes the digest in `sandbox.yaml` (`image.oci: ...@sha256:...`). The package is private. `sandbox.yaml` has a `registry` block with `password_env: GITHUB_TOKEN`, so `run` pulls with the token from Bitwarden.
- **MCP servers.** `dev-tools/managed-settings.json` becomes `/etc/claude-code/managed-settings.json` in the VM. Root owns it, and project and user settings cannot override it. It declares draw.io, the Flux schema catalog and GitHub. It denies five GitHub tools (`merge_pull_request`, `delete_file` and others). To change it, run `just msb build`.
- **Podman.** The VM has rootless podman. `docker` is an alias of podman. `sandbox-boot` gives the group `agent` access to `/dev/fuse` and `/dev/net/tun`, makes `/` a shared mount, and `/etc/containers/containers.conf.d/10-sandbox.conf` mounts `/etc/ssl/certs` in each container. The policy of the VM applies to a container too. To push to a registry on the host, allow its port in `HOST_PORTS`.
- **The recipes.** The justfile lists the steps of each recipe in order. The top of the justfile lists the required tools with the just function `require`. just checks them at the start of every recipe and stops with a message if one is missing. The block `# --- Required environment variables ---` lists the required Bitwarden keys with `env`. `run` starts the private recipe `_vm` with `bws run` and the variable `MSB_IN_BWS=1`. The keys exist only there, so just checks them only when that variable is set. `msb.py` has the steps that need Python (`github-login`, `ensure-vm`, `allow-host`). It is a `uv` script. On the first run, `uv` installs Python 3.13 and the one dependency, `ruamel.yaml` (this needs the network).
- **Memory.** The VM has 3 GB and 4 CPUs (`memory` and `cpus` in `sandbox.yaml`). A test with Headroom, Fresh, all nine language servers and `claude` together peaked at 810 MB. The VM has no swap, so a process that needs more than the VM has is killed. Big container builds or Terraform plans may need more: change `memory`, then `just msb rm && just msb run` (push your work first).
- **Small items.** `sandbox-boot` installs the plugin ponytail 5.3.2. The shell is plain bash. `sandbox.yaml` sets the git identity from your host git config. The VM has no sshd: `ssh_config` starts `msb ssh serve` as a `ProxyCommand`, so the VM must run before `edit` or `shell` connects. `ssh_config` expects `msb` in the default mise data directory (`~/.local/share/mise`).

## When something fails

| You see | Do this |
|---|---|
| `could not find executable ...` | A tool is not on the `PATH`. Run `mise install` in the repo root. Install `docker` and `code` yourself. |
| ``environment variable `GH_TOKEN` not present`` (or another key) | `bws run` did not give that key. Check that the key exists in the Bitwarden project with this exact name, and that your machine account can read the project. To list the key names, run `BWS_ACCESS_TOKEN=$(age -d ~/.config/bws/access-token.age) bws secret list \| jq -r '.[].key'`. just reports one key at a time, so check all four: `GH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `QWEN_API_KEY` and `GITHUB_TOKEN`. |
| `age: error: incorrect passphrase`, then `Missing access token` | You entered the wrong passphrase. Run the recipe again. |
| `age: error: failed to open input file`, then `Missing access token` | The encrypted token file does not exist. Do prerequisite 4. |
| `run` cannot pull the image (`not found` or `unauthorized`) | `not found`: `sandbox.yaml` does not pin an image that exists. Run `just msb build`. `unauthorized`: the Bitwarden key `GITHUB_TOKEN` needs the scope `read:packages`. |
| `msb doctor` shows a red line | Read the line. For `/dev/kvm`, run `sudo usermod -aG kvm "$USER"`, then log in again. |
| `run` says that `sandbox-boot` failed | `run` prints the reason. Run `just msb run` again. This repairs a cause outside the VM, such as the network. If the cause is in `sandbox.yaml`, the image or a host value, run `just msb rm && just msb run`. |
| `msb ls` shows `crashed` or `stopped` | Run `just msb run`. The clone stays. If `run` still fails and the clone has work, push the work first. Then run `just msb rm && just msb run`. |
| `run` says that the VM does not match the configuration | `sandbox.yaml` or a host value changed. Push the work in the clone (`just msb shell`). Then run `just msb rm && just msb run`. |
| A site fails in the VM | The site is not in `network.allow`. Run `just msb allow-host <host>`. |
| `just msb edit` cannot connect | Run `just msb run`, then `just msb setup` again. Check that `msb ls` shows the VM as `running`. |
| The editor or the shell freezes after some output | You are on `msb exec`. `edit` and `shell` use ssh because of this. See decision 14. |
| A language server does not start | Look at the LSP indicator in the status bar of Fresh (click it). Fresh starts servers only in a trusted folder. `sandbox-boot` trusts the clone. For another folder use the command palette, "Workspace Trust...", then trust. The server logs are in `~/.local/state/fresh/logs/lsp/` in the VM. |
| No hints in a Dockerfile | The server starts, but I did not see diagnostics from it. See decision 14. |
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

- **Decision.** The variable `bws_run` at the top of `.msb/justfile` runs `age -d`. The recipes use it. `msb.py` does not handle the Bitwarden token.
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

- **Decision.** `sandbox.yaml` pins the image by digest. `build` gives every file the same timestamp and adds no provenance and no SBOM. Layers use zstd level 9. The build does not export a cache to the registry: on a 14 GB machine, that export grew past 6 GB in 25 seconds in a test, and in full builds systemd-oomd killed Docker at 6 GB of memory and 17 GB of swap. The cache of BuildKit on your machine is enough.
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

### 13. Check the tools and the keys at the top of the justfile

- **Decision.** The top of `.msb/justfile` lists the tools with `require` and the Bitwarden keys with `env`. We do not use `set lazy`.
- **Why.** just checks every top-level definition at the start and stops with its own message. The recipes need no check of their own, and we wrote no shell loop. The keys exist only inside `bws run`, so `run` starts `_vm` there with `MSB_IN_BWS=1`. The key lines are `if`-expressions that read the variable only when `MSB_IN_BWS` is set.
- **Cost.** Every recipe needs all the tools, also `shell` and `rm`. just runs `git rev-parse HEAD` for each recipe. It reports one missing item at a time, in the alphabetical order of the variable names. The key names in the justfile must match `sandbox.yaml`.

### 14. Fresh is the editor, and it runs in the VM

- **Decision.** The editor is [Fresh](https://github.com/sinelaw/fresh) 0.5.4 (Rust, GPL-3.0). It is a terminal editor with menus, tabs, a file explorer, mouse support and a built-in terminal. It has no modes. It runs in the VM, in the terminal where you run `just msb run`. `dev-tools/fresh-config.json` is the one file that says which language server starts for which language. The Dockerfile copies it to `~/.config/fresh/config.json`. The servers are in `tools/lsp.toml` (and ty and ruff in `tools/dev.toml`).
- **Why.** VS Code needed an SSH link, a server in the VM and an extension host. Fresh needs a binary and one file. It has no plugin code in this repo and nothing to install or match on the host. `edit` and `shell` connect with ssh (`ssh_config`, `msb ssh serve --stdio`), not with `msb exec`. Fresh finds the servers in the PATH. The comparison with Zed, Helix, Lapce, micro and Emacs is in `docs/research/vm-editor-options.md`.
- **Cost.** Fresh is young (0.5.4) and its terminal UI is not a GUI window. The Node server for Dockerfiles (`dockerfile-language-server-nodejs`) crashes on the answer that Fresh gives to `workspace/configuration`, so we use Docker's own `docker-language-server`. For it, I saw the server start and answer hover, but no diagnostics. Fresh limits each server to 50% of the memory of the system. `bash-language-server` (it loads a WASM parser) and `marksman` (.NET) need `process_limits.enabled = false` in the config. Without it they crash with errors that name a missing file or an out-of-memory zone. The memory limit of the VM stays. Fresh sends the right language id for Terraform and just, so they need no shim. `msb exec` (msb 0.7.10) stops passing output after about 1 MB, with or without a terminal, and a screen editor then freezes. I measured this: Fresh, `less` and plain `cat` all stopped near 1 MB, and ssh through `msb ssh serve --stdio` passed 6.9 MB at once. So the editor and the shell use ssh. `setup` and the SSH key are needed again. The config turns off 12 bundled plugins that this sandbox does not need: the agent and orchestrator plugins (they list your Claude Code and Codex sessions and run Fresh as a background daemon, so `auto_attach` is off too) and the welcome screen and dashboard. This takes the idle memory of Fresh from about 80 MB to about 63 MB. Fresh also tries the X11 clipboard, which does not exist in the VM, so the config turns it off (copy then uses the terminal clipboard, OSC 52).
