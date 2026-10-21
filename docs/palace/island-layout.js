/* island-layout.js — the island itself, as pure numbers.

   Everything here is deterministic and DOM-free: the terrain field (height,
   moisture, rock, shore), the fixed set of island features, the weighted
   Voronoi that turns topics into zones, and the placement of one marker per
   bookmark inside its own zone. The renderer and Scripts/test_palace.mjs
   both read this module, so what the tests prove is what the frame draws. */

/* ── deterministic value/gradient noise ─────────────────────────────────── */
const PERM = (() => {
  const base = new Uint8Array(256);
  for (let i = 0; i < 256; i++) base[i] = i;
  let s = 1337 >>> 0;
  const rnd = () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296);
  for (let i = 255; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    const t = base[i]; base[i] = base[j]; base[j] = t;
  }
  const p = new Uint8Array(512);
  for (let i = 0; i < 512; i++) p[i] = base[i & 255];
  return p;
})();
const GX = new Float32Array(256), GY = new Float32Array(256);
for (let i = 0; i < 256; i++) {
  const a = (i / 256) * Math.PI * 2;
  GX[i] = Math.cos(a); GY[i] = Math.sin(a);
}
const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);

export function noise2(x, y) {
  const X = Math.floor(x), Y = Math.floor(y);
  const xf = x - X, yf = y - Y;
  const xi = X & 255, yi = Y & 255;
  const u = fade(xf), v = fade(yf);
  const aa = PERM[PERM[xi] + yi], ab = PERM[PERM[xi] + yi + 1];
  const ba = PERM[PERM[xi + 1] + yi], bb = PERM[PERM[xi + 1] + yi + 1];
  const g = (h, dx, dy) => GX[h] * dx + GY[h] * dy;
  const n00 = g(aa, xf, yf), n10 = g(ba, xf - 1, yf);
  const n01 = g(ab, xf, yf - 1), n11 = g(bb, xf - 1, yf - 1);
  const a1 = n00 + u * (n10 - n00);
  const a2 = n01 + u * (n11 - n01);
  return a1 + v * (a2 - a1);
}

export function fbm(x, y, oct = 4, lac = 2.02, gain = 0.5) {
  let f = 1, a = 1, sum = 0, norm = 0;
  for (let i = 0; i < oct; i++) {
    sum += a * noise2(x * f + i * 11.3, y * f - i * 7.1);
    norm += a; f *= lac; a *= gain;
  }
  return sum / norm;
}

/* Ridged multifractal: the sharp, braided spines that read as a jungle
   mountain rather than rolling dunes. Returns roughly 0..1. */
export function ridged(x, y, oct = 5, lac = 2.04, gain = 0.5) {
  let f = 1, a = 1, sum = 0, norm = 0, prev = 1;
  for (let i = 0; i < oct; i++) {
    let n = 1 - Math.abs(noise2(x * f + i * 5.7, y * f + i * 9.2));
    n *= n;
    sum += a * n * prev;
    prev = 0.55 + 0.45 * n;
    norm += a; f *= lac; a *= gain;
  }
  return sum / norm;
}

/* ── small math ─────────────────────────────────────────────────────────── */
export const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
export const sstep = (e0, e1, x) => {
  const t = clamp((x - e0) / (e1 - e0 || 1e-6), 0, 1);
  return t * t * (3 - 2 * t);
};
export const mix = (a, b, t) => a + (b - a) * t;
const gauss = (d, r) => Math.exp(-(d * d) / (r * r));

/* ── the island's fixed geography ───────────────────────────────────────── */
export const SEA_LEVEL = 0;
export const ISLAND_R = 1180;
export const TERRAIN_HALF = 1900;      // the heightfield covers [-1900, 1900]
export const MARKER_CAP = 180;         // markers drawn per zone; counts stay real

/* Nine places, each with its own biome, in the order topics claim them: the
   largest topic gets the volcano, and so on down. Positions are authored to
   match the terrain features built below, so a zone always contains the
   landform its biome names. */
export const SITES = [
  { id: "volcano",  name: "Caldera Ridge",     biome: "Volcano ridge",      note: "smoking caldera, ash flanks",      x: -150, z: -330, labelY: 150 },
  { id: "karst",    name: "Karst Shore",       biome: "Limestone pillars",  note: "sea stacks, mossy towers",         x:  790, z: -140, labelY: 120 },
  { id: "temple",   name: "Temple Terraces",   biome: "Overgrown ruins",    note: "stepped ziggurat, broken columns", x:  150, z:  450, labelY: 100 },
  { id: "river",    name: "River Valley",      biome: "River valley",       note: "braided river, gravel banks",      x: -430, z:  180, labelY: 110 },
  { id: "falls",    name: "Cliffside Falls",   biome: "Cliffs & waterfalls",note: "sea cliffs, three waterfalls",     x:  430, z: -690, labelY: 150 },
  { id: "swamp",    name: "Mangrove Marsh",    biome: "Swamp & mangroves",  note: "still water, stilt roots",         x: -740, z:  520, labelY:  80 },
  { id: "lagoon",   name: "Turquoise Lagoon",  biome: "Beach & lagoon",     note: "white sand, reef shallows",        x:  660, z:  620, labelY:  70 },
  { id: "highland", name: "Canopy Highlands",  biome: "Dense canopy",       note: "cloud forest, emergent trees",     x: -820, z: -180, labelY: 150 },
  { id: "crater",   name: "Mirror Crater",     biome: "Crater lake",        note: "still lake, bamboo rim",           x: -130, z: -830, labelY: 120 },
];
export const MAX_ZONES = SITES.length;

/* The river: volcano flank → valley → delta in the marsh → sea. Carved into
   the heightfield and drawn as a water ribbon by the renderer. */
export const RIVER = [
  [-250, -150, 330], [-350, -20, 215], [-430, 165, 140], [-545, 320, 86],
  [-690, 455, 36], [-840, 580, 9], [-985, 690, -14], [-1120, 790, -40],
];

/* Offshore limestone stacks, the Skull Island signature. [x, z, radius, height] */
export const STACKS = [
  [1480, -300, 64, 300], [1760, -110, 40, 185], [1390,  140, 78, 360],
  [1700,  430, 46, 215], [1255, -660, 50, 265], [1960, -430, 32, 150],
  [1180,  430, 38, 175], [1020, -860, 46, 230], [1560, -720, 30, 130],
  [ 880,  820, 42, 185], [1240,  760, 34, 150],
];
/* A few on land, in the karst zone, so the biome reads from the air too. */
export const LAND_STACKS = [
  [700, -300, 58, 300], [865, -45, 68, 355], [640, -60, 46, 225],
  [920, -315, 40, 205], [748, 118, 50, 255], [812, -200, 34, 165],
];

const VOLCANO = { x: -150, z: -330, R: 780, H: 880, crater: 150, depth: 260 };
const MESA = { x: 430, z: -800, R: 420, H: 250, edge: 95 };     // the falls plateau
const CRATER = { x: -130, z: -830, R: 240, H: 380, lake: 290 };
const HIGHLAND = { x: -820, z: -180, R: 520, H: 290 };
const TEMPLE = { x: 150, z: 450, R: 300, H: 128 };
const MARSH = { x: -740, z: 520, R: 330 };
const BEACH = { x: 660, z: 620, R: 400 };
const KARST = { x: 790, z: -140, R: 430 };

export const LAGOON = { x: 660, z: 620 };
/* Reef arc enclosing the lagoon: the crest sits just under the surface. */
export const REEF = { x: 560, z: 520, r: 760, from: -0.35, to: 1.5 };

/* The three waterfalls, on the seaward rim of the mesa. */
export const FALLS = [
  { a: -0.30, w: 34 }, { a: -0.03, w: 52 }, { a: 0.26, w: 26 },
].map((f) => ({
  ...f,
  x: MESA.x + Math.sin(f.a + Math.PI) * (MESA.R - 6),
  z: MESA.z + Math.cos(f.a + Math.PI) * (MESA.R - 6) * -1,
}));

/* ── the coastline ──────────────────────────────────────────────────────── */
/* Signed distance-ish field: > 0 inland, 0 at the waterline. */
export function coastField(x, z) {
  const wx = x + 210 * noise2(x * 0.00095 + 5.1, z * 0.00095 - 2.3);
  const wz = z + 210 * noise2(x * 0.00095 - 7.7, z * 0.00095 + 4.4);
  const d = Math.hypot(wx * 1.03, wz * 0.95);
  let r = ISLAND_R * (1 + 0.19 * fbm(wx * 0.0012, wz * 0.0012, 3));
  r -= 330 * gauss(Math.hypot(wx - 1010, wz - 880), 620);   // the lagoon bay
  r -= 210 * gauss(Math.hypot(wx + 1120, wz - 760), 480);   // the delta mouth
  r += 150 * gauss(Math.hypot(wx - 820, wz + 240), 420);    // karst headland
  return r - d;
}

/* ── height ─────────────────────────────────────────────────────────────── */
export function heightAt(x, z) {
  const m = coastField(x, z);
  if (m < -520) return -170;

  // Offshore: shelf dropping away, with the lagoon reef sitting just under.
  const shore = clamp(m / 190, -3, 1);
  let h;
  if (m <= 0) {
    h = -150 * Math.pow(clamp(-m / 480, 0, 1), 0.75) - 3;
  } else {
    const rel = ridged(x * 0.00074, z * 0.00074, 5);
    const spine = ridged(x * 0.0021 + 3.3, z * 0.0021 - 1.7, 3);
    const detail = 52 * fbm(x * 0.0043, z * 0.0043, 3);
    h = (470 * Math.pow(rel, 1.42) + 110 * Math.pow(spine, 2.2) * rel + detail + 14)
      * Math.pow(sstep(0, 1, shore), 0.62);
  }

  // Reef crest around the lagoon, a few metres under the surface.
  const ra = Math.atan2(z - REEF.z, x - REEF.x);
  if (ra > REEF.from && ra < REEF.to) {
    const rd = Math.abs(Math.hypot(x - REEF.x, z - REEF.z) - REEF.r * (1 + 0.05 * noise2(ra * 3.1, 2.7)));
    const edge = sstep(REEF.from, REEF.from + 0.3, ra) * sstep(REEF.to, REEF.to - 0.3, ra);
    h = Math.max(h, mix(h, -4 + 7 * noise2(x * 0.02, z * 0.02), gauss(rd, 70) * edge));
  }
  // Lagoon floor: shallow, flat, and bright.
  const ld = Math.hypot(x - BEACH.x, z - BEACH.z);
  if (m <= 0 && ld < 900) h = mix(h, -15 + 5 * noise2(x * 0.006, z * 0.006), gauss(Math.max(0, ld - 220), 520));

  if (m <= -40) return h;

  // Volcano: steep cone, ash gullies, a sunken caldera with a rim.
  const vd = Math.hypot(x - VOLCANO.x, z - VOLCANO.z);
  if (vd < VOLCANO.R * 1.15) {
    const t = clamp(1 - vd / VOLCANO.R, 0, 1);
    let cone = VOLCANO.H * Math.pow(t, 1.12);
    const ang = Math.atan2(z - VOLCANO.z, x - VOLCANO.x);
    cone += 30 * Math.sin(ang * 15 + 2.1 * noise2(vd * 0.004, ang)) * t * (1 - t) * 3.2;
    h = Math.max(h, h * 0.25 + cone);
    const cd = vd / VOLCANO.crater;
    if (cd < 1.45) {
      const floor = VOLCANO.H * Math.pow(1 - VOLCANO.crater / VOLCANO.R, 1.12) - VOLCANO.depth;
      h = mix(h, floor + 26 * fbm(x * 0.01, z * 0.01, 2), sstep(1.4, 0.85, cd));
    }
  }

  // The falls mesa: a flat-topped plateau whose seaward rim is a sheer cliff.
  const md = Math.hypot((x - MESA.x) * 1.0, (z - MESA.z) * 1.12);
  if (md < MESA.R + 160) {
    const ma = Math.atan2(z - MESA.z, x - MESA.x);
    const rim = MESA.R * (1 + 0.14 * noise2(ma * 2.3, 9.1) + 0.07 * noise2(ma * 5.1, 2.2));
    const t = sstep(rim, rim - MESA.edge, md);
    h = mix(h, Math.max(h, MESA.H + 120 + 34 * fbm(x * 0.004, z * 0.004, 3)), t);
  }

  // Crater lake cone to the north.
  const kd = Math.hypot(x - CRATER.x, z - CRATER.z);
  if (kd < CRATER.R * 1.6) {
    const t = clamp(1 - kd / (CRATER.R * 1.5), 0, 1);
    h = Math.max(h, h * 0.4 + CRATER.H * Math.pow(t, 0.9) + 18 * fbm(x * 0.006, z * 0.006, 2));
    if (kd < CRATER.R * 0.62) h = mix(h, CRATER.lake - 16, sstep(CRATER.R * 0.62, CRATER.R * 0.32, kd));
  }

  // Highland plateau: broad, rounded, cloud-forest shoulders.
  const hd = Math.hypot(x - HIGHLAND.x, z - HIGHLAND.z);
  if (hd < HIGHLAND.R * 1.5) h += HIGHLAND.H * sstep(HIGHLAND.R * 1.4, HIGHLAND.R * 0.3, hd) * clamp(m / 160, 0, 1);

  // Karst shelf: low ground so the limestone towers have something to stand on.
  const qd = Math.hypot(x - KARST.x, z - KARST.z);
  if (qd < KARST.R * 1.6) h = mix(h, mix(h, 46 + 26 * fbm(x * 0.005, z * 0.005, 2), 0.85), sstep(KARST.R * 1.5, KARST.R * 0.4, qd));

  // Temple terraces: a levelled shelf with three steps on its downhill side.
  const td = Math.hypot(x - TEMPLE.x, z - TEMPLE.z);
  if (td < TEMPLE.R * 1.7) {
    const w = sstep(TEMPLE.R * 1.6, TEMPLE.R * 0.55, td);
    const step = Math.round((TEMPLE.H + 26) / 26) * 26;
    h = mix(h, step + 10 * fbm(x * 0.01, z * 0.01, 2), w);
  }

  // Marsh: almost level, just above the waterline, pocked with still pools.
  const sd = Math.hypot(x - MARSH.x, z - MARSH.z);
  if (sd < MARSH.R * 1.8) {
    const w = sstep(MARSH.R * 1.7, MARSH.R * 0.5, sd);
    h = mix(h, 7 + 13 * fbm(x * 0.0075, z * 0.0075, 3), w);
  }

  // Beach: a long shallow ramp into the lagoon.
  const bd = Math.hypot(x - BEACH.x, z - BEACH.z);
  if (bd < BEACH.R * 1.7) h = mix(h, clamp(m, 0, 1e9) * 0.17 + 2.5, sstep(BEACH.R * 1.6, BEACH.R * 0.45, bd) * sstep(220, 30, m));

  // River: carved valley with a bed that only ever descends.
  const r = riverSample(x, z);
  if (r.d < 320) {
    const valley = gauss(r.d, 230) * 0.55;
    h = mix(h, Math.min(h, r.bed + 46), valley);
    h = mix(h, r.bed, gauss(r.d, 52) * 0.92);
  }

  // Erosion-ish terraces on mid slopes, the horizontal banding of the refs.
  const band = 23;
  const terr = Math.round(h / band) * band;
  h = mix(h, terr, 0.14 * sstep(40, 220, h) * sstep(620, 380, h));

  // Keep the shoreline honest: never cliff up straight out of deep water
  // except where a sea cliff is wanted.
  if (m > 0 && m < 190) h = Math.max(h, 1.2);
  return h;
}

/* Closest point on the river polyline: distance, bed height, and how far
   downstream it is (0..1). */
export function riverSample(x, z) {
  let best = { d: 1e9, bed: 0, u: 0 };
  for (let i = 0; i < RIVER.length - 1; i++) {
    const [ax, az, ay] = RIVER[i], [bx, bz, by] = RIVER[i + 1];
    const dx = bx - ax, dz = bz - az;
    const t = clamp(((x - ax) * dx + (z - az) * dz) / (dx * dx + dz * dz), 0, 1);
    const px = ax + dx * t, pz = az + dz * t;
    const d = Math.hypot(x - px, z - pz);
    if (d < best.d) best = { d, bed: mix(ay, by, t), u: (i + t) / (RIVER.length - 1) };
  }
  return best;
}

/* ── surface qualities used for colour and for scattering plants ────────── */
export function slopeAt(x, z, e = 6) {
  const hx = heightAt(x + e, z) - heightAt(x - e, z);
  const hz = heightAt(x, z + e) - heightAt(x, z - e);
  return Math.hypot(hx, hz) / (2 * e);
}

export function moistureAt(x, z, h) {
  const r = riverSample(x, z);
  let w = 0.46 + 0.34 * fbm(x * 0.0021 + 31.7, z * 0.0021 - 12.4, 3);
  w += 0.42 * gauss(r.d, 260);                                  // river corridor
  w += 0.40 * gauss(Math.hypot(x - MARSH.x, z - MARSH.z), 380); // marsh
  w += 0.26 * gauss(Math.hypot(x - MESA.x, z - MESA.z), 620);   // spray basin
  w -= 0.55 * gauss(Math.hypot(x - VOLCANO.x, z - VOLCANO.z), 330); // ash
  w -= 0.30 * gauss(Math.hypot(x - BEACH.x, z - BEACH.z), 300);     // dunes
  w -= clamp((h - 430) / 420, 0, 1) * 0.45;                         // bare summits
  return clamp(w, 0, 1);
}

/* ── zones: a multiplicatively weighted Voronoi over the used sites ─────── */
/* Bigger topics get more island. Each point belongs to exactly one zone, so
   the zones tile the island with no gaps and no overlap. */
export function zoneField(x, z, sites) {
  let bi = 0, bd = Infinity, sd = Infinity;
  for (let i = 0; i < sites.length; i++) {
    const s = sites[i];
    const d = Math.hypot(x - s.x, z - s.z) / s.weight;
    if (d < bd) { sd = bd; bd = d; bi = i; }
    else if (d < sd) sd = d;
  }
  return { zone: bi, d: bd, gap: sd - bd };
}

export function zoneWeights(regions) {
  const n = Math.min(regions.length, MAX_ZONES);
  const share = regions.slice(0, n).map((r) => Math.max(1, r.total));
  const mean = share.reduce((a, b) => a + b, 0) / n;
  return share.map((s) => clamp(Math.pow(s / mean, 0.22), 0.86, 1.2));
}

/* ── markers ────────────────────────────────────────────────────────────── */
const KINDS = ["camp", "totem", "banner", "torch", "cairn"];

/* A deterministic spiral of candidate spots around a site, filtered down to
   the ones that are inside this zone, above the waterline and walkable. */
function candidates(site, sites, index, want) {
  const out = [];
  const spread = 300 * site.weight;
  for (let k = 1; out.length < want && k < want * 26 + 400; k++) {
    const a = k * 2.3999632;
    const rad = spread * Math.sqrt(k / 42) * (0.55 + 0.6 * Math.abs(noise2(k * 0.37, index * 3.1)));
    const x = site.x + Math.cos(a) * rad;
    const z = site.z + Math.sin(a) * rad;
    const zf = zoneField(x, z, sites);
    if (zf.zone !== index || zf.gap < 26) continue;
    const h = heightAt(x, z);
    if (h < 9 || h > 560) continue;
    if (slopeAt(x, z) > 0.52) continue;
    out.push({ x, z, y: h });
  }
  return out;
}

export function placeMarkers(region, site, sites, index) {
  const districts = region.districts;
  const total = Math.min(region.items.length, MARKER_CAP);
  const camps = candidates(site, sites, index, Math.max(districts.length, 3) * 3);
  const markers = [];
  let placed = 0;
  districts.forEach((district, di) => {
    const camp = camps[(di * 2) % Math.max(1, camps.length)] || { x: site.x, z: site.z, y: heightAt(site.x, site.z) };
    const kind = KINDS[di % KINDS.length];
    const take = Math.min(district.items.length, Math.max(1, Math.round((total * district.items.length) / Math.max(1, region.items.length))));
    for (let i = 0; i < take && placed < total; i++) {
      const a = (i * 2.3999632) + di * 1.7;
      const rad = 22 + 17 * Math.sqrt(i + 0.6);
      let x = camp.x + Math.cos(a) * rad;
      let z = camp.z + Math.sin(a) * rad;
      let zf = zoneField(x, z, sites);
      let h = heightAt(x, z);
      // Walk back toward the camp until the spot is legal; the camp itself
      // is known good, so this always terminates somewhere valid.
      for (let s = 0; s < 6 && (zf.zone !== index || h < 6 || slopeAt(x, z) > 0.62); s++) {
        x = mix(x, camp.x, 0.45); z = mix(z, camp.z, 0.45);
        zf = zoneField(x, z, sites); h = heightAt(x, z);
      }
      if (zf.zone !== index || h < 6) { x = camp.x; z = camp.z; h = camp.y; }
      markers.push({
        id: district.items[i].id, item: district.items[i], zone: index, zoneId: site.id,
        district: district.name, kind, x, z, y: h,
        yaw: (noise2(x * 0.03, z * 0.03) + 1) * Math.PI,
        camp: di,
      });
      placed++;
    }
  });
  return markers;
}

/* ── the whole layout ───────────────────────────────────────────────────── */
export function computeIsland(atlas) {
  const regions = atlas.regions.slice(0, MAX_ZONES);
  const weights = zoneWeights(regions);
  const sites = regions.map((r, i) => ({ ...SITES[i], index: i, weight: weights[i] }));
  const zones = regions.map((region, i) => {
    const site = sites[i];
    const markers = placeMarkers(region, site, sites, i);
    const y = heightAt(site.x, site.z);
    return {
      index: i, id: region.id, siteId: site.id, name: region.name,
      place: site.name, biome: site.biome, note: site.note,
      x: site.x, z: site.z, y, labelY: y + site.labelY,
      weight: site.weight, total: region.total, share: region.share,
      first: region.first, last: region.last,
      districts: region.districts.map((d) => ({ name: d.name, total: d.total })),
      markers,
    };
  });
  const markers = zones.flatMap((z) => z.markers);
  const byId = new Map(markers.map((m) => [m.id, m]));
  return {
    sites, zones, markers, byId,
    total: atlas.total, label: atlas.label, demo: atlas.demo,
    stacks: STACKS, landStacks: LAND_STACKS, river: RIVER, falls: FALLS,
    zoneAt: (x, z) => zoneField(x, z, sites),
  };
}

export const zoneById = (layout, id) => layout.zones.find((z) => z.id === id) || null;
export const zoneBySite = (layout, siteId) => layout.zones.find((z) => z.siteId === siteId) || null;
