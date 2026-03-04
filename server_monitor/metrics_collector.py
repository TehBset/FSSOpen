"""
Collect CPU and bandwidth metrics using psutil and vnstat.
Daily averages are calculated over rolling 24-hour periods.
"""

import psutil
import subprocess
import json
from datetime import datetime, timedelta
from pathlib import Path
from collections import deque
from typing import Dict, Optional


class MetricsCollector:
    # Store up to 1440 samples (one per minute for 24 hours)
    MAX_SAMPLES = 1440

    def __init__(self, stats_file: str = "metrics.json", interface: Optional[str] = None):
        """
        :param stats_file: path where metrics are persisted
        :param interface: name of network interface to query with vnstat.  If
                          not provided the constructor will attempt to choose a
                          reasonable default (first non-loopback, up interface).
        """
        self.stats_file = Path(stats_file)
        self.interface = interface or self._guess_interface()
        self.cpu_samples = deque(maxlen=self.MAX_SAMPLES)
        self.bandwidth_samples = deque(maxlen=self.MAX_SAMPLES)
        self.last_update = None
        self.load_from_file()

    def _guess_interface(self) -> str:
        """Try to pick a reasonable network interface automatically."""
        try:
            import psutil
            stats = psutil.net_if_stats()
            for name, st in stats.items():
                if not st.isup:
                    continue
                # skip loopback and docker/virtual
                if name.startswith("lo") or name.startswith("docker") or name.startswith("vir"):
                    continue
                return name
        except Exception:
            pass
        # fallback to common default
        return "eth0"

    def load_from_file(self):
        """Load previously saved metrics from disk."""
        if self.stats_file.exists():
            try:
                with open(self.stats_file, "r") as f:
                    data = json.load(f)
                    # Restore last 24 hours of data
                    cutoff = datetime.utcnow() - timedelta(hours=24)
                    for item in data.get("samples", []):
                        ts = datetime.fromisoformat(item["timestamp"])
                        if ts > cutoff:
                            self.cpu_samples.append(item["cpu"])
                            self.bandwidth_samples.append(item["bandwidth"])
            except Exception as e:
                print(f"Error loading metrics file: {e}")

    def save_to_file(self):
        """Store metrics to disk for persistence."""
        try:
            data = {
                "last_updated": datetime.utcnow().isoformat(),
                "samples": [
                    {
                        "timestamp": (datetime.utcnow() - timedelta(minutes=i)).isoformat(),
                        "cpu": cpu,
                        "bandwidth": bw,
                    }
                    for i, (cpu, bw) in enumerate(zip(self.cpu_samples, self.bandwidth_samples))
                ],
            }
            with open(self.stats_file, "w") as f:
                json.dump(data, f)
        except Exception as e:
            print(f"Error saving metrics file: {e}")

    def get_cpu_percent(self) -> float:
        """Get current CPU usage percentage (1-minute average)."""
        try:
            return psutil.cpu_percent(interval=1)
        except Exception as e:
            print(f"Error reading CPU: {e}")
            return 0.0

    def get_bandwidth_mbps(self) -> float:
        """
        Get current bandwidth usage in Mb/s using vnstat.
        Returns the total (rx + tx) bandwidth.
        """
        try:
            iface = self.interface or "eth0"
            result = subprocess.run(
                ["vnstat", "-i", iface, "-tr", "5"],
                capture_output=True,
                text=True,
                timeout=10,
            )
            if result.returncode != 0:
                print(f"vnstat error (returncode {result.returncode}): {result.stderr}")
                return 0.0

            rx_mbps = 0.0
            tx_mbps = 0.0

            # Parse lines like:
            #   rx        15.08 Mbit/s          2532 packets/s
            #   tx        14.86 Mbit/s          1189 packets/s
            for line in result.stdout.split("\n"):
                line = line.strip()
                if not line or "Mbit/s" not in line:
                    continue

                parts = line.split()
                # First part is direction (rx or tx)
                if not parts:
                    continue
                direction = parts[0].lower()

                # Find the number before "Mbit/s"
                for i, part in enumerate(parts):
                    if "mbit/s" in part.lower():
                        if i > 0:
                            try:
                                value = float(parts[i - 1])
                                if direction == "rx":
                                    rx_mbps = value
                                elif direction == "tx":
                                    tx_mbps = value
                            except ValueError:
                                pass
                        break

            # Return total bandwidth (rx + tx)
            total = rx_mbps + tx_mbps
            return round(total, 2)

        except Exception as e:
            print(f"Error reading vnstat bandwidth: {e}")
            return 0.0

    def collect_sample(self):
        """Collect one CPU and bandwidth sample."""
        cpu = self.get_cpu_percent()
        bandwidth = self.get_bandwidth_mbps()
        self.cpu_samples.append(cpu)
        self.bandwidth_samples.append(bandwidth)
        self.last_update = datetime.utcnow()
        self.save_to_file()

    def get_daily_average(self) -> Dict[str, float]:
        """Return the daily (24-hour) average of CPU and bandwidth."""
        if not self.cpu_samples or not self.bandwidth_samples:
            return {"cpu": 0.0, "bandwidth": 0.0}

        cpu_avg = sum(self.cpu_samples) / len(self.cpu_samples)
        bandwidth_avg = sum(self.bandwidth_samples) / len(self.bandwidth_samples)

        return {
            "cpu": round(cpu_avg, 2),
            "bandwidth": round(bandwidth_avg, 2),
            "samples_count": len(self.cpu_samples),
        }
