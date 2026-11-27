#!/usr/bin/env bash
# The onCreateCommand of ../devcontainer.json: it runs once in each new agent container, as the user agent. ../compose.yaml mounts it read-only.
# Variables: SANDBOX_WORKSPACE and REPO_URL come from ../compose.yaml. SANDBOX_BRANCH is optional (default: the branch of the host checkout).
set -euo pipefail
ws=${SANDBOX_WORKSPACE:?SANDBOX_WORKSPACE is not set}

fail() {
    echo "on-create: $*" >&2
    exit 1
}

# Copy the home files of the image into the home volume. A new image always gives a new container, so each image update reaches the home.
# The image brings ~/.claude/plugins. The rest of the agent state stays: the clone, the rest of .claude, .qwen, .herdr and .cache.
# Trap: -f is required. Git pack files in the plugin checkouts are mode 0444, and cp -a cannot overwrite them.
# Remove the Claude plugins of the old image first, so only the plugins of this image stay.
rm -rf "$HOME/.claude/plugins"
cp -af /usr/share/sandbox/home/. "$HOME/" || fail "could not copy the home skeleton"
mkdir -p "$HOME/.claude" "$HOME/.qwen" "$HOME/.herdr" "$HOME/.cache/terraform-providers" || fail "could not make the folders of the home"

# Clone once. /run/sandbox/source (the .git folder of the host repo) is read-only, so the agent works in its own clone and pushes to GitHub.
if [ ! -d "$ws/.git" ]; then
    git clone --no-hardlinks ${SANDBOX_BRANCH:+--branch "$SANDBOX_BRANCH"} /run/sandbox/source "$ws" || fail "git clone failed (branch: ${SANDBOX_BRANCH:-the default})"
    git -C "$ws" remote set-url origin "$REPO_URL" || fail "could not set origin to $REPO_URL"
fi
(cd "$ws" && prek install --allow-missing-config) || fail "prek install failed"

# Keep the Herdr session in the home volume, so a new container restores the panes.
mkdir -p "$HOME/.config/herdr" "$HOME/.herdr/session-snapshots"
ln -sfn "$HOME/.herdr/session.json" "$HOME/.config/herdr/session.json"
ln -sfn "$HOME/.herdr/session-snapshots" "$HOME/.config/herdr/session-snapshots"

# Link the configs of the tools to /run/sandbox/configs, the read-only mount of ../configs. A tool cannot write through a link: edit the file in ../configs.
# ../configs/starship.toml must equal ~/.config/starship.toml on the host.
c=/run/sandbox/configs
mkdir -p "$HOME/.config/fresh/themes" "$HOME/.config/k9s/skins" || fail "could not make the config folders"
ln -sfn "$c/fresh-config.json" "$HOME/.config/fresh/config.json"
ln -sfn "$c/omarchy-terminal.json" "$HOME/.config/fresh/themes/omarchy-terminal.json"
ln -sfn "$c/herdr-config.toml" "$HOME/.config/herdr/config.toml"
ln -sfn "$c/starship.toml" "$HOME/.config/starship.toml"
ln -sfn "$c/k9s-skin-catppuccin-mocha.yaml" "$HOME/.config/k9s/skins/catppuccin-mocha.yaml"
ln -sfn "$c/k9s-skin-tokyo-night.yaml" "$HOME/.config/k9s/skins/tokyo-night.yaml"
