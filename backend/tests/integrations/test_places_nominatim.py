"""Place-name search with Nominatim: mapping, India-only, the public server's policy (identify, cache, one request a second)."""
import httpx
import pytest

from app.config import Settings
from app.integrations.errors import PlacesUnavailable
from app.integrations.factory import DisabledPlaces, DisabledWeatherAdapter, build_place_weather, build_places
from app.integrations.places_nominatim import MIN_INTERVAL_SECONDS, NominatimPlaces, in_india
from app.integrations.weather_openmeteo import OpenMeteoAdapter

THEOG = {"lat": "31.1197", "lon": "77.3567", "name": "Theog", "display_name": "Theog, Shimla, Himachal Pradesh, 171201, India",
         "addresstype": "town", "address": {"town": "Theog", "state_district": "Shimla", "state": "Himachal Pradesh", "country": "India"}}
KULLU_DISTRICT = {"lat": "31.9", "lon": "77.2", "name": "Kullu", "display_name": "Kullu, Himachal Pradesh, India", "addresstype": "state_district",
                  "address": {"state_district": "Kullu", "state": "Himachal Pradesh"}}
HP_STATE = {"lat": "31.9", "lon": "77.3", "name": "Himachal Pradesh", "display_name": "Himachal Pradesh, India", "addresstype": "state",
            "address": {"state": "Himachal Pradesh"}}
VILLAGE = {"lat": "31.25", "lon": "77.6", "name": "Kotgarh", "display_name": "Kotgarh, Shimla, Himachal Pradesh, India",
           "addresstype": "village", "address": {"village": "Kotgarh", "county": "Shimla", "state": "Himachal Pradesh"}}
LONDON = {"lat": "51.5", "lon": "-0.12", "name": "Theog", "display_name": "Theog, London, UK", "addresstype": "town", "address": {}}


class Spy:
    """An httpx client whose server is a list of canned answers; records every request."""

    def __init__(self, *answers):
        self.answers = list(answers)
        self.requests: list[httpx.Request] = []

    def handler(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        answer = self.answers.pop(0) if len(self.answers) > 1 else self.answers[0]
        if isinstance(answer, httpx.Response):
            return answer
        return httpx.Response(200, json=answer)

    def client(self) -> httpx.Client:
        return httpx.Client(transport=httpx.MockTransport(self.handler))


class Clock:
    """A fake clock: `sleep` moves it forward, so the one-request-a-second rule can be tested without waiting."""

    def __init__(self) -> None:
        self.now = 1000.0
        self.slept: list[float] = []

    def monotonic(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.slept.append(seconds)
        self.now += seconds


def make(spy: Spy, clock: Clock | None = None, agent: str = "FarmTrack-test/1.0 (test@example.org)") -> NominatimPlaces:
    clock = clock or Clock()
    return NominatimPlaces(agent, client=spy.client(), monotonic=clock.monotonic, sleep=clock.sleep)


def test_results_become_places_with_a_readable_label_and_a_kind():
    spy = Spy([THEOG, KULLU_DISTRICT, HP_STATE, VILLAGE])
    places = make(spy).search("theog", "en", 5)
    assert [(p.name, p.kind) for p in places] == [("Theog", "town"), ("Kullu", "district"), ("Himachal Pradesh", "state"), ("Kotgarh", "village")]
    assert places[0].label == "Theog, Shimla, Himachal Pradesh" and places[0].lat == 31.1197 and places[0].lon == 77.3567
    assert places[1].label == "Kullu, Himachal Pradesh", "a district is not repeated as its own district"
    assert places[3].label == "Kotgarh, Shimla, Himachal Pradesh", "a county counts as the district when there is no state_district"


def test_a_county_is_a_tehsil_and_the_district_comes_from_state_district():
    """Real Nominatim answer for Theog: addresstype 'county', address {county: Theog, state_district: Shimla, state: Himachal Pradesh}."""
    real = {"lat": "31.11989", "lon": "77.36362", "name": "Theog", "display_name": "Theog, Shimla, Himachal Pradesh, India",
            "addresstype": "county", "address": {"county": "Theog", "state_district": "Shimla", "state": "Himachal Pradesh", "country": "India"}}
    [place] = make(Spy([real])).search("theog", "en", 5)
    assert place.kind == "tehsil" and place.label == "Theog, Shimla, Himachal Pradesh"


def test_only_places_in_india_are_kept_and_the_list_is_cut_to_the_limit():
    spy = Spy([LONDON, THEOG, KULLU_DISTRICT, VILLAGE])
    assert [p.name for p in make(spy).search("theog", "en", 2)] == ["Theog", "Kullu"]


def test_duplicates_and_broken_items_are_skipped():
    broken = [{"lat": "x", "lon": "1"}, {"name": "No point"}, "text", None, {"lat": "31", "lon": "77", "display_name": ""}]
    spy = Spy([THEOG, dict(THEOG), *broken])
    assert [p.label for p in make(spy).search("theog", "en", 5)] == ["Theog, Shimla, Himachal Pradesh"]


def test_the_request_identifies_the_app_and_asks_for_india_and_himachal_first():
    spy = Spy([THEOG])
    make(spy, agent="FarmTrack/1.0 (field@example.org)").search("  Theog  ", "hi", 5)
    request = spy.requests[0]
    assert request.headers["user-agent"] == "FarmTrack/1.0 (field@example.org)", "the policy wants a real identifying User-Agent"
    params = dict(request.url.params)
    assert params["q"] == "  Theog  ", "the adapter sends the query as it was given (the route already tidied it)"
    assert params["countrycodes"] == "in" and params["accept-language"] == "hi,en" and params["format"] == "jsonv2"
    assert "viewbox" in params and "bounded" not in params, "Himachal is preferred, not required"


def test_an_empty_user_agent_is_refused():
    with pytest.raises(ValueError):
        NominatimPlaces("   ")


def test_a_repeated_search_comes_from_the_cache():
    spy = Spy([THEOG])
    places = make(spy)
    first = places.search("Theog", "en", 5)
    assert places.search("  theog ", "en", 5) == first
    assert len(spy.requests) == 1, "the policy asks clients to cache"
    places.search("theog", "hi", 5)
    places.search("theog", "en", 3)
    assert len(spy.requests) == 3, "another language or limit is another question"


def test_the_cache_expires_after_a_day():
    spy, clock = Spy([THEOG]), Clock()
    places = make(spy, clock)
    places.search("theog", "en", 5)
    clock.now += 24 * 3600 + 1
    places.search("theog", "en", 5)
    assert len(spy.requests) == 2


def test_real_requests_are_spaced_at_least_a_second_apart():
    spy, clock = Spy([THEOG]), Clock()
    places = make(spy, clock)
    places.search("theog", "en", 5)
    places.search("kullu", "en", 5)
    places.search("shimla", "en", 5)
    assert len(spy.requests) == 3
    assert clock.slept and all(s >= MIN_INTERVAL_SECONDS - 0.2 for s in clock.slept[1:]), clock.slept
    assert len(clock.slept) == 2, "the very first request does not wait"


@pytest.mark.parametrize("answer", [httpx.Response(500), httpx.Response(429), httpx.Response(200, text="not json"),
                                    httpx.Response(200, json={"error": "x"})])
def test_a_bad_reply_is_places_unavailable(answer):
    with pytest.raises(PlacesUnavailable):
        make(Spy(answer)).search("theog", "en", 5)


def test_no_network_is_places_unavailable():
    def boom(request):
        raise httpx.ConnectError("no route")

    places = NominatimPlaces("FarmTrack-test/1.0 (a@b.c)", client=httpx.Client(transport=httpx.MockTransport(boom)))
    with pytest.raises(PlacesUnavailable):
        places.search("theog", "en", 5)


def test_a_failure_is_not_cached():
    spy = Spy(httpx.Response(500), [THEOG])
    places = make(spy)
    with pytest.raises(PlacesUnavailable):
        places.search("theog", "en", 5)
    assert [p.name for p in places.search("theog", "en", 5)] == ["Theog"]


def test_in_india_bounds():
    assert in_india(31.1, 77.2) and in_india(8.5, 77.0) and not in_india(51.5, -0.1) and not in_india(0, 0)


# ------------------------------------------------------------------------------------------------ factory
def test_factory_choices():
    off = Settings(_env_file=None)
    assert isinstance(build_places(off), DisabledPlaces) and isinstance(build_place_weather(off), DisabledWeatherAdapter)
    on = Settings(_env_file=None, places_provider="nominatim", place_weather_provider="openmeteo")
    assert isinstance(build_places(on), NominatimPlaces) and isinstance(build_place_weather(on), OpenMeteoAdapter)
    with pytest.raises(ValueError):
        build_places(Settings(_env_file=None, places_provider="google"))
    with pytest.raises(ValueError):
        build_place_weather(Settings(_env_file=None, place_weather_provider="csv"))


def test_the_place_weather_adapter_is_not_the_farmers_own_weather_adapter():
    s = Settings(_env_file=None, place_weather_provider="openmeteo", weather_enabled=True, weather_provider="openmeteo")
    from app.integrations.factory import build_weather

    assert build_place_weather(s) is not build_weather(s), "own cache and own hourly call budget"


def test_disabled_places_raises():
    with pytest.raises(PlacesUnavailable):
        DisabledPlaces().search("theog", "en", 5)


def test_settings_default_to_off_and_to_a_placeholder_agent():
    s = Settings(_env_file=None)
    assert s.places_provider == "none" and s.place_weather_provider == "none"
    assert "PLACES_USER_AGENT" in s.places_user_agent


# ------------------------------------------------------------------------------------------------ reverse: which place is this point?
# The answers below are shaped like real Nominatim replies (zoom 13) for Himachal points, checked on 28 Oct 2026.
KOTGARH_POINT = {"lat": "31.311", "lon": "77.477", "name": "Kotgarh", "addresstype": "village",
                 "address": {"village": "Kotgarh", "county": "Kumharsain", "state_district": "Shimla", "state": "Himachal Pradesh"}}
DHALPUR_POINT = {"name": "Dhalpur", "addresstype": "suburb",
                 "address": {"suburb": "Dhalpur", "town": "Kullu", "county": "Kullu", "state_district": "Kullu", "state": "Himachal Pradesh"}}
ROHRU_POINT = {"address": {"town": "Rohru", "county": "Rohru", "state_district": "Shimla", "state": "Himachal Pradesh"}}


def test_a_point_is_named_by_its_village_tehsil_district_and_state():
    place = make(Spy(KOTGARH_POINT)).reverse(31.31101, 77.47707, "en")
    assert place is not None
    assert (place.name, place.kind) == ("Kotgarh", "village")
    assert place.label == "Kotgarh, Kumharsain, Shimla, Himachal Pradesh"
    assert (place.lat, place.lon) == (31.31101, 77.47707), "the point asked about, not the village's own"


def test_a_name_is_never_repeated_in_the_label():
    place = make(Spy(DHALPUR_POINT)).reverse(31.95, 77.1, "en")
    assert place is not None and place.label == "Dhalpur, Kullu, Himachal Pradesh" and place.kind == "village"


def test_a_town_a_tehsil_a_district_or_a_state_alone_is_still_a_name():
    town = make(Spy(ROHRU_POINT)).reverse(31.2, 77.7, "en")
    assert town is not None and town.label == "Rohru, Shimla, Himachal Pradesh" and town.kind == "town"
    only_tehsil = {"address": {"county": "Theog", "state_district": "Shimla", "state": "Himachal Pradesh"}}
    place = make(Spy(only_tehsil)).reverse(31.1, 77.3, "en")
    assert place is not None and (place.kind, place.label) == ("tehsil", "Theog, Shimla, Himachal Pradesh")
    only_district = {"address": {"state_district": "Kinnaur", "state": "Himachal Pradesh"}}
    place = make(Spy(only_district)).reverse(31.6, 78.4, "en")
    assert place is not None and (place.kind, place.label) == ("district", "Kinnaur, Himachal Pradesh")
    only_state = {"address": {"state": "Himachal Pradesh"}}
    place = make(Spy(only_state)).reverse(31.9, 77.2, "en")
    assert place is not None and (place.kind, place.label) == ("state", "Himachal Pradesh")


def test_nothing_known_at_a_point_is_none_and_is_remembered():
    spy = Spy({"error": "Unable to geocode"})
    places = make(spy)
    assert places.reverse(31.3, 77.4, "en") is None
    assert places.reverse(31.3, 77.4, "en") is None
    assert len(spy.requests) == 1, "a point with no name is not asked about again and again"
    assert make(Spy({"address": {}})).reverse(31.3, 77.4, "en") is None, "a reply without any name"


def test_the_reverse_request_asks_the_village_level_in_the_farmers_language():
    spy = Spy(KOTGARH_POINT)
    make(spy, agent="FarmTrack/1.0 (field@example.org)").reverse(31.31101, 77.47707, "hi")
    request = spy.requests[0]
    assert request.url.path == "/reverse" and request.headers["user-agent"] == "FarmTrack/1.0 (field@example.org)"
    params = dict(request.url.params)
    assert (params["lat"], params["lon"], params["zoom"]) == ("31.31101", "77.47707", "13")
    assert params["accept-language"] == "hi,en" and params["format"] == "jsonv2" and params["addressdetails"] == "1"


def test_points_a_hundred_metres_apart_share_one_answer_other_languages_do_not():
    spy = Spy(KOTGARH_POINT)
    places = make(spy)
    first = places.reverse(31.31101, 77.47707, "en")
    assert places.reverse(31.31149, 77.47651, "en") == first
    assert len(spy.requests) == 1
    places.reverse(31.31101, 77.47707, "hi")
    places.reverse(31.40, 77.47707, "en")
    assert len(spy.requests) == 3


def test_search_and_reverse_share_the_one_request_a_second_clock():
    spy, clock = Spy(KOTGARH_POINT), Clock()
    places = make(spy, clock)
    places.reverse(31.31, 77.47, "en")
    spy.answers = [[THEOG]]
    places.search("theog", "en", 5)
    assert len(spy.requests) == 2 and len(clock.slept) == 1 and clock.slept[0] >= MIN_INTERVAL_SECONDS - 0.2


@pytest.mark.parametrize("answer", [httpx.Response(500), httpx.Response(429), httpx.Response(200, text="not json"),
                                    httpx.Response(200, json=[1])])
def test_a_bad_reverse_reply_is_places_unavailable(answer):
    with pytest.raises(PlacesUnavailable):
        make(Spy(answer)).reverse(31.3, 77.4, "en")


def test_the_reverse_url_follows_the_search_url_and_an_odd_url_is_refused():
    spy = Spy(KOTGARH_POINT)
    NominatimPlaces("FarmTrack-test/1.0 (a@b.c)", url="http://nominatim.local:8088/search", client=spy.client()).reverse(31.3, 77.4, "en")
    assert str(spy.requests[0].url).startswith("http://nominatim.local:8088/reverse?")
    with pytest.raises(ValueError):
        NominatimPlaces("FarmTrack-test/1.0 (a@b.c)", url="http://nominatim.local/geocode")


def test_the_disabled_adapter_cannot_reverse_either():
    with pytest.raises(PlacesUnavailable):
        DisabledPlaces().reverse(31.3, 77.4, "en")
