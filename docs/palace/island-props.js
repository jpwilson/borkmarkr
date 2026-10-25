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
  vert(x, y, z, nx, ny, nz, c, shade, ao = 1, moist = 0, glow = 0) {
    this.pos.push(x, y, z); this.nrm.push(nx, ny, nz);
    this.col.push(c[0], c[1], c[2]); this.lit.push(shade, ao, moist, glow);
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
      // wound so the outward face is the front face
      this.quad(i0, i3, i2, i1);
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
      this.quad(base[i], top[i], top[j], base[j]);
    }
    // cap
    const capC = this.vert(...place(0, h, 0), 0, 1, 0, [col[0] * 1.14, col[1] * 1.14, col[2] * 1.14], shade, ao);
    const cap = [];
    for (let i = 0; i < seg; i++) {
      const a = (i / seg) * Math.PI * 2;
      cap.push(this.vert(...place(Math.cos(a) * r1, h, Math.sin(a) * r1), 0, 1, 0, [col[0] * 1.14, col[1] * 1.14, col[2] * 1.14], shade, ao));
    }
    for (let i = 0; i < seg; i++) this.tri(capC, cap[(i + 1) % seg], cap[i]);
  }
  geometry() {
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(this.pos, 3));
    g.setAttribute("normal", new THREE.Float32BufferAttribute(this.nrm, 3));
    g.setAttribute("color", new THREE.Float32BufferAttribute(this.col, 3));
    g.setAttribute("lit", new THREE.Float32BufferAttribute(this.lit, 4));
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
  const RINGS = 34, SEG = 30;
  const rows = [];
  const shadeBase = field ? clamp(sampleGrid(field, field.shade, cx, cz) * 0.5 + 0.5, 0, 1) : 0.95;
  // each tower has its own plan shape and lean, so a cluster never repeats
  const ex = 1 + 0.42 * noise2(seed, 1.3), ez = 1 - 0.36 * noise2(seed + 4.4, 2.9);
  const twist = noise2(seed * 2.2, 0.7) * 0.8;
  const leanX = noise2(seed, 7.7) * 0.085, leanZ = noise2(seed + 2, 5.1) * 0.085;
  // limestone stands almost vertical: the taper is a few per cent, not a cone
  const taper = 0.015 + 0.085 * Math.abs(noise2(seed * 1.7, 3.3));
  // and it does not round off at the top — it breaks into spires
  const breakAt = 0.62 + 0.10 * Math.abs(noise2(seed + 9, 1.1));
  /* The summit is two to four separate pinnacles, not a cap. `spireOf` is a
     few sharp lobes round the compass plus noise, so each tower has its own
     count and spacing: where it peaks the rock keeps its width and runs on
     up, and between the peaks it falls away into notches. A single apex over
     a raised rim is what made these read as sawn-off stumps. */
  const lobes = 2 + (Math.abs(noise2(seed + 3.3, 0.9)) * 3.4 | 0);
  const phase = noise2(seed, 2.2) * Math.PI * 2;
  const spireOf = (a) => clamp(
    0.52 * Math.pow(0.5 + 0.5 * Math.cos(a * lobes + phase), 2.4)
    + 0.40 * Math.pow(0.5 + 0.5 * Math.cos(a * (lobes + 2) - phase * 1.7 + seed), 3.2)
    + 0.34 * clamp(0.5 + 0.9 * noise2(Math.cos(a) * 2.2 + seed * 3.1, Math.sin(a) * 2.2 - seed), 0, 1)
    - 0.06, 0, 1);
  for (let r = 0; r <= RINGS; r++) {
    const t = r / RINGS;
    // sheer the whole way, with the sea notching a visible undercut in the
    // bottom few metres — the overhang every Ha Long photograph has
    let prof = 1 - taper * t;
    /* The undercut. A limestone tower standing in the sea is eaten away at
       the waterline into a notch you can put a boat under, and the overhang
       above it is the single silhouette cue that says karst rather than
       column. Deeper than before, and with a flare below it where the
       collapsed rock piles up. */
    prof *= 1 - 0.30 * Math.exp(-Math.pow((t - 0.05) / 0.045, 2));
    prof *= 1 + 0.12 * Math.exp(-Math.pow(t / 0.028, 2));
    const ledgeWave = Math.sin(t * 23 + seed * 3.1);
    const ledge = 1 + 0.045 * ledgeWave + 0.028 * Math.sin(t * 8.7 - seed);
    const row = [];
    const y = baseY + t * H;
    for (let i = 0; i < SEG; i++) {
      const a = (i / SEG) * Math.PI * 2 + twist * t;
      // deep vertical fissures, constant up the tower, plus finer flutes
      const fl = Math.sin(a * 7 + seed * 2.1);
      // two sets of fissures at different spacings: one deep chimney every
      // quarter turn, and a finer comb of flutes between them
      const fissure = Math.pow(Math.abs(Math.sin(a * 4.5 + seed * 5.3)), 7) * 0.9
                    + Math.pow(Math.abs(Math.sin(a * 9.0 - seed * 2.7)), 11) * 0.6;
      const fn = noise2(Math.cos(a) * 2.6 + seed, Math.sin(a) * 2.6 + t * 0.7);
      // above the break the rock between the spires is eaten away, so the
      // plan narrows to a handful of fingers instead of staying a disc
      const up = t > breakAt ? (t - breakAt) / (1 - breakAt) : 0;
      const sp = spireOf(a);
      // the notches cut in, but not to nothing: pared to a needle a tower
      // stops being limestone and starts being a tooth
      const crag = up > 0 ? Math.pow(up, 1.25) * (0.95 * sp - 0.50) : 0;
      const flute = 1 + 0.15 * fl + 0.12 * fn + 0.07 * Math.sin(a * 19 + t * 2.0) - fissure * 0.22 + crag;
      const rad = R * Math.max(0.02, prof) * ledge * Math.max(0.05, flute);
      const x = cx + Math.cos(a) * rad * ex + leanX * t * H;
      const z = cz + Math.sin(a) * rad * ez + leanZ * t * H;
      // and each finger runs on past the nominal top to its own height, so
      // the silhouette is a comb of pinnacles with deep notches between them
      const yy = y + (up > 0 ? Math.pow(up, 1.2) * H * 0.26 * (sp - 0.30) : 0);
      // pale dry limestone, with long dark rain streaks running straight down
      const streak = clamp(0.5 + 0.85 * noise2(a * 6.3 + seed, t * 0.45), 0, 1);
      let c = mixc(PAL.limestone, PAL.rockPale, 0.08 + 0.3 * noise2(a * 2.3, t * 1.2));
      // the long dark rain streaks that run straight down a karst face
      c = mixc(c, PAL.rockWet, Math.pow(clamp((streak - 0.50) * 3.0, 0, 1), 1.2) * 0.62);
      c = mixc(c, PAL.rockDark, clamp(fissure, 0, 1) * 0.46);
      // and the foot of the tower is wet, dark and black with algae
      c = mixc(c, PAL.rockDark, Math.pow(1 - clamp(t / 0.09, 0, 1), 1.4) * 0.55);
      // vegetation drapes over the crown and catches on the wider ledges,
      // thinning to bare rock on the sheer middle of the tower
      const shelf = clamp(0.5 + 0.5 * ledgeWave, 0, 1);
      const moss = clamp(1.45 * Math.pow(t, 2.4) + 0.42 * shelf * sstep(0.1, 0.55, t)
        + 0.62 * noise2(a * 1.9 - seed, t * 2.6) - 0.24, 0, 1);
      c = mixc(c, moss > 0.58 ? PAL.jungleDeep : PAL.moss, clamp((moss - 0.30) * 1.9, 0, 0.9));
      // the grooves are drawn with shading, not geometry: cheap and legible
      const groove = clamp(0.5 + 0.5 * (fl * 0.6 + fn * 0.5) + 0.12 * Math.sin(a * 19 + t * 2.0)
        + 0.14 * ledgeWave - fissure * 0.5, 0.42, 1.25);
      const upTone = (0.92 + 0.26 * t) * groove;
      row.push(b.vert(x, yy, z, Math.cos(a) * ex, 0.07 + t * 0.2, Math.sin(a) * ez,
        [c[0] * upTone, c[1] * upTone, c[2] * upTone], shadeBase * (0.58 + 0.42 * t), 0.45 + 0.55 * t, 0.2));
    }
    rows.push(row);
  }
  for (let r = 0; r < RINGS; r++) for (let i = 0; i < SEG; i++) {
    const j = (i + 1) % SEG;
    b.quad(rows[r][i], rows[r + 1][i], rows[r + 1][j], rows[r][j]);
  }
  /* Close the fingers off against a hub sunk below the lowest of them: fan
     to a single high apex and the notches fill back in, which is the flat cap
     all over again. Sunk, the cap is invisible and the comb stays a comb. */
  let lowest = Infinity;
  for (let i = 0; i < SEG; i++) lowest = Math.min(lowest, b.pos[rows[RINGS][i] * 3 + 1]);
  const topC = b.vert(cx + leanX * H, lowest - H * 0.02, cz + leanZ * H, 0, 1, 0,
    mixc(PAL.limestone, PAL.moss, 0.6), shadeBase, 1, 0.3);
  for (let i = 0; i < SEG; i++) b.tri(topC, rows[RINGS][(i + 1) % SEG], rows[RINGS][i]);
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
  const stone = mixc(PAL.limestone, PAL.rockPale, 0.12);
  const mossy = mixc(stone, PAL.moss, 0.42);
  const yaw = 0.42;

  /* Five tiers instead of four and half as wide again, because from the
     overview the old one was a pale smudge on a hillside. At this size it
     is the thing that tells you which zone you are looking at. */
  const tiers = 5;
  const STEP = 26;
  for (let i = 0; i < tiers; i++) {
    const w = 238 - i * 38, hh = 26 - i * 1.6;
    const y = base + i * STEP + hh / 2 - 2;
    const c = mixc(stone, mossy, 0.22 + 0.15 * i);
    b.box(cx, y, cz, w, hh, w, yaw, c, shade, 0.85 - i * 0.05);
    // a lip on each tier, so the steps read as masonry and not as a cake
    b.box(cx, y + hh / 2 + 1.6, cz, w + 9, 3.6, w + 9, yaw, mixc(c, PAL.rockDark, 0.3), shade, 0.7 - i * 0.04);
  }
  // shrine on top, and a broken lintel over its door
  const topY = base + tiers * STEP;
  b.box(cx, topY + 13, cz, 54, 30, 54, yaw, mixc(stone, mossy, 0.5), shade, 0.8);
  b.box(cx, topY + 30, cz, 62, 7, 62, yaw, mixc(stone, PAL.moss, 0.62), shade, 0.75);
  b.box(cx, topY + 40, cz, 20, 13, 20, yaw + 0.3, mixc(stone, PAL.moss, 0.5), shade, 0.8);

  // the great stair down the south face, wide and deep
  const sa = yaw;
  for (let i = 0; i < 26; i++) {
    const t = i / 25;
    const w = 46;
    const d = 126 - t * 64;
    const y = base + t * (tiers * STEP) + 1;
    b.box(cx + Math.sin(sa) * d, y, cz + Math.cos(sa) * d, w, 4.4, 9, yaw, mixc(stone, mossy, 0.3 + t * 0.3), shade, 0.8);
  }
  // balustrades either side of the stair
  for (const side of [-1, 1]) {
    for (let i = 0; i < 9; i++) {
      const t = i / 8;
      const d = 126 - t * 64;
      const y = base + t * (tiers * STEP) + 7;
      b.box(cx + Math.sin(sa) * d + Math.cos(sa) * side * 27, y, cz + Math.cos(sa) * d - Math.sin(sa) * side * 27,
        9, 11, 11, yaw, mixc(stone, PAL.moss, 0.4 + 0.3 * t), shade, 0.72);
    }
  }

  // columns, mostly broken, around a cleared plaza
  for (let i = 0; i < 20; i++) {
    const a = (i / 20) * Math.PI * 2 + 0.2;
    const rad = 168 + 22 * noise2(i * 1.3, 2.1);
    const x = cx + Math.cos(a) * rad, z = cz + Math.sin(a) * rad;
    const g = groundAt(field, x, z);
    const broken = noise2(i * 2.7, 5.5);
    const h = broken > 0.1 ? 34 + 16 * broken : 9 + 16 * Math.abs(broken);
    b.cylinder(x, g - 1, z, 5.4, 4.7, h, 9, mixc(stone, mossy, 0.3 + 0.4 * Math.abs(broken)), shade * 0.95);
    if (broken > 0.3) b.box(x, g + h + 2, z, 14, 4, 14, a, mixc(stone, mossy, 0.5), shade, 0.8);
    else {
      // a toppled drum lying in the grass
      const fx = x + Math.cos(a + 1.1) * 17, fz = z + Math.sin(a + 1.1) * 17;
      b.cylinder(fx, groundAt(field, fx, fz) + 3.6, fz, 5.1, 4.8, 17, 8, mixc(stone, PAL.moss, 0.58), shade, Math.PI / 2, a + 1.1);
    }
  }
  // fallen blocks, tumbled down the slope below the plaza
  for (let i = 0; i < 34; i++) {
    const a = i * 2.3999632;
    const rad = 86 + 150 * Math.sqrt((i % 11) / 11);
    const x = cx + Math.cos(a) * rad, z = cz + Math.sin(a) * rad;
    const g = groundAt(field, x, z);
    const s = 6 + 8 * Math.abs(noise2(i * 3.1, 7.7));
    b.box(x, g + s * 0.35, z, s * 1.7, s * 0.85, s, a * 1.7, mixc(stone, PAL.moss, 0.45 + 0.3 * Math.abs(noise2(i, 1))), shade, 0.7);
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
