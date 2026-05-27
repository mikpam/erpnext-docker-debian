# ERPNext on Railway — Clean Re-platform to Official frappe_docker (v16)

- **Date:** 2026-05-27
- **Status:** Design approved → spec (pending user spec review)
- **Repo:** `mikpam/erpnext-docker-debian` — rewritten clean on branch `rebuild/v16-official-clean`
- **Prepared by:** Aiterated (infra)

## 1. Goal & context

Replace the current **pipech-fork-based** ERPNext deployment (Railway project `erpnext-demo`) with a clean, reproducible, **single-service ERPNext v16** built from the **official `frappe_docker`** layered image. Fresh site; custom app `ai_task_log` retained.

This eliminates the anti-patterns found during the v15.108 upgrade — abandoned third-party base image (`pipech:version-15-latest`, frozen at ~15.91), unpinned versions, manual `git` surgery in the Dockerfile, and a now-obsolete IPv6 `sed` hotfix. It also serves as the **on-Railway rehearsal** for the real production target (DigitalOcean VPS + `frappe_docker` compose — tracked separately in FRIDAY `infra/project/erpnext-production-digitalocean-planned`).

### Why single-service on Railway
Railway allows **one volume per service**; Frappe requires **one shared `sites` volume across all its services**. True multi-service is therefore impossible on Railway, so all Frappe processes run in **one container via Supervisor** (the community-standard Railway pattern), mounting one `sites` volume.

## 2. Locked decisions

| Decision | Choice |
|---|---|
| App source | **Official `frappe/erpnext`** (the `mikpam/erpnext-fork` is an unmodified mirror — no reason to use it) |
| Version | **ERPNext v16 + Frappe v16** |
| Database | **MariaDB** (reuse the existing Railway `mariadb` service; bump image toward 11.x if v16 requires — confirm during build). NOT Postgres/Neon. |
| Runtime | **Single Railway service + Supervisor** (nginx + gunicorn + socketio + workers + scheduler) |
| Custom app | **`ai_task_log`** baked in via `apps.json` (confirm/port v16 compatibility) |
| Data | **Clean install — fresh site, no migration** (old 8 `ai_task_log` records sacrificed; safety backup taken first) |
| Build method | **Layered `Containerfile` + `apps.json`** (NOT the prebuilt `frappe/erpnext:v16` image — it cannot include the custom app) |
| Supervisor | **Roll our own `supervisord.conf`** on the official image (auditable; Railway's ERPNext template used only as a sanity reference) |
| Repo strategy | **Rewrite the existing repo** on a branch → PR → merge (keeps Railway's GitHub connection intact; no service reconfig) |

## 3. Architecture

### 3.1 Build (`railway/Dockerfile` → official layered build)
- Build **via `frappe_docker`'s `images/layered/Containerfile`** with build args `FRAPPE_PATH=https://github.com/frappe/frappe`, `FRAPPE_BRANCH=version-16`.
- `apps.json` (BuildKit secret), pinned:
  ```json
  [
    { "url": "https://github.com/frappe/erpnext", "branch": "version-16" },
    { "url": "https://github.com/mikpam/erpnext-custom-apps", "branch": "<v16-branch>" }
  ]
  ```
- Then a thin layer on top: install `supervisor`, copy our `supervisord.conf`, nginx config handling, and the boot/entrypoint scripts.
- Result: a single image containing frappe v16 + erpnext v16 + `ai_task_log`, with assets built (`bench build`), runnable as one supervised container.

> **`ai_task_log` packaging:** it currently lives as a subdirectory in the `erpnext-custom-apps` monorepo. The layered build's `apps.json` expects one app per repo URL. **Implementation must confirm** how to install a monorepo-subdir app (e.g., split `ai_task_log` into its own repo/branch, or install it in the extra layer via `bench get-app` from the cloned monorepo). Tracked in §8.

### 3.2 Runtime (single container, Supervisor-managed)
Supervised processes (all on localhost):
- **nginx** — serves `sites/assets` + reverse-proxies; configured via the official `nginx-entrypoint.sh` templating with `BACKEND=127.0.0.1:8000`, `SOCKETIO=127.0.0.1:9000`.
- **gunicorn** — Frappe web/API on `127.0.0.1:8000`.
- **socketio** (node) — `127.0.0.1:9000`.
- **bench worker** — queues `short,default,long` (1+ worker processes).
- **bench schedule** — scheduler.

### 3.3 Boot flow (entrypoint)
1. **Configurator (idempotent):** write `common_site_config.json` with `db_host`, `db_port`, `redis_cache`, `redis_queue`, `socketio_port` — pointing at the Railway **internal** service hostnames.
2. **First boot only** (guard: site dir absent on the volume): `bench new-site <site> --db-root-password <env> --admin-password <env> --install-app erpnext` → `bench install-app ai_task_log` → `bench enable-scheduler`.
3. **Subsequent boots:** `bench --site all migrate` (assets are baked in the image; rebuild only if needed).
4. Start `supervisord`.

### 3.4 Services (Railway project `erpnext-demo`)
- **erpnext** — new supervised image (this repo); public domain; one volume mounted at **`/home/frappe/frappe-bench/sites`** *(note: official path differs from pipech's `/home/frappe/bench/sites` — the volume is started empty for the clean install)*.
- **mariadb** (reuse; fresh DB for the new site), **redis-cache**, **redis-queue** (reuse).
- **Env vars:** site name, admin password, db root password; `DB_HOST`, `REDIS_CACHE`, `REDIS_QUEUE` → Railway internal hostnames. (Reuse `RFP_*` names or rename — §8.)

## 4. Build & deploy flow
1. Branch `rebuild/v16-official-clean` off `master`.
2. Replace `railway/Dockerfile` with the official-layered build; add `apps.json`, `supervisord.conf`, nginx config, entrypoint/boot scripts; remove the pipech-era scripts.
3. PR → review → merge to `master` → Railway auto-builds + deploys.
4. First boot performs the clean `new-site`.

## 5. Data & safety
- **Clean install = fresh site.** The existing v15.108 site (8 `ai_task_log` records) is NOT carried over.
- **Before merging the rebuild:** take a final `bench backup --with-files` of the current v15.108 site and **copy it off the volume** (the volume is emptied for the new site). This is the only recovery path back to the old state.
- New site uses a fresh DB; the old DB may be dropped or left in MariaDB.

## 6. Verification (post-deploy)
- `bench version` → frappe 16.x, erpnext 16.x, `ai_task_log` present.
- `GET /` → 200, login renders; `/api/method/ping` → `pong`.
- Assets resolve (no 404).
- `migrate` clean; all supervisor processes `RUNNING`.
- `ai_task_log` module loads; create a test record.
- DB/Redis connectivity over Railway IPv6 OK (v16 uses `getaddrinfo`/`AF_UNSPEC` — no hotfix needed).
- Deployment `SUCCESS` ≠ healthy: expect a transient 502 during first-boot `new-site`/build; verify by hitting the URL.

## 7. Rollback
- **Code:** redeploy the previous v15.108 Railway deployment (still in Railway's deployment history).
- **Data:** clean install replaces the site/volume, so a true rollback also requires restoring the §5 pre-rebuild backup. **Decide the go/no-go before merge** — once the fresh site is created, the old site is gone unless restored.

## 8. Open items (resolve in the implementation plan)
- `ai_task_log` v16 compatibility (may need a code port) **and** how the layered build installs a monorepo-subdir app.
- Exact `supervisord.conf` process list + the official image's gunicorn/socketio invocation.
- Volume path change (pipech `/home/frappe/bench` → official `/home/frappe/frappe-bench`); confirm the Railway volume remounts cleanly (empty).
- MariaDB version (keep 10.6 vs bump to 11.x for v16).
- Env-var naming (reuse `RFP_*` vs rename).

## Out of scope
- DigitalOcean production build (FRIDAY `infra/project/erpnext-production-digitalocean-planned`).
- `doctl` setup / DO access wiring.
