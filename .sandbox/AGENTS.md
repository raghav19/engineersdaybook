# Sandbox image

Guidance for agents working on `.sandbox/image/`.

## Tool/completion coupling

When adding or removing tools in `image/tools/*.toml`, update the `sandbox:completions` task in `image/mise.toml`.

Each tool has a different completion command. Check `<tool> --help` to find the correct syntax:
- Most tools: `<tool> completion bash`
- Some tools: `<tool> --completions bash` (e.g., `just`)
- Others: `<tool> generate-shell-completion bash` (e.g., `uv`)

## LSP server coupling

When adding a language server to `image/tools/lsp.toml`, also add it to `image/configs/editor/fresh-config.json`:

1. Add an entry to the list of the language under `lsp` with the command and `auto_start`
2. If the tool is also a formatter, add it under `languages.<language>.formatter`

`fresh-config.json` and `fresh-plugins.list` are copies of `~/.config/fresh/config.json` and `~/.config/fresh/plugins.list` on the host. Keep them the same as the host files. `fresh-plugins.sh` is a short form of `~/.mise/tasks/fresh/plugins.sh`. It has the kind `theme`, and it skips a package that is at its pinned commit. The list in the image also has one `theme` line for the `catppuccin` package. The theme `catppuccin-mocha` in the config comes from that package.
