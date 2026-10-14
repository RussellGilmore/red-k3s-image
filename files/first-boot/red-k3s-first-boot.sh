#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------------------------------------
# red-k3s AMI first-boot orchestration.
#
# Invoked by cloud-init from the instance's user-data. Expects user-data to
# have written /etc/red-k3s/first-boot.env:
#
#   K3S_ROLE=server|agent               (required)
#   DOMAIN=k3s.example.com              (required, both roles)
#   K3S_SERVER_TOKEN_PARAM=/path        (required, server only)
#   K3S_AGENT_TOKEN_PARAM=/path         (required, both roles)
#   ENABLE_TRAEFIK=false                (optional, server only)
#
# The env file carries SSM parameter NAMES only. Token values are fetched
# here into root-only files and must never be printed.
#
# Idempotent: completes once, marks a sentinel, and is a no-op on re-run.
# Safe to re-run by hand over SSM after a partial failure.
#
# SECURITY: never enable xtrace (set -x) in this script. Output is tee'd to
# a log file, and tracing would write token values into it.
# ---------------------------------------------------------------------------
set +x

ENV_FILE="/etc/red-k3s/first-boot.env"
RED_K3S_DIR="/etc/red-k3s"
CONFIG="/etc/rancher/k3s/config.yaml"
KUBECONFIG_PATH="/etc/rancher/k3s/k3s.yaml"
SERVER_TOKEN_FILE="${RED_K3S_DIR}/server-token"
AGENT_TOKEN_FILE="${RED_K3S_DIR}/agent-token"
SENTINEL="/var/lib/red-k3s/first-boot.done"
LOG_FILE="/var/log/red-k3s-first-boot.log"
IMDS="http://169.254.169.254/latest"

SSM_MAX_ATTEMPTS=10      # x 6s: rides out instance-profile propagation
API_MAX_ATTEMPTS=60      # x 5s
NODE_MAX_ATTEMPTS=60     # x 5s
AGENT_MAX_ATTEMPTS=180   # x 5s = 15 min: the server may boot after agents

install -d -o root -g root -m 0755 /var/log
exec > >(tee -a "${LOG_FILE}") 2>&1

log()  { echo "[first-boot] $*"; }
fail() { echo "[first-boot] ERROR: $*" >&2; exit 1; }

log "Starting red-k3s first-boot setup at $(date -u +%FT%TZ)."

[[ "${EUID}" -eq 0 ]] || fail "must run as root."

if [[ -f "${SENTINEL}" ]]; then
  log "Sentinel ${SENTINEL} exists; nothing to do."
  exit 0
fi

# ---------------------------------------------------------------------------
# 1. Load and validate the first-boot contract.
# ---------------------------------------------------------------------------
[[ -f "${ENV_FILE}" ]] || fail "${ENV_FILE} not found. User-data must write it."

# shellcheck disable=SC1090
source "${ENV_FILE}"

[[ -n "${K3S_ROLE:-}" ]] || fail "K3S_ROLE must be set in ${ENV_FILE} ('server' or 'agent')."
[[ -n "${DOMAIN:-}" ]]   || fail "DOMAIN must be set in ${ENV_FILE}."
[[ -n "${K3S_AGENT_TOKEN_PARAM:-}" ]] \
  || fail "K3S_AGENT_TOKEN_PARAM must be set in ${ENV_FILE}."

case "${K3S_ROLE}" in
  server)
    [[ -n "${K3S_SERVER_TOKEN_PARAM:-}" ]] \
      || fail "K3S_SERVER_TOKEN_PARAM must be set in ${ENV_FILE} for K3S_ROLE=server."

    # Traefik is off by default: ingress is Istio via the Gateway API.
    ENABLE_TRAEFIK="${ENABLE_TRAEFIK:-false}"
    case "${ENABLE_TRAEFIK}" in
      true|false) ;;
      *) fail "invalid ENABLE_TRAEFIK='${ENABLE_TRAEFIK}' (expected 'true' or 'false')." ;;
    esac

    UNIT="k3s"
    OTHER_UNIT="k3s-agent"
    ;;
  agent)
    if [[ -n "${ENABLE_TRAEFIK:-}" ]]; then
      log "WARNING: ENABLE_TRAEFIK is a server-only setting; ignoring it for the agent role."
    fi
    UNIT="k3s-agent"
    OTHER_UNIT="k3s"
    ;;
  *)
    fail "invalid K3S_ROLE='${K3S_ROLE}' (expected 'server' or 'agent')."
    ;;
esac

TEMPLATE="${RED_K3S_DIR}/${K3S_ROLE}-config.yaml.tmpl"
[[ -f "${TEMPLATE}" ]] || fail "${TEMPLATE} not found. The AMI is incomplete."

log "Role: ${K3S_ROLE}. Domain: ${DOMAIN}."

# ---------------------------------------------------------------------------
# 2. Read placement from IMDSv2. No AWS cloud provider, so these become
#    node labels ourselves. Region is used only for this script's SSM calls;
#    nothing is persisted for interactive AWS CLI use.
# ---------------------------------------------------------------------------
log "Reading region and availability zone from IMDS..."
IMDS_TOKEN="$(curl -fsS --retry 5 --retry-connrefused -X PUT \
  -H 'X-aws-ec2-metadata-token-ttl-seconds: 300' \
  "${IMDS}/api/token")" || fail "could not obtain an IMDSv2 token."

imds_get() {
  curl -fsS --retry 5 --retry-connrefused \
    -H "X-aws-ec2-metadata-token: ${IMDS_TOKEN}" \
    "${IMDS}/meta-data/$1"
}

REGION="$(imds_get placement/region)"           || fail "could not read region from IMDS."
ZONE="$(imds_get placement/availability-zone)"  || fail "could not read availability zone from IMDS."
[[ -n "${REGION}" && -n "${ZONE}" ]]            || fail "IMDS returned an empty region or zone."
log "Region: ${REGION}. Zone: ${ZONE}."

# ---------------------------------------------------------------------------
# 3. Fetch tokens from SSM into root-only files.
#    Written via a 0600 temp file and an atomic rename, so a partial or
#    world-readable token file never exists. Values are never echoed.
# ---------------------------------------------------------------------------
fetch_token() {
  local param="$1" dest="$2" label="$3" tmp attempt

  log "Fetching ${label} token from SSM parameter ${param}..."
  for attempt in $(seq 1 "${SSM_MAX_ATTEMPTS}"); do
    tmp="$(mktemp "${dest}.XXXXXX")"   # mktemp creates the file 0600
    if aws ssm get-parameter \
         --region "${REGION}" \
         --name "${param}" \
         --with-decryption \
         --query 'Parameter.Value' \
         --output text \
       | tr -d '\r\n' > "${tmp}" \
       && [[ -s "${tmp}" ]]; then
      chown root:root "${tmp}"
      chmod 0600 "${tmp}"
      mv -f "${tmp}" "${dest}"
      log "${label} token written to ${dest} (attempt ${attempt})."
      return 0
    fi
    rm -f "${tmp}"
    log "SSM fetch for ${label} token failed (attempt ${attempt}/${SSM_MAX_ATTEMPTS}); retrying in 6s..."
    sleep 6
  done

  fail "could not fetch the ${label} token from ${param}. Check the parameter exists and the instance role allows ssm:GetParameter on it."
}

install -d -o root -g root -m 0755 "${RED_K3S_DIR}"

if [[ "${K3S_ROLE}" == "server" ]]; then
  fetch_token "${K3S_SERVER_TOKEN_PARAM}" "${SERVER_TOKEN_FILE}" "server"
fi
fetch_token "${K3S_AGENT_TOKEN_PARAM}" "${AGENT_TOKEN_FILE}" "agent"

# ---------------------------------------------------------------------------
# 4. Render the k3s config. Regenerated from the template every run, so the
#    appended disable block can never accumulate duplicates.
# ---------------------------------------------------------------------------
log "Rendering ${CONFIG} from ${TEMPLATE}..."
install -d -o root -g root -m 0755 /etc/rancher/k3s

RENDERED="$(mktemp "${CONFIG}.XXXXXX")"
sed -e "s|__DOMAIN__|${DOMAIN}|g" \
    -e "s|__ZONE__|${ZONE}|g" \
    -e "s|__REGION__|${REGION}|g" \
    "${TEMPLATE}" > "${RENDERED}"

if [[ "${K3S_ROLE}" == "server" && "${ENABLE_TRAEFIK}" == "false" ]]; then
  log "Disabling bundled Traefik."
  cat >> "${RENDERED}" <<'EOF'

# Ingress is handled by Istio via the Gateway API.
disable:
  - traefik
EOF
fi

if grep -q '__[A-Z]\+__' "${RENDERED}"; then
  rm -f "${RENDERED}"
  fail "unsubstituted placeholder left in the rendered config."
fi

chown root:root "${RENDERED}"
chmod 0600 "${RENDERED}"
mv -f "${RENDERED}" "${CONFIG}"

# ---------------------------------------------------------------------------
# 5. Start k3s for this role only. Both units were installed but left
#    disabled at bake time so no identity, tokens or certs are in the AMI.
#
#    --no-block: the units use TimeoutStartSec=0, and an agent that cannot
#    reach the server would otherwise hang this script (and cloud-init)
#    forever. Readiness is polled below with a timeout instead.
# ---------------------------------------------------------------------------
systemctl disable --now "${OTHER_UNIT}" >/dev/null 2>&1 || true

log "Enabling and starting ${UNIT}..."
systemctl reset-failed "${UNIT}" 2>/dev/null || true
systemctl enable "${UNIT}"
systemctl start --no-block "${UNIT}"

# ---------------------------------------------------------------------------
# 6. Wait for readiness.
# ---------------------------------------------------------------------------
wait_server() {
  local attempt api_ready=false node_name
  node_name="$(hostname | tr '[:upper:]' '[:lower:]')"

  log "Waiting for the Kubernetes API to become ready..."
  for attempt in $(seq 1 "${API_MAX_ATTEMPTS}"); do
    if KUBECONFIG="${KUBECONFIG_PATH}" k3s kubectl get --raw='/readyz' >/dev/null 2>&1; then
      api_ready=true
      log "API ready after ${attempt} attempt(s)."
      break
    fi
    sleep 5
  done

  if [[ "${api_ready}" != "true" ]]; then
    systemctl status k3s --no-pager >&2 || true
    journalctl -u k3s --no-pager -n 50 >&2 || true
    fail "API did not become ready in time."
  fi

  # Look up this node by name, not items[0]: agents may already have joined
  # if this is a manual re-run.
  log "Waiting for node ${node_name} to register..."
  for attempt in $(seq 1 "${NODE_MAX_ATTEMPTS}"); do
    if KUBECONFIG="${KUBECONFIG_PATH}" k3s kubectl get node "${node_name}" >/dev/null 2>&1; then
      log "Node ${node_name} registered after ${attempt} attempt(s)."
      break
    fi
    if [[ "${attempt}" -eq "${NODE_MAX_ATTEMPTS}" ]]; then
      journalctl -u k3s --no-pager -n 50 >&2 || true
      fail "node ${node_name} did not register with the API server."
    fi
    sleep 5
  done

  log "Waiting for ${node_name} to reach Ready..."
  if ! KUBECONFIG="${KUBECONFIG_PATH}" k3s kubectl wait \
      --for=condition=Ready "node/${node_name}" --timeout=300s; then
    KUBECONFIG="${KUBECONFIG_PATH}" k3s kubectl get nodes -o wide >&2 || true
    fail "node did not reach Ready in time."
  fi

  log "Node taints:"
  KUBECONFIG="${KUBECONFIG_PATH}" k3s kubectl get node "${node_name}" \
    -o jsonpath='{range .spec.taints[*]}  {.key}={.value}:{.effect}{"\n"}{end}' || true
}

wait_agent() {
  local attempt

  # The kubelet health endpoint only answers ok once the agent has joined
  # the server and the kubelet is running.
  log "Waiting for the agent to join https://${DOMAIN}:6443 (up to $(( AGENT_MAX_ATTEMPTS * 5 / 60 )) min)..."
  for attempt in $(seq 1 "${AGENT_MAX_ATTEMPTS}"); do
    if [[ "$(curl -fsS --max-time 3 http://127.0.0.1:10248/healthz 2>/dev/null || true)" == "ok" ]]; then
      log "Agent joined and kubelet healthy after ${attempt} attempt(s)."
      return 0
    fi
    sleep 5
  done

  systemctl status k3s-agent --no-pager >&2 || true
  journalctl -u k3s-agent --no-pager -n 50 >&2 || true
  fail "agent did not join in time. k3s-agent stays enabled and keeps retrying; re-run this script once the server is reachable to complete first boot."
}

case "${K3S_ROLE}" in
  server) wait_server ;;
  agent)  wait_agent ;;
esac

# ---------------------------------------------------------------------------
# 7. Mark completion.
# ---------------------------------------------------------------------------
log "Writing sentinel ${SENTINEL}."
install -d -o root -g root -m 0755 /var/lib/red-k3s
date -u +%FT%TZ > "${SENTINEL}"
chmod 0644 "${SENTINEL}"

log "red-k3s first-boot setup complete (role: ${K3S_ROLE})."
if [[ "${K3S_ROLE}" == "server" ]]; then
  KUBECONFIG="${KUBECONFIG_PATH}" k3s kubectl get nodes -o wide --show-labels || true
fi
