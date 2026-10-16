# push, pin: publish the built artifact and record it in the stack of the component. Imported by workflow.just; uses build of package.just.

# reads:  out/<name>/manifests.yaml, and only that: the rest of out/<name>/ is helper files
# writes: the registry, and out/<name>/push.json (the tag and digest)
# output: the artifact in the registry as <registry>/<name>:<commit>, with its tag and digest printed. Nothing for a disabled component
# build (which validates), then push the artifact
[script('bash')]
push: build
    set -euo pipefail
    [ -s {{ out }}/manifests.yaml ] || { echo "disabled: nothing to push"; exit 0; }
    flux push artifact {{ registry }}/{{ name }}:{{ tag }} \
      --path {{ out }} \
      --ignore-paths '/*,!/manifests.yaml' \
      --source "$(git remote get-url origin)" \
      --revision "$(git branch --show-current)@sha1:$(git rev-parse HEAD)" \
      --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" \
      --output json \
      | jq --arg tag {{ tag }} '. + {tag: $tag}' \
      | tee {{ out }}/push.json

# reads:  out/values.yaml, flux/stack-entry.yaml of this folder (the contract: never written), the stack of its tier, the other stack (to check
#         dependsOn), and out/<name>/push.json when it exists
# writes: the stack of its tier: sync/<full name>/infra-stack.yaml for platform/addons, app-stack.yaml for the rest
# output: stack-composer (tools/) patches the pair of this component in its stack: the pin of push.json goes into the entry, the entry overrides the
#         fields of the pair (a pair that is not there is added, unpinned when there is no push.json). When the flag is false the pair is removed,
#         so Flux removes its objects, and its pin is gone. It writes only when every check passes: see tools/stack-composer/stack_composer.py
# rollback: git revert the commit
# rollout: record the pushed artifact in the stack
[script('bash')]
pin: _config (tools::_tools 'stack-composer')
    set -euo pipefail
    args=()
    [ ! -f {{ out }}/push.json ] || args+=(--push {{ out }}/push.json)
    # the other stack of the cluster is only read: a Kustomization here can wait for one there (the apps wait for the infrastructure)
    [ ! -f {{ root }}/{{ other_stack }} ] || args+=(--also {{ root }}/{{ other_stack }})
    {{ tools }}/stack-composer/stack-composer ${args[@]+"${args[@]}"} {{ root }}/out/values.yaml {{ name }} {{ justfile_directory() }}/flux/stack-entry.yaml {{ root }}/{{ stack }}
