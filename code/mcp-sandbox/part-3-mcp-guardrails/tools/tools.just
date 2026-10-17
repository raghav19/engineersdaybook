# Shared by the justfile of every build function in tools/: `import '../tools.just'`.
#
# A function is a Python script built into one binary (interpreter and PyYAML inside) and pushed as its own artifact,
# <registry>/tools/<name>: one file in the registry, not a container image. Dependencies: tools/pyproject.toml, locked in uv.lock.
#
#   just build   ruff check and format check the script, then the binary, built by uv from uv.lock -> out/tools/<name>/<name>.
#                A binary that is newer than its inputs (the script, model/, pyproject.toml, uv.lock and this file) is not built again.
#   just push    build, push once, then record its tag and digest in out/manifest.yaml (under `tools:`).
#                A binary that the manifest already records is not pushed again.
#   just _tools  build and push the functions that a recipe needs. The first run does the work, and the next runs do nothing.
#                lib/workflow/workflow.just loads this file as the module `tools` and every component recipe runs `tools::_tools`.
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

# the root of part 3 (this file is tools/tools.just)
root := parent_directory(source_directory())
# what `push` (tools) and `publish-artifact` (components, lib/workflow/publish.just) recorded. Local, next to out/values.yaml
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

# reads:  the script of this folder (and its model/ folder, if it has one), tools/pyproject.toml, uv.lock and this file
# writes: out/tools/<name>/<name>
# output: the binary, it runs without Python. Nothing happens when the binary is newer than all of its inputs
# validate the script with ruff, then build the binary from exactly what uv.lock says (--locked fails when pyproject.toml and uv.lock disagree)
[default, script('bash')]
build:
    set -euo pipefail
    inputs=({{ script }} ../pyproject.toml ../uv.lock {{ root }}/tools/tools.just)
    [ ! -d model ] || inputs+=(model)
    if [ -x {{ binary }} ] && [ -z "$(find "${inputs[@]}" -type f -newer {{ binary }})" ]; then exit 0; fi
    {{ uv }} ruff check --quiet {{ script }}
    {{ uv }} ruff format --check --quiet {{ script }}
    {{ uv }} \
      pyinstaller {{ flags }} {{ data }} \
        --name {{ name }} \
        --distpath {{ out }}/{{ name }} \
        --workpath {{ out }}/{{ name }}/work \
        --specpath {{ out }}/{{ name }}/work \
        {{ script }}

# reads:  out/tools/<name>/<name>, and out/manifest.yaml
# writes: the registry, <repo>:sha256-<sha256 of the binary>
# writes: out/manifest.yaml: `tools: <name>: {tag, digest}`. The file is created when it is not there
# output: nothing when the manifest already records this binary: the tag is its sha256, so the same binary is the same tag
# build, push the binary once and record it
[script('bash')]
push: build
    set -euo pipefail
    sha=$(sha256sum {{ binary }} | cut -d' ' -f1)
    tag=sha256-$sha
    if [ -f {{ manifest }} ] && [ "$(N={{ name }} yq '.tools[strenv(N)].tag // ""' {{ manifest }})" = "$tag" ]; then exit 0; fi
    # flux requires a revision; taken from the binary, not from HEAD, so the digest does not change with every commit
    digest=$(flux push artifact {{ repo }}:$tag \
      --path {{ binary }} \
      --reproducible \
      --source {{ source }} \
      --revision binary@sha256:$sha \
      --creds {{ creds }} \
      --output json \
      | jq -r .digest)
    touch {{ manifest }}
    N={{ name }} TAG=$tag DIGEST=$digest \
      yq -i '.tools[strenv(N)] = {"tag": strenv(TAG), "digest": strenv(DIGEST)}' {{ manifest }}
    echo "{{ name }}: $tag $digest"

# build and push the functions (tools/) that a recipe runs: config-builder and value-injector, or the names given
# (`compose-stack` asks for stack-composer, which only it uses). A function that is built and recorded is skipped
[script('bash')]
_tools *names='config-builder value-injector':
    set -euo pipefail
    for function in {{ names }}; do just {{ root }}/tools/$function/push; done
