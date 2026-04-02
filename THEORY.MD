# Theory: Vibe-Kanban Container Deployment

## Problem

Vibe-Kanban is a Kanban board application distributed as an npm package. It needs a reliable, repeatable deployment mechanism that supports three concurrent instances (project, dev, prod) on the same host, each at potentially different versions, with secure remote access and CI/CD automation. The repo must be the sole source of truth for all deployment artifacts — nothing should be assumed to exist on the host already.

## Operating Theory

This repo contains no application code. The app is the `vibe-kanban` npm package, pulled at container startup via `npx --yes vibe-kanban@${VK_VERSION}`. This repo is strictly deployment plumbing: a Containerfile, a deploy script, a systemd unit template, and a CI workflow.

Each instance has a **runtime directory** that contains everything needed to run that instance at that version:

- **project** → `/home/deploy/projects/vk-container/` (this repo checkout, run manually)
- **dev** → `/srv/vibe-kanban/dev/` (populated by CI from the `dev` branch)
- **prod** → `/srv/vibe-kanban/prod/` (populated by CI from the `main` branch)

CI copies `Containerfile`, `deploy.sh`, and `VERSION` into the runtime directory, then runs `deploy.sh` from there. This ensures each instance is self-contained and version-isolated — dev can be running different deployment logic than prod.

All three instances have completely separate Podman named volumes (`vk-<instance>-share`, `vk-<instance>-home`, `vk-<instance>-config`). No data is shared between instances.

## Strategy

Minimal tooling, maximum clarity. One shell script handles everything: volume creation, image build, env generation, systemd unit installation, service restart. No orchestration frameworks — just Podman, systemd, and SSH. The CI workflow's only job is to get the right files to the right place and run the script.

The version is tracked in a `VERSION` file. Bumping the version and pushing triggers a full redeploy: CI copies the new VERSION to the runtime directory, deploy.sh generates a new .env with that version, and the systemd restart pulls the new npm package version at container startup.

## Key Discoveries

The original workflow assumed `deploy.sh` already existed on the host at `/srv/vibe-kanban/deploy.sh` — it checked out the repo on the GitHub Actions runner but never copied anything to the target host. This meant changes to deploy.sh, Containerfile, or VERSION in git had no effect on deployments. The fix was adding an SCP step to copy deployment files into the instance's runtime directory before running deploy.sh, making the repo the actual source of truth rather than whatever was manually placed on the host at some earlier point.

## Open Questions

- How rollbacks work — there's no apparent mechanism to revert to a previous version beyond changing the VERSION file and redeploying.
