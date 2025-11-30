#!/bin/bash
set -euo pipefail

# One-time init script for Render. DOES NOT start bench.
# It will skip work if /workspace/.initialized exists.

echo "🚀 init.sh starting..."
export PATH="$PATH:/home/frappe/.local/bin"

INITIALIZED_FLAG="/workspace/.initialized"

if [ -f "$INITIALIZED_FLAG" ]; then
  echo "🔁 init.sh already ran. Exiting."
  exit 0
fi

# Helper: print and exit on missing env
require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "❌ REQUIRED env $name is not set. Aborting."
    exit 1
  fi
}

# Ensure we have at least DB_HOST (or DATABASE_URL) and Redis info
if [ -z "${DATABASE_URL:-}" ]; then
  require_env "DB_HOST"
  DB_PORT="${DB_PORT:-5432}"
else
  echo "Using DATABASE_URL from env"
  # populate DB_HOST DB_PORT for logs/consumers
  read DB_HOST DB_PORT <<< "$(python3 - <<'PY'
from urllib.parse import urlparse
import os,sys
u=os.environ.get('DATABASE_URL')
if not u:
    sys.exit(1)
p=urlparse(u)
print(p.hostname or '', p.port or 5432)
PY
)"
fi

if [ -z "${REDIS_CACHE:-}" ]; then
  require_env "REDIS_HOST"
  REDIS_PORT="${REDIS_PORT:-6379}"
  REDIS_URL="redis://${REDIS_HOST}:${REDIS_PORT}"
else
  REDIS_URL="${REDIS_CACHE}"
fi

echo "DB host: ${DB_HOST:-<from DATABASE_URL>}"
echo "Redis URL: ${REDIS_URL}"

# Wait for Postgres (simple tcp check)
echo "⏳ Waiting for Postgres..."
python3 - <<PY
import socket, time, os, sys
host=os.environ.get('DB_HOST') or ''
port=int(os.environ.get('DB_PORT') or 5432)
# If DATABASE_URL is used and DB_HOST is empty, skip explicit wait (DB is likely internal)
if not host:
    print("No DB_HOST provided in env — assuming DATABASE_URL internal connectivity works.")
    sys.exit(0)
for i in range(120):
    try:
        s=socket.create_connection((host, port), timeout=2)
        s.close()
        print("🟢 Postgres is reachable")
        sys.exit(0)
    except Exception:
        print(".", end="", flush=True)
        time.sleep(1)
print("\n❌ Timeout waiting for Postgres at {}:{}. Aborting.".format(host, port))
sys.exit(1)
PY

# Wait for Redis (tcp)
echo "⏳ Waiting for Redis..."
python3 - <<PY
import socket, time, os, sys
# parse REDIS_CACHE/REDIS_HOST from env
from urllib.parse import urlparse
u=os.environ.get('REDIS_CACHE') or os.environ.get('REDIS_URL') or ''
if u:
    p=urlparse(u)
    host = p.hostname or ''
    port = int(p.port or 6379)
else:
    host = os.environ.get('REDIS_HOST') or ''
    port = int(os.environ.get('REDIS_PORT') or 6379)
if not host:
    print("No REDIS host provided; skipping redis wait")
    sys.exit(0)
for i in range(60):
    try:
        s=socket.create_connection((host, port), timeout=2)
        s.close()
        print("🟢 Redis is reachable")
        sys.exit(0)
    except Exception:
        print(".", end="", flush=True)
        time.sleep(1)
print("\n❌ Timeout waiting for Redis at {}:{}. Aborting.".format(host, port))
sys.exit(1)
PY

# Create bench/site if missing
if [ ! -d "/workspace/frappe-bench" ]; then
    echo "🛠 Creating new bench..."
    cd /workspace

    bench init \
        --skip-redis-config-generation \
        --skip-assets \
        frappe-bench \
        --version version-15

    cd frappe-bench

    echo "🔧 Writing sites/common_site_config.json (Postgres config)"
    python3 - <<PY
import json, os
conf = {}
conf['db_type'] = 'postgres'
# allow DATABASE_URL or explicit parts; bench may pick up DATABASE_URL directly
conf['db_host'] = os.environ.get('DB_HOST') or ''
conf['db_port'] = int(os.environ.get('DB_PORT') or 5432)
conf['db_name'] = os.environ.get('DB_NAME') or ''
conf['db_user'] = os.environ.get('DB_USER') or ''
conf['db_password'] = os.environ.get('DB_PASSWORD') or ''
open('sites/common_site_config.json','w').write(json.dumps(conf, indent=2))
print('Wrote sites/common_site_config.json')
PY

    echo "🔧 Configuring bench to use external Redis"
    bench set-redis-cache-host "$REDIS_URL" || true
    bench set-redis-queue-host "$REDIS_URL" || true
    bench set-redis-socketio-host "$REDIS_URL" || true

    echo "🔧 Cleaning Procfile (remove redis/watch) (idempotent)"
    sed -i '/redis/d' ./Procfile || true
    sed -i '/watch/d' ./Procfile || true

    echo "📦 Getting CRM App (if not present)"
    bench get-app crm --branch main || true

    echo "🌐 Creating site (Postgres) -- this may take a little while"
    bench new-site crm.localhost \
        --admin-password "${ADMIN_PASSWORD:-admin}" \
        --db-type postgres || true

    echo "📥 Installing crm app..."
    bench --site crm.localhost install-app crm || true

    bench --site crm.localhost set-config developer_mode 1 || true
    bench --site crm.localhost set-config mute_emails 1 || true
    bench --site crm.localhost set-config server_script_enabled 1 || true

else
    echo "🟢 /workspace/frappe-bench already exists. Skipping bench init."
    cd /workspace/frappe-bench
fi

echo "🧹 Clearing cache..."
bench clear-cache || true

echo "🎯 Switching to crm.localhost (if exists)"
bench use crm.localhost || true

# Mark initialization done
touch "$INITIALIZED_FLAG"
echo "✨ init.sh completed. .initialized created at $INITIALIZED_FLAG"
exit 0
