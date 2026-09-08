#!/usr/bin/env python3
"""Generate the launcher icon and the startup splash from art/logo.png.

The source is a wide transparent wordmark on a checkered flag, so both outputs
are the same composition - the logo laid on a dark ground - at two very
different shapes: a square for the Quest library tile, and 16:10 for the splash
the game shows while it loads.

The ground is near black rather than pure black so the flag's dark squares stay
distinguishable from it, with a slight vertical lift so a full screen of it does
not look like a dead panel. The logo is never enlarged past what the source can
carry: it is 416 px wide, and pushing it much beyond twice that turns the
lettering to mush.

    python tools/make_art.py
"""

import os
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, "art", "logo.png")

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

# The wordmark's tagline is near-black with a pale halo, drawn for a light
# background: on the dark ground it is there but not readable. Rather than give
# up the dark ground - a white screen in a headset is unpleasant, and every menu
# behind this one is dark - the logo sits on a light card, which is how the
# artwork reads as it was drawn.
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


def compose(logo, size, coverage, cap=2.0):
    """Centre the logo on the ground, filling `coverage` of the width."""
    w, h = size
    out = ground(size)

    scale = min(w * coverage / logo.width, h * coverage / logo.height, cap)
    lw, lh = int(round(logo.width * scale)), int(round(logo.height * scale))
    resized = logo.resize((lw, lh), Image.LANCZOS)

    pad = int(round(lh * 0.10))
    cw, ch = lw + 2 * pad, lh + 2 * pad
    cx, cy = (w - cw) // 2, (h - ch) // 2

    card = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle((0, 0, cw - 1, ch - 1),
                                           radius=int(round(ch * 0.09)), fill=CARD)
    card.paste(resized, (pad, pad), resized)

    out.paste(card, (cx, cy), card)
    return out


def main():
    if not os.path.exists(SOURCE):
        print("missing %s" % SOURCE, file=sys.stderr)
        return 1

    logo = Image.open(SOURCE).convert("RGBA")
    print("source: %s %dx%d" % (SOURCE, logo.width, logo.height))

    # The icon is a small tile, so the logo takes nearly all of it; a wide image
    # on a square leaves the bands above and below regardless.
    for density, px in MIPMAPS:
        path = os.path.join(RES, "mipmap-" + density, "ic_launcher.png")
        # No cap here: at 192 px the logo is being shrunk, not stretched.
        compose(logo, (px, px), 0.92, cap=1e9).save(path)
        print("icon:   %s %dx%d" % (path, px, px))

    os.makedirs(os.path.dirname(SPLASH), exist_ok=True)
    compose(logo, SPLASH_SIZE, 0.45).save(SPLASH, quality=92)
    print("splash: %s %dx%d" % ((SPLASH,) + SPLASH_SIZE))
    print("run tools/stage_data.py to carry it into stage/")

    return 0


if __name__ == "__main__":
    sys.exit(main())
