# Lapce as the editor of the msb sandbox

Question: Can Lapce replace VS Code for the msb sandbox? Which settings and which installs does it need? How do the language servers start?

Source: Lapce `v0.4.6` (released 2026-01-21), its source at `github.com/lapce/lapce`, `github.com/lapce/lapce-plugin-rust`, `docs.lapce.dev` and `plugins.lapce.dev`. Research date: 2026-10-29. Style: ASD-STE100, STE-flavored mode.

Evidence tags: **documented** means the docs say it. **source** means the code says it. **measured** means we ran it on 2026-10-29. Paths are in `lapce/lapce`.

## Verdict

1. Yes. Lapce works with a VM that has no `sshd`. The window runs on the host. Only `lapce-proxy` runs in the VM.
2. Lapce has no setting for a language server. A language server starts from a volt (a WASM plugin).
3. No volt exists for ty, bash, Docker or just. The volts for Terraform, YAML and TOML are archived.
4. One small volt can start any program. We build it once and give it one `volt.toml` for each server.
5. Lapce sends an empty language id for `.tf` files. terraform-ls then gives no hover, completion or symbols. A small script fixes this.
6. The version of Lapce on the host and the version of the proxy must be equal.

## 1. VS Code compared with Lapce

| Item | VS Code | Lapce | Tag | Source |
|---|---|---|---|---|
| Where the parts run | Window on host. Server and extensions in VM. | Window on host. `lapce-proxy` in VM. | documented | `docs.lapce.dev` (remote development) |
| SSH link | `remote.SSH.configFile` and a ProxyCommand. | Runs `ssh [-p port] user@host`. Reads no SSH config of its own. | source | `lapce-app/src/proxy/ssh.rs` |
| Host key | Setting in the SSH config. | Cannot answer a new-key question. The key must be in `known_hosts`. | source | `ssh.rs` (no `-o StrictHostKeyChecking`) |
| Proxy install | VS Code downloads its server. | Runs `proxy --version`. If it differs, downloads and uploads the proxy. | source | `lapce-app/src/proxy/remote.rs`, `extra/proxy.sh` |
| Proxy path in VM | `~/.vscode-server` | `~/.local/share/lapce-stable/proxy/lapce` | source | `remote.rs`, `lapce-core/src/directory.rs` |
| Extensions | Marketplace, 7 extensions in `msb.py`. | Volts in `~/.local/share/lapce-stable/plugins/<folder>/`. | source | `lapce-proxy/src/plugin/wasi.rs` (`find_all_volts`) |
| Settings file | `Code/User/settings.json` | `~/.config/lapce-stable/settings.toml` | source | `extra/schemas/settings.json` |
| Open a folder | `code --folder-uri` | Not on a remote. In the Lapce terminal, run `lapce <folder>`. | documented | `docs.lapce.dev` (remote development) |
| Authentication | Any | SSH key only. | documented | `docs.lapce.dev` |

## 2. How a language server starts

| Claim | Tag | Source |
|---|---|---|
| `settings.toml` allows only `core`, `editor`, `terminal`, `ui` and the two theme keys, plus one free table for each volt. There is no table for a language server. | source | `extra/schemas/settings.json`, `lapce-app/src/config.rs` (`plugins` with `serde(flatten)`) |
| A volt is a folder with `volt.toml` and a `.wasm` file. Its code calls `start_lsp(server_uri, args, document_selector, options)`. | source | `lapce-plugin-rust/src/lib.rs` |
| `start_lsp` accepts `file:` (an absolute path) and `urn:` (a command name). Any other scheme fails. | source | `lapce-proxy/src/plugin/lsp.rs` (`LspClient::new`) |
| Lapce loads each folder of `plugins/` that has a `volt.toml`. It needs no registry. | source | `wasi.rs` (`find_all_volts`, `load_volt`) |
| `volt.toml` may have other tables. Lapce ignores them. The module reads `/volt.toml` because Lapce gives the volt folder to the module as `/`. | source, measured | `lapce-rpc/src/plugin.rs` (no `deny_unknown_fields`), `wasi.rs` (preopen) |
| The settings of a volt reach its module as `initialization_options`. The key in `settings.toml` is the `name` of the volt. | source | `lapce-proxy/src/plugin/catalog.rs`, `wasi.rs` |

## 3. Volts that exist

| Language | Volt | Last change | Use it? |
|---|---|---|---|
| Python types | none for ty | | No. Our volt starts `ty server`. |
| Python lint | `lapce-ruff-lsp` (ruff-lsp) | 2022-12 | No. Our volt starts `ruff server`. |
| Terraform | `lapce-terraform-ls` | 2024-02 (archived) | No. |
| YAML, TOML | `lapce-yaml`, `lapce-toml` | 2022 (archived) | No. |
| Markdown | `lapce-markdown` (marksman) | 2023-07 | No. |
| bash, Dockerfile, just | none | | No. Our volt starts the server. |

Source: `plugins.lapce.dev/api/v1/plugins?q=<name>` and the repository of each volt, 2026-10-29.

## 4. Measured on the host (Lapce 0.4.6, isolated config)

| Test | Result |
|---|---|
| Checksums of `lapce-linux-amd64.tar.gz` and `lapce-proxy-linux-x86_64.gz` | Equal to the digests in the GitHub release. |
| Lapce loads our volts from `plugins/`, with no registry. `ty server`, `ruff server` and `terraform-ls serve` start when a `.py` and a `.tf` file open. | Yes. |
| `languageId` in `didOpen` | `.py` gives `python`. `.tf` gives an empty string. The strings of the proxy binary have no id for Terraform or just. |
| terraform-ls with an empty id: document symbols, hover, completion | All three fail with `no feature found for language` (2 of 2 runs). |
| terraform-ls with the id `terraform` | All three work (2 of 2 runs). |
| terraform-ls through `lsp-langid`, empty id from the client | All three work (3 of 3 runs). |
| terraform-ls diagnostics with an empty id | They appear after an edit (`didChange`), 5 of 5 runs. They do not appear after `didOpen` alone. terraform-ls has a race here, also with the correct id (2 of 6 runs). |
| just-lsp with an empty id | Diagnostics. just-lsp needs no fix. |
| `msb ssh serve --host 127.0.0.1 --port 2222` | `ssh` and `scp` work. `scp` fails for a relative path. Use the baked proxy. |
| `lapce-proxy 0.4.6` in the VM | Runs. Prints `Lapce-proxy 0.4.6`. |

## 5. Measured in the image build

| Test | Result |
|---|---|
| `docker buildx build --target lsp` (terraform-ls, taplo, marksman, just-lsp, three npm servers) | Builds. |
| An LSP `initialize` request to each of the seven servers | All answer with `capabilities`. marksman needs `DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=1` because the image has no ICU library. |
| `--target lapce-proxy` and `--target lapce-volts` | Build. Nine volt folders. |

## 6. Not tested

- The click path in the Lapce window (remote icon, SSH host, `lapce <folder>`). A person must test it.
- The full image (`just msb build`) and the digest pin. The host runs these.
- Hover, completion and diagnostics in the Lapce window for each server.
- `lsp-langid` in the VM. It starts with `uv run --script`. The first start fills the uv cache.

## 7. Risks

- Lapce changes slowly, and `lapce-plugin` has had no change since 2024-08. A new Lapce can break the volt.
- Two versions must match: Lapce on the host and `LAPCE_VERSION` in the Dockerfile.
- `run` adds one line to `~/.ssh/known_hosts`.
