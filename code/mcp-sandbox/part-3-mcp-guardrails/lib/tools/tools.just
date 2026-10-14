# Shared by the justfile of every build function in lib/tools: `import '../tools.just'`.
#
# A function is a Python script built into one binary (interpreter and PyYAML inside) and pushed as its own artifact,
# <registry>/tools/<name>: one file in the registry, not a container image. Dependencies: lib/tools/pyproject.toml, locked in uv.lock.
#
#   just build   the binary, built by uv from uv.lock -> out/tools/<name>/<name>
#   just push    build, push, then print the line that pins it. Put that line in lib/lib.just.
#
# The digest does not move when nothing changed: the build is deterministic (fixed Python and hash seed, locked dependencies)
# and so is the push (--reproducible), so the same inputs give the same bytes, on any checkout path.

set quiet
set fallback
set shell := ['bash', '-euo', 'pipefail', '-c']

# VARIABLES

name := file_name(justfile_directory())
script := replace(name, '-', '_') + '.py'
pin := replace(name, '-', '_')
out := parent_directory(parent_directory(source_directory())) / 'out' / 'tools'
binary := out / name / name

# Everything that makes the binary the same bytes on every build, so that `push` prints the same digest for the same inputs.
#
# PYTHONHASHSEED  Python gives strings a random hash on every start, which changes the order PyInstaller lists the modules
#                 in the bundle, so two builds of one source differ. A fixed seed gives one order. The value itself does not matter.
# python          the exact release, not 3.13: the interpreter is inside the binary, so another patch release is another binary.
# flags           PyInstaller flags; part of the hash below, so changing them is a new tag.
export PYTHONHASHSEED := '1'
python := '3.13.15'
flags := '--onefile --clean --noconfirm --log-level WARN'

# what the binary is built from, for the tag and the revision. Dependencies come from uv.lock, so they are in the hash through it
inputs := sha256(sha256_file(script) + sha256_file('../pyproject.toml') + sha256_file('../uv.lock') + python + flags)
tag := replace_regex(inputs, '^(.{12}).*', '$1')
# flux requires a revision; taken from the inputs, not from HEAD, so the digest does not change with every commit
revision := 'inputs@sha1:' + replace_regex(inputs, '^(.{40}).*', '$1')

# registry
repo := 'oci://ghcr.io/raghav19/mcp-guardrails/tools/' + name
source := 'https://github.com/raghav19/engineersdaybook'
ghcr_user := env('GHCR_USER', 'raghav19')
# placeholder-ghcr.io is replaced by the sbx proxy
ghcr_push_token := env('GHCR_PUSH_TOKEN', 'placeholder-ghcr.io')
creds := ghcr_user + ':' + ghcr_push_token

# RECIPES

# reads:  the script of this folder, lib/tools/pyproject.toml and uv.lock
# writes: out/tools/<name>/<name>
# output: the binary, it runs without Python
# build the binary with uv, from exactly what uv.lock says (--locked fails when pyproject.toml and uv.lock disagree)
[default]
build:
    uv run \
      --quiet \
      --locked \
      --python {{ python }} \
      --project .. \
      --group build \
      pyinstaller {{ flags }} \
        --name {{ name }} \
        --distpath {{ out }}/{{ name }} \
        --workpath {{ out }}/{{ name }}/work \
        --specpath {{ out }}/{{ name }}/work \
        {{ script }}

# reads:  out/tools/<name>/<name>
# writes: the registry, <repo>:<tag>
# output: the line that pins the artifact, for lib/lib.just
# rollback: git revert the commit of that line
# build, push the binary and print its pin
[script('bash')]
push: build
    set -euo pipefail
    digest=$(flux push artifact {{ repo }}:{{ tag }} \
      --path {{ binary }} \
      --reproducible \
      --source {{ source }} \
      --revision {{ revision }} \
      --creds {{ creds }} \
      --output json \
      | jq -r .digest)
    echo "{{ pin }} := '$digest'"
