#!/usr/bin/env bash
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

echo -e "${CYAN}${BOLD}======================================================${NC}"
echo -e "${CYAN}${BOLD}       DOMjudge Local Orchestrator - Bootstrap        ${NC}"
echo -e "${CYAN}${BOLD}======================================================${NC}"

# Detect Active Wi-Fi Network Interface & IP
WIFI_IFACE=$(ip -br -4 addr show up 2>/dev/null | awk '$1 ~ /^(wl|wlan)/ {print $1; exit}' || true)
WIFI_IP=""
if [ -n "${WIFI_IFACE}" ]; then
  WIFI_IP=$(ip -br -4 addr show dev "${WIFI_IFACE}" 2>/dev/null | awk '{print $3}' | cut -d/ -f1 || true)
fi

# Fallback to general LAN IP if Wi-Fi interface is not found or has no IP assigned
if [ -z "${WIFI_IP}" ]; then
  WIFI_IP=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -vE '^(172\.|127\.)' | head -n1 || true)
fi
if [ -z "${WIFI_IP}" ]; then
  WIFI_IP="127.0.0.1"
fi
LAN_IP="${WIFI_IP}"

echo -e "${BLUE}[1/5]${NC} Starting MariaDB and DOMserver containers..."
docker compose up -d mariadb domserver

echo -e "${BLUE}[2/5]${NC} Waiting for DOMserver initialization and database setup..."
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
  echo -e "${YELLOW}Check container logs with: docker compose logs domserver${NC}"
  exit 1
fi

echo -e "${BLUE}[3/5]${NC} Tuning PHP-FPM, Nginx, and Contest Languages..."
# Apply upload limits and memory settings in domserver
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

if [ -f "${SCRIPT_DIR}/custom-templates/DOMjudgelogo.svg" ]; then
  docker compose cp "${SCRIPT_DIR}/custom-templates/DOMjudgelogo.svg" domserver:/opt/domjudge/domserver/webapp/public/images/DOMjudgelogo.svg 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/hive-logo.png" domserver:/opt/domjudge/domserver/webapp/public/images/hive-logo.png 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/hive-logo-white.png" domserver:/opt/domjudge/domserver/webapp/public/images/hive-logo-white.png 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/favicon.svg" domserver:/opt/domjudge/domserver/webapp/public/images/favicon.svg 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/favicon-32x32.png" domserver:/opt/domjudge/domserver/webapp/public/images/favicon-32x32.png 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/favicon-16x16.png" domserver:/opt/domjudge/domserver/webapp/public/images/favicon-16x16.png 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/favicon.ico" domserver:/opt/domjudge/domserver/webapp/public/favicon.ico 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/apple-touch-icon.png" domserver:/opt/domjudge/domserver/webapp/public/apple-touch-icon.png 2>/dev/null || true
  docker compose cp "${SCRIPT_DIR}/custom-templates/hive-theme.css" domserver:/opt/domjudge/domserver/webapp/public/css/custom/hive-theme.css 2>/dev/null || true
  docker compose exec -T domserver chown -R www-data:www-data /opt/domjudge/domserver/webapp/public/images/ /opt/domjudge/domserver/webapp/public/css/custom/ /opt/domjudge/domserver/webapp/public/favicon.ico /opt/domjudge/domserver/webapp/public/apple-touch-icon.png 2>/dev/null || true
  docker compose exec -T domserver /opt/domjudge/domserver/webapp/bin/console cache:clear >/dev/null 2>&1 || true
fi

# Ensure required languages are enabled and Go is registered
source "${SCRIPT_DIR}/.env"
docker compose exec -T mariadb mariadb -udomjudge -p"${MYSQL_PASSWORD}" domjudge >/dev/null 2>&1 << 'EOF' || true
START TRANSACTION;
INSERT INTO immutable_executable (userid, hash) 
SELECT 1, MD5('go-compile-v1') 
WHERE NOT EXISTS (SELECT 1 FROM executable WHERE execid = 'go');

SET @imm_id = (SELECT immutable_execid FROM immutable_executable WHERE hash = MD5('go-compile-v1') LIMIT 1);

INSERT INTO executable (execid, description, type, immutable_execid)
SELECT 'go', 'go', 'compile', @imm_id
WHERE NOT EXISTS (SELECT 1 FROM executable WHERE execid = 'go');

INSERT INTO executable_file (immutable_execid, filename, ranknumber, file_content, hash, is_executable)
SELECT @imm_id, 'build', 1, '#!/bin/sh\n# nothing to compile\n', MD5('#!/bin/sh\n# nothing to compile\n'), 1
WHERE NOT EXISTS (SELECT 1 FROM executable_file WHERE immutable_execid = @imm_id AND filename = 'build');

INSERT INTO executable_file (immutable_execid, filename, ranknumber, file_content, hash, is_executable)
SELECT @imm_id, 'run', 2, '#!/bin/sh\nDEST="$1" ; shift\nMEMLIMIT="$1" ; shift\nMAINSOURCE="$1"\nexport GOCACHE=/tmp/gocache\nexport GOPATH=/tmp/gopath\nmkdir -p /tmp/gocache /tmp/gopath\ngo build -o "$DEST" "$@"\nEXITCODE=$?\nrm -rf /tmp/gocache /tmp/gopath\nexit $EXITCODE\n', MD5('go_run_script_v1'), 1
WHERE NOT EXISTS (SELECT 1 FROM executable_file WHERE immutable_execid = @imm_id AND filename = 'run');

INSERT INTO language (langid, externalid, name, extensions, require_entry_point, entry_point_description, allow_submit, allow_judge, time_factor, compile_script, filter_compiler_files, compiler_version_command, runner_version_command)
SELECT 'go', 'go', 'Go', '["go"]', 0, NULL, 1, 1, 1, 'go', 1, 'go version', NULL
WHERE NOT EXISTS (SELECT 1 FROM language WHERE langid = 'go');

UPDATE language SET allow_submit = 1 WHERE langid IN ('cpp', 'c', 'java', 'py3', 'rs', 'kt', 'js', 'csharp', 'go');

-- Ensure Manouba Contest exists
INSERT INTO contest (
    cid, externalid, name, shortname,
    activatetime, starttime, freezetime, endtime, unfreezetime, deactivatetime,
    activatetime_string, starttime_string, freezetime_string, endtime_string, unfreezetime_string, deactivatetime_string,
    enabled, starttime_enabled, process_balloons, public, open_to_all_teams, allow_submit
)
SELECT 1, 'manouba', 'Manouba Contest', 'manouba',
    UNIX_TIMESTAMP(), 1793185200, 1793196000, 1793199600, 1793203200, 1793286000,
    FROM_UNIXTIME(UNIX_TIMESTAMP(), '%Y-%m-%d %H:%i:%s Africa/Tunis'),
    '2026-10-28 12:00:00 Africa/Tunis',
    '2026-10-28 15:00:00 Africa/Tunis',
    '2026-10-28 16:00:00 Africa/Tunis',
    '2026-10-28 17:00:00 Africa/Tunis',
    '2026-10-29 16:00:00 Africa/Tunis',
    1, 1, 1, 1, 1, 1
WHERE NOT EXISTS (SELECT 1 FROM contest WHERE externalid = 'manouba');

-- Ensure Problem A (Scammini) is attached
INSERT INTO contestproblem (cid, probid, shortname, points, allow_submit, allow_judge, color, lazy_eval_results)
SELECT c.cid, 5, 'A', 1, 1, 1, '#3B82F6', 0 FROM contest c WHERE c.externalid = 'manouba'
AND NOT EXISTS (SELECT 1 FROM contestproblem cp WHERE cp.cid = c.cid AND cp.probid = 5);

COMMIT;
EOF
echo -e "${GREEN}[✓] Limits set to 512M and languages (C, C++, Java, PyPy3, Rust, Kotlin, JS, C#, Go) enabled.${NC}"

echo -e "${BLUE}[4/5]${NC} Extracting secrets and updating configuration..."
RESTAPI_FILE="/opt/domjudge/domserver/etc/restapi.secret"

source "${SCRIPT_DIR}/.env"
DOMJUDGE_ADMIN_PASSWORD="${DOMJUDGE_ADMIN_PASSWORD:-admin1234}"
ADMIN_PW="${DOMJUDGE_ADMIN_PASSWORD}"

JUDGE_PW=$(docker compose exec -T domserver awk '$3=="judgehost" {print $4}' "${RESTAPI_FILE}" 2>/dev/null | tr -d '\r\n')
if [ -z "${JUDGE_PW}" ]; then
  JUDGE_PW=$(docker compose exec -T domserver grep -v '^#' "${RESTAPI_FILE}" 2>/dev/null | awk '{print $4}' | tr -d '\r\n')
fi

if [ -z "${JUDGE_PW}" ]; then
  echo -e "${RED}[✗] Failed to extract judgehost password from ${RESTAPI_FILE}.${NC}"
  exit 1
fi

# Sync passwords into DOMjudge database
docker compose exec -T domserver /opt/domjudge/domserver/webapp/bin/console domjudge:reset-user-password admin "${DOMJUDGE_ADMIN_PASSWORD}" >/dev/null 2>&1 || true
docker compose exec -T domserver /opt/domjudge/domserver/webapp/bin/console domjudge:reset-user-password judgehost "${JUDGE_PW}" >/dev/null 2>&1 || true

sed -i "s|^JUDGEDAEMON_PASSWORD=.*|JUDGEDAEMON_PASSWORD=${JUDGE_PW}|" "${SCRIPT_DIR}/.env"
echo -e "${GREEN}[✓] Synchronized DOMjudge credentials and updated .env.${NC}"

echo -e "${BLUE}[5/5]${NC} Launching 8 Judgehost containers (pinned to cores 4, 5, 6, 7, 8, 9, 10, 11)..."
docker compose up -d dj-judgehost-1 dj-judgehost-2 dj-judgehost-3 dj-judgehost-4 dj-judgehost-5 dj-judgehost-6 dj-judgehost-7 dj-judgehost-8

echo -e "${YELLOW}      Awaiting 8 judgehosts to register with DOMserver...${NC}"
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

JH1_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-1 2>/dev/null || echo "unknown")
JH2_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-2 2>/dev/null || echo "unknown")
JH3_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-3 2>/dev/null || echo "unknown")
JH4_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-4 2>/dev/null || echo "unknown")
JH5_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-5 2>/dev/null || echo "unknown")
JH6_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-6 2>/dev/null || echo "unknown")
JH7_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-7 2>/dev/null || echo "unknown")
JH8_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-8 2>/dev/null || echo "unknown")

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║              DOMJUDGE HIGH-PERFORMANCE CLUSTER (8 CORES)             ║${NC}"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Wi-Fi Interface"        "${WIFI_IFACE:-None (fallback)}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Wi-Fi IP Address"       "${WIFI_IP}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${YELLOW}${BOLD}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "TEAM ACCESS URL"        "http://${WIFI_IP}:8080"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Public Arena (Wi-Fi)"    "http://${WIFI_IP}:8080/public"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Team Portal (Wi-Fi)"     "http://${WIFI_IP}:8080/team"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Jury / Admin (Local)"    "http://localhost:8080/jury"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${BOLD}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Admin Username"         "admin"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${YELLOW}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Admin Password"         "${ADMIN_PW}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${BOLD}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Default Team User"       "demo"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${YELLOW}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Default Team Password"   "demo"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Judgehosts 1-4 (Cores 4-7)" "${JH1_STATUS}, ${JH2_STATUS}, ${JH3_STATUS}, ${JH4_STATUS}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Judgehosts 5-8 (Cores 8-11)" "${JH5_STATUS}, ${JH6_STATUS}, ${JH7_STATUS}, ${JH8_STATUS}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${GREEN}%-43s${NC} ${GREEN}${BOLD}║${NC}\n" "Active in DOMjudge"     "${API_JH_COUNT} daemon(s) registered"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : %-43s ${GREEN}${BOLD}║${NC}\n" "Languages Enabled"     "C, C++, Java, PyPy3, Rust, Go..."
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : %-43s ${GREEN}${BOLD}║${NC}\n" "Max Upload / Post Size" "512M (Nginx + PHP-FPM)"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : %-43s ${GREEN}${BOLD}║${NC}\n" "Stop without data loss" "./stop-contest.sh"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : %-43s ${GREEN}${BOLD}║${NC}\n" "Wipe all contest data"  "./nuke-everything.sh"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : %-43s ${GREEN}${BOLD}║${NC}\n" "Polygon converter"     "./.venv/bin/p2d"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
echo -e "${GREEN}${BOLD}║                  WI-FI CONTEST CHECKLIST & PRE-FLIGHT                ║${NC}"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${YELLOW}%-67s${NC} ${GREEN}${BOLD}║${NC}\n" "[!] 1. AP / Client Isolation: MUST be DISABLED on the router"
printf "${GREEN}${BOLD}║${NC}  ${NC}%-67s${NC} ${GREEN}${BOLD}║${NC}\n" "       (Allows team laptops to communicate with host IP)"
printf "${GREEN}${BOLD}║${NC}  ${NC}%-67s${NC} ${GREEN}${BOLD}║${NC}\n" "[*] 2. Same Network: Teams must connect to this Wi-Fi network"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-67s${NC} ${GREEN}${BOLD}║${NC}\n" "[*] 3. Contest URL: http://${WIFI_IP}:8080"
printf "${GREEN}${BOLD}║${NC}  ${NC}%-67s${NC} ${GREEN}${BOLD}║${NC}\n" "[*] 4. Host Firewall: Port 8080 must accept incoming TCP packets"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
