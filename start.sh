#!/bin/bash
set -e

echo "🚀 start.sh: starting bench..."

if [ ! -d "/workspace/frappe-bench" ]; then
    echo "❌ Bench not found. Run init.sh first."
    exit 1
fi

cd /workspace/frappe-bench

# Run bench in foreground mode (required for Docker)
bench start
