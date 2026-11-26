#!/usr/bin/env bash
# The onCreateCommand of ../devcontainer.json: it runs once in each new agent container, as the user agent. It fills the home volume and makes the clone.
# Variables: SANDBOX_WORKSPACE and REPO_URL come from ../compose.yaml. SANDBOX_BRANCH is optional (default: the branch of the host checkout).
set -euo pipefail
ws=${SANDBOX_WORKSPACE:?SANDBOX_WORKSPACE is not set}

fail() {
    echo "on-create: $*" >&2
    exit 1
}

# Copy the home files of the image into the home volume. A new image always gives a new container, so each image update reaches the home.
# The folders of the agent stay: the clone, .claude, .qwen, .herdr and .cache.
# Trap: -f is required. Git pack files in the plugin checkouts are mode 0444, and cp -a cannot overwrite them.
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

# Install the Claude Code plugins into the home volume. A failure prints a warning and does not stop the script.
claude plugin marketplace add DietrichGebert/ponytail#v5.3.2 && claude plugin install ponytail@ponytail ||
    echo "on-create: warning: the ponytail plugin is not installed" >&2
claude plugin marketplace add /home/agent/token-economizer && claude plugin install tokeneconomizer@tokeneconomizer ||
    echo "on-create: warning: the TokenEconomizer plugin is not installed" >&2
