/* island-props.js — everything carved out of rock: the limestone towers that
   give the island its Skull Island silhouette, the stepped temple and its
   fallen columns, scattered boulders and driftwood. All of it is built into
   plain buffers by the small Build helper below and merged into a handful of
   draw calls, with sun visibility baked per vertex from the terrain field. */
import * as THREE from "three";
import { sampleGrid, groundAt, PAL, terrainMaterial } from "./island-terrain.js";
import { clamp, mix, sstep, noise2, fbm, heightAt, STACKS, LAND_STACKS } from "./island-layout.js";

/* ── a tiny geometry builder ────────────────────────────────────────────── */
export class Build {
  constructor() { this.pos = []; this.nrm = []; this.col = []; this.lit = []; this.idx = []; }
  get count() { return this.pos.length / 3; }
  vert(x, y, z, nx, ny, nz, c, shade, ao = 1, moist = 0) {
    this.pos.push(x, y, z); this.nrm.push(nx, ny, nz);
    this.col.push(c[0], c[1], c[2]); this.lit.push(shade, ao, moist);
    return this.count - 1;
  }
  tri(a, b, c) { this.idx.push(a, b, c); }
  quad(a, b, c, d) { this.idx.push(a, b, c, a, c, d); }
  /* an axis-aligned box, optionally yawed, with flat normals */
  box(cx, cy, cz, sx, sy, sz, yaw, col, shade, ao = 1) {
    const ca = Math.cos(yaw), sa = Math.sin(yaw);
    const P = (x, y, z) => [cx + x * ca - z * sa, cy + y, cz + x * sa + z * ca];
    const hx = sx / 2, hy = sy / 2, hz = sz / 2;
    const corners = [
      P(-hx, -hy, -hz), P(hx, -hy, -hz), P(hx, -hy, hz), P(-hx, -hy, hz),
      P(-hx, hy, -hz), P(hx, hy, -hz), P(hx, hy, hz), P(-hx, hy, hz),
    ];
    const faces = [
      [4, 5, 6, 7, 0, 1, 0], [0, 3, 2, 1, 0, -1, 0],
      [3, 7, 6, 2, 0, 0, 1], [0, 1, 5, 4, 0, 0, -1],
      [1, 2, 6, 5, 1, 0, 0], [0, 4, 7, 3, -1, 0, 0],
    ];
    for (const [a, b, c, d, nx, ny, nz] of faces) {
      const n = [nx * ca - nz * sa, ny, nx * sa + nz * ca];
      const tone = 0.82 + 0.18 * (ny * 0.5 + 0.5) + 0.08 * n[0];
      const cc = [col[0] * tone, col[1] * tone, col[2] * tone];
      const i0 = this.vert(...corners[a], ...n, cc, shade, ao);
      const i1 = this.vert(...corners[b], ...n, cc, shade, ao);
      const i2 = this.vert(...corners[c], ...n, cc, shade, ao);
      const i3 = this.vert(...corners[d], ...n, cc, shade, ao);
      this.quad(i0, i1, i2, i3);
    }
  }
  cylinder(cx, cy, cz, r0, r1, h, seg, col, shade, tilt = 0, yaw = 0, ao = 1) {
    const base = [];
    const top = [];
    const ct = Math.cos(tilt), st = Math.sin(tilt);
    const cyw = Math.cos(yaw), syw = Math.sin(yaw);
    const place = (x, y, z) => {
      const y2 = y * ct - x * st, x2 = x * ct + y * st;
      return [cx + x2 * cyw - z * syw, cy + y2, cz + x2 * syw + z * cyw];
    };
    for (let i = 0; i < seg; i++) {
      const a = (i / seg) * Math.PI * 2;
      const nx = Math.cos(a), nz = Math.sin(a);
      const tone = 0.76 + 0.3 * (0.5 + 0.5 * Math.cos(a - 2.4));
      const cc = [col[0] * tone, col[1] * tone, col[2] * tone];
      base.push(this.vert(...place(nx * r0, 0, nz * r0), nx, 0.1, nz, cc, shade, ao));
      top.push(this.vert(...place(nx * r1, h, nz * r1), nx, 0.1, nz, [cc[0] * 1.1, cc[1] * 1.1, cc[2] * 1.1], shade, ao));
    }
    for (let i = 0; i < seg; i++) {
      const j = (i + 1) % seg;
      this.quad(base[i], base[j], top[j], top[i]);
    }
    // cap
    const capC = this.vert(...place(0, h, 0), 0, 1, 0, [col[0] * 1.14, col[1] * 1.14, col[2] * 1.14], shade, ao);
    const cap = [];
    for (let i = 0; i < seg; i++) {
      const a = (i / seg) * Math.PI * 2;
      cap.push(this.vert(...place(Math.cos(a) * r1, h, Math.sin(a) * r1), 0, 1, 0, [col[0] * 1.14, col[1] * 1.14, col[2] * 1.14], shade, ao));
    }
    for (let i = 0; i < seg; i++) this.tri(capC, cap[i], cap[(i + 1) % seg]);
  }
  geometry() {
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute("normal", new THREE.Float32BufferAttribute(this.nrm, 3));
    g.setAttribute("color", new THREE.Float32BufferAttribute(this.col, 3));
    g.setAttribute("lit", new THREE.Float32BufferAttribute(this.lit, 3));
    g.setIndex(this.count > 65535 ? new THREE.Uint32BufferAttribute(this.idx, 1) : new THREE.Uint16BufferAttribute(this.idx, 1));
    g.computeBoundingSphere();
    return g;
  }
}

const mixc = (a, b, t) => [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];

/* ── limestone towers ───────────────────────────────────────────────────── */
/* Undercut at the waterline, fluted sides, mossy shelves, a rounded crown —
   the profile of a Ha Long Bay stack rather than a cone. */
function tower(b, cx, cz, R, H, baseY, field, seed) {
  const RINGS = 24, SEG = 26;
  const rows = [];
  const shadeBase = field ? clamp(sampleGrid(field, field.shade, cx, cz) * 0.5 + 0.5, 0, 1) : 0.95;
  // each tower has its own plan shape and lean, so a cluster never repeats
  const ex = 1 + 0.34 * noise2(seed, 1.3), ez = 1 - 0.28 * noise2(seed + 4.4, 2.9);
  const twist = noise2(seed * 2.2, 0.7) * 1.1;
  const leanX = noise2(seed, 7.7) * 0.10, leanZ = noise2(seed + 2, 5.1) * 0.10;
  // some towers taper like a blade, others stand almost straight
  const taper = 0.08 + 0.42 * Math.abs(noise2(seed * 1.7, 3.3));
  const breakAt = 0.74 + 0.2 * Math.abs(noise2(seed + 9, 1.1));
  for (let r = 0; r <= RINGS; r++) {
    const t = r / RINGS;
    // sheer to about three-quarters height, then break into a crown
    const prof = 1 - taper * t - 0.9 * Math.pow(Math.max(0, (t - breakAt) / (1 - breakAt)), 1.7);
    const ledge = 1 + 0.045 * Math.sin(t * 21 + seed * 3.1) + 0.03 * Math.sin(t * 7.3 - seed);
    const row = [];
    const y = baseY + t * H;
    for (let i = 0; i < SEG; i++) {
      const a = (i / SEG) * Math.PI * 2 + twist * t;
      const fl = Math.sin(a * 8 + seed * 2.1), fn = noise2(Math.cos(a) * 2.6 + seed, Math.sin(a) * 2.6 + t * 1.6);
      // the crown breaks into separate crags rather than rounding off
      const crag = t > breakAt ? 0.45 * noise2(Math.cos(a) * 3.4 + seed * 2, Math.sin(a) * 3.4) * ((t - breakAt) / (1 - breakAt)) : 0;
      const flute = 1 + 0.13 * fl + 0.11 * fn + 0.05 * Math.sin(a * 21 + t * 4.0) + crag;
      const rad = R * Math.max(0.02, prof) * ledge * flute;
      const x = cx + Math.cos(a) * rad * ex + leanX * t * H;
      const z = cz + Math.sin(a) * rad * ez + leanZ * t * H;
      // pale limestone; narrow wet streaks; moss in the gullies and the crown
      const streak = clamp(0.5 + 0.8 * noise2(a * 5.1 + seed, t * 0.9), 0, 1);
      let c = mixc(PAL.limestone, PAL.rockPale, 0.3 + 0.4 * noise2(a * 2.3, t * 2.1));
      c = mixc(c, PAL.rockWet, Math.pow(clamp((streak - 0.62) * 2.8, 0, 1), 1.7) * 0.28);
      const moss = clamp(0.55 * Math.pow(t, 2.0) + 0.75 * noise2(a * 1.9 - seed, t * 3.3) - 0.12, 0, 1);
      c = mixc(c, moss > 0.6 ? PAL.jungleMid : PAL.moss, clamp((moss - 0.42) * 1.5, 0, 0.8));
      // the grooves are drawn with shading, not geometry: cheap and legible
      const groove = clamp(0.58 + 0.46 * (fl * 0.6 + fn * 0.5) + 0.12 * Math.sin(a * 21 + t * 4.0), 0.3, 1.25);
      const up = (0.82 + 0.4 * t) * groove;
      row.push(b.vert(x, y, z, Math.cos(a) * ex, 0.12 + t * 0.35, Math.sin(a) * ez,
        [c[0] * up, c[1] * up, c[2] * up], shadeBase * (0.62 + 0.38 * t), 0.5 + 0.5 * t, 0.2));
    }
    rows.push(row);
  }
  for (let r = 0; r < RINGS; r++) for (let i = 0; i < SEG; i++) {
    const j = (i + 1) % SEG;
    b.quad(rows[r][i], rows[r][j], rows[r + 1][j], rows[r + 1][i]);
  }
  const topC = b.vert(cx + leanX * H, baseY + H + R * 0.05, cz + leanZ * H, 0, 1, 0,
    mixc(PAL.limestone, PAL.moss, 0.45), shadeBase, 1, 0.3);
  for (let i = 0; i < SEG; i++) b.tri(topC, rows[RINGS][i], rows[RINGS][(i + 1) % SEG]);
}

export function buildStacks(field, uniforms) {
  const b = new Build();
  const list = [];
  STACKS.forEach(([x, z, r, h], i) => { tower(b, x, z, r, h, -26, field, i * 1.7); list.push({ x, z, r, h, sea: true }); });
  LAND_STACKS.forEach(([x, z, r, h], i) => {
    const base = groundAt(field, x, z) - 14;
    tower(b, x, z, r, h, base, field, 9.1 + i * 2.3);
    list.push({ x, z, r, h: h + base, sea: false });
  });
  const mesh = new THREE.Mesh(b.geometry(), terrainMaterial(uniforms));
  mesh.name = "stacks";
  mesh.userData.tris = b.idx.length / 3;
  mesh.userData.list = list;
  return mesh;
}

/* ── the temple ─────────────────────────────────────────────────────────── */
/* A stepped ziggurat with a stair down its face, a ring of columns — most of
   them broken — and blocks that have slid off into the grass. */
export function buildTemple(field, uniforms, site) {
  const b = new Build();
  const cx = site.x, cz = site.z;
  const base = groundAt(field, cx, cz);
  const shade = clamp(sampleGrid(field, field.shade, cx, cz) * 0.45 + 0.55, 0, 1);
  const stone = mixc(PAL.limestone, PAL.rockPale, 0.25);
  const mossy = mixc(stone, PAL.moss, 0.42);
  const yaw = 0.42;

  const tiers = 5;
  for (let i = 0; i < tiers; i++) {
    const w = 122 - i * 19, hh = 11 - i * 0.7;
    const y = base + i * (11 - 0.7) + hh / 2 - 2;
    const c = mixc(stone, mossy, 0.25 + 0.14 * i);
    b.box(cx, y, cz, w, hh, w, yaw, c, shade, 0.85 - i * 0.05);
  }
  // shrine on top
  b.box(cx, base + tiers * 10.3 + 7, cz, 26, 15, 26, yaw, mixc(stone, mossy, 0.5), shade, 0.8);
  b.box(cx, base + tiers * 10.3 + 16, cz, 30, 4, 30, yaw, mixc(stone, PAL.moss, 0.6), shade, 0.75);

  // stair down the south face
  const sa = yaw;
  for (let i = 0; i < 16; i++) {
    const t = i / 15;
    const w = 26;
    const d = 62 - t * 34;
    const y = base + t * (tiers * 10.3) + 1;
    b.box(cx + Math.sin(sa) * d, y, cz + Math.cos(sa) * d, w, 3.4, 7, yaw, mixc(stone, mossy, 0.3 + t * 0.3), shade, 0.8);
  }

  // columns, mostly broken, around a cleared plaza
  for (let i = 0; i < 14; i++) {
    const a = (i / 14) * Math.PI * 2 + 0.2;
    const rad = 118 + 16 * noise2(i * 1.3, 2.1);
    const x = cx + Math.cos(a) * rad, z = cz + Math.sin(a) * rad;
    const g = groundAt(field, x, z);
    const broken = noise2(i * 2.7, 5.5);
    const h = broken > 0.1 ? 26 + 10 * broken : 7 + 12 * Math.abs(broken);
    b.cylinder(x, g - 1, z, 4.4, 3.9, h, 9, mixc(stone, mossy, 0.3 + 0.4 * Math.abs(broken)), shade * 0.95);
    if (broken > 0.3) b.box(x, g + h + 1.6, z, 11, 3.2, 11, a, mixc(stone, mossy, 0.5), shade, 0.8);
    else {
      // a toppled drum lying in the grass
      const fx = x + Math.cos(a + 1.1) * 14, fz = z + Math.sin(a + 1.1) * 14;
      b.cylinder(fx, groundAt(field, fx, fz) + 3, fz, 4.2, 4.0, 13, 8, mixc(stone, PAL.moss, 0.55), shade, Math.PI / 2, a + 1.1);
    }
  }
  // fallen blocks
  for (let i = 0; i < 22; i++) {
    const a = i * 2.3999632;
    const rad = 70 + 110 * Math.sqrt((i % 11) / 11);
    const x = cx + Math.cos(a) * rad, z = cz + Math.sin(a) * rad;
    const g = groundAt(field, x, z);
    const s = 5 + 6 * Math.abs(noise2(i * 3.1, 7.7));
    b.box(x, g + s * 0.35, z, s * 1.6, s * 0.8, s, a * 1.7, mixc(stone, PAL.moss, 0.45 + 0.3 * Math.abs(noise2(i, 1))), shade, 0.7);
  }

  const mesh = new THREE.Mesh(b.geometry(), terrainMaterial(uniforms));
  mesh.name = "temple";
  mesh.userData.tris = b.idx.length / 3;
  return mesh;
}

/* ── boulders, logs and driftwood ───────────────────────────────────────── */
export function buildBoulders(field, layout, uniforms, count = 220) {
  const b = new Build();
  let placed = 0;
  for (let i = 0; placed < count && i < count * 24; i++) {
    const a = i * 2.3999632;
    const rad = 1180 * Math.sqrt(((i * 37) % 977) / 977);
    const x = Math.cos(a) * rad, z = Math.sin(a) * rad;
    const y = groundAt(field, x, z);
    if (y < 3 || y > 540) continue;
    const slope = sampleGrid(field, field.slope, x, z);
    if (slope < 0.25 && noise2(x * 0.01, z * 0.01) < 0.2) continue;
    placed++;
    const s = 4 + 9 * Math.abs(noise2(x * 0.02, z * 0.02));
    const shade = clamp(sampleGrid(field, field.shade, x, z), 0, 1);
    const wet = clamp(sampleGrid(field, field.moist, x, z), 0, 1);
    const col = mixc(mixc(PAL.rockDark, PAL.rockPale, 0.3 + 0.4 * Math.abs(noise2(i, 3))), PAL.moss, wet * 0.5);
    // three overlapping boxes read as a weathered boulder at this scale
    b.box(x, y + s * 0.3, z, s * 1.7, s * 1.0, s * 1.5, a, col, shade, 0.8);
    b.box(x + s * 0.3, y + s * 0.7, z - s * 0.2, s * 1.1, s * 0.7, s * 1.0, a + 1.1, col, shade, 0.85);
  }
  const mesh = new THREE.Mesh(b.geometry(), terrainMaterial(uniforms));
  mesh.name = "boulders";
  mesh.userData.tris = b.idx.length / 3;
  return mesh;
}
