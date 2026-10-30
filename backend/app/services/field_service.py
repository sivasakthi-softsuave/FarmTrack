"""'My field': latest sensor readings (with a stale flag), 7-day forecast, weather risks and a spoken summary."""
from __future__ import annotations

import logging
from datetime import UTC, datetime

from sqlalchemy.orm import Session

from app.api.schemas import (
    ConditionsOut,
    FieldOut,
    ForecastDayOut,
    HourOut,
    ReadingsOut,
    RiskOut,
    SpokenOut,
    SprayHeatOut,
    SprayOut,
    SprayRainOut,
    SprayWindOut,
)
from app.domain.types import FarmerProfile, LocalizedText, RiskItem, SensorReading, Severity, WeatherSnapshot
from app.interfaces import AirQualityAdapter, WeatherAdapter
from app.services import texts
from app.services.container import Container
from app.services.history import merged_history
from app.services.presenters import ist
from app.services.prompts import PromptBook
from app.services.speech import speak
from app.services.spray_weather import SprayRules, assess_spray

logger = logging.getLogger(__name__)

HEAVY_RAIN_MM = 10.0        # matches rules_config rain.heavy_rain_mm_default; wording only, the rules decide risks
NO_RAIN_MM = 1.0
_LEVEL_ORDER = {Severity.red: 0, Severity.yellow: 1, Severity.green: 2}


class FieldService:
    def __init__(self, container: Container, db: Session) -> None:
        self.c = container
        self.db = db

    def get(self, farmer: FarmerProfile) -> FieldOut:
        now = self.c.clock.now()
        weather = self._weather(farmer, now) if self.c.settings.weather_enabled else None
        weather_on = self.c.settings.weather_enabled
        reading, sensor_stale = self._sensor(farmer, now)
        stale = sensor_stale or (weather_on and (weather is None or weather.stale))
        risks = self._risks(farmer, weather, now) if weather else []
        readings = self._readings(reading, weather)
        as_of = reading.time if reading else (weather.as_of if weather else now)
        return FieldOut(
            station_id=farmer.station_id, village=farmer.village, as_of=ist(as_of), stale=stale, readings=readings,
            conditions=self._conditions(self.c.weather, weather, farmer.station_id, farmer.lat, farmer.lon),
            hours=self._hours(weather), spray=self._spray(weather),
            forecast=[ForecastDayOut(day=d.day, tmin_c=d.tmin_c, tmax_c=d.tmax_c, rain_mm=d.rain_mm)
                      for d in (weather.daily_forecast[:7] if weather else [])],
            risks=[RiskOut(id=r.id, level=r.level, title=r.title, text=r.text) for r in risks],
            spoken=self._spoken(readings, weather, risks, stale, weather_on))

    def at_place(self, lat: float, lon: float, now: datetime) -> FieldOut:
        """Live weather for a place the farmer picked on the map: the same shape as `get`, but there is no sensor and no risk list
        (risks belong to the farmer's own field and spray diary), so the spoken summary says nothing about risks.
        `now` must be the REAL time (the forecast API only serves about 14 days back and 7 ahead of the real today).
        Raises WeatherUnavailable when no weather can be produced: the route answers 503."""
        assert self.c.place_weather is not None  # noqa: S101  the route checks this first
        lat, lon = round(lat, 2), round(lon, 2)          # about 1 km: finer than the weather grid, and a better cache hit rate
        weather = self.c.place_weather.snapshot(None, lat, lon, now)
        readings = self._readings(None, weather)
        return FieldOut(
            station_id=None, village=None, as_of=ist(weather.as_of), stale=weather.stale, readings=readings,
            conditions=self._conditions(self.c.place_weather, weather, None, lat, lon),
            hours=self._hours(weather), spray=self._spray(weather),
            forecast=[ForecastDayOut(day=d.day, tmin_c=d.tmin_c, tmax_c=d.tmax_c, rain_mm=d.rain_mm) for d in weather.daily_forecast[:7]],
            risks=[], spoken=self._spoken(readings, weather, [], weather.stale, weather_on=True, for_place=True))

    # ------------------------------------------------------------------ data (each source may fail on its own)
    def _weather(self, farmer: FarmerProfile, now: datetime) -> WeatherSnapshot | None:
        try:
            return self.c.weather.snapshot(farmer.station_id, farmer.lat, farmer.lon, now)
        except Exception:
            logger.exception("weather unavailable farmer=%s", farmer.id)
            return None

    def _sensor(self, farmer: FarmerProfile, now: datetime) -> tuple[SensorReading | None, bool]:
        if not farmer.station_id:
            return None, False
        try:
            return self.c.iot.latest(farmer.station_id, now), bool(self.c.iot.is_stale(farmer.station_id, now))
        except Exception:
            logger.exception("sensor data unavailable farmer=%s", farmer.id)
            return None, True

    def _risks(self, farmer: FarmerProfile, weather: WeatherSnapshot, now: datetime) -> list[RiskItem]:
        history, _ = merged_history(self.c, self.db, farmer, now)
        try:
            return list(self.c.rules.evaluate_risks(farmer, weather, now, history))
        except Exception:
            logger.exception("risk evaluation failed farmer=%s", farmer.id)
            return []

    @staticmethod
    def _readings(reading: SensorReading | None, weather: WeatherSnapshot | None) -> ReadingsOut | None:
        if reading is not None:
            return ReadingsOut(temp_c=reading.temp_c, rh_pct=reading.rh_pct,
                               rain_24h_mm=weather.rain_last_24h_mm if weather else reading.rain_mm,
                               leaf_wetness_min=reading.leaf_wetness_min, soil_moisture_pct=reading.soil_moisture_pct)
        if weather is not None and (weather.temp_c is not None or weather.rh_pct is not None):
            return ReadingsOut(temp_c=weather.temp_c, rh_pct=weather.rh_pct, rain_24h_mm=weather.rain_last_24h_mm)
        return None

    @staticmethod
    def _conditions(adapter: WeatherAdapter | None, weather: WeatherSnapshot | None, station_id: str | None, lat: float | None,
                    lon: float | None) -> ConditionsOut | None:
        """The "current weather" details of the snapshot plus the air quality, which a weather source that has it gives in a second call
        (and which never raises). None when the source knows none of it (the CSV demo archive): the app then shows no such card."""
        if weather is None:
            return None
        aqi = adapter.air_quality(station_id, lat, lon) if isinstance(adapter, AirQualityAdapter) else None
        conditions = ConditionsOut(
            sky=weather.sky, is_day=weather.is_day, feels_like_c=weather.feels_like_c, wind_kmh=weather.wind_kmh,
            visibility_km=weather.visibility_km, pressure_hpa=weather.pressure_hpa, dew_point_c=weather.dew_point_c, aqi=aqi,
            uv_index=weather.uv_index, sunrise=_utc(weather.sunrise), sunset=_utc(weather.sunset))
        return conditions if conditions.model_dump(exclude_none=True) else None

    @staticmethod
    def _hours(weather: WeatherSnapshot | None) -> list[HourOut]:
        """The next hours (the current one first) in UTC; empty when the weather source has no hourly details."""
        if weather is None:
            return []
        return [HourOut(time=_utc(h.time), temp_c=h.temp_c, sky=h.sky, is_day=h.is_day, rain_chance_pct=h.rain_chance_pct,
                        rain_mm=h.rain_mm, wind_kmh=h.wind_kmh) for h in weather.outlook]

    def _spray(self, weather: WeatherSnapshot | None) -> SprayOut | None:
        """"Can I spray today?": only when SPRAY_WEATHER_ENABLED (draft limits, see app/services/spray_weather.py) and there are hours to judge."""
        if weather is None or not self.c.settings.spray_weather_enabled:
            return None
        check = assess_spray(weather.outlook, SprayRules.from_settings(self.c.settings))
        if check is None:
            return None
        return SprayOut(state=check.state, headline=check.headline, wind=SprayWindOut(kmh=check.wind_kmh, status=check.wind_status),
                        rain=SprayRainOut(dry_hours=check.dry_hours, mm_next_3h=check.mm_next_3h, status=check.rain_status),
                        heat=SprayHeatOut(temp_c=check.temp_c, status=check.heat_status))

    # ------------------------------------------------------------------ speech
    def _spoken(self, readings: ReadingsOut | None, weather: WeatherSnapshot | None, risks: list[RiskItem],
                stale: bool, weather_on: bool = True, for_place: bool = False) -> SpokenOut:
        book = PromptBook(self.c.settings.voice_dir)
        parts: list[LocalizedText] = []
        if stale:
            parts.append(book.get("field_stale", texts.FIELD_STALE_FALLBACK))
        if readings is None and weather is None:   # (also true when weather is off and there is no sensor)
            parts.append(book.get("field_no_data", texts.FIELD_NO_DATA_FALLBACK))
            return speak(self.c.audio, book.join(*parts))
        if readings is not None and readings.temp_c is not None:
            words = texts.PLACE_TEMPERATURE if for_place else texts.FIELD_TEMPERATURE      # a picked place is "there", not "your field"
            parts.append(words[_temperature_band(readings.temp_c)])
        if weather is not None:
            parts.append(texts.FIELD_RAIN[_rain_band(weather.rain_next_48h_mm)])
        if not weather_on or for_place:                # no weather, or a picked place (its risks are not worked out): say nothing about risks
            return speak(self.c.audio, book.join(*parts))
        notable = sorted((r for r in risks if r.level != Severity.green), key=lambda r: _LEVEL_ORDER[r.level])[:2]
        if notable:
            parts.append(texts.FIELD_RISK_LEAD)
            parts.extend(r.text for r in notable)
        else:
            parts.append(texts.FIELD_NO_RISK)
        return speak(self.c.audio, book.join(*parts))


def _utc(value: datetime | None) -> datetime | None:
    """A moment in UTC (the app shows it on the phone's own clock)."""
    return None if value is None else value.astimezone(UTC)


def _temperature_band(temp_c: float) -> str:
    if temp_c < 5:
        return "cold"
    if temp_c < 15:
        return "cool"
    if temp_c < 25:
        return "mild"
    if temp_c < 32:
        return "warm"
    return "hot"


def _rain_band(rain_mm: float) -> str:
    if rain_mm < NO_RAIN_MM:
        return "none"
    return "heavy" if rain_mm >= HEAVY_RAIN_MM else "light"
