#!/usr/bin/env bash
set -euo pipefail

ARCH="$(dpkg --print-architecture)"
echo "Installing SSM Agent for ${ARCH}..."

# Remove the snap version that ships with Ubuntu cloud images, if present.
if snap list amazon-ssm-agent >/dev/null 2>&1; then
  echo "Removing snap version of amazon-ssm-agent..."
  sudo snap remove amazon-ssm-agent
fi

# Install the deb directly from the AWS-hosted bucket.
DEB_URL="https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/debian_${ARCH}/amazon-ssm-agent.deb"
TMP_DEB="$(mktemp --suffix=.deb)"

echo "Downloading SSM Agent deb from ${DEB_URL}..."
sudo curl -fsSL -o "${TMP_DEB}" "${DEB_URL}"

echo "Installing SSM Agent deb..."
sudo dpkg -i "${TMP_DEB}"
rm -f "${TMP_DEB}"

# The deb installs the service but we want to be explicit.
sudo systemctl enable amazon-ssm-agent
# Don't start it during the build — it will start on first boot of new
# instances. Starting it now would register the build instance as a managed
# node, which we don't want.
sudo systemctl stop amazon-ssm-agent || true

# Clear out any registration state that might have been written.
sudo rm -rf /var/lib/amazon/ssm/Vault/Store/RegistrationKey \
            /var/lib/amazon/ssm/registration \
            /var/lib/amazon/ssm/ipc

echo "SSM Agent install complete."
systemctl is-enabled amazon-ssm-agent
