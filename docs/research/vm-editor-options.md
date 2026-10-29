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
| `bash-language-server` closes at start: `Fatal process out of memory: Zone` | Fresh limits each server to 50% of system memory. The server loads a WASM parser and needs a large address space. It works alone and with the limit off. We did not find the exact limit type. | `process_limits.enabled = false` for this server |
| `dockerfile-language-server-nodejs` closes: `Cannot read properties of undefined (reading 'scopeUri')` | The server asks for configuration with an empty list. Fresh answers with one item. | Use `docker-language-server` (Docker, Go) |
| `marksman` says `Workspace folder is bogus` | The folder had no `.git`. | None. The clone has `.git`. |
| bash-language-server warns: no `shellcheck` | The tool was not in the image. | Add `shellcheck` to `tools/lsp.toml` |

## 5. Not tested

- The mouse. We drove Fresh with keys in `tmux`. The docs and the source say the mouse works.
- `just msb run` and `just msb edit` against a real VM, and the 4 GB memory of the VM. The host runs these.
- Diagnostics from the Docker server.
- Whether a person who knows VS Code finds the layout familiar enough.

## 6. Risks

- Fresh is at version 0.5.4. Its config keys can change.
- The editor is in a terminal. A terminal without mouse support loses the mouse.
- Fresh can start a language server only in a trusted folder. The first `run` of a new VM asks once.
