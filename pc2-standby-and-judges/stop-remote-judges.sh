#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Stopping remote judgehosts on PC 2..."
docker compose -f docker-compose.remote-judge.yml down
echo "Remote judgehosts stopped."
