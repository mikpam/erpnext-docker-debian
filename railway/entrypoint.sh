#!/bin/bash
set -eo pipefail
cd /home/frappe/frappe-bench

# Reuse the existing Railway service vars (names confirmed from the dashboard):
#   FRAPPE_DB_HOST, FRAPPE_DB_PASSWORD (MariaDB root), FRAPPE_REDIS_CACHE,
#   FRAPPE_REDIS_QUEUE, RFP_SITE_ADMIN_PASSWORD.
# NOTE: values are passed single-quoted to bench; passwords must not contain a single quote (').
SITE_NAME="${SITE_NAME:-erpnext-production-e56b.up.railway.app}"

# DB host/port — FRAPPE_DB_HOST may be "host" or "host:port"
DB_HOST="${FRAPPE_DB_HOST%%:*}"
case "$FRAPPE_DB_HOST" in
  *:*) DB_PORT="${FRAPPE_DB_HOST##*:}" ;;
  *)   DB_PORT="3306" ;;
esac

# Redis — accept either "host:port" or "redis://host:port"
case "$FRAPPE_REDIS_CACHE" in redis://*) RC="$FRAPPE_REDIS_CACHE" ;; *) RC="redis://$FRAPPE_REDIS_CACHE" ;; esac
case "$FRAPPE_REDIS_QUEUE" in redis://*) RQ="$FRAPPE_REDIS_QUEUE" ;; *) RQ="redis://$FRAPPE_REDIS_QUEUE" ;; esac

# Configurator (idempotent)
su frappe -c "bench set-config -g db_host '$DB_HOST'"
su frappe -c "bench set-config -gp db_port '$DB_PORT'"
su frappe -c "bench set-config -g redis_cache '$RC'"
su frappe -c "bench set-config -g redis_queue '$RQ'"
su frappe -c "bench set-config -g redis_socketio '$RQ'"
su frappe -c "bench set-config -gp socketio_port 9000"

# First boot only: create the fresh site
if [ ! -d "sites/$SITE_NAME" ]; then
  echo "-> Creating new site $SITE_NAME"
  su frappe -c "bench new-site '$SITE_NAME' --no-mariadb-socket --mariadb-user-host-login-scope=% --db-root-password '$FRAPPE_DB_PASSWORD' --admin-password '$RFP_SITE_ADMIN_PASSWORD' --install-app erpnext --set-default"
  su frappe -c "bench --site '$SITE_NAME' enable-scheduler"
else
  echo "-> Existing site found; running migrate"
  su frappe -c "bench --site all migrate"
fi

exec "$@"
