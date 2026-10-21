/* Where everything sits on the map. Pure numbers — no DOM, no three.js — so
   Scripts/test_palace.mjs can check the packing the renderer takes on trust:
   regions never overlap, districts stay inside their region, markers stay
   inside their district, and the tour covers every beat.

   Units are "map metres". The atlas lives inside a disc of radius OUTER; the
   terrain plate and the water run well past it. */

export const MAP = {
  OUTER: 430,        // regions are packed inside this disc
  GAP: 44,           // valley floor kept between two regions
  FILL: 0.42,        // share of the disc the regions cover
  R_MIN: 50,
  R_MAX: 210,
  PLATE: 1500,       // half-size of the terrain plate
  WATER: -34,        // water level, in height units
  SHORE: 1150,       // ground starts dropping to the sea past this radius
};

const TAU = Math.PI * 2;
const GOLDEN = 2.399963229728653;

export function hash32(text) {
  let h = 2166136261;
  const s = String(text);
  for (let i = 0; i < s.length; i++) h = Math.imul(h ^ s.charCodeAt(i), 16777619);
  return h >>> 0;
}
/* Deterministic 0..1 from a string + an index. */
export const rand = (seed, n = 0) => (hash32(`${seed}#${n}`) % 100000) / 100000;

/* A closed wobbly outline for a region or district. Stays inside r*1.17 and
   outside r*0.83, which is what keeps the packing proof simple. */
export function boundary(cx, cz, r, seed, steps = 72) {
  const p1 = rand(seed, 1) * TAU, p2 = rand(seed, 2) * TAU, p3 = rand(seed, 3) * TAU;
  const pts = [];
  for (let i = 0; i < steps; i++) {
    const a = (i / steps) * TAU;
    const k = 1 + 0.085 * Math.sin(3 * a + p1) + 0.05 * Math.sin(5 * a + p2) - 0.03 * Math.sin(7 * a + p3);
    pts.push([cx + Math.cos(a) * r * k, cz + Math.sin(a) * r * k]);
  }
  return pts;
}
export const BOUND_MAX = 1.17;
export const BOUND_MIN = 0.83;

/* Circle packing by relaxation: seed on a golden-angle spiral, then push
   overlapping discs apart and anything poking out of the disc back in. Same
   input, same output — there is no randomness past the seeded jitter. */
function pack(discs, outer, gap, seed, iterations = 900) {
  const n = discs.length;
  const pos = discs.map((d, i) => {
    const a = i * GOLDEN + rand(seed, i) * 0.4;
    const rad = outer * 0.60 * Math.sqrt((i + 0.4) / Math.max(1, n));
    return [Math.cos(a) * rad, Math.sin(a) * rad];
  });
  const rad = discs.map((d) => d.rMax);
  for (let step = 0; step < iterations; step++) {
    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        let dx = pos[j][0] - pos[i][0], dz = pos[j][1] - pos[i][1];
        let d = Math.hypot(dx, dz);
        if (d < 1e-6) { dx = Math.cos(i * GOLDEN); dz = Math.sin(i * GOLDEN); d = 1e-6; }
        const want = rad[i] + rad[j] + gap;
        if (d < want) {
          const push = (want - d) / 2 / d;
          pos[i][0] -= dx * push; pos[i][1] -= dz * push;
          pos[j][0] += dx * push; pos[j][1] += dz * push;
        }
      }
    }
    for (let i = 0; i < n; i++) {
      const d = Math.hypot(pos[i][0], pos[i][1]);
      const limit = outer - rad[i];
      if (d > limit) {
        const k = limit / Math.max(d, 1e-6);
        pos[i][0] *= k; pos[i][1] *= k;
      } else if (step > iterations * 0.5 && d > 1e-6) {
        pos[i][0] -= (pos[i][0] / d) * 0.05;   // gentle pull inwards so the atlas stays compact
        pos[i][1] -= (pos[i][1] / d) * 0.05;
      }
    }
  }
  return pos;
}

/* The worst overlap left after a packing run, as a fraction of the distance
   the two discs needed. Zero means the layout is legal: the valley gap is
   what the packer aims for, but only a real overlap is a failure. */
function worstOverlap(pos, rad) {
  let worst = 0;
  for (let i = 0; i < pos.length; i++) {
    for (let j = i + 1; j < pos.length; j++) {
      const want = rad[i] + rad[j];
      const have = Math.hypot(pos[i][0] - pos[j][0], pos[i][1] - pos[j][1]);
      if (have < want) worst = Math.max(worst, (want - have) / want);
    }
  }
  return worst;
}

/* Some sets simply don't fit — two equal discs can never both sit inside a
   circle only twice their radius. Shrink everything a step at a time until
   the packing is legal, and report the scale so the caller can shrink the
   outlines and markers with it. */
function packFit(radii, outer, gap, seed) {
  let scale = 1;
  for (let attempt = 0; attempt < 18; attempt++) {
    const rad = radii.map((r) => r * scale);
    const pos = pack(rad.map((rMax) => ({ rMax })), outer, gap * scale, seed);
    if (worstOverlap(pos, rad) <= 1e-9) return { pos, scale };
    scale *= 0.93;
  }
  const rad = radii.map((r) => r * scale);
  return { pos: pack(rad.map((rMax) => ({ rMax })), outer, gap * scale, seed), scale };
}

/* Radii from counts: area ∝ number of bookmarks, scaled so the whole set
   covers MAP.FILL of the disc. */
function radiiFor(counts, outer, fill, rMin, rMax) {
  const total = counts.reduce((n, c) => n + c, 0) || 1;
  const K = Math.sqrt((fill * outer * outer) / total);
  return counts.map((c) => Math.min(rMax, Math.max(rMin, K * Math.sqrt(Math.max(1, c)))));
}

/* Golden-angle spiral inside a disc: even, deterministic, no clumping. */
function spiral(count, radius, seed) {
  const out = [];
  for (let i = 0; i < count; i++) {
    const a = i * GOLDEN + rand(seed, 100 + i) * 0.9;
    const rr = radius * Math.sqrt((i + 0.55) / Math.max(1, count)) * (0.82 + 0.16 * rand(seed, 300 + i));
    out.push([Math.cos(a) * rr, Math.sin(a) * rr]);
  }
  return out;
}

export const MARKER_IN = 0.78;     // markers stay this far inside their district
const DISTRICT_IN = 0.70;          // districts stay this far inside their region

/* atlas (from PalaceData.buildAtlas) → map geometry. */
export function computeLayout(atlas) {
  const regions = atlas.regions;
  const wanted = radiiFor(regions.map((r) => r.total), MAP.OUTER, MAP.FILL, MAP.R_MIN, MAP.R_MAX);
  const fit = packFit(wanted.map((r) => r * BOUND_MAX), MAP.OUTER, MAP.GAP, "regions");
  const radii = wanted.map((r) => r * fit.scale);
  const pos = fit.pos;

  const newest = atlas.range ? atlas.range.end : 0;
  const oldest = atlas.range ? atlas.range.start : 0;
  const span = Math.max(1, newest - oldest);

  const out = regions.map((region, i) => {
    const r = radii[i];
    const [cx, cz] = pos[i];
    const node = {
      id: region.id, name: region.name, color: region.color, total: region.total,
      index: i, x: cx, z: cz, r, rMax: r * BOUND_MAX, rMin: r * BOUND_MIN,
      boundary: boundary(cx, cz, r, `region:${region.id}`),
      districts: [], markers: [],
    };

    const inner = r * DISTRICT_IN;
    const dWanted = radiiFor(region.districts.map((d) => d.total), inner, 0.40, inner * 0.13, inner * 0.52);
    const dFit = packFit(dWanted.map((dr) => dr * BOUND_MAX), inner, inner * 0.08, `d:${region.id}`);
    const dRadii = dWanted.map((dr) => dr * dFit.scale);
    const dPos = dFit.pos;
    region.districts.forEach((district, j) => {
      const dr = dRadii[j];
      const dx = cx + dPos[j][0], dz = cz + dPos[j][1];
      const dNode = {
        name: district.name, total: district.total, index: j, regionId: region.id,
        x: dx, z: dz, r: dr, rMax: dr * BOUND_MAX,
        boundary: boundary(dx, dz, dr, `district:${region.id}:${district.name}`, 48),
        markers: [],
      };
      const pts = spiral(district.items.length, dr * MARKER_IN, `m:${region.id}:${district.name}`);
      district.items.forEach((item, k) => {
        const undated = item.at == null;
        const age = undated ? 0 : (item.at - oldest) / span;
        const marker = {
          id: item.id, x: dx + pts[k][0], z: dz + pts[k][1],
          regionId: region.id, district: district.name, color: region.color,
          source: item.source, at: item.at, age, undated,
          // Height is recency. A bookmark with no save date gets a short flat
          // stub instead of a made-up age.
          height: undated ? 2.4 : 4.2 + 11 * Math.pow(age, 1.3),
          item,
        };
        dNode.markers.push(marker);
        node.markers.push(marker);
      });
      node.districts.push(dNode);
    });
    return node;
  });

  const bounds = out.reduce((m, r) => Math.max(m, Math.hypot(r.x, r.z) + r.rMax), 0);
  return { regions: out, bounds, outer: MAP.OUTER, markerCount: out.reduce((n, r) => n + r.markers.length, 0) };
}

export const regionById = (layout, id) => layout.regions.find((r) => r.id === id) || null;

/* The reading trail: saves in the order they happened, thinned to `count`
   pins so the dashed line stays legible. Region-scoped when `regionId` is
   given, otherwise it wanders the whole atlas. */
export function readingTrail(layout, { regionId = null, count = 8 } = {}) {
  const pool = (regionId ? [regionById(layout, regionId)] : layout.regions)
    .filter(Boolean)
    .flatMap((r) => r.markers)
    .filter((m) => m.at != null)
    .sort((a, b) => a.at - b.at);
  if (pool.length < 2) return [];
  const n = Math.min(count, pool.length);
  const pins = [];
  for (let i = 0; i < n; i++) pins.push(pool[Math.round((i * (pool.length - 1)) / (n - 1))]);
  return pins.filter((m, i) => i === 0 || m !== pins[i - 1]);
}

/* The scripted tour. Beats are contiguous and cover [0, duration]; the
   renderer reads `id` to know what the UI and camera should be doing. */
/* Captions are templates: the numbers in them come out of the model, so a
   four-week library never claims sixteen months. */
export const TOUR_BEATS = [
  { id: "orbit-in", name: "Overview orbit", label: "{total} bookmarks, as one place", length: 7 },
  { id: "timeline", name: "Saves spread", label: "{span} of saves, spreading in order", length: 8 },
  { id: "region", name: "Into a region", label: "Every topic is a region — {regions} of them", length: 6 },
  { id: "detail", name: "One bookmark", label: "Every save is a marker you can open", length: 6 },
  { id: "trail", name: "Reading trail", label: "The order you saved things, drawn on the ground", length: 6 },
  { id: "follow", name: "Reader cam", label: "Ride the trail, stop by stop", length: 8 },
  { id: "sources", name: "Sources re-skin", label: "Re-colour the map by where it came from", length: 6 },
  { id: "map2d", name: "Flat map", label: "Or read it flat", length: 5 },
  { id: "orbit-out", name: "Closing orbit", label: "bookmarker.lol", length: 4 },
];

/* "3 weeks" / "16 months", derived, never written down. */
export function spanWords(atlas) {
  if (!atlas.range) return "A library with no dates";
  const days = atlas.stats.spanDays || 0;
  if (days < 21) return `${Math.max(1, days)} day${days === 1 ? "" : "s"}`;
  if (days < 75) return `${Math.round(days / 7)} weeks`;
  const months = atlas.stats.spanMonths || 1;
  return months < 24 ? `${months} months` : `${(months / 12).toFixed(1)} years`;
}

/* The circle the atlas actually occupies, so the camera can frame the
   library rather than the scenery behind it. */
export function libraryBounds(layout) {
  let r = 0;
  for (const region of layout.regions) r = Math.max(r, Math.hypot(region.x, region.z) + region.rMax);
  return Math.max(120, r);
}

export function tourPlan(atlas, layout) {
  const focus = regionById(layout, "recipes")
    || layout.regions.slice().sort((a, b) => b.total - a.total)[0]
    || null;
  const markers = focus ? focus.markers.filter((m) => m.at != null) : [];
  const pick = markers.length ? markers[Math.floor(markers.length * 0.62)] : (layout.regions[0]?.markers[0] || null);
  const words = { total: String(atlas.total), span: spanWords(atlas), regions: String(atlas.regions.length) };
  let t = 0;
  const beats = TOUR_BEATS.map((b) => {
    const label = b.label.replace(/\{(\w+)\}/g, (m, k) => (words[k] != null ? words[k] : m));
    const beat = { ...b, label, start: t, end: t + b.length };
    t += b.length;
    return beat;
  });
  return {
    beats,
    duration: t,
    focusRegion: focus ? focus.id : null,
    marker: pick ? pick.id : null,
    trail: readingTrail(layout, { regionId: focus ? focus.id : null, count: 8 }).map((m) => m.id),
    at(time) {
      const clamped = Math.min(Math.max(time, 0), t - 1e-6);
      const beat = beats.find((b) => clamped >= b.start && clamped < b.end) || beats[beats.length - 1];
      return { beat, local: (clamped - beat.start) / beat.length, time: clamped };
    },
  };
}
