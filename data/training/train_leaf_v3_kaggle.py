"""FarmTrack leaf model v3 = v2 plus the Tomato-Village leaf photos: one classifier for the MVP crops (apple, tomato,
potato, maize, grape), run on a Kaggle GPU.

Run as a Kaggle notebook (script) with GPU and internet on and these datasets attached:
  bhataakib02/apple-disease-dataset              apple: AppleLeaf9, FGVC7, FGVC8 (orchard field photos), Kashmir, PlantVillage;
                                                 already de-duplicated across the five sources
  nirmalsankalana/plant-diseases-training-dataset tomato, potato, maize, grape (mostly PlantVillage, plus other open sets)
  nirmalsankalana/plantdoc-dataset               PlantDoc (CC BY 4.0, field photos from the web); its test split is kept out
                                                 of training and reported on its own as a "field" check
  mamtag/tomato-village                          Tomato-Village (Gehlot et al. 2023; Kaggle licence "unknown"): single leaves on a
                                                 plain sheet, phone photos, Rajasthan. Only the ORIGINAL photos of early blight, late
                                                 blight and healthy are used: its other classes have no catalogue id, its "_<n>" files
                                                 are copies of the originals (healthy has none, so they would teach "small = disease")
                                                 and its own train/val/test share leaves. Photos taken in the same minute stay
                                                 together; groups are dealt 70/15/15 into train / val / test.

Output (/kaggle/working/farmtrack_leaf_v3): model.safetensors (half precision), config.json in the format the backend loads
(app/vision/torch_models.py: architecture, num_classes, label_names = disease catalogue ids, pretrained_cfg), metrics.json,
class_counts.csv. The labels are the dataset folder names mapped to catalogue ids; no agronomist has confirmed them.
"""
from __future__ import annotations

import csv
import json
import math
import os
import random
import re
import time
from collections import Counter, defaultdict
from pathlib import Path

import numpy as np
import timm
import torch
from PIL import Image, ImageFile
from torch import nn
from torch.utils.data import DataLoader, Dataset, WeightedRandomSampler
from torchvision import transforms

ImageFile.LOAD_TRUNCATED_IMAGES = True
SEED = 26
random.seed(SEED)
np.random.seed(SEED)
torch.manual_seed(SEED)

INPUT = Path('/kaggle/input')
OUT = Path('/kaggle/working/farmtrack_leaf_v3')
OUT.mkdir(parents=True, exist_ok=True)

ARCH = 'convnext_tiny'                       # what the backend builds (timm.create_model)
PRETRAINED = 'convnext_tiny.fb_in22k_ft_in1k'
SIZE = 224
EPOCHS = int(os.environ.get('EPOCHS', '8'))
BATCH = 64
CAP_PER_SOURCE_CLASS = 1500                  # balance: no source/class pair dominates
VAL_SHARE = 0.15
IMAGE_EXT = {'.jpg', '.jpeg', '.png', '.bmp', '.webp'}

# ----------------------------------------------------------------------------------------------- label maps (catalogue ids)

APPLE = {   # bhataakib02/apple-disease-dataset folder -> catalogue id ("complex", "mosaic": no catalogue id, left out)
    'scab': 'Apple___Apple_scab',
    'healthy': 'Apple___healthy',
    'rust': 'Apple___Cedar_apple_rust',
    'black_rot': 'Apple___Black_rot',
    'frog_eye_leaf_spot': 'Apple___Black_rot',               # frogeye leaf spot = black rot fungus on leaves
    'brown_spot': 'Apple___Marssonina_blotch',               # Chinese datasets' "brown spot" = Marssonina (inferred, as in v1)
    'alternaria_leaf_spot': 'Apple___Alternaria_leaf_spot',
    'leaf_blotch': 'Apple___Alternaria_leaf_spot',           # Kashmir "leaf blotch" = Alternaria leaf blotch (as in v1)
    'grey_spot': 'Apple___Gray_spot',
    'powdery_mildew': 'Apple___Powdery_mildew',
}
MERGED = {  # nirmalsankalana/plant-diseases-training-dataset folder -> catalogue id (apple taken from the apple set only)
    'Tomato___bacterial_spot': 'Tomato___Bacterial_spot',
    'Tomato___early_blight': 'Tomato___Early_blight',
    'Tomato___late_blight': 'Tomato___Late_blight',
    'Tomato___leaf_mold': 'Tomato___Leaf_Mold',
    'Tomato___septoria_leaf_spot': 'Tomato___Septoria_leaf_spot',
    'Tomato___spider_mites': 'Tomato___Spider_mites Two-spotted_spider_mite',
    'Tomato___target_spot': 'Tomato___Target_Spot',
    'Tomato___leaf_curl': 'Tomato___Tomato_Yellow_Leaf_Curl_Virus',
    'Tomato___mosaic_virus': 'Tomato___Tomato_mosaic_virus',
    'Tomato___healthy': 'Tomato___healthy',
    'Potato___early_blight': 'Potato___Early_blight',
    'Potato___late_blight': 'Potato___Late_blight',
    'Potato___healthy': 'Potato___healthy',
    'Corn___common_rust': 'Corn_(maize)___Common_rust_',
    'Corn___gray_leaf_spot': 'Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot',
    'Corn___northern_leaf_blight': 'Corn_(maize)___Northern_Leaf_Blight',
    'Corn___healthy': 'Corn_(maize)___healthy',
    'Grape___black_rot': 'Grape___Black_rot',
    'Grape___black_measles': 'Grape___Esca_(Black_Measles)',
    'Grape___Leaf_blight': 'Grape___Leaf_blight_(Isariopsis_Leaf_Spot)',
    'Grape___healthy': 'Grape___healthy',
}
PLANTDOC = {  # nirmalsankalana/plantdoc-dataset folder -> catalogue id (other crops of PlantDoc left out)
    'Apple_Scab_Leaf': 'Apple___Apple_scab',
    'Apple_leaf': 'Apple___healthy',
    'Apple_rust_leaf': 'Apple___Cedar_apple_rust',
    'Corn_Gray_leaf_spot': 'Corn_(maize)___Cercospora_leaf_spot Gray_leaf_spot',
    'Corn_leaf_blight': 'Corn_(maize)___Northern_Leaf_Blight',
    'Corn_rust_leaf': 'Corn_(maize)___Common_rust_',
    'Potato_leaf_early_blight': 'Potato___Early_blight',
    'Potato_leaf_late_blight': 'Potato___Late_blight',
    'Tomato_Early_blight_leaf': 'Tomato___Early_blight',
    'Tomato_Septoria_leaf_spot': 'Tomato___Septoria_leaf_spot',
    'Tomato_leaf': 'Tomato___healthy',
    'Tomato_leaf_bacterial_spot': 'Tomato___Bacterial_spot',
    'Tomato_leaf_late_blight': 'Tomato___Late_blight',
    'Tomato_leaf_mosaic_virus': 'Tomato___Tomato_mosaic_virus',
    'Tomato_leaf_yellow_virus': 'Tomato___Tomato_Yellow_Leaf_Curl_Virus',
    'Tomato_mold_leaf': 'Tomato___Leaf_Mold',
    'Tomato_two_spotted_spider_mites_leaf': 'Tomato___Spider_mites Two-spotted_spider_mite',
    'grape_leaf': 'Grape___healthy',
    'grape_leaf_black_rot': 'Grape___Black_rot',
}
TOMATO_VILLAGE = {  # mamtag/tomato-village "Variant-a" folder -> catalogue id (Leaf Miner, Spotted Wilt Virus and the three
    'Early_blight': 'Tomato___Early_blight',      # nutrient deficiencies have no catalogue id: left out)
    'Late_blight': 'Tomato___Late_blight',
    'Healthy': 'Tomato___healthy',
}
LICENCE = {  # recorded with every source; FGVC and PlantVillage terms are unclear: the model is an internal demo model
    'appleleaf9': 'CC BY 4.0', 'kashmir': 'CC BY 4.0', 'fgvc7': 'Kaggle competition data (terms to check)',
    'fgvc8': 'Kaggle competition data (terms to check)', 'plantvillage': 'PlantVillage (licence ambiguous)',
    'merged': 'mixed open sets, mostly PlantVillage (licence ambiguous)', 'plantdoc': 'CC BY 4.0',
    'tomato_village': 'Kaggle licence "unknown" (cite Gehlot et al. 2023): internal demo only',
}
FIELD_SOURCES = {'fgvc7', 'fgvc8', 'kashmir', 'plantdoc'}     # photos taken in orchards and fields, not on a lab table
CROP_PREFIXES = ('Apple___', 'Tomato___', 'Potato___', 'Corn_(maize)___', 'Grape___')


def crop_of(label: str) -> str:
    return next(p for p in CROP_PREFIXES if label.startswith(p))


# ----------------------------------------------------------------------------------------------- find the attached data

DATASETS = ['bhataakib02/apple-disease-dataset', 'nirmalsankalana/plant-diseases-training-dataset',
            'nirmalsankalana/plantdoc-dataset', 'mamtag/tomato-village']
SEARCH = [INPUT]


def find_dir(name: str, max_depth: int = 10) -> Path:
    """The attached datasets are mounted under /kaggle/input (the exact layout differs between Kaggle versions, and the
    folders can be symbolic links). When they are not attached they are downloaded with kagglehub (internet on)."""
    for _ in range(2):
        for base in SEARCH:
            for root, dirs, _files in os.walk(base, followlinks=True):
                depth = len(Path(root).relative_to(base).parts)
                if name in dirs:
                    return Path(root) / name
                if depth >= max_depth:
                    dirs[:] = []
        if len(SEARCH) == 1:
            import kagglehub
            for ref in DATASETS:
                path = Path(kagglehub.dataset_download(ref))
                print('downloaded', ref, '->', path, flush=True)
                SEARCH.append(path)
    raise FileNotFoundError(f'{name} not found under {SEARCH}')


def show_inputs(levels: int = 4) -> None:
    """What is mounted, a few levels deep (printed so a missing dataset is easy to see in the log)."""
    for root, dirs, files in os.walk(INPUT, followlinks=True):
        depth = len(Path(root).relative_to(INPUT).parts)
        print('  ' * depth + (Path(root).name or str(INPUT)), f'({len(dirs)} dirs, {len(files)} files)')
        if depth >= levels:
            dirs[:] = []


show_inputs()


def images_in(folder: Path) -> list[Path]:
    return sorted(p for p in folder.rglob('*') if p.suffix.lower() in IMAGE_EXT)


items: list[tuple[str, str, str, str]] = []   # (path, label, source, split) split: 'pool' (train/val) or 'test'

apple_root = find_dir('Apple Disease Dataset - Final')
for source_dir in sorted(p for p in apple_root.iterdir() if p.is_dir()):
    for class_dir in sorted(p for p in source_dir.iterdir() if p.is_dir()):
        label = APPLE.get(class_dir.name)
        if label:
            items += [(str(p), label, source_dir.name, 'pool') for p in images_in(class_dir)]

merged_root = find_dir('Tomato___healthy').parent
for folder, label in MERGED.items():
    if (merged_root / folder).is_dir():
        items += [(str(p), label, 'merged', 'pool') for p in images_in(merged_root / folder)]

plantdoc_train = find_dir('Apple_Scab_Leaf').parent
plantdoc_root = plantdoc_train.parent
for split_name, split in (('train', 'pool'), ('test', 'test')):
    for folder, label in PLANTDOC.items():
        d = plantdoc_root / split_name / folder
        if d.is_dir():
            items += [(str(p), label, 'plantdoc', split) for p in images_in(d)]



def tomato_village_items(root: Path) -> list[tuple[str, str, str, str]]:
    """Original photos only (no "_<n>" suffix), grouped by the minute they were taken, groups dealt into train/val/test."""
    rng = random.Random(SEED)
    rows = []
    for folder, label in TOMATO_VILLAGE.items():
        groups: dict[str, list[Path]] = defaultdict(list)
        for split_name in ('train', 'val', 'test'):          # the dataset's own splits are pooled and dealt again
            for p in images_in(root / split_name / folder):
                if not re.search(r'_\d+$', p.stem):
                    groups[re.sub(r'^(IMG\d{12}).*$', r'\1', p.stem)].append(p)
        keys = sorted(groups)
        rng.shuffle(keys)
        for k, key in enumerate(keys):
            share = k / len(keys)
            split = 'train' if share < 0.70 else 'val' if share < 0.85 else 'test'
            rows += [(str(p), label, 'tomato_village', split) for p in groups[key]]
    return rows


items += tomato_village_items(find_dir('Variant-a(Multiclass Classification)'))

print('images found:', len(items))

# ----------------------------------------------------------------------------------------------- balance and split

by_pair: dict[tuple[str, str], list[tuple[str, str, str, str]]] = defaultdict(list)
for it in items:
    by_pair[(it[2], it[1])].append(it)

train, val, test = [], [], []
for (source, label), group in sorted(by_pair.items()):
    random.shuffle(group)
    pool = [g for g in group if g[3] == 'pool'][:CAP_PER_SOURCE_CLASS]
    test += [g for g in group if g[3] == 'test']
    n_val = max(1, round(len(pool) * VAL_SHARE)) if len(pool) >= 5 else 0
    val += pool[:n_val]
    train += pool[n_val:]
    val += [g for g in group if g[3] == 'val']                # sources that bring their own grouped split
    train += [g for g in group if g[3] == 'train']

LABELS = sorted({it[1] for it in train}, key=lambda s: (CROP_PREFIXES.index(crop_of(s)), s))
INDEX = {label: i for i, label in enumerate(LABELS)}
print('classes:', len(LABELS), '| train', len(train), '| val', len(val), '| test', dict(Counter(r[2] for r in test)))

with open(OUT / 'class_counts.csv', 'w', newline='', encoding='utf-8') as f:
    w = csv.writer(f)
    w.writerow(['source', 'label', 'licence', 'train', 'val', 'test'])
    counts = Counter((it[2], it[1], part) for part, rows in (('train', train), ('val', val), ('test', test)) for it in rows)
    for source, label in sorted({(it[2], it[1]) for it in train + val + test}):
        w.writerow([source, label, LICENCE[source], counts[(source, label, 'train')], counts[(source, label, 'val')],
                    counts[(source, label, 'test')]])

# ----------------------------------------------------------------------------------------------- data

MEAN, STD = (0.485, 0.456, 0.406), (0.229, 0.224, 0.225)
train_tf = transforms.Compose([
    transforms.RandomResizedCrop(SIZE, scale=(0.5, 1.0), ratio=(0.75, 1.33)),
    transforms.RandomHorizontalFlip(),
    transforms.RandomVerticalFlip(),
    transforms.RandomRotation(25),
    transforms.ColorJitter(0.35, 0.35, 0.3, 0.04),            # field light: sun, shade, phone white balance
    transforms.RandomApply([transforms.GaussianBlur(5, (0.1, 1.8))], p=0.25),   # hand shake, focus
    transforms.ToTensor(),
    transforms.Normalize(MEAN, STD),
    transforms.RandomErasing(p=0.2, scale=(0.02, 0.12)),
])
eval_tf = transforms.Compose([   # the backend's preprocess_timm: resize to SIZE x SIZE (crop_pct 1.0), normalise
    transforms.Resize((SIZE, SIZE)),
    transforms.ToTensor(),
    transforms.Normalize(MEAN, STD),
])


class Leaves(Dataset):
    def __init__(self, rows, tf):
        self.rows, self.tf = rows, tf

    def __len__(self):
        return len(self.rows)

    def __getitem__(self, i):
        path, label, _, _ = self.rows[i]
        try:
            img = Image.open(path).convert('RGB')
        except Exception:
            img = Image.new('RGB', (SIZE, SIZE))
        return self.tf(img), INDEX[label], i


label_freq = Counter(it[1] for it in train)
weights = [1.0 / math.sqrt(label_freq[it[1]]) for it in train]    # rare classes seen more often, without overdoing it
sampler = WeightedRandomSampler(weights, num_samples=len(train), replacement=True)
workers = min(8, os.cpu_count() or 2)
train_dl = DataLoader(Leaves(train, train_tf), batch_size=BATCH, sampler=sampler, num_workers=workers, pin_memory=True,
                      drop_last=True, persistent_workers=True)


def loader(rows):
    return DataLoader(Leaves(rows, eval_tf), batch_size=128, shuffle=False, num_workers=workers, pin_memory=True)


# ----------------------------------------------------------------------------------------------- model and training

device = 'cuda' if torch.cuda.is_available() else 'cpu'
print('device:', device, torch.cuda.get_device_name(0) if device == 'cuda' else '')
model = timm.create_model(PRETRAINED, pretrained=True, num_classes=len(LABELS), drop_path_rate=0.1).to(device)
opt = torch.optim.AdamW(model.parameters(), lr=2e-4, weight_decay=0.05)
steps = EPOCHS * len(train_dl)
warm = len(train_dl) // 2
sched = torch.optim.lr_scheduler.LambdaLR(
    opt, lambda s: (s + 1) / warm if s < warm else 0.5 * (1 + math.cos(math.pi * (s - warm) / max(1, steps - warm))))
loss_fn = nn.CrossEntropyLoss(label_smoothing=0.1)
scaler = torch.amp.GradScaler('cuda', enabled=device == 'cuda')


@torch.no_grad()
def predict(rows):
    model.eval()
    probs = np.zeros((len(rows), len(LABELS)), dtype=np.float32)
    for x, _, idx in loader(rows):
        with torch.autocast(device, dtype=torch.float16, enabled=device == 'cuda'):
            probs[idx.numpy()] = torch.softmax(model(x.to(device, non_blocking=True)).float(), -1).cpu().numpy()
    return probs


best, best_state = -1.0, None
for epoch in range(EPOCHS):
    model.train()
    start, seen, loss_sum = time.time(), 0, 0.0
    for x, y, _ in train_dl:
        x, y = x.to(device, non_blocking=True), y.to(device, non_blocking=True)
        with torch.autocast(device, dtype=torch.float16, enabled=device == 'cuda'):
            loss = loss_fn(model(x), y)
        opt.zero_grad(set_to_none=True)
        scaler.scale(loss).backward()
        scaler.step(opt)
        scaler.update()
        sched.step()
        seen += len(y)
        loss_sum += loss.item() * len(y)
    p = predict(val)
    acc = float(np.mean(p.argmax(1) == np.array([INDEX[r[1]] for r in val])))
    print(f'epoch {epoch + 1}/{EPOCHS} loss {loss_sum / seen:.3f} val acc {acc:.4f} ({time.time() - start:.0f} s)', flush=True)
    if acc > best:
        best, best_state = acc, {k: v.detach().cpu().clone() for k, v in model.state_dict().items()}

model.load_state_dict(best_state)

# ----------------------------------------------------------------------------------------------- evaluation


def report(rows, probs):
    """Overall, crop (summed probabilities per crop), and disease within the true crop (how the backend uses it: the
    crop is decided first, then the model's classes of that crop are renormalised)."""
    truth = np.array([INDEX[r[1]] for r in rows])
    crop_ids = [CROP_PREFIXES.index(crop_of(lab)) for lab in LABELS]
    crop_mat = np.zeros((len(LABELS), len(CROP_PREFIXES)), dtype=np.float32)
    for i, c in enumerate(crop_ids):
        crop_mat[i, c] = 1
    crop_pred = (probs @ crop_mat).argmax(1)
    crop_true = np.array([crop_ids[t] for t in truth])
    within = []
    for k, t in enumerate(truth):
        mask = np.array([c == crop_true[k] for c in crop_ids])
        within.append(int(np.argmax(np.where(mask, probs[k], -1)) == t))
    per_class = {}
    for i, lab in enumerate(LABELS):
        sel = truth == i
        if sel.any():
            per_class[lab] = {'n': int(sel.sum()), 'acc_within_crop': float(np.mean(np.array(within)[sel]))}
    conf = probs.max(1)
    right = probs.argmax(1) == truth
    bins = {}
    for lo, hi in ((0.0, 0.5), (0.5, 0.7), (0.7, 0.9), (0.9, 1.01)):
        sel = (conf >= lo) & (conf < hi)
        bins[f'{lo:.1f}-{min(hi, 1.0):.1f}'] = {'n': int(sel.sum()), 'acc': float(right[sel].mean()) if sel.any() else None}
    return {
        'n': len(rows),
        'top1': float(right.mean()) if len(rows) else None,
        'crop_acc': float(np.mean(crop_pred == crop_true)) if len(rows) else None,
        'disease_acc_within_true_crop': float(np.mean(within)) if len(rows) else None,
        'confidence_bins': bins,
        'per_class': per_class,
    }


metrics = {'best_val_top1': best, 'classes': LABELS, 'val_by_source': {}, 'field_sources': sorted(FIELD_SOURCES)}
val_probs = predict(val)
for source in sorted({r[2] for r in val}):
    sel = [i for i, r in enumerate(val) if r[2] == source]
    metrics['val_by_source'][source] = report([val[i] for i in sel], val_probs[sel])
test_probs = predict(test) if test else None


def test_report(source):
    sel = [i for i, r in enumerate(test) if r[2] == source]
    return report([test[i] for i in sel], test_probs[sel]) if sel else None


metrics['plantdoc_test_field'] = test_report('plantdoc')
metrics['tomato_village_test'] = test_report('tomato_village')
metrics['apple_confusions_val'] = {}
apple_rows = [i for i, r in enumerate(val) if r[1].startswith('Apple___')]
for i in apple_rows:
    t, pr = val[i][1], LABELS[int(val_probs[i].argmax())]
    if t != pr:
        metrics['apple_confusions_val'][f'{t} -> {pr}'] = metrics['apple_confusions_val'].get(f'{t} -> {pr}', 0) + 1

# ----------------------------------------------------------------------------------------------- export

from safetensors.torch import save_file  # noqa: E402

save_file({k: v.half().contiguous() for k, v in model.state_dict().items()}, str(OUT / 'model.safetensors'))
config = {
    'architecture': ARCH,
    'num_classes': len(LABELS),
    'label_names': LABELS,
    'pretrained_cfg': {'input_size': [3, SIZE, SIZE], 'mean': list(MEAN), 'std': list(STD), 'crop_pct': 1.0,
                       'interpolation': 'bilinear'},
    'label_descriptions': {label: label for label in LABELS},
    'note': 'FarmTrack leaf v3: ConvNeXt-Tiny fine-tuned on apple, tomato, potato, maize and grape leaves (Kaggle GPU), v2 data plus Tomato-Village. '
            'Labels unconfirmed by an agronomist; research and web photos, not farmers\' photos. See model_card.md.',
}
(OUT / 'config.json').write_text(json.dumps(config, indent=2), encoding='utf-8')
(OUT / 'metrics.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')
print(json.dumps({k: metrics[k] for k in ('best_val_top1',)}, indent=2))
for source, m in metrics['val_by_source'].items():
    print(f"val {source:13s} n={m['n']:5d} top1={m['top1']:.3f} crop={m['crop_acc']:.3f} within-crop={m['disease_acc_within_true_crop']:.3f}")
for key, name in (('plantdoc_test_field', 'PlantDoc test (field)'), ('tomato_village_test', 'Tomato-Village test')):
    m = metrics[key]
    if m:
        print(f"{name} n={m['n']} top1={m['top1']:.3f} crop={m['crop_acc']:.3f} within-crop={m['disease_acc_within_true_crop']:.3f}")
print('done')
