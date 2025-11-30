#!/bin/bash
set -euo pipefail

echo "🚀 init.sh starting..."
export PATH="$PATH:/home/frappe/.local/bin"

# Helper: print and exit on missing env
require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    echo "❌ REQUIRED env $name is not set. Aborting."
    exit 1
  fi
}

# Prefer DATABASE_URL if provided; otherwise require DB_HOST/DB_PORT etc.
if [ -n "${DATABASE_URL:-}" ]; then
  echo "Using DATABASE_URL from env"
  # Extract host and port from DATABASE_URL
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
  # If DATABASE_URL exists but parsing failed, require explicit vars below
else
  require_env "DB_HOST"
  DB_PORT="${DB_PORT:-5432}"
fi

# Redis: prefer REDIS_CACHE (url) but still need host/port for readiness check
if [ -n "${REDIS_CACHE:-}" ]; then
  REDIS_URL="$REDIS_CACHE"
  # parse host and port for readiness
  read REDIS_HOST REDIS_PORT <<< "$(python3 - <<'PY'
import os,sys
from urllib.parse import urlparse
u=os.environ.get('REDIS_CACHE') or os.environ.get('REDIS_URL') or ''
if not u:
    sys.exit(0)
p=urlparse(u)
print(p.hostname or '', p.port or 6379)
PY
)"
else
  require_env "REDIS_HOST"
  REDIS_PORT="${REDIS_PORT:-6379}"
  REDIS_URL="redis://${REDIS_HOST}:${REDIS_PORT}"
fi

# Wait for Postgres (tcp connect check via python)
echo "⏳ Waiting for Postgres at ${DB_HOST}:${DB_PORT} ..."
python3 - <<PY
import socket, time, os, sys
host=os.environ.get('DB_HOST') or "$DB_HOST"
port=int(os.environ.get('DB_PORT') or "$DB_PORT")
timeout = 2
for i in range(120):
    try:
        s=socket.create_connection((host, port), timeout=timeout)
        s.close()
        print("🟢 Postgres is reachable")
        sys.exit(0)
    except Exception as e:
        print(".", end="", flush=True)
        time.sleep(1)
print("\n❌ Timeout waiting for Postgres at {}:{}. Aborting.".format(host, port))
sys.exit(1)
PY

# Wait for Redis
echo "⏳ Waiting for Redis at ${REDIS_HOST:-$REDIS_HOST}:${REDIS_PORT:-$REDIS_PORT} ..."
python3 - <<PY
import socket, time, os, sys
host=os.environ.get('REDIS_HOST') or "$REDIS_HOST"
port=int(os.environ.get('REDIS_PORT') or "$REDIS_PORT")
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

# Create bench if not exists
if [ ! -d "/workspace/frappe-bench" ]; then
    echo "🛠 Creating new bench..."
    cd /workspace

    # Initialize bench (skip redis config generation since we use external)
    bench init \
        --skip-redis-config-generation \
        --skip-assets \
        frappe-bench \
        --version version-15

    cd frappe-bench

    # Write common_site_config.json so bench/new-site uses Postgres connection
    echo "🔧 Creating common_site_config.json for Postgres connection"
    python3 - <<PY
import json, os
conf = {}
# prefer DATABASE_URL if present, otherwise set fields from env
db_url = os.environ.get('DATABASE_URL')
if db_url:
    conf['db_type'] = 'postgres'
    conf['db_host'] = os.environ.get('DB_HOST') or '${DB_HOST}'
    conf['db_port'] = int(os.environ.get('DB_PORT') or '${DB_PORT}')
    # If you plan to create DBs per-site, ensure DB_USER/DB_PASSWORD/DB_NAME exist
    conf['db_name'] = os.environ.get('DB_NAME') or '${DB_NAME:-}'
    conf['db_user'] = os.environ.get('DB_USER') or '${DB_USER:-}'
    conf['db_password'] = os.environ.get('DB_PASSWORD') or '${DB_PASSWORD:-}'
else:
    # fallback to explicit env vars
    conf['db_type'] = 'postgres'
    conf['db_host'] = os.environ.get('DB_HOST') or '${DB_HOST}'
    conf['db_port'] = int(os.environ.get('DB_PORT') or '${DB_PORT}')
    conf['db_name'] = os.environ.get('DB_NAME') or '${DB_NAME:-}'
    conf['db_user'] = os.environ.get('DB_USER') or '${DB_USER:-}'
    conf['db_password'] = os.environ.get('DB_PASSWORD') or '${DB_PASSWORD:-}'
open('sites/common_site_config.json','w').write(json.dumps(conf, indent=2))
print('Wrote sites/common_site_config.json')
PY

    echo "🔧 Configuring bench Redis envs to use external Redis"
    bench set-redis-cache-host "$REDIS_URL"
    bench set-redis-queue-host "$REDIS_URL"
    bench set-redis-socketio-host "$REDIS_URL"

    echo "🔧 Cleaning Procfile (remove redis/watch) (idempotent)"
    sed -i '/redis/d' ./Procfile || true
    sed -i '/watch/d' ./Procfile || true

    echo "📦 Installing CRM App (if not present)..."
    bench get-app crm --branch main || true

    echo "🌐 Creating site (Postgres)..."
    # create site non-interactively using common_site_config.json; pass admin password
    bench new-site crm.localhost \
        --admin-password "${ADMIN_PASSWORD:-admin}" \
        --db-type postgres || true

    echo "📥 Installing crm app..."
    bench --site crm.localhost install-app crm || true

    bench --site crm.localhost set-config developer_mode 1 || true
    bench --site crm.localhost set-config mute_emails 1 || true
    bench --site crm.localhost set-config server_script_enabled 1 || true
else
    echo "🟢 bench already exists. Skipping setup."
    cd /workspace/frappe-bench
fi

echo "🧹 Clearing cache..."
bench clear-cache || true

echo "🎯 Switching to crm.localhost"
bench use crm.localhost || true

echo "🚀 Starting bench (foreground)..."
# start bench in foreground so supervisord picks it up as the process output stream
exec bench start
