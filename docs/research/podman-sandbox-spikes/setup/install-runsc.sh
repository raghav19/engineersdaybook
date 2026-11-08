#!/usr/bin/env bash
# Install gVisor (runsc) release 20261102.0 into a private folder. No root. No system files.
# It downloads the official tarball from the gVisor release bucket and checks the published SHA-512.
# Layout source: https://gvisor.dev/docs/user_guide/install/ (gvisor.tar.zstd + gvisor.tar.zstd.sha512).
set -euo pipefail

RELEASE="20261102.0"
ARCH="$(uname -m)"
URL="https://storage.googleapis.com/gvisor/releases/release/${RELEASE}/${ARCH}"
DEST="<SPIKES>/G-bin"
DL="${DEST}/../G-dl"

mkdir -p "${DEST}" "${DL}"
cd "${DL}"
curl -fsSL -o gvisor.tar.zstd "${URL}/gvisor.tar.zstd"
curl -fsSL -o gvisor.tar.zstd.sha512 "${URL}/gvisor.tar.zstd.sha512"
sha512sum -c gvisor.tar.zstd.sha512
tar --zstd -xf gvisor.tar.zstd -C "${DEST}"
chmod 0755 "${DEST}/runsc"
"${DEST}/runsc" --version
echo "gVisor installed in ${DEST}"
ls -la "${DEST}"
