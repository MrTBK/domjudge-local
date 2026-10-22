#!/usr/bin/env bash
# ==============================================================================
# Package everything needed for PC 2 (Offline / USB stick mode)
# ==============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

OUTPUT_DIR="$SCRIPT_DIR/pc2_deployment_bundle"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "=========================================================="
echo " Packaging DOMjudge Secondary Node (PC 2 Deployment Bundle)"
echo "=========================================================="

echo "[1/3] Copying scripts and configurations..."
cp -r "$SCRIPT_DIR/pc2-standby-and-judges/"* "$OUTPUT_DIR/"

# Include latest backup if available
mkdir -p "$OUTPUT_DIR/backups"
LATEST_BACKUP=$(ls -t "$SCRIPT_DIR"/backups/*.sql 2>/dev/null | head -n1 || true)
if [ -n "$LATEST_BACKUP" ]; then
    echo "[2/3] Bundling latest database snapshot: $(basename "$LATEST_BACKUP")..."
    cp "$LATEST_BACKUP" "$OUTPUT_DIR/backups/"
else
    echo "[2/3] No existing backup found in backups/ (skipping snapshot copy)."
fi

echo ""
read -rp "Do you also want to export the Docker image (domjudge/judgehost:9.0.1-custom, ~1.6GB)? (y/N): " export_img
if [[ "$export_img" =~ ^[Yy]$ ]]; then
    echo "Exporting custom judgehost image to $OUTPUT_DIR/judgehost_custom.tar.gz (this takes ~1-2 min)..."
    docker save domjudge/judgehost:9.0.1-custom | gzip > "$OUTPUT_DIR/judgehost_custom.tar.gz"
    echo "Docker image exported successfully."
fi

echo ""
echo "Creating archive: domjudge_pc2_bundle.tar.gz..."
tar -czf "$SCRIPT_DIR/domjudge_pc2_bundle.tar.gz" -C "$SCRIPT_DIR" pc2_deployment_bundle

echo "=========================================================="
echo " [✓] BUNDLE READY!"
echo " Folder : $OUTPUT_DIR"
echo " Archive: $SCRIPT_DIR/domjudge_pc2_bundle.tar.gz"
echo "=========================================================="
echo "You can copy this folder or archive to a USB flash drive or"
echo "transfer it directly to PC 2!"
