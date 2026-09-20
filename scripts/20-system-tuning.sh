#!/usr/bin/env bash
set -euo pipefail

echo "[20] Applying basic system tuning..."

timedatectl set-timezone UTC || true

export DEBIAN_FRONTEND=noninteractive
apt-get install -y unattended-upgrades
systemctl enable unattended-upgrades || true

echo "[20] Configuring unattended-upgrades reboot window..."
tee /etc/apt/apt.conf.d/52-red-k3s-unattended > /dev/null <<'EOF'
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "07:00";
EOF
chmod 0644 /etc/apt/apt.conf.d/52-red-k3s-unattended

tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
chmod 0644 /etc/apt/apt.conf.d/20auto-upgrades

echo "[20] System tuning complete."
