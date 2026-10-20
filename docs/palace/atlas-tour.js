/* The scripted tour used by the X video and by ?capture. Every beat is a
   deterministic function of time: given t, there is exactly one camera pose
   and one UI state, so renderAt(t) in a headless browser and the live
   playback agree frame for frame. */
import * as THREE from "three";
import { readingTrail, regionById, tourPlan } from "./atlas-layout.js";
import { easeInOut } from "./atlas-scene.js";

const lerp = (a, b, t) => a + (b - a) * t;
const lerpAngle = (a, b, t) => a + ((((b - a) % (Math.PI * 2)) + Math.PI * 3) % (Math.PI * 2) - Math.PI) * t;

export class Tour {
  constructor({ atlas, layout, ground, frameDist }) {
    this.atlas = atlas;
    this.layout = layout;
    this.ground = ground;
    this.frameDist = frameDist || (() => 1000);
    this.plan = tourPlan(atlas, layout);
    this.region = this.plan.focusRegion ? regionById(layout, this.plan.focusRegion) : layout.regions[0];
    this.marker = this.region ? (this.region.markers.find((m) => m.id === this.plan.marker) || this.region.markers[0]) : null;
    this.trailPins = readingTrail(layout, { regionId: this.region ? this.region.id : null, count: 8 });
    this.globalTrail = readingTrail(layout, { count: 10 });
    this.duration = this.plan.duration;
    // One smooth curve through the trail pins: the chase camera reads its
    // position and its heading from the tangent, so it never snaps at a pin.
    const pins = this.trailPins.length >= 2 ? this.trailPins : this.globalTrail;
    this.chaseCurve = pins.length >= 2
      ? new THREE.CatmullRomCurve3(pins.map((p) => new THREE.Vector3(p.x, 0, p.z)), false, "catmullrom", 0.35)
      : null;
    this.keyCache = null;
  }

  orbit(az, scale, pol) {
    return { tx: 0, ty: this.ground(0, 0) + 55, tz: 0, az, dist: this.frameDist(1.06) * scale, pol };
  }
  atRegion(az, dist, pol) {
    const r = this.region || { x: 0, z: 0 };
    return { tx: r.x, ty: this.ground(r.x, r.z) + 20, tz: r.z, az, dist, pol };
  }
  atMarker(az, dist, pol) {
    const m = this.marker || { x: 0, z: 0, y: 0 };
    return { tx: m.x, ty: this.ground(m.x, m.z) + 8, tz: m.z, az, dist, pol };
  }

  /* Chase camera: sits behind a point travelling along the smoothed route. */
  chase(u) {
    if (!this.chaseCurve) return this.atRegion(0.6, 420, 1.1);
    const t = Math.min(0.999, Math.max(0, u));
    const p = this.chaseCurve.getPointAt(t);
    const tan = this.chaseCurve.getTangentAt(t);
    const heading = Math.atan2(tan.x, tan.z);
    return { tx: p.x, ty: this.ground(p.x, p.z) + 55, tz: p.z, az: heading + Math.PI, dist: 400, pol: 1.08 };
  }

  keys() {
    const frame = Math.round(this.frameDist(1.06));
    if (this.keyCache && this.keyCache.frame === frame) return this.keyCache.keys;
    const ra = this.region ? Math.atan2(this.region.x, this.region.z) : 0;
    const keys = [
      [0, this.orbit(-0.58, 1.18, 1.085)],
      [8, this.orbit(-0.10, 1.03, 1.055)],
      [17, this.orbit(0.48, 0.88, 1.03)],
      [21.5, this.atRegion(ra - 0.75, 620, 1.12)],
      [25, this.atRegion(ra - 0.35, 400, 1.09)],
      [28.5, this.atMarker(ra - 0.05, 310, 1.07)],
      [32, this.atMarker(ra + 0.28, 230, 1.03)],
      [35.5, this.atRegion(ra + 0.55, 460, 1.09)],
      [39, this.chase(0)],
      [47, this.chase(1)],
      [50, this.orbit(1.45, 1.0, 1.06)],
      [53, this.orbit(1.72, 1.06, 1.07)],
      [this.duration, this.orbit(2.30, 1.2, 1.09)],
    ];
    this.keyCache = { frame, keys };
    return keys;
  }

  cameraAt(time) {
    const t = Math.min(Math.max(time, 0), this.duration);
    if (t >= 39 && t <= 47) return this.chase(easeInOut((t - 39) / 8));
    const keys = this.keys();
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
        s.tab = "layers";
        break;
      case "map2d":
        s.dim = "2d";
        s.tab = "overview";
        break;
      default:
        s.tab = "overview";
        break;
    }
    if (["region", "detail", "sources", "trail"].includes(beat.id)) s.trail = this.trailPins;
    return s;
  }
}
