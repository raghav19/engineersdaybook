#!/usr/bin/env bash
# Render the artifacts of one cluster: one folder of rendered manifests per chain of the cluster stack.
#
#   tasks/render.sh <cluster> [chain]      writes out/<cluster>/<chain>/<kind>-<name>.yaml
#
# Run through `task render CLUSTER=<cluster> [CHAIN=<chain>]`. Needs kustomize, helm, yq, jq and kubeconform (mise install).
# The stack (clusters/<cluster>/sync/stack.yaml) is the only list: each chain Kustomization that reads an OCIRepository names the folders
# it renders in the annotation render.engineersdaybook.dev/folders. A chain without that source (secrets) is not rendered.
#
# Steps, each one stops the run on failure:
#   1. stack         every chain names folders, and the folders exist
#   2. values        every key of the merged ConfigMap mcp-values is read by a wiring rule (values/wiring); show where each value comes from
#   3. versions      the agentgateway CRD chart and the controller chart have the same tag
#   4. render        per chain: stage 1 kustomize build of each folder, stage 2 values + wiring + chain label; no Secret, no ciphertext
#   5. preview       helm template of every HelmRelease, for review, under out/<cluster>/.preview/<chain>/ (never pushed, never applied)
#   6. schemas       every rendered object against the core schemas and against the CRDs (Gateway API, agentgateway), unknown fields as errors
#
# The charts are installed by Flux (HelmRelease), so the artifact holds the HelmRelease and its OCIRepository, not the chart output.
# The preview renders the same chart, version and values with helm. It is evidence for a reviewer, not the applied bytes.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cluster=${1:?usage: render.sh <cluster> [chain]}
only=${2:-}
overlay=$root/clusters/$cluster
stack=$overlay/sync/stack.yaml
out=$root/out/$cluster
chain_label='chain.engineersdaybook.dev/name'
folders_key='render.engineersdaybook.dev/folders'
values_name=mcp-values

[[ -f $stack ]] || { echo "render: $stack not found" >&2; exit 1; }
for t in kustomize helm yq jq kubeconform; do
  command -v "$t" >/dev/null || { echo "render: missing tool $t. Run: mise install" >&2; exit 1; }
done

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
rel() { realpath -m --relative-to="$1" "$2"; }

# --- 1. stack --------------------------------------------------------------------------------------------------------------------------
echo "== 1. stack $cluster"
mapfile -t all_chains < <(yq -N 'select(.kind == "Kustomization" and .spec.sourceRef.kind == "OCIRepository") | .metadata.name' "$stack")
((${#all_chains[@]} > 0)) || { echo "render: no chain with an OCIRepository source in $stack" >&2; exit 1; }
folders_of() { yq -N "select(.kind == \"Kustomization\" and .metadata.name == \"$1\") | .metadata.annotations[\"$folders_key\"]" "$stack"; }
for c in "${all_chains[@]}"; do
  f=$(folders_of "$c")
  [[ -n $f && $f != null ]] || { echo "render: chain $c has no annotation $folders_key in $stack" >&2; exit 1; }
  for d in $f; do
    [[ -f $root/$d/kustomization.yaml ]] || { echo "render: chain $c: $d has no kustomization.yaml" >&2; exit 1; }
  done
done
if [[ -n $only ]]; then
  printf '%s\n' "${all_chains[@]}" | grep -qx "$only" \
    || { echo "render: no chain $only in $stack. Chains: ${all_chains[*]}" >&2; exit 1; }
  chains=("$only")
else
  chains=("${all_chains[@]}")
fi
echo "   ${#chains[@]} of ${#all_chains[@]} chains: ${chains[*]}"

# --- 2. values -------------------------------------------------------------------------------------------------------------------------
# kustomize is the merge engine: fleet (values/), then this cluster's values.env. The wiring file is the list of valid keys.
# Each chain gets the same two inputs in its temporary root, so the values are one object for the whole cluster.
write_root() { # dir [wiring yes|no]
  local dir=$1 wiring=${2:-yes}
  mkdir -p "$dir"
  cp "$overlay/values.env" "$dir/values.env"
  {
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo "resources:"
    [[ -f $dir/in.yaml ]] && echo "  - in.yaml"
    echo "  - $(rel "$dir" "$root/values")"
    echo "generatorOptions: {disableNameSuffixHash: true}"
    echo "configMapGenerator:"
    echo "  - name: $values_name"
    echo "    namespace: agentgateway-system"
    echo "    behavior: merge"
    echo "    envs: [values.env]"
    if [[ $wiring == yes ]]; then
      echo "components:"
      echo "  - $(rel "$dir" "$root/values/wiring")"
    fi
  } >"$dir/kustomization.yaml"
}
echo "== 2. values"
write_root "$work/values-root" no
kustomize build "$work/values-root" >"$work/values-all.yaml"
yq -N "select(.kind == \"ConfigMap\" and .metadata.name == \"$values_name\") | .data" "$work/values-all.yaml" >"$work/values.yaml"
[[ $(yq 'length' "$work/values.yaml") -gt 0 ]] || { echo "render: no values in $root/values" >&2; exit 1; }
wired=$(yq '.replacements[].source.fieldPath | sub("^data\\."; "")' "$root/values/wiring/kustomization.yaml" | sort -u)
unknown=$(comm -13 <(echo "$wired") <(yq 'keys | .[]' "$work/values.yaml" | sort -u))
if [[ -n $unknown ]]; then
  echo "render: these keys are in the values but no wiring rule in values/wiring reads them (a misspelled key?):" >&2
  echo "$unknown" | sed 's/^/   /' >&2
  exit 1
fi
printf '   %-24s %-30s %s\n' KEY VALUE SOURCE
while IFS= read -r key; do
  val=$(yq ".$key" "$work/values.yaml")
  fleet=$(grep -E "^$key=" "$root/values/values.env" | head -1 | cut -d= -f2- || true)
  if [[ $val == "$fleet" ]]; then src=fleet; else src="overrides fleet ($fleet)"; fi
  printf '   %-24s %-30s %s\n' "$key" "$val" "$src"
done < <(yq 'keys | .[]' "$work/values.yaml")

# --- 3. versions -----------------------------------------------------------------------------------------------------------------------
echo "== 3. versions"
chart_tag() { yq -N 'select(.kind == "OCIRepository") | .spec.ref.tag' "$1"; }
crd_ver=$(chart_tag "$root/platform/addons/agentgateway/crds.yaml")
ctl_ver=$(chart_tag "$root/platform/addons/agentgateway/controller.yaml")
if [[ -z $crd_ver || $crd_ver == null || -z $ctl_ver || $ctl_ver == null ]]; then
  echo "render: no OCIRepository ref.tag in platform/addons/agentgateway/crds.yaml or controller.yaml" >&2
  exit 1
fi
if [[ $crd_ver != "$ctl_ver" ]]; then
  echo "render: agentgateway CRD chart $crd_ver and controller chart $ctl_ver differ. Both are one artifact: set the same tag." >&2
  exit 1
fi
echo "   agentgateway chart tag $ctl_ver (CRDs and controller)"

# --- 4. render -------------------------------------------------------------------------------------------------------------------------
echo "== 4. render"
if [[ -n $only ]]; then rm -rf "$out/$only" "$out/.preview/$only"; else rm -rf "$out"; fi
mkdir -p "$out"
for c in "${chains[@]}"; do
  d=$work/chain-$c
  mkdir -p "$d"
  first=yes
  for f in $(folders_of "$c"); do
    [[ $first == yes ]] || echo "---" >>"$d/in.yaml"
    first=no
    kustomize build "$root/$f" >>"$d/in.yaml"
  done
  write_root "$d"
  yq -i ".labels = [{\"pairs\": {\"$chain_label\": \"$c\"}}]" "$d/kustomization.yaml"
  kustomize build "$d" >"$d/out.yaml"
  # the values ConfigMap is a render input, not an object of the artifact
  yq -N -o=json -I=0 "select(.kind != \"ConfigMap\" or .metadata.name != \"$values_name\")" "$d/out.yaml" >"$d/out.jsonl"
  [[ -s $d/out.jsonl ]] || { echo "render: chain $c rendered no objects" >&2; exit 1; }
  if jq -e 'select(.kind == "Secret")' "$d/out.jsonl" >/dev/null; then
    echo "render: chain $c contains a Secret. A Secret comes from clusters/$cluster/sync/secrets (SOPS), never from a render." >&2
    exit 1
  fi
  if grep -qE 'ENC\[|^sops:' "$d/out.yaml"; then
    echo "render: chain $c contains SOPS ciphertext." >&2
    exit 1
  fi
  mkdir -p "$out/$c"
  while IFS= read -r doc; do
    file=$(jq -r '(.kind | ascii_downcase) + "-" + .metadata.name + ".yaml"' <<<"$doc")
    [[ ! -e $out/$c/$file ]] || { echo "render: chain $c: two objects write $file" >&2; exit 1; }
    yq -P '.' <<<"$doc" >"$out/$c/$file"
  done <"$d/out.jsonl"
  printf '   %-20s %s objects from %s\n' "$c" "$(find "$out/$c" -type f | wc -l)" "$(folders_of "$c")"
done

# --- 5. preview ------------------------------------------------------------------------------------------------------------------------
echo "== 5. preview (helm template, not applied)"
shown=0
for c in "${chains[@]}"; do
  for rf in "$out/$c"/helmrelease-*.yaml; do
    [[ -e $rf ]] || continue
    name=$(yq '.metadata.name' "$rf")
    ns=$(yq '.metadata.namespace' "$rf")
    release=$(yq '.spec.releaseName // .metadata.name' "$rf")
    src=$(yq '.spec.chartRef.name' "$rf")
    sf="$out/$c/ocirepository-$src.yaml"
    [[ -f $sf ]] || { echo "render: HelmRelease $ns/$name: no OCIRepository $src in chain $c" >&2; exit 1; }
    url=$(yq '.spec.url' "$sf"); tag=$(yq '.spec.ref.tag' "$sf")
    yq '.spec.values // {}' "$rf" >"$work/values-$name.yaml"
    mkdir -p "$out/.preview/$c"
    helm template "$release" "$url" --version "$tag" --namespace "$ns" --include-crds -f "$work/values-$name.yaml" \
      >"$out/.preview/$c/$release.yaml" 2>"$work/helm.err" || { cat "$work/helm.err" >&2; echo "render: helm template failed for $release" >&2; exit 1; }
    printf '   %-20s %-30s %s objects\n' "$c" "$release@$tag" "$(yq -N '.kind' "$out/.preview/$c/$release.yaml" | grep -c .)"
    shown=$((shown + 1))
  done
done
((shown > 0)) || echo "   none in these chains"

# --- 6. schemas ------------------------------------------------------------------------------------------------------------------------
# The CRDs come from their two sources whatever chain is rendered: the Gateway API folder and the agentgateway CRD chart.
# A raw CRD schema accepts unknown fields, so every object schema is closed: a misspelled field is an error, as server-side validation reports it.
echo "== 6. schemas"
mkdir -p "$work/schemas"
crd_url=$(yq -N 'select(.kind == "OCIRepository") | .spec.url' "$root/platform/addons/agentgateway/crds.yaml")
{
  kustomize build "$root/platform/addons/gateway-api"
  echo "---"
  helm template agentgateway-crds "$crd_url" --version "$crd_ver" --include-crds 2>"$work/helm.err" \
    || { cat "$work/helm.err" >&2; echo "render: helm template of the CRD chart failed" >&2; exit 1; }
} | yq -N -o=json -I=0 'select(.kind == "CustomResourceDefinition")' | while IFS= read -r crd; do
  kind=$(jq -r '.spec.names.kind | ascii_downcase' <<<"$crd")
  for v in $(jq -r '.spec.versions[].name' <<<"$crd"); do
    jq --arg v "$v" '
      .spec.versions[] | select(.name == $v) | .schema.openAPIV3Schema // empty
      | walk(if type == "object" and (.properties? != null) and (has("additionalProperties") | not)
                  and (.["x-kubernetes-preserve-unknown-fields"] != true)
             then . + {additionalProperties: false} else . end)' <<<"$crd" >"$work/schemas/${kind}_${v}.json"
  done
done
k8s=$(yq '.nodes[0].image' "$overlay/kind-config.yaml" 2>/dev/null | sed -nE 's/.*:v([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')
k8s=${k8s:-1.37.0}
objs=()
for c in "${chains[@]}"; do while IFS= read -r f; do objs+=("$f"); done < <(find "$out/$c" -type f -name '*.yaml'); done
if ! kubeconform -strict -kubernetes-version "$k8s" -ignore-missing-schemas -schema-location default \
     -schema-location "$work/schemas/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" -summary "${objs[@]}" >"$work/kubeconform.out" 2>&1; then
  grep -v 'is valid$' "$work/kubeconform.out" | sed 's#^'"$out"'/#   #' >&2
  echo "render: an object does not match the schema of its kind (Kubernetes $k8s plus the CRDs)." >&2
  exit 1
fi
echo "   Kubernetes $k8s plus $(ls "$work/schemas" | wc -l) CRD schemas: $(tail -1 "$work/kubeconform.out" | sed 's/^Summary: //')"
echo "render: $cluster ok"
