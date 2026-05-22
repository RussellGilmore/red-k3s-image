#!/usr/bin/env bash
set -euo pipefail

STAGING="/tmp/red-k3s-staging"
ASSET_DIR="/opt/red-k3s"

echo "Installing k3s config template..."
mkdir -p "${ASSET_DIR}/k3s"
install -o root -g root -m 0644 \
  "${STAGING}/k3s/config.yaml.tmpl" "${ASSET_DIR}/k3s/config.yaml.tmpl"

echo "Installing the bootstrap script..."
install -o root -g root -m 0755 \
  "${STAGING}/bootstrap/k3s-bootstrap" /usr/local/bin/k3s-bootstrap

echo "Installing systemd units..."
install -o root -g root -m 0644 \
  "${STAGING}/systemd/k3s-bootstrap.service" \
  /etc/systemd/system/k3s-bootstrap.service
install -o root -g root -m 0644 \
  "${STAGING}/systemd/k3s-cert-renewal.service" \
  /etc/systemd/system/k3s-cert-renewal.service
install -o root -g root -m 0644 \
  "${STAGING}/systemd/k3s-cert-renewal.timer" \
  /etc/systemd/system/k3s-cert-renewal.timer

echo "Creating runtime directories..."
# Where EC2 user_data will drop config.env, and where the sentinel lives.
mkdir -p /etc/k3s-bootstrap /var/lib/k3s-bootstrap
chmod 0755 /etc/k3s-bootstrap /var/lib/k3s-bootstrap

echo "Enabling units (enable only — they fire on first boot of derived instances)..."
systemctl daemon-reload
systemctl enable k3s-bootstrap.service
systemctl enable k3s-cert-renewal.timer

echo "Verifying unit state..."
test "$(systemctl is-enabled k3s-bootstrap.service)" = "enabled" \
  || { echo "ERROR: k3s-bootstrap.service not enabled"; exit 1; }
test "$(systemctl is-enabled k3s-cert-renewal.timer)" = "enabled" \
  || { echo "ERROR: k3s-cert-renewal.timer not enabled"; exit 1; }
test "$(systemctl is-active k3s-bootstrap.service)" = "inactive" \
  || { echo "ERROR: k3s-bootstrap.service should be inactive at bake time"; exit 1; }

echo "Bootstrap orchestration installed."
