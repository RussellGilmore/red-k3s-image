#!/usr/bin/env bash
set -euo pipefail

: "${CERT_MANAGER_VERSION:?CERT_MANAGER_VERSION must be set, e.g. v1.20.2}"
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

# ----------------------------------------------------------------------
# Pre-download cert-manager manifest so first boot doesn't depend on
# GitHub being reachable.
# ----------------------------------------------------------------------
echo "Pre-downloading cert-manager ${CERT_MANAGER_VERSION} manifest..."
CM_ASSETS_DIR="/opt/red-k3s/cert-manager"
mkdir -p "${CM_ASSETS_DIR}"
curl -fsSL -o "${CM_ASSETS_DIR}/cert-manager.yaml" \
  "https://github.com/cert-manager/cert-manager/releases/download/${CERT_MANAGER_VERSION}/cert-manager.yaml"
chmod 0644 "${CM_ASSETS_DIR}/cert-manager.yaml"

# Sanity check: did we get a manifest with the expected version string?
if ! grep -q "${CERT_MANAGER_VERSION}" "${CM_ASSETS_DIR}/cert-manager.yaml"; then
  echo "ERROR: cert-manager manifest does not contain expected version ${CERT_MANAGER_VERSION}"
  exit 1
fi
echo "cert-manager manifest staged at ${CM_ASSETS_DIR}/cert-manager.yaml"
ls -lh "${CM_ASSETS_DIR}/cert-manager.yaml"

# ----------------------------------------------------------------------
# Move staged template files and helper binaries into permanent locations.
# (They arrived in /tmp/red-k3s-files via the Packer file provisioner.)
# ----------------------------------------------------------------------
echo "Installing cert-manager templates..."
install -o root -g root -m 0644 \
  /tmp/red-k3s-files/cert-manager/cluster-issuer.yaml.tmpl \
  "${CM_ASSETS_DIR}/cluster-issuer.yaml.tmpl"
install -o root -g root -m 0644 \
  /tmp/red-k3s-files/cert-manager/k3s-api-certificate.yaml.tmpl \
  "${CM_ASSETS_DIR}/k3s-api-certificate.yaml.tmpl"

echo "Installing helper scripts to /usr/local/bin..."
install -o root -g root -m 0755 \
  /tmp/red-k3s-files/bin/rotate-k3s-ca /usr/local/bin/rotate-k3s-ca
install -o root -g root -m 0755 \
  /tmp/red-k3s-files/bin/on-cert-renewal /usr/local/bin/on-cert-renewal

# ----------------------------------------------------------------------
# Clean up the staging directory.
# ----------------------------------------------------------------------
rm -rf /tmp/red-k3s-files

echo "Verifying staged artifacts..."
ls -la /opt/red-k3s/cert-manager/
ls -la /usr/local/bin/helm /usr/local/bin/rotate-k3s-ca /usr/local/bin/on-cert-renewal

echo "Helm + cert-manager assets staged successfully."
