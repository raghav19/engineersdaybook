# Shared by every component justfile: `import '<../>lib/lib.just'`. The component is the folder the justfile sits in; its name is the
# folder name, and the folder name is also the OCIRepository / Kustomization name in clusters/<cluster>/sync/stack.yaml.
#
#   just build      kustomize build of this folder -> out/<name>/, one file per object. This is the artifact.
#   just validate   build, then flux-schema validate against the Kubernetes, Flux and ecosystem schemas
#   just push       validate, then push out/<name>/ to the URL its OCIRepository in stack.yaml pulls, tagged with the commit
#   just pin        write the pushed tag and digest into stack.yaml (a developer or agent commits it in a PR)
#

set quiet
set lazy
set fallback
set allow-duplicate-recipes
set shell := ['bash', '-euo', 'pipefail', '-c']

# VARIABLES
root := parent_directory(source_directory())
name := file_name(justfile_directory())
out := root / 'out' / name
tag := `git log -1 --format=%h --abbrev=12 -- .`
registry := 'oci://ghcr.io/raghav19/mcp-guardrails'
ghcr_user := env('GHCR_USER', 'raghav19')
# note: placeholder-ghcr.io replaced by sbx proxy
ghcr_push_token := env('GHCR_PUSH_TOKEN', 'placeholder-ghcr.io')

# RECIPES
[default]
help:
    just --list

build:
    rm -rf {{ out }} && mkdir -p {{ out }}
    kustomize build . -o {{ out }}

validate: build _checks
    flux-schema validate {{ out }} --schema-location default --schema-location ecosystem --verbose

# validate, then push out/<name>/ as <registry>/<name>:<commit>; 
# the tag and digest land in out/<name>.json
push: validate
    flux push artifact {{ registry }}/{{ name }}:{{ tag }} --path {{ out }} \
      --source "$(git remote get-url origin)" \
      --revision "$(git branch --show-current)@sha1:$(git rev-parse HEAD)" \
      --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" --output json \
      | jq --arg tag {{ tag }} '. + {tag: $tag}' | tee {{ root }}/out/{{ name }}.json

# rollout: write the pushed tag and digest into this component's OCIRepository in stack.yaml 
# rollback: git revert the commit
pin cluster='kind':
    yq -i '(select(.spec.url == "{{ registry }}/{{ name }}") | .spec.ref) = (load("{{ root }}/out/{{ name }}.json") | pick(["tag", "digest"]) | ... style="")' \
      {{ root }}/clusters/{{ cluster }}/sync/stack.yaml

_checks:
    true
