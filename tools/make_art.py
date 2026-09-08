#!/usr/bin/env python3
"""Generate the launcher icon and the startup splash from the art in art/.

Two sources, because the two outputs want different things:

  art/keyart.jpg  the 16:9 key art, for the launcher icon
  art/logo.png    the transparent wordmark, for the splash

The icon is square and the key art is not, and a centre crop that fits would cut
the wordmark in half at both ends. Rather than leave black bars, the square is
filled with the same art blown up, blurred and darkened, and the whole picture
laid sharp on top of it - the tile reads edge to edge and nothing is lost.

The splash is 16:10 and mostly empty by design, so it gets the wordmark on a dark
ground instead. Its tagline is near-black with a pale halo, drawn for a light
background, so the logo sits on a light card: a white screen in a headset is
unpleasant, and every menu behind this one is dark.

Neither source is enlarged past what it can carry - the wordmark is 416 px wide,
and much beyond twice that the lettering turns to mush.

    python tools/make_art.py
    python tools/stage_data.py     # to carry the splash into stage/
"""

import os
import sys

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
KEYART = os.path.join(ROOT, "art", "keyart.jpg")
LOGO = os.path.join(ROOT, "art", "logo.png")

# Android launcher icon, one per density bucket.
MIPMAPS = [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)]
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# The game's startup splash, at the size of the one it replaces. It goes into the
# overlay rather than straight into stage/, which stage_data.py rewrites from the
# game data every time it runs.
SPLASH = os.path.join(ROOT, "templates", "data", "data", "img", "splash.jpg")
SPLASH_SIZE = (1920, 1200)

TOP = (24, 25, 28)
BOTTOM = (10, 10, 12)
CARD = (233, 234, 238)


def ground(size):
    """A dark vertical gradient, drawn a row at a time."""
    w, h = size
    img = Image.new("RGB", (1, h))
    px = img.load()
    for y in range(h):
        t = y / float(h - 1)
        px[0, y] = tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3))
    return img.resize((w, h), Image.NEAREST)


def cover(img, size):
    """Scale to fill `size` completely, then centre-crop the overflow away."""
    w, h = size
    scale = max(w / img.width, h / img.height)
    sw, sh = max(1, int(round(img.width * scale))), max(1, int(round(img.height * scale)))
    out = img.resize((sw, sh), Image.LANCZOS)
    return out.crop(((sw - w) // 2, (sh - h) // 2, (sw - w) // 2 + w, (sh - h) // 2 + h))


def icon(art, px):
    """The key art on a blurred, darkened blow-up of itself."""
    back = cover(art, (px, px)).filter(ImageFilter.GaussianBlur(max(1.0, px / 14.0)))
    back = ImageEnhance.Brightness(back).enhance(0.45)

    fw = int(round(px * 0.96))
    fh = max(1, int(round(fw * art.height / art.width)))
    back.paste(art.resize((fw, fh), Image.LANCZOS), ((px - fw) // 2, (px - fh) // 2))
    return back


def splash(logo, size, coverage=0.45, cap=2.0):
    """The wordmark on a light card, centred on the dark ground."""
    w, h = size
    out = ground(size)

    scale = min(w * coverage / logo.width, h * coverage / logo.height, cap)
    lw, lh = int(round(logo.width * scale)), int(round(logo.height * scale))
    resized = logo.resize((lw, lh), Image.LANCZOS)

    pad = int(round(lh * 0.10))
    cw, ch = lw + 2 * pad, lh + 2 * pad

    card = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle((0, 0, cw - 1, ch - 1),
                                           radius=int(round(ch * 0.09)), fill=CARD)
    card.paste(resized, (pad, pad), resized)

    out.paste(card, ((w - cw) // 2, (h - ch) // 2), card)
    return out


def main():
    for path in (KEYART, LOGO):
        if not os.path.exists(path):
            print("missing %s" % path, file=sys.stderr)
            return 1

    art = Image.open(KEYART).convert("RGB")
    logo = Image.open(LOGO).convert("RGBA")
    print("key art: %dx%d, logo: %dx%d" % (art.width, art.height, logo.width, logo.height))

    for density, px in MIPMAPS:
        path = os.path.join(RES, "mipmap-" + density, "ic_launcher.png")
        icon(art, px).save(path)
        print("icon:   %s %dx%d" % (path, px, px))

    os.makedirs(os.path.dirname(SPLASH), exist_ok=True)
    splash(logo, SPLASH_SIZE).save(SPLASH, quality=92)
    print("splash: %s %dx%d" % ((SPLASH,) + SPLASH_SIZE))
    print("run tools/stage_data.py to carry the splash into stage/")

    return 0


if __name__ == "__main__":
    sys.exit(main())
