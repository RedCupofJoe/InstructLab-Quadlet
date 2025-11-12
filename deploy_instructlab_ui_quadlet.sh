#!/usr/bin/env bash
# Purpose:
#   Deploy the InstructLab UI Quadlet (rootless) by:
#     1) copying the 'instructlab-ui.container' unit into ~/.config/containers/systemd/
#     2) creating the persistent data directory used by the Volume= lines
#     3) enabling lingering so the service survives reboots without interactive login
#     4) enabling and starting the UI service
#
# Usage:
#   bash deploy_instructlab_ui_quadlet.sh
#   bash deploy_instructlab_ui_quadlet.sh --container-file ./path/to/instructlab-ui.container --persist-dir ~/instructlab-data
#
# Security:
#   The Quadlet publishes 127.0.0.1:8888 by default. Change PublishPort in the unit if you need LAN access.

set -euo pipefail

# -------- Defaults --------
CONTAINER_FILE_DEFAULT="instructlab-ui.container"
QUADLET_DIR_DEFAULT="${HOME}/.config/containers/systemd"
PERSIST_DIR_DEFAULT="${HOME}/instructlab-data"

# -------- Args --------
CONTAINER_FILE="${CONTAINER_FILE_DEFAULT}"
QUADLET_DIR="${QUADLET_DIR_DEFAULT}"
PERSIST_DIR="${PERSIST_DIR_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container-file) CONTAINER_FILE="$2"; shift 2;;
    --persist-dir)    PERSIST_DIR="$2";    shift 2;;
    --quadlet-dir)    QUADLET_DIR="$2";    shift 2;;
    -h|--help)
      sed -n '1,80p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "[ERROR] Unknown arg: $1" >&2; exit 1;;
  esac
done

# -------- Prechecks --------
[[ -f "${CONTAINER_FILE}" ]] || { echo "[ERROR] Missing unit: ${CONTAINER_FILE}" >&2; exit 1; }

for bin in podman systemctl loginctl; do
  command -v "${bin}" >/dev/null 2>&1 || { echo "[ERROR] '${bin}' not found." >&2; exit 1; }
done

# -------- Install Quadlet --------
mkdir -p "${QUADLET_DIR}"
UNIT_BASENAME="$(basename -- "${CONTAINER_FILE}")"
SERVICE_NAME="${UNIT_BASENAME%.container}.service"

echo "[INFO] Installing UI Quadlet to: ${QUADLET_DIR}/${UNIT_BASENAME}"
install -m 0644 "${CONTAINER_FILE}" "${QUADLET_DIR}/${UNIT_BASENAME}"

# -------- Persistent volume dir --------
echo "[INFO] Ensuring persistent dir exists: ${PERSIST_DIR}"
mkdir -p "${PERSIST_DIR}" "${PERSIST_DIR}/.cache"

# SELinux labeling (optional; helps avoid AVC denials)
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  if sudo -n true 2>/dev/null; then
    echo "[INFO] SELinux detected; labeling ${PERSIST_DIR} for containers"
    sudo chcon -Rt container_file_t "${PERSIST_DIR}" || true
  else
    echo "[WARN] sudo not available non-interactively; if you see SELinux denials, run:"
    echo "       sudo chcon -Rt container_file_t ${PERSIST_DIR}"
  fi
fi

# -------- Persistence across reboot --------
echo "[INFO] Enabling linger for user: ${USER}"
loginctl enable-linger "${USER}"

# -------- Start service --------
echo "[INFO] Reloading user daemon & starting '${SERVICE_NAME}'"
systemctl --user daemon-reload
systemctl --user start "${SERVICE_NAME}"

# -------- Info --------
cat <<EOF

✅ UI service deployed.

Service:        ${SERVICE_NAME}
Quadlet path:   ${QUADLET_DIR}/${UNIT_BASENAME}
Persistent dir: ${PERSIST_DIR}
Lingering:      enabled for ${USER}

Open the UI:
  http://127.0.0.1:8888
  (Token defaults to: 'instructlab' — change JUPYTER_TOKEN in the unit if desired.)

Useful commands:
  journalctl --user -u ${SERVICE_NAME} -f
  systemctl  --user status ${SERVICE_NAME}
  systemctl  --user restart ${SERVICE_NAME}
  podman ps --filter "name=instructlab-ui"

To remove:
  systemctl --user disable --now ${SERVICE_NAME}
  rm -f "${QUADLET_DIR}/${UNIT_BASENAME}"
  systemctl --user daemon-reload
  loginctl disable-linger "${USER}"
EOF
