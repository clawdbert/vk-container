#!/usr/bin/env bash
set -euo pipefail

# Usage: deploy.sh <instance> <version> <ts_fqdn>
# instance: dev | prod   (project is not CI-deployed)

INSTANCE=${1:?instance required (dev|prod)}
VERSION=${2:?version required}
TS_FQDN=${3:?ts_fqdn required}

[[ "$INSTANCE" == "dev" || "$INSTANCE" == "prod" ]] \
  || { echo "instance must be dev or prod"; exit 1; }

# ── Derived values ────────────────────────────────────────────────────────────
case "$INSTANCE" in
  dev)
    PORT=3928; BACKEND_PORT=3931; NODE_ENV=development ;;
  prod)
    PORT=3929; BACKEND_PORT=3932; NODE_ENV=production ;;
esac

DEPLOY_DIR="/srv/vibe-kanban/${INSTANCE}"
UNIT_NAME="vk-${INSTANCE}"
UNIT_PATH="/home/deploy/.config/systemd/user/${UNIT_NAME}.service"

# ── 1. Ensure directories exist ───────────────────────────────────────────────
mkdir -p "${DEPLOY_DIR}"
mkdir -p /var/tmp/vibe-kanban
mkdir -p /home/deploy/projects

# ── 2. Create named volumes if absent ────────────────────────────────────────
for vol in "vk-${INSTANCE}-share" "vk-${INSTANCE}-home" "vk-${INSTANCE}-config"; do
  podman volume inspect "$vol" &>/dev/null || podman volume create "$vol"
done

# ── 3. Build container image ──────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "${SCRIPT_DIR}/Containerfile" ]; then
  podman build -t vk-node:22-bookworm-slim "${SCRIPT_DIR}"
else
  echo "ERROR: No Containerfile available at ${SCRIPT_DIR}"
  exit 1
fi

# ── 4. Write .env ─────────────────────────────────────────────────────────────
cat > "${DEPLOY_DIR}/.env" <<EOF
VK_INSTANCE=${INSTANCE}
PORT=${PORT}
BACKEND_PORT=${BACKEND_PORT}
HOST=0.0.0.0
NODE_ENV=${NODE_ENV}
HOME=/home/deploy
VK_CONTAINER_NAME=vk-${INSTANCE}
VK_SHARE_VOL=vk-${INSTANCE}-share
VK_HOME_VOL=vk-${INSTANCE}-home
VK_CONFIG_VOL=vk-${INSTANCE}-config
VK_ALLOWED_ORIGINS=https://${TS_FQDN}:${PORT}
VK_VERSION=${VERSION}
EOF

# ── 5. Write unit file ────────────────────────────────────────────────────────
cat > "${UNIT_PATH}" <<UNIT
[Unit]
Description=vibe-kanban (vk-${INSTANCE}) — Podman container
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=on-failure
RestartSec=10s
StartLimitIntervalSec=120s
StartLimitBurst=5

EnvironmentFile=${DEPLOY_DIR}/.env

ExecStartPre=-/usr/bin/podman rm -f \${VK_CONTAINER_NAME}
ExecStart=/usr/bin/podman run --rm \\
  --name \${VK_CONTAINER_NAME} \\
  -p 127.0.0.1:\${PORT}:\${PORT} \\
  -e PORT \\
  -e BACKEND_PORT \\
  -e HOST \\
  -e NODE_ENV \\
  -e HOME \\
  -e VK_ALLOWED_ORIGINS \\
  -v \${VK_SHARE_VOL}:/home/deploy/.local/share/vibe-kanban:rw \\
  -v \${VK_HOME_VOL}:/home/deploy/.vibe-kanban:rw \\
  -v \${VK_CONFIG_VOL}:/home/deploy/.config/vibe-kanban:rw \\
  -v /var/tmp/vibe-kanban:/var/tmp/vibe-kanban:rw \\
  -v /home/deploy/projects:/home/deploy/projects:rw \\
  -v /home/deploy/.nvm:/home/deploy/.nvm:ro \\
  --workdir /home/deploy \\
  localhost/vk-node:22-bookworm-slim \\
  npx --yes vibe-kanban@\${VK_VERSION}
ExecStop=/usr/bin/podman stop \${VK_CONTAINER_NAME}

[Install]
WantedBy=default.target
UNIT

# ── 6. Reload and restart ─────────────────────────────────────────────────────
systemctl --user daemon-reload
systemctl --user enable "${UNIT_NAME}"
systemctl --user restart "${UNIT_NAME}"

# ── 7. Verify ─────────────────────────────────────────────────────────────────
sleep 3
systemctl --user is-active --quiet "${UNIT_NAME}" \
  && echo "✓ ${UNIT_NAME} is running" \
  || { echo "✗ ${UNIT_NAME} failed"; journalctl --user -u "${UNIT_NAME}" -n 20 --no-pager; exit 1; }
