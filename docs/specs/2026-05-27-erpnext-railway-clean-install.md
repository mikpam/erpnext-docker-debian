# ERPNext on Railway — Clean Re-platform to Official ERPNext v16

- **Date:** 2026-05-27
- **Status:** Approved (updated — `ai_task_log` dropped per Michael; clean vanilla test bed)
- **Repo:** `mikpam/erpnext-docker-debian` — rewritten clean on branch `rebuild/v16-official-clean`
- **Prepared by:** Aiterated (infra)

## 1. Goal & context
Replace the **pipech-fork-based** ERPNext deployment (Railway project `erpnext-demo`) with a clean, **vanilla official ERPNext v16**, single-service on Railway. Fresh site, **no custom apps**.

> The `ai_task_log` POC proved that AI can be wired into ERPNext with just a Gemini connection key. That proof is done and the app is trivial to recreate/expand — so it is **deliberately left out** of the clean build and rebuilt later as an intentional feature (ideally on the production stack).

This eliminates the anti-patterns from the v15.108 upgrade (abandoned third-party base, unpinned versions, manual `git` surgery, obsolete IPv6 hotfix) and is the on-Railway rehearsal for the real production target (DigitalOcean VPS + `frappe_docker` compose — FRIDAY `infra/project/erpnext-production-digitalocean-planned`).

### Why single-service on Railway
Railway allows one volume per service; Frappe needs one shared `sites` volume across all its services. True multi-service is impossible on Railway, so all processes run in **one container via Supervisor** (community-standard Railway pattern).

## 2. Locked decisions
| Decision | Choice |
|---|---|
| App | **Vanilla official `frappe/erpnext` — NO custom apps** |
| Version | **ERPNext v16 + Frappe v16** |
| Base image | Official **prebuilt `frappe/erpnext:<v16-tag>`** + a thin Supervisor layer. No source build, no `apps.json`, no BuildKit secret (all unnecessary without custom apps). |
| Database | **MariaDB** (reuse Railway `mariadb` 10.6; v16 needs ≥10.6). NOT Postgres. |
| Runtime | **Single Railway service + Supervisor** (nginx + gunicorn + socketio + worker + scheduler) |
| Data | **Clean install — fresh site, no migration** |
| Repo | **Rewrite the existing repo** on a branch → PR → merge (keeps Railway's connection) |

## 3. Architecture
### 3.1 Build (`railway/Dockerfile`)
```
FROM frappe/erpnext:<v16-tag>
+ install supervisor, copy supervisord.conf + entrypoint
```
That's the whole image — no custom app, no `apps.json`. The only customization over the official image is the Supervisor layer (needed because Railway is single-container).

### 3.2 Runtime (single container, Supervisor-managed)
- **nginx** — `nginx-entrypoint.sh`, `BACKEND=127.0.0.1:8000`, `SOCKETIO=127.0.0.1:9000`.
- **gunicorn** — Frappe web/API on `127.0.0.1:8000` (exact command confirmed from the image in Phase 1).
- **socketio** — `node /home/frappe/frappe-bench/apps/frappe/socketio.js` on 9000.
- **worker** — `bench worker --queue long,default,short`.
- **scheduler** — `bench schedule`.

### 3.3 Boot flow (entrypoint)
1. Configurator (idempotent): set `db_host`, `db_port`, `redis_cache`, `redis_queue`, `socketio_port` from Railway env → Railway internal hostnames.
2. First boot only (site dir absent): `bench new-site <site> --db-root-password <env> --admin-password <env> --install-app erpnext --set-default`.
3. Later boots: `bench --site all migrate`.
4. Start `supervisord`.

### 3.4 Services (Railway project `erpnext-demo`)
- **erpnext** — new image; public domain; volume at **`/home/frappe/frappe-bench/sites`** (official path; started empty for the clean install).
- **mariadb** (reuse; fresh DB), **redis-cache**, **redis-queue** (reuse).
- Env: `SITE_NAME`, `ADMIN_PASSWORD`, `DB_ROOT_PASSWORD`, `DB_HOST`, `DB_PORT`, `REDIS_CACHE`, `REDIS_QUEUE`.

## 4. Build & deploy flow
Branch → replace `railway/Dockerfile`, add `supervisord.conf` + `entrypoint.sh`, remove pipech-era scripts → PR → merge → Railway auto-builds + deploys → first boot creates the fresh site.

## 5. Safety
Data is a throwaway POC; take a quick `bench backup` before merge as cheap insurance. Rollback = redeploy the previous Railway deployment (`fe71718d` v15.108).

## 6. Verification (post-deploy)
- `bench version` → frappe 16.x, erpnext 16.x.
- `GET /` → 200; `/api/method/ping` → `pong`; login renders; assets resolve (no 404).
- `migrate` clean; all supervisor processes `RUNNING`.
- DB/Redis over Railway IPv6 OK (v16 `getaddrinfo`/`AF_UNSPEC` — no hotfix).
- Note: deployment `SUCCESS` ≠ healthy — expect a transient 502 during first-boot `new-site`; verify via the URL.

## 7. Rollback
Code: redeploy the previous v15.108 deployment (still in Railway history). Clean install replaces the site/volume; old data is throwaway POC, so no data-restore concern.

## 8. Open items (Phase 1 spike)
- Exact v16 image tag + the image's gunicorn command + confirm `bench`/`socketio.js`/`nginx-entrypoint.sh` paths.
- Volume path change (pipech `/home/frappe/bench` → official `/home/frappe/frappe-bench`); start empty.

## Out of scope
- DigitalOcean production build (FRIDAY `infra/project/erpnext-production-digitalocean-planned`).
- `doctl` setup.
- The AI / Gemini integration — deliberate later follow-up (POC already proved the pattern).
