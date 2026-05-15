#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for cloud-init to finish..."
cloud-init status --wait

echo "Cloud-init complete."
cloud-init status --long

echo "Waiting for apt/dpkg locks to be released (unattended-upgrades, etc.)..."
LOCKS=(
  /var/lib/dpkg/lock-frontend
  /var/lib/dpkg/lock
  /var/lib/apt/lists/lock
  /var/cache/apt/archives/lock
)

TIMEOUT=300
WAITED=0
while :; do
  HELD=0
  for lock in "${LOCKS[@]}"; do
    if fuser "${lock}" >/dev/null 2>&1; then
      HELD=1
      break
    fi
  done
  if [[ "${HELD}" -eq 0 ]]; then
    echo "All apt/dpkg locks released."
    break
  fi
  if [[ "${WAITED}" -ge "${TIMEOUT}" ]]; then
    echo "ERROR: apt/dpkg locks still held after ${TIMEOUT}s"
    for lock in "${LOCKS[@]}"; do
      echo "  ${lock}: $(fuser "${lock}" 2>&1 || echo 'free')"
    done
    exit 1
  fi
  echo "Lock(s) still held, sleeping 5s (waited ${WAITED}s)..."
  sleep 5
  WAITED=$((WAITED + 5))
done
