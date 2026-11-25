#!/usr/bin/env python3
"""Build the website's screenshots from the simulator captures.

    bash Scripts/capture_screenshots.sh         # take the captures
    python3 Scripts/make_web_screenshots.py     # make docs/img/* from them

or both, with the App Store panels: bash Scripts/refresh_screenshots.sh

The site shows the app with its covers drawn as clay. Screens whose captures
carry real creators' thumbnails (the Library, search) are published from their
`-neutral` twin, the same launch with `-neutralCovers`. The thumbnails come
back only as motion: `docs/live-covers.js` lays a "live sheet" over a neutral
phone and cross-fades each cover between the two.

The covers are found, not measured: each pair differs only where a thumbnail
replaces clay, so the bounding boxes of the difference are the covers. The
script fails rather than guessing when a pair doesn't look like that (no
difference at all, or a difference that isn't a 4:3 card cover or a square row
cover), and rewrites the table between `covers:begin` and `covers:end` in
`docs/live-covers.js`, so a new layout needs only a rerun.

Writes, at the sizes and in the recipes the site has always used:
  docs/img/library.{webp,jpg,png}   neutral Library (the /app/ hero)
  docs/img/library-live.webp        its thumbnails, paper outside the covers
  docs/img/search.{webp,png}        neutral search
  docs/img/browse.{webp,jpg,png}    Browse (no thumbnails)
  docs/img/dial.{webp,jpg}          the dial (no thumbnails)
  docs/img/press/0{1,2,3}-*.jpg     the press kit's three, neutral, with the
                                    sizes quoted on docs/press/index.html
`docs/img/you.*` is not made here: it is a signed-out frame and the captures
are signed in. Pillow only.
"""

import json
import os
import pathlib
import re

from PIL import Image, ImageChops

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOTS = pathlib.Path(os.environ.get("SHOTS", ROOT / "Marketing" / "captures"))
DOCS = pathlib.Path(os.environ.get("DOCS", ROOT / "docs"))
IMG = DOCS / "img"

W, H = 1320, 2868          # an iPhone 17 Pro Max capture
WEB = (600, 1304)          # .webp / .jpg, and the live sheet
SMALL = (405, 880)         # .png (JSON-LD screenshots)
PRESS = (303, 660)         # press kit downloads

# Captures that show creators' thumbnails, each with a `<name>-neutral` twin.
PAIRS = ("library", "search", "scoped", "topic")
# Of those, the screens a page animates (`data-live="<name>"` on a phone's
# `.screen`): each gets `<name>-live.webp` and a row in live-covers.js.
LIVE = ("library",)

DIFF_MIN = 8               # a channel difference above this is a real change
CARD, ROW = 4 / 3, 1.0     # cover shapes: Library cards, list rows
SHAPE_TOLERANCE = 0.04
MIN_SIDE = 90              # capture px; a row cover is 168
CLIP_OUTSET = 2            # sheet px around each cover the page shows
PAPER_MARGIN = 6           # sheet px around each cover the sheet keeps
SHEET_QUALITY = 80


def capture(name: str) -> Image.Image:
    path = SHOTS / f"{name}.png"
    if not path.exists():
        raise SystemExit(f"No {path.name} in {SHOTS}. Run Scripts/capture_screenshots.sh first.")
    image = Image.open(path).convert("RGB")
    if image.size != (W, H):
        raise SystemExit(f"{path.name} is {image.size}, expected {(W, H)}: "
                         "capture on an iPhone 17 Pro Max simulator.")
    return image


def runs(flags, gap: int = 2) -> list[tuple[int, int]]:
    """[start, end) spans of truthy flags, joining gaps of `gap` or fewer."""
    spans: list[list[int]] = []
    for i, on in enumerate(flags):
        if not on:
            continue
        if spans and i - spans[-1][1] <= gap:
            spans[-1][1] = i + 1
        else:
            spans.append([i, i + 1])
    return [(a, b) for a, b in spans]


def cover_rects(name: str) -> list[tuple[int, int, int, int]]:
    """The covers on `name`: where its capture and its neutral twin differ.

    Row bands, then column runs inside each band, then the bounding box of
    what differs in each cell. Reading order (top to bottom, left to right).
    """
    thumb, neutral = capture(name), capture(f"{name}-neutral")
    r, g, b = ImageChops.difference(thumb, neutral).split()
    mask = ImageChops.lighter(ImageChops.lighter(r, g), b).point(lambda v: 255 if v > DIFF_MIN else 0)
    rects = []
    for top, bottom in runs(mask.getprojection()[1]):
        band = mask.crop((0, top, W, bottom))
        for left, right in runs(band.getprojection()[0]):
            box = band.crop((left, 0, right, bottom - top)).getbbox()
            if box:
                rects.append((left + box[0], top + box[1], left + box[2], top + box[3]))
    if not rects:
        raise SystemExit(f"{name}.png and {name}-neutral.png are identical: the thumbnails "
                         "didn't load (is the simulator online?) or -neutralCovers did nothing.")
    for rect in rects:
        x0, y0, x1, y1 = rect
        w, h = x1 - x0, y1 - y0
        if min(w, h) < MIN_SIDE or not any(abs(w / h - shape) <= shape * SHAPE_TOLERANCE for shape in (CARD, ROW)):
            raise SystemExit(f"{name}: the pair differs at {rect} ({w}x{h}), which is not a 4:3 or "
                             "square cover. Something besides the covers changed between the two "
                             "shots; retake them.")
    return rects


def sheet_box(rect, margin: int) -> tuple[int, int, int, int]:
    """A capture rect in sheet pixels, grown by `margin` and kept on the sheet."""
    sx, sy = WEB[0] / W, WEB[1] / H
    x0, y0, x1, y1 = rect
    return (max(0, int(x0 * sx) - margin), max(0, int(y0 * sy) - margin),
            min(WEB[0], -int(-x1 * sx // 1) + margin), min(WEB[1], -int(-y1 * sy // 1) + margin))


def clip(rect) -> str:
    """`clip-path: inset()` for a capture rect, as percentages of the frame."""
    x0, y0, x1, y1 = sheet_box(rect, CLIP_OUTSET)
    pct = lambda part, whole: f"{part / whole * 100:.2f}%"
    return " ".join([pct(y0, WEB[1]), pct(WEB[0] - x1, WEB[0]), pct(WEB[1] - y1, WEB[1]), pct(x0, WEB[0])])


def live_sheet(name: str, rects) -> pathlib.Path:
    """The thumbnail capture at web size, with paper everywhere but the covers.

    Only the covers are ever shown (each layer is clipped to one), so the rest
    is flattened to the screen's paper colour and costs nearly nothing. The
    margin keeps the encoder's edge away from the clip.
    """
    full = capture(name).resize(WEB, Image.LANCZOS)
    paper = max(full.getcolors(WEB[0] * WEB[1]))[1]
    sheet = Image.new("RGB", WEB, paper)
    for rect in rects:
        box = sheet_box(rect, PAPER_MARGIN)
        sheet.paste(full.crop(box), box[:2])
    path = IMG / f"{name}-live.webp"
    sheet.save(path, "WEBP", quality=SHEET_QUALITY, method=6)
    return path


def publish_table(table: dict[str, list[str]]) -> None:
    script = DOCS / "live-covers.js"
    text = script.read_text()
    pattern = re.compile(r"(/\* covers:begin[^*]*\*/)(.*?)(\n[ \t]*/\* covers:end \*/)", re.S)
    if not pattern.search(text):
        raise SystemExit(f"{script} has no covers:begin / covers:end markers.")
    body = "\n  var COVERS = " + json.dumps(table, separators=(",", ":")) + ";"
    script.write_text(pattern.sub(lambda m: m.group(1) + body + m.group(3), text, count=1))


def web(image: Image.Image, name: str, jpg: bool = True, png: bool = True) -> None:
    """The site's recipe; it reproduces the committed files byte for byte."""
    small = image.resize(WEB, Image.LANCZOS)
    small.save(IMG / f"{name}.webp", "WEBP", quality=80, method=6)
    if jpg:
        small.save(IMG / f"{name}.jpg", "JPEG", quality=82, progressive=True, optimize=True)
    if png:
        image.resize(SMALL, Image.LANCZOS).quantize(256, method=Image.Quantize.MEDIANCUT).save(
            IMG / f"{name}.png", "PNG", optimize=True)


def press(image: Image.Image, file: str) -> int:
    path = IMG / "press" / f"{file}.jpg"
    image.resize(PRESS, Image.LANCZOS).save(path, "JPEG", quality=85, progressive=True, optimize=True)
    return path.stat().st_size


def quote_press_sizes(sizes: dict[str, int]) -> None:
    """Keep "JPG, 43 KB" on the press page true to the files."""
    page = DOCS / "press" / "index.html"
    text = page.read_text()
    for file, size in sizes.items():
        pattern = re.compile(r'(href="/img/press/' + re.escape(file) + r'\.jpg">Download<span class="meta"> — JPG, )\d+( KB)')
        if not pattern.search(text):
            raise SystemExit(f"{page}: no size quoted for {file}.jpg")
        text = pattern.sub(lambda m: f"{m.group(1)}{round(size / 1000)}{m.group(2)}", text)
    page.write_text(text)


def main() -> None:
    covers = {}
    for name in PAIRS:
        covers[name] = cover_rects(name)
        print(f"{name}: {len(covers[name])} covers", " ".join(f"{r}" for r in covers[name]))

    table = {}
    for name in LIVE:
        print("wrote", live_sheet(name, covers[name]))
        table[name] = [clip(rect) for rect in covers[name]]
    publish_table(table)
    print("wrote", DOCS / "live-covers.js", json.dumps(table))

    library, search = capture("library-neutral"), capture("search-neutral")
    browse, dial = capture("browse"), capture("dial")
    web(library, "library")
    web(search, "search", jpg=False)
    web(browse, "browse")
    web(dial, "dial", png=False)
    sizes = {"01-library": press(library, "01-library"),
             "02-browse": press(browse, "02-browse"),
             "03-search": press(search, "03-search")}
    quote_press_sizes(sizes)
    print("wrote docs/img/{library,search,browse,dial}.* and docs/img/press/*", sizes)


if __name__ == "__main__":
    main()
