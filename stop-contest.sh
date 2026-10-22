#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${YELLOW}${BOLD}Stopping DOMjudge local environment...${NC}"
pkill -f "auto-backup.sh" 2>/dev/null || true
docker compose stop

echo -e "${GREEN}[✓] DOMjudge containers stopped safely.${NC}"
echo -e "${BLUE}Contest data and submissions are preserved in named volume 'dj-db-data'.${NC}"
echo -e "Run ${BOLD}./start-contest.sh${NC} anytime to resume the contest."
