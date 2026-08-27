#!/usr/bin/env python3
"""Regenerate docs/img/og.png (1200x630) — the link-preview card for bookmarker.lol.

    python3 Scripts/gen_og_image.py

Needs Pillow >= 10 (variable-font support). Uses the app's bundled fonts and
the light app icon, so the card matches the landing page and the iOS app.
"""
import pathlib
from PIL import Image, ImageDraw, ImageFont

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "docs" / "img" / "og.png"
ICON = ROOT / "Branding" / "icon-light-1024.png"
BRICOLAGE = ROOT / "App" / "Fonts" / "BricolageGrotesque.ttf"
INSTRUMENT = ROOT / "App" / "Fonts" / "InstrumentSans.ttf"

W, H = 1200, 630
PAPER, INK, INK2, CORAL = "#F6F3EE", "#191510", "#6E655A", "#FF5A2D"
NAME, SITE = "bookmarker", "bookmarker.lol"
HEADLINE = ["The folder your feeds", "never gave you."]
SUB = ["Every link you save on Instagram, X, TikTok and YouTube,",
       "in one library you can actually search. For iPhone."]
MARGIN = 96


def font(path, size, weight):
    f = ImageFont.truetype(str(path), size)
    axes = f.get_variation_axes()
    values = []
    for axis in axes:
        name = axis["name"]
        name = name.decode() if isinstance(name, bytes) else name
        values.append(weight if name == "Weight" else axis["default"])
    f.set_variation_by_axes(values)
    return f


def rounded_mark(size):
    mark = Image.open(ICON).convert("RGBA").resize((size, size), Image.LANCZOS)
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=int(size * 0.235), fill=255)
    mark.putalpha(mask)
    return mark


def main():
    img = Image.new("RGB", (W, H), PAPER)
    draw = ImageDraw.Draw(img)

    mark_size = 112
    img.paste(rounded_mark(mark_size), (MARGIN, MARGIN), rounded_mark(mark_size))

    wordmark = font(BRICOLAGE, 44, 800)
    wy = MARGIN + mark_size / 2
    draw.text((MARGIN + mark_size + 24, wy), NAME, font=wordmark, fill=INK, anchor="lm")

    headline = font(BRICOLAGE, 84, 800)
    y = 268
    for line in HEADLINE:
        draw.text((MARGIN, y), line, font=headline, fill=INK, anchor="la")
        y += 92

    sub = font(INSTRUMENT, 29, 400)
    y = 490
    for line in SUB:
        draw.text((MARGIN, y), line, font=sub, fill=INK2, anchor="lm")
        y += 40

    dot_y = 583
    draw.ellipse((MARGIN, dot_y - 6, MARGIN + 12, dot_y + 6), fill=CORAL)
    draw.text((MARGIN + 24, dot_y), SITE, font=font(INSTRUMENT, 27, 700), fill=INK, anchor="lm")

    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.convert("P", palette=Image.ADAPTIVE, colors=256).save(OUT, optimize=True)
    print(f"wrote {OUT.relative_to(ROOT)} {W}x{H}")


if __name__ == "__main__":
    main()
