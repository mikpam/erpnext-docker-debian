#!/bin/sh
set -e

echo "-> Running migrations"
su frappe -c "bench --site all migrate" || echo "-> Migration skipped (site may not exist yet)"

echo "-> Re-linking assets (bench migrate recreates sites/assets/ as a real directory)"
rm -rf /home/frappe/bench/sites/assets
ln -sfn /home/frappe/bench/built_sites/assets /home/frappe/bench/sites/assets

echo "-> Copying assets.json to all site directories (Frappe reads from sites/{site}/assets/)"
for site_dir in /home/frappe/bench/sites/*/; do
    [ -d "$site_dir" ] || continue
    # Skip non-site directories (assets, built_sites symlinks, etc.)
    site_name=$(basename "$site_dir")
    [ -f "$site_dir/site_config.json" ] || continue
    mkdir -p "$site_dir/assets"
    cp -f /home/frappe/bench/built_sites/assets/assets.json "$site_dir/assets/assets.json"
    echo "   Updated $site_name/assets/assets.json"
done

echo "-> Clearing cache (full flush to purge stale assets_json from Redis)"
su frappe -c "bench --site all clear-cache"

echo "-> Bursting env into config"
envsubst '$RFP_DOMAIN_NAME' < /home/$systemUser/temp_nginx.conf > /etc/nginx/conf.d/default.conf
envsubst '$PATH,$HOME,$NVM_DIR,$NODE_VERSION' < /home/$systemUser/temp_supervisor.conf > /home/$systemUser/supervisor.conf

echo "-> Starting nginx"
nginx

echo "-> Starting supervisor"
/usr/bin/supervisord -c /home/$systemUser/supervisor.conf
