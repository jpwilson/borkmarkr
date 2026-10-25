/* island-flora.js — the jungle.

   Tens of thousands of instanced clumps: lumpy broadleaf canopy in clustered
   masses, emergent trees breaking the canopy line, palms on the sand,
   mangroves in the marsh, dry scrub on the ash and the summits, and crowns on
   the limestone towers. Every instance carries the terrain's baked sun
   visibility, so a ridge shadow falls across the trees as well as the ground.

   Instance order is shuffled once, deterministically, so dropping quality
   thins the forest evenly across the island instead of deleting a stripe. */
import * as THREE from "three";
import { sampleGrid, groundAt, PAL, ATMOS_PARS } from "./island-terrain.js";
import { clamp, mix, sstep, noise2, fbm, coastField, riverSample, zoneField, tintOf, ISLAND_R, CAMP_CLEAR, CAMP_FADE } from "./island-layout.js";

const mixc = (a, b, t) => [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];

/* ── one lobe of leaves ─────────────────────────────────────────────────── */
/* `lobes` is what stops a crown reading as a toy: instead of one ball, the
   radius picks up a handful of smooth bulges pointing in fixed directions,
   so the silhouette breaks into overlapping masses the way a broadleaf crown
   does. The result is returned as raw arrays, not a geometry, because a
   crown is several of these stacked — see clumpGeometry. */
function lobeArrays({ bands = 3, segs = 8, squash = 0.74, dent = 0.3, seed = 1, pinch = 0.55, lobes = 3 } = {}) {
  const pos = [], nrm = [], idx = [];
  const rows = [];
  const lobeDirs = [];
  for (let k = 0; k < lobes; k++) {
    const t = (k + 0.5) / lobes;
    const phi = Math.acos(1 - 0.92 * t);
    const th = k * 2.3999632 + seed * 2.1;
    lobeDirs.push({
      x: Math.sin(phi) * Math.cos(th), y: Math.cos(phi), z: Math.sin(phi) * Math.sin(th),
      amp: 0.33 + 0.38 * Math.abs(noise2(k * 1.7 + seed, 3.3)),
      w: 0.62 + 0.34 * Math.abs(noise2(k * 2.9 - seed, 5.1)),
    });
  }
  for (let b = 0; b <= bands + 1; b++) {
    const phi = (b / (bands + 1)) * Math.PI;
    const row = [];
    for (let sgi = 0; sgi < segs; sgi++) {
      const th = (sgi / segs) * Math.PI * 2;
      const sx = Math.sin(phi) * Math.cos(th), sy = Math.cos(phi), sz = Math.sin(phi) * Math.sin(th);
      let r = 1 + dent * (noise2(sx * 1.15 + seed * 3.1, sz * 1.15 + sy * 1.15)
                        + 0.5 * noise2(sx * 2.6 - seed, sz * 2.6 + sy * 2.2));
      for (const L of lobeDirs) {
        const d = sx * L.x + sy * L.y + sz * L.z;
        r += Math.exp(-Math.pow((1 - d) / L.w, 2) * 2.4) * L.amp * 0.45;
      }
      r *= 1 - pinch * Math.pow(clamp((phi - Math.PI * 0.55) / (Math.PI * 0.45), 0, 1), 1.6);
      const x = Math.sin(phi) * Math.cos(th) * r;
      const z = Math.sin(phi) * Math.sin(th) * r;
      const y = Math.cos(phi) * r * squash;
      const l = Math.hypot(x, y, z) || 1;
      row.push(pos.length / 3);
      pos.push(x, y, z); nrm.push(x / l, y / l, z / l);
    }
    rows.push(row);
  }
  for (let b = 0; b < rows.length - 1; b++) for (let sgi = 0; sgi < segs; sgi++) {
    const a = rows[b][sgi], c = rows[b][(sgi + 1) % segs];
    const d = rows[b + 1][sgi], e = rows[b + 1][(sgi + 1) % segs];
    idx.push(a, c, d, c, e, d);
  }
  return { pos, nrm, idx };
}

/* ── a crown: several lobes, stacked and offset ─────────────────────────── */
/* A broadleaf seen from above is not a ball. It is three or four masses of
   leaves at different heights, with sunlit tops and black gaps between them,
   and that difference is the whole reason the old canopy read as a tray of
   broccoli. Each crown here is a small tower of lobes: one dominant mass
   near the top, two or three smaller ones pushed out and down around it,
   with the colour keyed to the final height in the crown rather than to the
   lobe's own, so a low lobe is genuinely in the shade of the one above it. */
function clumpGeometry(seed, { count = 3, spread = 0.52, drop = 0.34, bands = 3, segs = 8, trunk = 0 } = {}) {
  const P = [], N = [], C = [], I = [];
  const r = rng(((seed * 7919) | 0) >>> 0);
  let maxY = 0.001, minY = 1e9;
  const parts = [];
  for (let k = 0; k < count; k++) {
    const first = k === 0;
    const a = k * 2.3999632 + seed;
    const rad = first ? spread * 0.18 * r() : spread * (0.52 + 0.62 * r());
    const sc = first ? 1 : 0.46 + 0.42 * r();
    const yOff = first ? 0.30 + 0.12 * r() : -drop * (0.25 + 0.95 * r());
    const lobe = lobeArrays({
      bands, segs, squash: 0.62 + 0.26 * r(), dent: 0.26 + 0.20 * r(),
      seed: seed * 1.7 + k * 3.3, pinch: 0.18 + 0.26 * r(), lobes: 3 + ((r() * 3) | 0),
    });
    const sx = sc * (0.82 + 0.4 * r()), sz = sc * (0.82 + 0.4 * r()), sy = sc * (0.72 + 0.4 * r());
    const ox = Math.cos(a) * rad, oz = Math.sin(a) * rad;
    const base = P.length / 3;
    for (let i = 0; i < lobe.pos.length; i += 3) {
      const x = lobe.pos[i] * sx + ox;
      const y = lobe.pos[i + 1] * sy + yOff;
      const z = lobe.pos[i + 2] * sz + oz;
      P.push(x, y, z);
      /* A squashed sphere's normals are not the sphere's normals: they go
         through the inverse scale, not the scale. Skipping this is what made
         every crown shade like a flat plate with a hard rim — the lobes were
         lit as if they were still round. */
      let nx = lobe.nrm[i] / sx, ny = lobe.nrm[i + 1] / sy, nz = lobe.nrm[i + 2] / sz;
      const nl = Math.hypot(nx, ny, nz) || 1;
      N.push(nx / nl, ny / nl, nz / nl);
      if (y > maxY) maxY = y;
      if (y < minY) minY = y;
    }
    for (const t of lobe.idx) I.push(base + t);
    parts.push(base);
  }
  // a short trunk, for the variants that are meant to be read from the ground
  if (trunk > 0) {
    const SEG = 5, base = P.length / 3;
    const bottom = minY - trunk;
    for (let ring = 0; ring < 2; ring++) {
      const y = ring === 0 ? bottom : minY + 0.12;
      const rr = ring === 0 ? 0.085 : 0.05;
      for (let i = 0; i < SEG; i++) {
        const a = (i / SEG) * Math.PI * 2;
        P.push(Math.cos(a) * rr, y, Math.sin(a) * rr);
        N.push(Math.cos(a), 0.1, Math.sin(a));
      }
    }
    for (let i = 0; i < SEG; i++) {
      const j = (i + 1) % SEG;
      I.push(base + i, base + j, base + SEG + i, base + j, base + SEG + j, base + SEG + i);
    }
    minY = bottom;
  }
  // shift so the crown's underside sits at y = 0, then colour by height
  const span = Math.max(0.3, maxY - minY);
  for (let i = 0; i < P.length; i += 3) {
    P[i + 1] -= minY;
    const up = clamp((P[i + 1]) / span, 0, 1);
    // outward-facing vertices catch more light than ones buried in the clump
    const out = clamp(Math.hypot(P[i], P[i + 2]) / (spread + 1.0), 0, 1);
    const lit = Math.pow(up, 1.5) * (0.62 + 0.38 * out);
    const c = mixc(mixc([0.005, 0.011, 0.006], [0.055, 0.115, 0.022], lit), [0.165, 0.215, 0.040], Math.pow(up, 4.5) * 0.58);
    C.push(c[0], c[1], c[2]);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(P, 3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(N, 3));
  g.setAttribute("color", new THREE.Float32BufferAttribute(C, 3));
  g.setIndex(I);
  g.userData.span = span;
  return g;
}

function mergeGeos(list) {
  const pos = [], nrm = [], col = [];
  for (const g of list) {
    const p = g.getAttribute("position"), n = g.getAttribute("normal"), c = g.getAttribute("color");
    for (let i = 0; i < p.count; i++) {
      pos.push(p.getX(i), p.getY(i), p.getZ(i));
      nrm.push(n.getX(i), n.getY(i), n.getZ(i));
      col.push(c.getX(i), c.getY(i), c.getZ(i));
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute("color", new THREE.Float32BufferAttribute(col, 3));
  return g;
}

/* ── a palm: tapered leaning trunk and a crown of drooping fronds ───────── */
function palmGeometry() {
  const pos = [], nrm = [], col = [], idx = [];
  const push = (x, y, z, n, c) => { pos.push(x, y, z); nrm.push(n[0], n[1], n[2]); col.push(c[0], c[1], c[2]); return pos.length / 3 - 1; };
  const bark = [0.14, 0.105, 0.062], barkLit = [0.30, 0.245, 0.145];
  const H = 1, R = 0.055;
  const SEG = 5, STEPS = 5;
  const rings = [];
  // a palm leans, and the lean is a curve, not a shear
  const leanOf = (t) => t * t * 0.22;
  for (let s = 0; s <= STEPS; s++) {
    const t = s / STEPS;
    const y = t * H;
    const r = R * (1 - t * 0.42);
    const row = [];
    for (let i = 0; i < SEG; i++) {
      const a = (i / SEG) * Math.PI * 2;
      row.push(push(Math.cos(a) * r + leanOf(t), y, Math.sin(a) * r,
        [Math.cos(a), 0.15, Math.sin(a)], mixc(bark, barkLit, 0.25 + 0.5 * (0.5 + 0.5 * Math.cos(a - 2.2)) + 0.25 * t)));
    }
    rings.push(row);
  }
  for (let s = 0; s < STEPS; s++) for (let i = 0; i < SEG; i++) {
    const j = (i + 1) % SEG;
    idx.push(rings[s][i], rings[s][j], rings[s + 1][i], rings[s][j], rings[s + 1][j], rings[s + 1][i]);
  }
  const top = [leanOf(1), H, 0];
  // nine fronds, each a three-segment strip that arcs out and falls away
  for (let f = 0; f < 9; f++) {
    const a = (f / 9) * Math.PI * 2 + 0.4;
    const dx = Math.cos(a), dz = Math.sin(a);
    const L = 0.52 + 0.14 * noise2(f * 2.1, 1.3);
    const droop = 0.26 + 0.2 * noise2(f, 4.4);
    const cBase = [0.10, 0.20, 0.05], cTip = [0.34, 0.47, 0.09];
    const n = [0, 1, 0];
    let prevL = push(top[0], top[1] + 0.02, top[2], n, cBase);
    let prevR = prevL;
    for (let k = 1; k <= 3; k++) {
      const u = k / 3;
      const w = 0.105 * (1 - u * 0.62);
      // the arc: up a little, then over and down
      const lift = Math.sin(u * Math.PI * 0.72) * 0.11 - droop * u * u;
      const px = -dz * w, pz = dx * w;
      const x = top[0] + dx * L * u, y = top[1] + lift, z = top[2] + dz * L * u;
      const c = mixc(cBase, cTip, u);
      const l = push(x + px, y, z + pz, n, c);
      const rr = push(x - px, y, z - pz, n, c);
      idx.push(prevL, l, rr, prevL, rr, prevR);
      prevL = l; prevR = rr;
    }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute("color", new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  return g;
}

/* ── a fern: a rosette of fronds, for slopes and the understorey ────────── */
function fernGeometry() {
  const pos = [], nrm = [], col = [], idx = [];
  const push = (x, y, z, c) => { pos.push(x, y, z); nrm.push(0, 1, 0); col.push(c[0], c[1], c[2]); return pos.length / 3 - 1; };
  const dark = [0.035, 0.072, 0.020], lit = [0.17, 0.27, 0.055];
  for (let f = 0; f < 7; f++) {
    const a = f * 2.3999632;
    const dx = Math.cos(a), dz = Math.sin(a);
    const L = 0.8 + 0.5 * Math.abs(noise2(f * 1.9, 3.1));
    const rise = 0.42 + 0.34 * Math.abs(noise2(f * 3.7, 1.1));
    const w = 0.16;
    const px = -dz * w, pz = dx * w;
    const b0 = push(0, 0.04, 0, dark);
    const m1 = push(dx * L * 0.5 + px, rise, dz * L * 0.5 + pz, mixc(dark, lit, 0.55));
    const m2 = push(dx * L * 0.5 - px, rise, dz * L * 0.5 - pz, mixc(dark, lit, 0.55));
    const tp = push(dx * L, rise * 0.55, dz * L, lit);
    idx.push(b0, m1, m2, m1, tp, m2);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute("color", new THREE.Float32BufferAttribute(col, 3));
  g.setIndex(idx);
  return g;
}

/* ── an emergent tree: bare trunk, wide flat crown above the canopy ─────── */
/* These are the trees that break the canopy line in every aerial of a real
   rainforest. Tall, bare for most of their height, and crowned with a wide
   plate of leaves that catches the sun a good twenty metres above everything
   around it — which is what gives a jungle its depth from the air. */
function emergentGeometry(seed = 5.5) {
  const trunk = new THREE.CylinderGeometry(0.045, 0.14, 0.72, 6, 1, true);
  trunk.translate(0, 0.36, 0);
  const tp = trunk.getAttribute("position");
  const tc = [];
  for (let i = 0; i < tp.count; i++) {
    const t = tp.getY(i) / 0.72;
    const c = mixc([0.10, 0.082, 0.055], [0.33, 0.27, 0.17], 0.25 + 0.5 * t);
    tc.push(c[0], c[1], c[2]);
  }
  trunk.setAttribute("color", new THREE.Float32BufferAttribute(tc, 3));
  // three boughs of leaves spread into a plate, not one ball on a stick
  const crown = clumpGeometry(seed, { count: 3, spread: 0.78, drop: 0.16, bands: 3, segs: 9 });
  crown.scale(1.02, 0.40, 1.02);
  crown.translate(0, 0.66, 0);
  return mergeGeos([trunk.toNonIndexed(), crown.toNonIndexed()]);
}

/* ── mangrove: dark crown over a splay of stilt roots ───────────────────── */
function mangroveGeometry() {
  const crown = clumpGeometry(2.2, { count: 3, spread: 0.46, drop: 0.3, bands: 3, segs: 8 });
  crown.scale(1, 0.72, 1);
  crown.translate(0, 0.52, 0);
  const pos = [], nrm = [], col = [], idx = [];
  // six legs, splayed, meeting under the crown: the shape that reads as
  // mangrove from any distance where you can see it at all
  const rootCol = [0.072, 0.055, 0.034];
  for (let k = 0; k < 6; k++) {
    const a = k * 2.3999632;
    const dx = Math.cos(a), dz = Math.sin(a);
    const foot = 0.52 + 0.2 * Math.abs(noise2(k * 1.7, 2.3));
    const w = 0.035;
    const px = -dz * w, pz = dx * w;
    const base = pos.length / 3;
    pos.push(dx * foot + px, 0, dz * foot + pz,
             dx * foot - px, 0, dz * foot - pz,
             dx * 0.10 + px, 0.56, dz * 0.10 + pz,
             dx * 0.10 - px, 0.56, dz * 0.10 - pz);
    for (let i = 0; i < 4; i++) { nrm.push(dx, 0.2, dz); col.push(rootCol[0], rootCol[1], rootCol[2]); }
    idx.push(base, base + 1, base + 2, base + 1, base + 3, base + 2);
  }
  const roots = new THREE.BufferGeometry();
  roots.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  roots.setAttribute("normal", new THREE.Float32BufferAttribute(nrm, 3));
  roots.setAttribute("color", new THREE.Float32BufferAttribute(col, 3));
  roots.setIndex(idx);
  return mergeGeos([roots.toNonIndexed(), crown.toNonIndexed()]);
}

/* ── the foliage shader ─────────────────────────────────────────────────── */
export function floraMaterial(uniforms, { sway = 1, twoSided = false } = {}) {
  return new THREE.ShaderMaterial({
    // spread copies the uniform *objects*, so uTime and the palette stay
    // shared; only the sway strength is this material's own
    uniforms: { ...uniforms, uSwayK: { value: sway } },
    vertexShader: /* glsl */`
      attribute vec3 ilit;
      uniform float uTime, uSway, uSwayK;
      varying vec3 vWorld; varying vec3 vNormal; varying vec3 vColor; varying vec3 vLit;
      varying float vUp;
      void main() {
        vec3 p = position;
        vec4 wp = modelMatrix * instanceMatrix * vec4(p, 1.0);
        // two wave trains crossing the island, so a gust travels rather than
        // every tree on the hillside nodding in time
        float phase = wp.x * 0.012 + wp.z * 0.009;
        float gust = sin(uTime * 0.55 + phase) * 0.6 + sin(uTime * 1.23 + phase * 2.1) * 0.4;
        float local = sin(uTime * 2.1 + wp.x * 0.07 + wp.z * 0.05) * 0.22;
        wp.xz += (gust + local) * uSway * uSwayK * max(0.0, p.y) * 0.85;
        vWorld = wp.xyz;
        /* instanceMatrix carries a non-uniform scale, so the normal has to
           go through the inverse of it. mat3(instanceMatrix) * normal tips
           every normal toward the squashed axis, which reads as faceting. */
        vec3 isc = vec3(length(instanceMatrix[0].xyz), length(instanceMatrix[1].xyz), length(instanceMatrix[2].xyz));
        vNormal = normalize(mat3(instanceMatrix) * (normal / max(isc * isc, vec3(1e-4))));
        vColor = color * instanceColor;
        vLit = ilit;
        // where this vertex sits in its own crown: 0 underside, 1 sunlit top
        vUp = clamp(p.y * 0.62 + 0.18, 0.0, 1.0);
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      uniform sampler2D uDetail;
      varying vec3 vNormal; varying vec3 vColor; varying vec3 vLit; varying float vUp;
      void main() {
        vec3 n = normalize(vNormal);
        vec3 viewDir = normalize(cameraPosition - vWorld);
        // leaf clumps: a crown is not a smooth surface, it is a few hundred
        // sprays of leaves. Three world-space octaves break the normal up so
        // the shading stops reading as moulded plastic.
        float near = 1.0 - smoothstep(260.0, 1500.0, length(vWorld - cameraPosition));
        vec2 ca = vWorld.xz * 0.17 + vWorld.y * 0.06;
        vec2 cb = vWorld.zy * 0.52 - vWorld.x * 0.05;
        float c1 = texture2D(uDetail, ca).r - 0.5;
        float c2 = texture2D(uDetail, cb).g - 0.5;
        float c3 = texture2D(uDetail, ca * 3.1 + 0.31).b - 0.5;
        n = normalize(n + vec3(c1 + c3 * 0.6, (c1 + c2) * 0.28, c2 + c3 * 0.6) * mix(0.17, 0.30, near));

        float shade = vLit.x, ao = vLit.y;
        // ambient occlusion by height: the holes between crowns go dark,
        // which is what gives an aerial its texture instead of a field of
        // highlights. Harder than before — the canopy wants real black in it.
        float deep = mix(0.16, 1.0, pow(vUp, 1.25));
        float ndl = dot(n, uSunDir);
        float sun = pow(clamp(ndl * 0.54 + 0.46, 0.0, 1.0), 1.6) * mix(0.09, 1.0, shade) * mix(0.30, 1.0, vUp);
        vec3 light = uSunColor * sun;
        // the fill is sky, and sky is blue: that separation is what turns a
        // flat green hillside into sunlit tops over cold shadow
        light += uSkyColor * (0.34 + 0.34 * n.y) * ao * deep;
        light += uGroundColor * 0.13 * ao * deep;
        // leaves glow where the low sun comes through them
        float trans = pow(clamp(dot(viewDir, -uSunDir), 0.0, 1.0), 2.0) * clamp(0.7 - ndl, 0.0, 1.0);
        light += uSunDeep * trans * 0.85 * shade * vUp;
        vec3 color = vColor * light;
        // new growth on the sunlit tops: the yellow-green that keeps a
        // rainforest canopy from reading as one colour
        color = mix(color, color * vec3(1.22, 1.10, 0.56), pow(vUp, 3.5) * sun * 0.42);
        // a thin hot edge where a crown turns away into the sun
        float rim = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 2.4) * clamp(ndl * 0.6 + 0.4, 0.0, 1.0);
        color += uSunColor * rim * 0.38 * shade * vUp;
        vec3 hv = normalize(uSunDir + viewDir);
        color += uSunColor * pow(max(dot(n, hv), 0.0), 26.0) * 0.08 * shade;
        color = applyAtmos(color, vWorld, -viewDir);
        gl_FragColor = vec4(color * uExposure, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
    vertexColors: true,
    // crowns are closed volumes; only the strip geometry — fronds, ferns,
    // stilt roots — needs its back faces, and leaving them on everywhere
    // doubled the fill cost for nothing
    side: twoSided ? THREE.DoubleSide : THREE.FrontSide,
  });
}

/* ── scatter ────────────────────────────────────────────────────────────── */
function rng(seed) {
  let s = seed >>> 0;
  return () => ((s = (Math.imul(s, 1664525) + 1013904223) >>> 0) / 4294967296);
}
function shuffled(list, seed) {
  const r = rng(seed);
  for (let i = list.length - 1; i > 0; i--) {
    const j = Math.floor(r() * (i + 1));
    const t = list[i]; list[i] = list[j]; list[j] = t;
  }
  return list;
}

const VOLCANO = { x: -150, z: -330 };

/* A stand of jungle is not one plant. Most crowns are plain green; a tenth
   are the pale yellow-green of new growth, a tenth the blue-green of the
   shade species, and a rare few are flowering — the red specks that stop an
   aerial from reading as a single colour. */
function species(u) {
  if (u < 0.13) return [1.42, 1.18, 0.34];   // new growth, acid yellow-green
  if (u < 0.29) return [0.46, 0.95, 1.18];   // shade species, blue-green
  if (u < 0.32) return [1.80, 0.60, 0.40];   // flowering, the red specks
  if (u < 0.39) return [1.06, 1.06, 0.56];   // olive
  return [1, 1, 1];
}

/* How much jungle a spot can hold, 0..1. The biome differences people read
   from the air — bare ash, pale karst, open temple plaza, marsh, dunes — are
   mostly this function saying no. */
function canopyDensity(field, x, z, h, slope, moist, zone, temple, camps) {
  if (h < 3.5 || h > 820) return 0;
  if (slope > 2.0) return 0;
  let d = 0.25 + 0.95 * moist;
  d *= clamp(1.4 - slope * 0.42, 0.22, 1);
  d *= sstep(3.5, 16, h);
  d *= 1 - 0.8 * sstep(560, 760, h);
  const vd = Math.hypot(x - VOLCANO.x, z - VOLCANO.z);
  d *= clamp(sstep(250, 560, vd), 0.0, 1);                       // ash cone is bare
  if (temple) d *= clamp(sstep(110, 250, Math.hypot(x - temple.x, z - temple.z)), 0.06, 1);
  const beach = sstep(80, 20, coastField(x, z)) * sstep(24, 8, h);
  d *= 1 - 0.9 * beach;
  // the river keeps its corridor open, so the valley reads from the air
  const riv = riverSample(x, z);
  d *= clamp(sstep(42, 115, riv.d), 0.0, 1);
  // natural clearings: grass shelves, slips, outcrops
  d *= clamp(0.55 + 1.1 * fbm(x * 0.0034 + 41.2, z * 0.0034 - 7.8, 2), 0, 1);
  if (zone.gap < 40 && slope < 1.15) d *= 0.05 + 0.9 * sstep(14, 40, zone.gap);                   // keep the trail open
  // a camp stands in a clearing, the way a camp does — and the camera relies
  // on it: island-layout's canopyTopAt cuts the same hole, to the metre
  if (camps) for (const c of camps) {
    const cd = Math.hypot(x - c.x, z - c.z);
    if (cd < CAMP_CLEAR) return 0;
    if (cd < CAMP_FADE) d *= sstep(CAMP_CLEAR, CAMP_FADE, cd);
  }
  return clamp(d, 0, 1);
}

export function buildFlora(field, layout, uniforms, stacks) {
  const sites = field.sites;
  const temple = layout.zones.find((z) => z.siteId === "temple") || null;
  const canopy = [], emergent = [], palms = [], mangroves = [], scrub = [], ferns = [];
  // one clearing per camp, not per marker: markers cluster tightly
  const camps = layout.clearings || [];
  const R = ISLAND_R + 60;
  // fewer sample points than before, because each one now plants a crown
  // built from three or four lobes rather than a single ball: the triangle
  // budget buys silhouette instead of count, which is what the canopy was
  // short of
  const CLUSTERS = 15500;
  const r = rng(99173);
  // a zone's own hue, multiplied into every plant standing in it, so the
  // biomes read as different country from the air
  const zoneTint = sites.map((st) => tintOf(st.id));
  const tintAt = (zi) => (zi >= 0 && zoneTint[zi]) || [1, 1, 1];

  for (let i = 0; i < CLUSTERS; i++) {
    // jittered golden-angle disc: even coverage, no grid artefacts
    const a = i * 2.3999632;
    const rad = R * Math.sqrt((i + 0.5) / CLUSTERS) * (0.985 + 0.03 * r());
    const cx = Math.cos(a) * rad + (r() - 0.5) * 26;
    const cz = Math.sin(a) * rad + (r() - 0.5) * 26;
    const h = groundAt(field, cx, cz);
    const slope = sampleGrid(field, field.slope, cx, cz);
    const moist = sampleGrid(field, field.moist, cx, cz);
    const zone = zoneField(cx, cz, sites);
    const shade = clamp(sampleGrid(field, field.shade, cx, cz), 0, 1);
    const ao = clamp(sampleGrid(field, field.ao, cx, cz), 0, 1);

    // beaches and spits get palms
    const coast = coastField(cx, cz);
    if (h > 2.2 && h < 26 && coast < 110 && slope < 0.33) {
      const zt = tintAt(zone.zone);
      const n = r() < 0.72 ? 1 + ((r() * 2.4) | 0) : 0;
      for (let k = 0; k < n; k++) {
        const s = 9 + 9 * r();
        palms.push({ x: cx + (r() - 0.5) * 34, z: cz + (r() - 0.5) * 34, y: h - 0.5, s, yaw: r() * 6.28,
          tint: [zt[0] * (0.85 + 0.3 * r()), zt[1] * (0.9 + 0.25 * r()), zt[2] * (0.8 + 0.3 * r())], shade, ao });
      }
      if (r() < 0.45) scrub.push({ x: cx, z: cz, y: h, s: 2.4 + 2.4 * r(), yaw: r() * 6.28, tint: [zt[0], zt[1] * 0.98, zt[2] * 0.72], shade, ao, dry: 1 });
      continue;
    }
    // marsh: mangroves standing in the shallows
    const marshD = Math.hypot(cx + 740, cz - 520);
    if (marshD < 430 && h > 1 && h < 30) {
      // thinner than the jungle: a mangrove flat is half open water, and
      // packing it solid hid the one thing that makes it read as a swamp
      if (r() < 0.3) continue;
      const n = 1 + Math.floor(r() * 2);
      for (let k = 0; k < n; k++) {
        const s = 7 + 6 * r();
        const zt = tintAt(zone.zone);
        mangroves.push({ x: cx + (r() - 0.5) * 30, z: cz + (r() - 0.5) * 30, y: h - 1.5, s, yaw: r() * 6.28,
          tint: [zt[0] * (0.56 + 0.25 * r()), zt[1] * (0.70 + 0.25 * r()), zt[2] * (0.46 + 0.3 * r())], shade, ao });
      }
      continue;
    }

    const d = canopyDensity(field, cx, cz, h, slope, moist, zone, temple, camps);
    if (d <= 0.02) {
      // bare ground still gets dry scrub, which keeps the ash and the summits
      // from reading as empty polygons
      if (h > 6 && h < 860 && slope < 2.2 && r() < 0.7) {
        const dry = clamp(1 - moist, 0, 1);
        const zt = tintAt(zone.zone);
        const it = { x: cx, z: cz, y: h, s: 2.4 + 4.2 * r(), yaw: r() * 6.28,
          tint: [zt[0] * (0.85 + 0.5 * dry), zt[1] * (0.8 + 0.3 * dry), zt[2] * (0.45 + 0.2 * dry)], shade, ao, dry };
        // on a wet slope that is scrub only because the canopy cannot hold,
        // the thing that actually grows is ferns
        if (moist > 0.5 && slope > 0.5) ferns.push({ ...it, s: it.s * 1.5 }); else scrub.push(it);
      }
      continue;
    }
    // a clump of 1–5 crowns, so the canopy is lumpy rather than evenly dotted
    const n = 1 + Math.floor(d * 5.2 * (0.6 + 0.8 * r()));
    const spreadR = 13 + 22 * r();
    const zt = tintAt(zone.zone);
    for (let k = 0; k < n; k++) {
      const ka = r() * 6.283, kr = spreadR * Math.sqrt(r());
      const x = cx + Math.cos(ka) * kr, z = cz + Math.sin(ka) * kr;
      const y = groundAt(field, x, z);
      if (y < 2.5) continue;
      // size: mostly small, with a long tail of big crowns. A rainforest seen
      // from above is a few giants among a mass of ordinary trees, not a tray
      // of equal balls.
      // size: mostly small, with a long tail of big crowns, and a wider
      // spread than before so no two neighbours read as the same tree
      const s = (6.2 + 26 * Math.pow(r(), 2.2)) * (0.74 + 0.5 * d);
      const wet = clamp(moist + 0.25 * (r() - 0.5), 0, 1);
      // tint: wetter is deeper and bluer, drier is olive and yellow
      // large-scale mottling: whole stands of canopy go dark or bright,
      // which is what stops an aerial reading as one flat green
      const mot = 0.50 + 0.90 * clamp(0.5 + 0.75 * fbm(x * 0.0021 + 17.3, z * 0.0021 - 9.1, 3), 0, 1);
      const v = mot * (0.62 + 0.58 * r());
      const hue = species(r());
      const tint = [
        zt[0] * v * hue[0] * (mix(1.02, 0.56, wet) + 0.26 * (r() - 0.5)),
        zt[1] * v * hue[1] * (mix(1.00, 1.16, wet) + 0.22 * (r() - 0.5)),
        zt[2] * v * hue[2] * (mix(0.46, 0.84, wet) + 0.20 * (r() - 0.5)),
      ];
      canopy.push({ x, z, y: y - s * 0.10, s, yaw: r() * 6.28, tint, shade, ao, moist: wet, variant: (r() * 6) | 0 });
    }
    // understory: small dark crowns filling the gaps between the big ones
    if (d > 0.22 && r() < 0.8) {
      const un = 1 + Math.floor(r() * 3);
      for (let k = 0; k < un; k++) {
        const ka = r() * 6.283, kr = spreadR * 1.3 * Math.sqrt(r());
        const x = cx + Math.cos(ka) * kr, z = cz + Math.sin(ka) * kr;
        const y = groundAt(field, x, z);
        if (y < 2.5) continue;
        const it = { x, z, y, s: 4 + 7 * r(), yaw: r() * 6.28,
          tint: [zt[0] * (0.44 + 0.2 * r()), zt[1] * (0.74 + 0.2 * r()), zt[2] * (0.36 + 0.2 * r())],
          shade: shade * 0.8, ao: ao * 0.75, moist };
        if (r() < 0.45) ferns.push({ ...it, s: it.s * 1.15 }); else scrub.push(it);
      }
    }
    // the tall ones that break the canopy line
    // the tall ones that break the canopy line — and in the cloud forest,
    // more of them and bigger, because that is what a canopy highland is
    const highland = Math.hypot(cx + 820, cz + 180) < 560 ? 2.1 : 1;
    if (r() < 0.14 * d * highland && h > 24 && h < 660) {
      const s = (26 + 24 * r()) * (highland > 1 ? 1.25 : 1);
      const hue = species(r() * 0.9);
      emergent.push({ x: cx, z: cz, y: h - 1, s, yaw: r() * 6.28,
        tint: [zt[0] * hue[0] * (0.66 + 0.24 * r()), zt[1] * hue[1] * (0.86 + 0.16 * r()), zt[2] * hue[2] * (0.52 + 0.2 * r())],
        shade, ao, moist, variant: (r() * 3) | 0 });
    }
  }

  // crowns clinging to the limestone towers
  for (const st of (stacks || [])) {
    const topY = st.sea ? -26 + st.h : st.h;
    // a crown of scrub spilling over the summit, sized to the tower it is on
    // the crags reach above the nominal top, so the crown sits above it too
    const crest = topY + st.h * 0.14;
    const n = Math.max(14, Math.round(st.r * 1.1));
    for (let k = 0; k < n; k++) {
      const a = r() * 6.283, rr = st.r * 0.92 * Math.sqrt(r());
      // scrub drapes down the notches between the pinnacles rather than
      // sitting in a ring on a rim: spread the depth, keep the clumps small
      canopy.push({ x: st.x + Math.cos(a) * rr, z: st.z + Math.sin(a) * rr, y: crest - st.h * (0.02 + 0.26 * r() * r()),
        s: st.r * (0.13 + 0.19 * r()), yaw: r() * 6.28,
        tint: [0.74 + 0.3 * r(), 1.0, 0.66 + 0.26 * r()], shade: 1, ao: 0.95, moist: 0.5, variant: (r() * 6) | 0 });
    }
    // growth catching on the ledges, thinning down the sheer flanks
    const ledges = Math.max(14, Math.round(st.h * 0.13));
    for (let k = 0; k < ledges; k++) {
      const a = r() * 6.283, t = 0.14 + 0.76 * r();
      const rr = st.r * (0.88 - 0.1 * t) * (0.9 + 0.2 * r());
      canopy.push({ x: st.x + Math.cos(a) * rr, z: st.z + Math.sin(a) * rr, y: topY - st.h * (1 - t),
        s: st.r * (0.1 + 0.2 * r() * t), yaw: r() * 6.28,
        tint: [0.5 + 0.3 * r(), 0.78 + 0.25 * r(), 0.42 + 0.25 * r()], shade: 0.7 + 0.3 * r(), ao: 0.7, moist: 0.65, variant: (r() * 6) | 0 });
    }
  }

  const group = new THREE.Group();
  group.name = "flora";
  const made = [];
  const add = (name, geo, list, seed, sway = 1, twoSided = false, flatten = 1) => {
    if (!list.length) return;
    shuffled(list, seed);
    const mesh = new THREE.InstancedMesh(geo, floraMaterial(uniforms, { sway, twoSided }), list.length);
    const lit = new Float32Array(list.length * 3);
    const m = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), s = new THREE.Vector3();
    const col = new THREE.Color();
    list.forEach((it, i) => {
      q.setFromAxisAngle(new THREE.Vector3(0, 1, 0), it.yaw);
      p.set(it.x, it.y, it.z);
      const sq = 0.7 + 0.6 * ((i * 37) % 100) / 100;
      s.set(it.s * (0.86 + 0.28 * ((i * 53) % 100) / 100), it.s * flatten * sq, it.s * (0.86 + 0.28 * ((i * 71) % 100) / 100));
      m.compose(p, q, s);
      mesh.setMatrixAt(i, m);
      col.setRGB(it.tint[0], it.tint[1], it.tint[2]);
      mesh.setColorAt(i, col);
      lit[i * 3] = it.shade; lit[i * 3 + 1] = it.ao; lit[i * 3 + 2] = it.moist ?? 0.4;
    });
    mesh.geometry.setAttribute("ilit", new THREE.InstancedBufferAttribute(lit, 3));
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    mesh.name = name;
    mesh.frustumCulled = true;
    mesh.userData.full = list.length;
    mesh.userData.tris = (geo.index ? geo.index.count : geo.getAttribute("position").count) / 3 * list.length;
    group.add(mesh);
    made.push(mesh);
  };

  /* Six crown shapes, not three, and each one a stack of lobes rather than a
     single ball. Two of them carry a trunk, for the beats that end up near
     the ground. Six variants is the point where a hillside stops repeating
     at the distance you can actually tell one crown from another. */
  const crowns = [
    clumpGeometry(1.1, { count: 4, spread: 0.56, drop: 0.38, bands: 3, segs: 9 }),
    clumpGeometry(4.7, { count: 3, spread: 0.62, drop: 0.30, bands: 3, segs: 9 }),
    clumpGeometry(8.3, { count: 5, spread: 0.50, drop: 0.44, bands: 3, segs: 8 }),
    clumpGeometry(2.9, { count: 3, spread: 0.44, drop: 0.26, bands: 4, segs: 10, trunk: 0.5 }),
    clumpGeometry(6.1, { count: 4, spread: 0.68, drop: 0.34, bands: 3, segs: 9 }),
    clumpGeometry(9.7, { count: 3, spread: 0.38, drop: 0.22, bands: 3, segs: 9, trunk: 0.7 }),
  ];
  const scrubGeo = clumpGeometry(7.3, { count: 2, spread: 0.46, drop: 0.3, bands: 2, segs: 7 });
  crowns.forEach((geo, k) => add(`canopy-${k}`, geo, canopy.filter((c) => (c.variant ?? 0) === k), 7717 + k * 131, 1));
  const emergents = [emergentGeometry(5.5), emergentGeometry(2.3), emergentGeometry(7.9)];
  emergents.forEach((geo, k) => add(`emergent-${k}`, geo, emergent.filter((c) => (c.variant ?? 0) === k), 3391 + k * 97, 1.25));
  add("palm", palmGeometry(), palms, 5519, 2.1, true);
  add("mangrove", mangroveGeometry(), mangroves, 8821, 0.6, true);
  add("scrub", scrubGeo, scrub, 2203, 1.3);
  add("fern", fernGeometry(), ferns, 4409, 2.4, true);

  group.userData.meshes = made;
  group.userData.total = canopy.length + emergent.length + palms.length + mangroves.length + scrub.length + ferns.length;
  group.userData.counts = { canopy: canopy.length, emergent: emergent.length, palm: palms.length,
    mangrove: mangroves.length, scrub: scrub.length, fern: ferns.length };
  return group;
}

/* Thin every layer by the same fraction; order is already shuffled, so the
   thinning is spatially even. */
export function setFloraDensity(group, frac) {
  for (const mesh of group.userData.meshes) {
    mesh.count = Math.max(1, Math.round(mesh.userData.full * frac));
  }
}
