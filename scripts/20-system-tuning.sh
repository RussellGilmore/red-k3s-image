#!/usr/bin/env bash
set -euo pipefail

echo "Setting timezone to UTC..."
sudo timedatectl set-timezone UTC

echo "Configuring kernel modules for K3s..."
sudo tee /etc/modules-load.d/k3s.conf > /dev/null <<'EOF'
br_netfilter
overlay
EOF

sudo modprobe br_netfilter
sudo modprobe overlay

echo "Configuring sysctl for K3s..."
sudo tee /etc/sysctl.d/90-k3s.conf > /dev/null <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
net.ipv6.conf.all.forwarding        = 1

# Reasonable inotify limits for a Kubernetes node
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches   = 524288
EOF

sudo sysctl --system

echo "Configuring journald log retention..."
sudo mkdir -p /etc/systemd/journald.conf.d
sudo tee /etc/systemd/journald.conf.d/00-k3s.conf > /dev/null <<'EOF'
[Journal]
SystemMaxUse=500M
SystemKeepFree=1G
SystemMaxFileSize=50M
EOF

echo "Disabling swap (Kubernetes requires this)..."
sudo swapoff -a
sudo sed -i.bak '/\sswap\s/s/^/#/' /etc/fstab

echo "Enabling iSCSI service for future Longhorn use..."
sudo systemctl enable iscsid
