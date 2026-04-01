# Theory: Vibe-Kanban Container Deployment

## Problem

Vibe-Kanban is a Kanban board application distributed as an npm package. It needs a reliable, repeatable deployment mechanism that supports multiple instances (dev and prod) on the same host, with secure remote access and CI/CD automation. The challenge is not the application itself but the orchestration: getting the right version running in the right environment with correct networking, persistence, and service management — and doing so identically every time, triggered by a git push.

## Operating Theory

This repo is pure infrastructure-as-code. It contains no application logic — the app is pulled at runtime via `npx --yes vibe-kanban@${VK_VERSION}`. The deployment model is:

1. **Podman containers** (not Docker) run as user-level services, avoiding root and the Docker daemon.
2. **Systemd user services** manage container lifecycle — start, stop, restart, enable on boot.
3. **Named Podman volumes** persist application state across container restarts (share, home, config).
4. **Instance isolation** via naming conventions: `vk-dev-*` vs `vk-prod-*` volumes, separate ports (dev: 3928/3931, prod: 3929/3932), separate service units.
5. **Tailscale** provides secure network access — the containers bind to localhost, and Tailscale handles external routing.
6. **GitHub Actions** ties it together: push to `dev` branch deploys dev instance, push to `main` deploys prod. The workflow SSHs into the target host and runs `deploy.sh`.

The `deploy.sh` script is the single source of truth for deployment logic — it creates directories, builds the container image if needed, generates environment config, installs the systemd unit, and starts the service.

## Strategy

The approach is minimal and direct: one script, one service file, one container definition, one CI workflow. No Terraform, no Kubernetes, no Ansible — just shell scripting and systemd on a single host. This is appropriate for the scale (two instances on one machine) and keeps the operational surface small.

The version is tracked in a `VERSION` file at the repo root, which the CI workflow reads to determine what to deploy. This decouples "deploy the infrastructure" from "upgrade the app version" — both happen via the same git-push mechanism but are independently controllable.

## Key Discoveries

The repo evolved from an initial `install.sh` + `vibe-kanban.service` approach to the current `deploy.sh` + `vk-project.service` model in the "first attempt" commit. This refactor introduced GitHub Actions CI/CD and multi-instance support, suggesting the original single-instance manual-deploy approach was insufficient once dev/prod separation became necessary.

## Open Questions

- Whether the container image rebuild strategy (build only if missing) handles version upgrades correctly, or whether stale images could cause deployment issues.
- How rollbacks work — there's no apparent mechanism to revert to a previous version beyond changing the VERSION file and redeploying.
