# FarmTrack leaf model v2 (`farmtrack_leaf_v2`)

Internal demo model, trained 26 Oct 2026 on a Kaggle T4 GPU (notebook `krishnan001dev/farmtrack-leaf-v2-training`, private;
script `data/training/train_leaf_v2_kaggle.py`). **Not field-validated. Labels not confirmed by an agronomist. Licence review
pending (see below): do not ship to farmers on these weights.**

## What it is

- ConvNeXt-Tiny (timm `convnext_tiny`, from `convnext_tiny.fb_in22k_ft_in1k`), fully fine-tuned, 224 x 224, 8 epochs.
- **29 classes, one model for the five MVP crops**; every label is a `disease_id` of `data/reference/disease_catalogue.csv`:
  apple 8 (scab, Marssonina blotch, Alternaria leaf spot, black rot / frogeye, cedar rust, gray spot, powdery mildew, healthy),
  tomato 10, potato 3, maize 4, grape 4.
- Backend: `DISEASE_MODEL_DIR=data/training/output/farmtrack_leaf_v2` with `DISEASE_PROVIDER=model`. It answers for every crop
  it has classes of (the crop's classes are renormalised, like model A's crop mask); other crops still go to model A.
- Weights `model.safetensors` (56 MB, half precision) are NOT committed (`.gitignore`); get them from the Kaggle notebook output.

## Data (class_counts.csv has every source x class count)

| Source | Photos | Kind | Licence |
|---|---|---|---|
| `bhataakib02/apple-disease-dataset`: FGVC7 + FGVC8 | 1,730 + 7,237 | orchard field photos (US) | Kaggle competition data: **terms to check** |
| same: AppleLeaf9 | 1,900 | lab / field mix (China) | CC BY 4.0 |
| same: Kashmir | 406 | field photos (J&K) | CC BY 4.0 |
| same: PlantVillage apple | 6,000 | lab, plain background | **ambiguous** |
| `nirmalsankalana/plant-diseases-training-dataset` | 26,657 | mostly PlantVillage (lab) | **ambiguous** (uploader says CC0) |
| `nirmalsankalana/plantdoc-dataset` (PlantDoc) | 1,925 train/val, 176 test | web photos of real plants (India) | CC BY 4.0 |

In all 38,975 photos trained on and 6,880 kept back for validation.

Capped at 1,500 photos per source and class; 15 % of each kept back for validation; the PlantDoc test split is never trained on.

Label mapping (inferred, as in v1): dataset "brown spot" = Marssonina blotch; Kashmir "leaf blotch" = Alternaria; FGVC/AppleLeaf9
"frog eye leaf spot" = black rot; "rust" = cedar apple rust. FGVC "complex" and AppleLeaf9 "mosaic" left out (no catalogue id).

## Results (accuracy; "within crop" = the crop is given and only its classes compete, as in the backend)

| Check | n | Top-1 | Crop right | Disease within crop |
|---|---|---|---|---|
| PlantVillage / merged (lab) | 4,899 | 0.99 to 1.00 | 1.00 | 0.99 to 1.00 |
| AppleLeaf9 | 286 | 0.98 | 1.00 | 0.98 |
| FGVC7 / FGVC8 (orchard field) | 259 / 1,086 | 0.97 / 0.96 | 1.00 | 0.97 / 0.96 |
| PlantDoc validation (field, web) | 288 | 0.70 | 0.94 | 0.74 |
| **PlantDoc test (field, never trained on)** | **176** | **0.65** | **0.94** | **0.69** |
| **Kashmir (field, closest to Himachal)** | **62** | **0.53** | **0.97** | **0.55** |

What this means:
- **On photos like the training photos it is near perfect; on real field photos it is right about 2 times in 3**, and on the
  Kashmir orchard photos (the closest to Himachal) about 1 in 2. Kashmir apple scab: only 7 of 24 right (often called black rot).
  The numbers are small (176 and 62 photos): treat them as a direction, not a measure.
- **Crop: right 94 to 97 % on field photos**: a useful second opinion for the crop gate (the project's most critical step).
- **Marssonina (100 %) comes from a single source (AppleLeaf9)**: the model may be recognising that dataset's look, not the disease.
  No independent Marssonina photo was available to check it.
- **Confidence now means something** (PlantDoc field test): answers at confidence >= 0.9 were right 92 % of the time (51 photos),
  0.7 to 0.9: 68 %, below 0.7: about 40 %. This is better than the earlier models (confidence did not separate right from wrong) and
  supports sending low-confidence results to the expert queue. Not calibrated on Himachal photos.
- Weak classes on field photos: potato early blight (0.36), maize gray leaf spot (0.25, n=4), maize northern leaf blight (0.42),
  tomato mosaic (0.50). Strong: grape (1.00), maize common rust (0.90), apple cedar rust (0.90), tomato late blight (0.80).

## Before it can be used with farmers

1. **Licence review**: FGVC competition data and PlantVillage terms; retrain without them if they do not allow commercial use.
2. **Agronomist check of the labels** (the inferred mappings above) and of a sample of training photos per class.
3. **Test on the client's own photos** (Himachal orchards, phone cameras, with dates and confirmed labels); the Kashmir result says
   the gap is large. Phase 2 fine-tuning on those photos is the real fix.
4. Set the expert-queue confidence threshold from that test, not from these numbers.
