/* The scripted tour used by the X video and by ?capture. Every beat is a
   deterministic function of time: given t, there is exactly one camera pose
   and one UI state, so renderAt(t) in a headless browser and the live
   playback agree frame for frame. */
import { readingTrail, regionById, tourPlan } from "./atlas-layout.js";
import { easeInOut } from "./atlas-scene.js";

const lerp = (a, b, t) => a + (b - a) * t;
const lerpAngle = (a, b, t) => a + ((((b - a) % (Math.PI * 2)) + Math.PI * 3) % (Math.PI * 2) - Math.PI) * t;

export class Tour {
  constructor({ atlas, layout, ground }) {
    this.atlas = atlas;
    this.layout = layout;
    this.ground = ground;
    this.plan = tourPlan(atlas, layout);
    this.region = this.plan.focusRegion ? regionById(layout, this.plan.focusRegion) : layout.regions[0];
    this.marker = this.region ? (this.region.markers.find((m) => m.id === this.plan.marker) || this.region.markers[0]) : null;
    this.trailPins = readingTrail(layout, { regionId: this.region ? this.region.id : null, count: 8 });
    this.globalTrail = readingTrail(layout, { count: 10 });
    this.duration = this.plan.duration;
    this.keys = this.buildKeys();
  }

  orbit(az, dist, pol) { return { tx: 0, ty: this.ground(0, 0) + 95, tz: 0, az, dist, pol }; }
  atRegion(az, dist, pol) {
    const r = this.region || { x: 0, z: 0 };
    return { tx: r.x, ty: this.ground(r.x, r.z) + 24, tz: r.z, az, dist, pol };
  }
  atMarker(az, dist, pol) {
    const m = this.marker || { x: 0, z: 0, y: 0 };
    return { tx: m.x, ty: this.ground(m.x, m.z) + 9, tz: m.z, az, dist, pol };
  }

  /* Chase camera: sits behind the point travelling along the trail. */
  chase(u) {
    const pins = this.trailPins.length >= 2 ? this.trailPins : this.globalTrail;
    if (pins.length < 2) return this.atRegion(0.6, 420, 1.18);
    const f = u * (pins.length - 1);
    const i = Math.min(pins.length - 2, Math.floor(f));
    const t = f - i;
    const a = pins[i], b = pins[i + 1];
    const x = lerp(a.x, b.x, t), z = lerp(a.z, b.z, t);
    const heading = Math.atan2(b.x - a.x, b.z - a.z);
    return { tx: x, ty: this.ground(x, z) + 70, tz: z, az: heading + Math.PI, dist: 430, pol: 1.16 };
  }

  buildKeys() {
    const ra = this.region ? Math.atan2(this.region.x, this.region.z) : 0;
    const keys = [
      [0, this.orbit(-0.58, 1280, 1.235)],
      [8, this.orbit(-0.10, 1110, 1.215)],
      [17, this.orbit(0.48, 960, 1.19)],
      [21.5, this.atRegion(ra - 0.75, 640, 1.19)],
      [25, this.atRegion(ra - 0.35, 420, 1.16)],
      [28.5, this.atMarker(ra - 0.05, 300, 1.12)],
      [32, this.atMarker(ra + 0.28, 235, 1.07)],
      [35.5, this.atRegion(ra + 0.55, 470, 1.14)],
      [39, this.chase(0)],
      [47, this.chase(1)],
      [50, this.orbit(1.45, 1040, 1.20)],
      [53, this.orbit(1.72, 1120, 1.215)],
      [this.duration, this.orbit(2.30, 1300, 1.235)],
    ];
    return keys;
  }

  cameraAt(time) {
    const t = Math.min(Math.max(time, 0), this.duration);
    if (t >= 39 && t <= 47) return this.chase(easeInOut((t - 39) / 8));
    const keys = this.keys;
    let i = 0;
    while (i < keys.length - 2 && t > keys[i + 1][0]) i++;
    const [t0, a] = keys[i], [t1, b] = keys[i + 1];
    const u = t1 === t0 ? 0 : easeInOut(Math.min(1, Math.max(0, (t - t0) / (t1 - t0))));
    return {
      tx: lerp(a.tx, b.tx, u), ty: lerp(a.ty, b.ty, u), tz: lerp(a.tz, b.tz, u),
      dist: lerp(a.dist, b.dist, u), pol: lerp(a.pol, b.pol, u), az: lerpAngle(a.az, b.az, u),
    };
  }

  /* UI state for a moment in the tour. */
  stateAt(time) {
    const t = Math.min(Math.max(time, 0), this.duration - 1e-4);
    const { beat, local } = this.plan.at(t);
    const s = {
      beat: beat.id,
      lower: { title: beat.label, sub: `${this.atlas.label} · ${this.atlas.total} bookmarks` },
      mode: "topics", tab: "layers", dim: "3d",
      focus: null, selection: null, hover: null,
      time: 1, trail: this.globalTrail, moment: null,
    };
    switch (beat.id) {
      case "orbit-in":
        s.tab = "overview";
        break;
      case "timeline":
        s.time = lerp(0.08, 1, easeInOut(local));
        s.tab = "overview";
        break;
      case "region":
        s.focus = this.region ? this.region.id : null;
        s.tab = local > 0.35 ? "overview" : "layers";
        break;
      case "detail":
        s.focus = this.region ? this.region.id : null;
        s.tab = "overview";
        s.hover = this.marker;
        s.selection = local >= 0.4 ? this.marker : null;
        break;
      case "sources":
        s.mode = "sources";
        s.focus = this.region ? this.region.id : null;
        s.selection = local < 0.3 ? this.marker : null;
        break;
      case "trail":
        s.focus = this.region ? this.region.id : null;
        s.trail = this.trailPins;
        s.tab = "layers";
        break;
      case "map2d":
        s.dim = "2d";
        s.tab = "overview";
        s.trail = this.globalTrail;
        break;
      default:
        s.tab = "overview";
        break;
    }
    if (["region", "detail", "sources", "trail"].includes(beat.id)) s.trail = this.trailPins;
    return s;
  }
}
