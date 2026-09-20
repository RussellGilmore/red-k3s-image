#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Stop and disable the background apt timers/services so they can't grab the
# dpkg lock mid-provisioning. cloud-init reporting "done" does not stop these,
# and on 26.04 they aggressively spawn apt-get jobs that race provisioning.
# These are re-enabled at the end of the build (see 99-cleanup.sh) so deployed
# instances still receive automatic security updates.
echo "[10] Disabling background apt timers for the build..."
systemctl stop apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
systemctl disable apt-daily.timer apt-daily-upgrade.timer 2>/dev/null || true
systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true
systemctl kill --kill-who=all apt-daily.service 2>/dev/null || true
systemctl kill --kill-who=all apt-daily-upgrade.service 2>/dev/null || true

# Belt-and-suspenders: wait for any in-flight apt/dpkg lock to clear.
echo "[10] Waiting for apt/dpkg locks to be released..."
while sudo fuser /var/lib/apt/lists/lock /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock >/dev/null 2>&1; do
  echo "[10] apt is locked by another process; waiting..."
  sleep 5
done

# Heal any partially-completed dpkg transaction left by a killed timer job.
dpkg --configure -a 2>/dev/null || true

echo "[10] Updating apt and upgrading base packages..."
apt-get update -y
apt-get upgrade -y

echo "[10] Installing baseline utilities..."
apt-get install -y \
  ca-certificates \
  curl \
  gnupg \
  jq \
  unzip \
  vim

echo "[10] apt baseline complete."
