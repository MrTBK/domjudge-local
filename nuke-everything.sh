#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${RED}${BOLD}======================================================${NC}"
echo -e "${RED}${BOLD}          DOMjudge Complete Teardown Utility          ${NC}"
echo -e "${RED}${BOLD}======================================================${NC}"
echo -e "${YELLOW}This will permanently remove:${NC}"
echo -e "  - Containers (dj-domserver, dj-mariadb, dj-judgehost-1, dj-judgehost-2)"
echo -e "  - Docker network (domjudge-net)"
echo -e "  - Named Docker volume and all database contents (dj-db-data)"
echo ""

read -r -p "Are you sure you want to completely destroy the contest environment? [y/N]: " CONFIRM
CONFIRM=${CONFIRM:-N}

case "${CONFIRM}" in
  [yY][eE][sS]|[yY])
    echo -e "\n${YELLOW}[..] Destroying containers, network, and volumes...${NC}"
    docker compose down -v --remove-orphans

    # Reset JUDGEDAEMON_PASSWORD in .env
    if [ -f "${SCRIPT_DIR}/.env" ]; then
      sed -i "s|^JUDGEDAEMON_PASSWORD=.*|JUDGEDAEMON_PASSWORD=placeholder_will_be_auto_updated|" "${SCRIPT_DIR}/.env"
    fi

    echo -e "${GREEN}${BOLD}[✓] Complete teardown finished. Zero trace left on system!${NC}"
    ;;
  *)
    echo -e "\n${GREEN}Teardown aborted. Contest environment remains untouched.${NC}"
    exit 0
    ;;
esac
