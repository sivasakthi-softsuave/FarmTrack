# FarmTrack MVP: open questions and decisions to review

Written 19 Oct 2026 at the end of the autonomous build. You were away, so every doubt below was settled by me with the
safest or most conventional option; nothing was left half done. Go through A first (needs you), then B (needs an
expert), then veto anything in D. The per-agent working notes with the full detail are in `notes/` (reference only,
delete the folder when you no longer need it).

## A. Decided by you on 19 Oct 2026, and what is still open
**Decided (already in the code):**
- **No callback.** Farmers photograph a leaf and get the answer at once (disease and what to do); the case is saved in the
  database. No expert phone call, no in-app expert reply. The "not sure" texts say: do not spray yet, take another photo or
  show the plant to a local expert, with no promise that anyone answers. The expert queue and the admin pages remain as an
  internal review list; the "save this case" button on the result screen only records it.
- **No SMS and no OTP for the MVP.** Login is user name + password and is always required (light security on purpose;
  OTP code is still in the backend behind `OTP_LOGIN_ENABLED`). Demo accounts `f001` to `f050`, password `farm1234`
  (`DEMO_PASSWORD`). Real farmers get their login from the admin site (Set login / Create farmer). Decide later: SMS gateway,
  who creates accounts, whether a PIN or a printed card would suit farmers better than typing a password, "forgot password".
- **Automatic medicine advice for every disease with chemical control** (`RULES_AUTO_ADVICE_DISEASES=*`). The evidence says
  the models cannot tell apple scab, Alternaria and Marssonina apart, so a wrong disease can give a wrong medicine; the
  hard guards stay (expert-review, no-cure, low confidence below 0.65, unknown disease, wrong crop, no approved data for the
  crop all go to the safe "do not spray yet" answer). Set the variable empty to go back to scab only.
- **No seasons during development** (22 Oct 2026). A disease is advised on any date: the rules no longer reject scab outside
  its season or leaf spots before 1 June, and the growth stage no longer excludes products (setting `RULES_SEASON_CHECK`,
  default `false`; `true` brings the production behaviour back). Before real use, decide whether to switch it on again.
  What still goes to the safe "do not spray yet" answer: Root rot, Brown spot and Black rot (flagged "needs an expert" in
  the disease list), the combined "Scab & Rust" class, low confidence, and crops without approved medicines.
- **Android only for now**, iOS later. The camera screen also has a gallery button (up to 4 photos per scan).

**Still open:**
1. **Photo retention** is 365 days, then deleted (the scan result stays). Photos can show people and houses. There is no
   "delete my data" route yet. Decide the retention period and whether a deletion route is required.
2. **Watering/irrigation** is not in the MVP (as agreed). Confirm it stays out.
3. **Admin site** is server-rendered pages (login with an admin key, CSRF, no JavaScript), not a React/Flutter web app.
   It covers: expert queue, expert requests, release advice to a farmer, product on/off switch, farmers, alerts, audit,
   demo clock. Say if you want a richer UI.
4. **Languages:** Hindi and English only. A third language is data only (strings, prompts, glossary, audio) but each
   needs a native review.
5. **Hosting and operations:** run ONE uvicorn worker (scheduler and in-memory rate limits assume it); PostgreSQL with
   pgvector; a reverse proxy with `--proxy-headers`; who owns backups and the admin key.
6. **Weather licence:** Open-Meteo's free endpoint and IMD data are non-commercial; production needs a paid plan or
    another source. Zoho field names (`Farmer_ID`, `Advisory` subform) and the client's IoT platform are assumptions.
7. **OpenAI model:** `gpt-4o-mini` shuts down 14 Jan 2027. The name is in `.env` (`OPENAI_MODEL`), switch to `gpt-6-luna`
    and rerun `data/model_test/` before then. The key in `.env` was never read or printed by me.
8. **Phones:** **Android first, as you asked; iOS was deliberately not touched** (the project folder exists, nothing was
    checked or built for it; Flutter 3.47 needs iOS 15, so an iPhone 6s/7 only works after updating to iOS 15). Android
    minSdk is 24 (Android 7); you said Android 9+, so older Android is a bonus, not a promise.

## B. Needs an expert
**Native Hindi speaker (everything Hindi is machine-drafted):** `voice/prompts.json` (spoken prompts), interface words in
`mobile/assets/l10n/strings.json`, advice phrases and numbers (`app/advice`), rules messages, alert texts, `services/texts.py`,
ask suggestions, diary words ("बीता कल" for yesterday because "कल" also means tomorrow), severity words ("Serious" for red),
crop names, button picture names ("green tick", "gear"). Also: **listening test of the generated voices** (hi-IN and en-IN
Neural2 are unverified defaults; Hindi availability and TTS prices were not checked) and whether farmers understand the
Material icons used for buttons.

**Agronomist:**
- Two different pesticides logged on one day give no warning (the rules cannot tell one tank from two). Add a soft
  "if mixed in one tank, do not" warning?
- Ziram 27 % SC rows have no waiting period in the data, the 80 % WP row has 21 days. Confirm.
- Doses for tomato/potato are per hectare; farmers think in bigha/kanal or per tank. Conversion is not done.
- Wording of the general protective measures (remove fallen leaves, watch the plants) and the Hindi crop-name table.
- The Marssonina rule text mentions "6 h leaf wetness on rain days"; the data scripts and the engine do not apply it.
- Demo scenarios S6, S7, S8, S10 disagree with the engine on purpose (policy, "never repeat the same chemical", no cure for
  virus, 97 vs 73 days). The engine is right under the rules; fix the scenario facts.
- Which crops beyond apple get approved lists (client counts and lists are still missing; "all HP crops" has data for apple only).

**Hindi crop names** beyond the demo crops and the voice list (banana, brinjal, okra, custard apple ...) are my draft
(`backend/app/advice/crop_names.py`, one table for scan cards and advice text); "beans" is `बीन्स` in advice sentences but
`फलियों` in the voice prompt.

**Client:** real field photos (the quality thresholds and the crop prior were tuned on 28 web photos), Zoho org details,
the IoT platform, a few farmers' real phones for a field test.

## C. Not tested here (no device, no Docker, no keys)
- **Android and iOS builds** (no SDK on this PC): no APK, camera, real Hindi TTS, audio playback, secure storage, TalkBack,
  push. 600+ widget tests, analyze and format are clean, and the real client was run against the real backend (31 calls).
- **Docker image never built; PostgreSQL/pgvector never run** (SQLite only). Run `pytest tests/services/test_migrations.py`
  and the pgvector store tests (`PG_TEST_URL`) once, then build the image.
- **Never called for real:** OpenAI (LLM and embeddings), Google TTS, Zoho, FCM, SMS, Open-Meteo.
- **Vision models:** the real crop and disease models run on a laptop CPU in a smoke test (apple named 28/28 with the farmer's
  crop as prior; scab/Alternaria/Marssonina still not separable, so only scab gets automatic advice). The Docker image has no
  ML libraries (stub vision) and the on-device model is not converted (stub). Setting `CROP_ID_PROVIDER=model` needs a torch image.
- **FCM push** needs a Firebase project, `google-services.json`, APNs key (steps in `docs/design-notes/mobile2a.md`).
- Load and performance; a 3 GB Android 9 phone; install size (build with `--split-per-abi`).

## D. Review wave (stopped early at your request)
A correctness/safety review and a security review of the backend ran in parallel and were stopped before they wrote their
final reports; what they had already fixed is in the code with tests (`tests/security/test_hardening.py`,
`tests/api/test_security_hardening_api.py`, `tests/security/test_environment_and_clock.py`, `tests/integrations/test_dotenv_settings.py`):
- text a farmer types into the medicine field could end up in a warning, then in the synthesised audio served publicly at
  `/audio/<hash>.mp3` (a name or phone number would have been published): typed text is now replaced in spoken warnings;
- login-code guessing: parallel guesses can no longer exceed the attempt cap, wrong codes are limited per phone over all of
  its code requests, the admin key limit applies before the comparison;
- `ENV=production`/`prod`-like spellings all count as production, an unknown `ENV` refuses to start instead of running with
  development defaults, the Docker image defaults to prod, production refuses a fixed demo clock;
- bounds: long typed names and app versions, audio file names with a trailing newline, error bodies never echo the input,
  image decoding concurrency, in-memory throttle/cache sizes, log-line injection;
- `ZOHO_*` and `OPEN_METEO_API_KEY` now also work from the `.env` file.
**Not done (checklist items that never ran):** a full JWT/CSRF/admin-XSS pass, a dependency vulnerability audit, a data-deletion
route, prompt-injection tests beyond the ask validator, resource limits on the admin lists. Run a proper security review
before real farmers use it.

## E. Decisions I made for you (veto any)
- **Safety design:** rules decide, the LLM only words it; a draft that deviates is replaced by a fixed template. No approved
  data = no medicine. A healthy result below 0.65 confidence goes to an expert (never "your plant is healthy" on a guess).
- **Crop identification:** two detectors, farmer's own crops as a prior (others at 0.15), ask with tick/cross when unsure;
  the on-device guess is ignored by the server.
- **Offline:** photos and spray entries queue on the phone and are sent when the network returns (safe retries through an
  `Idempotency-Key`; no duplicates). Expert requests are not queued. Items older than 7 days are dropped.
- **Login:** OTP + rotating refresh tokens, one session per device id, replay revokes that device. Rate limits are my numbers
  (OTP 3 per 15 min per phone, scans 30 and questions 20 per 10 min per farmer).
- **Spray diary:** the "I sprayed" tick records the first product of the advice (the one read aloud); typed names are matched
  to the catalogue by exact identity only, ambiguous or unknown names are saved as typed with a soft warning.
- **Voice:** fixed prompts are bundled audio when generated, else server audio, else the phone's voice. Spoken text never
  contains digits or personal data (audio files are public, addressed by a hash of the text).
- **Admin disables a product** and the rules fail closed if that switch cannot be read.
- **Demo clock** is frozen at 12 May 2026 (apple season); a strip on every screen says so. Set `DEMO_CLOCK` empty for real time.
- **Contract:** `contracts/openapi.json` is the API truth; changes stay additive.
- **Test build talks plain http to a PC** on the same Wi-Fi (`usesCleartextTraffic="true"` in the Android manifest, address
  typed in the app: login screen, "Server"). A deployed server needs https; then remove that attribute.
- Tools installed on this PC as a side effect: Flutter (`C:\siva\tools\flutter`), JDK 17 and the Android SDK
  (`C:\siva\tools\jdk17`, `C:\siva\tools\android-sdk`; the Android SDK licence was accepted for you on 19 Oct 2026).

## F. Known limits and tech debt
- Rate limits and idempotency locks live in process memory (one worker); use Redis before scaling out.
- Scan photos can be added to an existing scan from the API but the app sends all photos with the first upload.
- Waiting diary entries show as waiting only until the app restarts (they are still sent).
- Embedding dimension change (hash 512 to OpenAI 1536) needs `DROP TABLE kb_notes`; the Ask relevance threshold (0.25) was
  calibrated with the hash embedder and must be re-calibrated with real embeddings.
- A refresh token replayed within seconds (lost answer on a bad network) revokes that device's sessions; the app now sends
  a per-install device id so only that phone is affected.

## G. Backend tasks of 24 Oct 2026 (weather flag, code standard, admin upload, voice package, offline upload): decisions and doubts
**Decisions I made (veto any):**
- **`WEATHER_ENABLED`** (default true). Off = no lookup, no weather risks/alerts/forecast, no repeat-after-rain timing; advice then says only
  "Ask your expert for the best time to spray" (`timing.action=unknown`, empty rule text). The waiting-period alert still runs. Sensor
  readings are not weather and stay. If you would rather have no timing sentence at all when weather is off, that is a template change.
- **Catalogue bug fixed (not a test artefact):** the audio file hash cache was keyed on (path, mtime, size); on Windows a same-size rewrite
  within the timestamp tick returned the old hash, so a regenerated prompt could keep the old version number and the app would never
  download it. Files modified in the last 3 seconds are now hashed every time (`app/voice/catalogue.py`; the audio store shares the helper).
- **Training photos are stored re-encoded** (cleaned JPEG, long edge at most 2048 px, no EXIF/GPS), the same as scan photos, not as the
  original bytes. Smaller and safe, but a photo is slightly lossy and large originals are shrunk. Say if training needs the originals.
- Duplicate check is by the SHA-256 of the cleaned JPEG, across all classes (the same picture under two labels is refused, with the first label shown).
- "Write into the training folder" never overwrites and appends to `data/training/admin_uploads.csv` (the other agent's `sources.csv` is not touched).
- **Offline scans:** the result is computed when the server receives the photo, not at `taken_at`, because spray timing is about now. A
  `taken_at` more than 1 day in the future or older than 400 days is dropped silently (a wrong phone clock must not lose a photo).
- New API pieces, all additive: `weather_enabled` on `/v1/meta`; `taken_at` and `offline` on `ScanOut` and the scan form; `GET /v1/scans/by-request/{key}`;
  `GET /v1/voice/package?lang=`. The mobile app does not use the last three yet.
- `ruff format` is not configured (it would reformat 226 files), so not applied; mypy is clean (`python -m mypy app`) but not in CI.

**Doubts / not verified:**
- **No real Google TTS call has ever been made.** Request shape, base64 decoding, retries and error handling are tested against a mock
  only. Whether `hi-IN-Neural2-A` exists is unknown until `generate_prompt_audio.py --list-voices` runs with a key (`docs/voice-package.md`).
- The admin pages were rendered and fetched over HTTP on a local server and one rendered to a screenshot (wide layout looked right). A true
  phone-width view was not seen (headless Chrome here has a minimum window width); the CSS has no fixed widths wider than 16 rem.
- The admin training upload takes 20 files per request (body limit = 4 x MAX_UPLOAD_MB + 1 MB). A hundred photos need five batches.
- Scans sent from a long offline queue hit the 30 per 10 minutes limit (429); the app must keep retrying. Raise `scan_farmer` if that is too tight.
- `add photos to a scan` is still not idempotent (the app does not queue it).
- Training photos are not covered by the 365-day photo retention job; they stay until an admin deletes them.
- Postgres was not run: the new migration (0002) was checked against SQLite and the ORM metadata only.

## H. Apple leaf training (24 Oct 2026, owner request: reverses "no model training now")
The owner asked for a small trained apple model and for photos to be downloaded from the internet. Kit: `data/training/` (README there);
result: `data/training/output/apple_leaf_v1/` (weights not committed, rebuilt by the scripts; `model_card.md`, `metrics.json` are). Backend: `DISEASE_MODEL_DIR`
(with `DISEASE_PROVIDER=model`) makes apple answer from this model alone; unset = the downloaded models as before. It is an internal demo model.
- **Numbers (group-disjoint split, 4 classes, 1672 photos):** CV accuracy 0.97, held-out test 0.98. **Do not read this as field accuracy.** Each class comes
  largely from a different imaging source, so part of it is source recognition. Marssonina (99 % recall) has ONE source; the only independent real
  Marssonina photo found (Wikimedia, CC0) was called Marssonina at 0.57 and the other Commons photo was called scab (n=2, anecdotal).
- **Labels are unconfirmed.** Marssonina = the Chinese datasets' "Brown spot" (inferred = *Diplocarpon mali*); Alternaria = "Alternaria leaf spot" (AppleLeaf9)
  and "Alternaria" (Kashmir). Needs the agronomist, same as the test set.
- **Licences:** only CC BY 4.0 sources were used (AppleLeaf9 on GitHub, Kashmir apple dataset on Mendeley), recorded per file in `data/training/sources.csv`.
  Doubt: AppleLeaf9 is a compilation of PlantVillage (CC0), a Chinese segmentation dataset and Plant Pathology 2020/2021 (Kaggle); the compilers declare CC BY 4.0
  for the whole, I did not check the upstream terms of each part. Attribution must be kept (model card does). Photos are not committed.
- **Not found openly licensed:** enough independent Marssonina photos (Wikimedia Commons has 2). No unknown-licence photos were used. `data/images/testset_v1` is not in
  this checkout, so the model was not run on it; run `train_apple.py` again (or `backend/scripts/evaluate_vision.py` with `DISEASE_MODEL_DIR`) where the folder exists.
- **Backbone choice:** ImageNet ConvNeXt-Tiny, frozen, linear head only, not the `ixrbhii` apple weights (trained on the same public datasets: results would not be independent).
- **Only 4 classes:** rust, powdery mildew, frogeye etc. are forced into one of them. Keep the expert-review guards; do not widen automatic advice on this model alone.
- Next step for real accuracy: the client's confirmed field photos (a few hundred per disease) into `data/training/photos/` and retrain.


## J. Recognition failure on the phone and retraining check (26 to 27 Oct 2026)
- **Symptom:** every leaf scanned from the phone ended in "I am not sure what is wrong with your apple crop" (expert queue). Cause: the backend was running the downloaded
  models (crop detectors + `ixrbhii` apple model B + PlantVillage A), not the trained apple model. The weights of `apple_leaf_v1` were never on this machine (git-ignored,
  trained elsewhere), `.env` has no `DISEASE_MODEL_DIR`, and `scripts/start_backend_for_phone.ps1` does not set it. Downloaded models on `data/images/testset_v1` (23 leaves):
  6/23 exact, 11/23 lenient (also calls leaves "Root_rot_collar_rot").
- **Retrained here with the same recipe and data** (2,000 photos fetched again; training dropped 28 exact duplicates, so the training set equals v1): CV 0.975, held-out test 0.979.
  On the 23 test leaves: **13/23** (Alternaria 7/8, Marssonina 6/11, **scab 0/4: all four called Alternaria at 0.87 to 1.0**). Same result through the backend path
  (`DISEASE_MODEL_DIR`). Likely cause (inference): each class comes from a different photo style, so the model learned the style, not the disease.
  **Not switched on:** the start script was not changed, the backend still uses the downloaded models. Open: keep downloaded models, switch to this model, or neither
  until confirmed field photos exist (recommended: neither, plus `RULES_AUTO_ADVICE_DISEASES=` empty so only scab gets automatic advice).
- **Owner decision 26 Oct 2026: the model stays in the backend; no on-device model** (earlier wish for an on-device model is shelved). Offline = photos queue on the phone and are
  sent later (already built); `OnDeviceDetector` stays a stub; no new APK is needed for model changes. `docs/mvp-plan.md` row 14 and requirements FR-1.4 / NFR-5 still describe the
  on-device idea and were not edited.
- **Next step for real accuracy:** confirmed field photos (agronomist labels) through the admin upload / `training_photos`, then retrain.
- Files changed by the retraining: `data/training/output/apple_leaf_v1/metrics.json` and `model_card.md` regenerated (weights are git-ignored); `data/training/sources.csv` +28 rows
  (duplicate files the trainer ignored).
- **Demo model (27 Oct 2026, owner request, for the MVP demo):** `data/training/output/apple_leaf_demo/` = the v1 recipe + the 30 photos of `data/images/incoming` (fruit included),
  marked `internal-only/unknown licence` in `data/training/demo/sources.csv`. **Demo only, never ship.** Honest numbers on its web photos (never trained on them): 9/19 out-of-fold,
  7/8 held-out (tiny). On the 30 photos themselves it is 29/30 because it trained on them. `train_apple.py` got three small changes (`web_` photos first under the cap, source name
  `Web-incoming`, `--eval-dir` replaces the defaults). `scripts/start_backend_for_phone.ps1` now sets `DISEASE_MODEL_DIR` to this model and `RULES_AUTO_ADVICE_DISEASES='*'` (owner decision
  19 Oct) so Marssonina / Alternaria also show advice instead of "Not sure yet". Delete those two lines to go back.
- **Pure-LLM test (gpt-4o-mini only, 30 photos x 3 tests x 3 runs, $0.55):** crop: apple 72 % (leaf photos 67 %; cherry / rose / plum / pear mistaken); open disease question: "Apple scab"
  for ALL 30 photos, Marssonina and Alternaria never even in its "other possibilities"; with a menu of the CV classes: 16/30 (leaf photos 15/21) but scab 1/10; confidence 0.85 right or wrong;
  no healthy photos in the set, so "healthy" detection was not tested. Verdict: CV classifies, the LLM only explains.
- **Shortcut probe on the 2,000 public photos:** 8x8 colour thumbnail 0.77, centre-blanked ConvNeXt 0.94, full photo 0.97 (chance 0.27): the classes leak through background / style.
  `data/training/check_shortcuts.py` repeats it on any photo folder. Guide for the next steps: `docs/model-training-guide.md`.


## G. Mobile session of 24 Oct 2026 (tools, offline, voice package, weather flag)
- **Tools installed on this PC (D:\tools):** Flutter 3.47.7 / Dart 3.13.5 (the planned version), JDK 17.0.20, Android SDK (platforms 35/36, build-tools
  36.0.0, CMake 3.22.1, NDK r28c via Gradle), emulator + Android 15 x86_64 image, AVD `ft35` (`D:\tools\avd`). Steps: `docs/dev-setup.md` section 4.
- **Found and fixed: `mobile/lib/core/storage/token_store.dart` was missing from the repository** (root `.gitignore` had `storage/`). Re-created from its
  callers and tests (`TokenStore`, `StoredTokens`, `InMemoryTokenStore`, `SecureTokenStore` with memory fallback). **Please compare with your original copy.**
  `.gitignore` now says `/storage/`.
- **Bug fixed:** the offline queue was not sent when the network returned while a screen was open over Home (the connectivity listener went through a provider
  that pauses). It now listens to the connectivity stream directly.
- **Added (veto if unwanted):** "Last advice" card on Home (7 days, per farmer, opens from the phone); diary list kept for offline reading; waiting diary
  entries survive a restart in the list; tap on the waiting card = send now; language buttons with a badge letter and a tick (`badge` in languages.json);
  voice package download on Wi-Fi only; `weather_enabled` handling; `kotlin.incremental=false`; build script paths configurable.
- **Not done / doubts:** dark mode skipped (light high-contrast theme only); no UI polish beyond the language buttons because screens after the first were
  not looked at on the emulator; audio cache limit 40 MB (check once real audio exists); the `expert_photos_saved` comment in `expert_screen.dart` still says
  nobody calls back (owner decision since: phone call); a confident "healthy" apple result is spoken with `result_not_disease` ("We could not see a
  disease..."), cautious but it never says "healthy" (needs a new prompt and a native-reviewed Hindi text).
- **Backend requests:** (1) re-run `backend/scripts/dump_api_fixtures.py` so `mobile/test/fixtures/api/meta.json` gets `weather_enabled` from the server
  (added by hand now); (2) for the healthy label consider a dedicated status or spoken text; (3) `scripts/start_backend_for_phone.ps1` still points at
  `C:\siva\tools\python313` (falls back to the venv).


## H. Mobile UI session after the first phone test (24 Oct 2026)
- **Yellow "I sprayed" cause:** the advice screen spoke "If you have sprayed, tap the green tick" (server prompt `diary_tick_sprayed`) but its button was an amber
  notebook with the word "I sprayed"; the green tick only came one screen later (confirm screen). Now the advice button is the green tick, the app always says
  `diary_tick_sprayed` there (a server that still names `result_next_diary` = "notebook picture" no longer causes a mismatch), and once written the tick becomes a green
  "Sprayed" mark (grey "waiting" while the entry is only in the offline queue; kept on the phone per farmer, 50 advices). Yellow is now only for warnings; the
  "Waiting to send" card of Home is grey; crop pictures are blue (they were red/amber/green).
- **Layout:** one slim top bar (back, bell/gear on Home, speaker), no footer; the caption floats over the content only while it is spoken (one line, tap for all);
  only the screen's one main action sits below the content; the demo strip can be tapped away. Home = one big green Scan button + three blue ones. Advice first view =
  severity, medicine, when, warnings; summary, safety notes and steps are behind "More". Touch targets are now at least 56 dp (was 64). A bell badge bug was found: at
  large text the number covered the bell and swallowed the tap.
- **Please veto/decide:** the caption disappears when the speech ends (hearing-impaired users replay with the speaker); the speaker moved from bottom-left to top-right.
- **New strings (Hindi are drafts for the native reviewer):** `advice_sprayed_done` (Sprayed / छिड़काव हो गया), `more_label` (More / और देखें), `less_label`
  (Less / कम देखें); `last_result_card` shortened (Last advice: {date} / पिछली सलाह: {date}). No voice prompt was added or changed.
- **Backend/voice requests:** `result_next_diary` ("tap the notebook picture") is no longer used by the app; the backend may stop returning it (fixtures still have it).
- **Not seen on a screen:** expert result, saved-offline, retake, alert detail, language/settings at 320 dp (layout covered only by the widget audit tests); real phone, real TTS.

## I. Leaf model v2 for the five MVP crops (26 Oct 2026, trained on Kaggle)
The owner asked for a model for the FarmTrack use case, trained with the Kaggle MCP. Result: `data/training/output/farmtrack_leaf_v2/`
(29 catalogue classes for apple, tomato, potato, maize, grape; ConvNeXt-Tiny fine-tuned on a Kaggle T4; script
`data/training/train_leaf_v2_kaggle.py`; card `model_card.md`). Backend change: a `DISEASE_MODEL_DIR` model now answers for every crop
it has two or more classes of (crop mask as for model A), not only apple; `apple_leaf_v1` behaves as before.
- **Field accuracy is the real number:** PlantDoc test (176 web photos of real plants, never trained on) 0.65 top-1, 0.69 disease
  within the right crop, 0.94 crop; Kashmir orchard photos (62) 0.55 within crop, apple scab 7/24 (mostly called black rot).
  Lab-like sources 0.96 to 1.00. Small samples: a direction, not a measure.
- **Confidence is now informative** (PlantDoc test: >= 0.9 right 92 %, < 0.7 about 40 %), unlike the earlier models. Candidate for the
  expert-queue threshold once measured on Himachal photos.
- **Licences (decision needed):** FGVC7/8 (Kaggle competition data) and PlantVillage terms are unclear; the model is an internal demo
  model until reviewed. Retraining without them is possible (would drop most apple field photos).
- **Labels still unconfirmed** (brown spot = Marssonina, Kashmir leaf blotch = Alternaria, frogeye = black rot, rust = cedar rust).
  Marssonina comes from one source only.
- **Not done:** the model was not loaded in the backend on this PC (torch not installed here); the weights' tensor names and shapes
  and the labels were checked. Not run on `data/images/testset_v1` (not in this checkout). Not published as a Kaggle Model.

## K. Place picker on My field: free map, location choice, free weather (28 Oct 2026, owner request)
Built: `GET /v1/weather?lat=&lon=` and `GET /v1/places/search`, both off by default, reported by `/v1/meta`; in the app a "place bar" on My field opens
`/field/place` (search a name, "My location", a touch on the free map). Details: `backend/README.md` and `mobile/README.md` ("Place picker").
- **Free is not the same as allowed for a product:** Open-Meteo's free endpoint is non-commercial (paid plan for production: `OPEN_METEO_API_KEY`);
  OpenStreetMap's public tile server is best effort and not for production use (a tile provider is needed: `MAP_TILE_URL`, `MAP_ATTRIBUTION`);
  the public Nominatim allows 1 request a second for the whole app and forbids search-as-you-type (hence: search on submit, cache, spacing, per-farmer
  limit; self-host for many users). **Decision needed before real farmers:** which tile provider, which weather plan, a Nominatim of our own.
- **Placeholder contact:** `PLACES_USER_AGENT` must carry a real contact (e-mail) of the operator; the demo script has a placeholder. I did not put anyone's address in.
- **Live weather uses the real date, not the demo clock** (the forecast API only serves about 14 days back, 7 ahead): the farmer's own field and the
  advice keep the demo clock, so on the demo server "My field" weather (if `WEATHER_PROVIDER=openmeteo`) and the demo clock can disagree. Not changed here.
- **Not built:** cadastral (plot) boundaries (no public API found for Himachal's Bhu-Naksha; needs the Revenue Department / NIC), a satellite layer, offline map
  tiles, saving the chosen place, the credit's link to openstreetmap.org/copyright (needs `url_launcher`), iOS location text in `Info.plist`.
- **Hindi is a draft** for the new words (`field_place_*`, `place_*` in `strings.json`) until a native speaker reviews them. Place names come from OpenStreetMap in the app's language when it has them.
- **Checked live (28 Oct 2026):** Open-Meteo through the adapter for Theog, Kullu, Kalpa, Dharamshala, Rohru (about 150 ms, cached 1 ms); Nominatim for Theog,
  Kullu, Himachal Pradesh, Shimla in Hindi, Kotgarh, Rohru, Manali (Theog comes back as a "county" = tehsil, so the app has a `tehsil` kind).
  Not checked: a real phone, the GPS permission dialog, real tile loading, heavy use.
- **Home location button and real names (28 Oct 2026, after the first phone test):** the location line of Home opens the picker; the choice is kept on the phone
  per farmer. A point touched on the map and the phone's position were first shown as "A point on the map" / "My location": they are now named by their
  area through `GET /v1/places/reverse` (Nominatim reverse, zoom 13, e.g. "Janog, Theog, Shimla, Himachal Pradesh"; checked live on Theog, Kotgarh, Kullu, Kinnaur).
  Doubts: (1) the nearest named village is OpenStreetMap's, not always the village the farmer would say; (2) in Hindi, a village without a Hindi name stays in
  English and the district can appear in both scripts ("Kullu, कुल्लू"); (3) the pick (with its coordinates, also GPS ones) is stored in the phone's plain
  preferences; (4) the public Nominatim limit (1 request a second for the whole app) is shared by search and reverse: self-host before many farmers use it.

## L. "Current weather" details: feels like, wind, visibility, pressure, dew point, air quality (29 Oct 2026, owner request)
The owner showed Microsoft Weather's "current weather" card and asked for the same kind of details. Backend: `conditions` on `GET /v1/field` and
`GET /v1/weather` (see `backend/README.md`); the app side is a separate change.
- **Checked live (29 Oct 2026, Kotgarh 31.30, 77.47):** the forecast call with the extra hourly variables answers 200 and the adapter gave
  `{"sky":"clear","is_day":true,"feels_like_c":16.7,"wind_kmh":0.4,"visibility_km":10.7,"pressure_hpa":1017.7,"dew_point_c":10.1,"aqi":47}`; the
  air-quality API answered `current.us_aqi: 47`. The commercial host `customer-air-quality-api.open-meteo.com` exists (401 "API key required"
  without a key) but was NOT tried with a key.
- **Doubts:** (1) pressure is mean-sea-level, like a weather app; at a Himachal field at 1700 m the real surface pressure is about 200 hPa lower
  (`surface_pressure` is available if wanted). (2) The AQI is the US scale (0-500) taken from a modelled grid (CAMS), not from a sensor; Himachal
  valleys can differ from the grid. A farmer-friendly word (Good / Moderate / ...) and its colours are the app's job, the server sends only the number.
  (3) Wind speed is the 10 m wind, no direction and no gusts yet. (4) Same non-commercial licence as the rest of Open-Meteo, and CAMS asks for
  attribution where its data is shown (the app has no such credit line yet). (5) One more outbound request per place per 30 minutes (the field
  screen only, same 600-calls-an-hour budget); a slow air-quality API cannot delay the page by more than 3 s, and a failure is not retried for
  5 minutes. (6) WMO code 97 ("heavy thunderstorm", in Open-Meteo's table) is mapped to `thunderstorm` although it was not in the agreed list; the
  sky word is a coarse mapping (e.g. freezing drizzle is "drizzle", snow grains are "snow"), not a forecast text. (7) "Feels like" is Open-Meteo's
  apparent temperature (wind, humidity and sun included), not a measurement.

## M. Weather map: radar, clouds, rain amount (29 Oct 2026, owner request: "a map like zoom.earth, free and open source")
Built in the app only (`/field/map`, see `mobile/README.md`). Zoom.earth itself is not open source and no open clone exists; the layers come from
three free sources that need no key. Checked live on 29 Oct 2026: RainViewer's list and a radar tile (200), its coverage mask at Shimla, Kotgarh,
Kullu, Dharamshala and Kalpa (inside a radar circle), NASA GIBS tiles for `Himawari_AHI_Band13_Clean_Infrared` and `IMERG_Precipitation_Rate_30min`
(200; a moment that does not exist yet is 404; HEAD works), a storm over Delhi and Jaipur visible in both. Not checked: a real phone, heavy use.
- **Licences (decision needed before real farmers):** RainViewer's free tier is "personal, educational and small-scale community use", no SLA,
  not for high-volume commercial apps (since 1 Jan 2026: past radar only, zoom 7, 100 requests per IP per minute; satellite and forecast frames are
  gone, the live list shows them empty). NASA data is open, but I did not read GIBS's terms page and Himawari is originally the Japan Meteorological
  Agency's. OpenStreetMap's tile server is the same as for the place picker (section K). A paid RainViewer plan or another radar is the
  production route.
- **Doubts:** (1) Radar in the hills: coverage circles do not mean valley coverage (beam blocking); the farmer sees "no rain" where radar is blind.
  (2) Himawari looks at India from the edge of its view, so clouds over Himachal are stretched; I did not judge the picture over Himachal, and the
  infrared picture is a grey wash that needs the legend (white / blue = thick or tall cloud). (3) The rain amount picture is about six hours old (IMERG
  early run) and is labelled with its age; it says "measured from space", not forecast. (4) No forecast layer at all (no source found that is free
  and keyless; Open-Meteo has no raster tiles). (5) No wind, temperature or pressure layers: OpenWeatherMap's tiles do those but need a key and
  its free-plan limits and commercial terms were not confirmed. (6) The phone reaches these servers directly, so each farmer's phone address and
  the area looked at are visible to them; the server API is not involved. (7) Each source's credit is drawn as one line on the map; there is no link
  to the licences (no `url_launcher` yet). (8) Needs internet; offline it shows the message and an empty map (the app has no offline map tiles).
- **Hindi is a draft** for the new words (`weather_map_*` in `strings.json`), including "पूर्वाह्न / अपराह्न" for am / pm: a native speaker should choose
  what farmers say.

## N. Home, weather first ("option B", 29 Oct 2026, owner request: "use this design")
The owner chose option B of the two pictures in `docs/design/` (`home-now-in-your-field-proposal-b.html`, with `.png`). Home now shows, under the
camera card: one big weather card (the colour follows the sky), the next hours, "Can I spray today?", the rain of the week as a chart, and the
details of the air and the sun; "Last advice" moved below the weather. Pictures: `docs/app-screenshots/real-app/home-weather-*.png`. Code:
`mobile/lib/features/home/home_weather.dart`; server: `hours`, `spray` and the sun / UV fields of `conditions` (`backend/README.md`).
- **Decisions to veto:** (1) **Home follows the header place**: with a chosen place the weather, the heading ("Now at this place") and the new
  blocks are that place's (before, Home always showed the own field's numbers whatever the header said). (2) The leaf-wetness reading is no longer on
  Home (it stays on My field); with weather off, or an answer without a temperature, the old white card of sensor readings (soil) is shown instead.
  (3) The glass boxes inside the big card are DARK glass (black at 14 percent), not white as in the picture: white glass made the white words fall
  below 4.5 to 1 on the lighter blue. The bottoms of the five sky gradients were darkened a little for the same reason (`test/home_weather_test.dart`
  checks every one). (4) The hours strip drops hours that are over, and the spray check is never shown for an answer kept on the phone (it would say
  "good time" about weather that has gone). (5) A touch on the spray card and on the rain sentence makes the voice say the answer in words without digits.
- **The spray check is a draft rule, not agronomy:** the thresholds (wind 15 and 30 km/h, heat 32 and 40 degrees, rain 0.5 mm within 3 hours "not now",
  within 6 hours "be careful") are the server's defaults, configurable (`SPRAY_*`), and the check is OFF unless `SPRAY_WEATHER_ENABLED=true` (the phone demo
  script turns it on). **An agronomist must approve the thresholds and the words before real farmers see it.** It tells the weather part only; it does not know the
  product (for example dodine above 30 degrees is a product rule, not part of this check), the stage of the crop or the waiting periods.
- **Real data:** the hours, UV, sunrise and sunset come from the same Open-Meteo call as the rest (free endpoint, non-commercial, see K and L); the rain chance is
  the model's probability, not a measurement. The sunrise and sunset are at the place of the weather, shown on the phone's clock.
- **Hindi is a draft** for about 60 new words (`home_*`, `spray_*`), including "पूर्वाह्न / अपराह्न" in the hours strip (long for a narrow column: a native
  speaker may prefer "सुबह / शाम").
- **Not verified on a phone with real farmers:** the card colours in strong sun, the size of the text in the hours strip for older eyes, whether the spray words
  are understood.
- **Checked live (29 Oct 2026, 22:15, phone build v14):** the demo server (restarted with the new code and `SPRAY_WEATHER_ENABLED=true`) answered `/v1/field` (own field, Kotgarh: night, 9 degrees, `spray` go) and `/v1/weather` for a point near Chennai (`spray` care, windy 15.2 km/h); the phone showed both on Home (`docs/app-screenshots/real-app/phone-home-weather-*.png`). The hours are whole hours of the Indian clock, so in UTC they end in :30 (22:00 in India is 16:30Z); the app shows them on the phone's clock. Backend tests 3298 passed, 12 skipped; app tests 937 passed.

## O. Diary: crop circles, this week, timeline (30 Oct 2026, owner request: "use the second design")
The owner chose design 2 of `docs/design/diary-combined-proposals.html` (with `.png`; the first board is `diary-proposals.html`): the diary page is no longer a plain
list. From the top: **crop circles** (All, then one round photo for each crop in the diary; a touch shows only that crop and says its name; shown only when there
is more than one crop), **"This week"** (the last seven days, a dot for each spray, today in solid green; the whole card is a button that opens the month),
a **month sheet** (a calendar with a dot on each day sprayed, "Sprays / Crops / Last", arrows to earlier months as far back as the first entry, a speaker that
says the count in words, "Done"), and the **timeline** (a thread, a big circle for each day, a card for each spray). Code: `mobile/lib/features/diary/diary_timeline.dart`
and the new `DiaryEntryCard` in `diary_widgets.dart`; tests `mobile/test/diary_timeline_test.dart` and `diary_list_test.dart`; pictures
`mobile/test_visual/diary_timeline_shots_test.dart`. No server change: everything comes from what the diary already has.
- **Decisions to veto:** (1) **The days of the strip and of the month calendar are not touch targets** (seven columns cannot be 56 dp wide; the app's rule is
  56 dp for everything that is touched), so a touch on the strip opens the month and a touch on a calendar day does nothing. The design's "touch a day to jump to it"
  was left out for that reason; the timeline is right below. (2) **The warnings of an entry are always on its card** (before, they were inside until it was opened);
  the brand and the steps (take, mix in water) still open on a touch. (3) **The "wait" tag is grey, not amber** (amber stays for warnings); an entry whose medicine has
  no waiting days has no such tag, and the app never says a crop is "safe to pick" (the "Can I pick?" card of design 2 of the first board was not chosen).
  (4) The crop circles keep the order "crop sprayed last first"; with one crop there are no circles. (5) The old "Today / Yesterday" capital headings are now a bold word
  and the weekday or date beside it ("Today Tuesday", "Friday 8 May").
- **Limits:** the page and the counters cover the last 50 entries (what the diary asks the server for); an older month shows no dots. The type tag
  (Fungicide, Insecticide, Mite killer, Bacteria killer, Oil spray) is shown only for the five categories the server uses; any other category has no tag.
- **Hindi is a draft** for 24 new words (`diary_*`, `advice_dose_chip`): "This week", "Month", the counters, the spoken month sentences ("You sprayed four times in May"),
  the five kinds of medicine ("माइट नाशक", "जीवाणुनाशक", "तेल वाला छिड़काव" are the least certain) and "saved" ("लिखा गया"). A native speaker should read them.
- **Also in this change:** on Home the heading row shows the **short name of the place** (the first part: "Navalur" of "Navalur, Thiruporur"; "…" when it does not fit)
  where the green "Open my field" link used to be; the big weather card still opens My field. The word `home_open_field` was removed.
