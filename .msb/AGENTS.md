# msb sandbox image

Guidance for agents working on `.msb/image/`.

## Tool/completion coupling

When adding or removing tools in `image/tools/*.toml`, update the `sandbox:completions` task in `image/mise.toml`.

Each tool has a different completion command. Check `<tool> --help` to find the correct syntax:
- Most tools: `<tool> completion bash`
- Some tools: `<tool> --completions bash` (e.g., `just`)
- Others: `<tool> generate-shell-completion bash` (e.g., `uv`)

The build validates that each completion file is non-empty. A missing or wrong command fails the build.

## LSP server coupling

When adding a language server to `image/tools/lsp.toml`, also add it to `image/configs/editor/ttt-settings.json`:

1. Add an entry under `lsp.servers` with the command and language mappings
2. If the tool is also a formatter, add it under `formatters`

The build validates that each LSP command in `ttt-settings.json` is resolvable. A missing binary fails the build.
