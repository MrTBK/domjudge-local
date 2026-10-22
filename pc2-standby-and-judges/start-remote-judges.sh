#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${BLUE}${BOLD}      DOMjudge Secondary PC - Start Remote Judges     ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}"

if [ ! -f .env ]; then
    echo -e "${RED}[✗] Missing .env file in $SCRIPT_DIR${NC}"
    echo -e "${YELLOW}Run: cp .env.example .env and edit MAIN_SERVER_IP${NC}"
    exit 1
fi

source .env

echo -e "${BLUE}[1/3]${NC} Testing connectivity to Main DOMserver (${MAIN_SERVER_IP}:8080)..."
if curl -s --connect-timeout 4 "http://${MAIN_SERVER_IP}:8080/" >/dev/null 2>&1 || curl -s --connect-timeout 4 "http://${MAIN_SERVER_IP}:8080/api/v4/judgehosts" >/dev/null 2>&1; then
    echo -e "${GREEN}[✓] Main DOMserver is reachable!${NC}"
else
    echo -e "${RED}[✗] Cannot reach http://${MAIN_SERVER_IP}:8080/${NC}"
    echo -e "${YELLOW}Please verify:${NC}"
    echo -e "  1. Both PCs are on the same Wi-Fi / Ethernet."
    echo -e "  2. MAIN_SERVER_IP in .env is correct."
    echo -e "  3. Firewall on Main PC allows port 8080."
    read -rp "Continue anyway? (y/N): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Detect CPU cores on PC 2 to determine safe judgehost count
CPU_CORES=$(nproc 2>/dev/null || echo 4)
echo -e "${BLUE}[2/3]${NC} Detected ${CPU_CORES} CPU core(s) on this machine."

echo -e "${BLUE}[3/3]${NC} Starting Remote Judgehosts..."
docker compose -f docker-compose.remote-judge.yml up -d

echo ""
echo -e "${GREEN}${BOLD}[✓] Remote Judgehosts are running!${NC}"
echo -e "Check logs anytime with:  ${CYAN}docker compose -f docker-compose.remote-judge.yml logs -f${NC}"
echo -e "Stop judges with:        ${CYAN}./stop-remote-judges.sh${NC}"
