# The recipes that build and push a build function of tools/ (config-builder, value-injector, stack-composer).
#
# lib/workflow/workflow.just imports this file, so a recipe of a component depends on it: `_config: (build 'config-builder')`.
# The justfile of each function imports it too (`import '../tools.just'`), so `just tools/<name>/push` works. The argument `tool` is the name of the
# function. It defaults to the folder that the justfile sits in.
#
# A function is a Python script built into one binary (interpreter and PyYAML inside) and pushed as its own artifact,
# <registry>/tools/<name>: one file in the registry, not a container image. Dependencies: pyproject.toml of the function, locked in its uv.lock.
#
#   just build [tool]  ruff check, format check and ty check the script, then the binary, built by uv from uv.lock -> out/tools/<name>/<name>.
#                      PyInstaller keeps a cache in out/tools/<name>/work-<key>: a second build with the same inputs takes under a second.
#   just push [tool]   build, push once, then record its tag and digest in out/manifest.yaml (under `tools:`).
#                      A binary that the manifest already records is not pushed again.
#
# The identity of a function is the sha256 of its binary. The build is deterministic (fixed Python and hash seed, locked
# dependencies), so the same inputs give the same binary, on any checkout path, and the push (--reproducible) the same digest.
# The tag is that sha256, known before the push, so there is one push and one tag.

# the settings and the variables: see lib/workflow/common.just (root, name, manifest, tools, registry, ghcr_user, ghcr_push_token and the ones of the components)
import '../lib/workflow/common.just'

# the exact release, not 3.13: the interpreter is inside the binary, so another patch release is another binary
python := '3.13.15'
# PyInstaller flags; another set is another binary. No --clean: the cache of PyInstaller makes a second build fast, and the binary is the same without it
# --strip           remove the symbol table of libpython and of the compiled modules: nothing reads it at runtime (about 3 MiB less)
# --exclude-module  typer depends on rich, and rich on pygments and markdown_it, but no function uses them: each sets rich_markup_mode=None and
#                   pretty_exceptions_enable=False, so typer never imports rich (about 3 MiB less). A function that turns rich on fails at runtime
flags := '--onefile --noconfirm --log-level WARN --strip --exclude-module rich --exclude-module pygments --exclude-module markdown_it'
source := 'https://github.com/raghav19/engineersdaybook'
creds := ghcr_user + ':' + ghcr_push_token

# PYTHONHASHSEED  Python gives strings a random hash on every start, which changes the order PyInstaller lists the modules in the bundle, so two
#                 builds of one source differ. A fixed seed gives one order. The value itself does not matter. It is set here, not for every recipe.
#
# key             PyInstaller notices an edit of the script, but not a new version of a dependency and not a new Python release: it keeps the old
#                 binary, or mixes the old and the new. So the work folder is named by a key of the Python release, the flags, uv.lock and pyproject.toml.
#                 A change of one of them gives a new folder and a clean build. The same inputs give the same folder and a cached build.
#
# reads:  the script of the function, and its pyproject.toml and uv.lock
# writes: out/tools/<name>/<name>
# output: the binary, it runs without Python
# a build function: validate the script with ruff and ty, then build the binary from exactly what uv.lock says (--locked fails when pyproject.toml and uv.lock disagree)
[script('bash')]
build tool=name:
    set -euo pipefail
    export PYTHONHASHSEED=1
    cd {{ root }}/tools/{{ tool }}
    script={{ replace(tool, '-', '_') }}.py
    key=$(cat <(printf '%s %s' "{{ python }}" "{{ flags }}") uv.lock pyproject.toml | sha256sum | cut -c1-10)
    work={{ tools }}/{{ tool }}/work-$key
    mkdir -p {{ tools }}/{{ tool }}
    find {{ tools }}/{{ tool }} -maxdepth 1 -name 'work*' ! -path "$work" -exec rm -rf {} +
    uv=(uv run --quiet --locked --python {{ python }} --project "$PWD" --group build)
    "${uv[@]}" ruff check --quiet "$script"
    "${uv[@]}" ruff format --check --quiet "$script"
    "${uv[@]}" ty check --quiet "$script"
    "${uv[@]}" pyinstaller {{ flags }} \
      --name {{ tool }} \
      --distpath {{ tools }}/{{ tool }} \
      --workpath "$work" \
      --specpath "$work" \
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
