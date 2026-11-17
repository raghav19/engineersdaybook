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

`fresh-config.json` is a copy of `~/.config/fresh/config.json` on the host. Keep it the same as the host file.

`fresh-plugins.yaml` lists the Fresh packages. The mise task `fresh:plugins` in `image/mise.toml` runs `fresh-plugins.sh`, which installs each one at its pinned commit. The theme `catppuccin-mocha` in the config comes from the `catppuccin` package.
