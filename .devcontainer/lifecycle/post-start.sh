#!/usr/bin/env bash
# The postStartCommand of ../devcontainer.json: it runs after each start of the agent container, as the user agent. ../compose.yaml mounts it read-only.
# It writes the shell setup and the bash completions into the home volume, then the ready file for the healthcheck in ../compose.yaml.
set -euo pipefail

# The shell setup. ~/.bashrc of Debian loads ~/.bash_aliases. The script writes the file again at each start, so the lines never add up.
# The alias k is kubectl with completion. The alias tu is the launcher of the token usage plugin of Herdr. Herdr writes it at each start.
cat >"$HOME/.bash_aliases" <<'EOF'
eval "$(mise activate bash)"
eval "$(starship init bash)"
eval "$(fzf --bash)"
alias k=kubectl
. "$COMPLETIONS_DIR/kubectl" && complete -F __start_kubectl k
alias tu=~/.local/state/herdr/plugins/pseudovar.token-usage/bin/tu
EOF

# The bash completions of the tools in ../agent/tools/*.toml. Add one line for each new tool that has a completion.
mkdir -p "$COMPLETIONS_DIR"
kubectl completion bash >"$COMPLETIONS_DIR/kubectl"
helm completion bash >"$COMPLETIONS_DIR/helm"
kustomize completion bash >"$COMPLETIONS_DIR/kustomize"
k9s completion bash >"$COMPLETIONS_DIR/k9s"
fd --gen-completions bash >"$COMPLETIONS_DIR/fd"
flux completion bash >"$COMPLETIONS_DIR/flux"
just --completions bash >"$COMPLETIONS_DIR/just"
yq shell-completion bash >"$COMPLETIONS_DIR/yq"
herdr completion bash >"$COMPLETIONS_DIR/herdr"
docker completion bash >"$COMPLETIONS_DIR/docker"
crane completion bash >"$COMPLETIONS_DIR/crane"
uv generate-shell-completion bash >"$COMPLETIONS_DIR/uv"
gitleaks completion bash >"$COMPLETIONS_DIR/gitleaks"
flux9s completions bash >"$COMPLETIONS_DIR/flux9s"
starship completions bash >"$COMPLETIONS_DIR/starship"
echo complete -C terraform terraform >"$COMPLETIONS_DIR/terraform"
echo complete -C terragrunt terragrunt >"$COMPLETIONS_DIR/terragrunt"

# The healthcheck in ../compose.yaml waits for this file. /tmp is a tmpfs, so a restart empties it.
touch /tmp/sandbox-ready
