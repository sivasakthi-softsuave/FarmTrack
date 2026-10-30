"""The "current weather" details (`conditions`) of GET /v1/field and GET /v1/weather: sky, feels like, wind, visibility, pressure, dew point,
the air quality, UV index, sunrise and sunset. They come from the weather source; a source that knows none of it (the CSV demo archive) gives
`null`. (The hours and the spray check have their own tests: test_hours_spray_api.py.)"""
import pytest

from app.integrations.errors import WeatherUnavailable
from tests.fakes import FakeAirQualityWeather, FakeWeather

DETAILS = dict(sky="partly_cloudy", is_day=True, feels_like_c=12.3, dew_point_c=7.5, pressure_hpa=1008.3, wind_kmh=8.4, visibility_km=4.2)
CONDITIONS = {"sky": "partly_cloudy", "is_day": True, "feels_like_c": 12.3, "wind_kmh": 8.4, "visibility_km": 4.2, "pressure_hpa": 1008.3,
              "dew_point_c": 7.5, "aqi": 55, "uv_index": None, "sunrise": None, "sunset": None}


@pytest.fixture
def on(fake_container):
    """Place weather switched on, both weather sources able to give details and the air quality."""
    fake_container.settings.place_weather_provider = "openmeteo"
    for name in ("weather", "place_weather"):
        source = FakeAirQualityWeather()
        source.snapshot_value = source.snapshot_value.model_copy(update=DETAILS)
        setattr(fake_container, name, source)
    return fake_container


# ------------------------------------------------------------------------------------------------ /v1/field
def test_field_carries_the_conditions_with_the_air_quality(api_client, auth, on):
    body = api_client.get("/v1/field", headers=auth).json()
    assert body["conditions"] == CONDITIONS
    station, lat, lon, _ = on.weather.calls[0]
    assert on.weather.air_calls == [(station, lat, lon)], "the air quality of the same place the weather is of"
    assert body["readings"]["rh_pct"] == 80.0, "the humidity stays in readings"


def test_field_without_an_air_quality_still_has_the_rest(api_client, auth, on):
    on.weather.aqi = None
    conditions = api_client.get("/v1/field", headers=auth).json()["conditions"]
    assert conditions == {**CONDITIONS, "aqi": None}


def test_field_with_only_the_air_quality_known(api_client, auth, on):
    on.weather.snapshot_value = FakeWeather().snapshot_value
    on.weather.aqi = 40
    assert api_client.get("/v1/field", headers=auth).json()["conditions"] == {
        "sky": None, "is_day": None, "feels_like_c": None, "wind_kmh": None, "visibility_km": None, "pressure_hpa": None,
        "dew_point_c": None, "aqi": 40, "uv_index": None, "sunrise": None, "sunset": None}


def test_a_weather_source_that_knows_none_of_it_gives_null(api_client, auth, fake_container):
    """The CSV demo archive: no details and no air-quality capability."""
    assert not hasattr(fake_container.weather, "air_quality")
    body = api_client.get("/v1/field", headers=auth).json()
    assert "conditions" in body and body["conditions"] is None
    assert body["readings"] is not None, "the rest of the field page is unaffected"


def test_nothing_known_at_all_is_null_not_an_empty_object(api_client, auth, on):
    on.weather.snapshot_value = FakeWeather().snapshot_value
    on.weather.aqi = None
    assert api_client.get("/v1/field", headers=auth).json()["conditions"] is None


def test_weather_switched_off_has_no_conditions_and_asks_for_no_air_quality(api_client, auth, on):
    on.settings.weather_enabled = False
    body = api_client.get("/v1/field", headers=auth).json()
    assert body["conditions"] is None
    assert on.weather.calls == [] and on.weather.air_calls == []


def test_weather_that_cannot_be_read_has_no_conditions(api_client, auth, on):
    on.weather.raises = WeatherUnavailable("down")
    response = api_client.get("/v1/field", headers=auth)
    assert response.status_code == 200 and response.json()["conditions"] is None
    assert on.weather.air_calls == []


def test_the_spoken_summary_does_not_change_with_the_details(api_client, auth, on, fake_container):
    with_details = api_client.get("/v1/field", headers=auth).json()["spoken"]["text"]
    fake_container.weather = FakeWeather()
    without = api_client.get("/v1/field", headers=auth).json()["spoken"]["text"]
    assert with_details == without


# ------------------------------------------------------------------------------------------------ /v1/weather
def test_weather_of_a_chosen_place_carries_the_conditions(api_client, auth, on):
    body = api_client.get("/v1/weather?lat=31.1234&lon=77.3456", headers=auth).json()
    assert body["conditions"] == CONDITIONS
    assert on.place_weather.air_calls == [(None, 31.12, 77.35)], "the same rounded point as the weather"
    assert on.weather.air_calls == [], "the farmer's own-field source is not used for a chosen place"


def test_weather_of_a_place_without_details_is_null(api_client, auth, on):
    on.place_weather = FakeWeather()
    assert api_client.get("/v1/weather?lat=31&lon=77", headers=auth).json()["conditions"] is None


def test_the_air_quality_failing_never_fails_the_weather_of_a_place(api_client, auth, on):
    on.place_weather.aqi = None
    response = api_client.get("/v1/weather?lat=31&lon=77", headers=auth)
    assert response.status_code == 200 and response.json()["conditions"]["aqi"] is None
    assert response.json()["conditions"]["sky"] == "partly_cloudy"
