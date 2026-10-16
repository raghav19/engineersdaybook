# push, pin: publish the built artifact and record it in the stack of the component. Imported by workflow.just; uses build of package.just.

# reads:  out/<name>/manifests.yaml, and only that: the rest of out/<name>/ is helper files
# writes: the registry, and out/<name>/push.json (the tag and digest)
# output: the artifact in the registry as <registry>/<name>:<commit>, with its tag and digest printed
# build (which validates), then push the artifact
push: build
    flux push artifact {{ registry }}/{{ name }}:{{ tag }} \
      --path {{ out }} \
      --ignore-paths '/*,!/manifests.yaml' \
      --source "$(git remote get-url origin)" \
      --revision "$(git branch --show-current)@sha1:$(git rev-parse HEAD)" \
      --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" \
      --output json \
      | jq --arg tag {{ tag }} '. + {tag: $tag}' \
      | tee {{ out }}/push.json

# reads:  out/<name>/push.json
# writes: the stack of its tier: sync/<full name>/infra-stack.yaml for platform/addons, app-stack.yaml for the rest
# output: that stack with this component's OCIRepository pointing at the pushed tag and digest
# rollback: git revert the commit
# rollout: record the pushed artifact in the stack
pin:
    yq -i '{{ pin_ref }}' {{ root }}/{{ stack }}
