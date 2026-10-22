#!/usr/bin/env bash
# ==============================================================================
# Automated Live Database Backup Daemon for DOMjudge Contest Day
# Non-blocking, single-transaction hot dumps every 5 minutes
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
fi

BACKUP_DIR="${BACKUP_DIR:-$SCRIPT_DIR/backups}"
ROOT_PWD="${MYSQL_ROOT_PASSWORD:-dj_root_sec_9971bc391f42}"
INTERVAL_SECONDS=300 # 5 minutes

mkdir -p "$BACKUP_DIR"

echo "=========================================================================="
echo "  DOMjudge Contest Live Backup Daemon Running"
echo "  Target Directory: $BACKUP_DIR"
echo "  Frequency: Every 5 minutes (Non-blocking hot snapshots)"
echo "=========================================================================="

while true; do
    TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    BACKUP_FILE="$BACKUP_DIR/domjudge_live_${TIMESTAMP}.sql"
    
    if docker compose exec -T mariadb mariadb-dump -uroot -p"$ROOT_PWD" --single-transaction --quick domjudge > "$BACKUP_FILE" 2>/dev/null; then
        FILE_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
        echo "[$(date +"%H:%M:%S")] Backup OK: $BACKUP_FILE ($FILE_SIZE)"
        
        # Keep latest 20 snapshots
        ls -t "$BACKUP_DIR"/domjudge_live_*.sql 2>/dev/null | tail -n +21 | xargs -r rm --
    else
        echo "[$(date +"%H:%M:%S")] WARNING: Backup failed! Check if mariadb container is running."
    fi

    sleep $INTERVAL_SECONDS
done
