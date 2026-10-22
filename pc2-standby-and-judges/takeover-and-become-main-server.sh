#!/usr/bin/env bash
# ==============================================================================
# DISASTER RECOVERY: Promote PC 2 to Main Contest Server
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${RED}${BOLD}======================================================${NC}"
echo -e "${RED}${BOLD}   EMERGENCY FAILOVER: ACTIVATING STANDBY DOMSERVER   ${NC}"
echo -e "${RED}${BOLD}======================================================${NC}"

if [ ! -f .env ]; then
    echo -e "${RED}[✗] Missing .env file in $SCRIPT_DIR${NC}"
    echo -e "${YELLOW}Run: cp .env.example .env${NC}"
    exit 1
fi
source .env

# 1. Stop any remote judge daemons currently running
echo -e "${BLUE}[1/6]${NC} Stopping remote judge daemons..."
docker compose -f docker-compose.remote-judge.yml down 2>/dev/null || true

# 2. Find latest database backup
mkdir -p "$SCRIPT_DIR/backups"
LATEST_BACKUP=$(ls -t "$SCRIPT_DIR"/backups/*.sql 2>/dev/null | head -n1 || true)

if [ -z "$LATEST_BACKUP" ]; then
    echo -e "${RED}[✗] No .sql backup file found in $SCRIPT_DIR/backups!${NC}"
    echo "Please place your latest .sql backup inside $SCRIPT_DIR/backups/ and run again."
    exit 1
fi

echo -e "${GREEN}[✓] Found latest database snapshot: ${BOLD}$LATEST_BACKUP${NC}"

# 3. Start MariaDB
echo -e "${BLUE}[2/6]${NC} Starting MariaDB container on PC 2..."
docker compose -f docker-compose.standby.yml up -d mariadb

echo -e "${BLUE}[3/6]${NC} Waiting for MariaDB to be ready for import..."
for i in {1..30}; do
    if docker compose -f docker-compose.standby.yml exec -T mariadb mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
        break
    fi
    sleep 1
done

# 4. Import the database snapshot
echo -e "${BLUE}[4/6]${NC} Restoring database from snapshot..."
docker compose -f docker-compose.standby.yml exec -T mariadb mariadb -uroot -p"${MYSQL_ROOT_PASSWORD}" domjudge < "$LATEST_BACKUP"
echo -e "${GREEN}[✓] Database restored successfully!${NC}"

# 5. Start DOMserver and local judges
echo -e "${BLUE}[5/6]${NC} Starting DOMserver and local judgehosts on PC 2..."
docker compose -f docker-compose.standby.yml up -d domserver judgehost-1 judgehost-2

# 6. Apply PHP-FPM / Nginx contest tuning
echo -e "${BLUE}[6/6]${NC} Tuning DOMserver limits..."
sleep 5
docker compose -f docker-compose.standby.yml exec -T domserver bash -c '
sed -i "s|php_admin_value\[upload_max_filesize\] = .*|php_admin_value[upload_max_filesize] = 512M|" /opt/domjudge/domserver/etc/domjudge-fpm.conf
sed -i "s|php_admin_value\[post_max_size\] = .*|php_admin_value[post_max_size] = 512M|" /opt/domjudge/domserver/etc/domjudge-fpm.conf
sed -i "s|client_max_body_size .*|client_max_body_size 512M;|" /etc/nginx/snippets/domjudge-inner
supervisorctl restart php >/dev/null 2>&1 || true
supervisorctl restart nginx >/dev/null 2>&1 || true
' 2>/dev/null || true

# Detect active IP on PC 2
MY_IP=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -vE '^(172\.|127\.)' | head -n1 || echo "localhost")

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}       FAILOVER SUCCESSFUL! PC 2 IS NOW THE MAIN SERVER           ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════${NC}"
echo -e "  Contest URL for Teams : ${YELLOW}${BOLD}http://${MY_IP}:8080${NC}"
echo -e "  Admin URL             : ${CYAN}http://${MY_IP}:8080/jury${NC}"
echo -e "  Admin Username        : admin"
echo -e "  Admin Password        : ${DOMJUDGE_ADMIN_PASSWORD}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════${NC}"
echo -e "Tip: If your router allows IP reservation, setting PC 2's IP to the old Main PC's IP"
echo -e "will mean teams don't even need to refresh their browser URLs!"
