"""The next hours (`hours`), the sun and UV details of `conditions`, and the spray check (`spray`) of GET /v1/field and GET /v1/weather.

Hours and times are UTC with a trailing Z (the phone shows them on its own clock). The spray check is DRAFT and OFF by default."""
from datetime import datetime, timedelta

import pytest

from app.clock import IST
from app.domain.types import OutlookHour
from app.integrations.errors import WeatherUnavailable
from tests.fakes import NOW, FakeAirQualityWeather, FakeWeather

START = datetime(2026, 10, 29, 9, 0, tzinfo=IST)           # 03:30 UTC


def outlook(count: int = 12, **now_values) -> list[OutlookHour]:
    """`count` calm, dry hours from START; `now_values` change the first (current) hour."""
    hours = [OutlookHour(time=START + timedelta(hours=i), temp_c=27.0 - i * 0.5, sky="partly_cloudy", is_day=i < 9, rain_chance_pct=10 * i,
                         rain_mm=0.0, wind_kmh=4.0) for i in range(count)]
    if hours:
        hours[0] = hours[0].model_copy(update=now_values)
    return hours


def source(hours: list[OutlookHour] | None = None, **details) -> FakeAirQualityWeather:
    weather = FakeAirQualityWeather()
    weather.snapshot_value = weather.snapshot_value.model_copy(update={
        "sky": "partly_cloudy", "uv_index": 7.5, "sunrise": datetime(2026, 10, 29, 6, 1, tzinfo=IST),
        "sunset": datetime(2026, 10, 29, 17, 48, tzinfo=IST), "outlook": outlook() if hours is None else hours, **details})
    return weather


@pytest.fixture
def on(fake_container):
    """Place weather on, both sources with hours, spray switched ON."""
    fake_container.settings.place_weather_provider = "openmeteo"
    fake_container.settings.spray_weather_enabled = True
    fake_container.weather = source()
    fake_container.place_weather = source()
    return fake_container


GO = {"state": "go", "headline": "calm_dry", "wind": {"kmh": 4.0, "status": "ok"},
      "rain": {"dry_hours": None, "mm_next_3h": 0.0, "status": "ok"}, "heat": {"temp_c": 27.0, "status": "ok"}}


# ------------------------------------------------------------------------------------------------ hours
@pytest.mark.parametrize("url", ["/v1/field", "/v1/weather?lat=31.1&lon=77.3"])
def test_the_hours_are_the_next_hours_in_utc_the_current_one_first(api_client, auth, on, url):
    hours = api_client.get(url, headers=auth).json()["hours"]
    assert len(hours) == 12
    assert hours[0] == {"time": "2026-10-29T03:30:00Z", "temp_c": 27.0, "sky": "partly_cloudy", "is_day": True, "rain_chance_pct": 0,
                        "rain_mm": 0.0, "wind_kmh": 4.0}, "09:00 IST is 03:30 UTC"
    assert hours[1]["time"] == "2026-10-29T04:30:00Z" and hours[11]["time"] == "2026-10-29T14:30:00Z"
    assert hours[8]["is_day"] is True and hours[9]["is_day"] is False
    assert set(hours[0]) == {"time", "temp_c", "sky", "is_day", "rain_chance_pct", "rain_mm", "wind_kmh"}


def test_an_hour_with_unknown_numbers_has_nulls(api_client, auth, on):
    on.weather = source([OutlookHour(time=START)])
    assert api_client.get("/v1/field", headers=auth).json()["hours"] == [
        {"time": "2026-10-29T03:30:00Z", "temp_c": None, "sky": None, "is_day": None, "rain_chance_pct": None, "rain_mm": None,
         "wind_kmh": None}]


def test_fewer_hours_than_twelve_are_sent_as_they_are(api_client, auth, on):
    on.weather = source(outlook(5))
    assert len(api_client.get("/v1/field", headers=auth).json()["hours"]) == 5


# ------------------------------------------------------------------------------------------------ uv, sunrise and sunset
@pytest.mark.parametrize("url", ["/v1/field", "/v1/weather?lat=31.1&lon=77.3"])
def test_uv_sunrise_and_sunset_are_in_the_conditions(api_client, auth, on, url):
    conditions = api_client.get(url, headers=auth).json()["conditions"]
    assert conditions["uv_index"] == 7.5
    assert conditions["sunrise"] == "2026-10-29T00:31:00Z" and conditions["sunset"] == "2026-10-29T12:18:00Z", "06:01 and 17:48 IST in UTC"
    assert conditions["sky"] == "partly_cloudy", "the earlier details are unchanged"


def test_only_the_sun_known_is_still_a_conditions_object(api_client, auth, on):
    on.weather = source(sky=None, uv_index=None, sunset=None)
    conditions = api_client.get("/v1/field", headers=auth).json()["conditions"]
    assert conditions["sunrise"] == "2026-10-29T00:31:00Z" and conditions["sunset"] is None and conditions["uv_index"] is None


# ------------------------------------------------------------------------------------------------ spray
def test_spray_is_null_by_default_even_with_hours(api_client, auth, fake_container):
    fake_container.weather = source()
    assert fake_container.settings.spray_weather_enabled is False
    body = api_client.get("/v1/field", headers=auth).json()
    assert "spray" in body and body["spray"] is None
    assert len(body["hours"]) == 12, "the hours do not depend on the spray switch"


@pytest.mark.parametrize("url", ["/v1/field", "/v1/weather?lat=31.1&lon=77.3"])
def test_spray_go_for_a_calm_dry_day(api_client, auth, on, url):
    assert api_client.get(url, headers=auth).json()["spray"] == GO


def test_spray_says_rain_soon_with_the_dry_hours(api_client, auth, on):
    hours = outlook()
    hours[2] = hours[2].model_copy(update={"rain_mm": 3.0})
    on.weather = source(hours)
    spray = api_client.get("/v1/field", headers=auth).json()["spray"]
    assert spray["state"] == "stop" and spray["headline"] == "rain_soon"
    assert spray["rain"] == {"dry_hours": 2, "mm_next_3h": 3.0, "status": "stop"}
    assert spray["wind"]["status"] == "ok" and spray["heat"]["status"] == "ok"


def test_spray_says_windy_and_hot(api_client, auth, on):
    on.weather = source(outlook(wind_kmh=18.0))
    spray = api_client.get("/v1/field", headers=auth).json()["spray"]
    assert (spray["state"], spray["headline"], spray["wind"]) == ("care", "windy", {"kmh": 18.0, "status": "care"})
    on.weather = source(outlook(temp_c=41.0))
    spray = api_client.get("/v1/field", headers=auth).json()["spray"]
    assert (spray["state"], spray["headline"], spray["heat"]) == ("stop", "hot", {"temp_c": 41.0, "status": "stop"})


def test_the_limits_come_from_the_settings(api_client, auth, on):
    on.settings.spray_wind_care_kmh = 3.0
    spray = api_client.get("/v1/field", headers=auth).json()["spray"]
    assert (spray["state"], spray["headline"]) == ("care", "windy"), "4 km/h is above this farm's 3 km/h limit"


def test_spray_is_null_when_there_is_nothing_to_judge_from(api_client, auth, on):
    on.weather = source([OutlookHour(time=START)])         # a current hour with no wind, no temperature and no rain figure
    body = api_client.get("/v1/field", headers=auth).json()
    assert body["spray"] is None and len(body["hours"]) == 1


def test_spray_is_null_without_hours(api_client, auth, on):
    on.weather = source([])
    body = api_client.get("/v1/field", headers=auth).json()
    assert body["spray"] is None and body["hours"] == []


# ------------------------------------------------------------------------------------------------ sources without any of it
def test_the_csv_archive_has_no_hours_no_spray_and_no_conditions(api_client, auth, fake_container):
    fake_container.settings.spray_weather_enabled = True
    assert isinstance(fake_container.weather, FakeWeather) and fake_container.weather.snapshot_value.outlook == []
    body = api_client.get("/v1/field", headers=auth).json()
    assert body["hours"] == [] and body["spray"] is None and body["conditions"] is None
    assert body["readings"] is not None, "the rest of the page is unaffected"


def test_weather_switched_off_has_no_hours_and_no_spray(api_client, auth, on):
    on.settings.weather_enabled = False
    body = api_client.get("/v1/field", headers=auth).json()
    assert body["hours"] == [] and body["spray"] is None
    assert on.weather.calls == []


def test_weather_that_cannot_be_read_has_no_hours_and_no_spray(api_client, auth, on):
    on.weather.raises = WeatherUnavailable("down")
    response = api_client.get("/v1/field", headers=auth)
    assert response.status_code == 200 and response.json()["hours"] == [] and response.json()["spray"] is None


def test_a_chosen_place_uses_its_own_source_for_the_hours(api_client, auth, on):
    on.place_weather = source(outlook(3, wind_kmh=20.0))
    body = api_client.get("/v1/weather?lat=31.1&lon=77.3", headers=auth).json()
    assert len(body["hours"]) == 3 and body["spray"]["headline"] == "windy"
    assert len(api_client.get("/v1/field", headers=auth).json()["hours"]) == 12, "the own-field source is not touched"


def test_the_spoken_summary_does_not_change_with_the_hours(api_client, auth, on, fake_container):
    spoken = api_client.get("/v1/field", headers=auth).json()["spoken"]["text"]
    fake_container.weather = FakeWeather()
    assert api_client.get("/v1/field", headers=auth).json()["spoken"]["text"] == spoken


def test_the_demo_clock_does_not_shift_or_cut_the_hours(api_client, auth, on):
    """The hours are whatever the weather source sent: the clock of the fakes (NOW) does not change them."""
    assert NOW != START
    assert api_client.get("/v1/field", headers=auth).json()["hours"][0]["time"] == "2026-10-29T03:30:00Z"
