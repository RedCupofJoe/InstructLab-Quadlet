#!/usr/bin/env bash
# Purpose:
#   Rootless one-shot setup to:
#     1) place an existing Quadlet .container file into ~/.config/containers/systemd/
#     2) create a persistent data directory for bind-mounts
#     3) enable user lingering so the service survives reboots without an interactive login
#
# Usage:
#   bash deploy_instructlab_quadlet.sh
#   bash deploy_instructlab_quadlet.sh --container-file path/to/instructlab-gpu.container \
#                                      --persist-dir ~/instructlab-data
#
# Notes:
#   - Assumes the .container file already exists in your git repo.
#   - Requires: podman, systemd --user, loginctl (for enable-linger).
#   - The .container file must define the bind-mount path that matches PERSIST_DIR below,
#     or you should adjust either the file or PERSIST_DIR to match.

set -euo pipefail

########################################
# --------- CONFIG DEFAULTS -----------
########################################

# Default location of the .container file (relative to where you run the script).
# You can override with: --container-file /path/to/file.container
CONTAINER_FILE_DEFAULT="instructlab-gpu.container"

# Where user-level Quadlet unit files live for rootless Podman/systemd.
QUADLET_DIR_DEFAULT="${HOME}/.config/containers/systemd"

# Persistent host directory to be bind-mounted by the Quadlet (must match your .container Volume=).
# You can override with: --persist-dir /some/path
PERSIST_DIR_DEFAULT="${HOME}/instructlab-data"

########################################
# --------- CLI ARG PARSING -----------
########################################
CONTAINER_FILE="${CONTAINER_FILE_DEFAULT}"
QUADLET_DIR="${QUADLET_DIR_DEFAULT}"
PERSIST_DIR="${PERSIST_DIR_DEFAULT}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --container-file)
      CONTAINER_FILE="$2"; shift 2;;
    --persist-dir)
      PERSIST_DIR="$2"; shift 2;;
    --quadlet-dir)
      QUADLET_DIR="$2"; shift 2;;
    -h|--help)
      grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *)
      echo "[ERROR] Unknown arg: $1"; exit 1;;
  esac
done

########################################
# --------- PRECHECKS ------------------
########################################

# Ensure the container file is present.
if [[ ! -f "${CONTAINER_FILE}" ]]; then
  echo "[ERROR] Quadlet file not found: ${CONTAINER_FILE}" >&2
  exit 1
fi

# These tools are required.
for bin in podman systemctl loginctl; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "[ERROR] '${bin}' not found. Please install it first." >&2
    exit 1
  fi
done

# Systemd --user should be available; status may fail if no user session yet,
# but we can still install units and enable lingering.
if ! systemctl --user daemon-reload >/dev/null 2>&1; then
  echo "[WARN] systemctl --user daemon-reload had a non-zero status."
  echo "      This can happen without an active user session; proceeding anyway."
fi

########################################
# --------- COPY QUADLET FILE ----------
########################################

# Create the user Quadlet directory and copy the .container file.
mkdir -p "${QUADLET_DIR}"

# Derive a clean filename (e.g., instructlab-gpu.container) and service name (instructlab-gpu.service).
UNIT_BASENAME="$(basename -- "${CONTAINER_FILE}")"
UNIT_NAME="${UNIT_BASENAME}"                      # e.g., instructlab-gpu.container
SERVICE_NAME="${UNIT_BASENAME%.container}.service" # e.g., instructlab-gpu.service

echo "[INFO] Installing Quadlet to: ${QUADLET_DIR}/${UNIT_BASENAME}"
install -m 0644 "${CONTAINER_FILE}" "${QUADLET_DIR}/${UNIT_BASENAME}"

########################################
# --------- PERSISTENT VOLUME ----------
########################################

# Create the persistent directory that your Quadlet binds into the container (e.g., /workspace).
echo "[INFO] Ensuring persistent data dir exists: ${PERSIST_DIR}"
mkdir -p "${PERSIST_DIR}"

# If SELinux is enforcing, label the directory so containers can access it.
if command -v selinuxenabled >/dev/null 2>&1 && selinuxenabled; then
  echo "[INFO] SELinux detected; setting container_file_t on ${PERSIST_DIR} (safe to re-run)."
  # chcon may require sudo depending on your environment/policy
  if sudo -n true 2>/dev/null; then
    sudo chcon -Rt container_file_t "${PERSIST_DIR}" || true
  else
    echo "[WARN] sudo not available non-interactively; skipping chcon. If you hit SELinux denials, run:"
    echo "       sudo chcon -Rt container_file_t ${PERSIST_DIR}"
  fi
fi

########################################
# --------- LINGER & ENABLE ------------
########################################

# Make the user’s systemd user manager run without a login session (persist across reboots).
echo "[INFO] Enabling linger for user: ${USER}"
loginctl enable-linger "${USER}"

# Reload user manager so it sees the new Quadlet unit.
echo "[INFO] Reloading user systemd daemon"
systemctl --user daemon-reload

# Enable + start the service now.
echo "[INFO] Enabling and starting service: ${SERVICE_NAME}"
systemctl --user enable --now "${SERVICE_NAME}"

########################################
# -------------- DONE ------------------
########################################

# Optional: show a quick health peek; don't fail the script if this is empty.
echo "[INFO] Active containers with name matching the unit (if any):"
podman ps --filter "name=${SERVICE_NAME%.service}" || true

cat <<EOF

✅ Done.

Installed unit:   ${QUADLET_DIR}/${UNIT_BASENAME}
Persistent dir:   ${PERSIST_DIR}
Lingering:        enabled for ${USER}
Service:          ${SERVICE_NAME}

Useful commands:
  # Logs (follow):
  journalctl --user -u ${SERVICE_NAME} -f

  # Status:
  systemctl --user status ${SERVICE_NAME}

  # Edit Quadlet, then reload & restart:
  $EDITOR ${QUADLET_DIR}/${UNIT_BASENAME}
  systemctl --user daemon-reload
  systemctl --user restart ${SERVICE_NAME}

  # Enter container shell (name usually matches ContainerName in your .container):
  podman ps
  podman exec -it instructlab-gpu bash

To disable later:
  systemctl --user disable --now ${SERVICE_NAME}
  loginctl disable-linger ${USER}

EOF
