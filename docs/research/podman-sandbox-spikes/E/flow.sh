#!/usr/bin/env bash
# End-to-end flow against the LOCAL registry only (127.0.0.1:5071, plain HTTP).
# Usage: E-flow.sh publish BUNDLE_DIR PINFILE   # CI/publisher side: has the signing key and push rights
#        E-flow.sh host PINFILE OUTDIR          # host side: has only the public key and the pin file
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REG=${REG:-localhost:5071}; REPO=${REPO:-spk-e/flow}; TAG=${TAG:-latest}
COSIGN=${COSIGN:-$HOME/.local/share/mise/installs/aqua-sigstore-cosign/3.1.4/cosign}
KEYDIR=${KEYDIR:-$here/E-keys}
# Local-only switches. For a real TLS registry set TLS_VERIFY=true and drop the two cosign flags below.
export TLS_VERIFY=${TLS_VERIFY:-false}
LOCAL_COSIGN=(--allow-insecure-registry)
mode=${1:?publish|host}

case $mode in
publish)
  bundle=${2:?BUNDLE_DIR}; pinfile=${3:?PINFILE}
  # 1. every image in compose.yaml must be pinned by digest
  if grep -E '^\s*image:' "$bundle/compose.yaml" | grep -v -E '@sha256:[0-9a-f]{64}'; then
    echo "FAIL: unpinned image in compose.yaml" >&2; exit 1; fi
  # 2. publish: one layer per file (podman artifact is flat, no sub-directories)
  files=("$bundle"/*); for f in "${files[@]}"; do [[ -f $f ]] || { echo "FAIL: $f is not a regular file" >&2; exit 1; }; done
  podman artifact add --replace --type application/vnd.engineersdaybook.sandbox.v1 "$REG/$REPO:$TAG" "${files[@]}" >/dev/null
  podman artifact push --tls-verify="$TLS_VERIFY" "$REG/$REPO:$TAG" >/dev/null 2>&1
  digest=$(podman artifact inspect "$REG/$REPO:$TAG" | jq -r .Digest)
  # 3. sign by digest (key-only, no transparency log; the empty signing config switches the tlog off)
  [[ -f $KEYDIR/signing-config.json ]] || "$COSIGN" signing-config create --out "$KEYDIR/signing-config.json" >/dev/null
  COSIGN_PASSWORD=${COSIGN_PASSWORD-} "$COSIGN" sign --key "$KEYDIR/cosign.key" "${LOCAL_COSIGN[@]}" \
    --signing-config "$KEYDIR/signing-config.json" -y "$REG/$REPO@$digest" >/dev/null 2>&1
  # 4. the pin file is the ONLY thing that goes into git for review
  echo "$REG/$REPO@$digest" > "$pinfile"; echo "published + signed: $(cat "$pinfile")"
  ;;
host)
  pinfile=${2:?PINFILE}; out=${3:?OUTDIR}
  ref=$(<"$pinfile")
  [[ $ref =~ ^[a-z0-9./:_-]+@sha256:[0-9a-f]{64}$ ]] || { echo "FAIL: bad pin file" >&2; exit 2; }
  # 1. signature check by digest (no tag lookup anywhere)
  "$COSIGN" verify --key "$KEYDIR/cosign.pub" "${LOCAL_COSIGN[@]}" --insecure-ignore-tlog "$ref" >/dev/null 2>&1 \
    || { echo "FAIL: no valid signature for $ref" >&2; exit 1; }
  # 2. pull by digest, compare digest to the pin, check each file against its layer digest
  "$here/E-verify-pinned.sh" "$ref" "$out"
  # 3. start (the test bundle has a fake image digest, so only parse the file here)
  podman-compose -f "$out/compose.yaml" config >/dev/null && echo "compose.yaml parses; run: podman-compose -f $out/compose.yaml up -d"
  ;;
*) echo "unknown mode" >&2; exit 2;;
esac
