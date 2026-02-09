#!/bin/sh
set -e

echo "-> Running migrations"
su frappe -c "bench --site all migrate" || echo "-> Migration skipped (site may not exist yet)"

echo "-> Rebuilding assets (ensures hashes match with Redis available)"
su frappe -c "bench build"

echo "-> Clearing cache"
su frappe -c "bench --site all clear-cache"

echo "-> Bursting env into config"
envsubst '$RFP_DOMAIN_NAME' < /home/$systemUser/temp_nginx.conf > /etc/nginx/conf.d/default.conf
envsubst '$PATH,$HOME,$NVM_DIR,$NODE_VERSION' < /home/$systemUser/temp_supervisor.conf > /home/$systemUser/supervisor.conf

echo "-> Starting nginx"
nginx

echo "-> Starting supervisor"
/usr/bin/supervisord -c /home/$systemUser/supervisor.conf
