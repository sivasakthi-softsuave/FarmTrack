"""IOT_PROVIDER=none: no field sensor is installed (or none is known yet).

Nothing is ever reported, so "My field" takes its readings (warmth, air, rain) from the weather and never shows a sensor
reading as old: a quiet sensor is only a quiet sensor when there is one. Soil and leaf wetness exist only with a sensor, so
those tiles are not shown.
"""
from __future__ import annotations

from datetime import datetime

from app.domain.types import SensorReading


class NoSensorAdapter:
    def latest(self, station_id: str, now: datetime) -> SensorReading | None:
        return None

    def is_stale(self, station_id: str, now: datetime, max_age_hours: int = 48) -> bool:
        return False
