/* island-tour.js — the scripted flight.

   A pure function of the layout: the keys are built once from the island and
   the library, and stateAt(t) only ever reads them. Nothing is cached between
   calls and nothing is mutated while a frame is being computed, so renderAt(t)
   gives the same camera, the same selection and the same caption whatever ran
   before it. */
import { heightAt, clamp, mix, zoneBySite } from "./island-layout.js";

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
  const a = -0.30 + spin;
  const d = 2460;
  return {
    pos: v(Math.cos(a) * d, 1180, Math.sin(a) * d),
    target: v(-40, 230, -90),
    fov: 38,
  };
}

export function approachPose(layout, u = 0.5) {
  // low over the sea, coming in through the stacks from the east
  const far = v(3750, 78, 980), near = v(1560, 112, 330);
  return {
    pos: v(mix(far.x, near.x, u), mix(far.y, near.y, u), mix(far.z, near.z, u)),
    target: v(mix(600, 180, u), mix(150, 240, u), mix(-180, -230, u)),
    fov: 44,
  };
}

export function mapPose(layout) {
  return { pos: v(0.1, 4300, 0.1), target: v(0, 0, 0), fov: 34, top: true };
}

/* A close aerial on a zone: back off along the bearing from the island's
   centre, drop to a helicopter height, and tilt down into the terrain. */
export function zonePose(layout, zone, opts = {}) {
  const framing = {
    volcano:  { dist: 980, height: 760, lift: 180, fov: 40 },
    karst:    { dist: 780, height: 330, lift: 60,  fov: 42 },
    temple:   { dist: 520, height: 300, lift: 40,  fov: 40 },
    river:    { dist: 620, height: 310, lift: 30,  fov: 42 },
    falls:    { dist: 880, height: 420, lift: 70,  fov: 42 },
    swamp:    { dist: 560, height: 230, lift: 18,  fov: 44 },
    lagoon:   { dist: 700, height: 300, lift: 20,  fov: 42 },
    highland: { dist: 820, height: 560, lift: 120, fov: 40 },
    crater:   { dist: 620, height: 470, lift: 90,  fov: 40 },
  }[zone.siteId] || { dist: 700, height: 340, lift: 60, fov: 42 };
  // look into the sun side so the slope is rim-lit and the mist glows
  const bearing = Math.atan2(zone.z, zone.x) + (opts.spin || 0);
  const a = bearing + (opts.offset ?? 0.55);
  const d = framing.dist * (opts.dist || 1);
  const pos = v(zone.x + Math.cos(a) * d, zone.y + framing.height, zone.z + Math.sin(a) * d);
  return { pos, target: v(zone.x, zone.y + framing.lift, zone.z), fov: framing.fov };
}

export function markerPose(layout, marker, opts = {}) {
  const a = (opts.angle ?? 2.25);
  const d = opts.dist ?? 34;
  return {
    pos: v(marker.x + Math.cos(a) * d, marker.y + 16, marker.z + Math.sin(a) * d),
    target: v(marker.x, marker.y + 6.5, marker.z),
    fov: 36,
  };
}

/* The bookmark the tour lands on: the oldest save in the biggest district of
   the temple zone, falling back to whatever the island actually has. */
export function heroMarker(layout) {
  const prefer = ["temple", "river", "lagoon"];
  for (const siteId of prefer) {
    const zone = zoneBySite(layout, siteId);
    if (zone && zone.markers.length) {
      const best = zone.districts.reduce((a, b) => (b.total > a.total ? b : a), zone.districts[0]);
      return zone.markers.find((m) => m.district === best.name) || zone.markers[0];
    }
  }
  return layout.markers[0] || null;
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
  const heroZone = hero ? layout.zones[hero.zone] : layout.zones[0];
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
  const approach = push("approach", "Open sea", 8, `${layout.total} saves on one island`);
  key(at(approach, 0), { ...approachPose(layout, 0), fov: 46 }, { roll: 0.02 });
  key(at(approach, 0.55), approachPose(layout, 0.52), { roll: -0.03 });
  key(at(approach, 1), approachPose(layout, 0.92), { roll: -0.05 });

  /* 2 — rise over the reef and the coast */
  const rise = push("rise", "The coast", 5, "Reef, surf line, first canopy");
  key(at(rise, 0.5), { pos: v(1500, 420, 60), target: v(300, 220, -160), fov: 42 }, { roll: -0.04 });
  key(at(rise, 1), { pos: v(2150, 820, -260), target: v(60, 230, -140), fov: 40 }, { roll: -0.02 });

  /* 3 — the whole island */
  const over = push("overview", "Library Island", 6, `${layout.zones.length} zones`);
  key(at(over, 0.45), overviewPose(layout, 0.13));
  key(at(over, 1), overviewPose(layout, -0.02));

  /* 4..n — a pass over each featured zone */
  const zoneBeats = [];
  tourZones.forEach((zone, i) => {
    const b = push(`zone-${zone.siteId}`, zone.place, 6, `${zone.name} · ${zone.total} saved`);
    b.zone = zone.index;
    zoneBeats.push(b);
    key(at(b, 0.12), zonePose(layout, zone, { offset: 1.0, dist: 1.5 }));
    key(at(b, 0.62), zonePose(layout, zone, { offset: 0.62, dist: 1.05 }), { roll: 0.035 });
    key(at(b, 1), zonePose(layout, zone, { offset: 0.2, dist: 0.92 }), { roll: 0.02 });
  });

  /* then down into the zone the hero marker is in, and land on it */
  const dip = push("dip", heroZone.place, 5, `${heroZone.biome}`);
  dip.zone = heroZone.index;
  key(at(dip, 0.1), zonePose(layout, heroZone, { offset: 0.9, dist: 1.25 }));
  key(at(dip, 1), {
    pos: v(hero.x + Math.cos(2.25) * 150, hero.y + 78, hero.z + Math.sin(2.25) * 150),
    target: v(hero.x, hero.y + 10, hero.z), fov: 38,
  });

  const land = push("marker", "One bookmark", 6, hero ? hero.item.title : "");
  land.zone = heroZone.index;
  land.marker = hero ? hero.id : null;
  key(at(land, 0.35), markerPose(layout, hero, { dist: 58, angle: 2.25 }));
  key(at(land, 1), markerPose(layout, hero, { dist: 33, angle: 2.05 }));

  const out = push("pullout", "Library Island", 6, `${layout.total} saves · ${layout.zones.length} zones`);
  key(at(out, 0.42), { pos: v(hero.x + 520, hero.y + 560, hero.z + 620), target: v(hero.x, hero.y, hero.z), fov: 40 });
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
    // never fly through the island
    const floor = heightAt(pos.x, pos.z) + 16;
    if (pos.y < floor) pos.y = floor;
    const beat = this.beatAt(t);
    const local = clamp((t - beat.start) / beat.length, 0, 1);
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
