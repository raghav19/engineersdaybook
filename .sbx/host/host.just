# Host module: the services on the host machine that the sandbox needs: the ghcr.io login, the squid proxy, the sbx daemon and its systemd unit, and VS Code.
# Loaded by ../justfile as `mod host`, so the recipe names are `just sandbox host <recipe>`. Every recipe runs on the host machine, never in the VM.
# The VM's own policy (the kit, its allowed hosts, the MCP servers) is the agent module (../agent/) and is not touched here.
# The picture of how the parts fit is in README.md in this folder.

set quiet
set lazy
set shell := ['bash', '-euo', 'pipefail', '-c']

import '../shared.just'

ghcr_user := env('GHCR_USER', 'raghav19')

# The squid proxy the sbx daemon's own traffic goes through (sbx setting proxy.daemon). A plain Docker container from proxy/compose.yaml, with no
# systemd unit of its own: Docker's `restart: unless-stopped` keeps it up, and the daemon recipes start it first and stop it last.
# After editing proxy/squid.conf: just sandbox host daemon-restart. squid reads the file at start.
# Logs:   docker logs -f sbx-daemon-egress   (a line appears when a connection closes, so the MCP servers' long-lived ones show up late)
# Check:  docker ps --filter name=sbx-daemon-egress   healthy
compose := docker_env + ' docker compose -f ' + sbx_dir + '/host/proxy/compose.yaml'

# Step 1 of 6, once per machine. Log docker and sbx in to ghcr.io with the ghcr.io token in .env.secrets.json (the kit is a private package)
login: _host-only
    token=$(sops -d --extract '["ghcr.io"]' "{{ secrets }}"); \
    printf %s "$token" | docker login ghcr.io -u {{ ghcr_user }} --password-stdin; \
    printf %s "$token" | sbx secret set -f --registry ghcr.io --username {{ ghcr_user }} --password-stdin

# Step 2 of 6, once per machine. Pull the squid image for the daemon's egress proxy
proxy-install: _host-only
    {{ compose }} pull

# Once per machine, and again after editing a unit file. Puts the units on the host and points the daemon at the proxy. Installs only: it neither starts
# nor stops anything. Use daemon-start after it (daemon-restart if the daemon was already running, since it reads proxy.daemon at start).
# The picture of how the parts fit is in README.md in this folder.
#
# Needs (the checks at the top of the recipe): rootless Docker as an enabled user service, linger on so user services start at boot, and sbx installed
# by mise (github:docker/sbx-releases in the root mise.toml; run `mise install`). The daemon unit's ExecStart points into the mise install dir.
#
# What it does, in order:
#   1. copies the unit into ~/.config/systemd/user;
#   2. enables it, so the daemon starts at login or boot;
#   3. sets the sbx setting proxy.daemon to the proxy. Leave `proxy` and `proxy.sandbox` empty, or the VM's traffic goes through squid too.
#      Any `sbx settings` call starts a daemon outside systemd if none is running, so the recipe stops that one again.
# Safe to run again: it re-copies the units from the repo.
#
# Check:  systemctl --user is-enabled sbx-daemon                                                enabled
#         sbx settings get proxy.daemon                                                         http://127.0.0.1:3128 (starts a daemon if none runs)
# Undo:   sbx settings unset proxy.daemon
#         systemctl --user disable --now sbx-daemon.service && rm ~/.config/systemd/user/sbx-daemon.service; systemctl --user daemon-reload
#         then run `sbx daemon start` by hand

# Step 3 of 6, once per machine. Install the sbx daemon systemd unit from this repo and point the daemon at the squid proxy (does not start or stop it)
daemon-install: _host-only
    #!/usr/bin/env bash
    set -euo pipefail
    systemctl --user is-enabled docker.service >/dev/null 2>&1 \
      || { echo "Rootless Docker is not an enabled user service. Run: systemctl --user enable --now docker.service" >&2; exit 1; }
    [[ $(loginctl show-user "$USER" -p Linger) == *yes* ]] \
      || { echo "Linger is off, so user services would not start at boot. Run: loginctl enable-linger $USER" >&2; exit 1; }
    test -x "$HOME/.local/share/mise/installs/github-docker-sbx-releases/latest/sbx" \
      || { echo "sbx is not installed by mise, and the daemon unit runs it from there. Run: mise install" >&2; exit 1; }
    dir="$HOME/.config/systemd/user"
    src="{{ sbx_dir }}/daemon/systemd"
    mkdir -p "$dir"
    cp "$src/sbx-daemon.service" "$dir/sbx-daemon.service"
    systemctl --user daemon-reload
    systemctl --user enable sbx-daemon.service
    sbx settings set proxy.daemon http://127.0.0.1:3128
    # `sbx settings` starts a daemon outside systemd when none runs; stop that one, never the daemon under its unit
    systemctl --user is-active --quiet sbx-daemon.service || sbx daemon stop >/dev/null 2>&1 || true

# Starts the proxy and then the daemon, which sends its own traffic through it. reset-failed clears the start limit that systemd sets after 5 quick
# failures. A failure shows up a second or two after `start` returns, so check once more and print the journal if it is down.
# The reason is in the journal, not in `docker logs` (squid only).

# Step 4 of 6, once per machine and after a stop. Start the egress proxy, then the sbx daemon
daemon-start: _host-only proxy-start
    systemctl --user reset-failed sbx-daemon.service
    systemctl --user start sbx-daemon.service
    sleep 2
    systemctl --user is-active --quiet sbx-daemon.service || { journalctl --user -u sbx-daemon.service -n 20 --no-pager >&2; exit 1; }

# Stops the daemon, then any daemon running outside systemd, then the proxy. This ends running sandboxes. The unit stays enabled, so the daemon comes
# back at the next login or boot unless you also run: systemctl --user disable sbx-daemon

# Stop the sbx daemon, then the egress proxy (ends running sandboxes)
daemon-stop: _host-only && proxy-stop
    systemctl --user stop sbx-daemon.service
    sbx daemon stop >/dev/null 2>&1 || true # a daemon started outside systemd by an `sbx` call

# Stop, then start, the egress proxy and the sbx daemon (e.g. after editing squid.conf; ends running sandboxes)
daemon-restart: _host-only daemon-stop && daemon-start

# Start the squid egress proxy for the sbx daemon and wait until it is healthy
proxy-start: _host-only
    {{ compose }} up -d --wait

# Stop the squid egress proxy and remove its container
proxy-stop: _host-only
    {{ compose }} down

# Remote-SSH installs `remote.SSH.defaultExtensions` on the VM when it starts the VS Code server. The recipe sets that list to the static one below, so the
# list on the host is exactly this one (Python gets ty and Ruff only). A server that is already running installs nothing new: it takes a new sandbox, or
# `code --install-extension <id>` in a terminal of the VM. An extension that a VM already has stays until `code --uninstall-extension <id>`.

# Write the Remote-SSH and update settings into your host VS Code user settings (application scope, so a workspace file cannot set them) (run does it)
vscode-setup: _host-only
    #!/usr/bin/env bash
    set -euo pipefail
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
