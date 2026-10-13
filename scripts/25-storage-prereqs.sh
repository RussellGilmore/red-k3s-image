#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# ----------------------------------------------------------------------
# Longhorn prerequisites, baked into both roles. Inert until Longhorn is
# installed in the cluster.
# ----------------------------------------------------------------------
echo "[25] Installing Longhorn storage prerequisites..."
apt-get install -y \
  open-iscsi \
  nfs-common \
  cryptsetup

# ----------------------------------------------------------------------
# Kernel modules: load at boot, and fail the bake now if the running
# kernel does not ship them.
# ----------------------------------------------------------------------
echo "[25] Configuring kernel modules..."
tee /etc/modules-load.d/red-k3s-longhorn.conf > /dev/null <<'EOF'
# Longhorn prerequisites.
iscsi_tcp
dm_crypt
EOF
chmod 0644 /etc/modules-load.d/red-k3s-longhorn.conf

for mod in iscsi_tcp dm_crypt; do
  if ! modinfo "${mod}" >/dev/null 2>&1; then
    echo "[25] ERROR: kernel module ${mod} not available." >&2
    exit 1
  fi
done

# ----------------------------------------------------------------------
# iSCSI initiator name must be unique per instance. The package generates
# one at install time; 99-cleanup.sh deletes it so it is never baked into
# the AMI, and this unit regenerates it on each instance's first boot,
# before iscsid starts.
# ----------------------------------------------------------------------
echo "[25] Installing per-instance iSCSI initiator name unit..."
ISCSI_INAME="$(command -v iscsi-iname)"

tee /etc/systemd/system/red-k3s-iscsi-initiator.service > /dev/null <<EOF
[Unit]
Description=Generate a unique iSCSI initiator name for this instance
ConditionPathExists=!/etc/iscsi/initiatorname.iscsi
Before=iscsid.service iscsid.socket

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'echo "InitiatorName=\$(${ISCSI_INAME})" > /etc/iscsi/initiatorname.iscsi'

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/red-k3s-iscsi-initiator.service

systemctl daemon-reload
systemctl enable red-k3s-iscsi-initiator.service

echo "[25] Enabling iscsid..."
systemctl enable iscsid

# ----------------------------------------------------------------------
# Keep multipathd away from Longhorn's block devices, if multipath ships
# on this image. Nitro root volumes are nvme, so blacklisting sd* is safe.
# ----------------------------------------------------------------------
if systemctl list-unit-files multipathd.service >/dev/null 2>&1 \
   && systemctl list-unit-files multipathd.service | grep -q multipathd; then
  echo "[25] multipathd present; blacklisting sd* devices for Longhorn..."
  install -d -o root -g root -m 0755 /etc/multipath/conf.d
  tee /etc/multipath/conf.d/red-k3s-longhorn.conf > /dev/null <<'EOF'
blacklist {
    devnode "^sd[a-z0-9]+"
}
EOF
  chmod 0644 /etc/multipath/conf.d/red-k3s-longhorn.conf
else
  echo "[25] multipathd not present; skipping blacklist."
fi

echo "[25] Storage prerequisites complete."
