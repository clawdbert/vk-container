# Vibe-Kanban Podman Service

Container deployment for [vibe-kanban](https://www.npmjs.com/package/vibe-kanban) using Podman and systemd user services, with CI/CD via GitHub Actions and Tailscale networking.

## Prerequisites

- Linux host with [Podman](https://podman.io/) installed (rootless)
- systemd with user lingering enabled (`loginctl enable-linger deploy`)
- [Tailscale](https://tailscale.com/) connected to your tailnet
- A `deploy` user with write access to `/srv/vibe-kanban`

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/clawdbert/vk-container.git
cd vk-container
```

### 2. Create host directories

```bash
sudo mkdir -p /srv/vibe-kanban
sudo chown deploy:deploy /srv/vibe-kanban
mkdir -p /var/tmp/vibe-kanban
mkdir -p /home/deploy/projects
mkdir -p /home/deploy/.config/systemd/user
```

### 3. Copy the deploy script

```bash
cp deploy.sh /srv/vibe-kanban/deploy.sh
chmod +x /srv/vibe-kanban/deploy.sh
```

### 4. Get your Tailscale FQDN

```bash
tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//'
```

### 5. Deploy an instance

```bash
# deploy.sh <instance> <version> <ts_fqdn>
bash deploy.sh dev 0.1.36 your-host.tailnet-name.ts.net
```

This will:
- Create Podman volumes for persistent data
- Build the container image from the Containerfile (if not already built)
- Generate an `.env` file at `/srv/vibe-kanban/<instance>/.env`
- Install and start a systemd user service (`vk-dev` or `vk-prod`)

### 6. Verify

```bash
systemctl --user status vk-dev
```

## Instance Layout

| Instance | Frontend Port | Backend Port | NODE_ENV    | Managed By   |
|----------|--------------|--------------|-------------|--------------|
| project  | 3927         | 3930         | development | this repo    |
| dev      | 3928         | 3931         | development | CI (dev branch) |
| prod     | 3929         | 3932         | production  | CI (main branch) |

All three instances bind to `127.0.0.1` and are accessed via Tailscale. Each instance has its own isolated set of Podman volumes (`vk-<instance>-share`, `vk-<instance>-home`, `vk-<instance>-config`), so no data is shared between them.

> **Warning:** The `.env` in `/srv/vibe-kanban/<instance>/` (dev/prod) and the `.env` in `projects/vk-container/` (project) must reference different Podman named volumes. If two instances point to the same volumes, they will corrupt each other's data.

## Managing the Service

```bash
# View logs
journalctl --user -u vk-dev -f

# Restart
systemctl --user restart vk-dev

# Stop
systemctl --user stop vk-dev
```

## CI/CD

Pushes to `dev` deploy the dev instance; pushes to `main` deploy prod. The GitHub Actions workflow joins your tailnet via Tailscale OAuth, then SSHs into the target host to run `deploy.sh`.

### Required GitHub Secrets

| Secret              | Description                          |
|---------------------|--------------------------------------|
| TS_OAUTH_CLIENT_ID  | Tailscale OAuth client ID            |
| TS_OAUTH_CLIENT_SECRET | Tailscale OAuth client secret     |
| DEPLOY_SSH_KEY      | SSH private key for the deploy user  |
| SANDBOXES_TS_HOST   | Tailscale hostname of the target     |
| TS_FQDN             | Tailscale FQDN for CORS origins      |

## Upgrading the App Version

Edit `VERSION` and push:

```bash
echo "0.2.0" > VERSION
git add VERSION && git commit -m "bump to 0.2.0" && git push
```

CI will deploy the new version automatically.
