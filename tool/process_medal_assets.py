#!/usr/bin/env python3
"""Turn the generated 3D medal renders into transparent WebP game assets.

The ImageGen medals come back as opaque RGB squares with either a white or a
checkerboard backdrop and a soft contact shadow. On the navy passport cards
that backdrop would show as a bright box, so this script cuts it away:

  1. mark every "light neutral" pixel (bright, low chroma) - that is the
     backdrop plus the flat grey contact shadow,
  2. keep only the components of that mask that touch an image edge, so the
     medal's own silver highlights (enclosed, not edge-connected) survive,
  3. take the single largest remaining foreground blob and fill its holes,
  4. feather the silhouette, trim to a square and downscale to 256px,
  5. write assets/images/medals/<name>.webp with an alpha channel.

Run it after regenerating any medal:

    python3 tool/process_medal_assets.py [source_dir]

source_dir defaults to the ImageGen output folder.
"""

from __future__ import annotations

import glob
import os
import sys

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

SIZE = 256
# prefix in the generated file -> destination medal asset name.
MAP = {
    "first_whistle_medal": "first_whistle",
    "first_victory_medal": "first_victory",
    "hat_trick_medal": "hat_trick",
    "squad_builder_medal": "squad_builder",
    "entry_list_medal": "entry_list",
    "multi_sport_medal": "multi_sport",
    "season_regular_medal": "season_regular",
}

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "images", "medals")


def _largest_with_holes(fg: np.ndarray) -> np.ndarray:
    labels, count = ndimage.label(fg)
    if count == 0:
        return fg
    sizes = ndimage.sum(fg, labels, range(1, count + 1))
    keep = int(np.argmax(sizes)) + 1
    return ndimage.binary_fill_holes(labels == keep)


def cut(path: str) -> Image.Image:
    rgb = Image.open(path).convert("RGB")
    arr = np.asarray(rgb).astype(np.int16)
    lo = arr.min(axis=2)
    hi = arr.max(axis=2)
    light = (lo > 158) & ((hi - lo) < 38)

    labels, _ = ndimage.label(light)
    border = np.concatenate(
        [labels[0, :], labels[-1, :], labels[:, 0], labels[:, -1]]
    )
    bg_ids = {int(v) for v in np.unique(border) if v != 0}
    bg = np.isin(labels, list(bg_ids))

    fg = _largest_with_holes(~bg)

    alpha = (fg * 255).astype(np.uint8)
    alpha = np.asarray(
        Image.fromarray(alpha).filter(ImageFilter.GaussianBlur(0.7))
    )

    ys, xs = np.where(alpha > 12)
    top, bottom = int(ys.min()), int(ys.max())
    left, right = int(xs.min()), int(xs.max())
    side = max(right - left, bottom - top)
    pad = int(side * 0.07)
    cx, cy = (left + right) // 2, (top + bottom) // 2
    half = side // 2 + pad
    box = (
        max(0, cx - half),
        max(0, cy - half),
        min(rgb.width, cx + half),
        min(rgb.height, cy + half),
    )
    out = Image.fromarray(np.dstack([np.asarray(rgb), alpha]), "RGBA").crop(box)
    return out.resize((SIZE, SIZE), Image.LANCZOS)


def main() -> int:
    src_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        "~/.qoder/vibe_images"
    )
    os.makedirs(OUT_DIR, exist_ok=True)
    made = 0
    for prefix, name in MAP.items():
        matches = sorted(glob.glob(os.path.join(src_dir, f"{prefix}_*.png")))
        if not matches:
            print(f"!! missing source render for {prefix}")
            continue
        img = cut(matches[-1])
        dest = os.path.join(OUT_DIR, f"{name}.webp")
        img.save(dest, "WEBP", quality=92, method=6)
        print(f"  {name}.webp  {os.path.getsize(dest) // 1024} KB")
        made += 1
    print(f"==> wrote {made} medal assets to {OUT_DIR}")
    return 0 if made == len(MAP) else 1


if __name__ == "__main__":
    raise SystemExit(main())
