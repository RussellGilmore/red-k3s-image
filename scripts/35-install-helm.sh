#!/usr/bin/env bash
set -euo pipefail

: "${HELM_VERSION:?HELM_VERSION must be set, e.g. v4.3.0}"

ARCH="arm64"

# ----------------------------------------------------------------------
# Helm install (binary tarball, no apt repo dependency)
# ----------------------------------------------------------------------
echo "[35] Installing Helm ${HELM_VERSION} for ${ARCH}..."
HELM_TGZ="/tmp/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
curl -fsSL -o "${HELM_TGZ}" \
  "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
tar -xzf "${HELM_TGZ}" -C /tmp
install -o root -g root -m 0755 "/tmp/linux-${ARCH}/helm" /usr/local/bin/helm
rm -rf "${HELM_TGZ}" "/tmp/linux-${ARCH}"
helm version --short
