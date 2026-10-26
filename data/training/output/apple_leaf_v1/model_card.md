# FarmTrack apple leaf classifier v1 (internal demo model)

Created 2026-10-26 17:33 by `data/training/train_apple.py`. Classes: Apple___Apple_scab, Apple___Marssonina_blotch, Apple___Alternaria_leaf_spot, Apple___healthy.
Architecture `convnext_tiny.fb_in22k_ft_in1k` (timm), ImageNet-pretrained backbone frozen, linear head trained, temperature folded into the head. fp16 weights.

## Status: NOT validated for farmers
Labels are dataset folder names, **not confirmed by an agronomist**. The Marssonina class is the datasets' "Brown spot" (inferred to be
*Diplocarpon mali*). Accuracy below is on research/web images and does not describe field photos from Himachal. Do not quote 90-95 %.

## Data (photos are not redistributed; provenance per file in `data/training/sources.csv`)
Images per class used: {'Apple___Apple_scab': 400, 'Apple___Marssonina_blotch': 372, 'Apple___Alternaria_leaf_spot': 450, 'Apple___healthy': 450}. Images per source: {'AppleLeaf9': 1362, 'J&K-Mendeley': 310}. Image groups after merging near-duplicates: 1662.
Licences recorded in sources.csv (rows): {'CC-BY-4.0 / Yang, Duan & Wang (AppleLeaf9 compilers); images originate f': 1600, 'CC-BY-4.0 / Arshad Yatoo and Amit Sharma (Lovely Professional University': 400}.
All sources are CC BY 4.0 (attribution required: AppleLeaf9 compilers Yang, Duan and Wang, Agronomy 2022, 12(11), 2784; Yatoo and Sharma, Mendeley Data, DOI 10.17632/9m2dcb5mmr.3).

## Cross-validation (5-fold, group-disjoint, on train/val): accuracy 0.975, macro-F1 0.976
| class | precision | recall | F1 | n |
|---|---|---|---|---|
| Apple___Apple_scab | 0.95 | 0.97 | 0.96 | 320 |
| Apple___Marssonina_blotch | 0.99 | 1.00 | 0.99 | 298 |
| Apple___Alternaria_leaf_spot | 0.99 | 0.96 | 0.98 | 360 |
| Apple___healthy | 0.97 | 0.97 | 0.97 | 360 |

| true \ predicted | Apple_scab | Marssonina_blotch | Alternaria_leaf_spot | healthy |
|---|---|---|---|---|
| Apple_scab | 312 | 0 | 1 | 7 |
| Marssonina_blotch | 0 | 297 | 1 | 0 |
| Alternaria_leaf_spot | 6 | 2 | 347 | 5 |
| healthy | 9 | 0 | 2 | 349 |

## Held-out test (group-disjoint, 334 photos): accuracy 0.979, macro-F1 0.979
| class | precision | recall | F1 | n |
|---|---|---|---|---|
| Apple___Apple_scab | 0.95 | 0.99 | 0.97 | 80 |
| Apple___Marssonina_blotch | 0.99 | 1.00 | 0.99 | 74 |
| Apple___Alternaria_leaf_spot | 0.99 | 0.98 | 0.98 | 90 |
| Apple___healthy | 0.99 | 0.96 | 0.97 | 90 |

| true \ predicted | Apple_scab | Marssonina_blotch | Alternaria_leaf_spot | healthy |
|---|---|---|---|---|
| Apple_scab | 79 | 0 | 0 | 1 |
| Marssonina_blotch | 0 | 74 | 0 | 0 |
| Alternaria_leaf_spot | 1 | 1 | 88 | 0 |
| healthy | 3 | 0 | 1 | 86 |

Calibration: temperature 0.40; ECE 0.106 before, 0.006 after (out-of-fold).
Accuracy by source (test): {np.str_('AppleLeaf9'): {'n': 273, 'accuracy': 0.978021978021978}, np.str_('J&K-Mendeley'): {'n': 61, 'accuracy': 0.9836065573770492}}

## Other sets

**leaf** (23 photos, never trained on): accuracy 0.57
- SCB_05l.jpg: Apple___Alternaria_leaf_spot (0.999)
- SCB_05r.jpg: Apple___Alternaria_leaf_spot (0.994)
- SCB_06.jpg: Apple___Alternaria_leaf_spot (0.981)
- SCB_09.jpg: Apple___Alternaria_leaf_spot (0.871)
- MAR_01.jpg: Apple___Alternaria_leaf_spot (0.989)
- MAR_02.jpg: Apple___Marssonina_blotch (0.999)
- MAR_03.jpg: Apple___Marssonina_blotch (0.976)
- MAR_04a.jpg: Apple___Alternaria_leaf_spot (0.908)
- MAR_04b.jpg: Apple___Marssonina_blotch (0.997)
- MAR_05.jpg: Apple___Marssonina_blotch (0.962)
- MAR_06.jpg: Apple___Marssonina_blotch (0.848)
- MAR_07.jpg: Apple___Marssonina_blotch (0.941)
- MAR_08.jpg: Apple___Alternaria_leaf_spot (0.999)
- MAR_09.jpg: Apple___healthy (0.53)
- MAR_10.jpg: Apple___Alternaria_leaf_spot (0.975)
- ALT_01.jpg: Apple___Alternaria_leaf_spot (1.0)
- ALT_02.jpg: Apple___Alternaria_leaf_spot (0.997)
- ALT_03.jpg: Apple___Alternaria_leaf_spot (0.978)
- ALT_04.jpg: Apple___Alternaria_leaf_spot (1.0)
- ALT_07.jpg: Apple___Alternaria_leaf_spot (0.93)
- ALT_08.jpg: Apple___Marssonina_blotch (0.994)
- ALT_09.jpg: Apple___Alternaria_leaf_spot (1.0)
- ALT_10.jpg: Apple___Alternaria_leaf_spot (0.725)


## Limits
- Labels = dataset folder names; no agronomist confirmed them (Marssonina = dataset class 'Brown spot', inferred).
- Each class comes mostly from a different source/imaging setup, so part of the accuracy may be source recognition, not disease recognition.
- Research/web images, not field photos from Himachal farmers: field accuracy will be lower. Never quote these numbers as 90-95%.
- Test split is group-disjoint but drawn from the same datasets as training.
- Marssonina photos come from ONE source (AppleLeaf9 'Brown spot'), so its recall is largely source recognition; check external_test/ (independent real photos).
- The Kashmir (J&K) images are pre-augmented by their authors; the central 70 % is used and siblings of one leaf may survive grouping, so J&K accuracy is optimistic.
