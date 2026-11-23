#!/usr/bin/env bash
# Fetch a k3s admin kubeconfig from a server over SSM.
#
# Usage: get-kubeconfig.sh -u URL [options]
#
#   -u, --url URL         API URL written to the file (required), e.g. https://cluster.example.com:6443
#   -n, --name NAME       Server's EC2 Name tag        (default: red-k3s-server)
#   -o, --out FILE        Output kubeconfig path       (default: ~/.kube/red-k3s.yaml)
#   -c, --context NAME    Cluster/user/context name    (default: output file name without extension)
#   -i, --instance ID     Skip the Name lookup and use this instance ID
#   -h, --help            Show this help
#
# Each option can also be set by env var: K3S_API_URL, K3S_SERVER_NAME,
# KUBECONFIG_OUT, K3S_CONTEXT, K3S_INSTANCE_ID. Flags win over env vars.
#
# Uses your current AWS profile/region (falls back to us-east-1).
# The output is a cluster-admin credential: written 0600, never printed.
set -euo pipefail

API_URL="${K3S_API_URL:-}"
SERVER_NAME="${K3S_SERVER_NAME:-red-k3s-server}"
OUT="${KUBECONFIG_OUT:-${HOME}/.kube/red-k3s.yaml}"
CONTEXT="${K3S_CONTEXT:-}"
INSTANCE_ID="${K3S_INSTANCE_ID:-}"
export AWS_REGION="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-1}}"

usage() { sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; }
die()   { echo "error: $*" >&2; exit 1; }

need_value() { [[ $# -ge 2 && -n "$2" && "$2" != -* ]] || die "$1 needs a value."; }

# --- Parse flags -----------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -u|--url)      need_value "$@"; API_URL="$2";     shift 2 ;;
    -n|--name)     need_value "$@"; SERVER_NAME="$2"; shift 2 ;;
    -o|--out)      need_value "$@"; OUT="$2";         shift 2 ;;
    -c|--context)  need_value "$@"; CONTEXT="$2";     shift 2 ;;
    -i|--instance) need_value "$@"; INSTANCE_ID="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *)             usage >&2; die "unknown option: $1" ;;
  esac
done

[[ -n "${API_URL}" ]] || { usage >&2; die "--url is required (or set K3S_API_URL)."; }

# Expand a leading ~ in --out (flags don't get shell tilde expansion when quoted).
OUT="${OUT/#\~/${HOME}}"

# Context defaults to the output file's name without its extension.
if [[ -z "${CONTEXT}" ]]; then
  CONTEXT="$(basename "${OUT}")"
  CONTEXT="${CONTEXT%.*}"
fi

[[ "${API_URL}" =~ ^https://[^/[:space:]]+(:[0-9]+)?$ ]] \
  || die "invalid API URL '${API_URL}' (expected https://host[:port])."
[[ "${CONTEXT}" =~ ^[A-Za-z0-9._-]+$ ]] \
  || die "invalid context name '${CONTEXT}' (letters, digits, . _ - only)."

# --- Find the server -------------------------------------------------------
if [[ -z "${INSTANCE_ID}" ]]; then
  STATE=""
  read -r INSTANCE_ID STATE < <(
    aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=${SERVER_NAME}" \
                "Name=instance-state-name,Values=pending,running,stopping,stopped" \
      --query 'Reservations[].Instances[0].[InstanceId,State.Name]' \
      --output text
  ) || true

  [[ -n "${INSTANCE_ID:-}" && "${INSTANCE_ID}" != "None" ]] \
    || die "no instance tagged Name=${SERVER_NAME} in ${AWS_REGION}. Check your AWS profile."
  [[ "${STATE}" == "running" ]] \
    || die "${SERVER_NAME} (${INSTANCE_ID}) is ${STATE}. Start the cluster first."
fi

[[ "${INSTANCE_ID}" =~ ^i-[0-9a-f]+$ ]] || die "'${INSTANCE_ID}' is not an instance ID."

# --- Fetch into a private temp file ----------------------------------------
umask 077
mkdir -p "$(dirname "${OUT}")"
chmod 700 "$(dirname "${OUT}")"

TMP="$(mktemp "${OUT}.XXXXXX")"
trap 'rm -f "${TMP}" "${TMP}.bak"' EXIT

echo "Fetching kubeconfig from ${SERVER_NAME} (${INSTANCE_ID})..."
aws ssm start-session \
  --target "${INSTANCE_ID}" \
  --document-name AWS-StartInteractiveCommand \
  --parameters command="sudo cat /etc/rancher/k3s/k3s.yaml" \
| tr -d '\r' \
| sed -n '/^apiVersion:/,/^Exiting session/p' \
| sed '/^Exiting session/d' \
> "${TMP}"

grep -q '^apiVersion:' "${TMP}" \
  || die "no kubeconfig received. Check SSM access and that the server finished first boot."

# --- Point at the API URL; rename k3s's generic "default" names ------------
sed -i.bak \
  -e "s#https://127.0.0.1:6443#${API_URL}#" \
  -e "s/: default\$/: ${CONTEXT}/" \
  "${TMP}"

mv -f "${TMP}" "${OUT}"
echo "Wrote ${OUT} ($(stat -f '%Lp' "${OUT}" 2>/dev/null || stat -c '%a' "${OUT}")), context '${CONTEXT}'."

KUBECONFIG="${OUT}" kubectl get nodes
