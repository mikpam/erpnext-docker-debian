#!/bin/bash
set -eo pipefail
cd /home/frappe/frappe-bench

# NOTE: Railway-set values are passed single-quoted to bench; passwords must not contain a single quote (').
# Configurator: point the bench at Railway's MariaDB + Redis (idempotent)
su frappe -c "bench set-config -g db_host '$DB_HOST'"
su frappe -c "bench set-config -gp db_port '${DB_PORT:-3306}'"
su frappe -c "bench set-config -g redis_cache 'redis://$REDIS_CACHE'"
su frappe -c "bench set-config -g redis_queue 'redis://$REDIS_QUEUE'"
su frappe -c "bench set-config -g redis_socketio 'redis://$REDIS_QUEUE'"
su frappe -c "bench set-config -gp socketio_port 9000"

# First boot only: create the fresh site
if [ ! -d "sites/$SITE_NAME" ]; then
  echo "-> Creating new site $SITE_NAME"
  su frappe -c "bench new-site '$SITE_NAME' --no-mariadb-socket --mariadb-user-host-login-scope=% --db-root-password '$DB_ROOT_PASSWORD' --admin-password '$ADMIN_PASSWORD' --install-app erpnext --set-default"
  su frappe -c "bench --site '$SITE_NAME' enable-scheduler"
else
  echo "-> Existing site found; running migrate"
  su frappe -c "bench --site all migrate"
fi

exec "$@"
