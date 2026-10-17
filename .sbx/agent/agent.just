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

# The namespaces where the agent may read with the built-in `view` role (kubeconfig). Override with SANDBOX_KUBE_NAMESPACES, a list separated by spaces.
viewer_namespaces := env('SANDBOX_KUBE_NAMESPACES', 'default kube-system flux-system agentgateway-system istio-system istio-ingress spire-system mcp-guardrails')

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

# The agent reaches a kind API server (host 127.0.0.1:6444, the apiServerPort of Part 3's kind-config.yaml) as host.docker.internal through the sbx proxy. The
# policy kit allows localhost:6444 for that. The VM holds no real credential: .sbx/kubeconfig (committed, the same for everyone) has the placeholder
# "placeholder-kube" as its token, and no CA. kubeconfig-install does two things, once per cluster:
#   1. It creates a read-only identity in the cluster: sandbox-viewer.yaml, and the built-in `view` role in each of viewer_namespaces only, so the other
#      workloads of a shared cluster stay unreadable.
#   2. It registers an sbx custom secret for host.docker.internal. The proxy replaces the placeholder with a token that the sbx daemon gets from the host:
#      kube-token.sh runs `kubectl create token` (8 hours), and the daemon runs it again when its cached value is older than 6 hours. The token never
#      enters the VM and never expires there, and no timer is needed.
# Experimental: custom secrets may change between sbx releases. Whether the proxy can reach the API server (it must trust the kind CA) depends on the
# sbx proxy, not on this repo: run kubeconfig-check to find out.

# Once per cluster, and after editing sandbox-viewer.yaml or viewer_namespaces. Create the read-only identity of the sandbox in a kubectl context (default: the current kind one) and register its token source
kubeconfig-install context=env('SANDBOX_KUBE_CONTEXT', ''): _host-only _check-daemon
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
    k apply -f {{ sbx_dir }}/agent/sandbox-viewer.yaml > /dev/null
    # The label marks the bindings of this recipe, so a namespace that left the list loses its binding.
    wanted=" {{ viewer_namespaces }} "
    for n in {{ viewer_namespaces }}; do
      if k get namespace "$n" > /dev/null 2>&1; then
        k -n "$n" create rolebinding "$sa-view" --clusterrole=view --serviceaccount="$ns:$sa" --dry-run=client -o yaml \
          | k label --local -f - app.kubernetes.io/managed-by=sandbox-viewer -o yaml | k apply -f - > /dev/null
      else
        echo "kubeconfig-install: namespace $n is not in $ctx, skipped"
      fi
    done
    k get rolebinding -A -l app.kubernetes.io/managed-by=sandbox-viewer -o jsonpath='{range .items[*]}{.metadata.namespace}{"\n"}{end}' | while read -r n; do
      [[ $wanted == *" $n "* ]] || k -n "$n" delete rolebinding "$sa-view" > /dev/null
    done
    # The stored command has no double quote and an absolute path: sandboxd runs it outside this shell (see kube-token.sh). Global, like secrets-sync: one
    # cluster at a time, and the placeholder means nothing for any other request.
    kubectl_bin=$(command -v kubectl)
    sbx secret set-custom --host host.docker.internal --placeholder placeholder-kube \
      --command "{{ sbx_dir }}/agent/kube-token.sh $kubectl_bin $ctx" --refresh 6h > /dev/null
    echo "kubeconfig-install: $ctx has the read-only identity $ns/$sa, with view in: {{ viewer_namespaces }}"
    echo "kubeconfig-install: the token source is registered. Check it from the sandbox: just sandbox agent kubeconfig-check"

# Run kubectl in the sandbox and say what the result means. Run it after kubeconfig-install, with the sandbox running
kubeconfig-check: _host-only
    #!/usr/bin/env bash
    set -u
    out=$(sbx exec {{ name }} sh -c 'KUBECONFIG=/run/sandbox/source/.sbx/kubeconfig kubectl get namespaces --request-timeout=20s' 2>&1)
    rc=$?
    lower=$(tr 'A-Z' 'a-z' <<< "$out")
    if [ $rc -eq 0 ]; then
      echo "ok: the sandbox reads the cluster with a token that the host mints. Nothing else is needed."
      exit 0
    fi
    echo "$out" | head -5
    echo
    case $lower in
      *x509*)                       echo "x509: the VM does not trust the certificate it got. The proxy passes the TLS session through, or its certificate is not trusted. The placeholder cannot be replaced: this design does not work here." ;;
      *"502"*|*"bad gateway"*)      echo "502: the proxy cannot trust or reach the API server (it must trust the kind CA). This design does not work here." ;;
      *unauthorized*|*"401"*)       echo "401: the TLS session works, but the placeholder was not replaced. Check 'sbx secret ls' for the host.docker.internal secret, and run kubeconfig-install again." ;;
      *forbidden*)                  echo "403: the token works, but the identity cannot read this. Run kubeconfig-install again, or the proxy policy blocks it: 'sbx policy log'." ;;
      *refused*|*timeout*|*"no such host"*|*"i/o timeout"*) echo "network: the cluster is down, or the policy does not allow localhost:6444. Check 'kind get clusters' and 'sbx policy ls'." ;;
      *)                            echo "unknown result: read the lines above." ;;
    esac
    exit 1
