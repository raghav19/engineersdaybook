# publish-artifact: publish the packaged artifact and record it in out/manifest.yaml. Imported by workflow.just; uses package-artifact of package.just.

# reads:  out/<name>/manifests.yaml, and only that: the rest of out/<name>/ is helper files
# writes: the registry, and out/manifest.yaml: the tag and digest of this component, under `components:` and the name of the cluster
# output: the artifact in the registry as <registry>/<name>:<commit>, with its tag and digest printed. Nothing for a disabled component
# package-artifact (which validates), then publish the artifact
[script('bash')]
publish-artifact: package-artifact
    set -euo pipefail
    [ -s {{ out }}/manifests.yaml ] || { echo "disabled: nothing to publish"; exit 0; }
    result=$(flux push artifact {{ registry }}/{{ name }}:{{ tag }} \
      --path {{ out }} \
      --ignore-paths '/*,!/manifests.yaml' \
      --source "$(git remote get-url origin)" \
      --revision "${GITHUB_HEAD_REF:-$(git branch --show-current)}@sha1:$(git rev-parse HEAD)" \
      --creds "{{ ghcr_user }}:{{ ghcr_push_token }}" \
      --output json)
    digest=$(jq -r .digest <<<"$result")
    # one assignment: it adds the entry or replaces the one of the last publish. The file is created when it is not there.
    touch {{ manifest }}
    C={{ cluster_name }} N={{ name }} TAG={{ tag }} DIGEST=$digest \
      yq -i '.components[strenv(C)][strenv(N)] = {"tag": strenv(TAG), "digest": strenv(DIGEST)}' {{ manifest }}
    echo "{{ name }}: {{ tag }} $digest"
