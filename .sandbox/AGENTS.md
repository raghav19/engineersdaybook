# Sandbox image

Guidance for agents working on `.sandbox/agent/image/`.

## Tool/completion coupling

When adding or removing tools in `agent/image/tools/*.toml`, update the `sandbox:completions` task in `agent/image/mise.toml`. Add one line for each tool that has a bash completion. Remove the line of each tool that you remove.

Tools differ in how they print completions. Check `<tool> --help` for the syntax. Examples:
- Most tools: `<tool> completion bash`
- Some tools: `<tool> --completions bash` (e.g., `just`)
- Others: `<tool> generate-shell-completion bash` (e.g., `uv`)
- A few tools use other forms. Read the task for `fd`, `yq`, `flux9s`, `terraform` and `terragrunt`.

## LSP server coupling

When adding a language server to `agent/image/tools/lsp.toml`, also add it to `agent/image/configs/editor/fresh-config.json`:

1. Add an entry to `lsp.<language>`: `{"command": "<tool>", "auto_start": true}`
2. If the tool is also a formatter, add it under `languages.<language>.formatter`

`fresh-config.json` is a copy of `~/.config/fresh/config.json` on the host. Keep it the same as the host file.

`agent/image/configs/editor/fresh-plugins.yaml` lists the Fresh packages. When you add a package, add a key with `kind`, `repo`, `commit` and `subdir`. The mise task `fresh:plugins` in `agent/image/mise.toml` runs `fresh-plugins.sh`, which installs each one at its pinned commit. The theme `catppuccin-mocha` in the config comes from the `catppuccin` package.
