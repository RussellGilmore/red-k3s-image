#!/usr/bin/env bash
set -euo pipefail

echo "Removing Packer staging directory..."
rm -rf /tmp/red-k3s-staging

echo "Cleaning shell history..."
sudo find / -name '.bash_history' -type f -delete 2>/dev/null || true
history -c || true

echo "Cleaning cloud-init state so it re-runs on first boot of new instances..."
sudo cloud-init clean --logs --seed

echo "Cleaning SSH host keys (regenerated on first boot)..."
sudo rm -f /etc/ssh/ssh_host_*

echo "Cleaning machine-id (regenerated on first boot)..."
sudo truncate -s 0 /etc/machine-id
sudo rm -f /var/lib/dbus/machine-id
sudo ln -sf /etc/machine-id /var/lib/dbus/machine-id

echo "Cleaning apt lists and logs..."
sudo rm -rf /var/lib/apt/lists/*
sudo find /var/log -type f \( -name '*.log' -o -name '*.gz' -o -name '*.[0-9]' \) -delete 2>/dev/null || true
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s

echo "Cleanup complete."
