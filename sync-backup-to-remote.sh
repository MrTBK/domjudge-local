#!/usr/bin/env bash
# ==============================================================================
# Continuously sync contest backups to Secondary PC (Standby Node)
# Usage: ./sync-backup-to-remote.sh user@10.119.136.XX:/path/to/backups/
# ==============================================================================
set -euo pipefail

REMOTE_TARGET="${1:-}"

if [ -z "$REMOTE_TARGET" ]; then
    echo "Usage: $0 <user@pc2_ip:/path/to/destination_folder>"
    echo "Example: $0 tbk@10.119.136.55:~/domjudge-backup/"
    exit 1
fi

LOCAL_BACKUP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/backups"

echo "Streaming backups from $LOCAL_BACKUP_DIR to $REMOTE_TARGET every 60 seconds..."
while true; do
    if [ -d "$LOCAL_BACKUP_DIR" ]; then
        rsync -avz --delete "$LOCAL_BACKUP_DIR/" "$REMOTE_TARGET" 2>/dev/null && \
        echo "[$(date +'%H:%M:%S')] Synced latest backups to secondary PC." || \
        echo "[$(date +'%H:%M:%S')] WARNING: Sync failed. Check network connection to PC 2."
    fi
    sleep 60
done
