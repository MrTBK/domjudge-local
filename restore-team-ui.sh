#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${SCRIPT_DIR}/backup-team-ui-before"

if [ ! -d "${BACKUP_DIR}" ]; then
  echo "Error: Backup directory ${BACKUP_DIR} not found!"
  exit 1
fi

echo "Restoring DOMjudge team UI from ${BACKUP_DIR}..."
cp -r "${BACKUP_DIR}/custom-templates" "${SCRIPT_DIR}/"
cp "${BACKUP_DIR}/docker-compose.yml" "${SCRIPT_DIR}/"
cp "${BACKUP_DIR}/start-contest.sh" "${SCRIPT_DIR}/"

docker compose up -d domserver
sleep 3
"${SCRIPT_DIR}/start-contest.sh" || true
echo "Restoration complete! Previous state is restored."
