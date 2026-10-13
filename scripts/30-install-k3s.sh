#!/usr/bin/env bash
set -euo pipefail

: "${K3S_VERSION:?K3S_VERSION must be set, e.g. v1.37.0+k3s1}"

# ----------------------------------------------------------------------
# The installer writes every K3S_* variable in its environment into the
# systemd .env files. Copy the version and unset it so nothing from the
# build environment leaks into the units. Asserted below.
# ----------------------------------------------------------------------
PINNED_VERSION="${K3S_VERSION}"
unset K3S_VERSION

BIN="/usr/local/bin/k3s"
UNIT_DIR="/etc/systemd/system"

# ----------------------------------------------------------------------
# Install k3s at a pinned version with BOTH units, server and agent, but
# do NOT start or enable either.
#
# Starting k3s during the bake would generate node identity, tokens and
# TLS material, and all of it would be baked into the AMI and shared by
# every instance. First boot enables exactly one unit, chosen by K3S_ROLE.
#
# Same binary for both roles; only the systemd unit differs:
#   k3s.service        -> k3s server
#   k3s-agent.service  -> k3s agent
# Both read /etc/rancher/k3s/config.yaml, rendered at first boot.
# ----------------------------------------------------------------------
curl -sfL https://get.k3s.io -o /tmp/k3s-install.sh
chmod 0755 /tmp/k3s-install.sh

echo "[30] Installing k3s ${PINNED_VERSION} server unit (install only)..."
INSTALL_K3S_VERSION="${PINNED_VERSION}" \
INSTALL_K3S_SKIP_START="true" \
INSTALL_K3S_SKIP_ENABLE="true" \
  /tmp/k3s-install.sh server

# Explicit 'agent' command: the installer names the unit k3s-agent and
# does not require K3S_URL/K3S_TOKEN. Those come from config.yaml at
# first boot. Reuses the binary downloaded above.
echo "[30] Installing k3s ${PINNED_VERSION} agent unit (install only)..."
INSTALL_K3S_VERSION="${PINNED_VERSION}" \
INSTALL_K3S_SKIP_DOWNLOAD="true" \
INSTALL_K3S_SKIP_START="true" \
INSTALL_K3S_SKIP_ENABLE="true" \
  /tmp/k3s-install.sh agent

rm -f /tmp/k3s-install.sh

# ----------------------------------------------------------------------
# Verify the bake-time state. If any assertion fails, the AMI is unsafe
# or incomplete and must not be published.
# ----------------------------------------------------------------------
fail() {
  echo "[30] ERROR: $*" >&2
  exit 1
}

echo "[30] Verifying installed version..."
INSTALLED="$("${BIN}" --version | head -n1)"
echo "[30] ${INSTALLED}"
[[ "${INSTALLED}" == *"${PINNED_VERSION}"* ]] \
  || fail "expected ${PINNED_VERSION}, got: ${INSTALLED}"

# assert_unit_inert <unit> <k3s subcommand>
assert_unit_inert() {
  local unit="$1" cmd="$2"
  local path="${UNIT_DIR}/${unit}.service"
  local env_file="${path}.env"

  echo "[30] Verifying ${unit}.service..."

  [[ -f "${path}" ]] || fail "${path} missing."

  # ExecStart spans two lines in installer output; join before matching.
  sed -n '/^ExecStart=/,$p' "${path}" | tr -d '\\\n' \
    | grep -Eq "ExecStart=${BIN}[[:space:]]+${cmd}([[:space:]]|$)" \
    || fail "${unit}.service does not run '${BIN} ${cmd}'."

  if systemctl is-enabled "${unit}" 2>/dev/null | grep -qx "enabled"; then
    fail "${unit} is enabled; it must stay disabled in the image."
  fi

  if systemctl is-active --quiet "${unit}"; then
    fail "${unit} is running; it must not start during the bake."
  fi

  if [[ -s "${env_file}" ]] && grep -Eq '^(K3S|CONTAINERD)_' "${env_file}"; then
    fail "${env_file} contains K3S_/CONTAINERD_ variables from the build env."
  fi
}

systemctl daemon-reload
assert_unit_inert k3s server
assert_unit_inert k3s-agent agent

echo "[30] Verifying no node identity or cluster material exists..."
for p in \
  /var/lib/rancher/k3s/server/tls \
  /var/lib/rancher/k3s/server/token \
  /var/lib/rancher/k3s/agent \
  /etc/rancher/node/password \
  /etc/rancher/k3s/k3s.yaml; do
  [[ -e "${p}" ]] && fail "${p} exists; k3s must not have run."
done

echo "[30] k3s ${PINNED_VERSION} installed; server and agent units present, disabled and inactive."
