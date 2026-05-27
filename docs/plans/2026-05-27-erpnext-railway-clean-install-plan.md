# ERPNext v16 Clean Re-platform on Railway — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Replace the pipech-fork ERPNext deployment with a clean, **vanilla official ERPNext v16**, single-service on Railway — fresh site, **no custom apps**.

**Architecture:** `FROM frappe/erpnext:<v16-tag>` (official prebuilt, pinned) + a thin Supervisor layer running nginx + gunicorn + socketio + worker + scheduler in one container. Reuse Railway `mariadb`/`redis-cache`/`redis-queue`; fresh site on first boot. No source build, no `apps.json`, no custom app.

**Tech stack:** Docker, official `frappe/erpnext` image, Supervisor, nginx, Railway, MariaDB, Redis, Frappe/ERPNext v16.

---

## Phase 0 — Safety (cheap insurance; data is throwaway POC)
### Task 0.1: Quick backup of the current site
- [ ] **Step 1:** `railway ssh --service erpnext bash -lc 'cd /home/frappe/bench && su frappe -c "bench --site erpnext-production-e56b.up.railway.app backup --with-files"'` → expect "completed with files".
- [ ] **Step 2:** Note the rollback target in the PR: redeploy Railway deployment `fe71718d` (v15.108). (No off-volume download needed — data is throwaway.)

---

## Phase 1 — Spike: confirm the v16 image facts (no building yet)
### Task 1.1: Pin the tag + record the image's process commands
**Files:** Create `docs/specs/rebuild-spike-notes.md`
- [ ] **Step 1: Find the published v16 tag**
  `curl -sS "https://hub.docker.com/v2/repositories/frappe/erpnext/tags/?page_size=100" | jq -r '.results[].name' | grep -E "^v?16" | sort | head -20`
  Record the exact tag to pin (prefer a specific `v16.x.x`; else `version-16`).
- [ ] **Step 2: Record the default backend (gunicorn) command + confirm paths**
  `docker pull frappe/erpnext:<tag> && docker inspect frappe/erpnext:<tag> --format '{{json .Config.Cmd}}'`
  `docker run --rm frappe/erpnext:<tag> bash -lc 'which bench; ls /home/frappe/frappe-bench/apps/frappe/socketio.js; ls /usr/local/bin/nginx-entrypoint.sh; env/bin/gunicorn --version'`
  Record the gunicorn invocation verbatim (Phase 2 binds it to `127.0.0.1:8000`) and confirm `bench`/`socketio.js`/`nginx-entrypoint.sh` exist.
- [ ] **Step 3: Commit** `git add docs/specs/rebuild-spike-notes.md && git commit -m "docs: spike — v16 tag + image process commands"`

> **Gate:** if no v16 image tag is published, pause and report (fall back to building v16 from source via the layered Containerfile — a different plan).

---

## Phase 2 — Build the image
### Task 2.1: Dockerfile (official base + supervisor)
**Files:** Modify `railway/Dockerfile` (replace pipech build); Delete `railway/railway-setup.sh`, `railway/railway-cmd.sh`, `railway/temp_nginx.conf`, `railway/temp_supervisor.conf` (pipech-era, superseded).
- [ ] **Step 1: Write the Dockerfile** (substitute `<v16-tag>` from Task 1.1)
  ```dockerfile
  FROM frappe/erpnext:<v16-tag>

  USER root
  RUN apt-get update && apt-get install -y supervisor && rm -rf /var/lib/apt/lists/*
  COPY railway/supervisord.conf /etc/supervisor/conf.d/frappe.conf
  COPY --chmod=0755 railway/entrypoint.sh /usr/local/bin/railway-entrypoint.sh

  EXPOSE 8080
  ENTRYPOINT ["/usr/local/bin/railway-entrypoint.sh"]
  CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
  ```
- [ ] **Step 2: Commit** `git add railway/Dockerfile && git rm railway/railway-setup.sh railway/railway-cmd.sh railway/temp_nginx.conf railway/temp_supervisor.conf && git commit -m "feat: official frappe/erpnext v16 base + supervisor (drop pipech build)"`

### Task 2.2: Supervisor config
**Files:** Create `railway/supervisord.conf`
- [ ] **Step 1: Write it** (substitute the exact gunicorn command from Task 1.1; keep `--bind=127.0.0.1:8000`)
  ```ini
  [program:nginx]
  command=/usr/local/bin/nginx-entrypoint.sh
  environment=BACKEND="127.0.0.1:8000",SOCKETIO="127.0.0.1:9000",FRAPPE_SITE_NAME_HEADER="$host",UPSTREAM_REAL_IP_ADDRESS="127.0.0.1"
  user=frappe
  autorestart=true
  stdout_logfile=/dev/stdout
  stdout_logfile_maxbytes=0

  [program:gunicorn]
  command=/home/frappe/frappe-bench/env/bin/gunicorn --chdir=/home/frappe/frappe-bench/sites --bind=127.0.0.1:8000 --threads=4 --workers=2 --worker-class=gthread --worker-tmp-dir=/dev/shm --timeout=120 frappe.app:application
  user=frappe
  directory=/home/frappe/frappe-bench
  autorestart=true
  stdout_logfile=/dev/stdout
  stdout_logfile_maxbytes=0

  [program:socketio]
  command=node /home/frappe/frappe-bench/apps/frappe/socketio.js
  user=frappe
  directory=/home/frappe/frappe-bench
  autorestart=true
  stdout_logfile=/dev/stdout
  stdout_logfile_maxbytes=0

  [program:worker]
  command=bench worker --queue long,default,short
  user=frappe
  directory=/home/frappe/frappe-bench
  autorestart=true
  stdout_logfile=/dev/stdout
  stdout_logfile_maxbytes=0

  [program:scheduler]
  command=bench schedule
  user=frappe
  directory=/home/frappe/frappe-bench
  autorestart=true
  stdout_logfile=/dev/stdout
  stdout_logfile_maxbytes=0
  ```
- [ ] **Step 2: Commit** `git add railway/supervisord.conf && git commit -m "feat: supervisor config (nginx/gunicorn/socketio/worker/scheduler)"`

### Task 2.3: Entrypoint (configurator + first-boot site + migrate)
**Files:** Create `railway/entrypoint.sh`
- [ ] **Step 1: Write it**
  ```bash
  #!/bin/bash
  set -e
  cd /home/frappe/frappe-bench
  # configurator (idempotent)
  su frappe -c "bench set-config -g db_host '$DB_HOST'"
  su frappe -c "bench set-config -gp db_port '$DB_PORT'"
  su frappe -c "bench set-config -g redis_cache 'redis://$REDIS_CACHE'"
  su frappe -c "bench set-config -g redis_queue 'redis://$REDIS_QUEUE'"
  su frappe -c "bench set-config -g redis_socketio 'redis://$REDIS_QUEUE'"
  su frappe -c "bench set-config -gp socketio_port 9000"
  # first boot only: create the fresh site
  if [ ! -d "sites/$SITE_NAME" ]; then
    su frappe -c "bench new-site '$SITE_NAME' --no-mariadb-socket --mariadb-user-host-login-scope=% --db-root-password '$DB_ROOT_PASSWORD' --admin-password '$ADMIN_PASSWORD' --install-app erpnext --set-default"
    su frappe -c "bench --site '$SITE_NAME' enable-scheduler"
  else
    su frappe -c "bench --site all migrate" || echo "migrate skipped"
  fi
  exec "$@"
  ```
- [ ] **Step 2: Commit** `git add railway/entrypoint.sh && git commit -m "feat: entrypoint — configurator + first-boot new-site + migrate"`

### Task 2.4: Local build smoke test (if Docker available)
- [ ] **Step 1:** `docker build -t erpnext-railway:test -f railway/Dockerfile .` → expect success. (If no local Docker, the Railway build in Phase 3 validates it — note which.)

---

## Phase 3 — Deploy + clean site
### Task 3.1: Railway env + volume path
- [ ] **Step 1:** Set service env (never echo values): `SITE_NAME`, `ADMIN_PASSWORD`, `DB_ROOT_PASSWORD`, `DB_HOST` (mariadb internal host), `DB_PORT=3306`, `REDIS_CACHE` (redis-cache host:6379), `REDIS_QUEUE` (redis-queue host:6379).
- [ ] **Step 2:** Change the erpnext volume mount to **`/home/frappe/frappe-bench/sites`** (was pipech `/home/frappe/bench/sites`); start empty for the clean site.

### Task 3.2: Merge → deploy → clean site
- [ ] **Step 1:** Open PR `rebuild/v16-official-clean` → `master`; confirm gitleaks clean.
- [ ] **Step 2: Pre-merge gate** — Phase 0 backup done; get Michael's go.
- [ ] **Step 3:** Merge → Railway auto-builds. Monitor: `railway logs --service erpnext --build --lines 200 <deployment-id>`.
- [ ] **Step 4:** Watch first boot (entrypoint runs `new-site`, then supervisor). Expect a transient 502 until nginx is up.

---

## Phase 4 — Verify (spec §6)
- [ ] **Step 1:** `railway ssh --service erpnext bash -lc 'cd /home/frappe/frappe-bench && su frappe -c "bench version"'` → frappe 16.x, erpnext 16.x.
- [ ] **Step 2:** `/api/method/ping` → `pong`; `GET /` → 200; login renders.
- [ ] **Step 3:** Asset bundle from the page `Link` header → 200 (no 404).
- [ ] **Step 4:** Deploy logs: all supervisor programs `RUNNING`; `migrate`/site-create clean; scheduler enabled.

---

## Phase 5 — Cutover, docs, FRIDAY
- [ ] **Step 1:** Update repo `CLAUDE.md` + README: official `frappe/erpnext` v16, single-service supervisor, no pipech, no custom apps.
- [ ] **Step 2:** Update the upgrade runbook §8 to the new v16/official setup.
- [ ] **Step 3:** Update FRIDAY `infra/reference/erpnext-demo-railway-metrix-digital-projects`: ERPNext v16, official base, clean-install date, new architecture, ai_task_log removed (recreate later).
- [ ] **Step 4:** Confirm FRIDAY `infra/project/erpnext-production-digitalocean-planned` still reflects the next step.

---

## Self-review notes
- **Spec coverage:** §2 → Phases 2–3; §3 architecture → Tasks 2.1–2.3; §5 safety → Phase 0; §6 verify → Phase 4; §7 rollback → Task 0.1 Step 2 + Task 3.2 Step 2; §8 spike → Phase 1 + Task 3.1 Step 2 (volume path).
- **No custom app** anywhere (ai_task_log removed per Michael; recreate the AI/Gemini integration later as a deliberate feature).
- **MariaDB:** keep 10.6 (v16 needs ≥10.6); bump only if Phase 4 surfaces an issue.
- **Spike-derived values** (v16 tag, gunicorn cmd) are produced in Phase 1 and substituted in Phase 2.
