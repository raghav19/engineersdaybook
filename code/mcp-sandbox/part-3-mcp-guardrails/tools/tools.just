# Shared by the justfile of every build function in tools/: `import '../tools.just'`.
#
# A function is a Python script built into one binary (interpreter and PyYAML inside) and pushed as its own artifact,
# <registry>/tools/<name>: one file in the registry, not a container image. Dependencies: tools/pyproject.toml, locked in uv.lock.
#
#   just build   ruff check and format check the script, then the binary, built by uv from uv.lock -> out/tools/<name>/<name>
#   just push    build, push once, then record its digest and binary sha256 in out/manifest.yaml (under `tools:`).
#   just _tools  pull every function at the digest that out/manifest.yaml records -> out/.tools/<name>/<name>.
#                out/ is local: a fresh clone has no record yet, so run `just tools/<name>/push` once (the build is deterministic: same digest).
#                lib/workflow/workflow.just loads this file as the module `tools` and every component build runs `tools::_tools`.
#
# The identity of a function is the sha256 of its binary. The build is deterministic (fixed Python and hash seed, locked
# dependencies), so the same inputs give the same binary, on any checkout path, and the push (--reproducible) the same digest.
# The tag is that sha256, known before the push, so there is one push and one tag.

set quiet
set fallback
set shell := ['bash', '-euo', 'pipefail', '-c']

# VARIABLES

name := file_name(justfile_directory())
script := replace(name, '-', '_') + '.py'
out := parent_directory(source_directory()) / 'out' / 'tools'
binary := out / name / name

# Everything that makes the binary the same bytes on every build, so that `push` prints the same digest for the same inputs.
#
# PYTHONHASHSEED  Python gives strings a random hash on every start, which changes the order PyInstaller lists the modules
#                 in the bundle, so two builds of one source differ. A fixed seed gives one order. The value itself does not matter.
# python          the exact release, not 3.13: the interpreter is inside the binary, so another patch release is another binary.
# flags           PyInstaller flags; another set is another binary.
# data            the folder model/ of a function, when it has one, goes into the binary (PyInstaller reads a relative path from the spec folder,
#                 so the path is absolute). The function and its model are one pinned unit. The binary stays reproducible: the contents of
#                 the files decide, not their dates and not the folder of the checkout.
export PYTHONHASHSEED := '1'
python := '3.13.15'
flags := '--onefile --clean --noconfirm --log-level WARN'
data := if path_exists(justfile_directory() / 'model') == 'true' { '--add-data ' + (justfile_directory() / 'model') + ':model' } else { '' }
# every tool of the build group (pyinstaller, ruff) runs from uv.lock, in the venv of tools/
uv := 'uv run --quiet --locked --python ' + python + ' --project .. --group build'

# the root of part 3 (this file is tools/tools.just) and where a build finds the pulled functions
root := parent_directory(source_directory())
tools := root / 'out' / '.tools'
# what `push` recorded, for the tools and for the components (lib/workflow/push.just). Local, next to out/values.yaml
manifest := root / 'out' / 'manifest.yaml'

# registry
registry := 'oci://ghcr.io/raghav19/mcp-guardrails'
repo := registry + '/tools/' + name
source := 'https://github.com/raghav19/engineersdaybook'
ghcr_user := env('GHCR_USER', 'raghav19')
# placeholder-ghcr.io is replaced by the sbx proxy
ghcr_push_token := env('GHCR_PUSH_TOKEN', 'placeholder-ghcr.io')
creds := ghcr_user + ':' + ghcr_push_token

# RECIPES

# reads:  the script of this folder (and its model/ folder, if it has one), tools/pyproject.toml and uv.lock
# writes: out/tools/<name>/<name>
# output: the binary, it runs without Python
# validate the script with ruff, then build the binary from exactly what uv.lock says (--locked fails when pyproject.toml and uv.lock disagree)
[default]
build:
    {{ uv }} ruff check --quiet {{ script }}
    {{ uv }} ruff format --check --quiet {{ script }}
    {{ uv }} \
      pyinstaller {{ flags }} {{ data }} \
        --name {{ name }} \
        --distpath {{ out }}/{{ name }} \
        --workpath {{ out }}/{{ name }}/work \
        --specpath {{ out }}/{{ name }}/work \
        {{ script }}

# reads:  out/tools/<name>/<name>
# writes: the registry, <repo>:sha256-<sha256 of the binary>
# writes: out/manifest.yaml: `tools: <name>: {digest, binary}`, the digest of the artifact and the sha256 of the binary. The file is created when it is not there
# build, push the binary once and record its pin
[script('bash')]
push: build
    set -euo pipefail
    sha=$(sha256sum {{ binary }} | cut -d' ' -f1)
    # flux requires a revision; taken from the binary, not from HEAD, so the digest does not change with every commit
    digest=$(flux push artifact {{ repo }}:sha256-$sha \
      --path {{ binary }} \
      --reproducible \
      --source {{ source }} \
      --revision binary@sha256:$sha \
      --creds {{ creds }} \
      --output json \
      | jq -r .digest)
    touch {{ manifest }}
    N={{ name }} DIGEST=$digest BINARY=sha256:$sha \
      yq -i '.tools[strenv(N)] = {"digest": strenv(DIGEST), "binary": strenv(BINARY)}' {{ manifest }}
    echo "{{ name }}: $digest"

# reads:  the digests and binary sha256 under `tools:` in out/manifest.yaml, then the registry, only for a digest that is not in out/.tools/ yet
# writes: out/.tools/<name>/<digest>/<name>, and the link out/.tools/<name>/<name> to it
# output: nothing; _config and _apply run the links
# pull the build functions (tools/) at the digests the config pins: config-builder and value-injector, or the names given
# (`compose-stack` asks for stack-composer, which only it uses)
[script('bash')]
_tools *names='config-builder value-injector':
    set -euo pipefail
    pull() {
      digest=""; binary=""
      if [ -f {{ manifest }} ]; then
        digest=$(N=$1 yq '.tools[strenv(N)].digest // ""' {{ manifest }})
        binary=$(N=$1 yq '.tools[strenv(N)].binary // ""' {{ manifest }})
      fi
      [ -n "$digest" ] && [ -n "$binary" ] || { echo "$1 has no pin in out/manifest.yaml: run 'just tools/$1/push' (host), it records the pin" >&2; exit 1; }
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
    for function in {{ names }}; do pull "$function"; done
