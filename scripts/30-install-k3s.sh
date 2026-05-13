#!/usr/bin/env bash
set -euo pipefail

: "${K3S_VERSION:?K3S_VERSION must be set, e.g. v1.34.6+k3s1}"

echo "Installing K3s ${K3S_VERSION} (service skipped, not enabled)..."

# Download and run the official installer with both skip flags set.
#   INSTALL_K3S_SKIP_START   — do not start k3s now
#   INSTALL_K3S_SKIP_ENABLE  — do not enable the systemd unit
#   INSTALL_K3S_VERSION      — pin the exact version
#
# The installer fetches the binary, writes the systemd unit, installs
# uninstall scripts (k3s-uninstall.sh), and creates the kubectl/crictl/ctr
# symlinks. With both skip flags it does NOT touch systemd state beyond
# writing the unit file.
curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="${K3S_VERSION}" \
  INSTALL_K3S_SKIP_START=true \
  INSTALL_K3S_SKIP_ENABLE=true \
  sh -s - server

echo "Verifying install..."
/usr/local/bin/k3s --version
ls -la /usr/local/bin/k3s /usr/local/bin/kubectl /usr/local/bin/crictl /usr/local/bin/ctr

echo "Confirming systemd unit is installed but not enabled..."
systemctl list-unit-files k3s.service
test "$(systemctl is-enabled k3s.service 2>&1 || true)" = "disabled" \
  || { echo "ERROR: k3s.service is enabled — should be disabled at bake time"; exit 1; }
test "$(systemctl is-active k3s.service 2>&1 || true)" = "inactive" \
  || { echo "ERROR: k3s.service is active — should be inactive at bake time"; exit 1; }

echo "Creating /etc/rancher/k3s directory for first-boot config..."
sudo mkdir -p /etc/rancher/k3s

echo "K3s ${K3S_VERSION} install complete (service inactive, disabled)."
