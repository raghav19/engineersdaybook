# The squid proxy the sbx daemon's own traffic goes through (sbx setting proxy.daemon). A plain Docker container from compose.yaml, with no systemd unit of
# its own: Docker's `restart: unless-stopped` keeps it up, and the daemon recipes in ../daemon.just start it first and stop it last. Imported by
# ../../justfile, so the recipe names are `just sandbox <recipe>`.
#
#   install-egress    once per machine: pull the squid image
#   start-egress      start the proxy and wait until it is healthy
#   stop-egress       stop the proxy and remove the container
#
# After editing squid.conf: just sandbox stop-egress start-egress (or restart-daemon). squid reads the file at start.
# Logs:   docker logs -f sbx-daemon-egress   (a line appears when a connection closes, so the MCP servers' long-lived ones show up late)
# Check:  docker ps --filter name=sbx-daemon-egress   healthy

# The rootless Docker socket. DOCKER_HOST is set per directory by mise, so these recipes set it themselves and work from anywhere. Set per command,
# not with `export`, which would reach every recipe of the module.
docker_env := 'DOCKER_HOST=unix://' + env('XDG_RUNTIME_DIR') + '/docker.sock'
compose := docker_env + ' docker compose -f ' + sbx_dir + '/daemon/egress/compose.yaml'

# Once per machine. Pull the squid image for the daemon's egress proxy
install-egress:
    {{ compose }} pull

# Start the squid egress proxy for the sbx daemon and wait until it is healthy
start-egress:
    {{ compose }} up -d --wait

# Stop the squid egress proxy and remove its container
stop-egress:
    {{ compose }} down

# Not run by hand: recipes that need the proxy list it as a dependency, so they stop with a clear message instead of a raw sbx error.
_check-egress:
    [ "$({{ docker_env }} docker inspect -f '{{{{.State.Health.Status}}' sbx-daemon-egress 2>/dev/null)" = healthy ] \
      || { echo "The egress proxy (sbx-daemon-egress) is not running and healthy. Run: just sandbox start-daemon" >&2; exit 1; }
