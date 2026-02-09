#!/bin/sh
set -e

echo "-> Running migrations"
su frappe -c "bench --site all migrate" || echo "-> Migration skipped (site may not exist yet)"

echo "-> Re-linking assets (bench migrate recreates sites/assets/ as a real directory)"
rm -rf /home/frappe/bench/sites/assets
ln -sfn /home/frappe/bench/built_sites/assets /home/frappe/bench/sites/assets

echo "-> Clearing cache"
su frappe -c "bench execute frappe.cache_manager.clear_global_cache"

echo "-> Bursting env into config"
envsubst '$RFP_DOMAIN_NAME' < /home/$systemUser/temp_nginx.conf > /etc/nginx/conf.d/default.conf
envsubst '$PATH,$HOME,$NVM_DIR,$NODE_VERSION' < /home/$systemUser/temp_supervisor.conf > /home/$systemUser/supervisor.conf

echo "-> Starting nginx"
nginx

echo "-> Starting supervisor"
/usr/bin/supervisord -c /home/$systemUser/supervisor.conf
