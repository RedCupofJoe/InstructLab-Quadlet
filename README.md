# InstructLab-Quadlet  
Rootless, GPU-enabled Quadlet stack for AI development with InstructLab, SDG Hub, and interactive UIs

---

## 📘 Overview

This repository contains a set of **Podman Quadlet unit files** and one-shot **deploy scripts** that create a persistent, GPU-accelerated AI workspace.  
All containers share a common persistent volume (`~/instructlab-data`) and automatically restart on boot via **systemd --user** + **loginctl lingering**.

### Included Quadlets
| Quadlet | Purpose | UI | GPU |
|----------|----------|----|-----|
| `instructlab-gpu.container` | Base GPU runtime for InstructLab development | ❌ | ✅ |
| `instructlab-ui.container` | JupyterLab-based UI for interactive notebooks/tests | ✅ | ✅ |
| `sdg-hub-ui.container` | SDG Hub (synthetic data generation) UI | ✅ | ✅ |

Each is deployed with its corresponding `deploy_*.sh` script.

---

## Requirements

| Component | Minimum Version | Notes |
|------------|-----------------|-------|
| **OS** | RHEL 9 / Fedora 40+ / UBI9 host | SELinux supported |
| **Podman** | ≥ 5.0 | Quadlet + systemd integration required |
| **Systemd** | Enabled with user sessions | Needed for rootless services |
| **NVIDIA Drivers** | Latest production driver | Must support CUDA 12.6 |
| **NVIDIA Container Toolkit** | ≥ 1.16 | Enables GPU passthrough into Podman containers |

Verify:
```bash
nvidia-smi
podman info | grep -A5 'nvidia'
```

If the second command shows no NVIDIA devices, install or repair the **NVIDIA Container Toolkit** as described below in the troubleshooting section.

---

## Deployment

Each deploy script:
1. Copies the Quadlet into `~/.config/containers/systemd/`
2. Creates the shared persistent directory (`~/instructlab-data`)
3. Enables lingering for your user (`loginctl enable-linger "$USER"`)
4. Reloads systemd, enables, and starts the service

### Example: Deploy the GPU Core
```bash
bash deploy_instructlab_quadlet.sh
```

### Example: Deploy the InstructLab UI
```bash
bash deploy_instructlab_ui_quadlet.sh
```

### Example: Deploy the SDG Hub UI
```bash
bash deploy_sdg_hub_ui_quadlet.sh
```

> Each service will persist across reboots and share the same workspace under `~/instructlab-data`.

---

## 💾 Persistent Volume Layout

```
~/instructlab-data/
├── .cache/          # pip & model cache
├── instructlab/     # source repo (if cloned here)
├── notebooks/       # notebooks from UI containers
├── sdg_hub/         # SDG Hub configs and assets
└── README.md        # auto-created reference file
```

All containers mount this path as `/workspace`.

---

## Verifying Services

List running containers:
```bash
podman ps
```

View logs:
```bash
journalctl --user -u instructlab-gpu -f
journalctl --user -u instructlab-ui -f
journalctl --user -u sdg-hub-ui -f
```

Restart or stop:
```bash
systemctl --user restart instructlab-ui.service
systemctl --user stop instructlab-gpu.service
```

---

## Troubleshooting Guide

### 1. NVIDIA GPU Not Detected in Container
**Symptoms:**
- `podman exec -it instructlab-gpu nvidia-smi` fails or returns “command not found”.
- Container starts, but training code throws `CUDA driver not found`.

**Root Cause:**
The **NVIDIA Container Toolkit** hook is missing or outdated after host upgrade.

**Fix:**
```bash
# Reinstall or repair toolkit
sudo dnf remove -y nvidia-container-toolkit
sudo dnf install -y nvidia-container-toolkit

# Reload OCI hooks and restart Podman
sudo systemctl restart podman
podman info | grep -A5 'nvidia'

# Verify inside container
podman exec -it instructlab-gpu nvidia-smi
```

**Check the OCI hook:**
```bash
ls /usr/share/containers/oci/hooks.d/ | grep nvidia
```
If missing, re-run the NVIDIA toolkit installer or reinstall via your driver package.

---

### 2. SELinux Denials (`AVC: denied { read }` or `dev/nvidia0` errors)
**Fix:**
Option 1 — disable label confinement in your Quadlet (already default):
```ini
SecurityLabelDisable=true
```
Option 2 — relabel your PV for container sharing:
```bash
sudo chcon -Rt container_file_t ~/instructlab-data
```

---

### 3. Podman Systemd Daemon Doesn’t Start on Reboot
**Fix:**
Ensure lingering is active:
```bash
loginctl show-user $USER | grep Linger
# If "Linger=no":
loginctl enable-linger $USER
```

---

### 4. Container Image Pulls Fail Offline
Mirror your CUDA base image locally:
```bash
podman pull docker.io/nvidia/cuda:12.6.0-cudnn-runtime-ubi9
podman tag docker.io/nvidia/cuda:12.6.0-cudnn-runtime-ubi9 localhost/cuda:12.6-ubi9
```
Then change the `Image=` line in each Quadlet:
```ini
Image=localhost/cuda:12.6-ubi9
```

---

### 5. Port Conflict (Jupyter UI won’t start)
If port 8888 is already in use, edit:
```ini
PublishPort=127.0.0.1:8890:8888/tcp
```
Then reload:
```bash
systemctl --user daemon-reload
systemctl --user restart instructlab-ui.service
```

---

## 🔄 Upgrade Guide

### A. Host-Level (Driver / Toolkit)
After upgrading the host OS, GPU driver, or Podman version:

1. **Verify NVIDIA devices still appear:**
   ```bash
   nvidia-smi
   podman info | grep -A5 'nvidia'
   ```
2. **If missing, re-run:**
   ```bash
   sudo dnf reinstall -y nvidia-driver nvidia-container-toolkit
   sudo systemctl restart podman
   ```
3. **Reload your user daemon and restart containers:**
   ```bash
   systemctl --user daemon-reload
   systemctl --user restart instructlab-gpu.service instructlab-ui.service sdg-hub-ui.service
   ```

---

### B. Quadlet / Repo Upgrades
To update this repo’s unit files or scripts:
```bash
cd ~/InstructLab-Quadlet
git pull
systemctl --user daemon-reload
systemctl --user restart instructlab-gpu.service instructlab-ui.service sdg-hub-ui.service
```

---

### C. Container Image Updates
Refresh all CUDA-based images:
```bash
podman pull docker.io/nvidia/cuda:12.6.0-cudnn-runtime-ubi9
```

Or update SDG Hub / InstructLab dependencies from inside a running container:
```bash
podman exec -it instructlab-gpu bash
python3.11 -m pip install --upgrade instructlab sdg-hub jupyterlab
exit
```

---

## Directory Summary

```
InstructLab-Quadlet/
├── instructlab-gpu.container          # Base runtime (headless)
├── instructlab-ui.container           # InstructLab Jupyter UI
├── sdg-hub-ui.container               # SDG Hub UI
├── deploy_instructlab_quadlet.sh      # GPU service deploy script
├── deploy_instructlab_ui_quadlet.sh   # UI service deploy script
├── deploy_sdg_hub_ui_quadlet.sh       # SDG Hub service deploy script
└── README.md                          # This guide
```

---

## Notes & Best Practices

- Always use **rootless Podman** unless a system-wide service is required.  
- Maintain consistent `Volume=` paths across Quadlets for shared workspace.
- Use `systemctl --user enable --now ...` so units persist automatically.
- Periodically prune unused images:
  ```bash
  podman image prune
  ```

---

## References

- **InstructLab**: [github.com/instructlab/instructlab](https://github.com/instructlab/instructlab)  
- **SDG Hub**: [github.com/Red-Hat-AI-Innovation-Team/sdg_hub](https://github.com/Red-Hat-AI-Innovation-Team/sdg_hub)  
- **NVIDIA Container Toolkit**: [docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/)  
- **Podman Quadlets**: [Red Hat Blog – Systemd Quadlet Primer](https://www.redhat.com/sysadmin/podman-systemd-quadlet)

---

**Maintainer:** [O’Neill Joseph](https://github.com/RedCupofJoe)  
**License:** Apache-2.0  
