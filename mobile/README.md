# FarmTrack mobile (Flutter)

Voice-guided app for low-literacy farmers: it speaks every step (Hindi, English), the farmer takes a photo and ticks
green or red. Flutter 3.47 / Dart 3.13, **Android first** (minSdk 24 = Android 7+). The iOS project exists (iOS 15+) but
has not been looked at yet. No code generation.

## Run
```
flutter pub get
flutter run --dart-define=USE_MOCK_API=true                      # demo without a backend (canned answers, log in with f001 / farm1234)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000      # real API (10.0.2.2 = host PC seen from the Android emulator;
                                                                 # a real phone needs the PC's LAN address or a deployed server)
flutter analyze && flutter test                                  # must stay clean (793 tests, about 2 minutes)
flutter build apk --split-per-abi                                # needs the Android SDK, never run on the dev PC
```
Dart defines: `API_BASE_URL` (default `http://10.0.2.2:8000`), `USE_MOCK_API` (default false, always on in tests).
Demo account (mock and dev backend): user name `f001` (to `f050`), password `farm1234`. Backend demo: start it with
`DEMO_DISEASE_HINTS="Apple=Apple___Apple_scab:0.9"` to get a scab result from the stub vision.
Real backend check: `tool/run_live_check.ps1` (or `.sh`) starts a local offline backend, runs `test_live/` over real HTTP
(31 calls) and stops it. API fixtures for the contract test come from `backend/scripts/dump_api_fixtures.py`
(re-run it after any backend change, then `flutter test test/contract_fixtures_test.dart`).

## Try it on an Android phone
1. PC: `powershell -ExecutionPolicy Bypass -File ..\scripts/start_backend_for_phone.ps1` (real vision models, no cloud calls, listens on
   the Wi-Fi; allow Python through the Windows firewall once). It prints the PC's address.
2. Build: `powershell -ExecutionPolicy Bypass -File tool/build_apk.ps1` (needs JDK 17 and the Android SDK, see
   `../docs/open-questions.md`); the APK is copied to `../dist/FarmTrack-test.apk`. Copy it to the phone and install it
   (allow "install unknown apps" for the file manager).
3. Phone and PC on the same Wi-Fi. In the app, login screen: tap "Server" and type the address the script printed
   (`http://<PC address>:8000`). Log in with `f001` / `farm1234`.
4. Scan: camera button or the gallery button next to it (up to four photos), then listen.

## How it works
- **Voice:** prompts in `assets/voice/prompts.json` (copy of `../voice/prompts.json`; run `python tool/sync_voice_assets.py`
  after changing it). Per sentence: bundled mp3, else server audio (cached by hash), else the phone's TTS. Dynamic advice
  text comes from the server (`spoken`). Every screen is built with `VoiceScaffold` (speaks once on entry): one slim white top bar (back,
  an optional title, the screen's small buttons, the speaker), the content, and at the bottom only the screen's one main action on a white
  strip. Home uses the deep-green header instead (`brandHeader`: greeting, village, bell, gear, speaker). The spoken sentence floats over the
  content as a dark one-line caption while it is spoken (tap to open all of it). Colours: green = done/yes, red = stop/no, grey = waiting,
  yellow = warning only, blue = information.
- **Look (27 Oct 2026: the approved mockup, all screens):** `../docs/design/ui-redesign-mockup.html` is the spec and the app follows it
  screen by screen, in English and Hindi: light green-grey ground, white cards with soft shadows, tinted panels with thin borders, the
  bottom bar (Home, Field, raised Scan, Diary, Ask) on the four main pages, floating dark caption with a breathing wave, wide action
  strip. Pictures of the real screens: `../docs/app-screenshots/real-app/`.
  - Tokens and text styles: `lib/core/theme/app_theme.dart` (`AppColors`, `Dimens`, `AppDecor`, `AppText`, `AppIcons`). Building blocks named
    after the mockup's CSS (`AppCard` .card, `SectionLabel` .label, `AppPill` .pill, `IconDot` .dot, `AppButton` .btn, `AppSwitch`,
    `VoiceWave`): `lib/core/widgets/design.dart`. Frame of every screen: `VoiceScaffold`.
  - **Fonts:** Noto Sans + Noto Sans Devanagari (SIL OFL, `assets/fonts/OFL.txt`), subset to Latin and Devanagari, five weights.
  - **Icons:** the mockup's line pictures as an icon font (`assets/fonts/FarmTrackIcons.ttf`, `lib/core/theme/farmtrack_icons.dart`),
    built from `tool/icons.json` by `tool/build_icon_font.py` (`pip install fonttools shapely svgpathtools`). Use `AppIcons.x`, never
    `Icons.*`. Change or add a picture in `icons.json`, run the script, commit the three files.
  - Round picture buttons are drawn 48 wide inside a 56 dp tap area (the accessibility rule is 56 dp). On the Home header the bell, the
    gear and the voice button stand in one line at the right (initials, greeting and location stay on the left) and are drawn 40 wide
    (`Dimens.compactIbtn`, `BigIconButton.diameter`); the tap area is still 56 dp. Three tap areas leave the names about 150 dp on a
    411 dp phone, so the location pill shows as many parts of the name as fit ("Kotgarh, Kumharsain", else "Kotgarh"; a screen reader
    always gets the whole short name), and a phone narrower than 380 dp leaves out the initials.
- **Voice button (28 Oct 2026, replaces the 27 Oct pair "mute" + "speaker"):** ONE speaker button at the right end of every top bar (the
  Home header, the camera). While the voice is on it is the speaker and one tap stops the voice at once and keeps the app silent on every
  screen (saved as `voice_muted`; the caption still shows each sentence for its reading time). While it is off it is the red
  crossed-out speaker and a tap turns the voice on and plays the screen again. Settings has the same choice as "Let the app speak".
  Consequence: there is no separate "listen again" button; to hear a screen again, turn the voice off and on. Code: `VoiceButton` in
  `lib/core/voice/voice_widgets.dart` (key `voice-button`; tests: `replayVoice()` in `test/support/finders.dart`), `AppSettings.muted`,
  `VoiceSettings.muted` in `DeviceVoiceService`.
- **Weather now and the week strip (29 Oct 2026, owner request, after the look of Microsoft's weather app):** "My field" (and the weather of a
  chosen place) starts with "Weather now" (`lib/features/field/current_weather.dart`): the picture of the sky, the temperature big, the
  word for the sky ("Mostly sunny"), "Feels like", and under a hairline the details, three to a row: air quality (a dot in the colour of
  its US AQI band, and the band in words), wind, humidity, visibility, pressure (sea level, mb), dew point. They come from `conditions`
  of `GET /v1/field` and `GET /v1/weather`; every one is optional and a missing one is simply not shown (an older server sends none:
  then the card has the temperature and the humidity). The digits are for the eyes: the voice still says only the server's summary.
  "Next seven days" is now a weather-app strip: the day on top in grey (today bold, on a soft panel), a coloured picture, the high in
  bold and the low in grey. The pictures are DRAWN (`weather_glyph.dart`: sun, moon, sun behind a cloud, cloud, cloud with a little or a
  lot of rain, snow), not icons of the icon font, so they can have the weather's own colours; the shapes differ too, so no colour carries
  a meaning alone, and the word is in the semantics label. Note: the orange sun is a picture, not the "warning" amber of the rules above.
  About 30 new Hindi words (`weather_*`, `sky_*`, `aqi_*`) are drafts for native review.
- **Seeing the real screens without a phone:** `flutter test test_visual/screens_shots_test.dart --dart-define=SHOT_DIR=<folder>` renders
  the screens at the mockup's 390 x 844 (2x) with the real fonts, in `en/` and `hi/` (`--dart-define=SMALL=true --dart-define=SCALE=1.5`
  for a 320 x 568 phone with large text; the other `test_visual/*_shots_test.dart` files cover more states). `flutter test` itself runs
  `test/` only. Card shadows look like flat grey steps in these pictures: the test renderer does not blur; a phone does.
- **Languages are data:** `assets/l10n/languages.json`, `strings.json`, the prompt file. A new language needs no code.
- **Voice package (24 Oct 2026):** at start the app loads the saved server catalogue, fetches a fresh one and, only over Wi-Fi or a cable,
  downloads every prompt audio file not on the phone yet (`VoicePackage` in `lib/core/voice/catalogue_sync.dart`; again when the phone reaches Wi-Fi;
  the farmer's language first). Order per sentence: bundled mp3, cached server file (works offline, checked first), download when online (6 s limit),
  phone TTS, caption only. Without any server audio (no TTS key yet) everything is spoken by the phone's voice.
- **Language list is data:** `assets/l10n/languages.json` (`badge` = the letter drawn in the button circle). More than two languages stack.
- **Weather flag:** `GET /v1/meta` `weather_enabled` (missing = true, last answer kept on the phone). False hides the forecast strip and the
  temperature/humidity/rain/leaf tiles of "My field" (the soil tile and the server's risks stay).
- **Crop pictures:** a crop's photo is `assets/crops/<crop id in lower case>.<jpg|png|jpeg|webp>` (400 x 400, a square, under about 60 KB; `test/crop_pictures_test.dart`
  fails if a crop the server lists has none). Without a file the blue picture of the crop's group is drawn. **After adding a file run `flutter clean` before
  `flutter build apk`:** the build cache does not notice new files in an asset folder that was already declared, and the APK silently comes out without them
  (check with `aapt list app-release.apk | grep assets/crops`). Photos from the web: make sure you may ship them.
- **Place picker (My field):** when `/v1/meta` says `place_weather_enabled`, the first card of "My field" names the place of the weather ("My field" or a
  picked place) and opens `/field/place`: search a name (only when the farmer submits; needs `places_search_enabled`), "My location" (GPS through
  `geolocator`, asked on the first tap; `ACCESS_COARSE/FINE_LOCATION` in the manifest) or a touch on the free map (`flutter_map`, OpenStreetMap
  tiles, a red pin, then "Show weather here"). The chosen place's weather (`GET /v1/weather`) shows in the same tiles and week; "Back to my field"
  returns. The place IS kept on the phone (one entry per farmer) until "Back to my field"; the location line of Home (a pill under the greeting) opens the same picker and shows the first two parts of the name. A touch on the map or the phone's position is named by its real area (`GET /v1/places/reverse`: village, tehsil, district, state); if the lookup fails the generic "A point on the map" / "My location" is used. The map's pictures come from OpenStreetMap's own server, fine for development and demos
  but NOT for production (its tile policy: best effort, heavy use blocked): build with `--dart-define=MAP_TILE_URL=https://your-provider/{z}/{x}/{y}.png`
  and `--dart-define=MAP_ATTRIBUTION="the credit your provider asks for"`. The credit line is always drawn on the map. iOS (location text in
  `Info.plist`) was not looked at.
- **Home, weather first (29 Oct 2026, owner chose "option B" of `../docs/design/home-now-in-your-field-proposal-b.html`):** under the camera card
  (and a "Result ready" card, if any) Home shows the weather of the place of the header line (`lib/features/home/home_weather.dart`; the place the
  farmer chose, else the own field: heading "Now at this place" / "Now in your field"): **one big card** whose colour follows the sky (blue sun,
  burnt-orange heat from 33 degrees, slate cloud, indigo rain, navy night: `HeroSky`; white words, 4.5 to 1 or better) with the drawn sky picture,
  the temperature, feels like, today's low and high and three dark-glass boxes (air, rain of the last day, wind); **Next hours** (a strip that
  moves sideways: the sky, temperature and rain chance of each hour; hours that are over are dropped); **Can I spray today?** (green "good time",
  amber "be careful", red "not now" with wind, rain and heat checks; a touch says the answer aloud, without digits; never shown for an answer
  kept on the phone); **Rain in the next days** (seven bars of millimetres and a sentence; a touch says the next rain); **More about the air** (air
  quality, visibility, dew point, pressure, sunrise and sunset, UV). Then "Last advice" and "Waiting to send". Every block is optional: a server
  without `hours`, `spray` or sun times simply has no such block. With weather off (or no temperature at all) the old white card of sensor readings
  stays. The numbers are for the eyes; the voice still says the server's short summary. The spray check is decided by the server (rules and
  thresholds in `backend/README.md`, draft until an agronomist approves). About 60 new Hindi words (`home_*`, `spray_*`) are drafts for native
  review. Pictures: `flutter test test_visual/home_weather_shots_test.dart --dart-define=SHOT_DIR=<folder>` (whole page, in several kinds of
  weather and in Hindi).
- **Diary: crop circles, this week, timeline (30 Oct 2026, owner chose design 2 of `../docs/design/diary-combined-proposals.html`):** the page of the Diary
  (`lib/features/diary/diary_timeline.dart`, `diary_list_screen.dart`) shows, from the top: round crop pictures ("All" and one for each crop; a touch shows only
  that crop, and says its name; only when the diary has more than one crop), "This week" (seven days, a dot for each spray, today solid green; the card is one button
  that opens the month), the month on a sheet (dots on the days sprayed, "Sprays / Crops / Last", arrows to earlier months, a speaker that says the count in words,
  "Done"), and the timeline: a thread, a big circle for each day ("Today Tuesday", "Friday 8 May") and a card for each spray with the crop's round picture, the
  medicine, "crop · saved" (or the grey "Waiting" tag), a speaker, tags (kind of medicine, dose "30 ml in 200 L", "Wait 14 days"), its warnings (always shown) and,
  on a touch, the brand and the steps. The days of the strip and the calendar are not touch targets (seven columns cannot be 56 dp). The numbers are for the eyes;
  the voice says the month in words. Pictures: `flutter test test_visual/diary_timeline_shots_test.dart --dart-define=SHOT_DIR=<folder>`. About 24 new Hindi words
  are drafts for native review (`docs/open-questions.md` section O).
- **Weather map (29 Oct 2026, owner request, "like zoom.earth, free and open"):** a "Weather map" card on My field (when the server's weather is on)
  opens `/field/map` (`weather_map_screen.dart`, `weather_map_widgets.dart`, `weather_map_data.dart`): the free map with three layers to choose
  by big buttons, a play button that runs the pictures as a film (one a second, the next one loaded in advance), a slider, and under the
  buttons the clock time and age of the picture ("11:53 am · 7 min ago"). It opens on the place chosen on My field (red pin), else on all of
  Himachal. **Rain radar** = RainViewer (past two hours, every 10 minutes, free tiles stop at zoom 7, radar covers Himachal on their coverage
  map but hills block beams); **Clouds** = Himawari infrared through NASA GIBS (every 10 minutes, about 40 minutes old; drawn at 70 percent);
  **Rain amount** = NASA GPM IMERG 30-minute rate through NASA GIBS (about six hours old). No key for any of them. The phone talks to these
  servers directly with its own Dio (`weatherMapDioProvider`: the farmer's login is never sent there; the tile requests tell them the area
  looked at and the phone's address). GIBS pictures are found by asking which moments exist (HEAD requests, newest first); the credit line names
  the base map and the layer. Tests replace `weatherMapFeedProvider` and `weatherMapTileProviderProvider` (see `test/support/map_fakes.dart`), so
  nothing is downloaded. About 24 new Hindi words (`weather_map_*`) are drafts. Wind, temperature and pressure layers are NOT built: the only
  free source (OpenWeatherMap tiles) needs a key. Licence: see `../docs/open-questions.md` section M before real farmers.
- **Offline:** photos and spray entries wait in `<app folder>/pending`, are sent when the network is back (connectivity stream, app resume, 30 s to 15 min
  timer, tap on the "Waiting to send" card), with an `Idempotency-Key` so a retry never duplicates. The queue survives restarts (7 days, 20 items); waiting
  diary entries show as waiting after a restart. The last advice (7 days) and the last diary list are kept on the phone: Home shows a "Last advice" card
  that opens it without internet, the diary shows its saved list with the offline marker.
- **Push:** `lib/core/push` has the interfaces only (no Firebase packages yet); steps to switch FCM on are in `../docs/design-notes/mobile2a.md`.
- **Login:** always required: user name + password (`POST /v1/auth/login`; no OTP, no phone number), tokens in secure storage,
  one shared refresh, a per-install device id sent at login. Only the last user name is remembered (never the password).

## Structure
```
lib/core/      config, theme, network (ApiClient, Dio, Mock), models, offline queue, push, voice, widgets, router, providers
lib/features/  onboarding auth home scan result diary field alerts ask settings
assets/        l10n (strings, languages, ask suggestions), voice (prompts), crops
test/          widget and unit tests; test/support = FakeVoice, fake TTS/audio/camera, TestEnv; test/fixtures/api = real backend answers
test_live/     tests against a running backend (not part of `flutter test`)
```

## Verified on 24 Oct 2026 / not verified
(24 Oct session, later: slim layout, green "I sprayed" tick and sprayed state looked at on the emulator at 411x731 dp and 320x569 dp with text 1.3 to 1.5, against
a real local backend; 754 tests. The release APK is arm64 and cannot start on the x86_64 emulator, so the emulator runs used a debug x86_64 build.)
Verified: analyze clean, 741 tests, release APK (arm64, 25 MB) built, debug x86_64 APK installed and started on an Android 15 emulator (language screen
seen and tapped), live check against the real backend (23 of 31 calls pass; the 8 others need the uncommitted photo folder).
Not verified: a real phone, real camera and permission texts, Hindi TTS voices, audio playback, secure storage on old phones, TalkBack,
behaviour on a 3 GB Android 9 phone, push, any screen after the language screen on the emulator. Design notes and doubts: `../docs/design-notes/mobile1.md`, `mobile2a.md`,
`mobile2b.md`, `contract.md`; open questions for the owner: `../docs/open-questions.md`.
