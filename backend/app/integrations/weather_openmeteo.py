"""Live weather and forecast from Open-Meteo (forecast API, past_days=14, forecast_days=7, hourly, timezone Asia/Kolkata).

The same forecast call also carries the "current weather" details of the hour (feels like, dew point, sea-level pressure, wind,
visibility, sky, day/night, UV index), the rain chance of every hour (for the next-hours strip) and today's sunrise and sunset. The air quality (US AQI) is a SEPARATE call to Open-Meteo's air-quality API (`air_quality()`), made
only by the field screen, with its own cache; its failure never breaks the weather.

LICENCE: the free api.open-meteo.com endpoints (forecast AND air quality) are for NON-COMMERCIAL use only. A commercial deployment
needs a paid plan: set OPEN_METEO_API_KEY and the adapter switches to customer-api.open-meteo.com and
customer-air-quality-api.open-meteo.com (see docs/design-notes/integrations.md). The air-quality data is CAMS ENSEMBLE data
(Copernicus): Open-Meteo asks for attribution to it and to Open-Meteo wherever it is shown.

`now` must be the real current time: the forecast API only serves about 14 days back and 7 days ahead of the real today.
"""
from __future__ import annotations

import logging
import math
import os
import threading
import time
from collections import deque
from datetime import date, datetime
from pathlib import Path

import httpx

from app.clock import IST
from app.domain.types import WeatherSnapshot
from app.integrations.errors import WeatherUnavailable
from app.integrations.reference import load_stations
from app.integrations.weather_common import HourlySeries, build_snapshot

logger = logging.getLogger(__name__)

FREE_URL = "https://api.open-meteo.com/v1/forecast"
CUSTOMER_URL = "https://customer-api.open-meteo.com/v1/forecast"
AIR_FREE_URL = "https://air-quality-api.open-meteo.com/v1/air-quality"
AIR_CUSTOMER_URL = "https://customer-air-quality-api.open-meteo.com/v1/air-quality"
AIR_TIMEOUT_SECONDS = 3.0        # the air quality only decorates the page: never let it hold the weather up for the 10 s of the forecast call
AIR_FAILURE_TTL_SECONDS = 5 * 60.0   # a failed air-quality call is not repeated for every page view, only every few minutes
MAX_US_AQI = 500
CACHE_TTL_SECONDS = 30 * 60
MAX_CACHED_PLACES = 512          # each entry is 21 days of hourly data (tens of KB): bound the memory
MAX_CALLS_PER_HOUR = 600         # the 12 demo stations need about 24 a hour; the rest is headroom, not an open tap
# The first three are the series the rules work from; the others are the "current weather" details (one hour of each is shown).
_HOURLY = ("temperature_2m,relative_humidity_2m,precipitation,apparent_temperature,dew_point_2m,pressure_msl,wind_speed_10m,visibility,"
           "weather_code,is_day,precipitation_probability,uv_index")
_DAILY = "sunrise,sunset"
_DETAIL_KEYS = ("apparent_temperature", "dew_point_2m", "pressure_msl", "wind_speed_10m", "visibility", "weather_code", "is_day",
                "precipitation_probability", "uv_index")
_INTEGER_DETAILS = {"weather_code", "is_day"}


def _number(value: object) -> float | None:
    """A reading as a float; a gap (null), text or a non-finite number is None, never a guess."""
    if isinstance(value, bool) or not isinstance(value, int | float):
        return None
    return float(value) if math.isfinite(value) else None


class OpenMeteoAdapter:
    def __init__(self, data_dir: Path | None = None, client: httpx.Client | None = None, ttl_seconds: float = CACHE_TTL_SECONDS,
                 monotonic=time.monotonic, api_key: str | None = None) -> None:  # noqa: ANN001
        self._data_dir = Path(data_dir) if data_dir else None
        self._api_key = api_key or None                  # from Settings (env or .env); the OPEN_METEO_API_KEY variable is the fallback
        self._http = client or httpx.Client(timeout=10.0)
        self._ttl = ttl_seconds
        self._monotonic = monotonic
        self._lock = threading.Lock()
        self._cache: dict[tuple[float, float], tuple[float, HourlySeries]] = {}
        self._air_cache: dict[tuple[float, float], tuple[float, int | None]] = {}      # None = the call failed (kept for a few minutes)
        self._calls: deque[float] = deque()              # times of the recent outbound requests (the calls are billed or quota-bound)

    def _take_call_budget(self) -> None:
        """A scan may carry client-chosen coordinates, so the number of distinct places is not under our control: cap the
        outbound requests per hour (the scan then simply runs without weather, like any other weather outage)."""
        now = self._monotonic()
        with self._lock:
            while self._calls and now - self._calls[0] >= 3600.0:
                self._calls.popleft()
            if len(self._calls) >= MAX_CALLS_PER_HOUR:
                raise WeatherUnavailable("Open-Meteo request budget for this hour is used up")
            self._calls.append(now)

    def _remember(self, key: tuple[float, float], series: HourlySeries) -> None:
        now = self._monotonic()
        with self._lock:
            self._cache[key] = (now, series)
            if len(self._cache) > MAX_CACHED_PLACES:     # expired places first, then the oldest: memory stays bounded
                for stale in [k for k, (stamp, _) in self._cache.items() if now - stamp >= self._ttl]:
                    del self._cache[stale]
                while len(self._cache) > MAX_CACHED_PLACES:
                    del self._cache[next(iter(self._cache))]

    def _coordinates(self, station_id: str | None, lat: float | None, lon: float | None) -> tuple[float, float, str | None]:
        if lat is not None and lon is not None:
            return lat, lon, station_id
        if station_id and self._data_dir is not None:
            station = load_stations(self._data_dir).get(station_id)
            if station is not None:
                return station.grid_lat, station.grid_lon, station_id
        raise WeatherUnavailable("Open-Meteo needs coordinates or a known station id")

    def _fetch(self, lat: float, lon: float) -> HourlySeries:
        key = (round(lat, 3), round(lon, 3))
        with self._lock:
            hit = self._cache.get(key)
            if hit and self._monotonic() - hit[0] < self._ttl:
                return hit[1]
        self._take_call_budget()
        api_key = self._api_key or os.environ.get("OPEN_METEO_API_KEY")
        params: dict[str, str | int | float] = {"latitude": lat, "longitude": lon, "hourly": _HOURLY, "daily": _DAILY,
                                                "past_days": 14, "forecast_days": 7, "timezone": "Asia/Kolkata"}
        if api_key:
            params["apikey"] = api_key
        try:
            resp = self._http.get(CUSTOMER_URL if api_key else FREE_URL, params=params)
        except httpx.HTTPError as exc:
            raise WeatherUnavailable(f"Open-Meteo request failed: {type(exc).__name__}") from exc
        if resp.status_code != 200:
            raise WeatherUnavailable(f"Open-Meteo answered HTTP {resp.status_code}")
        series = self._parse(resp)
        self._remember(key, series)
        return series

    @staticmethod
    def _parse(resp: httpx.Response) -> HourlySeries:
        try:
            body = resp.json()
            hourly = body["hourly"]
            stamps, temps, rhs, rains = (hourly["time"], hourly["temperature_2m"], hourly["relative_humidity_2m"],
                                         hourly["precipitation"])
            if not len(stamps) == len(temps) == len(rhs) == len(rains):
                raise ValueError("series lengths differ")
            # The "current weather" details are optional decoration: a missing or oddly sized series is simply absent (None), it
            # never makes the forecast unusable.
            details = [hourly.get(key) for key in _DETAIL_KEYS]
            details = [d if isinstance(d, list) and len(d) == len(stamps) else None for d in details]
            points = []
            for i, (stamp, temp, rh, rain) in enumerate(zip(stamps, temps, rhs, rains, strict=True)):
                if temp is None or rh is None:
                    continue          # a gap is skipped, never guessed
                points.append((datetime.fromisoformat(stamp).replace(tzinfo=IST), float(temp), float(rh), float(rain or 0.0),
                               [None if d is None else _number(d[i]) for d in details]))
        except (KeyError, TypeError, ValueError) as exc:
            raise WeatherUnavailable("Open-Meteo returned an unexpected payload") from exc
        points.sort(key=lambda p: p[0])
        sunrise, sunset = OpenMeteoAdapter._sun_times(body.get("daily"))

        def detail(j: int) -> list | None:
            if details[j] is None:
                return None
            integer = _DETAIL_KEYS[j] in _INTEGER_DETAILS
            column: list = []
            for p in points:
                value = p[4][j]
                column.append(None if value is None else (int(value) if integer else value))
            return column

        return HourlySeries(times=[p[0] for p in points], temp_c=[p[1] for p in points], rh_pct=[p[2] for p in points],
                            rain_mm=[p[3] for p in points], feels_like_c=detail(0), dew_point_c=detail(1), pressure_msl_hpa=detail(2),
                            wind_kmh=detail(3), visibility_m=detail(4), weather_code=detail(5), is_day=detail(6),
                            rain_chance_pct=detail(7), uv_index=detail(8), sunrise_by_day=sunrise, sunset_by_day=sunset)

    @staticmethod
    def _sun_times(daily: object) -> tuple[dict[date, datetime] | None, dict[date, datetime] | None]:
        """Sunrise and sunset per local day (`daily.time`, `daily.sunrise`, `daily.sunset`). Decoration only: anything odd is None, never an
        error (a day without a sunrise, such as a polar night, is simply missing)."""
        if not isinstance(daily, dict):
            return None, None
        days = daily.get("time")
        out: list[dict[date, datetime] | None] = []
        for key in ("sunrise", "sunset"):
            column = daily.get(key)
            if not isinstance(days, list) or not isinstance(column, list) or len(column) != len(days):
                out.append(None)
                continue
            found: dict[date, datetime] = {}
            for day, stamp in zip(days, column, strict=True):
                try:
                    found[date.fromisoformat(day)] = datetime.fromisoformat(stamp).replace(tzinfo=IST)
                except (TypeError, ValueError):
                    continue
            out.append(found or None)
        return out[0], out[1]

    def snapshot(self, station_id: str | None, lat: float | None, lon: float | None, now: datetime) -> WeatherSnapshot:
        latitude, longitude, station = self._coordinates(station_id, lat, lon)
        return build_snapshot(self._fetch(latitude, longitude), station, now, source="openmeteo")

    # ------------------------------------------------------------------ air quality (its own call, its own cache)
    def air_quality(self, station_id: str | None, lat: float | None, lon: float | None) -> int | None:
        """The US air-quality index (0-500) of the place right now, from Open-Meteo's air-quality API (a modelled grid, not a sensor).
        NEVER raises: any failure (no place, request budget used up, timeout, HTTP error, odd payload) is None, because the air quality
        only decorates the weather page. Answers are cached 30 minutes, a failure 5 minutes; the call counts against the same hourly
        request budget as the forecast."""
        try:
            latitude, longitude, _ = self._coordinates(station_id, lat, lon)
        except WeatherUnavailable:
            return None
        key = (round(latitude, 3), round(longitude, 3))
        now = self._monotonic()
        with self._lock:
            hit = self._air_cache.get(key)
            if hit and now - hit[0] < (self._ttl if hit[1] is not None else min(self._ttl, AIR_FAILURE_TTL_SECONDS)):
                return hit[1]
        try:
            self._take_call_budget()
        except WeatherUnavailable:
            logger.info("air quality skipped: the Open-Meteo request budget of this hour is used up")
            return None
        value = self._fetch_air_quality(latitude, longitude)
        self._remember_air(key, value)
        return value

    def _fetch_air_quality(self, lat: float, lon: float) -> int | None:
        api_key = self._api_key or os.environ.get("OPEN_METEO_API_KEY")
        params: dict[str, str | float] = {"latitude": lat, "longitude": lon, "current": "us_aqi", "timezone": "Asia/Kolkata"}
        if api_key:
            params["apikey"] = api_key
        try:
            resp = self._http.get(AIR_CUSTOMER_URL if api_key else AIR_FREE_URL, params=params, timeout=AIR_TIMEOUT_SECONDS)
            if resp.status_code != 200:
                logger.info("air quality unavailable: Open-Meteo answered HTTP %s", resp.status_code)
                return None
            value = _number(resp.json()["current"]["us_aqi"])
        except (httpx.HTTPError, ValueError, KeyError, TypeError) as exc:
            logger.info("air quality unavailable: %s", type(exc).__name__)
            return None
        if value is None or not 0 <= value <= MAX_US_AQI:
            return None
        return round(value)

    def _remember_air(self, key: tuple[float, float], value: int | None) -> None:
        now = self._monotonic()
        with self._lock:
            self._air_cache[key] = (now, value)
            if len(self._air_cache) > MAX_CACHED_PLACES:         # the same bound as the forecast cache (these entries are tiny)
                for stale in [k for k, (stamp, _) in self._air_cache.items() if now - stamp >= self._ttl]:
                    del self._air_cache[stale]
                while len(self._air_cache) > MAX_CACHED_PLACES:
                    del self._air_cache[next(iter(self._air_cache))]
