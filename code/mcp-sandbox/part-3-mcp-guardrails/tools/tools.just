# The recipes that build and push a build function of tools/ (config-builder, value-injector, stack-composer).
#
# lib/workflow/workflow.just imports this file, so a recipe of a component depends on it: `_config: (push 'config-builder')`.
# The justfile of each function imports it too (`import '../tools.just'`), so `just tools/<name>/push` works. The argument `tool` is the name of the
# function. It defaults to the folder that the justfile sits in.
#
# A function is a Python script built into one binary (interpreter and PyYAML inside) and pushed as its own artifact,
# <registry>/tools/<name>: one file in the registry, not a container image. Dependencies: tools/pyproject.toml, locked in uv.lock.
#
#   just build [tool]  ruff check and format check the script, then the binary, built by uv from uv.lock -> out/tools/<name>/<name>.
#                      A binary that is newer than its inputs (the script, model/, pyproject.toml, uv.lock and this file) is not built again.
#   just push [tool]   build, push once, then record its tag and digest in out/manifest.yaml (under `tools:`).
#                      A binary that the manifest already records is not pushed again.
#
# The identity of a function is the sha256 of its binary. The build is deterministic (fixed Python and hash seed, locked
# dependencies), so the same inputs give the same binary, on any checkout path, and the push (--reproducible) the same digest.
# The tag is that sha256, known before the push, so there is one push and one tag.

# the settings and the variables that lib/workflow/workflow.just shares with this file: root, name, manifest, tools, registry, ghcr_user, ghcr_push_token
import '../lib/workflow/common.just'

# the exact release, not 3.13: the interpreter is inside the binary, so another patch release is another binary
python := '3.13.15'
# PyInstaller flags; another set is another binary
flags := '--onefile --clean --noconfirm --log-level WARN'
source := 'https://github.com/raghav19/engineersdaybook'
creds := ghcr_user + ':' + ghcr_push_token

# PYTHONHASHSEED  Python gives strings a random hash on every start, which changes the order PyInstaller lists the modules in the bundle, so two
#                 builds of one source differ. A fixed seed gives one order. The value itself does not matter. It is set here, not for every recipe.
# model/          goes into the binary, when the function has one (PyInstaller reads a relative path from the spec folder, so the path is absolute).
#                 The function and its model are one pinned unit. The contents of the files decide, not their dates and not the folder of the checkout.

# reads:  the script of the function (and its model/ folder, if it has one), tools/pyproject.toml, uv.lock and this file
# writes: out/tools/<name>/<name>
# output: the binary, it runs without Python. Nothing happens when the binary is newer than all of its inputs
# a build function: validate the script with ruff, then build the binary from exactly what uv.lock says (--locked fails when pyproject.toml and uv.lock disagree)
[script('bash')]
build tool=name:
    set -euo pipefail
    export PYTHONHASHSEED=1
    cd {{ root }}/tools/{{ tool }}
    script={{ replace(tool, '-', '_') }}.py
    binary={{ tools }}/{{ tool }}/{{ tool }}
    inputs=("$script" ../pyproject.toml ../uv.lock {{ root }}/tools/tools.just)
    [ ! -d model ] || inputs+=(model)
    if [ -x "$binary" ] && [ -z "$(find "${inputs[@]}" -type f -newer "$binary")" ]; then exit 0; fi
    data=()
    [ ! -d model ] || data=(--add-data "$PWD/model:model")
    uv=(uv run --quiet --locked --python {{ python }} --project {{ root }}/tools --group build)
    "${uv[@]}" ruff check --quiet "$script"
    "${uv[@]}" ruff format --check --quiet "$script"
    "${uv[@]}" pyinstaller {{ flags }} ${data[@]+"${data[@]}"} \
      --name {{ tool }} \
      --distpath {{ tools }}/{{ tool }} \
      --workpath {{ tools }}/{{ tool }}/work \
      --specpath {{ tools }}/{{ tool }}/work \
      "$script"

# reads:  out/tools/<name>/<name>, and out/manifest.yaml
# writes: the registry, <registry>/tools/<name>:sha256-<sha256 of the binary>
# writes: out/manifest.yaml: `tools: <name>: {tag, digest}`. The file is created when it is not there
# output: nothing when the manifest already records this binary: the tag is its sha256, so the same binary is the same tag
# a build function: build it, push the binary once and record it
[script('bash')]
push tool=name: (build tool)
    set -euo pipefail
    binary={{ tools }}/{{ tool }}/{{ tool }}
    sha=$(sha256sum "$binary" | cut -d' ' -f1)
    tag=sha256-$sha
    if [ -f {{ manifest }} ] && [ "$(N={{ tool }} yq '.tools[strenv(N)].tag // ""' {{ manifest }})" = "$tag" ]; then exit 0; fi
    # flux requires a revision; taken from the binary, not from HEAD, so the digest does not change with every commit
    digest=$(flux push artifact {{ registry }}/tools/{{ tool }}:$tag \
      --path "$binary" \
      --reproducible \
      --source {{ source }} \
      --revision binary@sha256:$sha \
      --creds {{ creds }} \
      --output json \
      | jq -r .digest)
    touch {{ manifest }}
    N={{ tool }} TAG=$tag DIGEST=$digest \
      yq -i '.tools[strenv(N)] = {"tag": strenv(TAG), "digest": strenv(DIGEST)}' {{ manifest }}
    echo "{{ tool }}: $tag $digest"
