#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# red-k3s AMI first-boot orchestration.
#
# Invoked by cloud-init from the instance's user-data. Expects user-data to
# have written /etc/red-k3s/first-boot.env with:
#   DOMAIN=k3s.example.com
#   K3S_ROLE=server
#
# Idempotent: completes once, marks a sentinel, and is a no-op on re-run.
# Safe to re-run by hand over SSM after a partial failure.
# ---------------------------------------------------------------------------

ENV_FILE="/etc/red-k3s/first-boot.env"
TEMPLATE="/etc/red-k3s/config.yaml.tmpl"
CONFIG="/etc/rancher/k3s/config.yaml"
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
SENTINEL="/var/lib/red-k3s/first-boot.done"
LOG_FILE="/var/log/red-k3s-first-boot.log"

install -d -o root -g root -m 0755 /var/log
exec > >(tee -a "${LOG_FILE}") 2>&1

echo "[first-boot] Starting red-k3s first-boot setup at $(date -u +%FT%TZ)."

if [[ "${EUID}" -ne 0 ]]; then
  echo "[first-boot] ERROR: must run as root." >&2
  exit 1
fi

if [[ -f "${SENTINEL}" ]]; then
  echo "[first-boot] Sentinel ${SENTINEL} exists; nothing to do."
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Load and validate the first-boot contract.
# ---------------------------------------------------------------------------
if [[ ! -f "${ENV_FILE}" ]]; then
  echo "[first-boot] ERROR: ${ENV_FILE} not found. User-data must write it." >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${ENV_FILE}"

: "${DOMAIN:?DOMAIN must be set in ${ENV_FILE}}"
K3S_ROLE="${K3S_ROLE:-server}"

case "${K3S_ROLE}" in
  server)
    echo "[first-boot] Role: server."
    ;;
  agent)
    echo "[first-boot] ERROR: K3S_ROLE=agent is not yet supported by this AMI." >&2
    echo "[first-boot] Agent support is planned; use K3S_ROLE=server for now." >&2
    exit 1
    ;;
  *)
    echo "[first-boot] ERROR: invalid K3S_ROLE='${K3S_ROLE}' (expected 'server')." >&2
    exit 1
    ;;
esac

# ---------------------------------------------------------------------------
# 2. Render the k3s config.
# ---------------------------------------------------------------------------
echo "[first-boot] Rendering ${CONFIG} for ${DOMAIN}..."
install -d -o root -g root -m 0755 /etc/rancher/k3s
sed "s|__DOMAIN__|${DOMAIN}|g" "${TEMPLATE}" > "${CONFIG}"
chown root:root "${CONFIG}"
chmod 0600 "${CONFIG}"

# ---------------------------------------------------------------------------
# 3. Start k3s. It was installed but deliberately left disabled at bake time
#    so no node identity, token or certs are baked into the AMI.
# ---------------------------------------------------------------------------
echo "[first-boot] Enabling and starting k3s..."
systemctl reset-failed k3s 2>/dev/null || true
systemctl enable --now k3s

# ---------------------------------------------------------------------------
# 4. Wait for the API server to report ready.
# ---------------------------------------------------------------------------
echo "[first-boot] Waiting for the Kubernetes API to become ready..."
API_MAX_ATTEMPTS=60
api_ready=false

for attempt in $(seq 1 "${API_MAX_ATTEMPTS}"); do
  if KUBECONFIG="${KUBECONFIG_PATH}" k3s kubectl get --raw='/readyz' >/dev/null 2>&1; then
    api_ready=true
    echo "[first-boot] API ready after ${attempt} attempt(s)."
    break
  fi
  sleep 5
done

if [[ "${api_ready}" != "true" ]]; then
  echo "[first-boot] ERROR: API did not become ready in time." >&2
  systemctl status k3s --no-pager >&2 || true
  journalctl -u k3s --no-pager -n 50 >&2 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 5. Wait for this node to reach Ready.
# ---------------------------------------------------------------------------
echo "[first-boot] Waiting for the node to reach Ready..."
if ! KUBECONFIG="${KUBECONFIG_PATH}" k3s kubectl wait \
    --for=condition=Ready node --all --timeout=300s; then
  echo "[first-boot] ERROR: node did not reach Ready in time." >&2
  KUBECONFIG="${KUBECONFIG_PATH}" k3s kubectl get nodes -o wide >&2 || true
  exit 1
fi

# ---------------------------------------------------------------------------
# 6. Mark completion.
# ---------------------------------------------------------------------------
install -d -o root -g root -m 0755 /var/lib/red-k3s
date -u +%FT%TZ > "${SENTINEL}"
chmod 0644 "${SENTINEL}"

echo "[first-boot] red-k3s first-boot setup complete."
KUBECONFIG="${KUBECONFIG_PATH}" k3s kubectl get nodes -o wide || true
