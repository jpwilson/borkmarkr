/* Camera tracks: centripetal Catmull-Rom splines through key positions and
   look targets. Time maps to arc length through a monotone cubic, so speed
   changes smoothly between keys and the track starts and ends at rest. */
import * as THREE from "three";

const DIVS = 48;
const smooth = (t) => t * t * (3 - 2 * t);

export function monotone(xs, ys) {
  const n = xs.length;
  if (n === 1) return () => ys[0];
  const d = [], m = new Array(n).fill(0);
  for (let i = 0; i < n - 1; i++) d.push((ys[i + 1] - ys[i]) / (xs[i + 1] - xs[i]));
  for (let i = 1; i < n - 1; i++) m[i] = d[i - 1] * d[i] <= 0 ? 0 : (d[i - 1] + d[i]) / 2;
  for (let i = 0; i < n - 1; i++) {
    if (d[i] === 0) { m[i] = 0; m[i + 1] = 0; continue; }
    const a = m[i] / d[i], b = m[i + 1] / d[i], s = a * a + b * b;
    if (s > 9) { const k = 3 / Math.sqrt(s); m[i] = k * a * d[i]; m[i + 1] = k * b * d[i]; }
  }
  return (x) => {
    if (x <= xs[0]) return ys[0];
    if (x >= xs[n - 1]) return ys[n - 1];
    let lo = 0, hi = n - 1;
    while (hi - lo > 1) { const mid = (lo + hi) >> 1; if (xs[mid] <= x) lo = mid; else hi = mid; }
    const h = xs[hi] - xs[lo], t = (x - xs[lo]) / h, t2 = t * t, t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * ys[lo] + (t3 - 2 * t2 + t) * h * m[lo] + (-2 * t3 + 3 * t2) * ys[hi] + (t3 - t2) * h * m[hi];
  };
}

export class Track {
  /* keys: [{ t, p: [x,y,z], q: [x,y,z], fov }] with strictly increasing t. */
  constructor(keys) {
    this.keys = keys;
    this.duration = keys[keys.length - 1].t;
    const P = keys.map((k) => new THREE.Vector3(...k.p));
    const Q = keys.map((k) => new THREE.Vector3(...k.q));
    if (P.length === 1) { P.push(P[0].clone()); Q.push(Q[0].clone()); }
    this.pos = new THREE.CatmullRomCurve3(P, false, "centripetal");
    this.tgt = new THREE.CatmullRomCurve3(Q, false, "centripetal");
    this.segments = P.length - 1;
    this.pos.arcLengthDivisions = this.segments * DIVS;
    const lengths = this.pos.getLengths();
    const total = lengths[lengths.length - 1];
    this.still = total < 1e-4;
    const s = keys.map((_, i) => (this.still ? i / Math.max(1, keys.length - 1) : lengths[Math.min(lengths.length - 1, i * DIVS)] / total));
    this.arcAt = monotone(keys.map((k) => k.t), s);
  }

  sample(t, out) {
    const s = this.arcAt(Math.min(Math.max(t, 0), this.duration));
    const u = this.still ? s : this.pos.getUtoTmapping(Math.min(1, Math.max(0, s)));
    this.pos.getPoint(u, out.p);
    this.tgt.getPoint(u, out.q);
    const f = u * this.segments, i = Math.min(this.segments - 1, Math.floor(f));
    const a = this.keys[Math.min(i, this.keys.length - 1)], b = this.keys[Math.min(i + 1, this.keys.length - 1)];
    out.fov = a.fov + (b.fov - a.fov) * smooth(f - i);
    return out;
  }
}
