#!/usr/bin/env bash
set -euo pipefail

: "${HELM_VERSION:?HELM_VERSION must be set, e.g. v3.20.1}"

ARCH="arm64"

# ----------------------------------------------------------------------
# Helm install (binary tarball, no apt repo dependency)
# ----------------------------------------------------------------------
echo "Installing Helm ${HELM_VERSION} for ${ARCH}..."
HELM_TGZ="/tmp/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
curl -fsSL -o "${HELM_TGZ}" \
  "https://get.helm.sh/helm-${HELM_VERSION}-linux-${ARCH}.tar.gz"
tar -xzf "${HELM_TGZ}" -C /tmp
install -o root -g root -m 0755 "/tmp/linux-${ARCH}/helm" /usr/local/bin/helm
rm -rf "${HELM_TGZ}" "/tmp/linux-${ARCH}"
helm version --short

# ----------------------------------------------------------------------
# System-wide kubectl env: set KUBECONFIG so any root shell or systemd
# unit that runs kubectl picks up the K3s kubeconfig automatically.
# ----------------------------------------------------------------------
echo "Configuring system-wide KUBECONFIG..."
tee /etc/profile.d/k3s-kubeconfig.sh > /dev/null <<'EOF'
# Set KUBECONFIG for any login shell on this host.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
EOF
chmod 0644 /etc/profile.d/k3s-kubeconfig.sh
