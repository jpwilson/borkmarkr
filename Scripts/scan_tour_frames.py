#!/usr/bin/env python3
"""Walk the Library Island tour and fail on any frame that is nearly one colour.

    python3 -m http.server 8771 -d docs
    python3 Scripts/scan_tour_frames.py

The flight is a long interpolation through a world with a 70-metre canopy
standing on it, so it is easy for a keyframe to be legal — above the ground,
pointing at the right place — and still put the lens inside a tree or under a
ridge. That failure looks like one thing from the outside: a frame of flat
green or flat dark. This renders the whole tour at a low resolution and flags
any sample whose pixels barely vary, or whose middle is dominated by a single
colour, which is cheap enough to run on every change to the camera.
"""
import io
import json
import sys

import numpy as np
from PIL import Image
from playwright.sync_api import sync_playwright

URL = "http://127.0.0.1:8771/palace/?capture"
ARGS = ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader",
        "--ignore-gpu-blocklist", "--disable-lcd-text"]
W, H = 480, 270
STEP = 2.0

# the HUD is opaque chrome and would hide a flat frame behind it, so the test
# looks at the render only
HIDE = "for (const id of ['topbar','log','card','tip','transport','inset','grade','labels']) { const n = document.getElementById(id); if (n) n.style.display = 'none'; }"

MIN_STD = 11.0        # per-channel spread over the whole frame
MAX_DOMINANT = 0.70   # share of the centre box sitting in one coarse colour bin


def measure(png: bytes):
    a = np.asarray(Image.open(io.BytesIO(png)).convert("RGB"), dtype=np.float32)
    std = float(a.reshape(-1, 3).std(axis=0).mean())
    h, w, _ = a.shape
    mid = a[h // 4: 3 * h // 4, w // 4: 3 * w // 4].reshape(-1, 3)
    # 32-level bins: "the same colour" to an eye, not to a float comparison
    bins = (mid // 32).astype(np.int32)
    keys = bins[:, 0] * 64 + bins[:, 1] * 8 + bins[:, 2]
    dominant = float(np.bincount(keys).max()) / len(keys)
    return std, dominant


def main():
    bad = []
    with sync_playwright() as p:
        browser = p.chromium.launch(args=ARGS)
        # the page ships a CSP with no 'unsafe-eval'; wait_for_function needs it
        ctx = browser.new_context(bypass_csp=True, viewport={"width": W, "height": H}, device_scale_factor=1)
        page = ctx.new_page()
        errors = []
        page.on("pageerror", lambda e: errors.append(str(e)))
        page.goto(URL)
        page.wait_for_function("window.palace && window.palace.ready", timeout=240_000)
        page.evaluate(HIDE)
        duration = page.evaluate("palace.duration()")
        t = 0.0
        while t <= duration + 1e-6:
            page.evaluate(f"palace.renderAt({t})")
            page.evaluate("palace.sync()")
            std, dominant = measure(page.screenshot())
            flag = std < MIN_STD or dominant > MAX_DOMINANT
            beat = page.evaluate("document.getElementById('beat-label').textContent")
            print(f"{t:6.1f}s  std {std:6.2f}  dominant {dominant:5.1%}  {'FLAT' if flag else 'ok'}  {beat}")
            if flag:
                page.screenshot(path=f"/workspace/island-shots/flat_{t:05.1f}s.png")
                bad.append({"t": t, "std": round(std, 2), "dominant": round(dominant, 3), "beat": beat})
            t += STEP
        browser.close()
    if errors:
        print("page errors:", json.dumps(errors[:5]))
    if bad:
        print(f"\n{len(bad)} near-solid frame(s): {json.dumps(bad)}")
        return 1
    print("\nno near-solid frames over the whole tour")
    return 0


if __name__ == "__main__":
    sys.exit(main())
