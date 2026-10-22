#!/usr/bin/env bash
# ==============================================================================
# 1-Click Deployment to PC 2 over SSH
# Usage: ./deploy-to-pc2-ssh.sh <PC2_IP> [PC2_USERNAME]
# Example: ./deploy-to-pc2-ssh.sh 10.119.136.55 tbk
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

PC2_IP="${1:-}"
PC2_USER="${2:-$(whoami)}"

if [ -z "$PC2_IP" ]; then
    echo -e "${RED}Usage: $0 <PC2_IP> [PC2_USERNAME]${NC}"
    echo -e "Example: $0 10.119.136.55 tbk"
    exit 1
fi

echo -e "${BLUE}${BOLD}======================================================${NC}"
echo -e "${BLUE}${BOLD}   Deploying DOMjudge Secondary Node to ${PC2_USER}@${PC2_IP}   ${NC}"
echo -e "${BLUE}${BOLD}======================================================${NC}"

# Detect Main PC IP
MAIN_IP=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | grep -vE '^(172\.|127\.)' | head -n1 || echo "127.0.0.1")

echo -e "${BLUE}[1/5]${NC} Testing SSH connection to ${PC2_USER}@${PC2_IP}..."
ssh -o ConnectTimeout=5 "${PC2_USER}@${PC2_IP}" "echo '[SSH OK] Connected to PC 2'"

echo -e "${BLUE}[2/5]${NC} Synchronizing scripts and configs..."
ssh "${PC2_USER}@${PC2_IP}" "mkdir -p ~/domjudge-pc2/backups"
rsync -avz "$SCRIPT_DIR/pc2-standby-and-judges/" "${PC2_USER}@${PC2_IP}:~/domjudge-pc2/"

# Set Main PC IP in remote .env
ssh "${PC2_USER}@${PC2_IP}" "sed -i 's|^MAIN_SERVER_IP=.*|MAIN_SERVER_IP=${MAIN_IP}|' ~/domjudge-pc2/.env"

echo -e "${BLUE}[3/5]${NC} Checking if custom judgehost image exists on PC 2..."
REMOTE_HAS_IMG=$(ssh "${PC2_USER}@${PC2_IP}" "docker images -q domjudge/judgehost:9.0.1-custom 2>/dev/null" || true)

if [ -z "$REMOTE_HAS_IMG" ]; then
    echo -e "${YELLOW}Image not found on PC 2. Streaming domjudge/judgehost:9.0.1-custom over network...${NC}"
    docker save domjudge/judgehost:9.0.1-custom | ssh "${PC2_USER}@${PC2_IP}" "docker load"
    echo -e "${GREEN}[✓] Image transferred and loaded on PC 2!${NC}"
else
    echo -e "${GREEN}[✓] PC 2 already has domjudge/judgehost:9.0.1-custom!${NC}"
fi

echo -e "${BLUE}[4/5]${NC} Starting remote judges on PC 2..."
ssh "${PC2_USER}@${PC2_IP}" "cd ~/domjudge-pc2 && ./start-remote-judges.sh"

echo -e "${BLUE}[5/5]${NC} Sending initial database backup..."
LATEST_BACKUP=$(ls -t "$SCRIPT_DIR"/backups/*.sql 2>/dev/null | head -n1 || true)
if [ -n "$LATEST_BACKUP" ]; then
    rsync -avz "$LATEST_BACKUP" "${PC2_USER}@${PC2_IP}:~/domjudge-pc2/backups/"
    echo -e "${GREEN}[✓] Initial backup synced!${NC}"
fi

echo ""
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}   PC 2 IS FULLY CONFIGURED AS EXTRA JUDGE & STANDBY BACKUP!      ${NC}"
echo -e "${GREEN}${BOLD}══════════════════════════════════════════════════════════════════${NC}"
echo -e "To stream live backups continuously during the contest, run:"
echo -e "  ${YELLOW}./sync-backup-to-remote.sh ${PC2_USER}@${PC2_IP}:~/domjudge-pc2/backups/ &${NC}"
echo ""
