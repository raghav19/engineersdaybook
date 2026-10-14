# Daemon policy: what the sbx daemon and the MCP gateway inside it may reach. Imported by ../justfile, so the recipe names are `just sandbox <recipe>`.
# The VM's own traffic is the agent policy (../agent/) and is not touched here.
#
#   install-egress    once per machine: pull the squid image (egress/egress.just, which also has start-egress and stop-egress)
#   install-daemon    once per machine (and after editing the unit): install the sbx daemon systemd unit from this repo and point the daemon
#                     at the squid proxy. Installs only, does not start or stop anything
#   start-daemon      start the proxy (start-egress), then the daemon
#   stop-daemon       stop the daemon, then the proxy (this ends running sandboxes)
#   restart-daemon    stop-daemon then start-daemon, e.g. after editing squid.conf
#   install-mcp       register & attach MCP servers to the sandbox

github_app_client_id := 'Iv23liVvjK9IHk8lWmIh'
github_toolsets := 'context,issues,pull_requests,repos'
github_exclude_tools := 'delete_repository,delete_file,merge_pull_request,create_repository,fork_repository'

# Register the MCP servers on the sbx gateway and attach them to the running sandbox
install-mcp: _check-daemon _check-egress
    # register the MCP servers
    sbx mcp add drawio --url https://mcp.draw.io/mcp
    sbx mcp add flux-schema-catalog --url https://schemas.fluxoperator.dev/mcp
    sops -d --extract '["api.githubcopilot.com"]' {{ secrets }} | sbx secret set -f mcp:github:client_secret
    sbx mcp add github --url https://api.githubcopilot.com/mcp/ \
                       --client-id {{ github_app_client_id }} \
                       --no-scope \
                       --callback-port 8765 \
                       --header 'X-MCP-Toolsets: {{ github_toolsets }}' \
                       --header 'X-MCP-Exclude-Tools: {{ github_exclude_tools }}'
    # attach the MCP servers to the running sandbox
    sbx mcp load drawio --sandbox {{ name }}
    sbx mcp load flux-schema-catalog --sandbox {{ name }}
    sbx mcp load github --sandbox {{ name }}

# Once per machine, and again after editing a unit file. Puts the units on the host and points the daemon at the proxy. Installs only: it neither starts
# nor stops anything. Use start-daemon after it (restart-daemon if the daemon was already running, since it reads proxy.daemon at start).
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

# Once per machine. Install the sbx daemon systemd unit from this repo and point the daemon at the squid proxy (does not start or stop it)
install-daemon:
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

# Not run by hand: recipes that need the daemon list it as a dependency, so they stop with a clear message instead of a raw sbx error.
# `sbx daemon status` only reports, it does not start a daemon the way other sbx commands do.
# The output is captured first: `| grep -q` under pipefail can fail the pipeline when grep exits before sbx has finished writing.
_check-daemon:
    status=$(sbx daemon status 2>&1 || true); \
    [[ $status =~ Status:[[:space:]]+[^[:alnum:]]*running ]] || { echo "The sbx daemon is not running. Run: just sandbox start-daemon" >&2; exit 1; }

# Starts the proxy and then the daemon, which sends its own traffic through it. reset-failed clears the start limit that systemd sets after 5 quick
# failures. A failure shows up a second or two after `start` returns, so check once more and print the journal if it is down.
# The reason is in the journal, not in `docker logs` (squid only).

# Start the egress proxy, then the sbx daemon
start-daemon: start-egress
    systemctl --user reset-failed sbx-daemon.service
    systemctl --user start sbx-daemon.service
    sleep 2
    systemctl --user is-active --quiet sbx-daemon.service || { journalctl --user -u sbx-daemon.service -n 20 --no-pager >&2; exit 1; }

# Stops the daemon, then any daemon running outside systemd, then the proxy. This ends running sandboxes. The unit stays enabled, so the daemon comes
# back at the next login or boot unless you also run: systemctl --user disable sbx-daemon

# Stop the sbx daemon, then the egress proxy (ends running sandboxes)
stop-daemon:
    systemctl --user stop sbx-daemon.service
    sbx daemon stop >/dev/null 2>&1 || true # a daemon started outside systemd by an `sbx` call
    just stop-egress

# Stop, then start, the egress proxy and the sbx daemon (e.g. after editing squid.conf; ends running sandboxes)
restart-daemon: stop-daemon
    just start-daemon
