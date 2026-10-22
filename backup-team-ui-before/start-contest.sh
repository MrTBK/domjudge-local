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

# Detect LAN IP (excluding loopback and docker bridge subnets)
LAN_IP=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -vE '^(172\.|127\.)' | head -n1 || true)
if [ -z "${LAN_IP}" ]; then
  LAN_IP="127.0.0.1"
fi

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
  docker compose exec -T domserver chown -R www-data:www-data /opt/domjudge/domserver/webapp/public/images/ /opt/domjudge/domserver/webapp/public/favicon.ico /opt/domjudge/domserver/webapp/public/apple-touch-icon.png 2>/dev/null || true
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

-- Ensure Demo contest exists and is active if no contest exists
INSERT INTO contest (cid, externalid, name, shortname, starttime, endtime, freezetime, activatetime, enabled, public)
SELECT 2, 'demo', 'Demo contest', 'demo', UNIX_TIMESTAMP(), UNIX_TIMESTAMP() + 18000, UNIX_TIMESTAMP() + 14400, UNIX_TIMESTAMP(), 1, 1
WHERE NOT EXISTS (SELECT 1 FROM contest);

INSERT INTO contestproblem (cid, probid, shortname, points, allow_submit, allow_judge, color, lazy_eval_results)
SELECT c.cid, 1, 'A', 1, 1, 1, '#9486EA', 0 FROM contest c WHERE c.shortname = 'demo'
AND NOT EXISTS (SELECT 1 FROM contestproblem cp WHERE cp.cid = c.cid AND cp.probid = 1);

INSERT INTO contestproblem (cid, probid, shortname, points, allow_submit, allow_judge, color, lazy_eval_results)
SELECT c.cid, 2, 'B', 1, 1, 1, '#E93603', 0 FROM contest c WHERE c.shortname = 'demo'
AND NOT EXISTS (SELECT 1 FROM contestproblem cp WHERE cp.cid = c.cid AND cp.probid = 2);

INSERT INTO contestproblem (cid, probid, shortname, points, allow_submit, allow_judge, color, lazy_eval_results)
SELECT c.cid, 3, 'C', 1, 1, 1, '#9B630C', 0 FROM contest c WHERE c.shortname = 'demo'
AND NOT EXISTS (SELECT 1 FROM contestproblem cp WHERE cp.cid = c.cid AND cp.probid = 3);

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

echo -e "${BLUE}[5/5]${NC} Launching 4 Judgehost containers (pinned to cores 8, 9, 10, 11)..."
docker compose up -d dj-judgehost-1 dj-judgehost-2 dj-judgehost-3 dj-judgehost-4

echo -e "${YELLOW}      Awaiting 4 judgehosts to register with DOMserver...${NC}"
API_JH_COUNT=0
for _ in {1..30}; do
  if [ -n "${ADMIN_PW}" ]; then
    API_JH_COUNT=$(curl -s -u "admin:${ADMIN_PW}" http://127.0.0.1:8080/api/v4/judgehosts 2>/dev/null | grep -o '"hostname":"judgehost-[^"]*"' | wc -l | tr -d '[:space:]' || echo "0")
    if [ "${API_JH_COUNT:-0}" -ge 4 ]; then
      break
    fi
  fi
  sleep 1
done

JH1_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-1 2>/dev/null || echo "unknown")
JH2_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-2 2>/dev/null || echo "unknown")
JH3_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-3 2>/dev/null || echo "unknown")
JH4_STATUS=$(docker inspect --format '{{.State.Status}}' dj-judgehost-4 2>/dev/null || echo "unknown")

echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║              DOMJUDGE PRODUCTION ENVIRONMENT (4 CORES)               ║${NC}"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Public Arena (Local)"  "http://localhost:8080/public"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Public Arena (LAN)"    "http://${LAN_IP}:8080/public"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Team Interface"        "http://localhost:8080/team"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Jury / Admin Panel"   "http://localhost:8080/jury"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${BOLD}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Admin Username" "admin"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${YELLOW}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Admin Password" "${ADMIN_PW}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${BOLD}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Default Team User" "demo"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${YELLOW}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Default Team Password" "demo"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Judgehost 1 (Core 8)"  "${JH1_STATUS} (daemon 0)"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Judgehost 2 (Core 9)"  "${JH2_STATUS} (daemon 1)"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Judgehost 3 (Core 10)" "${JH3_STATUS} (daemon 2)"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${CYAN}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Judgehost 4 (Core 11)" "${JH4_STATUS} (daemon 3)"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : ${GREEN}%-41s${NC}${GREEN}${BOLD}║${NC}\n" "Active in DOMjudge" "${API_JH_COUNT} daemon(s) registered"
echo -e "${GREEN}${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : %-41s${GREEN}${BOLD}║${NC}\n" "Languages Enabled" "C, C++, Java, PyPy3, Rust, Go..."
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : %-41s${GREEN}${BOLD}║${NC}\n" "Max Upload / Post Size" "512M (Nginx + PHP-FPM)"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : %-41s${GREEN}${BOLD}║${NC}\n" "Stop without data loss" "./stop-contest.sh"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : %-41s${GREEN}${BOLD}║${NC}\n" "Wipe all contest data"  "./nuke-everything.sh"
printf "${GREEN}${BOLD}║${NC}  ${BOLD}%-22s${NC} : %-41s${GREEN}${BOLD}║${NC}\n" "Polygon converter"     "./.venv/bin/p2d"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
