# The editor for the msb sandbox: Fresh

Question: Which light editor replaces VS Code in the msb sandbox? It must have mouse support and no vim modes. It must use these language servers: ty, ruff, terraform-ls, yaml-language-server, taplo, marksman, bash-language-server, a Docker server and just-lsp.

Source: the repositories and docs of each editor, read on 2026-10-29. Fresh `v0.5.4` (released 2026-10-20) was run in the image of the sandbox. Style: ASD-STE100, STE-flavored mode.

Evidence tags: **documented** means the docs say it. **source** means the code says it. **measured** means we ran it on 2026-10-29.

## Verdict

1. Use Fresh. It runs in the VM, has menus, tabs, a file explorer and the mouse, and has no modes.
2. One file, `fresh-config.json`, says which language server starts for which language. No plugin code is in the repo.
3. Eight of nine languages show diagnostics in Fresh. The Dockerfile server starts but we saw no diagnostics.
4. Two servers needed a change. See section 4.

## 1. The candidates

| Editor | Where it runs | Mouse | Modes | LSP | Result |
|---|---|---|---|---|---|
| Fresh (Rust, GPL-3.0) | VM, terminal | Yes, menu bar, file explorer | None | Built in, many servers for one language | **Chosen** |
| Zed (Rust, GPL-3.0 and others) | Host window, server in VM | Yes | None | ty and ruff built in. Terraform, TOML, Dockerfile and just need extensions | Not tested. Heavier, needs the SSH link and the remote server |
| Helix (Rust, MPL-2.0) | VM, terminal | Yes, basic (on by default) | Modal | Built in for all nine servers | Not chosen. Modal, and the release is from 2025-07 |
| Lapce (Rust, Apache-2.0) | Host window, proxy in VM | Yes | None | Only through WASM plugins. We would need our own plugin | Not chosen. Needs plugin code in the repo |
| micro (Go, MIT) | VM, terminal | Yes | None | None built in | Not chosen |
| Emacs `-nw` (GPL-3.0) | VM, terminal | Yes | None | Built in (eglot). No taplo and no just-lsp in its defaults | Not chosen. Large, not barebones |

Sources: `docs.helix-editor.com/languages.html` and `languages.toml` (Helix); `zed.dev/docs/remote-development`, `/languages/python`, `/languages` (Zed); `github.com/sinelaw/fresh` README and `docs/features/lsp.md` (Fresh); `lapce/lapce` source (Lapce); `emacs-mirror/emacs` `eglot.el`.

## 2. How Fresh is configured

| Claim | Tag | Source |
|---|---|---|
| The config file is `~/.config/fresh/config.json`. `lsp.<language>` holds a list of servers with `command`, `args`, `auto_start`, `root_markers`, `process_limits` and other keys. | documented, measured | `docs/features/lsp.md`, `plugins/config-schema.json`, `fresh --cmd config show` |
| A user list replaces the default list of that language. Other languages keep their defaults. | measured | `fresh --cmd config show` listed our nine servers |
| Fresh has built-in entries for pylsp, terraform-ls, yaml-language-server, taplo, marksman and bash-language-server. It has none for ty, ruff, a Docker server or just-lsp. | source | `crates/fresh-editor-core/src/config.rs` |
| A folder with executable markers (for example `Cargo.toml`) starts as Restricted. Language servers do not run until you trust the folder (`T`). | documented | `docs/features/workspace-trust.md` |
| Fresh answers a `workspace/configuration` request from the `initialization_options` of the server. It gives `null` for an unknown section and one item for an empty request. | source | `services/lsp/async_handler.rs` (`resolve_workspace_configuration`) |
| Each server has a memory limit of 50% of system memory and a CPU limit of 90%, on Linux. | documented | `plugins/config-schema.json` (`ProcessLimits`) |
| `theme = "terminal"` uses the colors of the terminal (`Default` and the ANSI names), so Fresh follows the theme of the host terminal, for example Omarchy Solitude through `foot`. | documented, source | `docs/features/themes.md`, `themes/terminal.json` |
| `terminal.shell = {"command": "/bin/bash", "args": ["--login", "-i"]}` sets the shell of the terminal in the dock. Unset, Fresh uses `$SHELL`. | documented | `docs/features/terminal.md` (Shell Override) |
| `active_keybinding_map = "vscode"` changes only 4 keys of the default map (`Ctrl+D`, `Ctrl+/`, `Ctrl+Shift+K`, `Ctrl+G`). Other VS Code keys are custom entries in `keybindings`. | source | `keymaps/vscode.json`, `plugins/config-schema.json` |
| Fresh turns on the kitty keyboard protocol, so `Ctrl+Shift+<letter>`, `Ctrl+Tab` and `` Ctrl+` `` work in a terminal that supports it. `foot` 1.28 does. | source, documented | `services/terminal_modes.rs`, `man foot-ctlseqs` |
| There is no config key or flag for workspace trust. Fresh keeps the decision in `<data_dir>/workspaces/<path with / as _>/trust.json` as `{"level": "trusted"}` (also in the file that the key `T` writes, measured in the VM). Without the file Fresh asks. With it Fresh opens `Trusted` and does not ask (measured). `sandbox-boot` writes the file for the clone. | source, measured | `services/workspace_trust.rs` (`TrustStore`) |
| `Ctrl+H` cannot replace VS Code's replace key: a terminal sends Backspace for it. | inferred | |

## 3. Measured in the image

The image is `docker buildx build --target final` of this branch. We ran Fresh in `tmux` as the user `agent` and opened one file for each language.

| File | Server | Result in the diagnostics panel |
|---|---|---|
| `a.py` | ty and ruff | `[E]` ty: `Literal["a"]` is not assignable to `int`. `[W]` ruff: `os` imported but unused. |
| `main.tf` | terraform-ls | `[E]` Unclosed configuration block |
| `justfile` | just-lsp | `[E]` Variable `undefined_var` not found |
| `a.yaml` | yaml-language-server | `[E]` Flow sequence must end with a `]` |
| `bad.toml` | taplo | `[E]` expected value, `[E]` expected `]` |
| `notes.md` | marksman | `[W]` Link to non-existent document (the folder must be a git repository) |
| `s.sh` | bash-language-server and shellcheck | `[I]` Double quote to prevent globbing, `[W]` x is referenced but not assigned |
| `Dockerfile` | docker-language-server | Status `LSP (dockerfile) ready`. No diagnostics for an unknown instruction or a deprecated `MAINTAINER`. |

Fresh sends the language id `bash`, `terraform` and so on from its own language names. Terraform works with no shim. Under Lapce it needed one.

## 4. What did not work first

| Problem | Cause | Fix |
|---|---|---|
| `bash-language-server` closes at start: `Fatal process out of memory: Zone` | Fresh limits each server to 50% of system memory (an address-space limit). The server loads a WASM parser and needs a large address space. It works alone and with the limit off. | `process_limits.enabled = false` for this server |
| `dockerfile-language-server-nodejs` closes: `Cannot read properties of undefined (reading 'scopeUri')` | The server asks for configuration with an empty list. Fresh answers with one item. | Use `docker-language-server` (Docker, Go) |
| `marksman` says `Workspace folder is bogus` | The folder had no `.git`. | None. The clone has `.git`. |
| bash-language-server warns: no `shellcheck` | The tool was not in the image. | Add `shellcheck` to `tools/lsp.toml` |
| The editor froze after about 14 minutes in the VM. The shell of the VM was alive, the server of Fresh was idle, and 446 bytes of keystrokes waited unread | `msb exec` (msb 0.7.10) stops passing output after about 1 MB, with or without a terminal. Fresh, `less` and plain `cat` all stopped near 1 MB. Fresh sat in a `write()` to its terminal. | `edit` and `shell` use ssh (`msb ssh serve --stdio` as ProxyCommand), as VS Code did. See section 5 |
| Fresh tried the X11 clipboard at start and logged `X11 server connection timed out` after 47 seconds | The VM has no display server. | `clipboard.use_system_clipboard = false`. Copy uses OSC 52 (the clipboard of the host terminal). We did not prove that this call blocks the editor. |
| `marksman` crashed with `Could not load file or assembly 'FSharpPlus'` on `README.md` and on `AGENTS.md`, then Fresh stopped trying (cooldown) | Fresh limits each server to 50% of system memory (`ulimit -v`, 1970 MB in the 4 GB VM). .NET needs more address space, and the failed reservation shows as a missing file. With the cap, the server exits before `initialize`. Without it, it starts. Same cause as the bash server above. | `process_limits.enabled = false` for this server too |

## 5. The transport: `msb exec` against ssh

Test: a host pty runs the command, and we count the output that arrives. The VM and the file are the same for all runs (`cat` of a 2.7 MB file, four times).

| Route | Result |
|---|---|
| `msb exec -t` | Stops at about 1.0 MB. The command never finishes. |
| `msb exec` (no terminal) | Stops at about 1.0 MB. |
| `ssh -t` through `msb ssh serve --stdio` | All output arrives in 0.1 s. |
| Fresh in `msb exec -t`, key storm (PageDown) | Froze after 560 presses and 0.74 MB. |
| `less` in `msb exec -t`, same storm | Froze after 440 presses and 0.79 MB. |
| Fresh in `ssh -t`, same storm, 2400 presses | No freeze. |

We did not find the cause inside msb. The host `msb exec` process was idle (0% CPU) and the guest process waited in `write()`.

## 6. Trimming Fresh

Fresh loads its bundled features as plugins, and `plugins.<name>.enabled = false` turns one off (documented in the config schema). Test: Fresh opens one 900-line Python file in a container, no language server, idle after 12 seconds.

| Config | Memory (RSS) | Plugins started |
|---|---|---|
| Default | 79–85 MB | 49 |
| `auto_attach = false` only | 84 MB | 49 |
| + 9 agent plugins off (`agent_*`, `orchestrator`, `live_sessions`) | 67 MB | 40 |
| + `dashboard`, `welcome`, `welcome_screen` off (the config of this branch) | 63 MB | 37 |
| + 14 more off (`k8s-workspace`, `devcontainer`, `code-tour`, `audit_mode`, `vi_mode`, `theme_editor`, `compare_files`, `env-manager`, `flash`, and 5 language helpers) | 50–51 MB | 23 |

The agent plugins are not an AI assistant. They list and rejoin sessions of Claude Code and Codex that already run. For comparison, termide (no switches for its agent, database viewer or SFTP) used 49 MB, and Helix used 22 MB, in the same test.

## 7. Theme and colors

The `terminal` theme paints with ANSI color names, and the terminal maps them to its own palette. In Omarchy Solitude (`foot`) the palette is almost gray, so the names lose their meaning.

| Item | Old (`terminal` theme, Solitude palette) | New (`solitude.json`) |
|---|---|---|
| Added line | `Green` = `#9fa5a9` (gray) | `#1a4c2e` (green), 6.1:1 with the text |
| Removed line | `Red` = `#565d60` (gray) | `#5c2226` (red), 7.6:1 with the text |
| Keyword | `Red` = `#565d60`, 2.8:1 on the background | `#de6145`, 5.2:1 |
| Comment | `DarkGray` = `#4b4e55`, 2.2:1 | `#8b9296`, 5.9:1 |
| Text | `#cacccc` on `#101315`, 11.6:1 | the same |

Fresh uses 24-bit color only if `COLORTERM` is `truecolor` or `24bit` (`color_support.rs`). ssh does not send `COLORTERM` to the VM, so Fresh used 256 colors. Measured: Fresh in a container, Review Diff open. With `COLORTERM=truecolor` it sent the exact backgrounds `16;19;21` (editor), `26;76;46` (added) and `92;34;38` (removed). Without it, it sent only 256-palette indices, such as 232 for the editor background. The `edit` recipe now sets `COLORTERM=truecolor`.

The theme was generated from the `dark` theme of Fresh: the grays moved onto the Solitude ramp, and every named color (`Red`, `Yellow`, ...) replaced by an exact RGB value. The text colors were raised until each had at least 4.5:1 contrast.

## 8. Memory of the sandbox

Test: a new VM with 2 GB (same image, no swap), loaded like a heavy session. "Used" is `MemTotal - MemAvailable`, so the page cache is not counted.

| Step | Used |
|---|---|
| Idle VM (kernel and shell) | 110 MB |
| + Headroom proxy | 413 MB |
| + Fresh editor with 3 files | 527 MB |
| + all nine language servers at once | 721 MB |
| + `claude` started, no prompt | 777 MB (peak 810 MB, 40% of 2027 MB) |

All processes stayed alive. The test did not cover a long `claude` session, container builds or large Terraform plans. The sandbox has 3 GB so that these have room. On the host, one VM process held 1.37 GB (4 GB VM, after 9 minutes) and the 2 GB test VM held 1.23 GB after the load, because the file cache of the guest stays resident.

## 9. Not tested

- The mouse. We drove Fresh with keys in `tmux`. The docs and the source say the mouse works.
- `just msb run` and `just msb edit` against a real VM, and the 4 GB memory of the VM. The host runs these.
- Diagnostics from the Docker server.
- Whether a person who knows VS Code finds the layout familiar enough.

## 10. Risks

- Fresh is at version 0.5.4. Its config keys can change.
- The editor is in a terminal. A terminal without mouse support loses the mouse.
- Fresh can start a language server only in a trusted folder. The first `run` of a new VM asks once.
