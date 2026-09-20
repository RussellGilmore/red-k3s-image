#!/usr/bin/env bash
set -euo pipefail

echo "[00] Waiting for base image cloud-init to finish..."
cloud-init status --wait || true
echo "[00] cloud-init complete."
