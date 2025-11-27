#!/bin/bash
set -e

echo "🚀 init.sh starting..."

export PATH="$PATH:/home/frappe/.local/bin"

# Wait for MariaDB
echo "⏳ Waiting for MariaDB to start..."
until mysqladmin ping --host=127.0.0.1 --silent; do
    sleep 2
done
echo "🟢 MariaDB is up!"

# Wait for Redis
echo "⏳ Waiting for Redis..."
until redis-cli ping >/dev/null 2>&1; do
    sleep 1
done
echo "🟢 Redis is up!"

# Create bench if not exists
if [ ! -d "/workspace/frappe-bench" ]; then
    echo "🛠 Creating new bench..."

    cd /workspace

    bench init \
        --skip-redis-config-generation \
        --skip-assets \
        frappe-bench \
        --version version-15

    cd frappe-bench

    echo "🔧 Configuring bench hosts..."
    bench set-mariadb-host 127.0.0.1
    bench set-redis-cache-host redis://127.0.0.1:6379
    bench set-redis-queue-host redis://127.0.0.1:6379
    bench set-redis-socketio-host redis://127.0.0.1:6379

    echo "🔧 Cleaning Procfile (remove redis/watch)"
    sed -i '/redis/d' ./Procfile
    sed -i '/watch/d' ./Procfile

    echo "📦 Installing CRM App..."
    bench get-app crm --branch main

    echo "🌐 Creating site..."
    bench new-site crm.localhost \
        --force \
        --admin-password admin \
        --mariadb-root-password \
        --no-mariadb-socket

    bench --site crm.localhost install-app crm
    bench --site crm.localhost set-config developer_mode 1
    bench --site crm.localhost set-config mute_emails 1
    bench --site crm.localhost set-config server_script_enabled 1
else
    echo "🟢 bench already exists. Skipping setup."
    cd /workspace/frappe-bench
fi

echo "🧹 Clearing cache..."
bench clear-cache

echo "🎯 Switching to crm.localhost"
bench use crm.localhost

echo "🚀 Starting bench (foreground)..."
bench start



# #!bin/bash

# if [ -d "/home/frappe/frappe-bench/apps/frappe" ]; then
#     echo "Bench already exists, skipping init"
#     cd frappe-bench
#     bench start
# else
#     echo "Creating new bench..."
# fi

# bench init --skip-redis-config-generation frappe-bench --version version-15

# cd frappe-bench

# # Use containers instead of localhost
# bench set-mariadb-host mariadb
# bench set-redis-cache-host redis://redis:6379
# bench set-redis-queue-host redis://redis:6379
# bench set-redis-socketio-host redis://redis:6379

# # Remove redis, watch from Procfile
# sed -i '/redis/d' ./Procfile
# sed -i '/watch/d' ./Procfile

# bench get-app crm --branch main

# bench new-site crm.localhost \
#     --force \
#     --mariadb-root-password 123 \
#     --admin-password admin \
#     --no-mariadb-socket

# bench --site crm.localhost install-app crm
# bench --site crm.localhost set-config developer_mode 1
# bench --site crm.localhost set-config mute_emails 1
# bench --site crm.localhost set-config server_script_enabled 1
# bench --site crm.localhost clear-cache
# bench use crm.localhost

# bench start
