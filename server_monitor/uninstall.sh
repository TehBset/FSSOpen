#!/bin/bash

# Uninstall script for Mutabor VPN Server Monitor
# Usage: ./uninstall.sh

echo "Uninstalling Mutabor VPN Server Monitor..."

echo "[1/3] Stopping service..."
sudo systemctl stop server_monitor.service 2>/dev/null || true

echo "[2/3] Disabling service..."
sudo systemctl disable server_monitor.service 2>/dev/null || true

echo "[3/3] Removing systemd unit..."
sudo rm -f /etc/systemd/system/server_monitor.service
sudo systemctl daemon-reload

echo "Uninstall complete."
echo "Note: The application files in this directory were NOT deleted."
