from datetime import datetime, timedelta

import httpx
import pytest

from app.clock import IST
from app.config import Settings
from app.integrations.errors import WeatherUnavailable
from app.integrations.weather_common import sky_from_wmo
from app.integrations.weather_csv import CsvWeatherAdapter
from app.integrations.weather_openmeteo import (
    AIR_CUSTOMER_URL,
    AIR_FAILURE_TTL_SECONDS,
    AIR_FREE_URL,
    AIR_TIMEOUT_SECONDS,
    CUSTOMER_URL,
    FREE_URL,
    MAX_CACHED_PLACES,
    MAX_CALLS_PER_HOUR,
    OpenMeteoAdapter,
)
from app.interfaces import AirQualityAdapter

DATA = Settings(_env_file=None).data_dir
NOW = datetime(2026, 10, 19, 8, 0, tzinfo=IST)
START = datetime(2026, 10, 5, 0, 0)          # past_days=14 -> 5 Oct 00:00 local


def payload(rain_at: dict[int, float] | None = None, temp_none_at: int | None = None, details: bool = True) -> dict:
    stamps = [(START + timedelta(hours=i)).strftime("%Y-%m-%dT%H:%M") for i in range(21 * 24)]
    rain_at = rain_at or {}
    n = len(stamps)
    hourly = {
        "time": stamps,
        "temperature_2m": [None if i == temp_none_at else 10.0 + (i % 24) / 2 for i in range(n)],
        "relative_humidity_2m": [60.0 + (i % 40) for i in range(n)],
        "precipitation": [rain_at.get(i, 0.0) for i in range(n)],
    }
    if details:      # the "current weather" series, as Open-Meteo sends them (visibility in metres, is_day 1 / 0)
        hourly.update({
            "apparent_temperature": [8.0 + (i % 24) / 2 for i in range(n)],
            "dew_point_2m": [5.0 + (i % 10) / 10 for i in range(n)],
            "pressure_msl": [1000.0 + (i % 30) / 10 for i in range(n)],
            "wind_speed_10m": [3.0 + (i % 12) for i in range(n)],
            "visibility": [24140.0 - (i % 5) * 1000 for i in range(n)],
            "weather_code": [(0, 1, 2, 3, 61)[i % 5] for i in range(n)],
            "is_day": [1 if 6 <= i % 24 < 18 else 0 for i in range(n)],
            "precipitation_probability": [(i % 11) * 10 for i in range(n)],              # 0, 10, ... 100 %
            "uv_index": [max(0.0, 8.0 - abs(i % 24 - 12)) for i in range(n)],             # 0 at night, 8 at noon
        })
    body = {"hourly": hourly}
    if details:      # today's sunrise and sunset per local day, as Open-Meteo sends them (local time, no zone)
        days = [(START + timedelta(days=d)).strftime("%Y-%m-%d") for d in range(21)]
        body["daily"] = {"time": days, "sunrise": [f"{day}T06:{d % 60:02d}" for d, day in enumerate(days)],
                         "sunset": [f"{day}T17:{(d + 30) % 60:02d}" for d, day in enumerate(days)]}
    return body


def hour_index(when: datetime) -> int:
    return int((when.replace(tzinfo=None) - START).total_seconds() // 3600)


class Recorder:
    def __init__(self, body=None, status=200):
        self.requests: list[httpx.Request] = []
        self.body = payload() if body is None else body
        self.status = status

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        return httpx.Response(self.status, json=self.body)


def adapter(recorder, **kwargs) -> OpenMeteoAdapter:
    return OpenMeteoAdapter(DATA, client=httpx.Client(transport=httpx.MockTransport(recorder)), **kwargs)


def test_request_shape_and_free_endpoint(monkeypatch):
    monkeypatch.delenv("OPEN_METEO_API_KEY", raising=False)
    rec = Recorder()
    adapter(rec).snapshot(None, 31.12, 77.36, NOW)
    req = rec.requests[0]
    assert str(req.url).startswith(FREE_URL)
    params = dict(req.url.params)
    assert params["hourly"] == ("temperature_2m,relative_humidity_2m,precipitation,apparent_temperature,dew_point_2m,pressure_msl,"
                                "wind_speed_10m,visibility,weather_code,is_day,precipitation_probability,uv_index"), (
        "ONE forecast call carries the weather details, the rain chance and the UV index too")
    assert params["daily"] == "sunrise,sunset"
    assert len(rec.requests) == 1
    assert (params["past_days"], params["forecast_days"], params["timezone"]) == ("14", "7", "Asia/Kolkata")
    assert params["latitude"] == "31.12" and params["longitude"] == "77.36" and "apikey" not in params


def test_api_key_switches_to_the_commercial_endpoint(monkeypatch):
    monkeypatch.setenv("OPEN_METEO_API_KEY", "k-test")
    rec = Recorder()
    adapter(rec).snapshot(None, 31.12, 77.36, NOW)
    assert str(rec.requests[0].url).startswith(CUSTOMER_URL)
    assert rec.requests[0].url.params["apikey"] == "k-test"


def test_mapping_to_weather_snapshot(monkeypatch):
    monkeypatch.delenv("OPEN_METEO_API_KEY", raising=False)
    now_i = hour_index(NOW)
    body = payload(rain_at={now_i - 3: 2.5, now_i - 30: 9.0, now_i + 4: 1.2, now_i + 20: 0.8, now_i + 40: 3.0})
    snap = adapter(Recorder(body)).snapshot("ST01", 31.12, 77.36, NOW)
    assert (snap.source, snap.station_id, snap.stale) == ("openmeteo", "ST01", False)
    assert snap.temp_c == body["hourly"]["temperature_2m"][now_i] and snap.rh_pct == body["hourly"]["relative_humidity_2m"][now_i]
    assert snap.rain_last_24h_mm == 2.5                       # the 9 mm fell 30 h ago
    assert snap.rain_next_12h_mm == 1.2
    assert snap.rain_next_48h_mm == pytest.approx(1.2 + 0.8 + 3.0)
    assert len(snap.hourly_past) == 14 * 24                   # last 14 days, oldest first
    assert snap.hourly_past[-1].time == NOW and snap.hourly_past[0].time == NOW - timedelta(hours=14 * 24 - 1)
    assert len(snap.hourly_future) == 48 and snap.hourly_future[0].time == NOW + timedelta(hours=1)
    assert [d.day.isoformat() for d in snap.daily_forecast] == [f"2026-10-{d}" for d in range(19, 26)]
    wet = next(h for h in snap.hourly_past if h.time == NOW - timedelta(hours=3))
    assert wet.rain_mm == 2.5 and wet.leaf_wet is True


def test_gap_hours_with_null_temperature_are_skipped(monkeypatch):
    monkeypatch.delenv("OPEN_METEO_API_KEY", raising=False)
    gap = hour_index(NOW) - 5
    snap = adapter(Recorder(payload(temp_none_at=gap))).snapshot(None, 31.12, 77.36, NOW)
    times = {h.time for h in snap.hourly_past}
    assert NOW - timedelta(hours=5) not in times and NOW - timedelta(hours=4) in times


def test_responses_are_cached_for_30_minutes():
    clock = [1000.0]
    rec = Recorder()
    om = adapter(rec, monotonic=lambda: clock[0])
    om.snapshot(None, 31.12, 77.36, NOW)
    clock[0] += 29 * 60
    om.snapshot(None, 31.12, 77.36, NOW)
    assert len(rec.requests) == 1
    om.snapshot(None, 32.24, 77.19, NOW)                   # another place is a separate cache entry
    assert len(rec.requests) == 2
    clock[0] += 2 * 60
    om.snapshot(None, 31.12, 77.36, NOW)
    assert len(rec.requests) == 3


def test_station_id_is_resolved_to_coordinates():
    rec = Recorder()
    adapter(rec).snapshot("ST08", None, None, NOW)
    assert rec.requests[0].url.params["latitude"] == "31.458698"


def test_no_place_raises():
    with pytest.raises(WeatherUnavailable):
        adapter(Recorder()).snapshot("ST99", None, None, NOW)
    with pytest.raises(WeatherUnavailable):
        adapter(Recorder()).snapshot(None, None, None, NOW)


@pytest.mark.parametrize("status", [429, 500, 503])
def test_http_errors_become_weather_unavailable(status):
    with pytest.raises(WeatherUnavailable, match=str(status)):
        adapter(Recorder(status=status)).snapshot(None, 31.12, 77.36, NOW)


@pytest.mark.parametrize("body", [{}, {"hourly": {}}, {"hourly": {"time": ["x"], "temperature_2m": [1], "relative_humidity_2m": [1],
                                                                       "precipitation": [0]}},
                                  {"hourly": {"time": ["2026-10-19T00:00"], "temperature_2m": [], "relative_humidity_2m": [],
                                              "precipitation": []}}])
def test_malformed_payloads_become_weather_unavailable(body):
    with pytest.raises(WeatherUnavailable):
        adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW)


def test_network_failure_becomes_weather_unavailable():
    def boom(request):
        raise httpx.ConnectTimeout("slow", request=request)

    om = OpenMeteoAdapter(DATA, client=httpx.Client(transport=httpx.MockTransport(boom)))
    with pytest.raises(WeatherUnavailable, match="ConnectTimeout"):
        om.snapshot(None, 31.12, 77.36, NOW)


def test_failures_are_not_cached():
    rec = Recorder(status=500)
    om = adapter(rec)
    for _ in range(2):
        with pytest.raises(WeatherUnavailable):
            om.snapshot(None, 31.12, 77.36, NOW)
    assert len(rec.requests) == 2


# ------------------------------------------------------------------------------------------------ "current weather" details
def _details_at_now(**values) -> dict:
    """A payload whose detail series have the given value at the hour of NOW (None = a gap) and, if a series is left out, its default."""
    body = payload()
    for key, value in values.items():
        body["hourly"][key][hour_index(NOW)] = value
    return body


def test_details_are_read_at_the_hour_of_now_and_rounded(monkeypatch):
    monkeypatch.delenv("OPEN_METEO_API_KEY", raising=False)
    body = _details_at_now(apparent_temperature=6.34, dew_point_2m=4.06, pressure_msl=1008.26, wind_speed_10m=12.34,
                           visibility=4249.0, weather_code=2, is_day=1)
    snap = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW)
    assert (snap.feels_like_c, snap.dew_point_c, snap.pressure_hpa, snap.wind_kmh) == (6.3, 4.1, 1008.3, 12.3)
    assert snap.visibility_km == 4.2, "metres to kilometres, one decimal"
    assert (snap.sky, snap.is_day) == ("partly_cloudy", True)
    night = adapter(Recorder(_details_at_now(is_day=0, weather_code=65))).snapshot(None, 31.12, 77.36, NOW)
    assert (night.sky, night.is_day) == ("heavy_rain", False)


def test_a_gap_in_a_detail_stays_none_and_never_hides_the_others():
    body = _details_at_now(apparent_temperature=None, visibility=None, weather_code=None, is_day=None, pressure_msl=1010.0)
    snap = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW)
    assert snap.feels_like_c is None and snap.visibility_km is None and snap.sky is None and snap.is_day is None
    assert snap.pressure_hpa == 1010.0 and snap.wind_kmh is not None and snap.temp_c is not None


def test_odd_values_are_none_not_a_crash_or_a_guess():
    body = _details_at_now(apparent_temperature="warm", dew_point_2m=True, wind_speed_10m=[1], weather_code="x", visibility="far")
    snap = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW)
    assert (snap.feels_like_c, snap.dew_point_c, snap.wind_kmh, snap.sky) == (None, None, None, None)
    assert snap.temp_c is not None and snap.rh_pct is not None, "the weather itself is unharmed"


def test_a_source_without_the_detail_series_gives_none_of_them():
    snap = adapter(Recorder(payload(details=False))).snapshot(None, 31.12, 77.36, NOW)
    assert snap.temp_c is not None
    assert (snap.sky, snap.is_day, snap.feels_like_c, snap.dew_point_c, snap.pressure_hpa, snap.wind_kmh,
            snap.visibility_km) == (None,) * 7


def test_a_detail_series_of_the_wrong_length_is_ignored_and_the_forecast_still_works():
    body = payload()
    body["hourly"]["visibility"] = body["hourly"]["visibility"][:5]
    snap = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW)
    assert snap.visibility_km is None and snap.pressure_hpa is not None and len(snap.daily_forecast) == 7


def test_gap_hours_are_removed_from_the_detail_series_too_so_they_stay_aligned():
    gap = hour_index(NOW) - 5
    body = payload(temp_none_at=gap)
    body["hourly"]["weather_code"][hour_index(NOW)] = 3
    series = OpenMeteoAdapter._parse(httpx.Response(200, json=body))
    assert len(series.times) == 21 * 24 - 1
    for column in (series.feels_like_c, series.dew_point_c, series.pressure_msl_hpa, series.wind_kmh, series.visibility_m,
                   series.weather_code, series.is_day):
        assert column is not None and len(column) == len(series.times)
    now_at = series.times.index(NOW)
    assert series.weather_code[now_at] == 3 and isinstance(series.weather_code[now_at], int)
    assert series.visibility_m[now_at] == body["hourly"]["visibility"][hour_index(NOW)]
    after_gap = series.times.index(NOW - timedelta(hours=4))
    assert series.wind_kmh[after_gap] == body["hourly"]["wind_speed_10m"][hour_index(NOW) - 4]


# ------------------------------------------------------------------------------------------------ next hours, UV, sunrise and sunset
def test_the_outlook_is_the_next_12_hours_from_the_current_one():
    body = payload()
    i = hour_index(NOW)
    body["hourly"]["weather_code"][i] = 0
    body["hourly"]["weather_code"][i + 3] = 61
    body["hourly"]["precipitation"][i + 3] = 1.26
    snap = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW)
    outlook = snap.outlook
    assert [h.time for h in outlook] == [NOW + timedelta(hours=k) for k in range(12)], "the current hour first, 12 hours, oldest first"
    now = outlook[0]
    assert now.temp_c == round(body["hourly"]["temperature_2m"][i], 1) and now.wind_kmh == round(body["hourly"]["wind_speed_10m"][i], 1)
    assert now.sky == "clear" and now.is_day is True and now.rain_chance_pct == (i % 11) * 10 and now.rain_mm == 0.0
    wet = outlook[3]
    assert (wet.sky, wet.rain_mm) == ("rain", 1.3), "the rain of the hour, one decimal"
    assert outlook[9].is_day is True and outlook[11].is_day is False, "is_day follows the hour (6 to 18 is day in this fixture)"


def test_the_rain_chance_is_a_whole_percentage_between_0_and_100():
    body = payload()
    i = hour_index(NOW)
    for k, value in enumerate((101.0, -5.0, 33.4, 33.5, None, "high", True)):
        body["hourly"]["precipitation_probability"][i + k] = value
    outlook = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW).outlook
    assert [h.rain_chance_pct for h in outlook[:7]] == [100, 0, 33, 34, None, None, None]


def test_an_outlook_shorter_than_12_hours_at_the_end_of_the_data():
    body = payload()
    last = len(body["hourly"]["time"]) - 1
    late = START + timedelta(hours=last - 4)         # four hours before the last hour of the forecast
    snap = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, late.replace(tzinfo=IST))
    assert len(snap.outlook) == 5 and snap.outlook[0].time == late.replace(tzinfo=IST)


def test_a_gap_hour_is_not_in_the_outlook_and_the_next_ones_are_not_shifted():
    body = payload(temp_none_at=hour_index(NOW) + 2)
    outlook = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW).outlook
    assert [h.time for h in outlook] == [NOW + timedelta(hours=k) for k in range(12) if k != 2]
    after = next(h for h in outlook if h.time == NOW + timedelta(hours=3))
    assert after.wind_kmh == round(body["hourly"]["wind_speed_10m"][hour_index(NOW) + 3], 1)


def test_the_outlook_is_empty_without_the_detail_series_and_for_the_csv_archive():
    assert adapter(Recorder(payload(details=False))).snapshot(None, 31.12, 77.36, NOW).outlook == []
    csv = CsvWeatherAdapter(DATA).snapshot("ST01", None, None, datetime(2026, 5, 12, 8, 0, tzinfo=IST))
    assert csv.outlook == [] and csv.uv_index is None and csv.sunrise is None and csv.sunset is None


def test_only_the_rain_chance_known_is_still_an_outlook_with_gaps():
    body = payload(details=False)
    body["hourly"]["precipitation_probability"] = [40.0] * len(body["hourly"]["time"])
    outlook = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW).outlook
    assert len(outlook) == 12 and {h.rain_chance_pct for h in outlook} == {40}
    assert outlook[0].sky is None and outlook[0].wind_kmh is None and outlook[0].is_day is None


def test_the_uv_index_is_read_at_the_hour_of_now():
    body = _details_at_now(uv_index=7.46)
    assert adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW).uv_index == 7.5
    assert adapter(Recorder(_details_at_now(uv_index=None))).snapshot(None, 31.12, 77.36, NOW).uv_index is None
    assert adapter(Recorder(_details_at_now(uv_index="strong"))).snapshot(None, 31.12, 77.36, NOW).uv_index is None


def test_sunrise_and_sunset_are_todays_in_local_time():
    snap = adapter(Recorder()).snapshot(None, 31.12, 77.36, NOW)
    day = (NOW.date() - START.date()).days
    assert snap.sunrise == datetime(2026, 10, 19, 6, day % 60, tzinfo=IST)
    assert snap.sunset == datetime(2026, 10, 19, 17, (day + 30) % 60, tzinfo=IST)
    assert snap.sunrise.tzinfo is not None and snap.sunrise.utcoffset() == timedelta(hours=5, minutes=30)
    tomorrow = adapter(Recorder()).snapshot(None, 31.12, 77.36, NOW + timedelta(days=1))
    assert tomorrow.sunrise.date().isoformat() == "2026-10-20"


@pytest.mark.parametrize("daily", [None, "x", [], {}, {"time": ["2026-10-19"]}, {"time": ["2026-10-19"], "sunrise": [], "sunset": []},
                                   {"time": ["2026-10-19"], "sunrise": [None], "sunset": ["soon"]},
                                   {"time": ["x"], "sunrise": ["2026-10-19T06:00"], "sunset": ["2026-10-19T17:00"]}])
def test_odd_daily_data_gives_no_sunrise_and_never_breaks_the_weather(daily):
    body = payload()
    body["daily"] = daily
    snap = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW)
    assert snap.sunrise is None and snap.sunset is None
    assert snap.temp_c is not None and len(snap.daily_forecast) == 7 and len(snap.outlook) == 12


def test_a_missing_sunset_does_not_hide_the_sunrise():
    body = payload()
    day = (NOW.date() - START.date()).days
    body["daily"]["sunset"][day] = None
    snap = adapter(Recorder(body)).snapshot(None, 31.12, 77.36, NOW)
    assert snap.sunrise is not None and snap.sunset is None


@pytest.mark.parametrize("code,sky", [
    (0, "clear"), (1, "mostly_clear"), (2, "partly_cloudy"), (3, "cloudy"), (45, "fog"), (48, "fog"),
    (51, "drizzle"), (53, "drizzle"), (55, "drizzle"), (56, "drizzle"), (57, "drizzle"),
    (61, "rain"), (63, "rain"), (66, "rain"), (65, "heavy_rain"), (67, "heavy_rain"),
    (80, "showers"), (81, "showers"), (82, "heavy_rain"),
    (71, "snow"), (73, "snow"), (75, "snow"), (77, "snow"), (85, "snow"), (86, "snow"),
    (95, "thunderstorm"), (96, "thunderstorm"), (97, "thunderstorm"), (99, "thunderstorm"),
    (2.0, "partly_cloudy"),
])
def test_the_wmo_weather_code_table(code, sky):
    assert sky_from_wmo(code) == sky


@pytest.mark.parametrize("code", [None, 4, 10, 44, 100, -1, "x", [], float("nan")])
def test_an_unknown_weather_code_has_no_sky(code):
    assert sky_from_wmo(code) is None


def test_the_open_meteo_adapter_can_give_the_air_quality_and_the_csv_archive_cannot():
    assert isinstance(OpenMeteoAdapter(DATA), AirQualityAdapter)
    assert not isinstance(CsvWeatherAdapter(DATA), AirQualityAdapter)


# ------------------------------------------------------------------------------------------------ air quality (its own call)
def aq_body(value) -> dict:
    """What the air-quality API answers (checked live, 29 Oct 2026)."""
    return {"latitude": 31.3, "longitude": 77.5, "timezone": "Asia/Kolkata", "current_units": {"time": "iso8601", "interval": "seconds",
            "us_aqi": "USAQI"}, "current": {"time": "2026-10-19T08:00", "interval": 3600, "us_aqi": value}}


def test_air_quality_request_shape_and_value(monkeypatch):
    monkeypatch.delenv("OPEN_METEO_API_KEY", raising=False)
    rec = Recorder(aq_body(47))
    assert adapter(rec).air_quality(None, 31.30, 77.47) == 47
    req = rec.requests[0]
    assert str(req.url).startswith(AIR_FREE_URL)
    assert dict(req.url.params) == {"latitude": "31.3", "longitude": "77.47", "current": "us_aqi", "timezone": "Asia/Kolkata"}
    assert req.extensions["timeout"]["read"] == AIR_TIMEOUT_SECONDS, "a short timeout: the air quality must not hold the weather up"


def test_air_quality_api_key_switches_to_the_commercial_host(monkeypatch):
    monkeypatch.setenv("OPEN_METEO_API_KEY", "k-test")
    rec = Recorder(aq_body(47))
    adapter(rec).air_quality(None, 31.30, 77.47)
    assert str(rec.requests[0].url).startswith(AIR_CUSTOMER_URL) and rec.requests[0].url.params["apikey"] == "k-test"


def test_air_quality_is_a_whole_number_and_the_station_id_is_resolved():
    rec = Recorder(aq_body(46.6))
    value = adapter(rec).air_quality("ST08", None, None)
    assert value == 47 and isinstance(value, int)
    assert rec.requests[0].url.params["latitude"] == "31.458698"


def test_a_snapshot_makes_no_air_quality_call():
    """Scans use snapshot() too: they must not pay for a second outbound request they do not show."""
    rec = Recorder()
    adapter(rec).snapshot(None, 31.12, 77.36, NOW)
    assert [r.url.host for r in rec.requests] == ["api.open-meteo.com"]


def test_air_quality_is_cached_for_30_minutes_per_place():
    clock = [1000.0]
    rec = Recorder(aq_body(40))
    om = adapter(rec, monotonic=lambda: clock[0])
    om.air_quality(None, 31.12, 77.36)
    clock[0] += 29 * 60
    assert om.air_quality(None, 31.12, 77.36) == 40 and len(rec.requests) == 1
    om.air_quality(None, 32.24, 77.19)
    assert len(rec.requests) == 2
    clock[0] += 2 * 60
    om.air_quality(None, 31.12, 77.36)
    assert len(rec.requests) == 3


@pytest.mark.parametrize("status", [401, 429, 500, 503])
def test_an_air_quality_http_error_is_none_not_an_exception(status):
    assert adapter(Recorder(aq_body(47), status=status)).air_quality(None, 31.12, 77.36) is None


@pytest.mark.parametrize("body", [{}, {"current": None}, {"current": {}}, {"current": {"us_aqi": None}}, {"current": {"us_aqi": "42"}},
                                  {"current": {"us_aqi": True}}, {"current": {"us_aqi": 999}}, {"current": {"us_aqi": -3}},
                                  {"current": []}, []])
def test_an_odd_air_quality_payload_is_none(body):
    assert adapter(Recorder(body)).air_quality(None, 31.12, 77.36) is None


def test_air_quality_that_is_not_json_is_none():
    om = OpenMeteoAdapter(DATA, client=httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, content=b"<html>oops"))))
    assert om.air_quality(None, 31.12, 77.36) is None


@pytest.mark.parametrize("error", [httpx.ConnectTimeout, httpx.ReadTimeout, httpx.ConnectError])
def test_an_air_quality_network_failure_is_none(error):
    def boom(request):
        raise error("slow", request=request)

    om = OpenMeteoAdapter(DATA, client=httpx.Client(transport=httpx.MockTransport(boom)))
    assert om.air_quality(None, 31.12, 77.36) is None


def test_an_air_quality_failure_is_remembered_for_a_few_minutes_then_tried_again():
    clock = [1000.0]
    answers = [httpx.Response(500), httpx.Response(200, json=aq_body(52))]
    seen: list[httpx.Request] = []

    def handler(request):
        seen.append(request)
        return answers[min(len(seen), 2) - 1]

    om = OpenMeteoAdapter(DATA, client=httpx.Client(transport=httpx.MockTransport(handler)), monotonic=lambda: clock[0])
    assert om.air_quality(None, 31.12, 77.36) is None
    clock[0] += AIR_FAILURE_TTL_SECONDS - 10
    assert om.air_quality(None, 31.12, 77.36) is None and len(seen) == 1, "not asked again for every page view"
    clock[0] += 20
    assert om.air_quality(None, 31.12, 77.36) == 52 and len(seen) == 2
    clock[0] += 20 * 60
    assert om.air_quality(None, 31.12, 77.36) == 52 and len(seen) == 2, "a success is kept the full 30 minutes"


def test_air_quality_counts_against_the_hourly_request_budget_and_stops_when_it_is_used_up():
    clock = [0.0]
    rec = Recorder(aq_body(47))
    om = adapter(rec, monotonic=lambda: clock[0])
    om.air_quality(None, 31.12, 77.36)
    assert len(om._calls) == 1, "the same budget as the forecast"
    om._calls.extend([clock[0]] * MAX_CALLS_PER_HOUR)
    assert om.air_quality(None, 32.0, 77.0) is None and len(rec.requests) == 1, "budget used up: no request, no exception"
    clock[0] += 3601.0
    assert om.air_quality(None, 32.0, 77.0) == 47


def test_air_quality_without_a_place_is_none_and_asks_nothing():
    rec = Recorder(aq_body(47))
    assert adapter(rec).air_quality("ST99", None, None) is None and adapter(rec).air_quality(None, None, None) is None
    assert rec.requests == []


def test_the_air_quality_cache_is_bounded():
    clock = [0.0]
    om = adapter(Recorder(aq_body(47)), monotonic=lambda: clock[0])
    for n in range(MAX_CACHED_PLACES + 40):
        om.air_quality(None, 30.0 + n * 0.01, 77.0)
        clock[0] += 0.001
    assert len(om._air_cache) <= MAX_CACHED_PLACES
