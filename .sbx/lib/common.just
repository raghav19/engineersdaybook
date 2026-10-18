# What the sandbox, host and agent modules share. A just module cannot use another module's variables or recipes, so each of the three justfiles imports this
# file. The settings (`set ...`) cannot live here: each module has its own.

sbx_dir := parent_directory(source_directory())
repo := parent_directory(sbx_dir)
# Prints one secret of the Bitwarden project by name (`bws-secret.sh GITHUB_TOKEN`). It asks for the access token unless BWS_ACCESS_TOKEN is set.
bws_secret := sbx_dir / 'agent/bws-secret.sh'
name := shell('yq .name "$1"', sbx_dir / 'sbxenv.yaml')

# The rootless Docker socket. DOCKER_HOST is set per directory by mise, so recipes that call docker set it themselves and work from anywhere. Set per
# command, not with `export`, which would reach every recipe of the module.
docker_env := 'DOCKER_HOST=unix://' + env('XDG_RUNTIME_DIR') + '/docker.sock'

# Every recipe lists this first. All recipes run on the host machine: the sbx daemon, the proxy, Docker and the kind cluster are there, and the VM has none of them.
_host-only:
    [ -z "${SANDBOX_NAME:-}" ] || { echo "Run this on the host, not in the sandbox ($SANDBOX_NAME): the daemon, the proxy and the kind cluster are on the host." >&2; exit 1; }

# Not run by hand: recipes that need the daemon list it as a dependency, so they stop with a clear message instead of a raw sbx error.
# `sbx daemon status` only reports, it does not start a daemon the way other sbx commands do.
# The output is captured first: `| grep -q` under pipefail can fail the pipeline when grep exits before sbx has finished writing.
_check-daemon:
    status=$(sbx daemon status 2>&1 || true); \
    [[ $status =~ Status:[[:space:]]+[^[:alnum:]]*running ]] || { echo "The sbx daemon is not running. Run: just sandbox host daemon-start" >&2; exit 1; }

# Not run by hand: recipes that need the proxy list it as a dependency, so they stop with a clear message instead of a raw sbx error.
_check-proxy:
    [ "$({{ docker_env }} docker inspect -f '{{{{.State.Health.Status}}' sbx-daemon-egress 2>/dev/null)" = healthy ] \
      || { echo "The egress proxy (sbx-daemon-egress) is not running and healthy. Run: just sandbox host daemon-start" >&2; exit 1; }
