/* island-tour.js — the scripted flight.

   A pure function of the layout: the keys are built once from the island and
   the library, and stateAt(t) only ever reads them. Nothing is cached between
   calls and nothing is mutated while a frame is being computed, so renderAt(t)
   gives the same camera, the same selection and the same caption whatever ran
   before it. */
import { heightAt, clamp, mix, zoneBySite, clearanceAt, canopyTopAt, liftOverCanopy, sunAt } from "./island-layout.js";

const v = (x, y, z) => ({ x, y, z });
const ease = (u) => u * u * (3 - 2 * u);
const easeIn = (u) => u * u;
const easeOut = (u) => 1 - (1 - u) * (1 - u);

function catmull(p0, p1, p2, p3, u, key) {
  const a = p1[key], b = p2[key];
  const m1 = (p2[key] - p0[key]) * 0.5, m2 = (p3[key] - p1[key]) * 0.5;
  const u2 = u * u, u3 = u2 * u;
  return (2 * u3 - 3 * u2 + 1) * a + (u3 - 2 * u2 + u) * m1 + (-2 * u3 + 3 * u2) * b + (u3 - u2) * m2;
}

/* ── reusable framings, shared by the tour and by ?capture poses ────────── */
export function overviewPose(layout, spin = 0) {
  /* The hero framing, and the one thing that decides whether the island is
     lit at all: at the old bearing the camera stood on the shadow side and
     every ridge in the frame was fill light. From here the sun is about
     forty degrees off the lens, so the near slopes take the key, the
     valleys behind them fall into blue shadow, and the sea stacks sit out
     to the right with the lagoon under the camera. */
  const a = 1.50 + spin;
  const d = 3380;
  return {
    pos: v(Math.cos(a) * d, 1280, Math.sin(a) * d),
    target: v(10, 330, -40),
    fov: 36,
  };
}

export function approachPose(layout, u = 0.5) {
  /* Low over the sea, in through the stacks — and now flown straight down
     the sun's own bearing, so the island comes up as a silhouette against
     the light with the shafts coming through the towers and the mist. A
     sun-side approach is the one frame in the film that can be backlit;
     every other beat wants the key on the land. */
  const far = v(3400, 70, -1750), near = v(1450, 108, -700);
  return {
    pos: v(mix(far.x, near.x, u), mix(far.y, near.y, u), mix(far.z, near.z, u)),
    target: v(mix(650, 150, u), mix(130, 260, u), mix(120, -60, u)),
    fov: 44,
  };
}

export function mapPose(layout) {
  return { pos: v(0.1, 4300, 0.1), target: v(0, 0, 0), fov: 34, top: true };
}

/* A close aerial on a zone: back off along the bearing from the island's
   centre, drop to a helicopter height, and tilt down into the terrain. */
export function zonePose(layout, zone, opts = {}) {
  if (!zone) return overviewPose(layout);
  // each place is framed from the side that shows what it is: the falls from
  // out at sea, the lagoon off the reef, the valley looking up it
  const framing = {
    volcano:  { dist: 1180, height: 760, lift: 300, fov: 40, az: 1.45 },
    karst:    { dist: 1180, height: 560, lift: 150, fov: 38, az: 0.42 },
    temple:   { dist: 820,  height: 520, lift: 60,  fov: 38, az: 1.62 },
    river:    { dist: 780,  height: 430, lift: 40,  fov: 42, az: 1.95 },
    falls:    { dist: 1120, height: 390, lift: 190, fov: 38, az: -1.86, abs: true, aim: [-80, -400] },
    swamp:    { dist: 600,  height: 430, lift: 16,  fov: 42, az: 2.05 },
    lagoon:   { dist: 860,  height: 520, lift: 50,  fov: 40, az: 1.46, aim: [-150, -160] },
    highland: { dist: 940,  height: 660, lift: 180, fov: 40, az: 2.55 },
    crater:   { dist: 720,  height: 540, lift: 110, fov: 40, az: 1.85 },
  }[zone.siteId] || { dist: 820, height: 500, lift: 60, fov: 42, az: 1.35 };
  // look into the sun side so the slope is rim-lit and the mist glows
  const a = framing.az + (opts.spin || 0) + (opts.offset ?? 0) * 0.6;
  const d = framing.dist * (opts.dist || 1);
  // `aim` nudges the subject off the site itself — the falls want the cliff
  const [ax, az2] = framing.aim || [0, 0];
  const tx = zone.x + ax, tz = zone.z + az2;
  const base = framing.abs ? 0 : zone.y;
  const pos = v(tx + Math.cos(a) * d, base + framing.height, tz + Math.sin(a) * d);
  const target = v(tx, base + framing.lift, tz);
  // a low beat over a dense zone would otherwise sit inside the crowns — and
  // even eighty metres clear of them, a crown that close fills a third of the
  // frame with one green blob. Hold the lens well off the canopy.
  pos.y = Math.max(pos.y, clearanceAt(pos.x, pos.z, layout.clearings, 78));
  return { pos, target, fov: framing.fov };
}

export function markerPose(layout, marker, opts = {}) {
  if (!marker) return overviewPose(layout);
  // stand outside the camp, looking in: anywhere else and the camera ends up
  // over the middle of the cluster and the clearing reads as a hole
  const out = Math.atan2(marker.z - (marker.campZ ?? marker.z - 1), marker.x - (marker.campX ?? marker.x));
  // out along the camp's own radius, so the marker stands nearest the lens and
  // the rest of its camp falls away behind it; tilted off that line toward
  // whichever side of the clearing lies lower, so the camera looks downhill
  const side = heightAt(marker.x + Math.cos(out + 1.0) * 46, marker.z + Math.sin(out + 1.0) * 46)
    <= heightAt(marker.x + Math.cos(out - 1.0) * 46, marker.z + Math.sin(out - 1.0) * 46) ? 1 : -1;
  /* A helicopter hover, not a tripod. The near geometry of this island is a
     scatter of blobs: at eye level it reads as toy, and no amount of lighting
     fixes that. So the close-up is flown — a hundred and fifty metres up,
     tipped forty degrees down, the camp small and marked, the canopy around
     it doing the work. `alt` is metres above the camp and `pitch` is the
     tilt; the ground distance follows from them, never the other way round,
     because a camera lifted over a crown must not turn into a plan view. */
  const target = v(marker.x, marker.y + 8, marker.z);
  const alt = opts.alt ?? 255;
  const pitch = opts.pitch ?? 0.72;
  const tan = Math.tan(pitch);
  /* Where to hover. The near geometry of this island is a scatter of blobs
     and the emergents among them are fifty metres across: one standing on a
     ridge a hundred and fifty metres off the lens is a third of the frame,
     and that single blob is what makes a close-up read as a tabletop. So the
     framing is chosen, not assumed — every bearing round the camp is scored
     by how badly the canopy would crowd the lens there, at three heights,
     and the cheapest clear frame wins. */
  const crowd = (px, pz, py) => {
    let worst = 0;
    for (let i = 0; i < 12; i++) {
      const ang = (i / 12) * Math.PI * 2 + 0.3;
      for (const rad of [110, 190, 300]) {
        const top = canopyTopAt(px + Math.cos(ang) * rad, pz + Math.sin(ang) * rad, layout.clearings);
        const size = (52 + Math.max(0, top - py)) / Math.hypot(rad, Math.max(24, py - top));
        if (size > worst) worst = size;
      }
    }
    return worst;
  };
  const nominal = out + side * 0.55;
  const bearings = opts.angle != null ? [opts.angle]
    : Array.from({ length: 12 }, (_, i) => nominal + (i / 12) * Math.PI * 2);
  let best = null;
  for (const a of bearings) {
    for (const k of [1, 1.3, 1.6, 1.9]) {
      const y0 = target.y + alt * k;
      const d = (y0 - target.y) / tan;
      const x = marker.x + Math.cos(a) * d, z = marker.z + Math.sin(a) * d;
      const y = Math.max(y0, clearanceAt(x, z, layout.clearings, 72));
      // nudged back toward the camp's open side, and toward staying low:
      // height is bought only where it actually buys a clear frame
      const off = Math.abs(((a - nominal + Math.PI * 3) % (Math.PI * 2)) - Math.PI);
      const score = crowd(x, z, y) + off * 0.012 + (k - 1) * 0.05;
      if (!best || score < best.score) best = { score, a, pos: v(x, y, z) };
    }
  }
  // and climb until nothing — ground or crown — stands in the line of sight
  const pos = liftOverCanopy(best.pos, target, layout.clearings, 18);
  return { pos, target, fov: opts.fov ?? 34, angle: best.a };
}

/* The bookmark the tour lands on. The beat is the one close-up in the film,
   so the camp it picks has to be one the golden hour actually reaches: a
   landing in a ridge shadow is a black frame however well it is composed.
   Preference order breaks ties between equally lit camps. */
export function heroMarker(layout) {
  const prefer = ["river", "lagoon", "highland", "temple", "karst", "swamp", "volcano"];
  let best = null, bestScore = -1;
  prefer.forEach((siteId, rank) => {
    const zone = zoneBySite(layout, siteId);
    if (!zone || !zone.markers.length) return;
    const biggest = zone.districts.reduce((a, b) => (b.total > a.total ? b : a), zone.districts[0]);
    const seen = new Set();
    for (const m of zone.markers) {
      if (seen.has(m.camp)) continue;
      seen.add(m.camp);
      const score = sunAt(m.campX, m.campZ) * 2
        + (m.district === biggest.name ? 0.5 : 0)
        - rank * 0.14;
      if (score > bestScore) { bestScore = score; best = m; }
    }
  });
  return best || layout.markers[0] || null;
}

function zonesForTour(layout) {
  // the volcano, then the two most distinctive biomes the library reaches
  const want = ["volcano", "falls", "river", "karst", "lagoon", "temple", "highland", "swamp", "crater"];
  const picked = [];
  for (const id of want) {
    const z = zoneBySite(layout, id);
    if (z) picked.push(z);
    if (picked.length >= 3) break;
  }
  return picked.length ? picked : layout.zones.slice(0, 3);
}

export function buildPlan(layout) {
  const hero = heroMarker(layout);
  // an empty library still gets a flight: the island is there, it is simply
  // uninhabited, so the beats that land on a bookmark are left out entirely
  const heroZone = hero ? layout.zones[hero.zone] : null;
  const tourZones = zonesForTour(layout);
  const keys = [];
  const beats = [];
  const push = (id, label, length, detail) => {
    const start = beats.length ? beats[beats.length - 1].end : 0;
    const beat = { id, label, detail, start, end: start + length, length };
    beats.push(beat);
    return beat;
  };
  const at = (beat, f) => beat.start + beat.length * f;
  const key = (t, pose, extra = {}) => keys.push({ t, ...pose, roll: 0, ...extra });

  /* 1 — in off the sea, low, through the mist and the stacks */
  const approach = push("approach", "Open sea", 8, layout.total ? `${layout.total} saves on one island` : "Nothing saved here yet");
  key(at(approach, 0), { ...approachPose(layout, 0), fov: 46 }, { roll: 0.02 });
  key(at(approach, 0.55), approachPose(layout, 0.52), { roll: -0.03 });
  key(at(approach, 1), approachPose(layout, 0.92), { roll: -0.05 });

  /* 2 — rise over the reef and the coast */
  const rise = push("rise", "The coast", 5, "Reef, surf line, first canopy");
  key(at(rise, 0.5), { pos: v(1250, 430, -380), target: v(120, 230, -160), fov: 42 }, { roll: -0.04 });
  key(at(rise, 1), { pos: v(1540, 880, 1380), target: v(40, 250, -120), fov: 40 }, { roll: -0.02 });

  /* 3 — the whole island */
  const over = push("overview", "Library Island", 6, `${layout.zones.length} zones`);
  key(at(over, 0.45), overviewPose(layout, 0.13));
  key(at(over, 1), overviewPose(layout, -0.02));

  /* 4..n — a pass over each featured zone */
  tourZones.forEach((zone) => {
    const b = push(`zone-${zone.siteId}`, zone.place, 6, `${zone.name} · ${zone.total} saved`);
    b.zone = zone.index;
    key(at(b, 0.12), zonePose(layout, zone, { offset: 1.0, dist: 1.5 }));
    key(at(b, 0.62), zonePose(layout, zone, { offset: 0.62, dist: 1.05 }), { roll: 0.035 });
    key(at(b, 1), zonePose(layout, zone, { offset: 0.2, dist: 0.92 }), { roll: 0.02 });
  });

  /* then down into the zone the hero marker is in, and land on it */
  if (hero && heroZone) {
    // the landing is a descent along one bearing: pick the bearing the final
    // hover chose and fly the whole approach down it, or the three keys each
    // solve for their own best side and the camera crabs between them
    const hover = markerPose(layout, hero);
    const angle = hover.angle;
    const dip = push("dip", heroZone.place, 5, `${heroZone.biome}`);
    dip.zone = heroZone.index;
    key(at(dip, 0.1), zonePose(layout, heroZone, { offset: 0.9, dist: 1.25 }));
    key(at(dip, 1), markerPose(layout, hero, { alt: 430, pitch: 0.62, fov: 40, angle }));

    const land = push("marker", "One bookmark", 6, hero.item.title);
    land.zone = heroZone.index;
    land.marker = hero.id;
    key(at(land, 0.35), markerPose(layout, hero, { alt: 340, pitch: 0.68, angle }));
    key(at(land, 1), hover);
  }

  const out = push("pullout", "Library Island", 6,
    layout.total ? `${layout.total} saves · ${layout.zones.length} zones` : "Save a link and it lands here");
  if (hero) {
    // the pull-out has to actually pull out: half a kilometre up and a
    // kilometre back, or the beat is another low skim over the crowns
    key(at(out, 0.42), { pos: v(hero.x + 900, hero.y + 1020, hero.z + 1080), target: v(hero.x, hero.y + 60, hero.z), fov: 40 });
  } else {
    key(at(out, 0.42), overviewPose(layout, 0.55));
  }
  key(at(out, 1), overviewPose(layout, 0.22));

  keys.sort((a, b) => a.t - b.t);
  const duration = beats[beats.length - 1].end;
  return { keys, beats, duration, hero, heroZone, zones: tourZones };
}

export class Tour {
  constructor(layout) {
    this.layout = layout;
    this.plan = buildPlan(layout);
    this.duration = this.plan.duration;
  }
  beatAt(t) {
    const { beats } = this.plan;
    for (const b of beats) if (t >= b.start && t < b.end) return b;
    return beats[beats.length - 1];
  }
  /* Pure: same t in, same state out. */
  stateAt(time) {
    const t = clamp(time, 0, this.duration);
    const k = this.plan.keys;
    let i = 0;
    while (i < k.length - 2 && t > k[i + 1].t) i++;
    const a = k[i], b = k[Math.min(i + 1, k.length - 1)];
    const span = Math.max(1e-6, b.t - a.t);
    const u = ease(clamp((t - a.t) / span, 0, 1));
    const p0 = k[Math.max(0, i - 1)], p3 = k[Math.min(k.length - 1, i + 2)];
    const pos = {
      x: catmull(p0.pos, a.pos, b.pos, p3.pos, u, "x"),
      y: catmull(p0.pos, a.pos, b.pos, p3.pos, u, "y"),
      z: catmull(p0.pos, a.pos, b.pos, p3.pos, u, "z"),
    };
    const target = {
      x: catmull(p0.target, a.target, b.target, p3.target, u, "x"),
      y: catmull(p0.target, a.target, b.target, p3.target, u, "y"),
      z: catmull(p0.target, a.target, b.target, p3.target, u, "z"),
    };
    // never fly through the island — or through the canopy standing on it
    const clearings = this.layout.clearings;
    const floor = clearanceAt(pos.x, pos.z, clearings, 68);
    if (pos.y < floor) pos.y = floor;
    const beat = this.beatAt(t);
    const local = clamp((t - beat.start) / beat.length, 0, 1);
    // on a beat that holds a bookmark, the frame is only worth anything if the
    // camp is actually visible: lift the camera until the sight line is clear
    if (beat.marker) {
      const m = this.layout.byId?.get(beat.marker);
      if (m && (pos.x !== target.x || pos.z !== target.z)) {
        const clear = liftOverCanopy(pos, { x: m.x, y: m.y + 11, z: m.z }, clearings, 18);
        if (clear.y > pos.y) { target.y += clear.y - pos.y; pos.y = clear.y; }
      }
    }
    return {
      t, pos, target,
      fov: mix(a.fov, b.fov, u),
      roll: mix(a.roll || 0, b.roll || 0, u),
      beat: beat.id,
      beatLabel: beat.label,
      beatDetail: beat.detail,
      zone: beat.zone ?? null,
      // the card opens a beat into the landing and stays open to the end of it
      marker: beat.marker && local > 0.18 ? beat.marker : null,
      progress: t / this.duration,
    };
  }
}
