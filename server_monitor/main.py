"""
Lightweight API for VPN server metrics.
Runs on each VPN node and exposes daily average CPU/bandwidth.
"""

from fastapi import FastAPI
from pydantic import BaseModel
import asyncio
from contextlib import asynccontextmanager

from metrics_collector import MetricsCollector

# Global collector instance
collector: MetricsCollector = None


async def periodic_collection():
    """Background task: collect metrics every minute."""
    while True:
        try:
            collector.collect_sample()
        except Exception as e:
            print(f"Error in metrics collection: {e}")
        await asyncio.sleep(60)  # every minute


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Initialize collector and start background task."""
    global collector
    collector = MetricsCollector("metrics.json")

    # Start the background collection task
    task = asyncio.create_task(periodic_collection())

    yield

    # Shutdown
    task.cancel()


app = FastAPI(title="VPN Server Monitor", lifespan=lifespan)


class StatsResponse(BaseModel):
    cpu: float
    bandwidth: float
    unit_cpu: str = "%"
    unit_bandwidth: str = "Mb/s"
    samples_count: int


@app.get("/stats")
async def get_stats() -> StatsResponse:
    """
    Return 24-hour average CPU load and bandwidth usage.
    """
    if collector is None:
        return StatsResponse(cpu=0.0, bandwidth=0.0, samples_count=0)

    avg = collector.get_daily_average()
    return StatsResponse(
        cpu=avg["cpu"],
        bandwidth=avg["bandwidth"],
        samples_count=avg.get("samples_count", 0),
    )


@app.get("/health")
async def health():
    """Health check endpoint."""
    return {"status": "ok", "last_update": collector.last_update if collector else None}
