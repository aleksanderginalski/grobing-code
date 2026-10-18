"""The app's icon font and its glyph constants (ISSUE-046; grobing-vault/05_DESIGN/brand/style-b.md rule 3).

Input:
  - Google's Material Symbols Rounded variable font and its .codepoints file (Apache-2.0,
    github.com/google/material-design-icons, folder variablefont/; README → Ikony pins the commit);
  - the author's icon sheet from DALL-E (decision 1' of ISSUE-046): 3 × 3 amber icons in two tones on near-black,
    kept OUTSIDE the repos. Its nine icons replace the Material ones named in SHEET;
  - the author's candle (style-b.md rule 8) from DALL-E, also outside the repos: in two tones (Glyphs.candle — the logo,
    buttons) and solid with its details cut out (Glyphs.candleSolid — inside a pin, the mark of the dead in the tree).

Output:
  assets/fonts/grobing-symbols.ttf  the Material font cut down to tool/icons/glyphs.txt, with the FILL, GRAD, opsz and
                                    wght axes and the layout closure (some icons swap glyphs along FILL through GSUB
                                    feature variations, and Flutter's own icon tree shaker drops those glyphs — so the
                                    app draws this font as text, never through IconData), plus the sheet's icons
                                    traced to outlines: for each, a line glyph and a fill glyph (the silhouette, drawn
                                    at 25% under the lines), at free code points of the Private Use Area;
  lib/app/widgets/glyphs.dart       one `Glyph` constant per line of glyphs.txt, named in lowerCamelCase.

    python tool/icons/build_symbols.py <MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf> <...codepoints> <sheet.png>
        <Z-znicz.png> <Z-znicz-pelny.png>

Needs fontTools, potracer, numpy and Pillow (`python -m pip install fonttools potracer numpy pillow`).
"""
import os
import sys

import numpy as np
import potrace
from fontTools import subset
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
FONT_OUT = os.path.join(ROOT, "assets", "fonts", "grobing-symbols.ttf")
DART_OUT = os.path.join(ROOT, "lib", "app", "widgets", "glyphs.dart")
AXES = {"FILL", "GRAD", "opsz", "wght"}

# The author's sheet, row by row: the Material name each of its icons takes the place of.
SHEET = ["map", "group", "nature", "search", "settings", "add_photo_alternate", "add_location_alt", "ink_pen", "cast"]
LINE = 0.55  # alpha above this is a line of the drawing (0.4 took the leaves' fill into the lines and merged the tree)
THICKEN = 12  # the sheet's lines widened by this many font units (≈ 0.3 dp at 24 dp): at 0.6–0.75 dp they stood beside
# Material's 1.5 dp (weight 300) as a second weight; +0.5 dp merged the tree's crown (ui review, probe thicken-x2)
SILHOUETTE = 0.15  # alpha above this is inside the drawing (lines and their 25% fills); the glow stays under it
UP = 3  # trace at 3 × the sheet's resolution, for smoother outlines
BOX = 800  # the drawing's longer side in font units: the 20 dp live area of a 24 dp icon, as Material's (960 = 24 dp)


def camel(name):
    head, *rest = name.split("_")
    return head + "".join(p[:1].upper() + p[1:] for p in rest)


def sheet_cells(path, grid=3):
    """The drawings of a grid × grid sheet (1: one drawing) as alpha 0..1 (from the red channel), each cropped to
    itself."""
    red = np.asarray(Image.open(path).convert("RGB").getchannel("R"), dtype=np.float32)
    h, w = red.shape
    cells = []
    for i in range(grid * grid):
        r, c = divmod(i, grid)
        cell = red[r * h // grid : (r + 1) * h // grid, c * w // grid : (c + 1) * w // grid]
        bg = float(np.median(np.concatenate([cell[:6].ravel(), cell[-6:].ravel(), cell[:, :6].ravel(), cell[:, -6:].ravel()])))
        top = float(np.percentile(cell, 99.5))
        alpha = np.clip((cell - bg) / max(1.0, top - bg), 0, 1)
        ys, xs = np.nonzero(alpha > SILHOUETTE)
        cells.append(alpha[ys.min() : ys.max() + 1, xs.min() : xs.max() + 1])
    return cells


HOLE_AREA = 900  # a dark region enclosed by the drawing and larger than ~30 × 30 px of the sheet …
HOLE_ALPHA = 0.06  # … and this dark on average is a real hole (the gear's centre); smaller or lighter ones are fill


def fill_mask(alpha):
    """The fill layer: everything inside the drawing's outer edge, except real holes. Thresholding the fill itself
    traced DALL-E's darker texture inside a fill (the gear) as blotches, so the inside is what the background cannot
    reach from the border, and only large, dark enclosed regions stay open."""
    drawn = alpha > SILHOUETTE
    h, w = drawn.shape
    # The background: flood from a margin around the drawing over everything not drawn.
    canvas = Image.new("L", (w + 2, h + 2), 0)
    canvas.paste(Image.fromarray((drawn * 255).astype(np.uint8), "L"), (1, 1))
    ImageDraw.floodfill(canvas, (0, 0), 128)
    inside = np.asarray(canvas)[1:-1, 1:-1] != 128
    # Enclosed regions that are not drawn (4-connected): each one is a hole or a gap in the texture.
    candidates = inside & ~drawn
    mask = inside.copy()
    seen = np.zeros_like(candidates)
    for y0, x0 in np.argwhere(candidates):
        if seen[y0, x0]:
            continue
        seen[y0, x0] = True
        stack, part = [(y0, x0)], []
        while stack:
            y, x = stack.pop()
            part.append((y, x))
            for ny, nx in ((y + 1, x), (y - 1, x), (y, x + 1), (y, x - 1)):
                if 0 <= ny < h and 0 <= nx < w and candidates[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        if len(part) > HOLE_AREA:
            ys, xs = zip(*part)
            if alpha[ys, xs].mean() < HOLE_ALPHA:
                mask[ys, xs] = False
    return mask.astype(np.float32)


def trace(alpha, threshold, grow=0):
    """potrace curves of alpha > threshold, traced at UP × the size, in that up-scaled pixel space; grow widens
    the shape by that many up-scaled pixels on each side (the lines — THICKEN)."""
    img = Image.fromarray((alpha * 255).astype(np.uint8), "L")
    img = img.resize((img.width * UP, img.height * UP), Image.LANCZOS).filter(ImageFilter.GaussianBlur(UP / 2))
    img = img.point(lambda v: 255 if v > threshold * 255 else 0)
    if grow > 0:
        img = img.filter(ImageFilter.MaxFilter(2 * grow + 1))
    shape = np.asarray(img) > 127
    return potrace.Bitmap(~shape).trace(turdsize=6 * UP * UP, alphamax=1.0, opticurve=True, opttolerance=0.2)


def glyph(curves, size):
    """A TrueType glyph from potrace curves: the drawing centred in the 960-unit icon square, longer side BOX."""
    width, height = size
    scale = BOX / max(width, height)
    dx = (960 - width * scale) / 2
    dy = (960 - height * scale) / 2

    def pt(p):
        return (dx + p.x * scale, 960 - dy - p.y * scale)

    tt = TTGlyphPen(None)
    pen = Cu2QuPen(tt, max_err=1.0, reverse_direction=False)
    for curve in curves:
        pen.moveTo(pt(curve.start_point))
        for seg in curve:
            if seg.is_corner:
                pen.lineTo(pt(seg.c))
                pen.lineTo(pt(seg.end_point))
            else:
                pen.curveTo(pt(seg.c1), pt(seg.c2), pt(seg.end_point))
        pen.closePath()
    return tt.glyph()


def main(font_path, codepoints_path, sheet_path, candle_path, candle_solid_path):
    names = []
    with open(os.path.join(HERE, "glyphs.txt"), encoding="utf-8") as fh:
        for line in fh:
            line = line.split("#", 1)[0].strip()
            if line:
                names.append(line)
    codepoints = {}
    with open(codepoints_path, encoding="utf-8") as fh:
        for line in fh:
            parts = line.split()
            if len(parts) == 2:
                codepoints.setdefault(parts[0], int(parts[1], 16))
    missing = [n for n in names if n not in codepoints]
    if missing:
        sys.exit(f"not in the font: {missing}")
    if not set(SHEET) <= set(names):
        sys.exit(f"the sheet's names must be in glyphs.txt: {sorted(set(SHEET) - set(names))}")

    options = subset.Options()
    options.layout_features = ["*"]
    options.layout_closure = True
    options.notdef_outline = True
    options.name_IDs = ["*"]
    options.name_languages = ["*"]
    options.hinting = False
    options.glyph_names = False
    font = TTFont(font_path)
    used = set(font.getBestCmap())
    subsetter = subset.Subsetter(options)
    subsetter.populate(unicodes=[codepoints[n] for n in names if n not in SHEET])
    subsetter.subset(font)
    axes = {a.axisTag for a in font["fvar"].axes}
    if axes != AXES:
        sys.exit(f"axes {sorted(axes)}, expected {sorted(AXES)}")

    # The sheet's icons: two static glyphs each (no variations — the axes do not change them), at code points the
    # full Material font does not use, from the top of the BMP Private Use Area down.
    free = (cp for cp in range(0xF8FF, 0xE000, -1) if cp not in used)
    order = font.getGlyphOrder()
    glyf, hmtx, gvar = font["glyf"], font["hmtx"], font["gvar"]

    def add(gname, source, threshold, widen, size):
        g = glyph(trace(source, threshold, widen), size)
        g.recalcBounds(glyf)
        order.append(gname)
        glyf[gname] = g
        hmtx[gname] = (960, getattr(g, "xMin", 0))
        gvar.variations[gname] = []
        cp = next(free)
        for table in font["cmap"].tables:
            table.cmap[cp] = gname
        return cp

    def two_tones(name, alpha):
        size = (alpha.shape[1] * UP, alpha.shape[0] * UP)
        grow = round(THICKEN / 2 * max(size) / BOX)  # font units → up-scaled pixels of this drawing
        return [
            add(f"grobing.{name}.line", alpha, LINE, grow, size),
            add(f"grobing.{name}.fill", fill_mask(alpha), 0.5, 0, size),
        ]

    sheet_codes = {name: two_tones(name, alpha) for name, alpha in zip(SHEET, sheet_cells(sheet_path))}
    # The candle — the app's sign (style-b.md rule 8): the author's candle in two tones, and the same candle solid with
    # its details cut out (inside a pin, the mark of the dead in the tree).
    (candle,) = sheet_cells(candle_path, grid=1)
    (solid,) = sheet_cells(candle_solid_path, grid=1)
    extra_codes = {
        "candle": two_tones("candle", candle),
        "candleSolid": [add("grobing.candle.solid", solid, 0.5, 0, (solid.shape[1] * UP, solid.shape[0] * UP))],
    }
    font.setGlyphOrder(order)
    # Advance widths do not vary (every icon is 960 wide); HVAR maps glyphs by index and would not cover the new ones.
    if "HVAR" in font:
        del font["HVAR"]
    version = font["name"].getDebugName(5)
    os.makedirs(os.path.dirname(FONT_OUT), exist_ok=True)
    font.save(FONT_OUT)

    lines = [
        "// GENERATED by tool/icons/build_symbols.py from tool/icons/glyphs.txt — do not edit by hand.",
        f"// Material Symbols Rounded, {version} (Apache-2.0), and the author's sheet traced (ISSUE-046); README → Ikony.",
        "",
        "import 'grobing_icon.dart';",
        "",
        "/// The icons of the app (style-b.md rule 3), drawn by [GrobingIcon] from assets/fonts/grobing-symbols.ttf.",
        "abstract final class Glyphs {",
    ]
    for n in names:
        if n in sheet_codes:
            line, fill = sheet_codes[n]
            lines.append("  /// From the author's sheet (line and fill glyphs).")
            lines.append(f"  static const Glyph {camel(n)} = Glyph(0x{line:x}, fill: 0x{fill:x});")
        else:
            lines.append(f"  static const Glyph {camel(n)} = Glyph(0x{codepoints[n]:x});")
    lines.append("")
    lines.append("  /// The candle, the app's sign (style-b.md rule 8) — the author's drawing in two tones.")
    lines.append(f"  static const Glyph candle = Glyph(0x{extra_codes['candle'][0]:x}, fill: 0x{extra_codes['candle'][1]:x});")
    lines.append("  /// The same candle solid, its details cut out: inside a pin and the mark of the dead in the tree.")
    lines.append(f"  static const Glyph candleSolid = Glyph(0x{extra_codes['candleSolid'][0]:x});")
    lines.append("}")
    with open(DART_OUT, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")
    print(f"{len(names)} glyphs ({len(SHEET)} from the sheet), {len(font.getGlyphOrder())} in the font, "
          f"{os.path.getsize(FONT_OUT)} B, {version}")


if __name__ == "__main__":
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    main(*sys.argv[1:])
