# FarmTrack backend

Python API behind the voice-guided farmer app: photo -> crop and disease -> approved-list advice (rules decide, the
LLM only explains), spray diary, field readings and weather, alerts, "ask a question", voice prompts and audio, and a
small admin site for the expert queue. FastAPI, SQLAlchemy 2, Alembic. SQLite for development and tests, PostgreSQL
(pgvector) for production.

## Run (Windows or Unix)
```
cd backend
python -m venv .venv && .venv/Scripts/python -m pip install -e ".[dev]"     # Unix: .venv/bin/python
.venv/Scripts/python -m uvicorn app.main:app --reload --port 8000           # or: make install / make run
.venv/Scripts/python -m pytest                                              # whole suite, offline, a few minutes
.venv/Scripts/python -m ruff check app tests     # what CI runs; `python -m mypy app` is clean too (not in CI)
```
With the defaults everything runs offline: mock LLM, hash embeddings, in-memory vector store, stub vision, mock Zoho
and IoT, weather from the demo archive, push and SMS only logged. The demo clock is frozen at 2026-05-12 (apple season;
`DEMO_CLOCK` in `.env`, empty = real time).

Demo login (`POST /v1/auth/login`): username `f001` (the farmer id in lower case, `f001` ... `f050`) and password
`farm1234` (`DEMO_PASSWORD`). The demo logins exist only where the demo farmers are loaded (dev/test, or `SEED_DEMO=1` in
production); a dev database made before the password login gets them added at start-up. Real farmers get their login from an
admin: Admin > Farmers ("Create farmer", and "Set login" for a new or forgotten password; also
`POST /admin/api/v1/farmers` and `POST /admin/api/v1/farmers/{id}/login`). A farmer without a password cannot log in.
Usernames are 3-40 characters of `a-z 0-9 . _ -` (not case-sensitive), passwords at least 6 characters, stored only as a
salted PBKDF2 hash. The phone number is a contact field, not the login. The phone + OTP login (`/v1/auth/otp/*`) is still in
the code but off: both routes answer 404 unless `OTP_LOGIN_ENABLED=true` (it also needs a real SMS gateway). Interactive API:
http://localhost:8000/docs (dev only).
Admin site: http://localhost:8000/admin, key = `ADMIN_API_KEY` (dev default `dev-admin-key`).

For a phone on the same Wi-Fi use `..\scripts/start_backend_for_phone.ps1` (real vision models from `storage/models`, listens on all addresses).

Force a disease result for an offline demo (stub vision only, never in production):
`DEMO_DISEASE_HINTS="Apple=Apple___Apple_scab:0.9"`.

## Configuration
Everything is an environment variable or a line of the repo-root `.env` (copy `../.env.example`; the file lists every
setting with a comment). `.env` holds secrets: never commit it, never paste it anywhere. Switches that matter:
`LLM_PROVIDER=openai` + `OPENAI_API_KEY` + `OPENAI_MODEL` (default `gpt-4o-mini`, shut down 14 Jan 2027 -> `gpt-6-luna`),
`TTS_PROVIDER=google`, `CROP_ID_PROVIDER=model` / `DISEASE_PROVIDER=model` (needs `pip install -e ".[ml]"`, ~300 MB of
model files, see `app/vision/torch_models.py`), `EMBEDDINGS_PROVIDER`, `VECTOR_STORE=pgvector`, `ZOHO_PROVIDER=real`,
`WEATHER_PROVIDER=openmeteo`, `WEATHER_ENABLED=false` (no weather at all), `TRAINING_EXPORT_DIR`, `PUSH_PROVIDER=fcm` (`.[fcm]`), `RULES_AUTO_ADVICE_DISEASES` (default `*`, see below).
`ENV=prod` refuses to start with development defaults (secret keys, CORS `*`, demo hints), hides the API docs and uses
Alembic migrations only.

## Weather off switch (`WEATHER_ENABLED`)
`WEATHER_ENABLED=false` (default `true`) turns weather off everywhere: no lookup and no network call (`app.integrations.factory`
builds a `DisabledWeatherAdapter` that only raises), no weather risks (scab infection, leaf spot, late blight, rain wash-off), no
weather alerts (the waiting-period alert still runs), an empty forecast and no weather sentence on `GET /v1/field`, no repeat-after-rain
or wait-for-rain timing in advice (`timing.action` is `unknown`, reasons `["weather_disabled"]`, empty text; the advice templates
then say only "Ask your expert for the best time to spray"). `GET /v1/meta` reports `weather_enabled` so the app can hide the weather UI.
The field sensor readings are not weather and stay. Weather is read in: `scan_service._weather`, `field_service`, `alerts/evaluator`,
`rules/recommend` (risks and timing), `integrations/factory`, `api/routes/meta`; the admin dashboard shows the state.

## Place picker on "My field" (`PLACE_WEATHER_PROVIDER`, `PLACES_PROVIDER`)
The farmer can look at the weather of any point in India, not only of the saved field. Both features are off by default (`none`) and are
reported by `GET /v1/meta` (`place_weather_enabled`, `places_search_enabled`), so the app only offers what works.
- `GET /v1/weather?lat=&lon=` (`PLACE_WEATHER_PROVIDER=openmeteo`): the answer has the shape of `GET /v1/field` (readings of warmth, air and the
  last 24 h of rain, 7 days, a spoken summary) with no sensor values and no risk list; the spoken text never says "no risk" for a place it did
  not work out risks for. It has its own Open-Meteo adapter (own cache, own hourly call budget), uses the REAL clock (never `DEMO_CLOCK`: the
  forecast API only serves about 14 days back and 7 ahead), and rounds the point to 2 decimals (about 1 km). Outside India it is 400
  `invalid_location`; switched off 503 `place_weather_off`; the weather service failing 503 `weather_unavailable`. 60 calls per 10 minutes per farmer.
- `GET /v1/places/search?q=&lang=&limit=` (`PLACES_PROVIDER=nominatim`): a state, district, tehsil, town or village by name (Hindi or English,
  India only, Himachal Pradesh preferred), at most 8 results with `lat`/`lon`. It uses the public OpenStreetMap Nominatim server, whose policy
  (read 28 Oct 2026) allows ONE request per second for the whole app, wants a real contact in `PLACES_USER_AGENT`, asks for caching and forbids
  search-as-you-type: the adapter caches for a day, spaces its requests 1.1 s apart, and the app searches only when the farmer submits. 20 searches
  per 10 minutes per farmer. For many users run your own Nominatim and set `PLACES_URL`.
- `GET /v1/places/reverse?lat=&lon=&lang=` (same provider): the named area a point lies in, so a touch on the map or the phone's position is
  shown by its real name and not as "a point": the nearest village (zoom 13 of Nominatim's reverse lookup, checked on real Himachal points), its tehsil,
  district and state, e.g. `Kotgarh, Kumharsain, Shimla, Himachal Pradesh`. 404 `place_not_found` when nothing is known there (the app then uses
  its generic words). The app asks once when the farmer CHOOSES a point (never per touch); answers are cached (points within about 100 m share one)
  and share the one-request-a-second clock with the search. 30 per 10 minutes per farmer. `PLACES_URL` must end with `/search` (the reverse URL is
  derived from it).
- **Current weather details (29 Oct 2026):** `GET /v1/field` and `GET /v1/weather` carry `conditions` (null when the source knows none of it:
  the CSV demo archive, weather off or unreadable), all fields optional: `sky` (`clear`, `mostly_clear`, `partly_cloudy`, `cloudy`, `fog`,
  `drizzle`, `rain`, `heavy_rain`, `showers`, `snow`, `thunderstorm`; from the WMO `weather_code`, an unknown code is null), `is_day`,
  `feels_like_c` (apparent temperature), `wind_kmh` (10 m), `visibility_km` (metres from Open-Meteo, 1 decimal), `pressure_hpa` (**mean sea
  level**, as a weather app shows it, not the pressure at the field's height), `dew_point_c`, `aqi` (**US AQI 0-500**). The humidity is the
  existing `readings.rh_pct`. All but `aqi` ride on the ONE forecast call (extra hourly variables, the hour of "now", gaps stay null).
  `aqi` is a second, separate call to Open-Meteo's air-quality API (`current=us_aqi`), made only for the field screen (never by a scan), cached
  30 minutes per place (a failure 5 minutes), 3 s timeout, counted in the same 600-calls-an-hour budget; any failure just leaves `aqi` null and
  never touches the weather. Code: `app/integrations/weather_openmeteo.py` (`air_quality`), `weather_common.py` (`sky_from_wmo`),
  `FieldService._conditions`, `AirQualityAdapter` in `app/interfaces.py`.
- **Next hours, sun, UV and the spray check (29 Oct 2026, Home option B):** `GET /v1/field` and `GET /v1/weather` also carry
  (a) `conditions.uv_index` (UV of the current hour, 1 decimal), `conditions.sunrise` and `conditions.sunset` (today's, **UTC with a trailing
  Z**); (b) `hours`: always present, up to **12 hours, the current hour first**, each `{time (UTC, Z), temp_c, sky, is_day, rain_chance_pct
  (0-100), rain_mm, wind_kmh}` with null for what the source does not know; **empty for the CSV demo archive**, weather off or unreadable;
  (c) `spray`: null, or `{state: go|care|stop, headline: calm_dry|windy|hot|rain_soon|raining, wind: {kmh, status}, rain: {dry_hours,
  mm_next_3h, status}, heat: {temp_c, status}}` with status `ok|care|stop`. All of it rides on the ONE forecast call (extra hourly
  `precipitation_probability` and `uv_index`, daily `sunrise,sunset`, same 30-minute cache and 600-calls-an-hour budget). Times stay
  `timezone=Asia/Kolkata` in the request and are turned into UTC at the edge. Code: `HourlySeries` / `_outlook` in `weather_common.py`,
  `OpenMeteoAdapter._sun_times`, `FieldService._hours` and `_spray`, the pure rules in `app/services/spray_weather.py`.
  **The spray check is DRAFT and OFF by default** (`SPRAY_WEATHER_ENABLED=false`: `spray` is null; the hours are sent either way). Its limits
  are settings, to be approved by an agronomist before real farmers see it: `SPRAY_RAIN_MM=0.5` (an hour with that much rain is wet; wet in the
  current hour or the next two = `stop`, in the three after = `care`; `dry_hours` = whole hours until the first wet hour, null when none
  in the hours known; `mm_next_3h` = rain of the current and next two hours), `SPRAY_WIND_CARE_KMH=15`, `SPRAY_WIND_STOP_KMH=30` (the
  current hour's wind), `SPRAY_HEAT_CARE_C=32`, `SPRAY_HEAT_STOP_C=40` (the current temperature). `state` = the worst part, `headline` = its
  reason (rain before wind before heat when equal; rain in the current hour is `raining`, otherwise `rain_soon`); an unknown number counts as
  fine for its part and with none of wind, temperature and rain known there is no check. It speaks only of the weather: medicine, dose and
  waiting period stay with the advice and the rules.
- The free Open-Meteo endpoints (forecast and air quality) are for non-commercial use: set `OPEN_METEO_API_KEY` (paid plan) in production
  (the adapter then uses `customer-api.` and `customer-air-quality-api.open-meteo.com`). The air-quality data is CAMS ENSEMBLE (Copernicus):
  Open-Meteo asks for attribution to it and to Open-Meteo where it is shown. Code: `app/api/routes/places.py`,
  `app/integrations/places_nominatim.py`, `FieldService.at_place`.

## Admin: training photos, farmers' photos, voice
- **Admin > Training photos** (`/admin/training`): upload several labelled leaf photos (class from the disease catalogue; the four apple
  classes first, or a free class name; optional crop, leaf id, source, licence, "confirmed by"). Files go through the same checks as scan
  photos (`MAX_UPLOAD_MB`, real image decoding, pixel limit, EXIF/GPS removed; the stored file is the cleaned JPEG, long edge 2048 px)
  and are stored as `STORAGE_DIR/training_uploads/<class>/<sha16>.jpg` with a row in `training_photos` (migration 0002) and an audit
  entry. Duplicates (same picture, any class) are refused. List by class, preview, delete, **download a ZIP** (`<class>/adm_<sha16>.jpg`
  + `sources.csv`), or **write into the training folder** (`TRAINING_EXPORT_DIR`, default `data/training/photos/<class>/`, plus
  `../admin_uploads.csv` in the `sources.csv` columns). At most 20 files per upload (the request body limit is the scan limit).
- **Admin > Farmer photos** (`/admin/uploads`): the photos farmers sent with scans, with photo time, received time and an "offline queue"
  mark; filter for offline ones.
- **Admin > Voice** (`/admin/voice`) and a dashboard line: TTS provider configured or not, prompts with and without audio per language.
  Steps to generate the audio: `../docs/voice-package.md`.

## Offline uploads
The app queues a scan with an `Idempotency-Key` and sends it when online, possibly several times. `POST /v1/scans` also takes
`taken_at` (photo time) and `offline` (form fields); both are stored on the scan (`scans.taken_at`, `scans.offline`) and returned in
`ScanOut`. A `taken_at` more than 1 day ahead or more than 400 days old is ignored (null), never an error. Advice is always worked out on
arrival. `GET /v1/scans/by-request/{key}` returns the stored result without photos or analysis when the response was lost. A replay
(same key) returns the first result whatever the content; a 429 or a validation error does not use up the key. A burst of more than 30
new scans in 10 minutes gets 429 (the app must retry later). Tests: `tests/api/test_offline_upload_api.py`.

## Docker
`docker compose --env-file ../.env up -d --build` (api + PostgreSQL with pgvector; the entrypoint runs
`alembic upgrade head` first). Written but never built or run on the development machine: see `../docs/open-questions.md`.

## Layout
```
app/rules/        deterministic engine: approved list, season/stage, rotation (FRAC/IRAC), waiting period, rain, risks
app/vision/       photo quality gate, crop identifier, disease classifier (stub by default, torch models optional)
app/advice/ llm/  composer + validator (only rule facts may be spoken), OpenAI/mock providers
app/rag/          knowledge notes, retrieval, grounded "ask" answers
app/voice/        prompt catalogue, TTS providers, content-addressed audio cache
app/services/     scan pipeline, spray diary, field, auth, expert release, product matching
app/api/ admin/   routes (contract: ../contracts/openapi.json) and the server-rendered admin pages
app/alerts/       alert evaluator, scheduler (run ONE worker), maintenance jobs
app/integrations/ Zoho, IoT, weather, push adapters (mock + real-shaped)
app/security/     auth tokens, rate limits, upload sanitising, redacting logs, startup checks
scripts/          evaluate_vision.py, generate_prompt_audio.py, dump_api_fixtures.py (fixtures for the mobile tests)
```
Contract: `make export-openapi` rewrites `../contracts/openapi.json` (changes must stay additive for the app).

## The rules that must not be broken
- A medicine reaches a farmer only from the rules engine's approved output for that crop; the LLM text is checked
  against it and replaced by a fixed template when it deviates. No approved data for a crop = no medicine advice.
- Automatic medicine advice for every disease with chemical control (owner decision, policy `RULES_AUTO_ADVICE_DISEASES=*`;
  set it empty to narrow it to apple scab). Diseases flagged for expert review, without a chemical cure, low confidence,
  unknown disease, a disease of another crop and crops without approved data ALWAYS go to the expert queue with general
  non-chemical advice. Banned, off-label and waiting-period checks are hard rules.
- Spoken texts never contain a name, phone or village (audio files are public, addressed by a hash of the text).
- Never log phone numbers, tokens, question text or keys.
