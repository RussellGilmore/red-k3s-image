#!/usr/bin/env bash
set -euo pipefail

echo "Waiting for cloud-init to finish..."
cloud-init status --wait

echo "Cloud-init complete."
cloud-init status --long
