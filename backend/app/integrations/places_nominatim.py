"""Place-name search (state, district, town, village) and "which place is this point?" with OpenStreetMap's Nominatim.

POLICY (https://operations.osmfoundation.org/policies/nominatim/, read 28 Oct 2026): the PUBLIC server allows at most one request
per second for the whole application, wants a real identifying User-Agent (set PLACES_USER_AGENT with a contact), asks clients to
cache results, and forbids search-as-you-type. So this adapter (1) answers repeats from a cache, (2) spaces its real requests at
least `MIN_INTERVAL_SECONDS` apart (the search and the reverse lookup share that one clock) and (3) is meant to be called when the
farmer SUBMITS a search or CHOOSES a point, never for every key press or every touch of the map.
The data is (c) OpenStreetMap contributors (ODbL): the app shows that credit on its map.
For many users, run your own Nominatim and point `PLACES_URL` at it.
"""
from __future__ import annotations

import threading
import time
from collections.abc import Callable

import httpx

from app.domain.types import Lang, Place
from app.integrations.errors import PlacesUnavailable

DEFAULT_URL = "https://nominatim.openstreetmap.org/search"
MIN_INTERVAL_SECONDS = 1.1          # the public server's limit is 1 per second for the whole application
MAX_WAIT_SECONDS = 4.0              # a request that would have to wait longer than this is refused (the farmer may try again)
CACHE_TTL_SECONDS = 24 * 3600.0
MAX_CACHED_QUERIES = 512
# India (the product's area), and Himachal Pradesh preferred inside it (a hint, not a filter: viewbox without `bounded`).
COUNTRY = "in"
HP_VIEWBOX = "75.4,33.4,79.2,30.2"          # left,top,right,bottom
INDIA_LAT = (6.0, 37.6)
INDIA_LON = (68.0, 97.6)

# Reverse lookup: zoom 13 is the village / suburb level (checked on real Himachal points: Kotgarh, Narkanda, Akpa, Dhalpur near Kullu);
# 14 gives obscure hamlets and single dwellings, 10 only a town.
REVERSE_ZOOM = 13
_LOCALITY_KEYS = ("village", "hamlet", "suburb", "neighbourhood", "locality", "isolated_dwelling", "town", "city")

_DISTRICT_TYPES = {"state_district", "district"}
_TEHSIL_TYPES = {"county"}                      # OpenStreetMap maps a Himachal tehsil (sub-district) as a "county"
_VILLAGE_TYPES = {"village", "hamlet", "suburb", "neighbourhood", "isolated_dwelling", "locality"}
_TOWN_TYPES = {"town", "city", "municipality"}

_MISSING = object()                             # "not in the cache" (None is a real, cacheable answer: nothing is known there)


def in_india(lat: float, lon: float) -> bool:
    return INDIA_LAT[0] <= lat <= INDIA_LAT[1] and INDIA_LON[0] <= lon <= INDIA_LON[1]


def _kind(item: dict) -> str:
    raw = str(item.get("addresstype") or item.get("type") or "").lower()
    if raw == "state":
        return "state"
    if raw in _DISTRICT_TYPES:
        return "district"
    if raw in _TEHSIL_TYPES:
        return "tehsil"
    if raw in _TOWN_TYPES:
        return "town"
    if raw in _VILLAGE_TYPES:
        return "village"
    return "place"


def _place(item: dict) -> Place | None:
    try:
        lat, lon = float(item["lat"]), float(item["lon"])
    except (KeyError, TypeError, ValueError):
        return None
    if not in_india(lat, lon):
        return None
    address = item.get("address") if isinstance(item.get("address"), dict) else {}
    display = str(item.get("display_name") or "")
    name = str(item.get("name") or "").strip() or display.split(",")[0].strip()
    if not name:
        return None
    parts = [name]
    for key in ("state_district", "county"):                 # the district, once
        district = str(address.get(key) or "").strip()
        if district and district not in parts:
            parts.append(district)
            break
    state = str(address.get("state") or "").strip()
    if state and state not in parts:
        parts.append(state)
    return Place(name=name, label=", ".join(parts), kind=_kind(item), lat=round(lat, 5), lon=round(lon, 5))


def _reverse_place(item: dict, lat: float, lon: float) -> Place | None:
    """The named area a point lies in: the nearest village (or suburb, town), its tehsil, its district and the state, e.g.
    "Kotgarh, Kumharsain, Shimla, Himachal Pradesh". The point returned is the one asked about, not the village's own."""
    address = item.get("address") if isinstance(item.get("address"), dict) else {}
    if not address:
        return None

    def text(key: str) -> str:
        return str(address.get(key) or "").strip()

    locality_key = next((k for k in _LOCALITY_KEYS if text(k)), None)
    locality = text(locality_key) if locality_key else ""
    parts: list[str] = []
    for value in (locality, text("county"), text("state_district"), text("state")):      # village, tehsil, district, state: each once
        if value and value not in parts:
            parts.append(value)
    if not parts:
        return None
    # the kind of the most detailed thing that is known: the village, else the tehsil, else the district, else the state
    detail = locality_key or ("county" if text("county") else "state_district" if text("state_district") else "state")
    kind = _kind({"addresstype": detail})
    return Place(name=locality or parts[0], label=", ".join(parts), kind=kind, lat=round(lat, 5), lon=round(lon, 5))


class NominatimPlaces:
    def __init__(self, user_agent: str, url: str = DEFAULT_URL, client: httpx.Client | None = None,
                 monotonic: Callable[[], float] = time.monotonic, sleep: Callable[[float], None] = time.sleep,
                 reverse_url: str | None = None) -> None:
        if not user_agent.strip():
            raise ValueError("Nominatim needs an identifying User-Agent (PLACES_USER_AGENT)")
        self._url = url
        base = url.rstrip("/")
        if reverse_url is None and not base.endswith("/search"):
            raise ValueError("PLACES_URL must end with /search (the reverse lookup is the same server's /reverse)")
        self._reverse_url = reverse_url or base[: -len("/search")] + "/reverse"
        self._headers = {"User-Agent": user_agent.strip(), "Accept": "application/json"}
        self._http = client or httpx.Client(timeout=10.0)
        self._monotonic = monotonic
        self._sleep = sleep
        self._lock = threading.Lock()                      # one real request at a time, spaced MIN_INTERVAL_SECONDS apart (search AND reverse)
        self._last_call = -1e9
        self._cache: dict[tuple, tuple[float, object]] = {}
        self._cache_lock = threading.Lock()

    # ------------------------------------------------------------------ the two questions
    def search(self, query: str, lang: Lang, limit: int) -> list[Place]:
        key = ("search", " ".join(query.lower().split()), lang, limit)
        cached = self._cached(key)
        if isinstance(cached, list):
            return list(cached)
        params = {"q": query, "format": "jsonv2", "addressdetails": 1, "limit": min(limit * 2, 20), "countrycodes": COUNTRY,
                  "viewbox": HP_VIEWBOX, "accept-language": f"{lang},en", "dedupe": 1}
        data = self._get_json(self._url, params)
        if not isinstance(data, list):
            raise PlacesUnavailable("place search returned an unexpected reply")
        places: list[Place] = []
        seen: set[str] = set()
        for item in data:
            place = _place(item) if isinstance(item, dict) else None
            if place is None or place.label in seen:
                continue
            seen.add(place.label)
            places.append(place)
            if len(places) >= limit:
                break
        self._remember(key, places)
        return list(places)

    def reverse(self, lat: float, lon: float, lang: Lang) -> Place | None:
        """The named area of a point (None when OpenStreetMap knows nothing there). Points within about 100 m share one answer."""
        key = ("reverse", round(lat, 3), round(lon, 3), lang)
        cached = self._cached(key)
        if cached is not _MISSING:
            return cached if isinstance(cached, Place) else None
        params = {"lat": round(lat, 5), "lon": round(lon, 5), "format": "jsonv2", "zoom": REVERSE_ZOOM, "addressdetails": 1,
                  "accept-language": f"{lang},en"}
        data = self._get_json(self._reverse_url, params)
        if not isinstance(data, dict):
            raise PlacesUnavailable("place search returned an unexpected reply")
        place = None if data.get("error") else _reverse_place(data, lat, lon)       # "Unable to geocode": nothing is known there
        self._remember(key, place)
        return place

    # ------------------------------------------------------------------ plumbing
    def _cached(self, key: tuple) -> object:
        with self._cache_lock:
            hit = self._cache.get(key)
            if hit and self._monotonic() - hit[0] < CACHE_TTL_SECONDS:
                return hit[1]
        return _MISSING

    def _remember(self, key: tuple, value: object) -> None:
        with self._cache_lock:
            self._cache[key] = (self._monotonic(), value)
            if len(self._cache) > MAX_CACHED_QUERIES:
                for stale in [k for k, (stamp, _) in self._cache.items() if self._monotonic() - stamp >= CACHE_TTL_SECONDS]:
                    del self._cache[stale]
                while len(self._cache) > MAX_CACHED_QUERIES:
                    del self._cache[next(iter(self._cache))]

    def _get_json(self, url: str, params: dict) -> object:
        """One real request, spaced from the last one (the public server's one-a-second rule); a failure is PlacesUnavailable."""
        if not self._lock.acquire(timeout=MAX_WAIT_SECONDS):
            raise PlacesUnavailable("the place search is busy; try again in a moment")
        try:
            wait = MIN_INTERVAL_SECONDS - (self._monotonic() - self._last_call)
            if wait > 0:
                self._sleep(wait)
            self._last_call = self._monotonic()
            try:
                response = self._http.get(url, params=params, headers=self._headers)
                response.raise_for_status()
                return response.json()
            except (httpx.HTTPError, ValueError) as exc:
                raise PlacesUnavailable(f"place search failed: {type(exc).__name__}") from exc
        finally:
            self._lock.release()


class DisabledPlaces:
    """PLACES_PROVIDER=none: the search is switched off (the route checks the setting first; this is the second line of defence)."""

    def search(self, query: str, lang: Lang, limit: int) -> list[Place]:
        raise PlacesUnavailable("the place search is switched off (PLACES_PROVIDER=none)")

    def reverse(self, lat: float, lon: float, lang: Lang) -> Place | None:
        raise PlacesUnavailable("the place search is switched off (PLACES_PROVIDER=none)")
