/* bookmarker — a topic's clay colours, from its hue.
 *
 * A line-for-line port of Core/ClayPalette.swift (ClayRecipe), so a topic is
 * the same colour on the web as on the iPhone, byte for byte. The fixture
 * Scripts/fixtures/clay_palette_cases.json pins both: Scripts/test_clay_palette
 * .swift and Scripts/test_clay_palette.mjs read it. Change one port, change the
 * other, regenerate the fixture (Scripts/gen_clay_palette_fixture.swift).
 *
 * The recipe (design/SYSTEM.md, "Topic colours: the clay palette"):
 *   1. hue h → today's dot colour sRGB HSB(h, .5, .7) → its OKLCH hue: the
 *      topic's place on the circle;
 *   2. the seven coloured SYSTEM.md rows, measured in OKLCH, are anchors pinned
 *      at the place of the topic each was drawn for (Health → Rose, Cars →
 *      Terracotta, Recipes → Ochre, Garden → Sage, Nutrition → Teal, Travel →
 *      Dusty blue, AI → Lilac); L, C and H of each role interpolate linearly
 *      between the two anchors either side, wrapping round;
 *   3. out of gamut: chroma binary-searched down, 24 halvings;
 *   4. gamma-encode, round to 8 bits, "#RRGGBB".
 * Sand (the "not filed" colour) is the SYSTEM.md row exactly.
 *
 *   tint(h)    surfaces: chips, slabs, tile footers. Text on it is deep(h).
 *   mid(h)     the 8 px dot, rings, small fills. Never under white text.
 *   deep(h)    text on the tint; the fill behind white text.
 *   solid(h)   = mid(h), the old name.
 *   chip(h)    "background:<tint>;color:<deep>", a drop-in style attribute.
 *   of(hue)    { tint, mid, deep } for a hue, or Sand for null/undefined.
 *   neutral    Sand: { tint, mid, deep }.
 *   gradient(h), coverTop(h), coverBottom(h): kept so old callers still draw;
 *              gradient is now the flat tint (covers use clay art instead).
 *
 * NEUTRAL_HUE (40) is kept for callers that still pass a number for "unfiled";
 * they should move to Palette.of(null) / Palette.neutral, which is Sand.
 * No DOM, so it loads in node as it is.
 */
"use strict";

const Palette = (() => {

  /* ── The reference rows (design/SYSTEM.md) ── */

  const row = (family, topicHue, tint, mid, deep) => ({ family, topicHue, colours: { tint, mid, deep } });

  /* Hues are the topics in Core/Taxonomy.swift: Health 352, Cars & motors 11,
     Recipes 42, Garden 96, Nutrition 146, Travel 202, AI 256. */
  const references = Object.freeze([
    row("Rose", 352, "#F4DCDD", "#D48A8F", "#7A3338"),
    row("Terracotta", 11, "#F3DDD2", "#C8674A", "#7A3420"),
    row("Ochre", 42, "#F4E6C4", "#D9A441", "#6E4E0E"),
    row("Sage", 96, "#E3EADB", "#8FA37E", "#3F5237"),
    row("Teal", 146, "#D8EAE6", "#6FA89C", "#2C5A50"),
    row("Dusty blue", 202, "#DCE7F0", "#7FA3C2", "#2F4E68"),
    row("Lilac", 256, "#E6DFF0", "#9A86BF", "#4A3A70"),
    row("Sand", null, "#ECE5D8", "#B5A68A", "#5A4E38"),
  ]);

  /* Not filed yet, More…, the ground under clay art: the Sand row exactly. */
  const neutral = Object.freeze({ tint: "#ECE5D8", mid: "#B5A68A", deep: "#5A4E38" });

  /* ── The recipe ── */

  const rgbOf = (hex) => {
    const d = hex.charAt(0) === "#" ? hex.slice(1) : hex;
    const value = d.length === 6 ? (parseInt(d, 16) || 0) : 0;
    return [(value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];
  };

  function lch(hex) {
    const [r, g, b] = rgbOf(hex);
    const lab = toOKLab(r / 255, g / 255, b / 255);
    return { l: lab[0], c: Math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]), h: degrees(lab[1], lab[2]) };
  }

  let anchorCache = null;
  function anchors() {
    if (anchorCache) return anchorCache;
    anchorCache = references
      .filter((ref) => ref.topicHue !== null)
      .map((ref) => ({
        at: okHue(ref.topicHue),
        tint: lch(ref.colours.tint), mid: lch(ref.colours.mid), deep: lch(ref.colours.deep),
      }))
      .sort((x, y) => x.at - y.at);
    return anchorCache;
  }

  /* The OKLCH hue (0..<360) of sRGB HSB(h, 0.5, 0.7) — today's dot colour. */
  function okHue(hue) {
    const [r, g, b] = hsb(hue, 0.5, 0.7);
    const lab = toOKLab(r, g, b);
    return degrees(lab[1], lab[2]);
  }

  /* A topic's colours from its stored hue. */
  function colours(hue) {
    const at = okHue(hue);
    return {
      tint: encode(role(at, "tint")),
      mid: encode(role(at, "mid")),
      deep: encode(role(at, "deep")),
    };
  }

  /* WCAG 2 contrast ratio, 1…21, of two "#RRGGBB" strings. */
  function contrast(a, b) {
    const x = luminance(a), y = luminance(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
  }

  /* ── Interpolation ── */

  function role(at, pick) {
    const A = anchors();
    const n = A.length;
    let i = n - 1;
    for (let j = 0; j < n; j++) if (A[j].at <= at) i = j;
    const a = A[i], b = A[(i + 1) % n];
    const h0 = a.at;
    let h1 = b.at;
    if (h1 <= h0) h1 += 360;
    let x = at;
    if (x < h0) x += 360;
    const t = (x - h0) / (h1 - h0);
    const p = a[pick], q = b[pick];
    let qh = q.h;
    if (qh < p.h) qh += 360;
    const h = (p.h + (qh - p.h) * t) % 360;
    return { l: p.l + (q.l - p.l) * t, c: p.c + (q.c - p.c) * t, h };
  }

  /* ── Colour maths (OKLab, Björn Ottosson 2020) ── */

  function encode(colour) {
    const rad = colour.h * Math.PI / 180;
    const ca = Math.cos(rad), sa = Math.sin(rad);
    const linear = (c) => fromOKLab(colour.l, c * ca, c * sa);
    let rgb = linear(colour.c);
    if (!inGamut(rgb)) {
      let lo = 0, hi = colour.c;
      for (let k = 0; k < 24; k++) {
        const mid = (lo + hi) / 2;
        if (inGamut(linear(mid))) lo = mid; else hi = mid;
      }
      rgb = linear(lo);
    }
    return "#" + rgb.map((c) => byte(c).toString(16).padStart(2, "0")).join("").toUpperCase();
  }

  const inGamut = (c) => c[0] >= 0 && c[0] <= 1 && c[1] >= 0 && c[1] <= 1 && c[2] >= 0 && c[2] <= 1;

  function byte(linear) {
    const c = Math.min(1, Math.max(0, linear));
    const encoded = c <= 0.0031308 ? 12.92 * c : 1.055 * Math.pow(c, 1 / 2.4) - 0.055;
    return Math.round(Math.min(1, Math.max(0, encoded)) * 255);
  }

  const toLinear = (c) => (c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4));

  function toOKLab(red, green, blue) {
    const r = toLinear(red), g = toLinear(green), b = toLinear(blue);
    const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
    const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
    const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
    return [0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s];
  }

  function fromOKLab(L, a, b) {
    const l1 = L + 0.3963377774 * a + 0.2158037573 * b;
    const m1 = L - 0.1055613458 * a - 0.0638541728 * b;
    const s1 = L - 0.0894841775 * a - 1.2914855480 * b;
    const l = l1 * l1 * l1, m = m1 * m1 * m1, s = s1 * s1 * s1;
    return [4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
            -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
            -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s];
  }

  /* HSB (HSV) → sRGB 0…1, as SwiftUI's Color(hue:saturation:brightness:). */
  function hsb(hue, s, v) {
    const wrapped = ((Number(hue) || 0) % 360 + 360) % 360;
    const x = wrapped / 60;
    const i = Math.floor(x);
    const f = x - i;
    const p = v * (1 - s), q = v * (1 - f * s), t = v * (1 - (1 - f) * s);
    switch (i % 6) {
      case 0: return [v, t, p];
      case 1: return [q, v, p];
      case 2: return [p, v, t];
      case 3: return [p, q, v];
      case 4: return [t, p, v];
      default: return [v, p, q];
    }
  }

  function degrees(a, b) {
    const d = Math.atan2(b, a) * 180 / Math.PI;
    return d < 0 ? d + 360 : d;
  }

  function luminance(hex) {
    const [r, g, b] = rgbOf(hex);
    return 0.2126 * toLinear(r / 255) + 0.7152 * toLinear(g / 255) + 0.0722 * toLinear(b / 255);
  }

  /* ── The page-facing API: built once per hue, like Topic.palettes ── */

  const cache = new Map();
  function palette(hue) {
    const key = Number(hue) || 0;
    let entry = cache.get(key);
    if (!entry) {
      entry = Object.freeze(colours(key));
      cache.set(key, entry);
    }
    return entry;
  }

  const of = (hue) => (hue === null || hue === undefined ? neutral : palette(hue));
  const tint = (hue) => palette(hue).tint;
  const mid = (hue) => palette(hue).mid;
  const deep = (hue) => palette(hue).deep;
  const solid = mid;
  const coverTop = mid;
  const coverBottom = deep;
  const gradient = (hue) => `linear-gradient(${tint(hue)}, ${tint(hue)})`;
  const chip = (hue) => `background:${tint(hue)};color:${deep(hue)}`;

  return Object.freeze({
    tint, mid, deep, solid, chip, of, neutral, NEUTRAL_HUE: 40,
    gradient, coverTop, coverBottom,
    colours, okHue, contrast, references,
  });
})();

if (typeof globalThis === "object") globalThis.Palette = Palette;
if (typeof module === "object" && module.exports) module.exports = { Palette };
