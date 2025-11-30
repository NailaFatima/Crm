#!/bin/bash
set -euo pipefail

echo "🚀 start.sh: starting bench (foreground)..."
export PATH="$PATH:/home/frappe/.local/bin"

cd /workspace/frappe-bench

# Ensure site exists (safe check)
if [ ! -f "sites/site_config.json" ] && [ ! -d "sites" ]; then
  echo "❌ bench not initialized. Please run init.sh once before starting."
  exit 1
fi

# Start bench in foreground so supervisord can capture logs
exec bench start
