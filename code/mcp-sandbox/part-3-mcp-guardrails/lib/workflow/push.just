# push, compose-stack: publish the packaged artifact and record it in the stack of the component. Imported by workflow.just; uses package-artifact of package.just.

# reads:  out/<name>/manifests.yaml, and only that: the rest of out/<name>/ is helper files
# writes: the registry, and out/manifest.yaml: the tag and digest of this component, under `components:` and the name of the cluster
# output: the artifact in the registry as <registry>/<name>:<commit>, with its tag and digest printed. Nothing for a disabled component
# package-artifact (which validates), then push the artifact
[script('bash')]
push: package-artifact
    set -euo pipefail
    [ -s {{ out }}/manifests.yaml ] || { echo "disabled: nothing to push"; exit 0; }
    result=$(flux push artifact {{ registry }}/{{ name }}:{{ tag }} \
      --path {{ out }} \
      --ignore-paths '/*,!/manifests.yaml' \
      --source "$(git remote get-url origin)" \
      --revision "$(git branch --show-current)@sha1:$(git rev-parse HEAD)" \
      --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" \
      --output json)
    digest=$(jq -r .digest <<<"$result")
    # one assignment: it adds the entry or replaces the one of the last push. The file is created when it is not there.
    touch {{ manifest }}
    C={{ cluster_name }} N={{ name }} TAG={{ tag }} DIGEST=$digest \
      yq -i '.components[strenv(C)][strenv(N)] = {"tag": strenv(TAG), "digest": strenv(DIGEST)}' {{ manifest }}
    echo "{{ name }}: {{ tag }} $digest"

# reads:  out/values.yaml, flux/stack.yaml of this folder (the contract: never written), the stack of the cluster (to check dependsOn), and out/manifest.yaml when it exists (the pin that the last push of this component recorded)
# writes: the stack of the cluster: sync/<full name>/infra-stack.yaml
# output: stack-composer (tools/) patches the pair of this component in its stack: the pin of manifest.yaml goes into the entry, the entry overrides the
#         fields of the pair (a pair that is not there is added, unpinned when manifest.yaml has no entry for it). When the flag is false the pair is removed,
#         so Flux removes its objects, and its pin leaves the stack. It writes only when every check passes: see tools/stack-composer/stack_composer.py
# rollback: git revert the commit
# rollout: record the pushed artifact in the stack
[script('bash')]
compose-stack: _config (tools::_tools 'stack-composer')
    set -euo pipefail
    args=()
    args+=(--manifest {{ manifest }} --cluster {{ cluster_name }})
    {{ tools }}/stack-composer/stack-composer ${args[@]+"${args[@]}"} {{ root }}/out/values.yaml {{ name }} {{ justfile_directory() }}/flux/stack.yaml {{ root }}/{{ stack }}
