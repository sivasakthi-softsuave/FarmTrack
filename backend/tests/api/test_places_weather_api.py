"""The field screen's place picker: GET /v1/weather (live weather for a chosen point) and GET /v1/places/search (find it by name)."""
from datetime import datetime, timedelta

import pytest

from app.clock import IST
from app.domain.types import ForecastDay, Place
from app.integrations.errors import PlacesUnavailable, WeatherUnavailable
from app.security.ratelimit import SlidingWindowLimiter
from tests.fakes import NOW


@pytest.fixture
def on(fake_container):
    """Both features switched on (the default is off: PLACE_WEATHER_PROVIDER / PLACES_PROVIDER = none)."""
    fake_container.settings.place_weather_provider = "openmeteo"
    fake_container.settings.places_provider = "nominatim"
    return fake_container


# ------------------------------------------------------------------------------------------------ /v1/meta
def test_meta_says_what_the_server_can_do(api_client, fake_container):
    body = api_client.get("/v1/meta").json()
    assert body["place_weather_enabled"] is False and body["places_search_enabled"] is False        # the default is off
    fake_container.settings.place_weather_provider = "openmeteo"
    fake_container.settings.places_provider = "nominatim"
    body = api_client.get("/v1/meta").json()
    assert body["place_weather_enabled"] is True and body["places_search_enabled"] is True
    fake_container.place_weather = None                                    # a provider that is set but missing: not offered
    assert api_client.get("/v1/meta").json()["place_weather_enabled"] is False


# ------------------------------------------------------------------------------------------------ /v1/weather
def test_weather_of_a_chosen_place_has_the_shape_of_my_field_without_sensors_or_risks(api_client, auth, on):
    on.place_weather.snapshot_value.daily_forecast = [
        ForecastDay(day=(NOW + timedelta(days=i)).date(), tmin_c=5.0 + i, tmax_c=15.0 + i, rain_mm=float(i)) for i in range(9)]
    on.place_weather.snapshot_value.rain_last_24h_mm = 3.5
    response = api_client.get("/v1/weather?lat=31.1234&lon=77.3456", headers=auth)
    assert response.status_code == 200
    body = response.json()
    assert body["station_id"] is None and body["village"] is None and body["risks"] == [] and body["stale"] is False
    assert body["readings"] == {"temp_c": 14.0, "rh_pct": 80.0, "rain_24h_mm": 3.5, "leaf_wetness_min": None, "soil_moisture_pct": None}
    assert len(body["forecast"]) == 7 and body["forecast"][0] == {"day": "2026-05-12", "tmin_c": 5.0, "tmax_c": 15.0, "rain_mm": 0.0}
    spoken = body["spoken"]["text"]["en"]
    assert spoken.startswith("It is cool there now.") and "No rain is expected" in spoken
    assert "your field" not in spoken, "a picked place is 'there', not 'your field'"
    assert "risk" not in spoken.lower() and "danger" not in spoken.lower(), "a picked place has no risk list: it must not claim 'no risk'"
    assert body["spoken"]["text"]["hi"].startswith("वहाँ")
    assert body["spoken"]["audio"]["hi"]["url"].startswith("/audio/")


def test_weather_uses_its_own_adapter_the_real_clock_and_rounded_coordinates(api_client, auth, on):
    api_client.get("/v1/weather?lat=31.1234&lon=77.3456", headers=auth)
    assert on.weather.calls == [], "the farmer's own-field weather adapter is not used"
    station, lat, lon, now = on.place_weather.calls[0]
    assert (station, lat, lon) == (None, 31.12, 77.35)
    assert now.tzinfo is not None and abs(now - datetime.now(IST)) < timedelta(minutes=1), "live weather needs the real time"
    assert now != NOW, "not the frozen demo clock"


def test_stale_weather_is_flagged_and_announced(api_client, auth, on):
    on.place_weather.snapshot_value.stale = True
    body = api_client.get("/v1/weather?lat=31&lon=77", headers=auth).json()
    assert body["stale"] is True and body["spoken"]["text"]["en"].startswith("This information is old.")


def test_weather_is_off_by_default(api_client, auth, fake_container):
    response = api_client.get("/v1/weather?lat=31&lon=77", headers=auth)
    assert response.status_code == 503 and response.json()["code"] == "place_weather_off"
    assert fake_container.place_weather.calls == []


@pytest.mark.parametrize("query", ["", "?lat=31", "?lon=77", "?lat=51.5&lon=-0.12", "?lat=0&lon=0", "?lat=nan&lon=77", "?lat=31&lon=inf"])
def test_weather_needs_a_point_in_india(api_client, auth, on, query):
    response = api_client.get("/v1/weather" + query, headers=auth)
    assert response.status_code == 400 and response.json()["code"] == "invalid_location"
    assert on.place_weather.calls == []


def test_weather_with_text_instead_of_numbers_is_refused(api_client, auth, on):
    assert api_client.get("/v1/weather?lat=abc&lon=77", headers=auth).status_code in (400, 422)
    assert on.place_weather.calls == []


def test_weather_upstream_failure_is_a_503_the_app_can_retry(api_client, auth, on):
    on.place_weather.raises = WeatherUnavailable("Open-Meteo is down")
    response = api_client.get("/v1/weather?lat=31&lon=77", headers=auth)
    assert response.status_code == 503 and response.json()["code"] == "weather_unavailable"
    assert "Open-Meteo" not in response.text, "no internal detail reaches the farmer"


def test_weather_needs_a_login(api_client, on):
    assert api_client.get("/v1/weather?lat=31&lon=77").status_code == 401
    assert on.place_weather.calls == []


def test_weather_is_rate_limited_per_farmer(api_client, auth, on):
    api_client.app.state.limiters.place_weather_farmer = SlidingWindowLimiter(2, 600.0)
    assert [api_client.get("/v1/weather?lat=31&lon=77", headers=auth).status_code for _ in range(3)] == [200, 200, 429]


# ------------------------------------------------------------------------------------------------ /v1/places/search
def test_search_returns_places_with_their_points(api_client, auth, on):
    response = api_client.get("/v1/places/search?q=Theog", headers=auth)
    assert response.status_code == 200
    items = response.json()["items"]
    assert items[0] == {"name": "Theog", "label": "Theog, Shimla, Himachal Pradesh", "kind": "town", "lat": 31.12, "lon": 77.35}
    assert len(items) == 2
    assert on.places.calls == [("Theog", "en", 5)]


def test_search_tidies_the_query_and_passes_language_and_limit(api_client, auth, on):
    api_client.get("/v1/places/search?q=%20%20Theog%20%20%20Shimla%20&lang=hi&limit=1", headers=auth)
    api_client.get("/v1/places/search?q=Kullu&lang=fr&limit=99", headers=auth)
    assert on.places.calls == [("Theog Shimla", "hi", 1), ("Kullu", "en", 8)], "limit is capped at 8; an unknown language is English"


@pytest.mark.parametrize("q", ["", "a", "   ", "x" * 81])
def test_search_refuses_a_query_that_is_too_short_or_too_long(api_client, auth, on, q):
    response = api_client.get("/v1/places/search", params={"q": q}, headers=auth)
    assert response.status_code == 400 and response.json()["code"] == "invalid_query"
    assert on.places.calls == []


def test_search_is_off_by_default(api_client, auth, fake_container):
    response = api_client.get("/v1/places/search?q=Theog", headers=auth)
    assert response.status_code == 503 and response.json()["code"] == "places_off"
    assert fake_container.places.calls == []


def test_search_upstream_failure_is_a_503(api_client, auth, on):
    on.places.raises = PlacesUnavailable("nominatim: 502")
    response = api_client.get("/v1/places/search?q=Theog", headers=auth)
    assert response.status_code == 503 and response.json()["code"] == "places_unavailable"
    assert "nominatim" not in response.text.lower()


def test_search_with_no_match_is_an_empty_list_not_an_error(api_client, auth, on):
    on.places.results = []
    response = api_client.get("/v1/places/search?q=Nowhereville", headers=auth)
    assert response.status_code == 200 and response.json() == {"items": []}


def test_search_needs_a_login(api_client, on):
    assert api_client.get("/v1/places/search?q=Theog").status_code == 401
    assert on.places.calls == []


def test_search_is_rate_limited_per_farmer(api_client, auth, on):
    api_client.app.state.limiters.places_farmer = SlidingWindowLimiter(2, 600.0)
    statuses = [api_client.get("/v1/places/search?q=Theog", headers=auth).status_code for _ in range(3)]
    assert statuses == [200, 200, 429]


def test_a_place_result_can_be_sent_straight_back_to_weather(api_client, auth, on):
    """The two calls fit together: a result's lat/lon is a valid point for /v1/weather."""
    place = Place(**api_client.get("/v1/places/search?q=Theog", headers=auth).json()["items"][0])
    assert api_client.get(f"/v1/weather?lat={place.lat}&lon={place.lon}", headers=auth).status_code == 200


# ------------------------------------------------------------------------------------------------ /v1/places/reverse
def test_reverse_names_the_area_of_a_point(api_client, auth, on):
    response = api_client.get("/v1/places/reverse?lat=31.3112&lon=77.4771&lang=hi", headers=auth)
    assert response.status_code == 200
    assert response.json() == {"name": "Kotgarh", "label": "Kotgarh, Kumharsain, Shimla, Himachal Pradesh", "kind": "village",
                               "lat": 31.31, "lon": 77.48}
    assert on.places.reverse_calls == [(31.3112, 77.4771, "hi")]
    api_client.get("/v1/places/reverse?lat=31.3&lon=77.4&lang=fr", headers=auth)
    assert on.places.reverse_calls[-1][2] == "en", "an unknown language is English"


@pytest.mark.parametrize("query", ["", "?lat=31", "?lon=77", "?lat=51.5&lon=-0.12", "?lat=nan&lon=77", "?lat=31&lon=inf"])
def test_reverse_needs_a_point_in_india(api_client, auth, on, query):
    response = api_client.get("/v1/places/reverse" + query, headers=auth)
    assert response.status_code == 400 and response.json()["code"] == "invalid_location"
    assert on.places.reverse_calls == []


def test_reverse_with_nothing_known_there_is_a_404_the_app_can_answer_with_its_own_words(api_client, auth, on):
    on.places.reverse_result = None
    response = api_client.get("/v1/places/reverse?lat=31.3&lon=77.4", headers=auth)
    assert response.status_code == 404 and response.json()["code"] == "place_not_found"


def test_reverse_is_off_by_default_and_a_failure_is_a_503(api_client, auth, fake_container):
    response = api_client.get("/v1/places/reverse?lat=31.3&lon=77.4", headers=auth)
    assert response.status_code == 503 and response.json()["code"] == "places_off"
    assert fake_container.places.reverse_calls == []
    fake_container.settings.places_provider = "nominatim"
    fake_container.places.raises = PlacesUnavailable("nominatim: 502")
    response = api_client.get("/v1/places/reverse?lat=31.3&lon=77.4", headers=auth)
    assert response.status_code == 503 and response.json()["code"] == "places_unavailable"
    assert "nominatim" not in response.text.lower()


def test_reverse_needs_a_login_and_is_rate_limited_per_farmer(api_client, auth, on):
    assert api_client.get("/v1/places/reverse?lat=31.3&lon=77.4").status_code == 401
    api_client.app.state.limiters.places_reverse_farmer = SlidingWindowLimiter(2, 600.0)
    statuses = [api_client.get("/v1/places/reverse?lat=31.3&lon=77.4", headers=auth).status_code for _ in range(3)]
    assert statuses == [200, 200, 429]
