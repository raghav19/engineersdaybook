#!/usr/bin/env bash
# Usage: E-verify-pinned.sh REF@sha256:<64 hex> OUTDIR
# Pull an OCI artifact by digest, check that the manifest digest equals the pin,
# check each extracted file against its layer digest, then leave the files in OUTDIR.
set -euo pipefail
ref=${1:?usage: $0 REF@sha256:DIGEST OUTDIR}
out=${2:?usage: $0 REF@sha256:DIGEST OUTDIR}
[[ $ref =~ ^[a-z0-9./:_-]+@(sha256:[0-9a-f]{64})$ ]] || { echo "FAIL: ref must end in @sha256:<64 hex>" >&2; exit 2; }
pin=${BASH_REMATCH[1]}
[[ -e $out ]] && { echo "FAIL: OUTDIR exists: $out" >&2; exit 2; }
args=(--tls-verify="${TLS_VERIFY:-true}")
podman artifact rm "$ref" >/dev/null 2>&1 || true
podman artifact pull "${args[@]}" "$ref" >/dev/null
meta=$(podman artifact inspect "$ref")
got=$(jq -r .Digest <<<"$meta")
[[ $got == "$pin" ]] || { echo "FAIL: digest $got != pin $pin" >&2; exit 1; }
tmp=$(mktemp -d "${out%/*}/.verify.XXXXXX"); trap 'rm -rf "$tmp"' EXIT
podman artifact extract "$ref" "$tmp" >/dev/null
while IFS=$'\t' read -r title dig; do
  [[ $title =~ ^[A-Za-z0-9._-]+$ && $title != .* ]] || { echo "FAIL: bad layer title: $title" >&2; exit 1; }
  have=sha256:$(sha256sum "$tmp/$title" | cut -d' ' -f1)
  [[ $have == "$dig" ]] || { echo "FAIL: $title is $have, layer says $dig" >&2; exit 1; }
done < <(jq -r '.Manifest.layers[] | [.annotations["org.opencontainers.image.title"], .digest] | @tsv' <<<"$meta")
n=$(jq '.Manifest.layers | length' <<<"$meta"); [[ $(ls -A "$tmp" | wc -l) -eq $n ]] || { echo "FAIL: file count differs from layer count" >&2; exit 1; }
mv "$tmp" "$out"; trap - EXIT
echo "OK: $ref ($n files) -> $out"
