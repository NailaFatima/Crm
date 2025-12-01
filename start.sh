#!/bin/bash
echo "🚀 start.sh: starting bench..."

if [ ! -d "/workspace/frappe-bench" ]; then
    echo "❌ /workspace/frappe-bench missing. init.sh failed earlier."
    exit 1
fi

cd /workspace/frappe-bench

echo "▶ Running: bench start on port 8001"
exec bench start --port 8001
