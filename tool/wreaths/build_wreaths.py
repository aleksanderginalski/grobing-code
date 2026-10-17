"""Wreath motifs for the app (ISSUE-044; grobing-vault/05_DESIGN/wieniec.md A1-A5, D13, D15).

Input: a folder with the author's images from DALL-E, one per motif, named by its key (`laur.png`, `dab.png`,
... - the keys of `WreathMotif` in lib/data/clans.dart): a white wreath on black, open at the top, in the
common frame (D13). Output: `assets/wreaths/wieniec-<key>.png` - a grey PNG with alpha, 640 x 640:

  alpha  the shape of the leaves (the white of the source);
  grey   the C3 shading as a multiplier of the line's colour, 128 = the colour itself: lighter at the ends of
         the branches and darker at the knot (+10% .. -16%), embossed leaves lit from the top left (+-22%),
         never darker than 80% of the colour (every colour of the palette keeps 3:1 on the background).

The app tints it once per motif and colour, adds the halo in the background's colour and keeps the result
(lib/app/widgets/wreath.dart): no blur at drawing time (style-b.md rule 2). The family-data guard lets only
such grey PNGs with alpha into assets/wreaths/ (grobing-agents/.claude/rules/family-data.md).

    python tool/wreaths/build_wreaths.py <folder with laur.png, dab.png, ...> [assets/wreaths]
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

SIZE = 640
KEYS = [
    "laur", "dab", "klosy", "jarzebina", "lipa", "brzoza", "klon", "kasztanowiec", "bluszcz", "dzika_roza",
    "chaber", "rumianek", "konwalia", "wrzos", "paproc", "kalina", "leszczyna", "chmiel", "jablon",
]
DARKEST = 0.80  # D15: never darker than 80% of the line's colour
GREY_ONE = 128  # the grey that means "the colour itself"


def shape(path):
    """The leaves as alpha 0..1 at SIZE: the luminance of the source, white on black."""
    grey = Image.open(path).convert("L").resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(grey).astype(np.float32) / 255.0


def shading(alpha):
    """C3: the fade of the tone (C1) times the emboss (C2), as in the discovery prototype (panel 9)."""
    rows = (np.arange(SIZE, dtype=np.float32) / SIZE)[:, None] * np.ones((1, SIZE), np.float32)
    fade = 1.10 - 0.26 * np.clip((rows - 0.15) / (0.90 - 0.15), 0.0, 1.0)
    height = Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(SIZE * 0.006))
    height = np.asarray(height).astype(np.float32) / 255.0
    gy, gx = np.gradient(height)
    lit = -(gx * -0.55 + gy * -0.83)  # light from the top left
    lit = lit / (np.percentile(np.abs(lit[alpha > 0.5]), 98) + 1e-6)
    emboss = 1.0 + 0.22 * np.clip(lit, -1.0, 1.0)
    return np.maximum(fade * emboss, DARKEST)


def build(src_dir, out_dir):
    os.makedirs(out_dir, exist_ok=True)
    missing = [k for k in KEYS if not os.path.isfile(os.path.join(src_dir, f"{k}.png"))]
    if missing:
        sys.exit(f"brak obrazów: {', '.join(missing)} (nazwy: <klucz>.png)")
    for key in KEYS:
        alpha = shape(os.path.join(src_dir, f"{key}.png"))
        grey = np.clip(np.round(shading(alpha) * GREY_ONE), 0, 255).astype(np.uint8)
        grey[alpha <= 0.0] = GREY_ONE
        image = Image.fromarray(np.dstack([grey, (alpha * 255).round().astype(np.uint8)]), "LA")
        target = os.path.join(out_dir, f"wieniec-{key}.png")
        image.save(target, optimize=True)
        print(f"{target}  {os.path.getsize(target) // 1024} KB")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    build(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else os.path.join("assets", "wreaths"))
