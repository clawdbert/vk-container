# Vibe-Kanban Podman Service

Container deployment for [vibe-kanban](https://www.npmjs.com/package/vibe-kanban) using Podman and systemd user services, with CI/CD via GitHub Actions and Tailscale networking.

## How It Works

This repo is the sole source of truth for deploying vibe-kanban. It contains the Containerfile, deploy script, systemd unit template, and CI workflow — no application code. The app itself is the `vibe-kanban` npm package, downloaded at container startup via `npx`.

Each instance gets its own **runtime directory** containing everything needed to run that version:

| Instance | Runtime Directory                        | Deployed By        |
|----------|------------------------------------------|--------------------|
| project  | `/home/deploy/projects/vk-container/`    | manual (this repo) |
| dev      | `/srv/vibe-kanban/dev/`                  | CI (dev branch)    |
| prod     | `/srv/vibe-kanban/prod/`                 | CI (main branch)   |

CI copies `Containerfile`, `deploy.sh`, and `VERSION` from the repo into the instance's runtime directory before running `deploy.sh`. This means each instance has its own copy of the deployment files at its own version level.

## Instance Layout

| Instance | Frontend Port | Backend Port | NODE_ENV    |
|----------|--------------|--------------|-------------|
| project  | 3927         | 3930         | development |
| dev      | 3928         | 3931         | development |
| prod     | 3929         | 3932         | production  |

All three instances bind to `127.0.0.1` and are accessed via Tailscale. Each instance has its own isolated set of Podman volumes (`vk-<instance>-share`, `vk-<instance>-home`, `vk-<instance>-config`), so no data is shared between them.

> **Warning:** The `.env` in each runtime directory must reference different Podman named volumes. If two instances point to the same volumes, they will corrupt each other's data.

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

### 3. Get your Tailscale FQDN

```bash
tailscale status --json | jq -r '.Self.DNSName' | sed 's/\.$//'
```

### 4. Deploy an instance

```bash
# deploy.sh <instance> <version> <ts_fqdn>
bash deploy.sh dev 0.1.36 your-host.tailnet-name.ts.net
```

This will:
- Create Podman volumes for persistent data
- Build the container image from the Containerfile (if not already built)
- Generate `.env` in the runtime directory
- Install and start a systemd user service (`vk-dev` or `vk-prod`)

### 5. Verify

```bash
systemctl --user status vk-dev
```

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

Pushes to `dev` deploy the dev instance; pushes to `main` deploy prod. The workflow:

1. Joins the tailnet via Tailscale OAuth
2. Copies `Containerfile`, `deploy.sh`, and `VERSION` to `/srv/vibe-kanban/<instance>/` on the host
3. SSHs in and runs `deploy.sh` from the runtime directory
4. `deploy.sh` builds the image, generates `.env`, installs the systemd unit, and restarts the service

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
