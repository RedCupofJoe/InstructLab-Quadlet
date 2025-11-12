#!/usr/bin/env bash
# Deploy SDG Hub UI Quadlet (rootless):
#   1) copy sdg-hub-ui.container to ~/.config/containers/systemd/
#   2) create/label the shared PV at ~/instructlab-data
#   3) enable lingering so it autostarts after reboot
#   4) enable + start the systemd --user service
#
# Usage:
#   bash deploy_sdg_hub_ui_quadlet.sh
#   bash deploy_sdg_hub_ui_quadlet.sh --container-file ./path/to/sdg-hub-ui.container --persist-dir ~/instructlab-data

set -euo pipefail

CONTAINER_FILE_DEFAULT="sdg-hub-ui.container"
QUADLET_DIR_DEFAULT="${HOME}/.config/containers/systemd"
PERSIST_DIR_DEFAULT="${HOME}/instructlab-data"

CONTAINER_FILE="${CONTAINER_FILE_DEFAULT}"
QUADLET_DIR="${QUADLET_DIR_DEFAULT}"
PERSIST_DIR="${PERSIST_DIR_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container-file) CONTAINER_FILE="$2"; shift 2;;
    --persist-dir)    PERSIST_DIR="$2";    shift 2;;
    --quadlet-dir)    QUADLET_DIR="$2";    shift 2;;
    -h|--help) sed -n '1,80p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "[ERROR] Unknown arg: $1" >&2; exit 1;;
  esac
done

# --- Prechecks ---
[[ -f "${CONTAINER_FILE}" ]] || { echo "[ERROR] Missing unit: ${CONTAINER_FILE}" >&2; exit 1; }
for bin in podman systemctl loginctl; do
  command -v "${bin}" >/dev/null 2>&1 || { echo "[ERROR] '${bin}' not found." >&2; exit 1; }
done

# --- Install Quadlet ---
mkdir -p "${QUADLET_DIR}"
UNIT_BASENAME="$(basename -- "${CONTAINER_FILE}")"
SERVICE_NAME="${UNIT_BASENAME%.container}.service"

echo "[INFO] Installing Quadlet to: ${QUADLET_DIR}/${UNIT_BASENAME}"
install -m 0644 "${CONTAINER_FILE}" "${QUADLET_DIR}/${UNIT_BASENAME}"

# --- Shared persistent volume (same path as your other units) ---
echo "[INFO] Ensuring persistent dir exists: ${PERSIST_DIR}"
mkdir -p "${PERSIST_DIR}" "${PERSIST_DIR}/.cache"

# Optional SELinux label for shared container access
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  if sudo -n true 2>/dev/null; then
    echo "[INFO] SELinux detected; labeling ${PERSIST_DIR} for containers"
    sudo chcon -Rt container_file_t "${PERSIST_DIR}" || true
  else
    echo "[WARN] sudo not available non-interactively; if you see SELinux denials, run:"
    echo "       sudo chcon -Rt container_file_t ${PERSIST_DIR}"
  fi
fi

# --- Persist across reboots (no interactive login needed) ---
echo "[INFO] Enabling linger for user: ${USER}"
loginctl enable-linger "${USER}"

# --- Start service ---
echo "[INFO] Reloading user daemon & starting '${SERVICE_NAME}'"
systemctl --user daemon-reload
systemctl --user start "${SERVICE_NAME}"

echo
echo "✅ SDG Hub UI deployed."
echo "Service:        ${SERVICE_NAME}"
echo "Quadlet path:   ${QUADLET_DIR}/${UNIT_BASENAME}"
echo "Persistent dir: ${PERSIST_DIR}"
echo "Lingering:      enabled for ${USER}"
echo
echo "Open the UI at: http://127.0.0.1:8888"
echo "(Default token: 'sdg' — change JUPYTER_TOKEN in the unit as needed.)"
echo
echo "Logs:    journalctl --user -u ${SERVICE_NAME} -f"
echo "Status:  systemctl --user status ${SERVICE_NAME}"
echo "Restart: systemctl --user restart ${SERVICE_NAME}"
echo "Shell:   podman exec -it sdg-hub-ui bash"
