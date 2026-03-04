# Server Monitor API

Lightweight FastAPI service that runs on each VPN server and exposes daily average
CPU load and bandwidth usage metrics.

## Overview

- **Collects** CPU and bandwidth samples every minute in the background
- **Persists** metrics to disk (`metrics.json`) for durability across restarts
- **Exposes** `/stats` endpoint returning 24-hour rolling averages
- **Minimal** dependencies: FastAPI, psutil, and uvicorn

## Endpoints

### GET `/stats`

Returns daily average metrics:

```json
{
  "cpu": 42.5,
  "bandwidth": 23.7,
  "unit_cpu": "%",
  "unit_bandwidth": "Mb/s",
  "samples_count": 1440
}
```

- `cpu`: average CPU load percentage over last 24 hours
- `bandwidth`: average bandwidth (Mb/s) over last 24 hours
- `samples_count`: number of samples collected (max 1440 = one per minute for 24h)

### GET `/health`

Simple health check:

```json
{
  "status": "ok",
  "last_update": "2026-03-04T15:30:45.123456"
}
```

## Installation

### Quick deploy (recommended)

Clone or copy this directory to your server and run:

```bash
cd /path/to/server_monitor
chmod +x deploy.sh
./deploy.sh
```

The script will:
1. Create a Python virtual environment
2. Install all dependencies  
3. Install and enable the systemd service
4. Start the service automatically

### Manual installation

```bash
cd /path/to/server_monitor
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
sudo cp server_monitor.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable server_monitor.service
sudo systemctl start server_monitor.service
```

### Testing (no systemd)

For quick testing without installing as a service:

```bash
cd /path/to/server_monitor
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --host 0.0.0.0 --port 8001
```

### Uninstall

```bash
chmod +x uninstall.sh
./uninstall.sh
```

## Configuration

No configuration file needed; the service auto-discovers:
- CPU via `psutil.cpu_percent()`
- Bandwidth via `vnstat` (auto-detects network interface)

Metrics are stored in `metrics.json` in the working directory.

## Checking status and logs

After installation:

```bash
# Check if service is running
sudo systemctl status server_monitor.service

# View recent logs
sudo journalctl -u server_monitor.service -n 50

# Follow logs in real-time
sudo journalctl -u server_monitor.service -f

# Check the metrics endpoint directly
curl http://localhost:8001/stats
curl http://localhost:8001/health
```

## Troubleshooting

### Service fails to start

Check the logs:
```bash
journalctl -u server_monitor.service -n 100 --no-pager
```

Common issues:
- **Missing vnstat**: `apt install vnstat`
- **Port 8001 in use**: Change port in `server_monitor.service` and systemd unit
- **Wrong interface**: The service auto-detects; if it picks the wrong one, edit `main.py` to pass `interface="ens3"`

### Bandwidth always 0

Make sure:
1. `vnstat` is installed: `which vnstat`
2. Test manually: `vnstat -i ens3 -tr 5` (replace ens3 with your interface)
3. Check logs for errors: `journalctl -u server_monitor.service -f`

## Dependencies

- `psutil`: CPU metrics
- `vnstat`: bandwidth tracking (must be installed on the host: `apt install vnstat`)
- `fastapi` and `uvicorn`: web framework

## Notes

- The service keeps a rolling buffer of the last 24 hours (1440 samples at 1/min).
- On startup it loads any saved metrics from disk; this allows continuity across restarts.
- Gateway will query this endpoint to pick the least-loaded server.

