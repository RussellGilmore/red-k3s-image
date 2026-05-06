#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(
  -y
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confold
)

echo "Updating package index..."
sudo apt-get update

echo "Upgrading installed packages..."
sudo apt-get "${APT_OPTS[@]}" upgrade
sudo apt-get "${APT_OPTS[@]}" dist-upgrade

echo "Installing baseline packages..."
sudo apt-get "${APT_OPTS[@]}" install \
  apparmor-utils \
  ca-certificates \
  curl \
  gnupg \
  htop \
  jq \
  lsb-release \
  net-tools \
  open-iscsi \
  rsync \
  socat \
  unzip \
  vim \
  wget

echo "Cleaning apt caches..."
sudo apt-get "${APT_OPTS[@]}" autoremove
sudo apt-get clean
