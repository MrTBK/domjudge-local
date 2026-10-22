#!/usr/bin/env bash
# ==============================================================================
# DOMjudge Contest Launcher - WI-FI MODE
# Dedicated for hosting the contest over local Wi-Fi
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${CYAN}${BOLD}======================================================================${NC}"
echo -e "${CYAN}${BOLD}       DOMjudge Local Orchestrator - WI-FI CONTEST LAUNCHER          ${NC}"
echo -e "${CYAN}${BOLD}======================================================================${NC}"

# Detect Active Wi-Fi Interface & IP
WIFI_IFACE=$(ip -br -4 addr show up 2>/dev/null | awk '$1 ~ /^(wl|wlan)/ {print $1; exit}' || true)
WIFI_IP=""

if [ -n "${WIFI_IFACE}" ]; then
  WIFI_IP=$(ip -br -4 addr show dev "${WIFI_IFACE}" 2>/dev/null | awk '{print $3}' | cut -d/ -f1 || true)
fi

if [ -z "${WIFI_IFACE}" ] || [ -z "${WIFI_IP}" ]; then
  echo -e "${RED}${BOLD}[✗] ERROR: No active Wi-Fi connection detected!${NC}"
  echo -e "${YELLOW}Please connect your laptop to the contest Wi-Fi network and try again.${NC}"
  echo -e "Available interfaces:"
  ip -br addr show
  exit 1
fi

echo -e "${GREEN}[✓] Active Wi-Fi Interface: ${BOLD}${WIFI_IFACE}${NC} (IP: ${CYAN}${BOLD}${WIFI_IP}${NC})"

# 1. Start Database & Web Tier
echo -e "${BLUE}[1/5]${NC} Starting MariaDB and DOMserver containers..."
docker compose up -d mariadb domserver

# 2. Wait for DOMserver readiness
echo -e "${BLUE}[2/5]${NC} Waiting for DOMserver initialization..."
MAX_WAIT=180
ELAPSED=0
SPINNER='|/-\'
SPIN_IDX=0

while [ ${ELAPSED} -lt ${MAX_WAIT} ]; do
  ADMIN_READY=false
  REST_READY=false
  NGINX_READY=false

  if docker compose exec -T domserver test -s /opt/domjudge/domserver/etc/initial_admin_password.secret 2>/dev/null; then
    ADMIN_READY=true
  fi
  if docker compose exec -T domserver test -s /opt/domjudge/domserver/etc/restapi.secret 2>/dev/null; then
    REST_READY=true
  fi
  if docker compose exec -T domserver supervisorctl status 2>/dev/null | grep -q "nginx.*RUNNING"; then
    NGINX_READY=true
  fi

  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:8080/ 2>/dev/null || echo "000")

  if [ "${ADMIN_READY}" = "true" ] && [ "${REST_READY}" = "true" ] && [ "${NGINX_READY}" = "true" ] && { [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "302" ]; }; then
    echo -e "\n${GREEN}[✓] DOMserver and database successfully initialized!${NC}"
    break
  fi

  printf "\r${YELLOW}      [%c] Waiting for initial credentials and web server... (%ds / %ds)${NC}" \
    "${SPINNER:$SPIN_IDX:1}" "${ELAPSED}" "${MAX_WAIT}"
  SPIN_IDX=$(( (SPIN_IDX + 1) % 4 ))
  sleep 3
  ELAPSED=$((ELAPSED + 3))
done

if [ ${ELAPSED} -ge ${MAX_WAIT} ]; then
  echo -e "\n${RED}[✗] Timed out waiting for DOMserver initialization.${NC}"
  exit 1
fi

# 3. High-Performance Tuning (PHP-FPM 100 workers, 512M upload)
echo -e "${BLUE}[3/5]${NC} Applying high-concurrency tuning (100 PHP-FPM workers, 512M uploads)..."
docker compose exec -T domserver bash -c '
sed -i "s|php_admin_value\[upload_max_filesize\] = .*|php_admin_value[upload_max_filesize] = 512M|" /opt/domjudge/domserver/etc/domjudge-fpm.conf
sed -i "s|php_admin_value\[post_max_size\] = .*|php_admin_value[post_max_size] = 512M|" /opt/domjudge/domserver/etc/domjudge-fpm.conf
sed -i "s|php_admin_value\[max_file_uploads\] = .*|php_admin_value[max_file_uploads] = 500|" /opt/domjudge/domserver/etc/domjudge-fpm.conf
sed -i "s|php_admin_value\[memory_limit\] = .*|php_admin_value[memory_limit] = 1024M|" /opt/domjudge/domserver/etc/domjudge-fpm.conf
sed -i "s|pm.max_children = .*|pm.max_children = 100|" /opt/domjudge/domserver/etc/domjudge-fpm.conf
sed -i "s|client_max_body_size .*|client_max_body_size 512M;|" /etc/nginx/snippets/domjudge-inner

supervisorctl restart php >/dev/null
supervisorctl restart nginx >/dev/null
'

# Sync custom templates & theme if present
if [ -f "${SCRIPT_DIR}/custom-templates/DOMjudgelogo.svg" ]; then
  docker compose cp "${SCRIPT_DIR}/custom-templates/DOMjudgelogo.svg" domserver:/opt/domjudge/domserver/webapp/public/images/DOMjudgelogo.svg 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/hive-logo.png" domserver:/opt/domjudge/domserver/webapp/public/images/hive-logo.png 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/hive-logo-white.png" domserver:/opt/domjudge/domserver/webapp/public/images/hive-logo-white.png 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/favicon.svg" domserver:/opt/domjudge/domserver/webapp/public/images/favicon.svg 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/hive-theme.css" domserver:/opt/domjudge/domserver/webapp/public/css/custom/hive-theme.css 2>/dev/null || true
  docker compose exec -T domserver chown -R www-data:www-data /opt/domjudge/domserver/webapp/public/images/ /opt/domjudge/domserver/webapp/public/css/custom/ 2>/dev/null || true
  docker compose exec -T domserver /opt/domjudge/domserver/webapp/bin/console cache:clear >/dev/null 2>&1 || true
fi

# Ensure languages enabled
source "${SCRIPT_DIR}/.env"
docker compose exec -T mariadb mariadb -udomjudge -p"${MYSQL_PASSWORD}" domjudge >/dev/null 2>&1 << 'EOF' || true
UPDATE language SET allow_submit = 1 WHERE langid IN ('cpp', 'c', 'java', 'py3', 'rs', 'kt', 'js', 'csharp', 'go');
EOF

# 4. Synchronize Credentials
echo -e "${BLUE}[4/5]${NC} Synchronizing cluster passwords and API credentials..."
RESTAPI_FILE="/opt/domjudge/domserver/etc/restapi.secret"
source "${SCRIPT_DIR}/.env"
DOMJUDGE_ADMIN_PASSWORD="${DOMJUDGE_ADMIN_PASSWORD:-admin1234}"
ADMIN_PW="${DOMJUDGE_ADMIN_PASSWORD}"

JUDGE_PW=$(docker compose exec -T domserver awk '$3=="judgehost" {print $4}' "${RESTAPI_FILE}" 2>/dev/null | tr -d '\r\n')
if [ -z "${JUDGE_PW}" ]; then
  JUDGE_PW=$(docker compose exec -T domserver grep -v '^#' "${RESTAPI_FILE}" 2>/dev/null | awk '{print $4}' | tr -d '\r\n')
fi

docker compose exec -T domserver /opt/domjudge/domserver/webapp/bin/console domjudge:reset-user-password admin "${DOMJUDGE_ADMIN_PASSWORD}" >/dev/null 2>&1 || true
docker compose exec -T domserver /opt/domjudge/domserver/webapp/bin/console domjudge:reset-user-password judgehost "${JUDGE_PW}" >/dev/null 2>&1 || true
sed -i "s|^JUDGEDAEMON_PASSWORD=.*|JUDGEDAEMON_PASSWORD=${JUDGE_PW}|" "${SCRIPT_DIR}/.env"

# 5. Launch all 8 dedicated Judgehosts
echo -e "${BLUE}[5/5]${NC} Launching 8 dedicated Judgehosts (pinned to CPU Cores 4 through 11)..."
docker compose up -d dj-judgehost-1 dj-judgehost-2 dj-judgehost-3 dj-judgehost-4 dj-judgehost-5 dj-judgehost-6 dj-judgehost-7 dj-judgehost-8

# Start automated 5-minute live backup daemon in background if not already running
mkdir -p "${SCRIPT_DIR}/backups"
if ! pgrep -f "auto-backup.sh" >/dev/null 2>&1; then
  nohup "${SCRIPT_DIR}/auto-backup.sh" > "${SCRIPT_DIR}/backups/backup_daemon.log" 2>&1 &
  echo -e "${GREEN}[✓] 5-minute live disaster recovery backup daemon started (PID: $!).${NC}"
else
  echo -e "${GREEN}[✓] 5-minute live backup daemon is already active.${NC}"
fi

# Await registration
API_JH_COUNT=0
for _ in {1..35}; do
  if [ -n "${ADMIN_PW}" ]; then
    API_JH_COUNT=$(curl -s -u "admin:${ADMIN_PW}" http://127.0.0.1:8080/api/v4/judgehosts 2>/dev/null | grep -o '"hostname":"judgehost-[^"]*"' | wc -l | tr -d '[:space:]' || echo "0")
    if [ "${API_JH_COUNT:-0}" -ge 8 ]; then
      break
    fi
  fi
  sleep 1
done

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║           DOMJUDGE CLUSTER IS LIVE — WI-FI HOST MODE                ║${NC}"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Network Mode"            "WI-FI (Local WLAN)"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Wi-Fi Interface"         "${WIFI_IFACE}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Host Wi-Fi IP"           "${WIFI_IP}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${YELLOW}${BOLD}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "TEAM CONTEST URL"        "http://${WIFI_IP}:8080"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Team Portal"             "http://${WIFI_IP}:8080/team"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Public Scoreboard"       "http://${WIFI_IP}:8080/public"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Jury / Admin Panel"     "http://localhost:8080/jury"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${BOLD}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Admin Credentials"      "admin / ${ADMIN_PW}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${BOLD}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Default Team Login"     "demo / demo"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${GREEN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Judgehosts Active"      "${API_JH_COUNT} / 8 cores online"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${GREEN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Live 5-Min Backups"    "Active in ./backups/"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}${BOLD}║                    WI-FI CONTEST CHECKLIST                           ║${NC}"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${YELLOW}%-67s${NC} ${GREEN}${BOLD}║${NC}\n" "[!] 1. AP / Client Isolation: MUST BE DISABLED ON THE ROUTER"
printf "${GREEN}${BOLD}║${NC}  ${NC}%-67s${NC} ${GREEN}${BOLD}║${NC}\n" "       (Allows team laptops to communicate with this server)"
printf "${GREEN}${BOLD}║${NC}  ${NC}%-67s${NC} ${GREEN}${BOLD}║${NC}\n" "[*] 2. Same Wi-Fi SSID: All 50 team laptops must connect to this Wi-Fi"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-67s${NC} ${GREEN}${BOLD}║${NC}\n" "[*] 3. Contest Link for Teams: http://${WIFI_IP}:8080"
printf "${GREEN}${BOLD}║${NC}  ${NC}%-67s${NC} ${GREEN}${BOLD}║${NC}\n" "[*] 4. Stop contest safely: ./stop-contest.sh"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
