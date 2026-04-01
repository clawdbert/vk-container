#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"

echo "==> Building container image..."
podman build -t vk-node:22-bookworm-slim "$SCRIPT_DIR"

echo "==> Creating named volumes (idempotent)..."
podman volume create vk-data-share 2>/dev/null || true
podman volume create vk-data-home  2>/dev/null || true
podman volume create vk-config     2>/dev/null || true

echo "==> Creating bind-mount directories..."
mkdir -p /var/tmp/vibe-kanban
mkdir -p /home/deploy/projects

if [ ! -f "$SCRIPT_DIR/.env" ]; then
  echo "ERROR: .env not found. Copy .env.example to .env and fill in your values."
  exit 1
fi

echo "==> Installing systemd unit..."
mkdir -p "$UNIT_DIR"
cp "$SCRIPT_DIR/vibe-kanban.service" "$UNIT_DIR/vibe-kanban.service"
systemctl --user daemon-reload
systemctl --user enable vibe-kanban

echo "==> Starting service..."
systemctl --user restart vibe-kanban

echo ""
echo "Done. Check status with:"
echo "  systemctl --user status vibe-kanban"
echo "  journalctl --user -u vibe-kanban -f"
echo ""
echo "Remaining manual steps (require sudo):"
echo "  sudo loginctl enable-linger deploy"
echo "  sudo tailscale serve --bg --https=3927 http://localhost:3927"
