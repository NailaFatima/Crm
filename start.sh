#!/bin/bash
echo "🚀 start.sh: starting bench..."

if [ ! -d "/workspace/frappe-bench" ]; then
    echo "❌ /workspace/frappe-bench missing. init.sh never completed."
    exit 1
fi

cd /workspace/frappe-bench
exec bench start
