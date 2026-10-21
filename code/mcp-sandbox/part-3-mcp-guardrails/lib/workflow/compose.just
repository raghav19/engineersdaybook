# compose-stack: put the artifact that publish-artifact recorded into the stack of the cluster. Imported by workflow.just; uses push of tools/tools.just.

# reads:  out/values.yaml, flux/stack.yaml of this folder (the contract: never written), the stacks of all the groups (to check dependsOn), and out/manifest.yaml when it exists (the pin that the last publish of this component recorded)
# writes: the stack of the group of this component: sync/<full name>/infra/<group>/stack.yaml (the label app.kubernetes.io/part-of of the entry file)
# output: stack-composer (tools/) patches the pair of this component in its stack: the pin of manifest.yaml goes into the entry, the entry overrides the
#         fields of the pair (a pair that is not there is added, unpinned when manifest.yaml has no entry for it). When the flag is false the pair is removed,
#         so Flux removes its objects, and its pin leaves the stack. It writes only when every check passes: see tools/stack-composer/stack_composer.py
# rollback: git revert the commit
# rollout: record the published artifact in the stack
[script('bash')]
compose-stack: _config (push 'stack-composer')
    set -euo pipefail
    args=()
    args+=(--manifest {{ manifest }} --cluster {{ cluster_name }})
    [ -n "{{ group }}" ] || { echo "{{ name }}: flux/stack.yaml needs the label app.kubernetes.io/part-of on its Kustomization" >&2; exit 1; }
    # the other groups: read only, a dependsOn can point into them
    for f in {{ root }}/{{ stacks }}/*/stack.yaml; do [ "$f" = "{{ root }}/{{ stack }}" ] || args+=(--also "$f"); done
    {{ tools }}/stack-composer/stack-composer ${args[@]+"${args[@]}"} {{ root }}/out/values.yaml {{ name }} {{ justfile_directory() }}/flux/stack.yaml {{ root }}/{{ stack }}
