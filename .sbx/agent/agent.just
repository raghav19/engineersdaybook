# Agent policy: everything that shapes what runs inside the VM (the kit, its egress allow and deny lists, the tools, the skills).
# Imported by ../justfile, so the recipe names are `just sandbox <recipe>`.
#
#   install-skills  once per machine: install the agent skills into the sbx store that every sandbox shares
#   update-skills   refresh the skills the store already has to upstream's latest
#   sync-secrets    set the tokens in .sbx/secrets.json as sbx custom secrets, so the VM can use them without holding them (run does it first)
#   build           maintainer: build the dev-tools kit, push it to ghcr.io and pin its digest in ../sbxenv.yaml
#   setup-vscode    write the Remote-SSH and update settings into your host VS Code user settings (run does it first)

kit_repo := 'ghcr.io/raghav19/dev-agent-sandbox/dev-tools'
kit_version := '0.1.0'

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

# Write the Remote-SSH and update settings into your host VS Code user settings (application scope, so a workspace file cannot set them)
setup-vscode:
    #!/usr/bin/env bash
    set -euo pipefail
    f="$HOME/.config/Code/User/settings.json"
    mkdir -p "$(dirname "$f")"
    [ -f "$f" ] || echo '{}' > "$f"
    merged=$(jq '. * {
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
