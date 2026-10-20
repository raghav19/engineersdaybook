# Agent module: what the VM receives: the skills, the secrets, the MCP servers, the kubeconfig and the kits.
# Loaded by ../justfile as `mod agent`: `just sandbox agent <recipe>`. Every recipe runs on the host, never in the VM. The host services are ../host/.

set quiet
set lazy
set shell := ['bash', '-euo', 'pipefail', '-c']
set script-interpreter := ['bash', '-euo', 'pipefail']

import '../lib/common.just'

github_app_client_id := 'Iv23liVvjK9IHk8lWmIh'
github_toolsets := 'context,issues,pull_requests,repos'
github_exclude_tools := 'delete_repository,delete_file,merge_pull_request,create_repository,fork_repository'

# The kits (kits/<kit>/<kit>.yaml) are one package each under this repository. The version of a kit is the version: in its descriptor.
kit_registry := 'ghcr.io/raghav19/dev-agent-sandbox'

# The hosts of the egress allow list in the policy kit, on one line (allow-hosts)
egress_hosts := shell('yq -r "$1" "$2"', '.capabilities[] | select(.type == "com.docker.sandbox/network-policy@2") | .config.runtime.allow | join(" ")', sbx_dir / 'kits/policy/policy.yaml')

# Once per machine, safe to run again: install the skills, register the ghcr.io secret and the MCP servers
setup: skills-install secrets-sync mcp-register

# Install the agent skills into the sbx store. Every sandbox links the store in read-only at its start
skills-install: _host-only
    sbx skills add --force mattpocock/skills
    sbx skills add --force danyuchn/asd-ste100-skill
    sbx skills add --force jfr992/terragrunt-skill
    sbx skills add --force antonbabenko/agent-plugins
    sbx skills add --force fluxcd/agent-skills
    sbx skills add --force aws/agent-toolkit-for-aws \
      --skill aws-containers --skill aws-compute --skill aws-iam --skill aws-networking \
      --skill aws-security --skill aws-storage --skill aws-auth

# Refresh the skills in the sbx store to the latest upstream version. A sandbox picks them up at its next start
skills-update: _host-only
    sbx skills update

# Maintainer. Build and push the kits (dev-tools and policy, or the ones you name) and pin each digest in sbxenv.yaml.
# No provenance or SBOM: buildx adds new ones at every build, and that changes the digest.
[script]
kit-build *kits: _host-only
    kits="{{ kits }}"
    for kit in ${kits:-dev-tools policy}; do
      dir={{ sbx_dir }}/kits/$kit
      rel=$(realpath --relative-to="{{ repo }}" "$dir")
      epoch=$(git -C "{{ repo }}" log -1 --format=%ct -- "$rel" ":(exclude)$rel/README.md")
      meta=$(mktemp)
      docker buildx build "$dir" -f "$dir/$kit.yaml" \
        -t "{{ kit_registry }}/$kit:$(yq .version "$dir/$kit.yaml")" \
        --provenance=false --sbom=false \
        --build-arg SOURCE_DATE_EPOCH="${epoch:-0}" \
        --output type=registry,compression=zstd,compression-level=9,force-compression=true,rewrite-timestamp=true \
        --metadata-file "$meta"
      export ref="{{ kit_registry }}/$kit" digest=$(jq -r '."containerimage.digest"' "$meta")
      rm -f "$meta"
      export entry="$ref@$digest"
      # yq matches nothing without failing, so grep checks that the pin landed
      yq -i '(.kits[] | select(contains(strenv(ref)))) = strenv(entry) | .kits |= (. + [strenv(entry)] | unique)' {{ sbx_dir }}/sbxenv.yaml
      grep -q "$digest" {{ sbx_dir }}/sbxenv.yaml
      echo "pinned $kit $digest"
    done

# Allow the hosts of the policy kit in the local sbx policy now, without a kit rebuild
[script]
allow-hosts: _host-only
    set -f # no glob expansion of **.istio.io
    for host in {{ egress_hosts }}; do
      sbx policy allow network "$host"
    done

# Make the ghcr.io push token a sbx custom secret. The sbx proxy swaps the placeholder for the Bitwarden secret GITHUB_TOKEN on requests to ghcr.io only
[script]
secrets-sync: _host-only _check-daemon
    # sbx runs the command with no terminal and no mise on its PATH, and the daemon may have another HOME than this shell
    bin_path=$(dirname "$(command -v bws)"):$(dirname "$(command -v jq)"):/usr/bin:/bin
    token_file=${BWS_ACCESS_TOKEN_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/bws/access-token}
    # sbx shows only "exit status 1" when the command fails, so run it here first: its message reaches you and the token goes nowhere
    env PATH="$bin_path" BWS_NO_PROMPT=1 BWS_ACCESS_TOKEN_FILE="$token_file" {{ bws_secret }} GITHUB_TOKEN > /dev/null \
      || { echo "secrets-sync: the command that the daemon would run failed (the message is above)." >&2; exit 1; }
    # no double quote in the command: sbx 0.47 saves such a secret empty
    sbx secret set-custom --host ghcr.io --placeholder placeholder-ghcr.io \
      --command "/usr/bin/env PATH=$bin_path BWS_NO_PROMPT=1 BWS_ACCESS_TOKEN_FILE=$token_file {{ bws_secret }} GITHUB_TOKEN" > /dev/null
    echo "sbx secret placeholder-ghcr.io for ghcr.io"

# Register the MCP servers on the sbx gateway. The GitHub App client secret goes to the sbx secret store, never to the VM
mcp-register: _host-only _check-daemon
    sbx mcp add drawio --url https://mcp.draw.io/mcp
    sbx mcp add flux-schema-catalog --url https://schemas.fluxoperator.dev/mcp
    {{ bws_secret }} GITHUB_APP_CLIENT_SECRET | sbx secret set -f mcp:github:client_secret
    sbx mcp add github --url https://api.githubcopilot.com/mcp/ \
                       --client-id {{ github_app_client_id }} \
                       --no-scope \
                       --callback-port 8765 \
                       --header 'X-MCP-Toolsets: {{ github_toolsets }}' \
                       --header 'X-MCP-Exclude-Tools: {{ github_exclude_tools }}'

# Attach the registered MCP servers to the running sandbox. `run` does it
mcp-load: _host-only _check-daemon
    sbx mcp load drawio --sandbox {{ name }}
    sbx mcp load flux-schema-catalog --sandbox {{ name }}
    sbx mcp load github --sandbox {{ name }}

# Once per cluster, safe to run again: create the sandbox identity in a kind context (default: the current one), then write .sbx/kubeconfig
kube *context: _host-only
    {{ sbx_dir }}/agent/kube.sh install {{ context }}
    {{ sbx_dir }}/agent/kube.sh write {{ context }}

# `run` calls this: a new token and CA for the current kind context (the CA changes after `kind delete`). A failure prints its message and `run` goes on
_kube-refresh: _host-only
    -{{ sbx_dir }}/agent/kube.sh write

# Make a one-time join token for the SPIRE agent in the VM, and the trust bundle, with the SPIRE server of the current kubectl context. SANDBOX_GITHUB_ID is the numeric id of your GitHub account.
# sbxenv.yaml runs the same script before every create and run, so this recipe is only for a manual check
spire-enroll: _host-only
    {{ sbx_dir }}/agent/spire.sh enroll
