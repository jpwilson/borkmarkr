/* bookmarker — a topic's colours, from its hue.
 *
 * An exact port of CategoryPalette in App/DesignSystem/Tokens.swift, so a
 * topic is the same colour on the web as on the iPhone. The Swift builds each
 * colour with SwiftUI's Color(hue:saturation:brightness:), which is HSB (also
 * called HSV), not the HSL that CSS speaks; the same numbers fed to hsl() come
 * out noticeably different. So the HSB is converted here and every colour is
 * handed back as a CSS hex string. It matches what SwiftUI resolves, byte for
 * byte, except where a channel lands exactly on a half (brightness .30 or .70
 * times 255), where the two can round 1/255 apart.
 *
 *   tint(h)        chip and tile background          HSB(h, .55, .97)
 *   deep(h)        text on the tint                  HSB(h, .46, .42)
 *   solid(h)       the topic's dot colour            HSB(h, .50, .70)
 *   coverTop(h)    cover gradient, top-left          HSB(h, .52, .62)
 *   coverBottom(h) cover gradient, bottom-right      HSB(h, .60, .30)
 *   gradient(h)    the whole cover, as CoverImage draws it: a CSS background
 *                  image (white 16% radial highlight at the top-left corner,
 *                  over coverTop → coverBottom corner to corner)
 *   chip(h)        "background:<tint>;color:<deep>", a drop-in style attribute
 *
 * NEUTRAL_HUE is NeutralPalette's 40: unfiled things, deliberately dull.
 * Hues are degrees, as in taxonomy.js. No DOM, so it loads in node as it is.
 */
"use strict";

const Palette = (() => {

  /* SwiftUI's HSB → sRGB, every component 0…1, hue wrapped into one turn. */
  function hsb(hue, saturation, brightness) {
    const degrees = ((Number(hue) || 0) % 360 + 360) % 360;
    const h = (degrees / 360) * 6;
    const i = Math.floor(h);
    const f = h - i;
    const v = brightness, s = saturation;
    const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
    const [r, g, b] = [[v, t, p], [q, v, p], [p, v, t], [p, q, v], [t, p, v], [v, p, q]][i % 6];
    const hex = (x) => Math.round(x * 255).toString(16).padStart(2, "0");
    return `#${hex(r)}${hex(g)}${hex(b)}`;
  }

  /* Built once per hue, like Topic.palettes on the phone. */
  const cache = new Map();
  function palette(hue) {
    const key = Number(hue) || 0;
    let entry = cache.get(key);
    if (!entry) {
      entry = Object.freeze({
        tint: hsb(key, 0.55, 0.97),
        deep: hsb(key, 0.46, 0.42),
        dot: hsb(key, 0.50, 0.70),
        coverTop: hsb(key, 0.52, 0.62),
        coverBottom: hsb(key, 0.60, 0.30),
      });
      cache.set(key, entry);
    }
    return entry;
  }

  const tint = (hue) => palette(hue).tint;
  const deep = (hue) => palette(hue).deep;
  const solid = (hue) => palette(hue).dot;
  const coverTop = (hue) => palette(hue).coverTop;
  const coverBottom = (hue) => palette(hue).coverBottom;
  const gradient = (hue) =>
    "radial-gradient(circle 180px at 0 0, rgba(255,255,255,.16), rgba(255,255,255,0)), "
    + `linear-gradient(to bottom right, ${coverTop(hue)}, ${coverBottom(hue)})`;
  const chip = (hue) => `background:${tint(hue)};color:${deep(hue)}`;

  return Object.freeze({ tint, deep, solid, coverTop, coverBottom, gradient, chip, NEUTRAL_HUE: 40 });
})();

if (typeof globalThis === "object") globalThis.Palette = Palette;
if (typeof module === "object" && module.exports) module.exports = { Palette };
