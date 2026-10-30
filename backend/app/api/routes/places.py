"""The field screen's place picker: weather for a place the farmer chose, and the search for that place by name.

  GET /v1/weather?lat=&lon=          live weather for any point in India (same shape as My field, without sensors and risks)
  GET /v1/places/search?q=&lang=     a state, district, town or village by name, with the point to show on the map
  GET /v1/places/reverse?lat=&lon=   which named area (village, tehsil, district, state) a point lies in: the name the app shows

Both are behind the farmer's login and rate limited per farmer. They are switched on by PLACE_WEATHER_PROVIDER and PLACES_PROVIDER
(`/v1/meta` reports `place_weather_enabled` and `places_search_enabled`, so the app only offers what works).
"""
from __future__ import annotations

import logging
from datetime import datetime

from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.api.deps import get_container, get_current_farmer, get_db, get_limiters
from app.api.schemas import ErrorOut, FieldOut, PlaceOut, PlaceSearchOut
from app.clock import IST
from app.domain.types import FarmerProfile
from app.integrations.errors import PlacesUnavailable, WeatherUnavailable
from app.integrations.places_nominatim import in_india
from app.security.errors import ApiError
from app.security.ratelimit import RateLimiters, enforce
from app.services.container import Container
from app.services.field_service import FieldService

logger = logging.getLogger(__name__)
router = APIRouter(prefix="/v1", tags=["places"], responses={401: {"model": ErrorOut}})

MIN_QUERY, MAX_QUERY, MAX_RESULTS = 2, 80, 8


def _on(provider: str, adapter: object | None) -> bool:
    return provider.strip().lower() != "none" and adapter is not None


@router.get("/weather", response_model=FieldOut, responses={400: {"model": ErrorOut}, 429: {"model": ErrorOut}, 503: {"model": ErrorOut}})
def get_place_weather(lat: float | None = None, lon: float | None = None, farmer: FarmerProfile = Depends(get_current_farmer),
                      db: Session = Depends(get_db), container: Container = Depends(get_container),
                      limiters: RateLimiters = Depends(get_limiters)) -> FieldOut:
    """Live weather (now, the last 24 h of rain, 7 days) for the point the farmer picked: lat and lon in India, both required."""
    if lat is None or lon is None or lat != lat or lon != lon or not in_india(lat, lon):     # (x != x: NaN)
        raise ApiError(400, "invalid_location", "Send lat and lon together, for a place in India.")
    if not _on(container.settings.place_weather_provider, container.place_weather):
        raise ApiError(503, "place_weather_off", "Weather for a chosen place is switched off on this server.")
    enforce(limiters.place_weather_farmer, farmer.id)
    now: datetime = datetime.now(IST)                       # live weather: the real time, not the demo clock
    try:
        return FieldService(container, db).at_place(lat, lon, now)
    except WeatherUnavailable:
        logger.warning("place weather unavailable farmer=%s", farmer.id, exc_info=True)
        raise ApiError(503, "weather_unavailable", "The weather for this place is not available now. Please try again.") from None


@router.get("/places/search", response_model=PlaceSearchOut,
            responses={400: {"model": ErrorOut}, 429: {"model": ErrorOut}, 503: {"model": ErrorOut}})
def search_places(q: str = "", lang: str = "en", limit: int = 5, farmer: FarmerProfile = Depends(get_current_farmer),
                  container: Container = Depends(get_container), limiters: RateLimiters = Depends(get_limiters)) -> PlaceSearchOut:
    """Find a state, district, town or village by name (Hindi or English), at most 8 results. Call it when the farmer SUBMITS the
    search, not on every key press (the public OpenStreetMap search forbids that)."""
    query = " ".join(q.split())
    if not MIN_QUERY <= len(query) <= MAX_QUERY:
        raise ApiError(400, "invalid_query", f"Type {MIN_QUERY} to {MAX_QUERY} letters of the place name.")
    if not _on(container.settings.places_provider, container.places):
        raise ApiError(503, "places_off", "The place search is switched off on this server.")
    enforce(limiters.places_farmer, farmer.id)
    assert container.places is not None  # noqa: S101  _on() checked it
    try:
        found = container.places.search(query, "hi" if lang == "hi" else "en", max(1, min(limit, MAX_RESULTS)))
    except PlacesUnavailable:
        logger.warning("place search unavailable farmer=%s", farmer.id, exc_info=True)
        raise ApiError(503, "places_unavailable", "The place search is not available now. Please try again.") from None
    return PlaceSearchOut(items=[PlaceOut(name=p.name, label=p.label, kind=p.kind, lat=p.lat, lon=p.lon) for p in found])


@router.get("/places/reverse", response_model=PlaceOut,
            responses={400: {"model": ErrorOut}, 404: {"model": ErrorOut}, 429: {"model": ErrorOut}, 503: {"model": ErrorOut}})
def reverse_place(lat: float | None = None, lon: float | None = None, lang: str = "en",
                  farmer: FarmerProfile = Depends(get_current_farmer), container: Container = Depends(get_container),
                  limiters: RateLimiters = Depends(get_limiters)) -> PlaceOut:
    """The named area a point lies in (the nearest village, its tehsil, district and state), so that a touch on the map or the phone's
    position is shown as "Kotgarh, Kumharsain, Shimla, Himachal Pradesh" and not as "a point". 404 when nothing is known there."""
    if lat is None or lon is None or lat != lat or lon != lon or not in_india(lat, lon):     # (x != x: NaN)
        raise ApiError(400, "invalid_location", "Send lat and lon together, for a place in India.")
    if not _on(container.settings.places_provider, container.places):
        raise ApiError(503, "places_off", "The place search is switched off on this server.")
    enforce(limiters.places_reverse_farmer, farmer.id)
    assert container.places is not None  # noqa: S101  _on() checked it
    try:
        found = container.places.reverse(lat, lon, "hi" if lang == "hi" else "en")
    except PlacesUnavailable:
        logger.warning("place lookup unavailable farmer=%s", farmer.id, exc_info=True)
        raise ApiError(503, "places_unavailable", "The place search is not available now. Please try again.") from None
    if found is None:
        raise ApiError(404, "place_not_found", "No named place is known at this point.")
    return PlaceOut(name=found.name, label=found.label, kind=found.kind, lat=found.lat, lon=found.lon)
