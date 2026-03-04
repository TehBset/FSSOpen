#!/bin/bash
set -e

# Deployment script for Mutabor VPN Server Monitor
# Usage: ./deploy.sh

echo "================================"
echo "Mutabor VPN Server Monitor Deploy"
echo "================================"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/6] Creating Python virtual environment..."
cd "$SCRIPT_DIR"
python3 -m venv venv
source venv/bin/activate

echo "[2/6] Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "[3/6] Verifying service files..."
if [ ! -f "server_monitor.service" ]; then
    echo "ERROR: server_monitor.service not found!"
    exit 1
fi

echo "[4/6] Installing systemd service..."
sudo cp server_monitor.service /etc/systemd/system/server_monitor.service
sudo systemctl daemon-reload

echo "[5/6] Enabling service to start on boot..."
sudo systemctl enable server_monitor.service

echo "[6/6] Starting service..."
sudo systemctl start server_monitor.service

echo ""
echo "================================"
echo "Deployment complete!"
echo "================================"
echo ""
echo "Service status:"
sudo systemctl status server_monitor.service
echo ""
echo "To view logs:"
echo "  journalctl -u server_monitor.service -f"
echo ""
echo "To test the API:"
echo "  curl http://localhost:8001/stats"
echo "  curl http://localhost:8001/health"
