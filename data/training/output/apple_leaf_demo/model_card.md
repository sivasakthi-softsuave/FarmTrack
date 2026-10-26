# FarmTrack apple leaf classifier "demo" (INTERNAL DEMO ONLY: do not give to farmers, do not redistribute)

> **DEMO-ONLY MODEL.** Trained on the 2,000 CC BY photos of `apple_leaf_v1` PLUS 30 collected web photos of **unknown licence**
> (`data/images/incoming`, added on the owner's instruction 26 Oct 2026, fruit photos included; marked `internal-only/unknown licence`
> in `data/training/demo/sources.csv`). It must not be shipped in a product or released outside the team until those photos are replaced
> or their licences are cleared. The same 23 leaf photos are also the old test set (`data/images/testset_v1`), so a score on them is NOT a test.
> Honest figures for the web photos: out-of-fold 9/19 (47 %), held-out test 7/8; both tiny samples. Photos in training are recognised
> (20/23 leaves, 5/5 fruit when run through the backend) because the model has seen them.

Created 2026-10-26 22:40 by `data/training/train_apple.py`. Classes: Apple___Apple_scab, Apple___Marssonina_blotch, Apple___Alternaria_leaf_spot, Apple___healthy.
Architecture `convnext_tiny.fb_in22k_ft_in1k` (timm), ImageNet-pretrained backbone frozen, linear head trained, temperature folded into the head. fp16 weights.

## Status: NOT validated for farmers
Labels are dataset folder names, **not confirmed by an agronomist**. The Marssonina class is the datasets' "Brown spot" (inferred to be
*Diplocarpon mali*). Accuracy below is on research/web images and does not describe field photos from Himachal. Do not quote 90-95 %.

## Data (photos are not redistributed; provenance per file in `data/training/sources.csv`)
Images per class used: {'Apple___Apple_scab': 408, 'Apple___Marssonina_blotch': 382, 'Apple___Alternaria_leaf_spot': 450, 'Apple___healthy': 450}. Images per source: {'Web-incoming': 27, 'AppleLeaf9': 1355, 'J&K-Mendeley': 308}. Image groups after merging near-duplicates: 1678.
Licences recorded in sources.csv (rows): {'CC-BY-4.0 / Yang, Duan & Wang (AppleLeaf9 compilers); images originate f': 1600, 'CC-BY-4.0 / Arshad Yatoo and Amit Sharma (Lovely Professional University': 400, 'internal-only/unknown licence / unknown': 30}.
The 2,000 research photos are CC BY 4.0 (the 30 web photos are NOT: unknown licence, internal demo only). Attribution required for the CC BY photos: AppleLeaf9 compilers Yang, Duan and Wang, Agronomy 2022, 12(11), 2784; Yatoo and Sharma, Mendeley Data, DOI 10.17632/9m2dcb5mmr.3).

## Cross-validation (5-fold, group-disjoint, on train/val): accuracy 0.967, macro-F1 0.967
| class | precision | recall | F1 | n |
|---|---|---|---|---|
| Apple___Apple_scab | 0.95 | 0.96 | 0.95 | 327 |
| Apple___Marssonina_blotch | 0.99 | 0.99 | 0.99 | 305 |
| Apple___Alternaria_leaf_spot | 0.97 | 0.95 | 0.96 | 360 |
| Apple___healthy | 0.96 | 0.97 | 0.97 | 360 |

| true \ predicted | Apple_scab | Marssonina_blotch | Alternaria_leaf_spot | healthy |
|---|---|---|---|---|
| Apple_scab | 314 | 0 | 4 | 9 |
| Marssonina_blotch | 1 | 302 | 2 | 0 |
| Alternaria_leaf_spot | 10 | 4 | 341 | 5 |
| healthy | 7 | 0 | 3 | 350 |

## Held-out test (group-disjoint, 338 photos): accuracy 0.976, macro-F1 0.976
| class | precision | recall | F1 | n |
|---|---|---|---|---|
| Apple___Apple_scab | 0.96 | 0.99 | 0.98 | 81 |
| Apple___Marssonina_blotch | 0.99 | 0.97 | 0.98 | 77 |
| Apple___Alternaria_leaf_spot | 0.97 | 0.98 | 0.97 | 90 |
| Apple___healthy | 0.99 | 0.97 | 0.98 | 90 |

| true \ predicted | Apple_scab | Marssonina_blotch | Alternaria_leaf_spot | healthy |
|---|---|---|---|---|
| Apple_scab | 80 | 0 | 1 | 0 |
| Marssonina_blotch | 0 | 75 | 2 | 0 |
| Alternaria_leaf_spot | 0 | 1 | 88 | 1 |
| healthy | 3 | 0 | 0 | 87 |

Calibration: temperature 0.50; ECE 0.096 before, 0.010 after (out-of-fold).
Accuracy by source (test): {np.str_('AppleLeaf9'): {'n': 268, 'accuracy': 0.9813432835820896}, np.str_('J&K-Mendeley'): {'n': 62, 'accuracy': 0.967741935483871}, np.str_('Web-incoming'): {'n': 8, 'accuracy': 0.875}}

## Other sets
none found

## Limits
- Labels = dataset folder names; no agronomist confirmed them (Marssonina = dataset class 'Brown spot', inferred).
- Each class comes mostly from a different source/imaging setup, so part of the accuracy may be source recognition, not disease recognition.
- Research/web images, not field photos from Himachal farmers: field accuracy will be lower. Never quote these numbers as 90-95%.
- Test split is group-disjoint but drawn from the same datasets as training.
- Marssonina photos come from ONE source (AppleLeaf9 'Brown spot'), so its recall is largely source recognition; check external_test/ (independent real photos).
- The Kashmir (J&K) images are pre-augmented by their authors; the central 70 % is used and siblings of one leaf may survive grouping, so J&K accuracy is optimistic.
