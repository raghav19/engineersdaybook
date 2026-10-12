# Shared by every component justfile: `import '<../>just/lib.just'`. The component is the folder the justfile sits in; its name is the
# folder name, and the folder name is also the OCIRepository / Kustomization name in clusters/<cluster>/sync/stack.yaml.
#
#   just build      kustomize build of this folder -> out/<name>/, one file per object. This is the artifact.
#   just validate   build, then flux schema validate against the Kubernetes, Flux and ecosystem schemas
#   just push       validate, then push out/<name>/ to the URL its OCIRepository in stack.yaml pulls, tagged with the commit
#   just pin        write the pushed tag and digest into stack.yaml (a developer or agent commits it in a PR)
#
# The plan-style diff (`just diff`) is repo-wide and lives in the root justfile. Only push publishes anything.
set quiet
set lazy
# a recipe this folder does not have (diff, cluster, tests) is looked up in the justfile above, so `just diff` works from here
set fallback
set allow-duplicate-recipes
set shell := ['bash', '-euo', 'pipefail', '-c']

root := parent_directory(source_directory())
name := file_name(justfile_directory())
out := root / 'out' / name
tag := `git log -1 --format=%h --abbrev=12 -- .`

# list the recipes (the default when no recipe is named)
[default]
help:
    just --list

# the artifact: kustomize build of this folder into out/<name>/, one file per object (HelmReleases stay objects)
build:
    rm -rf {{ out }} && mkdir -p {{ out }}
    kustomize build . -o {{ out }}

# build, the component's own `_checks`, then flux schema validate
validate: build _checks
    flux schema validate {{ out }} --schema-location default --schema-location ecosystem --verbose

# no checks by default; a component justfile redefines this one to add its own
_checks:
    true

# validate, then push out/<name>/ as <url in stack.yaml>:<commit>; the tag and digest land in out/<name>.json
[script('bash')]
push cluster='kind': _committed validate
    set -euo pipefail
    url=$(NAME={{ name }} yq -N 'select(.kind == "OCIRepository" and .metadata.name == strenv(NAME)) | .spec.url' \
      {{ root }}/clusters/{{ cluster }}/sync/stack.yaml)
    flux push artifact "$url:{{ tag }}" --path {{ out }} \
      --source "$(git remote get-url origin)" \
      --revision "$(git branch --show-current)@sha1:$(git rev-parse HEAD)" \
      --creds "$GHCR_USER:$GHCR_PUSH_TOKEN" --output json \
      | jq --arg tag {{ tag }} '. + {tag: $tag}' | tee {{ root }}/out/{{ name }}.json

# rollout: write the pushed tag and digest into this component's OCIRepository in stack.yaml (rollback: git revert the commit)
pin cluster='kind':
    test -f {{ root }}/out/{{ name }}.json || { echo "push {{ name }} first" >&2; exit 1; }
    NAME={{ name }} TAG="$(jq -r .tag {{ root }}/out/{{ name }}.json)" DIGEST="$(jq -r .digest {{ root }}/out/{{ name }}.json)" yq -i \
      '(select(.kind == "OCIRepository" and .metadata.name == strenv(NAME)) | .spec.ref) = {"tag": strenv(TAG), "digest": strenv(DIGEST)}' \
      {{ root }}/clusters/{{ cluster }}/sync/stack.yaml

_committed:
    test -z "$(git status --porcelain -- .)" || { echo "commit the source first: the artifact names a commit" >&2; exit 1; }
