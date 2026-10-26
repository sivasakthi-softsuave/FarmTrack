# How to prepare, label, train and check the apple disease model (beginner guide)

Written 27 Oct 2026 for the person who has to run this and has never trained a model before. Read it top to bottom once, then use
the checklists at the end. Every command and file name below exists in this repository today. Numbers marked *(estimate)* are my
estimates, not measurements. Nothing here is a promise of accuracy.

---

## 0. The short version

1. A model learns from **photos that already have the right answer written on them**. We call the answer a **label**.
2. The model can only be as good as (a) how **correct** the labels are and (b) how **much the training photos look like the photos
   farmers will really take**. The program and the model type matter much less. This project already proved it: models that scored
   97 to 99 % on their own test photos got about half of real web photos right.
3. For the MVP (apple, 3 diseases) you need, per class, about **400 photos of different leaves from different trees**
   (300 to train, 100 locked away for testing), labelled by an **agronomist**, in the **same kind of photo** for every class.
   With 5 classes (scab, Marssonina, Alternaria, healthy, other) that is about **2,000 photos**.
4. The work is mostly **people work** (taking photos, labelling, checking), not computer work. Training itself takes minutes to an hour.
5. Order of work: decide classes -> collect photos -> label -> split into train/test -> check for shortcuts -> train -> test honestly
   -> put into the app -> collect more and repeat.

---

## 1. Words you will meet

| Word | Plain meaning |
|---|---|
| **Class** | One possible answer: "Apple scab", "Marssonina blotch", "healthy" ... |
| **Label** | The correct class written on a photo (in a file name, folder, or sheet). |
| **Training** | Showing the model many labelled photos so it adjusts itself to give the right answer. |
| **Model / weights** | The result of training: one big file (`model.safetensors`, about 56 MB here) that turns a photo into class probabilities. |
| **Training set** | Photos the model is allowed to learn from. |
| **Test set** | Photos kept away from training and used only to measure the model honestly. **Locked**: never trained on, never used to tune. |
| **Accuracy** | Share of photos answered correctly. |
| **Recall** (per class) | Of all real scab photos, how many did the model find? |
| **Precision** (per class) | When the model says "scab", how often is it right? |
| **Confusion matrix** | A table showing which class gets mistaken for which (very useful: it shows scab being called Alternaria). |
| **Overfitting** | The model memorised its training photos and fails on new ones. |
| **Shortcut** | The model learns something easier than the disease, e.g. "yellow leaf on white paper = Marssonina". It scores well and is useless in the field. |
| **Domain shift** | Training photos and real photos look different (lab vs orchard, camera, light). The biggest problem in this project. |
| **Frozen backbone / fine-tuning** | Frozen: keep a ready-made image model unchanged and train only a small last layer (fast, safe with little data). Fine-tuning: adjust the whole model (needs more photos, slower, usually better). |
| **Confidence** | The number the model gives with its answer (0 to 1). Only useful if it was checked against real results. |

---

## 2. What we are building

- **Goal:** the farmer photographs an apple leaf; the backend says which disease it is (or "not sure" / "healthy"), then the rules
  engine picks the medicine from the approved list.
- **Where the model lives:** in the **backend** (owner decision 26 Oct 2026). The phone only uploads the photo. No new app build is
  needed when the model changes.
- **Classes for the MVP:**

| Class id (used in files and the app) | Meaning |
|---|---|
| `Apple___Apple_scab` | Apple scab |
| `Apple___Marssonina_blotch` | Marssonina blotch |
| `Apple___Alternaria_leaf_spot` | Alternaria leaf spot / blotch |
| `Apple___healthy` | Healthy leaf |
| *other / not sure* | Anything else, and photos that are not a clear leaf. **Needs a small code change** (see 9.3): today the training script knows only the first four. |

Why "other" matters: powdery mildew, frogeye, rust, nutrient problems, spray burn and insect damage also make spots. Without an
"other" class the model must force them into one of the three diseases and the app then gives wrong medicine advice.

---

## 3. Who does what, and what to prepare

### People
| Role | Job | Rough time *(estimate)* |
|---|---|---|
| **Agronomist (must have)** | Writes the class definitions; diagnoses in the orchard; labels and re-checks photos | Definitions: half a day. Labelling: about 10 to 15 seconds per photo, so 2,000 photos is 6 to 8 hours, double if two people label |
| **Field staff / farmers with phones** | Take the photos following section 5 | Depends on season and number of orchards |
| **Developer (you)** | Folders, label files, run the scripts, read the results | A few hours per training round |

### Tools
- A phone camera (several different phones is **good**: farmers use different phones).
- A shared sheet (Excel / Google Sheet) for labels: columns in 6.3.
- This PC: Python environment already set up in `data\training\.venv` (CPU, enough for the small model).
- Optional, free: a **Kaggle** account for a GPU (section 9.2).
- A safe place to keep the **weights and model card** (shared drive). The 24 Oct weights were lost because they were only on another PC.

### Permission and licence (do this before collecting)
- Photos taken by FarmTrack staff or farmers: get **written permission** that the photos may be used to train the model. Record it
  as licence `client-owned` in the sources file.
- Photos from the internet: only if the licence allows it (CC BY, CC0). Unknown-licence photos are for an **internal demo only**
  and must never go into a model that farmers or the client will use.
- Do not photograph people's faces; photos are cleaned of GPS data by the backend admin upload, but keep location in your own sheet.

---

## 4. Step 1: decide the classes (with the agronomist)

Sit with the agronomist and write, for each class, **one paragraph of what the leaf looks like** and **one list of what it is NOT**.
The draft below comes from the project notes and common descriptions. **It is a draft: the agronomist's wording replaces it.**

| Class | Draft description in plain words | Often confused with |
|---|---|---|
| Apple scab | Olive-green to brown, soft or velvety spots with fuzzy edges on leaves; later dark and rough. On fruit: hard, dark, cracked patches. Cool, wet spring. | Alternaria, Marssonina, frogeye |
| Marssonina blotch | Small dark brown to purple-black spots that grow into larger blotches; the leaf turns yellow around them, sometimes leaving dark green "islands"; leaves fall early. Monsoon and late summer. | Alternaria, scab |
| Alternaria leaf spot | Round brown spots, often with a darker ring or reddish edge; can be orange-brown. Monsoon (June to August). | Marssonina, frogeye, rust |
| Healthy | Normal colour and shape; only natural variation (veins, slight colour change). | Early disease with tiny specks |
| Other / not sure | Powdery mildew (white powder), frogeye (ringed spots, pale centre), rust (orange spots), nutrient shortage, spray burn, insect or hail damage, a blurry photo, not a leaf. | everything |

Also decide with the client:
- How many wrong answers are acceptable per disease (a wrong medicine is worse than "ask the expert").
- That **low-confidence answers go to the expert queue** (the app already has it).

---

## 5. Step 2: collect the photos

### 5.1 How to take one good photo (give this page to field staff)
1. **One leaf** in the photo, filling about two thirds of the picture, **whole leaf visible** (edges included).
2. **Natural light**, no flash. Avoid hard sun shadows across the leaf. Not in the dark.
3. **In focus**: tap the leaf on the screen, hold the phone about 20 to 30 cm away, hold still.
4. Mostly **on the tree** the way a farmer would do it (also some plucked leaves). Do not clean, arrange or edit the leaf.
5. Upper side of the leaf. A second photo of the underside is welcome.
6. **At most 3 photos of the same leaf** (different angles). More makes the test look better than it is.
7. Do not use filters, editing apps or "beauty" modes. Keep the **original file** (WhatsApp-compressed copies only as an extra set).
8. Take photos with **different phones**.

### 5.2 What the photo set must look like
| Rule | Why |
|---|---|
| **Every class photographed in the same way** (same phones, same kind of background, same light) | Otherwise the model learns the background, not the disease. This is the #1 mistake. |
| **Healthy leaves from the same orchards and trees** as the diseased ones | Otherwise "orchard photo" = disease. |
| **Many trees and orchards**: at least 30 different trees across several orchards per class | One tree gives many near-identical leaves. |
| **Different growth stages, dates and weather** | Diseases look different early and late. Collect through the season (the project plan says March to August 2027). |
| **Different severity**: early, medium, heavy | Farmers photograph early disease too, and it is the hardest. |
| **Include the hard photos**: shadow, two leaves, hand in frame, slightly blurry | Farmers will send them. |

### 5.3 How many (per class)
| Stage | Photos per class | What it tells you |
|---|---|---|
| Pilot | about 100 | Only whether the idea can work. Results are very rough. |
| **MVP minimum** | **about 400** = 300 train + 100 locked test | A usable first model. 5 classes = about 2,000 photos. |
| Comfortable | 800 or more | Better; each doubling helps less. |

- "Photos" means **different leaves**. Three angles of one leaf is still one leaf.
- The **test set** needs about 100 per class to be believable: with 100 photos the margin of error is about plus or minus 8 points
  (with 19 photos, as in our first test, it was plus or minus 22).
- "Other" needs at least as many photos as a disease, because it is a mix of many things.
- Public datasets (already used) can give the model a start, but **never use them as the test set**.

### 5.4 Ways to get photos into this project
1. **Admin site -> Training photos** (`/admin/training`): upload up to 20 photos at a time, choose the class, fill `crop`, `leaf_id`,
   `source`, `licence`, `confirmed_by`. Then press **"Write into the training folder"**: it copies the photos to
   `data\training\photos\<class_id>\adm_<code>.jpg` and appends their rows to `data\training\admin_uploads.csv` (append these rows to
   `data\training\sources.csv`). Admin address: `http://127.0.0.1:8005/admin` while the start script runs; the key is `ADMIN_API_KEY`
   from your `.env` (development default `dev-admin-key`).
2. **Admin site -> Farmer photos** (`/admin/uploads`): the photos farmers send with their scans. They are real field photos; after an
   agronomist labels them (via the expert queue or by hand) they can be added to the training set.
3. **Copy files by hand** into `data\training\photos\<class_id>\` and add one row each to `data\training\sources.csv`
   (columns `file, class, source_url, licence, author, note`).

Photo names: any, but keep the original file and add `leaf_id` (a code for the physical leaf) and, in your own sheet, `tree_id`,
orchard, date.

---

## 6. Step 3: label the photos (the most important step)

### 6.1 The golden rule
**Label in the orchard, not from the photo.** The agronomist looks at the real leaf and tree, says the diagnosis, and the field
person writes it down at once. A label guessed later from a small photo is much less reliable (even experts disagree on spots
that look alike). The photos in `data\images\incoming` were labelled by folder name by whoever collected them and **no agronomist
confirmed them**; that is why the results cannot be trusted.

### 6.2 Process
1. Photograph the leaf (5.1) and write the **label immediately** in the sheet next to the photo number.
2. Use only the class ids from section 2, plus `unsure` when the agronomist is not sure.
3. **Second check:** a different agronomist (or the same one a week later) re-labels a random 10 % of the photos without seeing the
   first label. If they agree on fewer than about 90 %, the class definitions (section 4) are unclear: fix the definitions first.
4. Photos marked `unsure`, or where the two checks disagree, are **left out of training** (or put in "other").
5. Keep the sheet; it is part of the data.

### 6.3 The label sheet (one row per photo)
The project's own template is `data\images\labels_template.csv`, columns:

`filename, crop, label, confirmed_by, leaf_id, plant_id, photo_date, location, source, notes`

| Column | Write |
|---|---|
| `filename` | exact photo file name |
| `crop` | Apple |
| `label` | one class id, or `unsure` |
| `confirmed_by` | the agronomist's name (not `unknown`) |
| `leaf_id` | one code per physical leaf (all photos of that leaf share it) |
| `plant_id` | the tree code (**fill this in**; it is what lets you split train and test by tree) |
| `photo_date`, `location`, `source` | date, village/orchard, phone model |
| `notes` | "two leaves", "early stage", "hand in frame" ... |

### 6.4 Label quality checks you can do alone
- Open each class folder as thumbnails: do the photos in a class look like the same thing? Remove clear mistakes (do not relabel guesses).
- Count photos per class, per orchard, per phone. If one class comes mostly from one orchard or phone, collect more elsewhere.
- Never copy the folder name of a downloaded dataset as a label without writing in the sheet where it came from.

---

## 7. Step 4: split the photos into train and test

- **Training photos** go to `data\training\photos\<class_id>\`.
- **Locked test photos** go to `data\training\external_test\<class_id>\` (it is git-ignored, so private). The training script
  reports the model's score on these automatically and **never trains on them**.
- **Split by tree and by day, not by photo**: all photos of one tree go to training **or** to test. A good test set comes from
  **orchards and dates the training photos did not come from**. (The script's own internal 20 % split groups by visual similarity,
  not by tree, so treat that number only as a sanity check.)
- Do not look at the test photos to "fix" the model. If you tune on the test set it is no longer a test.

Folder layout:
```
data\training\photos\Apple___Apple_scab\          training photos of scab
data\training\photos\Apple___Marssonina_blotch\
data\training\photos\Apple___Alternaria_leaf_spot\
data\training\photos\Apple___healthy\
data\training\external_test\Apple___Apple_scab\   LOCKED test photos (never trained on)
...
data\training\sources.csv                          one row per training photo: where it came from, licence, author
```

---

## 8. Step 5: check the photos for shortcuts, before training

New script: `data\training\check_shortcuts.py`. In PowerShell:
```
cd C:\siva\Research\FarmTrack\data\training
.venv\Scripts\python check_shortcuts.py
```
It trains three quick tests and prints accuracy for each (a few minutes):
- **A**: only an 8x8 colour thumbnail of each photo (no disease can be seen).
- **B**: the model sees the photo with its **centre blanked**, so only the frame and background are visible.
- **C**: the full photo.

**How to read it:** A and B should be **close to chance** (1 divided by the number of classes, or the share of the biggest class).
If **B is close to C**, the photos give the answer away through background or style: **stop and fix the collection (5.2)**, do not train yet.
On the public photos used so far: chance 0.27, A 0.77, B 0.94, C 0.97, so that data is **not clean**, which is why models trained on
it fail on new photos.

---

## 9. Step 6: train

### 9.1 Route A: on this PC (CPU), small and safe: `train_apple.py`
It keeps a ready-made image model (ConvNeXt-Tiny) frozen and trains only a small last layer. Good for a few hundred to a few thousand
photos. About 20 to 30 minutes on this PC.
```
cd C:\siva\Research\FarmTrack\data\training
.venv\Scripts\python train_apple.py --out output\apple_leaf_v3
```
- `--out` = a **new** folder name each time (never overwrite a model you may need). Keep the old ones.
- It drops unreadable photos and exact duplicates, groups near-copies, holds 20 % aside, runs 5-fold cross-validation, scores
  `external_test\` (your locked photos), and writes `model.safetensors`, `config.json`, `metrics.json`, `model_card.md`.
- Use `--quick` first (about 1 minute) to check that everything runs.
- If you add the test photos to `photos\` by mistake the score is meaningless: keep them apart.

### 9.2 Route B: on a free GPU at Kaggle: `train_leaf_v2_kaggle.py`
A teammate trained **model v2** this way (29 classes, five crops, ConvNeXt-Tiny fully fine-tuned, about 50 minutes on a T4 GPU).
Use it when you have thousands of photos and want fine-tuning. Steps are in `data\training\README.md`, section "v2". Its model card
is `data\training\output\farmtrack_leaf_v2\model_card.md` (read it: field accuracy was only about 65 to 69 %).
The weights stay in the Kaggle notebook output; **download `model.safetensors` and keep a copy** (the repo does not store it).
*(Note: the path example in that README lost its backslashes; type the path yourself.)*

### 9.3 Adding the "other / not sure" class
Today `train_apple.py` has the four classes hard-coded (`CLASSES` near the top). Adding a fifth needs a small code change plus a class
id the backend knows. Ask the developer to do it with you; do not edit by hand without testing.

### 9.4 Which route when
| Photos you have | Use |
|---|---|
| under 300 per class | Route A (frozen). Fine-tuning would overfit. |
| 300 to 800 per class | Route A first; Route B if the test score is not enough. |
| over 800 per class and a locked test set | Route B (fine-tune on a GPU). |

Cost *(estimate)*: Route A is free (your PC). Route B on Kaggle's free tier is free; a paid GPU run for this size is very small money.

### 9.5 After every training run
1. Read the new `model_card.md` and `metrics.json`.
2. **Copy `model.safetensors` and the model card to the shared drive**, with the date and the photo counts.
3. Write down the SHA-256 of the weights file (PowerShell: `Get-FileHash model.safetensors`).

---

## 10. Step 7: test honestly and read the result

Look at, in this order:
1. **The locked test set** (`external_test`): the only number that matters. Ignore "CV accuracy" and "held-out test" if the
   training photos came from the same datasets; they are optimistic.
2. **Per class recall and precision**, and the **confusion matrix**. Ask: which disease is being called which? (Scab called Alternaria?)
3. **Accuracy by source / orchard / phone**: if it is great on one and bad on another, it learned the source.
4. **Confidence**: group test answers by confidence (e.g. above 0.9, 0.7 to 0.9, below 0.7) and check the accuracy of each group.
   If high confidence is not clearly more accurate, confidence cannot be used. Then choose the **"not sure -> expert" threshold** from
   this table, not by feeling.
5. **Error bars**: with 100 test photos per class expect about plus or minus 8 points. Do not celebrate or panic over 2 points.

What "good enough" means is a business decision. A starting point I suggest *(my suggestion, no standard)*: for a disease that gets
automatic medicine advice, about 85 % precision on the locked test set; everything below goes to the expert queue.
Do not promise 90 to 95 %. Plantix, a commercial product, advertises about 73 to 74 % on field photos, and the public models here got
about 50 to 70 % on field photos.

---

## 11. Step 8: put the model into the app

The backend loads a model folder (needs `model.safetensors` + `config.json`). In `scripts\start_backend_for_phone.ps1` the lines are:
```
$env:DISEASE_PROVIDER = 'model'
$env:DISEASE_MODEL_DIR = Join-Path $root 'data\training\output\<your model folder>'
```
1. Stop the running backend (Ctrl+C in its window) and start the script again.
2. Test with photos the model **never saw** (the locked test set) and look at the app's answers.
3. To go back, delete the `DISEASE_MODEL_DIR` line and restart (the downloaded models answer again).
4. Medicine advice for a disease only appears if it is allowed by `RULES_AUTO_ADVICE_DISEASES` (default: scab only; `*` = every
   disease with chemical control). A wrong disease means wrong medicine advice, so widen it only after the test results justify it.
5. A model trained with unknown-licence photos is **demo only**. Its model card says so; keep it that way.

---

## 12. Step 9: keep improving (the loop)

1. The expert queue collects the cases the model was unsure about.
2. The agronomist labels them (this gives the hardest and most useful photos).
3. Add them to `photos\` (admin upload or by hand), update `sources.csv`.
4. Run the shortcut check (section 8), retrain (new `--out`), test on the locked set, compare with the previous model.
5. Only replace the model in the app if it is better on the **locked** test set and not worse on any single disease.
6. Keep adding photos each season; diseases and weather change.

---

## 13. Mistakes this project already made (so you can skip them)

| What happened | Lesson |
|---|---|
| Models scored 97 to 99 % on their own test photos but about half on real web photos | Only a locked, different-source test set tells the truth |
| Each class came from a different photo source, so the model learned the source (an 8x8 thumbnail alone gave 77 %) | Photograph every class the same way; run the shortcut check |
| Old model said "scab" for 22 of 30 photos; the new model said "Alternaria" for most | A model that cannot tell diseases apart picks one catch-all answer. Look at the confusion matrix, not only accuracy |
| The 30 collected photos became both the test and (later) training photos | A photo cannot be both. Their score became meaningless |
| Labels were folder names chosen by the collector | Agronomist labels, in the orchard |
| The first test had 19 photos | Needs about 100 per class for a believable number |
| Trained weights were left on another PC (not in git) | Copy the weights and model card to a shared drive every time |
| A "healthy" class was missing from the LLM test, so "always diseased" scored 100 % | Always include healthy and "other" photos |
| Public photos of unknown licence went into a demo model | Record the licence of every photo; unknown = demo only |

---

## 14. Numbers cheat-sheet

| Question | Answer |
|---|---|
| Photos per class for a usable first model | about 400 (300 train + 100 locked test) *(rule of thumb; the project plan says "a few hundred per disease")* |
| Total for scab + Marssonina + Alternaria + healthy + other | about 2,000 |
| Minimum different trees per class | 30, from several orchards |
| Photos of one leaf | at most 3 |
| Agronomist labelling time | 10 to 15 seconds per photo *(estimate)*; 2,000 photos = 6 to 8 hours |
| Re-check | a second person labels 10 % blind; aim for 90 % agreement or better |
| Training time, Route A (this PC) | 20 to 30 minutes |
| Training time, Route B (Kaggle T4) | about 50 minutes for the large v2 run |
| Margin of error of a test with 100 photos per class | about plus or minus 8 points |
| Realistic accuracy on real field photos | roughly 60 to 75 % *(public models: 50 to 70 %; Plantix advertises 73 to 74 %)*; not 90 to 95 % |

---

## 15. Checklists

**Before collecting**
- [ ] Agronomist's class definitions written (section 4)
- [ ] Written permission to use the photos for training
- [ ] One-page photo instructions given to field staff (5.1)
- [ ] Label sheet ready (6.3), with `plant_id` filled for every photo
- [ ] Plan to photograph healthy and "other" leaves from the same trees

**Before training**
- [ ] Every photo has a label confirmed by an agronomist, a `leaf_id`, a tree, a date, and a `sources.csv` row with licence
- [ ] 10 % re-labelled by a second person; agreement written down
- [ ] Photos of one tree are all in train or all in test
- [ ] Locked test photos are in `external_test\` and nowhere else
- [ ] `check_shortcuts.py` run: A and B near chance
- [ ] Old model's weights and card are backed up

**Before putting a model in the app**
- [ ] Locked test result read per class (recall, precision, confusion matrix)
- [ ] Confidence groups checked; "not sure" threshold chosen from them
- [ ] Better than the previous model on the locked test and not worse on any disease
- [ ] Weights and model card copied to the shared drive; SHA-256 noted
- [ ] Licence status of all training photos known (unknown = demo only)

---

## 16. Where things are in this repository

| What | Where |
|---|---|
| Training kit and its README | `data\training\` |
| Train on this PC | `data\training\train_apple.py` |
| Train on a Kaggle GPU (model v2) | `data\training\train_leaf_v2_kaggle.py` |
| Shortcut check | `data\training\check_shortcuts.py` |
| Training photos / locked test photos | `data\training\photos\<class>\` / `data\training\external_test\<class>\` (git-ignored) |
| Photo provenance and licence | `data\training\sources.csv` |
| Trained models and their model cards | `data\training\output\<model name>\` (weights are git-ignored) |
| Label sheet template | `data\images\labels_template.csv` |
| Admin upload page | `/admin/training` and `/admin/uploads` (backend README, "Admin: training photos") |
| Start the backend with a model | `scripts\start_backend_for_phone.ps1` (`DISEASE_MODEL_DIR`) |
| Which diseases get medicine advice | setting `RULES_AUTO_ADVICE_DISEASES` (`backend\app\rules\policy.py`) |
| Test results and decisions so far | `docs\open-questions.md` (sections H and I), `docs\research\cv-models.md` |
