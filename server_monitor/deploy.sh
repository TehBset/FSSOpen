#!/bin/bash
set -e

# Deployment script for Mutabor VPN Server Monitor
# Usage: sudo bash deploy.sh

echo "================================"
echo "Mutabor VPN Server Monitor Deploy"
echo "================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "ERROR: This script must be run with sudo"
    echo "Usage: sudo bash deploy.sh"
    exit 1
fi

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "[1/6] Checking and installing system dependencies..."
# Check if python3-venv is installed
if ! python3 -m venv --help &>/dev/null; then
    echo "  Installing python3-venv..."
    apt-get update
    apt-get install -y python3-venv python3-dev
fi

# Check if vnstat is installed
if ! command -v vnstat &> /dev/null; then
    echo "  Installing vnstat..."
    apt-get install -y vnstat
fi

# Check if ufw is enabled and open port 8001
if command -v ufw &> /dev/null; then
    UFW_STATUS=$(ufw status | grep -i active)
    if [ ! -z "$UFW_STATUS" ]; then
        echo "  UFW is active, opening port 8001..."
        ufw allow 8001/tcp || echo "  (Could not open port, may require confirmation)"
    fi
fi

echo "[2/6] Creating Python virtual environment..."
cd "$SCRIPT_DIR"
python3 -m venv venv
source venv/bin/activate

echo "[3/6] Installing Python dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

echo "[4/6] Verifying service files..."
if [ ! -f "server_monitor.service" ]; then
    echo "ERROR: server_monitor.service not found!"
    exit 1
fi

echo "[5/6] Installing systemd service..."
cp server_monitor.service /etc/systemd/system/server_monitor.service
systemctl daemon-reload
systemctl enable server_monitor.service

echo "[6/6] Starting service..."
systemctl start server_monitor.service

echo ""
echo "================================"
echo "Deployment complete!"
echo "================================"
echo ""
echo "Checking service status:"
systemctl status server_monitor.service --no-pager
echo ""
echo "Recent logs:"
journalctl -u server_monitor.service -n 10 --no-pager
echo ""
echo "To view live logs:"
echo "  journalctl -u server_monitor.service -f"
echo ""
echo "To test the API:"
echo "  curl http://localhost:8001/stats"
echo "  curl http://localhost:8001/health"

