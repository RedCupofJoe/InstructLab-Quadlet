#!/usr/bin/env bash
# Deploy the GPU quadlet and enable it to start at login and boot (with linger)
set -euo pipefail
CONTAINER_FILE=${1:-instructlab-gpu.container}
QUADLET_DIR="${HOME}/.config/containers/systemd"
PERSIST_DIR="${HOME}/instructlab-data"

command -v podman >/dev/null || { echo "[ERROR] podman missing"; exit 1; }
command -v systemctl >/dev/null || { echo "[ERROR] systemctl missing"; exit 1; }
command -v loginctl >/dev/null || { echo "[ERROR] loginctl missing"; exit 1; }

mkdir -p "${QUADLET_DIR}"
install -m 0644 "${CONTAINER_FILE}" "${QUADLET_DIR}/$(basename -- "${CONTAINER_FILE}")"

mkdir -p "${PERSIST_DIR}" "${PERSIST_DIR}/.cache"
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  if sudo -n true 2>/dev/null; then
    sudo chcon -Rt container_file_t "${PERSIST_DIR}" || true
  else
    echo "[WARN] SELinux is enforcing. Consider: sudo chcon -Rt container_file_t ${PERSIST_DIR}"
  fi
fi

loginctl enable-linger "${USER}"
systemctl --user daemon-reload

SERVICE_NAME="$(basename -- "${CONTAINER_FILE}")"
SERVICE_NAME="${SERVICE_NAME%.container}.service"

# Enable + start (previous script only started; enabling creates the symlink for autostart)
systemctl --user enable --now "${SERVICE_NAME}"

echo "Deployed ${SERVICE_NAME}. Logs: journalctl --user -u ${SERVICE_NAME} -f"
