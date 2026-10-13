#!/usr/bin/env bash
set -euo pipefail

: "${AWS_CLI_VERSION:?AWS_CLI_VERSION must be set, e.g. 2.37.2}"

ARCH="aarch64"

# ----------------------------------------------------------------------
# AWS CLI v2 install (official zip, pinned). Lands in /usr/local/bin so
# it is on root's PATH over SSM. No region or credentials are configured;
# the instance role supplies credentials at runtime.
# ----------------------------------------------------------------------
echo "[36] Installing AWS CLI ${AWS_CLI_VERSION} for ${ARCH}..."
AWS_ZIP="/tmp/awscli-${AWS_CLI_VERSION}.zip"
curl -fsSL -o "${AWS_ZIP}" \
  "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}-${AWS_CLI_VERSION}.zip"
unzip -q "${AWS_ZIP}" -d /tmp/awscli
/tmp/awscli/aws/install \
  --install-dir /usr/local/aws-cli \
  --bin-dir /usr/local/bin
rm -rf "${AWS_ZIP}" /tmp/awscli

INSTALLED="$(/usr/local/bin/aws --version 2>&1)"
echo "[36] ${INSTALLED}"

if [[ "${INSTALLED}" != aws-cli/${AWS_CLI_VERSION}\ * ]]; then
  echo "[36] ERROR: expected aws-cli/${AWS_CLI_VERSION}, got: ${INSTALLED}" >&2
  exit 1
fi
