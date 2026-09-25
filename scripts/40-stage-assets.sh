#!/usr/bin/env bash
set -euo pipefail

STAGING="/tmp/red-k3s-staging"

echo "[40] Installing staged assets from ${STAGING}..."

# k3s config template; __DOMAIN__ is slotted in at first boot.
install -D -o root -g root -m 0644 \
  "${STAGING}/k3s/config.yaml.tmpl" \
  /etc/red-k3s/config.yaml.tmpl

# First-boot script that cloud-init invokes at runtime.
install -D -o root -g root -m 0755 \
  "${STAGING}/first-boot/red-k3s-first-boot.sh" \
  /usr/local/sbin/red-k3s-first-boot.sh

# ----------------------------------------------------------------------
# System-wide kubectl env: set KUBECONFIG so any root shell picks up the
# k3s kubeconfig automatically. The kubeconfig itself is 0600, so this
# only helps root.
# ----------------------------------------------------------------------
echo "[40] Configuring system-wide KUBECONFIG..."
tee /etc/profile.d/k3s-kubeconfig.sh > /dev/null <<'EOF'
# Set KUBECONFIG for any login shell on this host.
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
EOF
chmod 0644 /etc/profile.d/k3s-kubeconfig.sh

echo "[40] Staged assets installed."
