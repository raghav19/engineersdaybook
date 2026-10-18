# Host module: the services on the host that the sandbox needs: the ghcr.io login, the sbx daemon and VS Code.
# Loaded by ../justfile as `mod host`: `just sandbox host <recipe>`. Every recipe runs on the host, never in the VM.

set quiet
set lazy
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

import '../lib/common.just'

ghcr_user := env('GHCR_USER', 'raghav19')

# Once per machine, safe to run again: log in, set sbx, install and start the daemon, connect VS Code
setup: login settings-apply daemon-install daemon-start vscode-connect

# Log docker and sbx in to ghcr.io with the Bitwarden secret GITHUB_TOKEN. Every NEW sandbox gets the login (--all-sandboxes)
login: _host-only
    token=$({{ bws_secret }} GITHUB_TOKEN); \
    printf %s "$token" | docker login ghcr.io -u {{ ghcr_user }} --password-stdin; \
    printf %s "$token" | sbx secret set -f --all-sandboxes --registry ghcr.io --username {{ ghcr_user }} --password-stdin

[private]
settings-apply: _host-only
    sbx settings set kit.allowedSources '["docker.io/","ghcr.io/raghav19/dev-agent-sandbox"]'
    sbx settings set ssh.agentForwardingEnabled false

# Install the sbx daemon systemd unit. Starts nothing
[script]
daemon-install: _host-only
    [[ $(loginctl show-user "$USER" -p Linger) == *yes* ]] \
      || { echo "Linger is off, so user services would not start at boot. Run: loginctl enable-linger $USER" >&2; exit 1; }
    test -x "$HOME/.local/share/mise/installs/github-docker-sbx-releases/latest/sbx" \
      || { echo "sbx is not installed by mise, and the daemon unit runs it from there. Run: mise install" >&2; exit 1; }
    mkdir -p "$HOME/.config/systemd/user"
    cp "{{ sbx_dir }}/host/systemd/sbx-daemon.service" "$HOME/.config/systemd/user/"
    systemctl --user daemon-reload
    systemctl --user enable sbx-daemon.service
    # `sbx settings` starts a daemon outside systemd when none runs. Stop that one, never the daemon under its unit.
    systemctl --user is-active --quiet sbx-daemon.service || sbx daemon stop >/dev/null 2>&1 || true

# Start the sbx daemon. Prints the journal if it does not stay up
daemon-start: _host-only
    systemctl --user reset-failed sbx-daemon.service
    systemctl --user start sbx-daemon.service
    sleep 2
    systemctl --user is-active --quiet sbx-daemon.service || { journalctl --user -u sbx-daemon.service -n 20 --no-pager >&2; exit 1; }

# Stop the sbx daemon (ends running sandboxes)
daemon-stop: _host-only
    systemctl --user stop sbx-daemon.service
    sbx daemon stop >/dev/null 2>&1 || true # a daemon that an `sbx` call started outside systemd

# Stop, then start, the sbx daemon (ends running sandboxes)
daemon-restart: _host-only daemon-stop && daemon-start

[private]
vscode-connect: _host-only
    sbx setup ssh
    code --install-extension ms-vscode-remote.remote-ssh

# Write the Remote-SSH and update settings into your host VS Code user settings. `run` does it
[script]
vscode-setup: _host-only
    f="$HOME/.config/Code/User/settings.json"
    mkdir -p "$(dirname "$f")"
    [ -f "$f" ] || echo '{}' > "$f"
    merged=$(jq '. * {
      "remote.SSH.defaultExtensions": [
        "astral-sh.ty",
        "charliermarsh.ruff",
        "tamasfe.even-better-toml",
        "kennylong.kubernetes-yaml-formatter",
        "yzhang.markdown-all-in-one",
        "skellock.just",
        "isontheline.vscode-sysmon"
      ],
      "remote.SSH.useExecServer": false,
      "remote.SSH.enableDynamicForwarding": false,
      "remote.SSH.enableAgentForwarding": false,
      "remote.SSH.connectTimeout": 30,
      "remote.SSH.showLoginTerminal": false,
      "remote.SSH.localServerDownload": "always",
      "update.mode": "none",
      "extensions.autoUpdate": "off",
      "extensions.autoCheckUpdates": false
    }' "$f")
    if [ "$merged" != "$(cat "$f")" ]; then echo "$merged" > "$f"; echo "VS Code settings updated in $f (applies to windows opened from now on)"; fi
