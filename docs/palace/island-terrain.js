/* island-terrain.js — the heightfield becomes geometry.

   The field is sampled once into typed arrays (height, moisture, slope, zone,
   trail, baked sun visibility and sky occlusion), and everything else in the
   scene — terrain mesh, foliage scatter, marker footing, water depth — reads
   that grid instead of re-running the noise. Sun visibility is ray-marched
   across the grid on the CPU, which is what gives the ridges their long
   golden-hour shadows without a single shadow map. */
import * as THREE from "three";
import {
  TERRAIN_HALF, ISLAND_R, SEA_LEVEL, heightAt, coastField, moistureAt, riverSample,
  zoneField, clamp, sstep, mix, fbm,
} from "./island-layout.js";

/* ── colour helpers (authored in sRGB, uploaded linear) ─────────────────── */
const srgb = (hex) => {
  const c = new THREE.Color(hex);
  c.convertSRGBToLinear();
  return [c.r, c.g, c.b];
};
const lerp3 = (a, b, t, out) => {
  out[0] = a[0] + (b[0] - a[0]) * t;
  out[1] = a[1] + (b[1] - a[1]) * t;
  out[2] = a[2] + (b[2] - a[2]) * t;
  return out;
};

export const PAL = {
  jungleDeep: srgb("#15240e"),
  jungleMid:  srgb("#2b4315"),
  jungleLit:  srgb("#4e7023"),
  jungleDry:  srgb("#737139"),
  moss:       srgb("#3c5c1d"),
  rockDark:   srgb("#2e2823"),
  rockWet:    srgb("#4c4840"),
  rockPale:   srgb("#938f7e"),
  limestone:  srgb("#d2cebb"),
  ash:        srgb("#332d29"),
  ashLight:   srgb("#564c43"),
  lava:       srgb("#b4350f"),
  sand:       srgb("#d8c095"),
  sandWet:    srgb("#8b7a5b"),
  marsh:      srgb("#38401f"),
  trail:      srgb("#b09467"),
  shallow:    srgb("#9ab79b"),
  seabed:     srgb("#233a3a"),
  bamboo:     srgb("#6d7d33"),
};

/* ── the field ──────────────────────────────────────────────────────────── */
export function buildField(layout, res = 449) {
  const half = TERRAIN_HALF, step = (half * 2) / (res - 1);
  const n = res * res;
  const h = new Float32Array(n), moist = new Float32Array(n), slope = new Float32Array(n);
  const zone = new Int8Array(n), gap = new Float32Array(n), shade = new Float32Array(n), ao = new Float32Array(n);
  const sites = layout.sites;

  for (let j = 0; j < res; j++) {
    const z = -half + j * step;
    for (let i = 0; i < res; i++) {
      const k = j * res + i;
      const x = -half + i * step;
      const y = heightAt(x, z);
      h[k] = y;
      if (y > -40) {
        const zf = zoneField(x, z, sites);
        zone[k] = zf.zone; gap[k] = zf.gap;
        moist[k] = moistureAt(x, z, y);
      } else { zone[k] = -1; gap[k] = 999; moist[k] = 0; }
    }
  }
  // slope from the sampled grid, so colour and scatter agree with the mesh
  for (let j = 0; j < res; j++) {
    for (let i = 0; i < res; i++) {
      const k = j * res + i;
      const l = h[j * res + Math.max(0, i - 1)], r = h[j * res + Math.min(res - 1, i + 1)];
      const u = h[Math.max(0, j - 1) * res + i], d = h[Math.min(res - 1, j + 1) * res + i];
      slope[k] = Math.hypot((r - l) / (2 * step), (d - u) / (2 * step));
    }
  }
  const field = { res, half, step, h, moist, slope, zone, gap, shade, ao, sites };
  bakeSun(field);
  bakeAO(field);
  return field;
}

export const sampleGrid = (field, arr, x, z) => {
  const { res, half, step } = field;
  const fx = clamp((x + half) / step, 0, res - 1.001);
  const fz = clamp((z + half) / step, 0, res - 1.001);
  const i = fx | 0, j = fz | 0, tx = fx - i, tz = fz - j;
  const a = arr[j * res + i], b = arr[j * res + i + 1];
  const c = arr[(j + 1) * res + i], d = arr[(j + 1) * res + i + 1];
  return mix(mix(a, b, tx), mix(c, d, tx), tz);
};
export const groundAt = (field, x, z) => sampleGrid(field, field.h, x, z);

/* Sun visibility: march the grid toward the sun and look for anything that
   rises above the ray. Soft-edged, so ridge shadows have a penumbra. */
export const SUN_AZ = 2.63;   // from the west-north-west
export const SUN_EL = 0.285;  // low, golden hour

function bakeSun(field) {
  const { res, step, h, shade } = field;
  const dx = Math.cos(SUN_AZ), dz = Math.sin(SUN_AZ), dy = Math.tan(SUN_EL);
  const stride = step * 1.15;
  const sx = (dx * stride) / step, sz = (dz * stride) / step, sy = dy * stride;
  const STEPS = 110;
  for (let j = 0; j < res; j++) {
    for (let i = 0; i < res; i++) {
      const k = j * res + i;
      const y0 = h[k];
      if (y0 < -8) { shade[k] = 1; continue; }
      let worst = 0;
      let x = i + sx * 0.6, z = j + sz * 0.6, y = y0 + sy * 0.6 + 1.5;
      for (let s = 1; s <= STEPS; s++, x += sx, z += sz, y += sy) {
        if (x < 0 || z < 0 || x >= res - 1 || z >= res - 1) break;
        const xi = x | 0, zi = z | 0, tx = x - xi, tz = z - zi;
        const a = h[zi * res + xi], b = h[zi * res + xi + 1];
        const c = h[(zi + 1) * res + xi], d = h[(zi + 1) * res + xi + 1];
        const hs = mix(mix(a, b, tx), mix(c, d, tx), tz);
        const over = (hs - y) / (18 + s * 1.6);
        if (over > worst) worst = over;
        if (worst > 1) break;
      }
      shade[k] = 1 - clamp(worst, 0, 1);
    }
  }
  // one blur pass: the penumbra sells the scale of the ridges
  const tmp = Float32Array.from(shade);
  for (let j = 1; j < res - 1; j++) for (let i = 1; i < res - 1; i++) {
    const k = j * res + i;
    shade[k] = (tmp[k] * 4 + tmp[k - 1] + tmp[k + 1] + tmp[k - res] + tmp[k + res]) / 8;
  }
}

/* Sky occlusion: how much of the dome a point can see, from how far it sits
   below its neighbourhood. Valleys go cool and deep, ridges stay open. */
function bakeAO(field) {
  const { res, h, ao, step } = field;
  const radii = [2, 5, 11, 21];
  for (let j = 0; j < res; j++) for (let i = 0; i < res; i++) {
    const k = j * res + i, y = h[k];
    let occ = 0;
    for (const r of radii) {
      let m = 0;
      for (let a = 0; a < 6; a++) {
        const ang = (a / 6) * Math.PI * 2 + r;
        const xi = clamp(i + Math.round(Math.cos(ang) * r), 0, res - 1);
        const zi = clamp(j + Math.round(Math.sin(ang) * r), 0, res - 1);
        m = Math.max(m, (h[zi * res + xi] - y) / (r * step));
      }
      occ += clamp(m, 0, 1.2);
    }
    ao[k] = clamp(1 - occ / (radii.length * 1.9), 0.22, 1);
  }
}

/* ── vertex colour ──────────────────────────────────────────────────────── */
const tmpA = [0, 0, 0], tmpB = [0, 0, 0];

function groundColor(x, z, y, slope, moist, zoneGap, out) {
  const dryHigh = clamp((y - 330) / 300, 0, 1);
  let veg = lerp3(PAL.jungleDeep, PAL.jungleLit, clamp(moist * 1.15 - 0.08, 0, 1), tmpA);
  veg = lerp3(veg, PAL.jungleDry, dryHigh * 0.55, tmpA);
  const varia = fbm(x * 0.0032, z * 0.0032, 3);
  veg = lerp3(veg, PAL.moss, clamp(varia * 0.8 + 0.3, 0, 1) * 0.35, tmpA);

  // rock where it is steep, plus the volcano's ash cone and the karst shelf
  const vd = Math.hypot(x + 150, z + 330);
  const ashAmt = clamp(1 - vd / 430, 0, 1) * clamp((y - 180) / 180, 0, 1);
  let rockAmt = sstep(0.52, 1.15, slope) * 0.95 + dryHigh * 0.2;
  rockAmt = clamp(rockAmt + ashAmt * 0.9, 0, 1);
  let rock = lerp3(PAL.rockDark, PAL.rockPale, clamp(0.35 + 0.5 * fbm(x * 0.008, z * 0.008, 2), 0, 1), tmpB);
  if (ashAmt > 0) rock = lerp3(rock, lerp3(PAL.ash, PAL.ashLight, clamp(0.3 + varia, 0, 1), [0, 0, 0]), clamp(ashAmt * 1.3, 0, 1), tmpB);
  lerp3(veg, rock, rockAmt, out);

  // marsh and riverbank
  const r = riverSample(x, z);
  if (r.d < 180) lerp3(out, PAL.marsh, Math.exp(-(r.d * r.d) / (120 * 120)) * 0.7, out);
  const sd = Math.hypot(x + 740, z - 520);
  if (sd < 520) lerp3(out, PAL.marsh, sstep(520, 180, sd) * 0.75, out);

  // beaches: a bright band either side of the waterline
  const m = coastField(x, z);
  const beach = sstep(70, 18, m) * sstep(26, 9, y) * clamp(1.15 - slope * 2.2, 0, 1);
  if (beach > 0) lerp3(out, PAL.sand, clamp(beach, 0, 1), out);

  // the trail that runs the zone boundary, the way the aerial reference reads
  if (zoneGap < 46 && y > 20 && slope < 1.05) {
    const t = sstep(46, 8, zoneGap) * clamp(1.15 - slope * 0.7, 0, 1);
    lerp3(out, PAL.trail, t * 0.8, out);
  }

  // under water: pale sand in the shallows, dark basalt as it drops away
  if (y < 2) {
    const sh = clamp((y + 22) / 24, 0, 1);
    const bed = lerp3(PAL.seabed, PAL.sand, sh * sh, tmpB);
    lerp3(out, bed, sstep(4, -6, y), out);
  }
  return out;
}

/* ── the terrain mesh ───────────────────────────────────────────────────── */
export function buildTerrain(field, uniforms) {
  const { res, half, step, h, slope, moist, shade, ao, gap } = field;
  const keep = new Int32Array(res * res).fill(-1);
  const pos = [], col = [], nrm = [], lit = [], idx = [];
  const c = [0, 0, 0];

  const needed = (i, j) => {
    // keep the land, the shelf and the reef; deep ocean is the water shader's job
    for (let dj = -1; dj <= 1; dj++) for (let di = -1; di <= 1; di++) {
      const k = clamp(j + dj, 0, res - 1) * res + clamp(i + di, 0, res - 1);
      if (h[k] > -118) return true;
    }
    return false;
  };

  for (let j = 0; j < res; j++) for (let i = 0; i < res; i++) {
    if (!needed(i, j)) continue;
    const k = j * res + i;
    const x = -half + i * step, z = -half + j * step, y = h[k];
    keep[k] = pos.length / 3;
    pos.push(x, y, z);
    const l = h[j * res + Math.max(0, i - 1)], r = h[j * res + Math.min(res - 1, i + 1)];
    const u = h[Math.max(0, j - 1) * res + i], d = h[Math.min(res - 1, j + 1) * res + i];
    const nx = (l - r) / (2 * step), nz = (u - d) / (2 * step);
    const il = 1 / Math.hypot(nx, 1, nz);
    nrm.push(nx * il, il, nz * il);
    groundColor(x, z, y, slope[k], moist[k], gap[k], c);
    col.push(c[0], c[1], c[2]);
    lit.push(shade[k], ao[k], clamp(moist[k], 0, 1));
  }
  for (let j = 0; j < res - 1; j++) for (let i = 0; i < res - 1; i++) {
    const a = keep[j * res + i], b = keep[j * res + i + 1];
    const cc = keep[(j + 1) * res + i], d = keep[(j + 1) * res + i + 1];
    if (a < 0 || b < 0 || cc < 0 || d < 0) continue;
    idx.push(a, cc, b, b, cc, d);
  }

  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("normal", new THREE.Float32BufferAttribute(nrm, 3));
  g.setAttribute("color", new THREE.Float32BufferAttribute(col, 3));
  g.setAttribute("lit", new THREE.Float32BufferAttribute(lit, 3));
  g.setIndex(idx.length > 65535 ? new THREE.Uint32BufferAttribute(idx, 1) : new THREE.Uint16BufferAttribute(idx, 1));
  g.computeBoundingSphere();

  const mesh = new THREE.Mesh(g, terrainMaterial(uniforms));
  mesh.name = "terrain";
  mesh.frustumCulled = false;
  mesh.userData.tris = idx.length / 3;
  return mesh;
}

/* ── shared shader chunks ───────────────────────────────────────────────── */
export const ATMOS_PARS = /* glsl */`
  uniform vec3 uSunDir, uSunColor, uSkyColor, uGroundColor, uFogColor, uHazeColor, uSunHaze;
  uniform float uFogDensity, uFogHeight, uTime, uExposure;
  varying vec3 vWorld;

  // Warm aerial perspective: thicker low down, and brighter when you look
  // into the sun, which is what makes the mist read as light rather than haze.
  vec3 applyAtmos(vec3 color, vec3 world, vec3 viewDir) {
    float dist = length(world - cameraPosition);
    float hCam = max(cameraPosition.y, 0.0), hPt = max(world.y, 0.0);
    float dh = max(1e-3, abs(hCam - hPt));
    float fh = uFogHeight;
    float a = exp(-hCam / fh), b = exp(-hPt / fh);
    float integral = fh * abs(a - b) / dh;
    float amount = 1.0 - exp(-uFogDensity * dist * integral);
    float toSun = max(0.0, dot(normalize(viewDir), uSunDir));
    vec3 fogCol = mix(uFogColor, uHazeColor, pow(toSun, 2.0) * 0.6);
    fogCol = mix(fogCol, uSunHaze, pow(toSun, 7.0) * 0.55);
    fogCol += uSunHaze * pow(toSun, 22.0) * 0.5 * amount;
    return mix(color, fogCol, clamp(amount, 0.0, 1.0));
  }
`;

export function terrainMaterial(uniforms) {
  return new THREE.ShaderMaterial({
    uniforms,
    vertexShader: /* glsl */`
      attribute vec3 lit;
      varying vec3 vWorld; varying vec3 vNormal; varying vec3 vColor; varying vec3 vLit;
      void main() {
        vec4 wp = modelMatrix * vec4(position, 1.0);
        vWorld = wp.xyz; vNormal = normal; vColor = color; vLit = lit;
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      uniform sampler2D uDetail;
      varying vec3 vNormal; varying vec3 vColor; varying vec3 vLit;

      void main() {
        vec3 n = normalize(vNormal);
        vec3 viewDir = normalize(cameraPosition - vWorld);

        // two scales of procedural detail, cross-faded by slope, standing in
        // for the texture a real surface would have at this distance
        vec3 d1 = texture2D(uDetail, vWorld.xz * 0.0022).rgb;
        vec3 d2 = texture2D(uDetail, vWorld.xz * 0.0135).rgb;
        float grain = (d1.r - 0.5) * 0.7 + (d2.g - 0.5) * 0.45;
        vec3 base = vColor * (1.0 + grain * 0.42);
        base *= 1.0 + (d2.b - 0.5) * 0.25;

        float shade = vLit.x, ao = vLit.y;
        float ndl = dot(n, uSunDir);
        // wrapped diffuse: foliage does not fall off like a billiard ball
        float wrap = clamp((ndl + 0.35) / 1.35, 0.0, 1.0);
        float sun = pow(wrap, 1.55) * mix(0.14, 1.0, shade);
        vec3 light = uSunColor * sun;
        light += uSkyColor * (0.30 + 0.30 * n.y) * ao;
        light += uGroundColor * (0.18 * (1.0 - n.y)) * ao;

        // back-scatter: light bleeding through the canopy on the sun side
        float back = pow(clamp(dot(viewDir, -uSunDir) * 0.5 + 0.5, 0.0, 1.0), 3.0);
        light += uSunColor * back * 0.16 * vLit.z * shade;

        vec3 color = base * light;

        // wet specular on rock and water-cut ground, low and sharp
        vec3 hv = normalize(uSunDir + viewDir);
        float spec = pow(max(dot(n, hv), 0.0), 42.0) * (1.0 - vLit.z) * shade * 0.35;
        color += uSunColor * spec;

        color = applyAtmos(color, vWorld, -viewDir);
        gl_FragColor = vec4(color * uExposure, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
    vertexColors: true,
  });
}

/* ── a tileable detail texture, generated once ──────────────────────────── */
export function detailTexture(size = 256) {
  const data = new Uint8Array(size * size * 4);
  const hash = (x, y, s) => {
    let h = Math.imul(x & 255, 374761393) ^ Math.imul(y & 255, 668265263) ^ Math.imul(s, 2246822519);
    h = Math.imul(h ^ (h >>> 13), 1274126177);
    return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
  };
  const tile = (u, v, period, seed) => {
    const x = u * period, y = v * period;
    const xi = Math.floor(x), yi = Math.floor(y);
    const tx = x - xi, ty = y - yi;
    const fx = tx * tx * (3 - 2 * tx), fy = ty * ty * (3 - 2 * ty);
    const w = (a, b) => hash(((a % period) + period) % period, ((b % period) + period) % period, seed);
    return mix(mix(w(xi, yi), w(xi + 1, yi), fx), mix(w(xi, yi + 1), w(xi + 1, yi + 1), fx), fy);
  };
  const oct = (u, v, p, seed) => tile(u, v, p, seed) * 0.6 + tile(u, v, p * 2, seed + 7) * 0.26 + tile(u, v, p * 4, seed + 19) * 0.14;
  for (let j = 0; j < size; j++) for (let i = 0; i < size; i++) {
    const u = i / size, v = j / size, k = (j * size + i) * 4;
    data[k] = oct(u, v, 8, 1) * 255;
    data[k + 1] = oct(u, v, 19, 2) * 255;
    data[k + 2] = oct(u, v, 5, 3) * 255;
    data[k + 3] = Math.abs(oct(u, v, 13, 4) - 0.5) * 2 * 255;
  }
  const tex = new THREE.DataTexture(data, size, size, THREE.RGBAFormat);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.minFilter = THREE.LinearMipmapLinearFilter;
  tex.magFilter = THREE.LinearFilter;
  tex.generateMipmaps = true;
  tex.needsUpdate = true;
  return tex;
}
