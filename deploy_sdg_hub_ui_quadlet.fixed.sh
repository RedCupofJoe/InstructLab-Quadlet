#!/usr/bin/env bash
# Deploy the SDG Hub UI quadlet (enable --now)
set -euo pipefail
CONTAINER_FILE=${1:-sdg-hub-ui.container}
QUADLET_DIR="${HOME}/.config/containers/systemd"
PERSIST_DIR="${HOME}/instructlab-data"

mkdir -p "${QUADLET_DIR}"
install -m 0644 "${CONTAINER_FILE}" "${QUADLET_DIR}/$(basename -- "${CONTAINER_FILE}")"

mkdir -p "${PERSIST_DIR}" "${PERSIST_DIR}/.cache"
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  if sudo -n true 2>/dev/null; then
    sudo chcon -Rt container_file_t "${PERSIST_DIR}" || true
  fi
fi

loginctl enable-linger "${USER}"
systemctl --user daemon-reload

SERVICE_NAME="$(basename -- "${CONTAINER_FILE}")"
SERVICE_NAME="${SERVICE_NAME%.container}.service"
systemctl --user enable --now "${SERVICE_NAME}"
echo "Deployed ${SERVICE_NAME}. Visit http://127.0.0.1:8999  (token: sdg)"
