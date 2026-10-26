"""Shortcut check: can the classes be told apart WITHOUT looking at the disease? Run it on every new batch of photos BEFORE training.

  .venv/Scripts/python check_shortcuts.py [--photos photos] [--cap 450]      (Windows PowerShell: .venv\\Scripts\\python ...)

It trains three quick linear probes on the photos with the same group-disjoint split as train_apple.py:
  A  an 8x8 colour thumbnail only (no lesion can be seen)
  B  ConvNeXt features with the CENTRE 60% x 60% of every photo blanked (only the frame / background is visible)
  C  ConvNeXt features of the full photo (the ceiling)
How to read it: A and B should be close to chance (1 / number of classes, or the largest class share). If B is close to C, the photos leak
the answer through background or photo style (different cameras, backgrounds or light per class): fix the collection, do not train yet.
On the 2,000 public photos of apple_leaf_v1 it gave A 0.77, B 0.94, C 0.97 against chance 0.27: that data is NOT clean.
"""
import argparse
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import timm  # noqa: E402
import torch  # noqa: E402
from PIL import Image  # noqa: E402
from sklearn.linear_model import LogisticRegression  # noqa: E402
from sklearn.preprocessing import StandardScaler  # noqa: E402

import train_apple as ta  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--photos", default=str(HERE / "photos"))
    ap.add_argument("--cap", type=int, default=450)
    ap.add_argument("--seed", type=int, default=7)
    a = ap.parse_args()

    items, _ = ta.scan(Path(a.photos), a.cap, a.seed)
    imgs = [ta.load_cached(p) for p, _, _ in items]
    y = np.array([c for _, c, _ in items])
    srcs = np.array([s for _, _, s in items])
    groups = np.array(ta.group_near_duplicates([ta.hash_bits(i) for i in imgs]))
    folds = ta.stratified_group_split(y, groups, 5, a.seed)
    names = [c.split("___")[1] for c in ta.CLASSES]
    chance = np.bincount(y, minlength=len(names)).max() / len(y)
    print(f"{len(imgs)} images, per class {dict(zip(names, np.bincount(y, minlength=len(names)).tolist()))}, chance = {chance:.2f}")

    def cv_accuracy(X, label):
        pred = np.zeros(len(y), dtype=int)
        for tr, te in folds:
            sc = StandardScaler().fit(X[tr])
            clf = LogisticRegression(max_iter=3000, C=0.5, class_weight="balanced").fit(sc.transform(X[tr]), y[tr])
            pred[te] = clf.predict(sc.transform(X[te]))
        per = {n: round(float((pred[y == i] == i).mean()), 2) for i, n in enumerate(names) if (y == i).any()}
        bysrc = {str(s): round(float((pred[srcs == s] == y[srcs == s]).mean()), 2) for s in sorted(set(srcs))}
        print(f"\n{label}\n  held-out accuracy {(pred == y).mean():.3f}   per class {per}   by source {bysrc}")

    tiny = np.stack([np.asarray(i.convert("RGB").resize((8, 8), Image.Resampling.BOX), dtype=np.float32).reshape(-1) / 255.0 for i in imgs])
    cv_accuracy(tiny, "A. 8x8 colour thumbnail only (no lesions visible)")

    net = timm.create_model("convnext_tiny.fb_in22k_ft_in1k", pretrained=True, num_classes=0).eval()
    cfg = net.pretrained_cfg
    size, mean, std = int(cfg["input_size"][1]), list(cfg["mean"]), list(cfg["std"])
    grey = tuple(int(255 * m) for m in mean)

    def blank_centre(im, frac=0.6):
        w, h = im.size
        out = im.convert("RGB").copy()
        cw, ch = int(w * frac), int(h * frac)
        box = ((w - cw) // 2, (h - ch) // 2, (w + cw) // 2, (h + ch) // 2)
        out.paste(Image.new("RGB", (box[2] - box[0], box[3] - box[1]), grey), box[:2])
        return out

    def feats(images):
        return ta.extract(net, [torch.from_numpy(ta.eval_transform(i, size, mean, std)) for i in images])

    cv_accuracy(feats([blank_centre(i) for i in imgs]), "B. ConvNeXt features, centre blanked (only the frame / background visible)")
    cv_accuracy(feats(imgs), "C. ConvNeXt features, full photo (the ceiling)")
    print("\nRead: if B is close to C (and far above chance), the photos give the answer away through background / style. Fix the photos first.")


if __name__ == "__main__":
    main()
