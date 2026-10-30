# FarmTrack leaf model v3 (`farmtrack_leaf_v3`)

Internal demo model, trained 29 Oct 2026 on a Kaggle T4 GPU (notebook `sivasakthims/farmtrack-leaf-v3-training`, private; script
`data/training/train_leaf_v3_kaggle.py`). It is v2 ([../farmtrack_leaf_v2/model_card.md](../farmtrack_leaf_v2/model_card.md)) with 391
Tomato-Village leaf photos added. **Not field-validated. Labels not confirmed by an agronomist. Licence review pending: do not ship
to farmers on these weights.**

## What it is

Same as v2: ConvNeXt-Tiny (timm `convnext_tiny`, from `convnext_tiny.fb_in22k_ft_in1k`), fully fine-tuned, 224 x 224, 8 epochs, the
same 29 classes (apple 8, tomato 10, potato 3, maize 4, grape 4), every label a `disease_id` of `data/reference/disease_catalogue.csv`.
Same backend use: `DISEASE_MODEL_DIR=data/training/output/farmtrack_leaf_v3` with `DISEASE_PROVIDER=model`. Weights
`model.safetensors` (56 MB, half precision) are not committed (`.gitignore`); this folder has them on the machine that downloaded
them. The Kaggle notebook output is the other copy.

## What is new: Tomato-Village (`mamtag/tomato-village`, Gehlot et al. 2023)

| | |
|---|---|
| Photos used | 391 originals: early blight 62, late blight 113, healthy 216 |
| What the photos are | one leaf on a plain sheet, phone camera, Rajasthan. **Not** photos of plants in the field |
| Split | by the minute the photo was taken (photos of one leaf stay together), 70/15/15: train 276, val 56, test 59 |
| Left out | Leaf Miner, Spotted Wilt Virus, three nutrient deficiencies (no catalogue id); the `_<n>` crop files (copies of the originals; healthy has none, so they would teach "small and blurry = disease"); the dataset's own splits (they share leaves); Variant-c (the in-field plant photos): its label files are the text "429: Too Many Requests", so they have no labels |
| Licence | Kaggle says "unknown": **internal demo only**; cite the paper |

All other data, caps and settings are as in v2 (38,975 + 276 photos trained on, 6,880 + 56 kept back for validation).

## Results (accuracy; "within crop" = the crop is given and only its classes compete, as in the backend)

| Check | n | Top-1 | Crop right | Disease within crop | v2 |
|---|---|---|---|---|---|
| PlantVillage / merged (lab) | 3,999 / 900 | 0.995 / 1.00 | 1.00 | 0.996 / 1.00 | 0.99 to 1.00 |
| AppleLeaf9 | 286 | 0.98 | 1.00 | 0.98 | 0.98 |
| FGVC7 / FGVC8 (orchard field) | 259 / 1,086 | 0.97 / 0.96 | 1.00 | 0.97 / 0.96 | 0.97 / 0.96 |
| PlantDoc validation (field, web) | 288 | 0.72 | 0.94 | 0.75 | 0.70 / 0.74 |
| **PlantDoc test (field, never trained on)** | **176** | **0.65** | **0.94** | **0.69** | 0.65 / 0.69 |
| **Kashmir (field, closest to Himachal)** | **62** | **0.53** | **0.97** | **0.53** | 0.53 / 0.55 |
| Tomato-Village validation | 56 | 0.91 | 1.00 | 0.91 | not measured |
| **Tomato-Village test (never trained on)** | **59** | **0.93** | **1.00** | **0.93** | not measured |

What this means:
- **Adding Tomato-Village did not change field accuracy.** PlantDoc test 0.65 and Kashmir 0.53 are the same as v2 (the differences are
  inside the noise of 176 and 62 photos). As expected: these photos are single leaves on a sheet, like the lab photos we already had.
- **Tomato-Village test 0.93 is the score on photos like the training photos** (59 photos: healthy 31 of 31, late blight 16 of 18,
  early blight 8 of 10). It says nothing about plants in a field. There is no v2 number on the same photos to compare with.
- **Tomato on PlantDoc field photos (test, n=79): about 7 in 10 right within the crop.** Weak: healthy 0.38 (n=8, healthy leaves called
  diseased), bacterial spot 0.44, mosaic virus 0.50. Better: late blight 0.80, septoria 0.83, yellow leaf curl 0.87, leaf mold 1.00 (n=6).
  Small numbers: a direction, not a measure.
- **Confidence still separates right from wrong** (PlantDoc field test): at confidence >= 0.9 right 92 % of the time (52 photos),
  0.7 to 0.9: 66 %, below 0.7: about 40 %. On Tomato-Village test: >= 0.9: 98 % (41 photos).
- Apple scab is still the weak apple class (28 scab photos called black rot in validation).

## Before it can be used with farmers

Same list as v2: licence review (FGVC, PlantVillage, Tomato-Village), agronomist check of the labels, a test on the client's own photos
(Himachal orchards and fields, phone cameras, confirmed labels), and the expert-queue threshold set from that test. **None of the
lab-style or leaf-on-a-sheet datasets closes the field gap; only photos from the field can.**
