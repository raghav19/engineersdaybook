# The pull of the build functions in lib/tools (config-builder, value-injector), the third leg of their life next to `build` and `push` in
# tools.just. Imported by lib.just, because every component build runs the functions: it needs `root`, `registry`, `ghcr_user` and
# `ghcr_push_token` from there.
#
# Each function is its own artifact <registry>/tools/<name>. Their digests are config, not part of this library:
# config/tools/manifest.yaml, from the block `just lib/tools/<name>/push` prints.

tools_manifest := root / 'config' / 'tools' / 'manifest.yaml'
tools := root / 'out' / '.tools'

# reads:  the digests and binary sha256 of config/tools/manifest.yaml, then the registry, only for a digest that is not in out/.tools/ yet
# writes: out/.tools/<name>/<digest>/<name>, and the link out/.tools/<name>/<name> to it
# output: nothing; _config and _apply run the links
# pull the build functions (lib/tools) at the digests the config pins
[script('bash')]
_tools:
    set -euo pipefail
    pull() {
      digest=$(yq -r ".\"$1\".digest // \"\"" {{ tools_manifest }})
      binary=$(yq -r ".\"$1\".binary // \"\"" {{ tools_manifest }})
      [ -n "$digest" ] && [ -n "$binary" ] || { echo "$1 is not pinned in config/tools/manifest.yaml: run 'just lib/tools/$1/push' (host) and put the block it prints there" >&2; exit 1; }
      dir={{ tools }}/$1/${digest#sha256:}
      if [ ! -x "$dir/$1" ]; then
        rm -rf "$dir" && mkdir -p "$dir"
        flux pull artifact {{ registry }}/tools/$1@$digest -o "$dir" \
          --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" >/dev/null 2>&1 \
          || { rm -rf "$dir"; echo "cannot pull {{ registry }}/tools/$1@$digest" >&2; exit 1; }
      fi
      # the pinned sha256 of the binary is checked on every run, not only after a pull
      [ "sha256:$(sha256sum "$dir/$1" | cut -d' ' -f1)" = "$binary" ] \
        || { echo "$1: the binary of $digest is not $binary" >&2; rm -rf "$dir"; exit 1; }
      ln -sfn "${digest#sha256:}/$1" {{ tools }}/$1/$1
    }
    pull config-builder
    pull value-injector
