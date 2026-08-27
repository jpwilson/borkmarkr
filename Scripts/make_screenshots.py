#!/usr/bin/env python3
"""Build App Store marketing screenshots from simulator captures.

App Store screenshots are just images at the required pixel size — they don't
have to be raw captures, and almost nothing in the top charts is. What ships is
a real screenshot composited onto a designed background with a headline. Apple's
rule is that the image must show the app as it actually is; framing, captions
and backgrounds around a genuine capture are fine, inventing UI is not.

Everything here wraps an unretouched 1320x2868 simulator capture. Nothing is
drawn over the app's own pixels.

    Scripts/capture_screenshots.sh        # take the captures
    venv/bin/python Scripts/make_screenshots.py   # frame them

Output: Marketing/screenshots/*.png at 1320x2868, ready to upload.
"""

import math
import pathlib
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "Marketing" / "screenshots"

W, H = 1320, 2868

# ── Panels ───────────────────────────────────────────────────────────────────
# One per uploaded screenshot, in order. Colours are the app's own accent ramp
# and taxonomy hues, so the store page and the app read as the same product.

PANELS = [
    {
        "shot": "library.png",
        "top": "#FF6B3D", "bottom": "#D8380F",
        "head": ["Everything you", "saved. One place."],
        "sub": "Instagram, X, TikTok, YouTube — one library you can actually search.",
    },
    {
        # Blue, not green: the Browse grid is a wall of saturated topic tiles,
        # several of them green. A green panel behind it flattened the whole
        # image. Blue barely appears in the taxonomy hues, so the grid pops.
        "shot": "browse.png",
        "top": "#3E96F5", "bottom": "#12559E",
        "head": ["It files itself", "as you save."],
        "sub": "50 topics, 600+ subtopics. Change anything it gets wrong.",
    },
    {
        "shot": "search.png",
        "top": "#8B6BFF", "bottom": "#4F2FC4",
        "head": ["Find it again", "in seconds."],
        "sub": "Search titles, tags, notes and people across every app at once.",
    },
]

# ── Layout ───────────────────────────────────────────────────────────────────

MARGIN = 96
HEAD_TOP = 250
HEAD_SIZE = 116
HEAD_LEAD = 132
SUB_SIZE = 44

PHONE_W = 940          # width of the framed device, before rotation
PHONE_TOP = 820        # y of the device's top edge
BEZEL = 20             # dark border thickness
CORNER = 108           # screen corner radius at full size
TILT = -5.0            # degrees; negative leans left like the reference


def font(size: int, weight: str = "Bold") -> ImageFont.FreeTypeFont:
    """System font at a given weight, falling back through what macOS ships."""
    try:
        f = ImageFont.truetype("/System/Library/Fonts/SFNS.ttf", size)
        try:
            f.set_variation_by_name(weight)
        except Exception:
            pass
        return f
    except OSError:
        index = {"Bold": 1, "Regular": 0, "Heavy": 1}.get(weight, 0)
        return ImageFont.truetype("/System/Library/Fonts/HelveticaNeue.ttc", size, index=index)


def gradient(top: str, bottom: str) -> Image.Image:
    """Vertical gradient, drawn a row at a time — the canvas is only 2868 tall."""
    r1, g1, b1 = Image.new("RGB", (1, 1), top).getpixel((0, 0))
    r2, g2, b2 = Image.new("RGB", (1, 1), bottom).getpixel((0, 0))
    base = Image.new("RGB", (W, H))
    draw = ImageDraw.Draw(base)
    for y in range(H):
        t = y / (H - 1)
        draw.line(
            [(0, y), (W, y)],
            fill=(round(r1 + (r2 - r1) * t),
                  round(g1 + (g2 - g1) * t),
                  round(b1 + (b2 - b1) * t)),
        )
    return base


def glow(base: Image.Image) -> None:
    """A soft light bloom behind the device, so it lifts off the flat panel."""
    layer = Image.new("L", (W, H), 0)
    ImageDraw.Draw(layer).ellipse(
        [W // 2 - 620, PHONE_TOP - 200, W // 2 + 620, PHONE_TOP + 1500], fill=64
    )
    layer = layer.filter(ImageFilter.GaussianBlur(220))
    base.paste(Image.new("RGB", (W, H), "white"), (0, 0), layer)


def framed(shot: Image.Image) -> Image.Image:
    """The capture inside a device body, rotated, with a shadow. RGBA."""
    scale = PHONE_W / shot.width
    sw, sh = PHONE_W, round(shot.height * scale)
    screen = shot.resize((sw, sh), Image.LANCZOS).convert("RGBA")

    # Round the screen corners.
    mask = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, sw - 1, sh - 1],
                                           radius=round(CORNER * scale), fill=255)
    screen.putalpha(mask)

    # Body: a slightly larger rounded rect behind the screen.
    bw, bh = sw + BEZEL * 2, sh + BEZEL * 2
    body = Image.new("RGBA", (bw, bh), (0, 0, 0, 0))
    ImageDraw.Draw(body).rounded_rectangle(
        [0, 0, bw - 1, bh - 1], radius=round(CORNER * scale) + BEZEL,
        fill=(22, 19, 16, 255),
    )
    body.alpha_composite(screen, (BEZEL, BEZEL))

    # Shadow, cast before rotation so it turns with the device.
    pad = 140
    canvas = Image.new("RGBA", (bw + pad * 2, bh + pad * 2), (0, 0, 0, 0))
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [pad, pad + 26, pad + bw, pad + bh + 26],
        radius=round(CORNER * scale) + BEZEL, fill=(0, 0, 0, 110),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(46)))
    canvas.alpha_composite(body, (pad, pad))

    return canvas.rotate(TILT, resample=Image.BICUBIC, expand=True)


def build(panel: dict, shots: pathlib.Path, index: int) -> pathlib.Path:
    shot = Image.open(shots / panel["shot"])
    if shot.size != (W, H):
        raise SystemExit(f"{panel['shot']} is {shot.size}, expected {(W, H)} — "
                         "capture on an iPhone 17 Pro Max simulator.")

    base = gradient(panel["top"], panel["bottom"])
    glow(base)
    draw = ImageDraw.Draw(base)

    head = font(HEAD_SIZE, "Bold")
    sub = font(SUB_SIZE, "Regular")

    y = HEAD_TOP
    for line in panel["head"]:
        draw.text((MARGIN, y), line, font=head, fill=(255, 255, 255))
        y += HEAD_LEAD

    # Short rule under the headline — echoes the app's accent underline.
    y += 18
    draw.rounded_rectangle([MARGIN, y, MARGIN + 120, y + 9], radius=5,
                           fill=(255, 255, 255, 200))
    y += 52

    for line in wrap(panel["sub"], sub, W - MARGIN * 2, draw):
        draw.text((MARGIN, y), line, font=sub, fill=(255, 255, 255, 214))
        y += SUB_SIZE + 14

    device = framed(shot)
    # Centre horizontally, allowing for the width the rotation added.
    x = (W - device.width) // 2
    top = PHONE_TOP - round(device.width * math.sin(math.radians(abs(TILT))) / 2)
    base.paste(device, (x, top), device)

    OUT.mkdir(parents=True, exist_ok=True)
    path = OUT / f"{index:02d}-{panel['shot']}"
    base.save(path)
    return path


def wrap(text: str, f: ImageFont.FreeTypeFont, width: int, draw) -> list[str]:
    words, lines, line = text.split(), [], ""
    for word in words:
        trial = f"{line} {word}".strip()
        if draw.textlength(trial, font=f) <= width:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def main() -> None:
    shots = ROOT / "Marketing" / "captures"
    if not shots.exists():
        raise SystemExit(f"No captures in {shots} — run Scripts/capture_screenshots.sh first")
    for i, panel in enumerate(PANELS, start=1):
        print("wrote", build(panel, shots, i).relative_to(ROOT))


if __name__ == "__main__":
    main()

# App Store Connect also has a 6.5" slot (1284x2778). Same aspect ratio to
# within 0.4%, so a resize plus a 6px trim top and bottom is pixel-honest.
def also_65(path):
    from PIL import Image
    im = Image.open(path).convert("RGB").resize((1284, 2790), Image.LANCZOS)
    im = im.crop((0, 6, 1284, 2784))
    out = path.parent.parent / "screenshots-6.5" / path.name
    out.parent.mkdir(parents=True, exist_ok=True)
    im.save(out, optimize=True)
    print("wrote", out)

if __name__ == "__main__":
    import pathlib as _pl
    for f in sorted(_pl.Path("Marketing/screenshots").glob("*.png")):
        also_65(f)
