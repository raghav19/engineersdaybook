# Agent module: what the VM receives: the kit, its allowed hosts, the skills, the secrets, the MCP servers and the kubeconfig.
# Loaded by ../justfile as `mod agent`, so the recipe names are `just sandbox agent <recipe>`. Every recipe runs on the host machine, never in the VM.
# The services on the host (the proxy, the daemon, VS Code) are the host module (../host/).

set quiet
set lazy
set shell := ['bash', '-euo', 'pipefail', '-c']

import '../lib/common.just'

github_app_client_id := 'Iv23liVvjK9IHk8lWmIh'
github_toolsets := 'context,issues,pull_requests,repos'
github_exclude_tools := 'delete_repository,delete_file,merge_pull_request,create_repository,fork_repository'

# The kits (kits/<kit>/<kit>.yaml) are published under this repository, one package per kit. The version of a kit is the version: in its descriptor.
kit_registry := 'ghcr.io/raghav19/dev-agent-sandbox'

# The namespaces where the agent may read with the built-in `view` role (kubeconfig-install): `*` for all of them, or a list separated by spaces for a shared
# cluster where the other workloads must stay unreadable. Override with SANDBOX_KUBE_NAMESPACES. `view` reads no Secret in either case.
viewer_namespaces := env('SANDBOX_KUBE_NAMESPACES', '*')
# How long the token in .sbx/kubeconfig lives (kubectl create token --duration). Every `run` writes a new one, so it lapses only when you stay away this long.
kube_token_duration := env('SANDBOX_KUBE_TOKEN_DURATION', '720h')

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

# .env.secrets.json (repo root, SOPS-encrypted to your age key) is shared with the other projects. The host recipes read two env-style keys from it: login reads
# GITHUB_TOKEN (the ghcr.io token) and mcp-install reads GITHUB_APP_CLIENT_SECRET (the client secret of the GitHub App). Neither is injected into the VM.
# A key with a dot in it is a host and a sandbox token: secrets-sync injects it (the key is the host, the value the token). A key without a dot is never
# registered. No such key exists today, so secrets-sync registers nothing. Edit with `sops .env.secrets.json`:
#   { "api.example.com": "the-token", "*.example.org": "another-token" }
# The sbx proxy swaps the placeholder "placeholder-<host>" for the token on requests to that host only (exact, or *.example.com), so the VM uses
# that placeholder wherever it would use the token. The host must also be allowed by the egress rules of the policy kit. set-custom creates or
# updates, so this is safe to run every time. sbx stores the --command and sandboxd runs it outside this shell, hence the absolute sops path; the
# token is never stored in sbx's config. The command has no double quote on purpose: sbx 0.47 saves such a secret empty (see secret-token.sh). A hostname
# pattern must not be expanded by the shell, hence set -f.

# Make the host-keyed tokens in .env.secrets.json (if any) available to the sandbox as sbx custom secrets (run does it)
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
    sops -d --extract '["GITHUB_APP_CLIENT_SECRET"]' {{ secrets }} | sbx secret set -f mcp:github:client_secret
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

# The agent reaches a kind API server (host 127.0.0.1) as host.docker.internal through the sbx proxy, which passes the TLS session through: it cannot read or
# change the request. So the VM needs a real token, in a kubeconfig that the host writes. The policy kit allows localhost:6444, the apiServerPort of Part 3's
# kind-config.yaml. The token is a ServiceAccount token, not the admin certificate, and it can only read. Two recipes, because the parts change at different rates:
#   kubeconfig-install  once per cluster: the read-only RBAC in the cluster. It does not change from run to run.
#   kubeconfig          every run: the file .sbx/kubeconfig, which holds three values that do change: a token (kube_token_duration), the CA (new after
#                       `kind delete` + `kind create`) and the server port. It makes no change in the cluster.
# The file is gitignored: it holds a credential and differs per developer. The host repo is mounted read-only in the VM, so it is
# /run/sandbox/source/.sbx/kubeconfig there, where KUBECONFIG in tools.toml points, and kubectl reads it at every command. tls-server-name is a SAN every kind
# API server certificate has, so the cluster needs no change. Both recipes take the context as the argument, else SANDBOX_KUBE_CONTEXT, else the current
# context of kubectl.

# Once per cluster, and after editing sandbox-viewer.yaml or viewer_namespaces. Create the read-only identity of the sandbox in a kubectl context (default: the current kind one)
kubeconfig-install context=env('SANDBOX_KUBE_CONTEXT', ''): _host-only
    #!/usr/bin/env bash
    set -euo pipefail
    ctx="{{ context }}"
    if [ -z "$ctx" ]; then
      ctx=$(kubectl config current-context 2>/dev/null) || true
      [ -n "$ctx" ] || { echo "kubectl has no current context. Name one: just sandbox agent kubeconfig-install <context>" >&2; exit 1; }
      # The recipe creates RBAC in the cluster, so a context that you did not name must be a local kind cluster, never a remote or shared one.
      [[ $ctx == kind-* ]] || { echo "The current context $ctx is not a kind cluster. Name it to use it: just sandbox agent kubeconfig-install $ctx" >&2; exit 1; }
    fi
    sa=sandbox-viewer
    ns=sandbox-viewer
    k() { kubectl --context "$ctx" "$@"; }
    # sandbox-viewer.yaml has the ServiceAccount and the cluster-wide read rules (no Secrets). The label marks the bindings of this recipe, so a switch between
    # the two modes below, or a namespace that left the list, loses its old binding.
    label=app.kubernetes.io/managed-by=sandbox-viewer
    if [ "{{ viewer_namespaces }}" = "*" ]; then
      wanted=" "
      where="all namespaces"
    else
      wanted=" {{ viewer_namespaces }} "
      where="{{ viewer_namespaces }}"
    fi
    k apply -f {{ sbx_dir }}/agent/sandbox-viewer.yaml > /dev/null
    if [ "{{ viewer_namespaces }}" = "*" ]; then
      # `view` in every namespace, now and later
      k create clusterrolebinding "$sa-view" --clusterrole=view --serviceaccount="$ns:$sa" --dry-run=client -o yaml \
        | k label --local -f - "$label" -o yaml | k apply -f - > /dev/null
    else
      # `view` in each listed namespace only, so the other workloads of a shared cluster stay unreadable
      k delete clusterrolebinding "$sa-view" --ignore-not-found > /dev/null
      for n in {{ viewer_namespaces }}; do
        if k get namespace "$n" > /dev/null 2>&1; then
          k -n "$n" create rolebinding "$sa-view" --clusterrole=view --serviceaccount="$ns:$sa" --dry-run=client -o yaml \
            | k label --local -f - "$label" -o yaml | k apply -f - > /dev/null
        else
          echo "kubeconfig-install: namespace $n is not in $ctx, skipped"
        fi
      done
    fi
    k get rolebinding -A -l "$label" -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' | while read -r n; do
      [[ $wanted == *" $n "* ]] || k -n "$n" delete rolebinding "$sa-view" > /dev/null
    done
    echo "kubeconfig-install: $ctx has the read-only identity $ns/$sa, with view in: $where"

# Write .sbx/kubeconfig for a kubectl context (default: the current one), for the sandbox to read (run does it for a kind context). Needs kubeconfig-install first
kubeconfig context=env('SANDBOX_KUBE_CONTEXT', ''): _host-only
    #!/usr/bin/env bash
    set -euo pipefail
    ctx="{{ context }}"
    [ -n "$ctx" ] || ctx=$(kubectl config current-context 2>/dev/null) || true
    [ -n "$ctx" ] || { echo "kubectl has no current context. Name one: just sandbox agent kubeconfig <context>" >&2; exit 1; }
    sa=sandbox-viewer
    ns=sandbox-viewer
    k() { kubectl --context "$ctx" "$@"; }
    k -n "$ns" get serviceaccount "$sa" > /dev/null 2>&1 \
      || { echo "$ctx has no read-only identity yet. Run once: just sandbox agent kubeconfig-install $ctx" >&2; exit 1; }
    server=$(k config view --minify -o jsonpath='{.clusters[0].cluster.server}')
    tls=""
    if [[ $server == *//127.0.0.1:* ]]; then
      server=${server/\/\/127.0.0.1:/\/\/host.docker.internal:}
      tls="tls-server-name: localhost"
    fi
    ca=$(k config view --minify --raw -o jsonpath='{.clusters[0].cluster.certificate-authority-data}')
    token=$(k -n "$ns" create token "$sa" --duration={{ kube_token_duration }})
    cat > {{ sbx_dir }}/kubeconfig <<EOF
    apiVersion: v1
    kind: Config
    clusters:
    - name: $ctx
      cluster:
        server: $server
        $tls
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
    echo "wrote {{ sbx_dir }}/kubeconfig for $ctx ($server), read-only, token valid {{ kube_token_duration }}"

# run calls this first. Best effort, so a missing or stopped cluster never keeps the sandbox from starting. It uses SANDBOX_KUBE_CONTEXT, else the current
# context of kubectl, and only when that is a kind context (kind-*): a context that you did not name is never a remote or shared one. A new token is written
# at every run, so the CA is always current. A cluster without the read-only identity is skipped with the command that creates it.
_kubeconfig-auto: _host-only
    #!/usr/bin/env bash
    set -u
    ctx="${SANDBOX_KUBE_CONTEXT:-$(kubectl config current-context 2>/dev/null)}" || exit 0
    [ -n "$ctx" ] || exit 0
    if [[ $ctx != kind-* && -z "${SANDBOX_KUBE_CONTEXT:-}" ]]; then
      echo "kubeconfig: the current context $ctx is not a kind cluster, skipped (name it with SANDBOX_KUBE_CONTEXT to use it)"
      exit 0
    fi
    just --justfile "{{ sbx_dir }}/justfile" agent kubeconfig "$ctx" \
      || echo "kubeconfig: $ctx skipped (the sandbox keeps the .sbx/kubeconfig it has, if any)"
