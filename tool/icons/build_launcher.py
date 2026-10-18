"""The launcher icon from the author's image (ISSUE-046 decision 4: L1, the candle; style-b.md rule 8).

Input: the author's DALL-E image — an amber drawing in two tones on near-black, kept OUTSIDE the repos
(README → Ikony). The drawing becomes a mask from the red channel (the background's red -> 0, the line's red -> 1),
so the colours come from the app, not from the image:

  res/mipmap-*/ic_launcher_foreground.png  the adaptive icon's foreground, 108 dp per density: the drawing in the
                                           accent (#E3A646) with its two tones, its longer side 54% of the layer
                                           — inside the 66 dp safe zone, as on the mockup;
  res/mipmap-*/ic_launcher_monochrome.png  Android 13 themed icons: the lines only (the 25% fills dropped);
  res/mipmap-*/ic_launcher.png             Android 7 (minSdk 24, no adaptive icons): the same on a rounded square
                                           of the background colour, 48 dp per density;
  <store PNG> (optional, outside the repo) the 512 x 512 icon for the Play listing.

The background layer is @color/grobing_background (res/mipmap-anydpi-v26/ic_launcher.xml).

    python tool/icons/build_launcher.py <L1-znicz.png> [<store 512 png outside the repo>]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.normpath(os.path.join(HERE, "..", "..", "android", "app", "src", "main", "res"))
AMBER = (0xE3, 0xA6, 0x46)
BACKGROUND = (0x12, 0x11, 0x10)
DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}
SYMBOL = 0.54  # the drawing's longer side as a part of the 108 dp layer: 58 dp, its farthest point 29.6 dp from the centre — inside the 66 dp safe zone (ui review; 0.44 left it under Android's 48 dp)
LINES = 0.80  # alpha above this is a line; the 25-50% fills stay out of the monochrome layer


def mask(path):
    """The drawing as alpha 0..255, cropped to itself and padded to a square."""
    red = Image.open(path).convert("RGB").getchannel("R")
    w, h = red.size
    bg = max(red.getpixel((x, y)) for x in (4, w - 5) for y in (4, h - 5))
    hist = red.histogram()
    total, acc, top = sum(hist), 0, 255
    for v in range(255, -1, -1):
        acc += hist[v]
        if acc >= total * 0.005:
            top = v
            break
    span = max(1, top - bg)
    alpha = red.point(lambda v: max(0, min(255, round((v - bg) * 255 / span))))
    box = alpha.point(lambda v: 255 if v > 20 else 0).getbbox()
    alpha = alpha.crop(box)
    side = max(alpha.size)
    square = Image.new("L", (side, side), 0)
    square.paste(alpha, ((side - alpha.width) // 2, (side - alpha.height) // 2))
    return square


def layer(alpha, canvas, part, colour):
    """The drawing in one colour, centred on a transparent canvas, its longer side `part` of the canvas."""
    size = max(1, round(canvas * part))
    a = alpha.resize((size, size), Image.LANCZOS)
    out = Image.new("RGBA", (canvas, canvas), colour + (0,))
    ink = Image.new("RGBA", (size, size), colour + (255,))
    ink.putalpha(a)
    out.alpha_composite(ink, ((canvas - size) // 2, (canvas - size) // 2))
    return out


def main(src, store=None):
    alpha = mask(src)
    lines = alpha.point(lambda v: 255 if v > LINES * 255 else 0).filter(ImageFilter.GaussianBlur(1.5))
    lines = lines.point(lambda v: 255 if v > 110 else 0)
    for name, k in DENSITIES.items():
        folder = os.path.join(RES, f"mipmap-{name}")
        os.makedirs(folder, exist_ok=True)
        px = round(108 * k)
        layer(alpha, px, SYMBOL, AMBER).save(os.path.join(folder, "ic_launcher_foreground.png"), optimize=True)
        layer(lines, px, SYMBOL, (255, 255, 255)).save(
            os.path.join(folder, "ic_launcher_monochrome.png"), optimize=True)
        legacy = round(48 * k)
        icon = Image.new("RGBA", (legacy, legacy), BACKGROUND + (0,))
        ImageDraw.Draw(icon).rounded_rectangle((0, 0, legacy - 1, legacy - 1), radius=legacy * 0.22,
                                               fill=BACKGROUND + (255,))
        icon.alpha_composite(layer(alpha, legacy, SYMBOL * 108 / 72, AMBER))
        icon.save(os.path.join(folder, "ic_launcher.png"), optimize=True)
    if store:
        full = Image.new("RGBA", (512, 512), BACKGROUND + (255,))
        full.alpha_composite(layer(alpha, 512, SYMBOL * 108 / 72, AMBER))
        full.convert("RGB").save(store, optimize=True)
    print("launcher icons written to", RES, "| store:", store or "-")


if __name__ == "__main__":
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    main(*sys.argv[1:])
