# Agent module: what the VM receives: the kit, its allowed hosts, the skills, the secrets, the MCP servers and the kubeconfig.
# Loaded by ../justfile as `mod agent`, so the recipe names are `just sandbox agent <recipe>`. Every recipe runs on the host machine, never in the VM.
# The services on the host (the proxy, the daemon, VS Code) are the host module (../host/).

set quiet
set lazy
set shell := ['bash', '-euo', 'pipefail', '-c']

import '../shared.just'

github_app_client_id := 'Iv23liVvjK9IHk8lWmIh'
github_toolsets := 'context,issues,pull_requests,repos'
github_exclude_tools := 'delete_repository,delete_file,merge_pull_request,create_repository,fork_repository'

# The kits (kits/<kit>/<kit>.yaml) are published under this repository, one package per kit. The version of a kit is the version: in its descriptor.
kit_registry := 'ghcr.io/raghav19/dev-agent-sandbox'

# The kind cluster the sandbox gets a kubeconfig for: the one that Part 3's kind-config.yaml names
kind_config := repo / 'code/mcp-sandbox/part-3-mcp-guardrails/clusters/kind/kind-config.yaml'
kind_cluster := shell('yq .name "$1"', kind_config)

# The hosts of the egress allow list in the policy kit, on one line (allow-hosts)
egress_hosts := shell('yq -r "$1" "$2"', '.capabilities[] | select(.type == "com.docker.sandbox/network-policy@2") | .config.runtime.allow | join(" ")', sbx_dir / 'kits/policy/policy.yaml')

# sbx has no declarative skills list, so this list is it. --force replaces a skill without asking.

# Step 5 of 6, once per machine. Install the agent skills into the sbx store, which every sandbox links in read-only at its start
skills-install: _host-only
    sbx skills add --force mattpocock/skills
    sbx skills add --force danyuchn/asd-ste100-skill
    sbx skills add --force jfr992/terragrunt-skill
    sbx skills add --force antonbabenko/agent-plugins
    sbx skills add --force fluxcd/agent-skills
    sbx skills add --force aws/agent-toolkit-for-aws \
      --skill aws-containers --skill aws-compute --skill aws-iam --skill aws-networking \
      --skill aws-security --skill aws-storage --skill aws-auth

# Refresh the skills in the sbx store to upstream's latest (a sandbox picks them up on its next start)
skills-update: _host-only
    sbx skills update

# The build context is the folder of the kit, so a build reads only the files of that kit. No provenance or SBOM attestation: buildx adds a
# new one on every build, which changed the pushed index digest (and so the pin below) while the image itself stayed identical. The fixed
# SOURCE_DATE_EPOCH with rewrite-timestamp makes a build from scratch give the same digest too (tested: two cold builds, same digest).
# SOURCE_DATE_EPOCH is the time of the last commit that touched the kit (README.md excluded), so a kit changes only when its own inputs do:
# a new host in the policy kit leaves the digest of dev-tools as it is.

# Maintainer. Build and push the kits (dev-tools, policy; both without a name) and pin each digest in sbxenv.yaml
kit-build *kits: _host-only
    #!/usr/bin/env bash
    set -euo pipefail
    kits="{{ kits }}"
    for kit in ${kits:-dev-tools policy}; do
      dir={{ sbx_dir }}/kits/$kit
      rel=$(realpath --relative-to="{{ repo }}" "$dir")
      version=$(yq .version "$dir/$kit.yaml")
      epoch=$(git -C "{{ repo }}" log -1 --format=%ct -- "$rel" ":(exclude)$rel/README.md")
      docker buildx build "$dir" -f "$dir/$kit.yaml" \
        -t "{{ kit_registry }}/$kit:$version" \
        --provenance=false --sbom=false \
        --build-arg SOURCE_DATE_EPOCH="${epoch:-0}" \
        --output type=registry,compression=zstd,compression-level=9,force-compression=true,rewrite-timestamp=true \
        --metadata-file "/tmp/$kit-push.json"
      # The digest comes from buildx's metadata file. The pin replaces the entry of this kit in sbxenv.yaml, or adds it (unique keeps the order).
      # yq matches nothing without failing, so grep checks that it landed.
      export ref="{{ kit_registry }}/$kit" digest=$(jq -r '."containerimage.digest"' "/tmp/$kit-push.json")
      export entry="$ref@$digest"
      yq -i '(.kits[] | select(contains(strenv(ref)))) = strenv(entry) | .kits |= (. + [strenv(entry)] | unique)' {{ sbx_dir }}/sbxenv.yaml
      grep -q "$digest" {{ sbx_dir }}/sbxenv.yaml
      echo "pinned $kit $digest"
    done

# Allow the hosts of the allow list in the policy kit in the local sbx policy now, without the kit rebuild (set -f: no glob expansion of **.istio.io)
allow-hosts: _host-only
    #!/usr/bin/env bash
    set -f -euo pipefail
    for host in {{ egress_hosts }}; do
      sbx policy allow network "$host"
    done

# .env.secrets.json (repo root, SOPS-encrypted to your age key) holds the tokens of the sandbox next to the env-style secrets of the other projects. A key with a
# dot in it is a host and a sandbox token: it is injected (the key is the host, the value the token), and login reads ghcr.io and mcp-install reads
# api.githubcopilot.com from the same file. A key without a dot (GITHUB_TOKEN) is not for the sandbox and is never registered. Edit with `sops .env.secrets.json`:
#   { "api.example.com": "the-token", "*.example.org": "another-token" }
# The sbx proxy swaps the placeholder "placeholder-<host>" for the token on requests to that host only (exact, or *.example.com), so the VM uses
# that placeholder wherever it would use the token. The host must also be allowed by the egress rules of the policy kit. set-custom creates or
# updates, so this is safe to run every time. sbx stores the --command and sandboxd runs it outside this shell, hence the absolute sops path; the
# token is never stored in sbx's config. The command has no double quote on purpose: sbx 0.47 saves such a secret empty (see secret-token.sh). A hostname
# pattern must not be expanded by the shell, hence set -f.

# Make the sandbox tokens in .env.secrets.json available to the sandbox as sbx custom secrets (run does it)
secrets-sync: _host-only _check-daemon
    #!/usr/bin/env bash
    set -f -euo pipefail
    sops_bin=$(command -v sops)
    file={{ secrets }}
    "$sops_bin" -d "$file" | jq -r 'keys[] | select(contains("."))' | while read -r host; do
      sbx secret set-custom --host "$host" --placeholder "placeholder-$host" \
        --command "{{ sbx_dir }}/agent/secret-token.sh $sops_bin $host" > /dev/null
      echo "sbx secret placeholder-$host for $host"
    done

# Register the MCP servers on the sbx gateway and attach them to the running sandbox (run does it)
mcp-install: _host-only _check-daemon _check-proxy
    # register the MCP servers
    sbx mcp add drawio --url https://mcp.draw.io/mcp
    sbx mcp add flux-schema-catalog --url https://schemas.fluxoperator.dev/mcp
    sops -d --extract '["api.githubcopilot.com"]' {{ secrets }} | sbx secret set -f mcp:github:client_secret
    sbx mcp add github --url https://api.githubcopilot.com/mcp/ \
                       --client-id {{ github_app_client_id }} \
                       --no-scope \
                       --callback-port 8765 \
                       --header 'X-MCP-Toolsets: {{ github_toolsets }}' \
                       --header 'X-MCP-Exclude-Tools: {{ github_exclude_tools }}'
    # attach the MCP servers to the running sandbox
    sbx mcp load drawio --sandbox {{ name }}
    sbx mcp load flux-schema-catalog --sandbox {{ name }}
    sbx mcp load github --sandbox {{ name }}

# The sandbox reaches the kind API server (host 127.0.0.1) as host.docker.internal through the sbx proxy, which needs `sbx policy allow network localhost:<port>`
# once. It holds a ServiceAccount token bound to the built-in `view` role and to `sandbox-viewer-extra` (no Secrets, read-only), not the kind admin
# certificate. `view` has no cluster-scoped kinds and none of the stack's custom resources, so the extra role adds get/list/watch on nodes, volumes,
# storage classes, CSI drivers, CRDs and webhook configurations, and on every resource of the agentgateway.dev, gateway.networking.k8s.io,
# fluxcd.controlplane.io and spire.spiffe.io groups. Nothing can be written, and no Secret can be read: anything that would reach a credential
# (the age key in `sops-age`, `ghcr-pull`, `github-upstream`) stays out. The file is in
# .sbx/kubeconfig (gitignored): the host repo is mounted read-only in the VM, so it is /run/sandbox/source/.sbx/kubeconfig there, where KUBECONFIG
# in tools.toml points. tls-server-name is a SAN every kind API server certificate has, so the cluster needs no change. Run it again after
# `kind delete` + `kind create` (new CA) or when the token (30 days) expires.

# Write .sbx/kubeconfig: a read-only (view) kubeconfig for the kind cluster, for the sandbox to read (run does it, when the host has the cluster)
kubeconfig cluster=kind_cluster: _host-only
    #!/usr/bin/env bash
    set -euo pipefail
    ctx=kind-{{ cluster }}
    sa=sandbox-viewer
    kubectl --context "$ctx" -n default create serviceaccount "$sa" --dry-run=client -o yaml | kubectl --context "$ctx" apply -f - > /dev/null
    kubectl --context "$ctx" create clusterrolebinding "$sa" --clusterrole=view --serviceaccount="default:$sa" --dry-run=client -o yaml \
      | kubectl --context "$ctx" apply -f - > /dev/null
    kubectl --context "$ctx" apply -f - > /dev/null <<YAML
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRole
    metadata:
      name: $sa-extra
    rules:
      - apiGroups: [""]
        resources: [nodes, persistentvolumes]
        verbs: [get, list, watch]
      - apiGroups: [storage.k8s.io]
        resources: [storageclasses, csidrivers]
        verbs: [get, list, watch]
      - apiGroups: [apiextensions.k8s.io]
        resources: [customresourcedefinitions]
        verbs: [get, list, watch]
      - apiGroups: [admissionregistration.k8s.io]
        resources: [validatingwebhookconfigurations, mutatingwebhookconfigurations]
        verbs: [get, list, watch]
      - apiGroups: [gateway.networking.k8s.io, agentgateway.dev, fluxcd.controlplane.io, spire.spiffe.io]
        resources: ["*"]
        verbs: [get, list, watch]
    ---
    apiVersion: rbac.authorization.k8s.io/v1
    kind: ClusterRoleBinding
    metadata:
      name: $sa-extra
    roleRef:
      apiGroup: rbac.authorization.k8s.io
      kind: ClusterRole
      name: $sa-extra
    subjects:
      - kind: ServiceAccount
        name: $sa
        namespace: default
    YAML
    server=$(kubectl --context "$ctx" config view --minify -o jsonpath='{.clusters[0].cluster.server}' | sed 's#//127\.0\.0\.1:#//host.docker.internal:#')
    ca=$(kubectl --context "$ctx" config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    token=$(kubectl --context "$ctx" -n default create token "$sa" --duration=720h)
    cat > {{ sbx_dir }}/kubeconfig <<EOF
    apiVersion: v1
    kind: Config
    clusters:
    - name: $ctx
      cluster:
        server: $server
        tls-server-name: localhost
        certificate-authority-data: $ca
    users:
    - name: $sa
      user:
        token: $token
    contexts:
    - name: $ctx
      context:
        cluster: $ctx
        user: $sa
    current-context: $ctx
    EOF
    echo "wrote {{ sbx_dir }}/kubeconfig for $ctx ($server), read-only, token valid 30 days"

# run calls this first. Best effort, so a missing or stopped cluster never keeps the sandbox from starting: no kind-config.yaml or no kubectl context for
# its cluster on this host is skipped silently, an unreachable cluster with one line. A new token is written at every run, so the CA is always current.
_kubeconfig-auto: _host-only
    #!/usr/bin/env bash
    set -u
    [ -f "{{ kind_config }}" ] || exit 0
    cluster=$(yq .name "{{ kind_config }}") || exit 0
    contexts=$(kubectl config get-contexts -o name 2>/dev/null) || exit 0
    grep -qx "kind-$cluster" <<< "$contexts" || exit 0
    just --justfile "{{ sbx_dir }}/justfile" agent kubeconfig "$cluster" \
      || echo "kubeconfig: kind-$cluster is not reachable, skipped (the sandbox keeps the .sbx/kubeconfig it has, if any)"
