#!/bin/bash
set -e

echo "🚀 init.sh running..."

if [ ! -d "/workspace/frappe-bench" ]; then
    echo "🛠 Creating new bench..."

    bench init --skip-redis-config-generation --skip-assets frappe-bench --version version-15

    cd frappe-bench

    bench get-app crm --branch main
    bench new-site crm.localhost --admin-password admin --db-type postgres
    bench --site crm.localhost install-app crm
else
    echo "🟢 Bench already exists. Skipping init."
fi
