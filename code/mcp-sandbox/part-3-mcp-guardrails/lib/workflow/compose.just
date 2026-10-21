# compose-stack: put the artifact that publish-artifact recorded into the stack of the cluster. Imported by workflow.just; uses push of tools/tools.just.

# reads:  out/values.yaml, flux/stack.yaml of this folder (the contract: never written), the stacks of both apps (to check dependsOn), and out/manifest.yaml when it exists (the pin that the last publish of this component recorded)
# writes: the stack of the app of this component: sync/<full name>/infra/<app>/stack.yaml (addons, or policies for platform/policies/)
# output: stack-composer (tools/) patches the pair of this component in its stack: the pin of manifest.yaml goes into the entry, the entry overrides the
#         fields of the pair (a pair that is not there is added, unpinned when manifest.yaml has no entry for it). When the flag is false the pair is removed,
#         so Flux removes its objects, and its pin leaves the stack. It writes only when every check passes: see tools/stack-composer/stack_composer.py
# rollback: git revert the commit
# rollout: record the published artifact in the stack
[script('bash')]
compose-stack: _config (push 'stack-composer')
    set -euo pipefail
    args=()
    args+=(--manifest {{ manifest }} --cluster {{ cluster_name }} --also {{ root }}/{{ other_stack }})
    {{ tools }}/stack-composer/stack-composer ${args[@]+"${args[@]}"} {{ root }}/out/values.yaml {{ name }} {{ justfile_directory() }}/flux/stack.yaml {{ root }}/{{ stack }}
