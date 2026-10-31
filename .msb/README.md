# The dev sandbox on microsandbox

This sandbox is a VM for Claude Code and the [TTT](https://github.com/eugenioenko/ttt) editor. It uses [microsandbox](https://docs.microsandbox.dev) (open source, Apache-2.0, beta v0.7). It replaced the Docker sbx sandbox (tag `docker-sbx`). One file, `sandbox.yaml`, declares the VM.

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
   - TTT opens in the terminal where you run `just msb run`. Use a terminal with mouse and 24-bit color support. Most modern terminals have both.

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
| 3 | `run` | Makes the VM, or starts it. Runs `sandbox-boot` in it. Opens the TTT editor in this terminal. You can run it as often as you want. |

TTT shows a menu bar, tabs, a sidebar and a status bar. You can use the mouse. TTT has no workspace trust gate, so it does not ask about the clone. A language server starts as soon as you open a file that matches one. `run` opens the editor in the terminal where you ran it. Quit with `Ctrl+Q` and your shell comes back. The VM keeps running, because `run` starts it before ssh connects, so `msb ssh serve` attaches to it and does not own it. `just msb edit` then opens the editor again with no bring-up. For full screen press `SUPER+F` (Hyprland). More room inside TTT: `Alt+T` makes the terminal fill the window, `Ctrl+K B` shows or hides the bottom panel, and `Alt+Shift+M` hides the menu bar.

The image bakes one file into `~/.config/ttt/`, and that file is `settings.json`. It also makes an empty `themes/` folder there, because a plugin cannot create one. `dev-tools/ttt-settings.json` is the one place that says which language server starts for which language. The theme is `omarchy`, and no theme file is baked. The plugin `omarchy-theme` writes `themes/omarchy.json` at each start from the palette of the host, which `sandbox.yaml` mounts read-only. So the editor follows whichever Omarchy theme is active on the host, within two seconds of a switch. Until that plugin is installed, `omarchy` does not resolve and TTT uses its own default. The picker previews each theme live. Open it with `Ctrl+P`, then search for "Switch Theme". `edit` sets `COLORTERM=truecolor` in the VM, because ssh does not send it and TTT then falls back to 256 colors. The terminal runs `/bin/bash --login -i`.

| You want to | TTT key | Notes |
|---|---|---|
| Command palette | `Ctrl+P` | VS Code uses `Ctrl+Shift+P`. TTT cannot bind that key. See below |
| Open a file by name | `Ctrl+K P` | VS Code uses `Ctrl+P`. A chord: press `Ctrl+K`, release, then press `P` |
| Open a folder | `Ctrl+O` | |
| New file, save, save as, quit | `Ctrl+N`, `Ctrl+S`, `Ctrl+K S`, `Ctrl+Q` | VS Code uses `Ctrl+Shift+S` for save as |
| **Open a terminal** (bottom panel) | `Ctrl+T` | VS Code uses `` Ctrl+` `` |
| **Make the terminal fill the window**, and back | `Alt+T` | |
| A new terminal tab | `Ctrl+K T` | the tabs list down the left edge of the panel |
| Show or hide the bottom panel | `Ctrl+K B` | the panel holds Terminal, Problems and References |
| In a terminal: scroll | mouse wheel, `Shift+PgUp`, `Shift+PgDn` | any key snaps back to the live view |
| Move focus: editor, panel, sidebar | `F6`, `Shift+F6` | |
| Show or hide the sidebar, focus it | `Ctrl+B`, `Ctrl+0` | |
| Focus the file explorer | `Ctrl+K E` | VS Code uses `Ctrl+Shift+E` |
| Search in all files | `Ctrl+K F` | VS Code uses `Ctrl+Shift+F` |
| Search and replace in all files | `Ctrl+K R` | VS Code uses `Ctrl+Shift+H` |
| Find, next, previous | `Ctrl+F`, `F3`, `Shift+F3` | |
| Replace | `Ctrl+R` | VS Code uses `Ctrl+H`. A terminal sends Backspace for it |
| Go to a line | `Ctrl+G` | |
| Close a tab, pin a tab | `Ctrl+W`, `Ctrl+K Enter` | |
| Next tab, previous tab | `Alt+.`, `Alt+,` | VS Code uses `Ctrl+Tab` |
| Move a line up or down | `Alt+Up`, `Alt+Down` | |
| Delete a line | `Ctrl+K K` | VS Code uses `Ctrl+Shift+K` |
| Duplicate a line | no key | `Ctrl+P`, then search "duplicate line" |
| Comment a line | `Ctrl+/` | |
| Wrap long lines | no key | `Ctrl+P`, then search "word wrap" |
| Insert a line below, join two lines | `Ctrl+Enter`, `Ctrl+K J` | |
| Fold, collapse all, expand all | `Ctrl+K [`, `Ctrl+K 0`, `Ctrl+K 9` | |
| Go to the matching bracket, sort lines | `Ctrl+K M`, `Ctrl+K O` | |
| A word left or right, delete a word | `Ctrl+Left`, `Ctrl+Right`, `Alt+Backspace` | |
| Start of file, end of file | `Ctrl+Home`, `Ctrl+End` | add `Shift` to select instead |
| **Your git changes**: stage, unstage, discard, commit, push, pull, sync | `Ctrl+K C` | VS Code uses `Ctrl+Shift+G`. The panel also lists the commit history |
| Add a cursor at the next match | `Ctrl+D` | |
| A cursor on every match, undo the last cursor | `Ctrl+K L`, `Ctrl+K U` | |
| Undo, redo, select all | `Ctrl+Z`, `Ctrl+Y`, `Ctrl+A` | |
| Copy, cut, paste | `Ctrl+C`, `Ctrl+X`, `Ctrl+V` | in the terminal, `Ctrl+V` pastes the buffer of TTT, not the clipboard of the host |
| Go to the definition | `F12` | |
| Go to the implementation, to the type | `Shift+F12` or `Ctrl+L I`, `Ctrl+L T` | VS Code uses `Shift+F12` for references |
| Find references | `Ctrl+L R` | |
| Rename | `F2` | |
| Hover information | `Ctrl+K I` | the mouse also hovers |
| Format the document, the selection | `Ctrl+L F`, `Ctrl+L S` | VS Code uses `Shift+Alt+F` |
| Fix all, organize imports | `Ctrl+L X`, `Ctrl+L O` | |
| Completion | `Ctrl+U` | it also suggests while you type |
| Restart a language server | no key | `Ctrl+P`, then search "restart" |
| Settings, keybindings | `Ctrl+K ,`, `Ctrl+K Y` | VS Code uses `Ctrl+,` |
| Menu bar | `F10`, or `Alt+F`, `Alt+E`, `Alt+S`, `Alt+V`, `Alt+O`, `Alt+H` | File, Edit, Selection, View, Options, Help |
| Show or hide the menu bar | `Alt+Shift+M` | |
| Resize the panel, resize the sidebar | `Alt+Shift+Up`, `Alt+Shift+Down`, `Alt+Shift+Left`, `Alt+Shift+Right` | VS Code uses the first two to duplicate a line |
| Preview a markdown file | no key | `Ctrl+P`, then search "Preview: Markdown". Right-click a `.md` file for the same entry. Text only, see below |
| Switch theme | no key | `Ctrl+P`, then search "switch theme" |
| Split the editor | none | TTT has no split editor. `F6` moves focus, it does not split |

Git in TTT: changed lines are marked in the gutter and on the scrollbar, and the file explorer (`Ctrl+B`) colors each file by its status. The Changes panel (`Ctrl+K C`) stages, unstages and discards, lists the commit history, writes the commit, and pushes, pulls and syncs. Fresh could not commit or push. A diff opens split or unified. Blame has no command of its own. It shows as a segment in the status bar. TTT also reviews a GitHub pull request when you pass its URL, but that needs the `gh` CLI, and the image has no `gh`.

TTT does not need the kitty keyboard protocol for its own keys. Every binding is a plain key or a chord, and a chord works in any terminal. TTT does ask the terminal for the protocol at its lowest level, and it waits at most one second for the answer. It cannot bind `Ctrl+Shift+<letter>`, because it registers that combination as one key and the terminal reports it as another. That is why the table above has no `Ctrl+Shift+P`, `Ctrl+Shift+F` or `Ctrl+Shift+G`. A chord replaces each of them. Your window manager can also take a key before TTT sees it. To change a key, use `Ctrl+K Y`.

To run `claude` or `qwen`, open a terminal in TTT (`Ctrl+T`) or use `just msb shell`. `claude` uses the token from Bitwarden and does not ask you to sign in.

TTT keeps seven keys for itself while the terminal has focus. They are `Ctrl+T`, `Alt+T`, `Ctrl+Q`, `Ctrl+P`, `Ctrl+B`, `F6` and `Shift+F6`. Every other key reaches the program, so `claude` and `qwen` get their own keys. Fresh needed `F9` for this, and TTT has no such switch. You can still give a key back. Clear its binding in `keybindings.json`, or move it to a chord, and TTT stops forcing it.

TTT has no agent session hub and no orchestrator. No plugin in its community list scans `~/.claude/projects/`. Sessions are a shell matter:

| You want to | Run |
|---|---|
| List the Qwen Code sessions | `qwen sessions` |
| Rejoin the newest session of this project | `qwen -c` |
| Pick a Qwen Code session to rejoin | `qwen --resume` |
| Rejoin a Claude Code conversation | `claude --resume` |

The `claude-home` volume keeps the Claude Code conversations, so they survive `just msb rm`. `qwen --help` notes that `--chat-recording` must be on, or `--continue` and `--resume` have nothing to read.

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
- **The image.** The files of `dev-tools/tools/` list the tools and their exact versions in six groups: `runtimes`, `headroom`, `infra`, `dev`, `agents` and `lsp`. `agents` has Claude Code and Qwen Code (the command `qwen`). `dev` has the editor (`ttt`), which mise fetches from its GitHub release and verifies against the `checksums.txt` of that release. `dev-tools/qwen-settings.json` becomes `/etc/qwen-code/settings.json`: one provider (the Token Plan, international, Singapore), model `qwen3.8-max`, with the key in `QWEN_API_KEY` (prerequisite 7), and the MCP servers (draw.io, Flux schema catalog, GitHub). Qwen Code makes `~/.qwen` itself, as agent, for the state that it writes. Every tool has an exact version, except `claude` and `qwen-code`: they are `2.1` and `0.26`, so a build takes the newest 2.1.x and 0.26.x. Docker caches that stage by the text of the file, so run `just msb build refresh` to install a newer one. A new VM (`just msb rm && just msb run`) then has it. For 2.2 or 0.27 or later, edit `tools/agents.toml`. `build` pushes `ghcr.io/raghav19/engineersdaybook/dev-sbx`, tagged with the commit, and writes the digest in `sandbox.yaml` (`image.oci: ...@sha256:...`). The package is private. `sandbox.yaml` has a `registry` block with `password_env: GITHUB_TOKEN`, so `run` pulls with the token from Bitwarden.
- **MCP servers.** Both Claude Code and Qwen Code have the same MCP servers (draw.io, Flux schema catalog, GitHub) configured at the system level. For Claude Code, `dev-tools/managed-settings.json` becomes `/etc/claude-code/managed-settings.json`. For Qwen Code, `dev-tools/qwen-settings.json` becomes `/etc/qwen-code/settings.json`, the system scope of Qwen Code. Root owns both files and their folders, so the agent cannot replace a file, and project and user settings cannot override them. The Claude Code settings deny five GitHub tools (`merge_pull_request`, `delete_file` and others). To change them, run `just msb build`.
- **The editor config.** `dev-tools/ttt-settings.json` becomes `~/.config/ttt/settings.json`. It is the one place that says which language server starts for which language. The image bakes no theme file and no grammar. The theme in use is `omarchy`, and the plugin below writes it at each start. The binary carries 19 themes and 125 grammars, and those grammars cover every language this repo uses except Just. So a `justfile` opens as plain text, and no server runs for it. `just` itself still reports a bad recipe when you run it. To add one theme or one grammar later, drop its JSON in `dev-tools/` and COPY it to `~/.config/ttt/themes/` or `~/.config/ttt/grammars/`. No upstream clone is needed. `TTT_CONFIG_DIR` in `dev-tools/mise.toml` pins that directory. Without it TTT prefers a `config/` directory next to its own executable, and that one wins file by file with no merge. One entry of `lsp.servers` needs care. `dockerfile` has no `languages` map, because a name with no dot has no extension to match, so TTT falls back to the name of the grammar. Every server key is lower case, because TTT lowercases the name before it looks the key up, and nothing checks it. Python has one server, because TTT runs one server per extension and two entries for `.py` would give a random winner. See `docs/research/vm-editor-ttt.md`.
- **The editor plugins.** `plugins.enabled` is `true`, and the image carries no plugin. Both that this sandbox uses are in the TTT community registry, so the panel installs them. Open the palette (`Ctrl+P`), search for "Plugins", then install `markdown-preview` and `omarchy-theme` and approve each. That takes about 30 seconds, and you repeat it after each `just msb rm`, because `~/.config/ttt` is in the VM and not in a volume. `markdown-preview` adds the palette command "Preview: Markdown" and a right-click entry on a `.md` file. It calls the markdown renderer that TTT already has. `omarchy-theme` reads the palette of the host from the read-only mount, writes `themes/omarchy.json`, and polls that mount every two seconds. It asks for `fs.read` on `~/.local/state/omarchy`, `fs.write` on `{config}/themes`, and `settings` limited to the key `theme`. Neither plugin asks for `system.exec`, `network.http` or `network.rpc`. Enabling plugins costs one automatic network call: a fetch of the community plugin list from `raw.githubusercontent.com` at each start. That host is in `network.allow`, the fetch runs in a goroutine with a timeout of 10 seconds, and it cannot block the start. TTT also scans a `plugins/` folder inside the open repository, and this repo has none.
- **Podman.** The VM has rootless podman. `docker` is an alias of podman. `sandbox-boot` gives the group `agent` access to `/dev/fuse` and `/dev/net/tun`, makes `/` a shared mount, and `/etc/containers/containers.conf.d/10-sandbox.conf` mounts `/etc/ssl/certs` in each container. The policy of the VM applies to a container too. To push to a registry on the host, allow its port in `HOST_PORTS`.
- **The recipes.** The justfile lists the steps of each recipe in order. The top of the justfile lists the required tools with the just function `require`. just checks them at the start of every recipe and stops with a message if one is missing. The block `# --- Required environment variables ---` lists the required Bitwarden keys with `env`. `run` starts the private recipe `_vm` with `bws run` and the variable `MSB_IN_BWS=1`. The keys exist only there, so just checks them only when that variable is set. `msb.py` has the steps that need Python (`github-login`, `ensure-vm`, `allow-host`). It is a `uv` script. On the first run, `uv` installs Python 3.13 and the one dependency, `ruamel.yaml` (this needs the network).
- **Memory.** The VM has 3 GB and 4 CPUs (`memory` and `cpus` in `sandbox.yaml`). A test with Headroom, the previous editor, all nine language servers and `claude` together peaked at 810 MB. That test predates TTT, so no figure is measured with it yet. The VM has no swap, so a process that needs more than the VM has is killed. Big container builds or Terraform plans may need more: change `memory`, then `just msb rm && just msb run` (push your work first).
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
| A language server does not start | Click the language segment in the status bar. It opens the output panel. TTT starts a server only when the file matches an entry of `lsp.servers` in `dev-tools/ttt-settings.json`, and only when the first word of `command` is on the `PATH`. Every request has a timeout of 10 seconds. A server that misses it on `initialize` is marked failed and does not retry by itself. Restart it with `Ctrl+P`, then search "restart". With `--debug`, TTT writes `~/.config/ttt/ttt.log`. |
| No hints in a Dockerfile | Not measured with TTT yet. Under Fresh the server started and answered hover, but it gave no diagnostics. See decision 14. |
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

### 14. Fresh is the editor, and it runs in the VM (record 15 replaces this one)

- **Decision.** The editor is [Fresh](https://github.com/sinelaw/fresh) 0.5.4 (Rust, GPL-3.0). It is a terminal editor with menus, tabs, a file explorer, mouse support and a built-in terminal. It has no modes. It runs in the VM, in the terminal where you run `just msb run`. `dev-tools/fresh-config.json` is the one file that says which language server starts for which language. The Dockerfile copies it to `~/.config/fresh/config.json`. The servers are in `tools/lsp.toml` (and ty and ruff in `tools/dev.toml`).
- **Why.** VS Code needed an SSH link, a server in the VM and an extension host. Fresh needs a binary and one file. It has no plugin code in this repo and nothing to install or match on the host. `edit` and `shell` connect with ssh (`ssh_config`, `msb ssh serve --stdio`), not with `msb exec`. Fresh finds the servers in the PATH. The comparison with Zed, Helix, Lapce, micro and Emacs is in `docs/research/vm-editor-options.md`.
- **Cost.** Fresh is young (0.5.4) and its terminal UI is not a GUI window. The Node server for Dockerfiles (`dockerfile-language-server-nodejs`) crashes on the answer that Fresh gives to `workspace/configuration`, so we use Docker's own `docker-language-server`. For it, I saw the server start and answer hover, but no diagnostics. Fresh limits each server to 50% of the memory of the system. `bash-language-server` (it loads a WASM parser) and `marksman` (.NET) need `process_limits.enabled = false` in the config. Without it they crash with errors that name a missing file or an out-of-memory zone. The memory limit of the VM stays. Fresh sends the right language id for Terraform and just, so they need no shim. `msb exec` (msb 0.7.10) stops passing output after about 1 MB, with or without a terminal, and a screen editor then freezes. I measured this: Fresh, `less` and plain `cat` all stopped near 1 MB, and ssh through `msb ssh serve --stdio` passed 6.9 MB at once. So the editor and the shell use ssh. `setup` and the SSH key are needed again. The config turns off 12 bundled plugins that this sandbox does not need: the agent and orchestrator plugins (they list your Claude Code and Codex sessions and run Fresh as a background daemon, so `auto_attach` is off too) and the welcome screen and dashboard. This takes the idle memory of Fresh from about 80 MB to about 63 MB. Fresh also tries the X11 clipboard, which does not exist in the VM, so the config turns it off (copy then uses the terminal clipboard, OSC 52).

### 15. TTT replaces Fresh as the editor (record 17 amends the theme and the plugins)

- **Decision.** The editor is [TTT](https://github.com/eugenioenko/ttt) 1.10.0 (Go, MIT). It is a terminal editor with a menu bar, tabs, a sidebar, a bottom panel, mouse support and an integrated terminal. It has no modes. `tools/dev.toml` installs it through the mise `github:` backend, so the Dockerfile has no editor stage of its own. `dev-tools/ttt-settings.json` is the one file that says which language server starts for which language. The Dockerfile copies it to `~/.config/ttt/settings.json`, and that is the only editor file the image bakes. The theme is `vscode-dark-plus`, which the binary carries, so the image bakes no theme file.
- **Why.** Fresh could not commit or push, and TTT can. TTT also formats through the server, organizes imports, folds code and opens a diff, with no plugin code in this repo. Three faults of Fresh have no analogue in TTT, and I read each one in its source. TTT never opens an X11 or a Wayland connection, so the clipboard stall of 47 seconds cannot happen. TTT sets no memory limit on a language server, so `marksman` and `bash-language-server` need no exception. TTT has no workspace trust gate, so `sandbox-boot` writes no trust file. TTT also waits at most one second for the terminal to answer its capability query. The evidence and the file paths are in `docs/research/vm-editor-ttt.md`.
- **Cost.** Six things are lost.
  1. TTT runs one language server per file extension, and two entries for `.py` give a random winner. So Python has `ruff` only. `ty` stays in the image for `prek`, and it still gates every commit, but it gives no diagnostics while you type.
  2. TTT has no split editor. `F6` moves focus between the editor, the panel and the sidebar.
  3. TTT cannot bind `Ctrl+Shift+<letter>`. It registers that combination as one key and the terminal reports it as another. The VS Code keys that the Fresh config mapped are gone, and the chords of TTT replace them.
  4. TTT has no agent session hub and no orchestrator, and no plugin in its community list scans `~/.claude/projects/`. Sessions are a shell matter again. The answer in that ecosystem is Herdr, and `herdr.dev` is not in `network.allow`.
  5. TTT has no workspace trust gate, and that changes the threat model. Opening a hostile repository now runs the configured servers and formatters at once. Our config is baked and the agent cannot rewrite it, so the blast radius is what we configured. TTT also scans a `plugins/` directory inside the repository, but a plugin there still needs an approval dialog before it runs.
  6. A `justfile` has no editor support. TTT compiles in 125 grammars and Just is not one of them, so the file opens as plain text and no server runs for it. Wiring it would need one vendored grammar of 18 KB plus its MIT notice, and we chose not to carry that. `just-lsp` is out of `tools/lsp.toml` for the same reason, because nothing could start it. `just` still reports a bad recipe when you run it. The grammar is available upstream at `ttt-plugins/lang-just`, so this is reversible with one file.

  Three more costs are smaller. Every LSP request has a timeout of 10 seconds, and no setting changes it. So a server that is slow to answer `initialize` is marked failed, and it does not retry by itself. `marksman` and `bash-language-server` are the two candidates, and neither is measured yet. TTT installs no handler for SIGTERM, so a killed TTT can leave the terminal in the keyboard mode that TTT set. If keys break after that, set `TCELL_KEYBOARD_PROTOCOL` to `legacy` in `dev-tools/mise.toml`, and accept the loss of `Ctrl+Tab`. The theme needs no contrast patch, and that is a change from the first candidate. `vscode-dark-plus` paints `#1e1e1e` as its background and its body text at 11.25 to 1 against it. Comments are `#6a9955` at 5.00 to 1, and every syntax color sits at 4.5 to 1 or above. Its three diff backgrounds are distinct: `#1e3a1e` for added, `#3a1e1e` for deleted and `#3a3a1e` for modified. I computed those ratios from the theme file, and I did not read them on a screen. The earlier candidate, `29-slate`, painted comments at 2.55 to 1, which is the same defect that the Solitude theme had before its fix.

### 16. The editor opens in your terminal, not in a new window

- **Decision.** `edit` is one line of ssh. It runs TTT in the terminal where you ran `just msb run`, and `Ctrl+Q` gives the shell back. There is no `edit-here`, no `edit full`, and no `SANDBOX_TERMINAL` or `SANDBOX_FULLSCREEN_FLAG`.
- **Why.** The recipe was 16 lines, and all of them served one behaviour: open a second window with a terminal of your choice. Its only caller was `run`, and `edit-here` was the same ssh command with none of that logic. What must survive is the split of `run` into two lines. Only the first runs under `bws run`, so the editor, and every shell or agent you start inside it, never sees `GH_TOKEN`, `GITHUB_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN` or `QWEN_API_KEY`. That split is about lines, not about windows.
- **Cost.** No second window, so the terminal that ran `run` stays busy until you quit. Open another `foot` window if you need a host shell. `SUPER+F` replaces `edit full`. A terminal other than the one you are in is no longer configurable. A failed connection prints the ssh error instead of a message that waits for Enter. The lifetime of the VM does not change. Quitting TTT already ended the ssh session before this. And `run` starts the VM first, so `msb ssh serve` attaches to it rather than owns it.

### 17. The editor takes its theme from the host, and it renders markdown as text

- **Decision.** `plugins.enabled` is `true`, and the image carries no plugin. Two plugins are installed from the TTT panel instead: `markdown-preview` and `omarchy-theme`. Both are in the community registry with a `path` entry, so the panel installs each one from that monorepo. `omarchy-theme` writes `themes/omarchy.json` from the palette of the host, so `settings.json` names the theme `omarchy`. `markdown-preview` adds "Preview: Markdown" to the palette and to the right-click menu of a `.md` file. `sandbox.yaml` mounts `~/.local/state/omarchy/current/theme` into the VM read-only, and the justfile supplies that path as `SANDBOX_OMARCHY_THEME`. The Dockerfile makes `themes/` first, because the filesystem API of a plugin cannot create a directory and refuses to open a missing one.
- **Why.** The palette is not committed. Its upstream repository, `bjarneo/omarchy-fireside-theme`, declares no licence, so its `colors.toml` is all rights reserved by default. This repository is public. A mount keeps the palette on the host, where it is already installed. It also makes the editor follow the active Omarchy theme, because the plugin polls the mount every two seconds. The alternative was to convert the palette once and commit a static theme file. That was rejected for the same licence reason. An earlier draft of this change vendored both plugins and pre-wrote their grants, to avoid a clone and a dialog at first run. That was reverted. Both plugins are in the upstream registry, so the panel installs them. The 11 vendored files and the grants file bought only the removal of two clicks.
- **Cost.** Two plugins must be installed by hand after each `just msb rm`, because `~/.config/ttt` is in the VM and not in a volume. Each install asks for approval. Until `omarchy-theme` has run, the theme `omarchy` does not resolve and TTT falls back to its own default. A second read-only host path enters the VM. Every file in it is a color definition, and the folder was scanned for credentials before the mount was added. It also holds generated configs for other apps, and those become readable inside the VM. They are `claude.json`, `pi.json`, `t3code.json`, `spotifast.json`, `hermes.yaml` and `shell.toml`. `plugins.enabled` brings the fetch of the community plugin list at each start. The mount is fixed when the VM is made, so a new host path needs `just msb rm && just msb run`. The host must have Omarchy at that path, or the VM creation fails on the mount.
- **No diagram is possible.** The whole image support of TTT is the setting `image.protocol`, and `internal/config/settings.go` allows it three values: `auto`, `kitty` and `none`. There is no sixel and no iterm2. `foot` 1.28.0 supports sixel and not the Kitty graphics protocol. So no image can appear in this editor, and a fenced `mermaid` block renders as highlighted source. Rendering one would also need a headless Chromium in the VM. The draw.io MCP server, which the VM already has, is the path for a diagram here.
