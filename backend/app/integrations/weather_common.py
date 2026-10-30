"""Builds a WeatherSnapshot from an hourly series. Shared by the CSV archive adapter and the Open-Meteo adapter.

Conventions (match data/demo_scenarios.json facts, which are computed the same way):
  * `now` is floored to the hour; a row stamped T describes the instant T.
  * hourly_past   = rows with time <= now, the last 14 days, oldest first (includes the current hour).
  * hourly_future = rows with time > now, up to 48 h.
  * rain_last_24h = rain in [now-24h, now); rain_next_12h / rain_next_48h = rain in [now, now+N h).
  * leaf_wet is the proxy from rules_config.json: rain >= 0.1 mm or RH >= 90 %.
  * daily_forecast = today and the next 6 days (7 days) from the series, partial days at the end of the data are kept.
  * the optional "current weather" series (feels like, dew point, pressure, wind, visibility, sky, day/night, UV) are read at the same hour
    as the temperature; a missing value stays None.
  * outlook = the next 12 hours (the current hour first) with sky, rain chance, rain and wind, for a source that has such details (the CSV
    archive has none: its outlook is empty); sunrise and sunset are today's.
"""
from __future__ import annotations

from bisect import bisect_left, bisect_right
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from app.clock import IST
from app.domain.types import ForecastDay, OutlookHour, WeatherHour, WeatherSnapshot
from app.integrations.errors import WeatherUnavailable

PAST_DAYS = 14
FUTURE_HOURS = 48
FORECAST_DAYS = 7
OUTLOOK_HOURS = 12
STALE_AFTER = timedelta(hours=6)
WET_RAIN_MM = 0.1
WET_RH_PCT = 90.0


@dataclass(frozen=True)
class HourlySeries:
    """Parallel arrays, sorted by time (timezone-aware IST). The optional arrays (None = the source has none) are as long as `times`
    and hold None where the source had a gap."""
    times: list[datetime]
    temp_c: list[float]
    rh_pct: list[float]
    rain_mm: list[float]
    feels_like_c: list[float | None] | None = None
    dew_point_c: list[float | None] | None = None
    pressure_msl_hpa: list[float | None] | None = None
    wind_kmh: list[float | None] | None = None
    visibility_m: list[float | None] | None = None
    weather_code: list[int | None] | None = None
    is_day: list[int | None] | None = None
    rain_chance_pct: list[float | None] | None = None
    uv_index: list[float | None] | None = None
    sunrise_by_day: dict[date, datetime] | None = None       # the local day -> the moment (timezone-aware)
    sunset_by_day: dict[date, datetime] | None = None


# WMO weather interpretation codes (Open-Meteo's `weather_code`) -> the words the app knows.
_SKY_BY_WMO_CODE: dict[int, str] = {
    0: "clear", 1: "mostly_clear", 2: "partly_cloudy", 3: "cloudy",
    45: "fog", 48: "fog",
    51: "drizzle", 53: "drizzle", 55: "drizzle", 56: "drizzle", 57: "drizzle",
    61: "rain", 63: "rain", 66: "rain", 65: "heavy_rain", 67: "heavy_rain",
    80: "showers", 81: "showers", 82: "heavy_rain",
    71: "snow", 73: "snow", 75: "snow", 77: "snow", 85: "snow", 86: "snow",
    95: "thunderstorm", 96: "thunderstorm", 97: "thunderstorm", 99: "thunderstorm",
}


def sky_from_wmo(code: int | float | None) -> str | None:
    """The sky word of a WMO weather code; None for no code or a code this table does not know (never a guess)."""
    if code is None:
        return None
    try:
        return _SKY_BY_WMO_CODE.get(int(code))
    except (TypeError, ValueError):
        return None


def _at(values: list | None, i: int):  # noqa: ANN202
    return values[i] if values is not None and i < len(values) else None


def _rounded(value: float | None, digits: int = 1) -> float | None:
    return None if value is None else round(float(value), digits)


def _percent(value: float | None) -> int | None:
    return None if value is None else max(0, min(100, round(value)))


def floor_hour(value: datetime) -> datetime:
    value = value.replace(tzinfo=IST) if value.tzinfo is None else value.astimezone(IST)
    return value.replace(minute=0, second=0, microsecond=0)


def _hour(series: HourlySeries, i: int) -> WeatherHour:
    rain, rh = series.rain_mm[i], series.rh_pct[i]
    return WeatherHour(time=series.times[i], temp_c=series.temp_c[i], rh_pct=rh, rain_mm=rain,
                       leaf_wet=rain >= WET_RAIN_MM or rh >= WET_RH_PCT)


def _rain_between(series: HourlySeries, start: datetime, end: datetime) -> float:
    """Rain in [start, end)."""
    lo, hi = bisect_left(series.times, start), bisect_left(series.times, end)
    return round(sum(series.rain_mm[lo:hi]), 1)


def _daily(series: HourlySeries, first_day: date) -> list[ForecastDay]:
    days: list[ForecastDay] = []
    for offset in range(FORECAST_DAYS):
        day = first_day + timedelta(days=offset)
        start = datetime(day.year, day.month, day.day, tzinfo=IST)
        lo, hi = bisect_left(series.times, start), bisect_left(series.times, start + timedelta(days=1))
        if hi > lo:
            temps = series.temp_c[lo:hi]
            days.append(ForecastDay(day=day, tmin_c=min(temps), tmax_c=max(temps), rain_mm=round(sum(series.rain_mm[lo:hi]), 1)))
    return days


def _outlook(series: HourlySeries, now_h: datetime) -> list[OutlookHour]:
    """The next hours from the current one. A source without any of the hourly details (the CSV demo archive) has no outlook."""
    if all(column is None for column in (series.weather_code, series.is_day, series.wind_kmh, series.rain_chance_pct)):
        return []
    lo = bisect_left(series.times, now_h)
    hi = bisect_left(series.times, now_h + timedelta(hours=OUTLOOK_HOURS))
    hours = []
    for i in range(lo, hi):
        is_day = _at(series.is_day, i)
        hours.append(OutlookHour(
            time=series.times[i], temp_c=_rounded(series.temp_c[i]), sky=sky_from_wmo(_at(series.weather_code, i)),
            is_day=None if is_day is None else bool(is_day), rain_chance_pct=_percent(_at(series.rain_chance_pct, i)),
            rain_mm=_rounded(series.rain_mm[i]), wind_kmh=_rounded(_at(series.wind_kmh, i))))
    return hours


def build_snapshot(series: HourlySeries, station_id: str | None, now: datetime, source: str) -> WeatherSnapshot:
    now_h = floor_hour(now)
    end = bisect_right(series.times, now_h)
    if end == 0:
        raise WeatherUnavailable(f"no weather data at or before {now_h.isoformat()}")
    start = bisect_right(series.times, now_h - timedelta(days=PAST_DAYS))
    future_end = bisect_right(series.times, now_h + timedelta(hours=FUTURE_HOURS))
    current = end - 1
    return WeatherSnapshot(
        station_id=station_id,
        as_of=now if now.tzinfo else now.replace(tzinfo=IST),
        temp_c=series.temp_c[current],
        rh_pct=series.rh_pct[current],
        rain_last_24h_mm=_rain_between(series, now_h - timedelta(hours=24), now_h),
        rain_next_12h_mm=_rain_between(series, now_h, now_h + timedelta(hours=12)),
        rain_next_48h_mm=_rain_between(series, now_h, now_h + timedelta(hours=48)),
        hourly_past=[_hour(series, i) for i in range(start, end)],
        hourly_future=[_hour(series, i) for i in range(end, future_end)],
        daily_forecast=_daily(series, now_h.date()),
        stale=now_h - series.times[current] > STALE_AFTER,
        source=source,
        sky=sky_from_wmo(_at(series.weather_code, current)),
        is_day=None if _at(series.is_day, current) is None else bool(_at(series.is_day, current)),
        feels_like_c=_rounded(_at(series.feels_like_c, current)),
        dew_point_c=_rounded(_at(series.dew_point_c, current)),
        pressure_hpa=_rounded(_at(series.pressure_msl_hpa, current)),
        wind_kmh=_rounded(_at(series.wind_kmh, current)),
        visibility_km=_rounded(None if _at(series.visibility_m, current) is None else _at(series.visibility_m, current) / 1000.0),
        uv_index=_rounded(_at(series.uv_index, current)),
        sunrise=(series.sunrise_by_day or {}).get(now_h.date()),
        sunset=(series.sunset_by_day or {}).get(now_h.date()),
        outlook=_outlook(series, now_h),
    )
