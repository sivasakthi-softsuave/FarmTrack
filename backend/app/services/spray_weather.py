"""The weather side of "Can I spray today?" (Home, option B): wind, rain and heat of the next hours, as a traffic light.

DRAFT: the limits are configuration (`SPRAY_*`, see `SprayRules`) and must be approved by an agronomist before real farmers see this
(`SPRAY_WEATHER_ENABLED` is off by default). It says nothing about the medicine, its dose or the waiting period: those come from the
advice and the rules engine. Pure functions, no I/O.

Rules, per part:
  * rain: "stop" if the current hour or one of the next two has at least `rain_mm` of rain, "care" if one of the three after that has,
    else "ok". `dry_hours` = whole hours from now until the first wet hour (None: none in the hours known); `mm_next_3h` = the rain of the
    current hour and the next two.
  * wind (the current hour): "care" from `wind_care_kmh`, "stop" from `wind_stop_kmh`.
  * heat (the current temperature): "care" from `heat_care_c`, "stop" from `heat_stop_c`.
  * a number that is not known counts as "ok" for its part; if none of wind, temperature and rain is known there is no check (None).
  * state = the worst part; headline = the reason of the worst part (rain before wind before heat when they are equally bad).
"""
from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import TYPE_CHECKING, Literal

from app.domain.types import OutlookHour

if TYPE_CHECKING:
    from app.config import Settings

Status = Literal["ok", "care", "stop"]
State = Literal["go", "care", "stop"]
Headline = Literal["calm_dry", "windy", "hot", "rain_soon", "raining"]

_RANK: dict[str, int] = {"ok": 0, "care": 1, "stop": 2}
_STOP_HOURS = 3           # the current hour and the next two: rain there means "not now"
_CARE_HOURS = 6           # hours 3, 4 and 5 from now: rain there means "be careful"


@dataclass(frozen=True)
class SprayRules:
    rain_mm: float = 0.5
    wind_care_kmh: float = 15.0
    wind_stop_kmh: float = 30.0
    heat_care_c: float = 32.0
    heat_stop_c: float = 40.0

    @classmethod
    def from_settings(cls, settings: Settings) -> SprayRules:
        return cls(rain_mm=settings.spray_rain_mm, wind_care_kmh=settings.spray_wind_care_kmh, wind_stop_kmh=settings.spray_wind_stop_kmh,
                   heat_care_c=settings.spray_heat_care_c, heat_stop_c=settings.spray_heat_stop_c)


@dataclass(frozen=True)
class SprayCheck:
    state: State
    headline: Headline
    wind_kmh: float | None
    wind_status: Status
    dry_hours: int | None
    mm_next_3h: float
    rain_status: Status
    temp_c: float | None
    heat_status: Status


def _status(value: float | None, care: float, stop: float) -> Status:
    if value is None:
        return "ok"
    if value >= stop:
        return "stop"
    return "care" if value >= care else "ok"


def assess_spray(hours: Sequence[OutlookHour], rules: SprayRules) -> SprayCheck | None:
    """The check for the next hours (the current hour first), or None when there is nothing to judge from."""
    if not hours:
        return None
    now = hours[0]
    rain_known = any(h.rain_mm is not None for h in hours[:_CARE_HOURS])
    if now.wind_kmh is None and now.temp_c is None and not rain_known:
        return None

    def wet(hour: OutlookHour) -> bool:
        return hour.rain_mm is not None and hour.rain_mm >= rules.rain_mm

    if any(wet(h) for h in hours[:_STOP_HOURS]):
        rain_status: Status = "stop"
    elif any(wet(h) for h in hours[_STOP_HOURS:_CARE_HOURS]):
        rain_status = "care"
    else:
        rain_status = "ok"
    dry_hours = next((i for i, h in enumerate(hours) if wet(h)), None)
    mm_next_3h = round(sum(h.rain_mm or 0.0 for h in hours[:_STOP_HOURS]), 1)
    wind_status = _status(now.wind_kmh, rules.wind_care_kmh, rules.wind_stop_kmh)
    heat_status = _status(now.temp_c, rules.heat_care_c, rules.heat_stop_c)

    parts: list[tuple[Status, Headline]] = [
        (rain_status, "raining" if rain_status == "stop" and wet(now) else "rain_soon"),
        (wind_status, "windy"),
        (heat_status, "hot"),
    ]
    worst = max(parts, key=lambda p: _RANK[p[0]])        # max() keeps the first of equals: rain, then wind, then heat
    state: State = "go" if worst[0] == "ok" else worst[0]
    return SprayCheck(state=state, headline="calm_dry" if state == "go" else worst[1], wind_kmh=now.wind_kmh, wind_status=wind_status,
                      dry_hours=dry_hours, mm_next_3h=mm_next_3h, rain_status=rain_status, temp_c=now.temp_c, heat_status=heat_status)
