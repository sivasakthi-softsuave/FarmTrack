"""The weather side of "Can I spray today?": every limit at its boundary and every headline (the limits are DRAFT, see the module)."""
from datetime import datetime, timedelta

import pytest

from app.clock import IST
from app.config import Settings
from app.domain.types import OutlookHour
from app.services.spray_weather import SprayRules, assess_spray

START = datetime(2026, 10, 29, 9, 0, tzinfo=IST)
RULES = SprayRules()          # 0.5 mm, wind 15 / 30 km/h, heat 32 / 40 C


def hours(count: int = 12, *, rain: dict[int, float | None] | None = None, wind: float | None = 4.0, temp: float | None = 27.0,
          rain_default: float | None = 0.0) -> list[OutlookHour]:
    """`count` hours from START: no rain unless said, the given wind and temperature in the CURRENT hour (the first)."""
    rain = rain or {}
    return [OutlookHour(time=START + timedelta(hours=i), temp_c=temp if i == 0 else 25.0, rain_mm=rain.get(i, rain_default),
                        wind_kmh=wind if i == 0 else 5.0) for i in range(count)]


def test_calm_dry_and_cool_enough_is_go():
    check = assess_spray(hours(), RULES)
    assert (check.state, check.headline) == ("go", "calm_dry")
    assert (check.wind_kmh, check.wind_status) == (4.0, "ok")
    assert (check.dry_hours, check.mm_next_3h, check.rain_status) == (None, 0.0, "ok")
    assert (check.temp_c, check.heat_status) == (27.0, "ok")


@pytest.mark.parametrize("kmh,status", [(0.0, "ok"), (14.9, "ok"), (15.0, "care"), (29.9, "care"), (30.0, "stop"), (80.0, "stop")])
def test_wind_boundaries(kmh, status):
    check = assess_spray(hours(wind=kmh), RULES)
    assert check.wind_status == status and check.wind_kmh == kmh
    assert check.state == ("go" if status == "ok" else status)
    if status != "ok":
        assert check.headline == "windy"


@pytest.mark.parametrize("c,status", [(-5.0, "ok"), (31.9, "ok"), (32.0, "care"), (39.9, "care"), (40.0, "stop"), (45.0, "stop")])
def test_heat_boundaries(c, status):
    check = assess_spray(hours(temp=c), RULES)
    assert check.heat_status == status and check.temp_c == c
    assert check.state == ("go" if status == "ok" else status)
    if status != "ok":
        assert check.headline == "hot"


@pytest.mark.parametrize("hour,status", [(0, "stop"), (1, "stop"), (2, "stop"), (3, "care"), (4, "care"), (5, "care"), (6, "ok"), (11, "ok")])
def test_rain_status_depends_on_how_soon_the_wet_hour_is(hour, status):
    check = assess_spray(hours(rain={hour: 0.5}), RULES)
    assert check.rain_status == status and check.dry_hours == hour, "dry hours = whole hours until the first wet hour"
    assert check.state == ("go" if status == "ok" else status)


def test_a_little_rain_below_the_limit_is_not_wet():
    check = assess_spray(hours(rain={0: 0.4, 1: 0.49, 2: 0.1}), RULES)
    assert (check.rain_status, check.dry_hours, check.state) == ("ok", None, "go")
    assert check.mm_next_3h == 1.0, "but it still counts in the rain of the next 3 hours"


def test_the_rain_of_the_next_3_hours_is_the_sum_of_the_first_three_rounded():
    check = assess_spray(hours(rain={0: 0.26, 1: 1.14, 2: 0.0, 3: 9.0}), RULES)
    assert check.mm_next_3h == 1.4, "the current hour and the next two, one decimal; the fourth hour is not in it"
    assert assess_spray(hours(rain={0: None, 1: 2.0, 2: None}), RULES).mm_next_3h == 2.0, "an unknown hour counts as 0"


def test_the_first_wet_hour_is_found_beyond_the_six_hours_too():
    check = assess_spray(hours(rain={9: 3.0}), RULES)
    assert (check.dry_hours, check.rain_status, check.state) == (9, "ok", "go"), "far rain is told (dry hours) but does not stop the spray"
    assert assess_spray(hours(count=4, rain={}), RULES).dry_hours is None, "no rain within the hours known"


def test_raining_now_is_raining_and_rain_soon_is_rain_soon():
    now = assess_spray(hours(rain={0: 2.0}), RULES)
    assert (now.state, now.headline, now.dry_hours) == ("stop", "raining", 0)
    soon = assess_spray(hours(rain={2: 2.0}), RULES)
    assert (soon.state, soon.headline) == ("stop", "rain_soon")
    later = assess_spray(hours(rain={4: 2.0}), RULES)
    assert (later.state, later.headline) == ("care", "rain_soon"), "rain in hours 3 to 5: be careful, not 'raining'"


@pytest.mark.parametrize("wind,temp,rain,state,headline", [
    (4.0, 27.0, {}, "go", "calm_dry"),
    (35.0, 27.0, {}, "stop", "windy"),
    (4.0, 41.0, {}, "stop", "hot"),
    (16.0, 33.0, {}, "care", "windy"),                       # equally bad: wind before heat
    (16.0, 27.0, {4: 1.0}, "care", "rain_soon"),             # equally bad: rain before wind
    (35.0, 27.0, {4: 1.0}, "stop", "windy"),                 # wind is worse than the rain that is a few hours away
    (16.0, 27.0, {1: 1.0}, "stop", "rain_soon"),             # rain is worse than the wind
    (35.0, 27.0, {0: 1.0}, "stop", "raining"),               # equally bad: rain before wind
    (35.0, 41.0, {}, "stop", "windy"),                       # equally bad: wind before heat
    (4.0, 41.0, {4: 1.0}, "stop", "hot"),
    (16.0, 41.0, {}, "stop", "hot"),
])
def test_the_state_is_the_worst_part_and_the_headline_is_its_reason(wind, temp, rain, state, headline):
    check = assess_spray(hours(wind=wind, temp=temp, rain=rain), RULES)
    assert (check.state, check.headline) == (state, headline)


def test_unknown_numbers_count_as_fine_for_their_part():
    check = assess_spray(hours(wind=None, temp=None), RULES)
    assert (check.state, check.headline, check.wind_kmh, check.temp_c) == ("go", "calm_dry", None, None)
    assert (check.wind_status, check.heat_status) == ("ok", "ok")
    only_temp = assess_spray(hours(wind=None, rain_default=None, temp=41.0), RULES)
    assert only_temp is not None and (only_temp.state, only_temp.headline) == ("stop", "hot")
    assert (only_temp.dry_hours, only_temp.mm_next_3h) == (None, 0.0)


def test_nothing_known_at_all_is_no_check():
    assert assess_spray(hours(wind=None, temp=None, rain_default=None), RULES) is None
    assert assess_spray([], RULES) is None


def test_only_the_first_six_hours_count_as_rain_data():
    unknown = hours(wind=None, temp=None, rain_default=None)
    known_late = [h.model_copy(update={"rain_mm": 1.0 if i == 8 else None}) for i, h in enumerate(unknown)]
    assert assess_spray(known_late, RULES) is None, "rain known only far away is not enough to judge today by"


def test_fewer_hours_than_twelve_are_judged_with_what_there_is():
    check = assess_spray(hours(count=2, rain={1: 1.0}), RULES)
    assert (check.state, check.dry_hours) == ("stop", 1)
    one = assess_spray(hours(count=1), RULES)
    assert one is not None and one.state == "go"


def test_the_limits_are_settings():
    rules = SprayRules.from_settings(Settings(_env_file=None, spray_rain_mm=1.0, spray_wind_care_kmh=10.0, spray_wind_stop_kmh=20.0,
                                              spray_heat_care_c=30.0, spray_heat_stop_c=35.0))
    assert rules == SprayRules(rain_mm=1.0, wind_care_kmh=10.0, wind_stop_kmh=20.0, heat_care_c=30.0, heat_stop_c=35.0)
    assert assess_spray(hours(wind=12.0), rules).state == "care" and assess_spray(hours(wind=12.0), RULES).state == "go"
    assert assess_spray(hours(rain={0: 0.8}), rules).state == "go", "0.8 mm is under this farm's 1.0 mm limit"
    defaults = SprayRules.from_settings(Settings(_env_file=None))
    assert defaults == RULES, "the settings defaults are the draft limits"
    assert Settings(_env_file=None).spray_weather_enabled is False, "off until an agronomist has approved the limits"
