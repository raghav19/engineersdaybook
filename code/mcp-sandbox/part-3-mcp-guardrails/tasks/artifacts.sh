#!/usr/bin/env bash
# The artifacts of one cluster against the registry, one chain at a time or all.
#
#   tasks/artifacts.sh list <cluster>             the chains, the folders each renders, what each waits for, the pin
#   tasks/artifacts.sh diff <cluster> [chain]     out/<cluster>/<chain> against the pinned artifact
#   tasks/artifacts.sh push <cluster> [chain]     push the chains whose render differs from the pin, print the digest lines
#   tasks/artifacts.sh pull <cluster> [chain]     pull the pinned artifact to review/<cluster>/<chain>
#
# Run through `task chains`, `task diff`, `task push` and `task review`, which render first where it matters.
# The registry URL and the pin of each chain come from clusters/<cluster>/sync/stack.yaml, the only place that names them.
# The pin is ref.digest. `ref.tag: unpinned` means the chain is not pushed yet.
#
# push needs GHCR_USER and GHCR_PUSH_TOKEN (write:packages) in the environment. Decrypt them only in this process:
#   sops exec-env .env.secrets.json 'task push'
# pull needs a token with read:packages in the same way (GHCR_USER, GHCR_PULL_TOKEN), or a docker login for ghcr.io.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cmd=${1:?usage: artifacts.sh <list|diff|push|pull> <cluster> [chain]}
cluster=${2:?usage: artifacts.sh <list|diff|push|pull> <cluster> [chain]}
only=${3:-}
stack=$root/clusters/$cluster/sync/stack.yaml
out=$root/out/$cluster
review=$root/review/$cluster

[[ -f $stack ]] || { echo "artifacts: $stack not found" >&2; exit 1; }
command -v yq >/dev/null || { echo "artifacts: missing tool yq. Run: mise install" >&2; exit 1; }

mapfile -t all_chains < <(yq -N 'select(.kind == "Kustomization" and .spec.sourceRef.kind == "OCIRepository") | .metadata.name' "$stack")
if [[ -n $only ]]; then
  printf '%s\n' "${all_chains[@]}" | grep -qx "$only" || { echo "artifacts: no chain $only in $stack. Chains: ${all_chains[*]}" >&2; exit 1; }
  chains=("$only")
else
  chains=("${all_chains[@]}")
fi

repo() { yq -N "select(.kind == \"OCIRepository\" and .metadata.name == \"$1\") | .spec.$2" "$stack"; }
digest_of() { local d; d=$(repo "$1" ref.digest); [[ $d == null ]] && d=""; echo "$d"; }
needs_flux() { command -v flux >/dev/null || { echo "artifacts: missing tool flux. Run: mise install" >&2; exit 1; }; }
need_out() { [[ -d $out/$1 ]] || { echo "artifacts: $out/$1 not found. Run: task render CLUSTER=$cluster CHAIN=$1" >&2; exit 1; }; }

case $cmd in
  list)
    printf '%-20s %-52s %-34s %s\n' CHAIN FOLDERS WAITS-FOR PIN
    for c in "${all_chains[@]}"; do
      folders=$(yq -N "select(.kind == \"Kustomization\" and .metadata.name == \"$c\") | .metadata.annotations[\"render.engineersdaybook.dev/folders\"]" "$stack")
      deps=$(yq -N "select(.kind == \"Kustomization\" and .metadata.name == \"$c\") | (.spec.dependsOn // []) | map(.name) | join(\",\")" "$stack")
      d=$(digest_of "$c")
      printf '%-20s %-52s %-34s %s\n' "$c" "$folders" "${deps:--}" "${d:-unpinned}"
    done
    ;;
  diff)
    needs_flux
    status=0
    for c in "${chains[@]}"; do
      need_out "$c"
      url=$(repo "$c" url); d=$(digest_of "$c")
      if [[ -z $d ]]; then echo "== $c: not pinned yet, the whole artifact is new"; continue; fi
      echo "== $c: out/ against $url@$d"
      flux diff artifact "$url@$d" --path "$out/$c" || status=1
    done
    exit $status
    ;;
  push)
    needs_flux
    cd "$root"
    if [[ -n $(git status --porcelain) ]]; then
      echo "artifacts: the working tree is not clean. An artifact names a commit, so commit first." >&2
      exit 1
    fi
    : "${GHCR_USER:?artifacts: set GHCR_USER}" "${GHCR_PUSH_TOKEN:?artifacts: set GHCR_PUSH_TOKEN}"
    hash=$(git rev-parse --short=12 HEAD)
    full=$(git rev-parse HEAD)
    pushed=0
    for c in "${chains[@]}"; do
      need_out "$c"
      url=$(repo "$c" url); d=$(digest_of "$c")
      if [[ -n $d ]] && flux diff artifact "$url@$d" --path "$out/$c" >/dev/null 2>&1; then
        echo "== $c: unchanged against $d, not pushed"
        continue
      fi
      echo "== push $c -> $url:$hash"
      json=$(flux push artifact "$url:$hash" --path "$out/$c" \
        --source "$(git config --get remote.origin.url)" \
        --revision "$(git branch --show-current)@sha1:$full" \
        --creds "$GHCR_USER:$GHCR_PUSH_TOKEN" --output json)
      new=$(jq -r '.digest // empty' <<<"$json")
      [[ -n $new ]] || { echo "artifacts: no digest in the push result: $json" >&2; exit 1; }
      printf '%s\n' "$c  $new  (tag $hash)" >>"$out/.pushed"
      pushed=$((pushed + 1))
    done
    if ((pushed > 0)); then
      echo
      echo "Pushed $pushed artifact(s). In $stack set, for each chain, under its OCIRepository spec.ref (remove the tag line):"
      while read -r c d rest; do echo "  $c:   digest: $d   $rest"; done <"$out/.pushed"
      echo "Commit that change and open the pull request. Nothing applies the artifacts until it merges."
      rm -f "$out/.pushed"
    else
      echo "Nothing changed against the pins. No push."
    fi
    ;;
  pull)
    needs_flux
    for c in "${chains[@]}"; do
      url=$(repo "$c" url); d=$(digest_of "$c")
      [[ -n $d ]] || { echo "artifacts: $c is not pinned yet, nothing to pull" >&2; exit 1; }
      mkdir -p "$review/$c"
      echo "== pull $c $url@$d -> review/$cluster/$c"
      flux pull artifact "$url@$d" --output "$review/$c"
    done
    ;;
  *) echo "usage: artifacts.sh <list|diff|push|pull> <cluster> [chain]" >&2; exit 1 ;;
esac
