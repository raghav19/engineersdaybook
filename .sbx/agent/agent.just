# Agent policy: everything that shapes what runs inside the VM (the kit, its egress allow and deny lists, the tools, the skills).
# Imported by ../justfile, so the recipe names are `just sandbox <recipe>`.
#
#   install-skills  once per machine: install the agent skills into the sbx store that every sandbox shares
#   update-skills   refresh the skills the store already has to upstream's latest
#   sync-secrets    set the tokens in .sbx/secrets.json as sbx custom secrets, so the VM can use them without holding them (run does it first)
#   build           maintainer: build the dev-tools kit, push it to ghcr.io and pin its digest in ../sbxenv.yaml
#   allow-egress    host only: allow the hosts of the dev-tools.yaml allow list in the local sbx policy now, without the kit rebuild
#   setup-vscode    write the Remote-SSH and update settings, and the extensions of the recipe, into your host VS Code user settings (run does it first)
#   kubeconfig      host only: write .sbx/kubeconfig, a read-only view of the kind cluster that the sandbox reads through the host repo mount

kit_repo := 'ghcr.io/raghav19/dev-agent-sandbox/dev-tools'
kit_version := '0.1.0'

# The kind cluster the sandbox gets a kubeconfig for: the one that Part 3's kind-config.yaml names
kind_config := repo / 'code/mcp-sandbox/part-3-mcp-guardrails/clusters/kind/kind-config.yaml'
kind_cluster := shell('yq .name "$1"', kind_config)

# The hosts of the egress allow list in dev-tools.yaml, on one line (allow-egress)
egress_hosts := shell('yq -r "$1" "$2"', '.capabilities[] | select(.type == "com.docker.sandbox/network-policy@2") | .config.runtime.allow | join(" ")', sbx_dir / 'agent/dev-tools.yaml')

# sbx has no declarative skills list, so this list is it. --force replaces a skill without asking.

# Once per machine. Install the agent skills into the sbx store, which every sandbox links in read-only at its start
install-skills:
    sbx skills add --force mattpocock/skills
    sbx skills add --force danyuchn/asd-ste100-skill
    sbx skills add --force jfr992/terragrunt-skill
    sbx skills add --force antonbabenko/agent-plugins
    sbx skills add --force fluxcd/agent-skills
    sbx skills add --force aws/agent-toolkit-for-aws \
      --skill aws-containers --skill aws-compute --skill aws-iam --skill aws-networking \
      --skill aws-security --skill aws-storage --skill aws-auth

# Refresh the skills in the sbx store to upstream's latest (a sandbox picks them up on its next start)
update-skills:
    sbx skills update

# The build context is the repo root, so the kit is built from the same files the repo uses. No provenance or SBOM attestation: buildx adds a
# new one on every build, which changed the pushed index digest (and so the pin below) while the image itself stayed identical. The fixed
# SOURCE_DATE_EPOCH with rewrite-timestamp makes a build from scratch give the same digest too (tested: two cold builds, same digest).
# SOURCE_DATE_EPOCH is the time of the last commit that touched a build input, so the image changes only when its inputs do.

# Maintainer. Build and push the dev-tools kit and pin its digest in sbxenv.yaml
build:
    #!/usr/bin/env bash
    set -euo pipefail
    epoch=$(git log -1 --format=%ct -- {{ sbx_dir }}/agent/dev-tools.yaml {{ sbx_dir }}/agent/dev-tools.yaml.dockerignore {{ sbx_dir }}/agent/tools.toml)
    docker buildx build "$(git rev-parse --show-toplevel)" \
      -f {{ sbx_dir }}/agent/dev-tools.yaml \
      -t {{ kit_repo }}:{{ kit_version }} \
      --provenance=false --sbom=false \
      --build-arg SOURCE_DATE_EPOCH="${epoch:-0}" \
      --output type=registry,compression=zstd,compression-level=9,force-compression=true,rewrite-timestamp=true \
      --metadata-file /tmp/dev-tools-push.json
    # The digest comes from buildx's metadata file. yq matches nothing without failing, so grep checks that it landed.
    export digest=$(jq -r '."containerimage.digest"' /tmp/dev-tools-push.json)
    yq -i '(.kits[] | select(contains("dev-tools"))) = "{{ kit_repo }}@" + strenv(digest)' {{ sbx_dir }}/sbxenv.yaml
    grep -q "$digest" {{ sbx_dir }}/sbxenv.yaml
    echo "pinned dev-tools $digest"

# Host only. Allow the hosts of the allow list in dev-tools.yaml in the local sbx policy now, without the kit rebuild (set -f: no glob expansion of **.istio.io)
allow-egress:
    #!/usr/bin/env bash
    set -f -euo pipefail
    for host in {{ egress_hosts }}; do
      sbx policy allow network "$host"
    done

# .sbx/secrets.json is for the sandbox and nothing else: every entry is injected, including the two the host recipes read (login reads ghcr.io, install-mcp reads api.githubcopilot.com).
# One entry per host, the host as the key and the token as the value (edit with `sops .sbx/secrets.json`):
#   { "api.example.com": "the-token", "*.example.org": "another-token" }
# The sbx proxy swaps the placeholder "placeholder-<host>" for the token on requests to that host only (exact, or *.example.com), so the VM uses
# that placeholder wherever it would use the token. The host must also be allowed by the egress rules in dev-tools.yaml. set-custom creates or
# updates, so this is safe to run every time. sbx stores the --command and sandboxd runs it outside this shell, hence the absolute sops path; the
# token is never stored in sbx's config. The command has no double quote on purpose: sbx 0.47 saves such a secret empty (see secret-token.sh). A hostname
# pattern must not be expanded by the shell, hence set -f.

# Make the tokens in .sbx/secrets.json available to the sandbox as sbx custom secrets (run does it first)
sync-secrets: _check-daemon
    #!/usr/bin/env bash
    set -f -euo pipefail
    sops_bin=$(command -v sops)
    file={{ secrets }}
    "$sops_bin" -d "$file" | jq -r 'keys[]' | while read -r host; do
      sbx secret set-custom --host "$host" --placeholder "placeholder-$host" \
        --command "{{ sbx_dir }}/agent/secret-token.sh $sops_bin $host" > /dev/null
      echo "sbx secret placeholder-$host for $host"
    done

# Remote-SSH installs `remote.SSH.defaultExtensions` on the VM when it starts the VS Code server. The recipe sets that list to the static one below, so the
# list on the host is exactly this one (Python gets ty and Ruff only). A server that is already running installs nothing new: it takes a new sandbox, or
# `code --install-extension <id>` in a terminal of the VM. An extension that a VM already has stays until `code --uninstall-extension <id>`.

# Write the Remote-SSH and update settings into your host VS Code user settings (application scope, so a workspace file cannot set them)
setup-vscode:
    #!/usr/bin/env bash
    set -euo pipefail
    f="$HOME/.config/Code/User/settings.json"
    mkdir -p "$(dirname "$f")"
    [ -f "$f" ] || echo '{}' > "$f"
    merged=$(jq '. * {
      "remote.SSH.defaultExtensions": [
        "anthropic.claude-code",
        "astral-sh.ty",
        "charliermarsh.ruff",
        "tamasfe.even-better-toml",
        "kennylong.kubernetes-yaml-formatter",
        "yzhang.markdown-all-in-one",
        "skellock.just",
        "isontheline.vscode-sysmon"
      ],
      "remote.SSH.useExecServer": false,
      "remote.SSH.enableDynamicForwarding": false,
      "remote.SSH.enableAgentForwarding": false,
      "remote.SSH.connectTimeout": 30,
      "remote.SSH.showLoginTerminal": false,
      "remote.SSH.localServerDownload": "always",
      "update.mode": "none",
      "extensions.autoUpdate": "off",
      "extensions.autoCheckUpdates": false
    }' "$f")
    if [ "$merged" != "$(cat "$f")" ]; then echo "$merged" > "$f"; echo "VS Code settings updated in $f (applies to windows opened from now on)"; fi

# The sandbox reaches the kind API server (host 127.0.0.1) as host.docker.internal through the sbx proxy, which needs `sbx policy allow network localhost:<port>`
# once. It holds a ServiceAccount token bound to the built-in `view` role and to `sandbox-viewer-extra` (no Secrets, read-only), not the kind admin
# certificate. `view` has no cluster-scoped kinds and none of the stack's custom resources, so the extra role adds get/list/watch on nodes, volumes,
# storage classes, CSI drivers, CRDs and webhook configurations, and on every resource of the agentgateway.dev, gateway.networking.k8s.io,
# fluxcd.controlplane.io and spire.spiffe.io groups. Nothing can be written, and no Secret can be read: anything that would reach a credential
# (the age key in `sops-age`, `ghcr-pull`, `github-upstream`) stays out. The file is in
# .sbx/kubeconfig (gitignored): the host repo is mounted read-only in the VM, so it is /run/sandbox/source/.sbx/kubeconfig there, where KUBECONFIG
# in tools.toml points. tls-server-name is a SAN every kind API server certificate has, so the cluster needs no change. Run it again after
# `kind delete` + `kind create` (new CA) or when the token (30 days) expires.

# Host only. Write .sbx/kubeconfig: a read-only (view) kubeconfig for the kind cluster, for the sandbox to read (run does it first, when the host has the cluster)
kubeconfig cluster=kind_cluster:
    #!/usr/bin/env bash
    set -euo pipefail
    [ -z "${SANDBOX_NAME:-}" ] || { echo "Run this on the host, not in the sandbox ($SANDBOX_NAME): it needs the host's kind cluster." >&2; exit 1; }
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
_kubeconfig-auto:
    #!/usr/bin/env bash
    set -u
    [ -f "{{ kind_config }}" ] || exit 0
    cluster=$(yq .name "{{ kind_config }}") || exit 0
    contexts=$(kubectl config get-contexts -o name 2>/dev/null) || exit 0
    grep -qx "kind-$cluster" <<< "$contexts" || exit 0
    just --justfile "{{ sbx_dir }}/justfile" kubeconfig "$cluster" \
      || echo "kubeconfig: kind-$cluster is not reachable, skipped (the sandbox keeps the .sbx/kubeconfig it has, if any)"
