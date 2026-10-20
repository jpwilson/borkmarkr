/* The landscape: a ridged heightfield, its vertex colouring, the water, the
   forests, and the draped overlays (region tints, outlines, trails) that sit
   on top of it. Everything samples one cached height grid, so a marker, a
   dashed trail and a tree all stand on exactly the surface that is drawn. */
import * as THREE from "three";
import { MAP } from "./atlas-layout.js";

/* ── Noise ──────────────────────────────────────────────────────────────── */
const fade = (t) => t * t * t * (t * (t * 6 - 15) + 10);

function gradient(ix, iz, seed) {
  let h = (seed ^ Math.imul(ix, 374761393) ^ Math.imul(iz, 668265263)) >>> 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177) >>> 0;
  const a = ((h ^ (h >>> 16)) >>> 0) * 1.4629180792671596e-9; // 2π / 2^32
  return [Math.cos(a), Math.sin(a)];
}

/* Classic gradient noise, -1..1. */
function perlin(x, z, seed) {
  const x0 = Math.floor(x), z0 = Math.floor(z);
  const fx = x - x0, fz = z - z0;
  const u = fade(fx), v = fade(fz);
  const dot = (ix, iz, dx, dz) => { const g = gradient(ix, iz, seed); return g[0] * dx + g[1] * dz; };
  const n00 = dot(x0, z0, fx, fz), n10 = dot(x0 + 1, z0, fx - 1, fz);
  const n01 = dot(x0, z0 + 1, fx, fz - 1), n11 = dot(x0 + 1, z0 + 1, fx - 1, fz - 1);
  return (n00 + (n10 - n00) * u) + ((n01 + (n11 - n01) * u) - (n00 + (n10 - n00) * u)) * v;
}

function fbm(x, z, seed, octaves = 5, lac = 2.03, gain = 0.5) {
  let sum = 0, amp = 1, norm = 0, f = 1;
  for (let o = 0; o < octaves; o++) {
    sum += perlin(x * f, z * f, seed + o * 7919) * amp;
    norm += amp; amp *= gain; f *= lac;
  }
  return sum / norm;
}

/* Ridged multifractal: the sharp crests and V-shaped valleys the reference
   terrain is made of. */
function ridged(x, z, seed, octaves = 8, lac = 2.0, gain = 0.58) {
  let sum = 0, amp = 1, norm = 0, f = 1, prev = 1;
  for (let o = 0; o < octaves; o++) {
    let n = 1 - Math.abs(perlin(x * f, z * f, seed + o * 104729) * 1.9);
    n = Math.max(0, n);
    n *= n;
    sum += n * amp * prev;
    prev = 0.55 + 0.45 * n;
    norm += amp; amp *= gain; f *= lac;
  }
  return sum / norm;
}

/* ── Height field ───────────────────────────────────────────────────────── */
export const GRID = 520;                 // cells across the terrain plate
const CELL = (MAP.PLATE * 2) / GRID;
const F = 1 / 1150;                      // first ridge octave ≈ 1150 m across

/* Ridged noise sits around 0.45 with little contrast; stretching it is what
   turns soft hills into crests and V-shaped valleys. */
const crest = (v) => Math.min(1.35, Math.max(-0.4, (v - 0.33) * 2.25));

export function buildHeightField(layout) {
  const n = GRID + 1;
  const data = new Float32Array(n * n);
  const regions = layout.regions;

  for (let j = 0; j < n; j++) {
    const z = -MAP.PLATE + j * CELL;
    for (let i = 0; i < n; i++) {
      const x = -MAP.PLATE + i * CELL;
      // warp the lattice so crests wander instead of running in straight lines
      const wx = x + fbm(x * F * 0.7, z * F * 0.7, 311, 3) * 380 + fbm(x * F * 3.4, z * F * 3.4, 1811, 2) * 48;
      const wz = z + fbm(x * F * 0.7 + 40, z * F * 0.7 - 40, 733, 3) * 380 + fbm(x * F * 3.4 + 9, z * F * 3.4 + 3, 1933, 2) * 48;
      const main = crest(ridged(wx * F, wz * F, 1337, 7, 2.0, 0.43));
      const cross = crest(ridged(wz * F * 1.81 + 11, wx * F * 1.81 - 7, 7717, 4, 2.0, 0.43));
      // smooth small-scale bumps instead of another ridged octave, which at
      // this grid spacing would alias into a field of identical pyramids
      const grain = fbm(x * F * 8.5, z * F * 8.5, 4409, 3);
      const broad = fbm(x * F * 0.42, z * F * 0.42, 5521, 4);

      // every region is a massif: high ground with the ridges still running
      // over it, so topics read as named ranges rather than separate pimples
      let lift = 0, mask = 0;
      for (const r of regions) {
        const d = Math.hypot(x - r.x, z - r.z) / (r.rMax * 1.3);
        if (d > 1.5) continue;
        const f = Math.exp(-d * d * 1.9);
        lift += f * (46 + 54 * (r.r / MAP.R_MAX));
        mask = Math.max(mask, f);
      }

      const amp = 126 + 76 * mask + 52 * broad;
      let h = 18 + broad * 70 + lift + main * amp + cross * amp * 0.42 + grain * 15;
      // ease the plateau tops so districts have ground to stand on
      if (mask > 0.5) {
        const k = (mask - 0.5) * 1.1;
        h = h * (1 - k) + (lift + 86 + broad * 34) * k;
      }

      // coast: a ragged shoreline well out past the atlas, then open water
      const rad = Math.hypot(x, z) + fbm(x * F * 1.1, z * F * 1.1, 9173, 3) * 190;
      if (rad > MAP.SHORE) {
        const t = Math.min(1, (rad - MAP.SHORE) / 330);
        h = h * (1 - t * t) + (MAP.WATER - 48) * (t * t);
      }
      data[j * n + i] = h;
    }
  }

  const sample = (x, z) => {
    const fx = (x + MAP.PLATE) / CELL, fz = (z + MAP.PLATE) / CELL;
    const i = Math.min(n - 2, Math.max(0, Math.floor(fx))), j = Math.min(n - 2, Math.max(0, Math.floor(fz)));
    const tx = Math.min(1, Math.max(0, fx - i)), tz = Math.min(1, Math.max(0, fz - j));
    const a = data[j * n + i], b = data[j * n + i + 1], c = data[(j + 1) * n + i], d = data[(j + 1) * n + i + 1];
    return (a + (b - a) * tx) + ((c + (d - c) * tx) - (a + (b - a) * tx)) * tz;
  };
  const slope = (x, z) => {
    const e = CELL;
    const dx = sample(x + e, z) - sample(x - e, z);
    const dz = sample(x, z + e) - sample(x, z - e);
    return Math.hypot(dx, dz) / (2 * e);
  };
  return { data, n, cell: CELL, sample, slope };
}

/* ── Terrain mesh ───────────────────────────────────────────────────────── */
const C = {
  shallow: new THREE.Color("#93a09f"),
  beach: new THREE.Color("#ded0b2"),
  sand: new THREE.Color("#d8c8a4"),
  meadow: new THREE.Color("#9aa275"),
  sage: new THREE.Color("#73855a"),
  ochre: new THREE.Color("#c7ad80"),
  tan: new THREE.Color("#bca684"),
  rock: new THREE.Color("#8f877a"),
  cliff: new THREE.Color("#79736a"),
  scree: new THREE.Color("#c3bba9"),
};

/* Height picks the band, slope pulls it towards bare rock, and a mottling
   noise keeps a band from reading as one flat wash. */
function terrainColor(h, s, m, out) {
  let c;
  if (h < MAP.WATER + 4) c = C.shallow.clone().lerp(C.beach, Math.max(0, (h - MAP.WATER + 16) / 22));
  else if (h < 30) c = C.beach.clone().lerp(C.meadow, Math.min(1, Math.max(0, (h - MAP.WATER - 4) / 40)));
  else if (h < 92) c = C.meadow.clone().lerp(C.ochre, Math.min(1, (h - 30) / 62));
  else if (h < 160) c = C.ochre.clone().lerp(C.tan, Math.min(1, (h - 92) / 68));
  else if (h < 215) c = C.tan.clone().lerp(C.rock, Math.min(1, (h - 160) / 55));
  else c = C.rock.clone().lerp(C.scree, Math.min(1, (h - 215) / 80));
  if (s > 0.45) c.lerp(C.cliff, Math.min(0.85, (s - 0.45) * 1.15));
  if (h > 4 && h < 130) c.lerp(C.sage, Math.max(0, m - 0.55) * 0.9 * (1 - Math.min(1, s)));
  const k = 0.9 + 0.2 * m;
  out.setRGB(c.r * k, c.g * k, c.b * k);
  return out;
}

export function buildTerrain(field) {
  const n = field.n;
  const geo = new THREE.PlaneGeometry(MAP.PLATE * 2, MAP.PLATE * 2, GRID, GRID);
  geo.rotateX(-Math.PI / 2);
  const pos = geo.attributes.position;
  const colors = new Float32Array(pos.count * 3);
  const tmp = new THREE.Color();
  for (let j = 0; j < n; j++) {
    for (let i = 0; i < n; i++) {
      const k = j * n + i;
      const h = field.data[k];
      pos.setY(k, h);
      const x = -MAP.PLATE + i * field.cell, z = -MAP.PLATE + j * field.cell;
      const mottle = 0.5 + 0.5 * fbm(x * F * 5.2, z * F * 5.2, 4211, 3);
      terrainColor(h, field.slope(x, z), mottle, tmp);
      colors[k * 3] = tmp.r; colors[k * 3 + 1] = tmp.g; colors[k * 3 + 2] = tmp.b;
    }
  }
  geo.setAttribute("color", new THREE.BufferAttribute(colors, 3));
  geo.computeVertexNormals();
  const mat = new THREE.MeshStandardMaterial({ vertexColors: true, roughness: 0.97, metalness: 0, flatShading: true });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.receiveShadow = true;
  mesh.castShadow = true;
  mesh.name = "terrain";
  return mesh;
}

export function buildWater() {
  const geo = new THREE.PlaneGeometry(26000, 26000, 1, 1).rotateX(-Math.PI / 2);
  const mat = new THREE.MeshStandardMaterial({ color: "#879aa3", roughness: 0.35, metalness: 0.08 });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.position.y = MAP.WATER;
  mesh.receiveShadow = false;
  mesh.name = "water";
  return mesh;
}

/* A pale gradient dome: cool at the zenith, warm haze at the horizon. No sun
   disc, no bloom — the sky is only here to give the ridges something to fade
   into. */
export function buildSky() {
  const geo = new THREE.SphereGeometry(11000, 32, 20);
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false, fog: false,
    uniforms: {
      top: { value: new THREE.Color("#c0ccd2") },
      mid: { value: new THREE.Color("#ccd3d2") },
      bottom: { value: new THREE.Color("#d6d8d1") },
    },
    vertexShader: "varying float vH; void main(){ vec4 w = modelMatrix * vec4(position,1.0); vH = normalize(w.xyz).y; gl_Position = projectionMatrix * viewMatrix * w; }",
    fragmentShader: `varying float vH; uniform vec3 top; uniform vec3 mid; uniform vec3 bottom;
      void main(){ float h = clamp(vH, -1.0, 1.0);
        vec3 c = h > 0.0 ? mix(mid, top, pow(h, 0.55)) : mix(mid, bottom, pow(-h, 1.4));
        gl_FragColor = vec4(c, 1.0); }`,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = "sky";
  mesh.renderOrder = -1;
  return mesh;
}

/* ── Forests and rocks ──────────────────────────────────────────────────── */
function coneGeometry(r, h, seg) {
  const g = new THREE.ConeGeometry(r, h, seg, 2);
  g.translate(0, h / 2, 0);
  return g;
}

/* Thousands of conifers on the slopes that would actually hold trees: above
   the beach, below the scree line, off the cliffs, and clumped by a density
   noise so the forest has edges and clearings. */
/* A deterministic 0..1 stream — the forests must look identical on every
   run so captured frames match. */
function rng(seed) {
  let t = (seed | 0) + 0x6d2b79f5;
  return () => {
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/* Tens of thousands of conifers on the ground that would actually hold them:
   above the beach, below the scree line, off the cliffs, and clumped by a
   density noise so the forest has edges, clearings and treelines. */
export function scatterTrees(field, { count = 30000, seed = 17 } = {}) {
  const geo = coneGeometry(4.4, 16, 5);
  const mat = new THREE.MeshStandardMaterial({ roughness: 0.95, metalness: 0, flatShading: true });
  const dark = new THREE.Color("#2b3b28"), mid = new THREE.Color("#44563a"), dusty = new THREE.Color("#6d7a53");
  const mesh = new THREE.InstancedMesh(geo, mat, count);
  mesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(count * 3), 3);
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
  const axis = new THREE.Vector3(0, 1, 0);
  const col = new THREE.Color();
  const r = rng(seed);
  // Trees only inside the band the camera ever looks at; past this the haze
  // has taken over anyway, and the instances would be wasted.
  const reach = 1780;
  let placed = 0, tries = 0;
  while (placed < count && tries < count * 40) {
    tries++;
    const x = (r() * 2 - 1) * reach, z = (r() * 2 - 1) * reach;
    const h = field.sample(x, z);
    if (h < 4 || h > 262) continue;
    const sl = field.slope(x, z);
    if (sl > 1.35) continue;
    const d1 = 0.5 + 0.5 * fbm(x * F * 2.6, z * F * 2.6, 8111, 4);
    const d2 = 0.5 + 0.5 * fbm(x * F * 7.5, z * F * 7.5, 2287, 3);
    const density = Math.pow(Math.max(0, d1 * 1.25 - 0.22), 1.5) * (0.6 + 0.7 * d2);
    const altitude = h < 22 ? 0.55 : h > 236 ? 0.3 : h > 190 ? 0.62 : h > 150 ? 0.85 : 1;
    const exposure = 1 - Math.min(0.55, Math.max(0, (sl - 0.75)) * 0.7);
    if (density * altitude * exposure < 0.08 + 0.2 * r()) continue;
    const scale = (0.6 + 0.85 * r()) * (h > 140 ? 0.74 : 1);
    const lean = 0.8 + 0.35 * r();
    p.set(x, h - 1.4, z);
    s.set(scale * lean, scale * (0.85 + 0.5 * r()), scale * lean);
    q.setFromAxisAngle(axis, r() * Math.PI * 2);
    m.compose(p, q, s);
    mesh.setMatrixAt(placed, m);
    const t = r();
    col.copy(dark).lerp(t > 0.8 ? dusty : mid, t * (h > 110 ? 0.95 : 0.6));
    mesh.instanceColor.setXYZ(placed, col.r, col.g, col.b);
    placed++;
  }
  mesh.count = placed;
  mesh.instanceMatrix.needsUpdate = true;
  mesh.instanceColor.needsUpdate = true;
  mesh.castShadow = true;
  mesh.receiveShadow = false;
  mesh.name = "forest";
  mesh.frustumCulled = false;
  return mesh;
}

export function scatterRocks(field, { count = 2600, seed = 91 } = {}) {
  const geo = new THREE.IcosahedronGeometry(4.2, 0);
  const mat = new THREE.MeshStandardMaterial({ color: "#8f877a", roughness: 1, metalness: 0, flatShading: true });
  const mesh = new THREE.InstancedMesh(geo, mat, count);
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3();
  const r = rng(seed);
  const reach = MAP.PLATE - 40;
  let placed = 0, tries = 0;
  while (placed < count && tries < count * 40) {
    tries++;
    const x = (r() * 2 - 1) * reach, z = (r() * 2 - 1) * reach;
    const h = field.sample(x, z);
    if (h < 10) continue;
    const sl = field.slope(x, z);
    if (sl < 0.55 && h < 150) continue;
    const scale = 0.35 + 1.5 * r();
    p.set(x, h - 1.5, z);
    s.set(scale * 1.4, scale * 0.75, scale);
    q.setFromEuler(new THREE.Euler(r() * 3, r() * 3, r() * 3));
    m.compose(p, q, s);
    mesh.setMatrixAt(placed++, m);
  }
  mesh.count = placed;
  mesh.instanceMatrix.needsUpdate = true;
  mesh.castShadow = true;
  mesh.name = "rocks";
  mesh.frustumCulled = false;
  return mesh;
}

/* ── Draped overlays ────────────────────────────────────────────────────── */

/* A translucent tint that follows the ground inside a wobbly boundary. Built
   on a polar grid so it fits the outline exactly without any clipping. */
export function drapeDisc(cx, cz, boundaryPts, field, { lift = 1.4, rings = 16 } = {}) {
  const spokes = boundaryPts.length;
  const verts = [], idx = [];
  for (let r = 0; r <= rings; r++) {
    const t = r / rings;
    for (let s = 0; s < spokes; s++) {
      const [bx, bz] = boundaryPts[s];
      const x = cx + (bx - cx) * t, z = cz + (bz - cz) * t;
      verts.push(x, field.sample(x, z) + lift, z);
    }
  }
  for (let r = 0; r < rings; r++) {
    for (let s = 0; s < spokes; s++) {
      const a = r * spokes + s, b = r * spokes + ((s + 1) % spokes);
      const c = (r + 1) * spokes + s, d = (r + 1) * spokes + ((s + 1) % spokes);
      idx.push(a, c, b, b, c, d);
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.Float32BufferAttribute(verts, 3));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

/* A constant-width ribbon laid on the ground: the perimeter outlines, the
   district edges and the reading trail are all this. `dash` drops alternate
   chunks so a dashed line stays dashed at any camera distance. */
export function ribbon(points, field, { width = 2.6, lift = 2.0, closed = false, dash = 0, gap = 0 } = {}) {
  const pts = closed ? [...points, points[0]] : points;
  if (pts.length < 2) return new THREE.BufferGeometry();
  const verts = [], idx = [];
  let run = 0, quad = 0;
  const half = width / 2;
  for (let i = 0; i < pts.length - 1; i++) {
    const [x0, z0] = pts[i], [x1, z1] = pts[i + 1];
    const dx = x1 - x0, dz = z1 - z0;
    const len = Math.hypot(dx, dz) || 1e-6;
    const nx = -dz / len, nz = dx / len;
    const steps = Math.max(1, Math.ceil(len / 5));
    for (let s = 0; s < steps; s++) {
      const t0 = s / steps, t1 = (s + 1) / steps;
      const seg = len / steps;
      if (dash > 0 && (Math.floor(run / dash) % (1 + Math.max(1, Math.round(gap / dash)))) !== 0) { run += seg; continue; }
      const ax = x0 + dx * t0, az = z0 + dz * t0;
      const bx = x0 + dx * t1, bz = z0 + dz * t1;
      // Height comes from the centre line, so the ribbon stays a flat band
      // across its width and never tears apart on a steep slope.
      const ay = field.sample(ax, az) + lift, by = field.sample(bx, bz) + lift;
      const base = quad * 4;
      verts.push(
        ax + nx * half, ay, az + nz * half,
        ax - nx * half, ay, az - nz * half,
        bx + nx * half, by, bz + nz * half,
        bx - nx * half, by, bz - nz * half,
      );
      idx.push(base, base + 2, base + 1, base + 1, base + 2, base + 3);
      quad++;
      run += seg;
    }
  }
  const geo = new THREE.BufferGeometry();
  geo.setAttribute("position", new THREE.Float32BufferAttribute(verts, 3));
  geo.setIndex(idx);
  geo.computeVertexNormals();
  return geo;
}

export { fbm, ridged, perlin };
