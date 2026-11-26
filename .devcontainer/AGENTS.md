# Sandbox image

Guidance for agents working on `.devcontainer/agent/`.

## Tool/completion coupling

When adding or removing tools in `agent/tools/*.toml`, update the completions in `agent/post-start.sh`. Add one line for each tool that has a bash completion. Remove the line of each tool that you remove.

Tools differ in how they print completions. Check `<tool> --help` for the syntax. Examples:
- Most tools: `<tool> completion bash`
- Some tools: `<tool> --completions bash` (e.g., `just`)
- Others: `<tool> generate-shell-completion bash` (e.g., `uv`)
- A few tools use other forms. Read the lines for `fd`, `yq`, `flux9s`, `terraform` and `terragrunt`.

## LSP server coupling

When adding a language server to `agent/tools/lsp.toml`, also add it to `agent/configs/editor/fresh-config.json`:

1. Add an entry to `lsp.<language>`: `{"command": "<tool>", "auto_start": true}`
2. If the tool is also a formatter, add it under `languages.<language>.formatter`

`fresh-config.json` is a copy of `~/.config/fresh/config.json` on the host. Keep it the same as the host file.

The Fresh packages step in `agent/Dockerfile` lists the Fresh packages and installs each one at its pinned commit. When you add a package, add a row with `name`, `kind`, `repo`, `commit` and `subdir`.

## Fresh theme

`fresh-config.json` sets `"theme": "omarchy-terminal.json"`. Keep this value, and keep the same value in `~/.config/fresh/config.json` on the host. The theme extends the built-in `terminal` theme. It takes its colors from the ANSI palette of the terminal, so it follows each Omarchy theme on the host and in the sandbox.
