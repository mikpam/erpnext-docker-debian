#!/bin/sh
set -e

echo "-> Set ownership of sites folder"
chown frappe:frappe /home/frappe/bench/sites

echo "-> Linking assets"
# ln -sf alone won't replace an existing directory — it creates a symlink INSIDE it.
# bench migrate also recreates sites/assets/ as a real dir, so use rm + ln -sfn.
rm -rf /home/frappe/bench/sites/assets
su frappe -c "ln -sfn /home/frappe/bench/built_sites/assets /home/frappe/bench/sites/assets"
su frappe -c "ln -sf /home/frappe/bench/built_sites/apps.json /home/frappe/bench/sites/apps.json"
su frappe -c "ln -sf /home/frappe/bench/built_sites/apps.txt /home/frappe/bench/sites/apps.txt"

exec "$@"
