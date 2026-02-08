# CLAUDE.md - ERPNext Docker (Railway Fork)

## What This Repo Is
Fork of pipech/erpnext-docker-debian with custom app installation baked into the Docker image.
Railway auto-deploys from this repo.

## Custom Apps
Custom Frappe apps live in a separate monorepo: https://github.com/mikpam/erpnext-custom-apps
The Dockerfile clones that repo at build time and installs each app via `bench get-app`.

## Adding a New Custom App
1. Add the app to mikpam/erpnext-custom-apps (as a subdirectory)
2. Edit `railway/Dockerfile` — add a `bench get-app /tmp/custom-apps/your_app` line
3. Edit `railway/railway-setup.sh` — add `bench install-app your_app`
4. Add any pip dependencies to the Dockerfile
5. Push to this repo — Railway auto-deploys

## Pulling Upstream Updates
```bash
git remote add upstream https://github.com/pipech/erpnext-docker-debian.git
git fetch upstream
git merge upstream/master
```

## Key Files
- `railway/Dockerfile` — two-stage build, custom apps installed in stage 1
- `railway/railway-setup.sh` — initial site creation (runs once)
- `railway/railway-cmd.sh` — boot script (runs every deploy: migrate + start services)
- `railway/railway-entrypoint.sh` — ownership + asset linking

## Railway Project
- Project: erpnext-demo (ID: 4cb0a514-c7ed-4bf6-ae9f-143c198f4774)
- URL: erpnext-production-e56b.up.railway.app
- ERPNext v15 on Python 3.11.6
