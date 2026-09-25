#!/usr/bin/env bash
set -euo pipefail

: "${K3S_VERSION:?K3S_VERSION must be set, e.g. v1.37.0+k3s1}"

# ----------------------------------------------------------------------
# Install k3s at a pinned version, but do NOT start or enable it.
#
# Starting k3s during the bake would generate the node identity, the
# cluster token and the TLS material, and all of it would be baked into
# the AMI and shared by every instance launched from it. The service is
# enabled and started at first boot instead, by red-k3s-first-boot.sh.
# ----------------------------------------------------------------------
echo "[30] Installing k3s ${K3S_VERSION} (install only, not started)..."

curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh
chmod 0755 /tmp/k3s-install.sh

INSTALL_K3S_VERSION="${K3S_VERSION}" \
INSTALL_K3S_SKIP_START="true" \
INSTALL_K3S_SKIP_ENABLE="true" \
  /tmp/k3s-install.sh server

rm -f /tmp/k3s-install.sh

# ----------------------------------------------------------------------
# Verify the bake-time state. These assertions are the whole point of
# this script: if any of them fail, the AMI is unsafe to publish.
# ----------------------------------------------------------------------
echo "[30] Verifying installed version..."
k3s --version

echo "[30] Verifying the k3s unit exists but is inert..."
test -f /etc/systemd/system/k3s.service

if systemctl is-enabled k3s 2>/dev/null | grep -qx "enabled"; then
  echo "[30] ERROR: k3s is enabled; it must stay disabled in the image." >&2
  exit 1
fi

if systemctl is-active --quiet k3s; then
  echo "[30] ERROR: k3s is running; it must not start during the bake." >&2
  exit 1
fi

if [[ -d /var/lib/rancher/k3s/server/tls ]]; then
  echo "[30] ERROR: cluster TLS material exists; k3s must not have run." >&2
  exit 1
fi

echo "[30] k3s ${K3S_VERSION} installed, disabled and inactive."
