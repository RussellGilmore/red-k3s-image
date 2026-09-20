#!/usr/bin/env bash
set -euo pipefail

echo "[15] Ensuring SSM agent is installed and enabled..."

if snap list amazon-ssm-agent >/dev/null 2>&1; then
  echo "[15] SSM agent snap already present."
else
  snap install amazon-ssm-agent --classic || true
fi

systemctl enable snap.amazon-ssm-agent.amazon-ssm-agent.service || true
echo "[15] SSM agent ready."
