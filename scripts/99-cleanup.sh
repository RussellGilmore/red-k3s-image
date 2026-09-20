#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[99] Re-enabling background apt timers for the deployed image..."
# The timers were disabled in 10-apt-baseline.sh to avoid dpkg lock contention
# during the build. Re-enable them here so instances launched from this AMI
# receive automatic security updates.
systemctl enable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true

echo "[99] Cleaning up before snapshot..."

apt-get clean
rm -rf /var/lib/apt/lists/*
rm -rf /tmp/red-k3s-staging

truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
ln -sf /etc/machine-id /var/lib/dbus/machine-id

cloud-init clean --logs || true

rm -f /etc/ssh/ssh_host_*

rm -f /root/.bash_history
find /var/log -type f -exec truncate -s 0 {} \;

echo "[99] Cleanup complete."
