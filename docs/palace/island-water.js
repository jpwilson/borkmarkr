/* island-water.js — ocean, lagoon, river, lake and waterfalls.

   The ocean shader reads a baked depth texture of the island, which is what
   gives the lagoon its turquoise shallows, puts a foam line exactly on the
   waterline and lets surf gather where the sea meets a cliff. Every animated
   term is driven by the uTime uniform, so a frame at t is the same frame
   whenever it is asked for. */
import * as THREE from "three";
import { ATMOS_PARS, PAL } from "./island-terrain.js";
import { clamp, mix, noise2, fbm, RIVER, FALLS, riverSample, heightAt, coastField } from "./island-layout.js";
import { Build } from "./island-props.js";

/* R: depth below the waterline (0..120 → 0..1). G: land height (0..60 → 0..1). */
export function depthTexture(field, stacks) {
  const { res, h, half, step } = field;
  const data = new Uint8Array(res * res * 4);
  // the towers are props, not terrain: stamp them in so the water shader
  // breaks surf around their feet like it does on the shore
  const land = Float32Array.from(h);
  for (const [x, z, r] of (stacks || [])) {
    const ri = Math.ceil((r + 26) / step);
    const ci = Math.round((x + half) / step), cj = Math.round((z + half) / step);
    for (let j = Math.max(0, cj - ri); j < Math.min(res, cj + ri); j++) {
      for (let i = Math.max(0, ci - ri); i < Math.min(res, ci + ri); i++) {
        const dx = (-half + i * step) - x, dz = (-half + j * step) - z;
        const d = Math.hypot(dx, dz);
        if (d > r + 26) continue;
        const ring = Math.max(0, 1 - Math.abs(d - r + 2) / 26);
        land[j * res + i] = Math.max(land[j * res + i], 4.5 * ring * ring);
      }
    }
  }
  for (let i = 0; i < res * res; i++) {
    const y = land[i];
    data[i * 4] = clamp(-y / 120, 0, 1) * 255;
    data[i * 4 + 1] = clamp(y / 60, 0, 1) * 255;
    data[i * 4 + 2] = clamp((y + 8) / 16, 0, 1) * 255;
    data[i * 4 + 3] = 255;
  }
  const tex = new THREE.DataTexture(data, res, res, THREE.RGBAFormat);
  tex.wrapS = tex.wrapT = THREE.ClampToEdgeWrapping;
  tex.minFilter = THREE.LinearFilter;
  tex.magFilter = THREE.LinearFilter;
  tex.needsUpdate = true;
  return tex;
}

const WATER_PARS = /* glsl */`
  uniform sampler2D uDepth, uDetail;
  uniform float uHalf;
  vec4 islandAt(vec2 p) {
    vec2 uv = (p + uHalf) / (2.0 * uHalf);
    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) return vec4(1.0, 0.0, 0.0, 1.0);
    return texture2D(uDepth, uv);
  }
  // three crossed wave trains plus a scrolling detail octave
  vec3 waterNormal(vec2 p, float t, float scale, float amp) {
    vec2 q = p * scale;
        vec2 g = vec2(
      cos(q.x + q.y * 0.6 + t * 1.10) * 1.0 - cos(q.x * -0.7 + q.y * 1.3 + t * 0.83) * 0.7 + cos(q.x * 1.9 - q.y * 1.1 + t * 1.57) * 1.9,
      cos(q.x + q.y * 0.6 + t * 1.10) * 0.6 + cos(q.x * -0.7 + q.y * 1.3 + t * 0.83) * 1.3 - cos(q.x * 1.9 - q.y * 1.1 + t * 1.57) * 1.1);
    // three incommensurate, rotated samples so the tile never shows
    mat2 rot = mat2(0.80, -0.60, 0.60, 0.80);
    vec3 d1 = texture2D(uDetail, p * 0.0031 + vec2(t * 0.004, t * 0.0021)).rgb - 0.5;
    vec3 d2 = texture2D(uDetail, rot * p * 0.0113 - vec2(t * 0.0032, t * 0.0051)).rgb - 0.5;
    vec3 d3 = texture2D(uDetail, rot * rot * p * 0.0417 + vec2(t * 0.012, -t * 0.009)).rgb - 0.5;
    g += (d1.xy * 2.2 + d2.xy * 2.0 + d3.xy * 1.4);
    return normalize(vec3(-g.x * amp, 1.0, -g.y * amp));
  }
`;

export function buildOcean(field, uniforms, { inner = false } = {}) {
  const size = inner ? 7000 : 90000;
  const seg = inner ? 180 : 24;
  const geo = new THREE.PlaneGeometry(size, size, seg, seg);
  geo.rotateX(-Math.PI / 2);
  const mat = new THREE.ShaderMaterial({
    uniforms,
    defines: { INNER: inner ? 1 : 0 },
    vertexShader: /* glsl */`
      uniform float uTime;
      varying vec3 vWorld;
      void main() {
        vec3 p = position;
        #if INNER
          // gentle swell so a low pass over the sea has something to move
          float s = sin(p.x * 0.0085 + uTime * 0.9) * cos(p.z * 0.0071 - uTime * 0.73);
          float s2 = sin(p.x * 0.019 - p.z * 0.013 + uTime * 1.4);
          float fade = 1.0 - smoothstep(2200.0, 3400.0, max(abs(p.x), abs(p.z)));
          p.y += (s * 1.5 + s2 * 0.8) * fade;
        #endif
        vec4 wp = modelMatrix * vec4(p, 1.0);
        vWorld = wp.xyz;
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      ${WATER_PARS}
      uniform vec3 uDeep, uShallow, uFoam;
      void main() {
        vec3 viewDir = normalize(cameraPosition - vWorld);
        float dist = length(vWorld - cameraPosition);
        // flatten the ripples with distance or the horizon turns to static
        float detail = 1.0 - smoothstep(900.0, 7000.0, dist);
        vec3 n = waterNormal(vWorld.xz, uTime, 0.038, mix(0.0028, 0.013, detail));
        vec4 isl = islandAt(vWorld.xz);
        float depth = isl.r * 120.0;

        float shallow = 1.0 - smoothstep(1.0, 34.0, depth);
        vec3 body = mix(uDeep, uShallow, shallow * shallow);
        body = mix(body, uShallow * 1.25 + uFoam * 0.12, (1.0 - smoothstep(0.0, 9.0, depth)) * 0.65);

        float fres = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 4.5);
        vec3 refl = reflect(-viewDir, n);
        float toSun = max(0.0, dot(refl, uSunDir));
        vec3 sky = skyAt(normalize(vec3(refl.x, abs(refl.y) + 0.02, refl.z))) * 0.88;
        vec3 color = mix(body, sky, clamp(fres * 0.9 + 0.05, 0.0, 1.0));
        // the glitter path, broad then tight
        color += uSunColor * pow(toSun, 160.0) * 2.2 * detail;
        color += uSunColor * pow(toSun, 26.0) * 0.10;

        // surf: a band on the waterline, lines rolling in, spray on rock
        if (depth < 42.0) {
        float waveline = 0.5 + 0.5 * sin(depth * 0.55 - uTime * 1.8 + (texture2D(uDetail, vWorld.xz * 0.0016).r - 0.5) * 7.0);
        float band = (1.0 - smoothstep(0.0, 13.0, depth)) * waveline;
        float edge = (1.0 - smoothstep(0.0, 3.2, depth));
        float cliff = isl.g * (1.0 - smoothstep(0.0, 26.0, depth));
        float foam = clamp(band * 0.85 + edge * 0.75 + cliff * 1.6, 0.0, 1.0);
        foam *= 0.55 + 0.45 * texture2D(uDetail, vWorld.xz * 0.012 + vec2(uTime * 0.01, 0.0)).g * 2.0;
        color = mix(color, uFoam, clamp(foam, 0.0, 0.92));
        }

        color = applyAtmos(color, vWorld, -viewDir);
        gl_FragColor = vec4(color * uExposure, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
  });
  const mesh = new THREE.Mesh(geo, mat);
  mesh.name = inner ? "ocean-near" : "ocean-far";
  mesh.position.y = inner ? 0 : -0.6;
  mesh.renderOrder = inner ? 1 : 0;
  mesh.frustumCulled = false;
  return mesh;
}

/* ── inland water: the river, the crater lake, the marsh ────────────────── */
const MARSH_FLAG = 1;   // lit.z, read by the shader to switch water type

export function buildInland(field, uniforms) {
  const b = new Build();
  const col = [0.055, 0.1, 0.085];
  // river ribbon
  for (let i = 0; i < RIVER.length - 1; i++) {
    const [ax, az, ay] = RIVER[i], [bx, bz, by] = RIVER[i + 1];
    const dx = bx - ax, dz = bz - az, len = Math.hypot(dx, dz);
    const px = -dz / len, pz = dx / len;
    const w0 = 15 + 30 * (i / (RIVER.length - 1)), w1 = 15 + 30 * ((i + 1) / (RIVER.length - 1));
    const y0 = ay + 2.2, y1 = by + 2.2;
    const c0 = [0.05, 0.1, 0.1], c1 = [0.07, 0.13, 0.12];
    const v0 = b.vert(ax + px * w0, y0, az + pz * w0, 0, 1, 0, c0, 1, 1, 0);
    const v1 = b.vert(ax - px * w0, y0, az - pz * w0, 0, 1, 0, c0, 1, 1, 0);
    const v2 = b.vert(bx - px * w1, y1, bz - pz * w1, 0, 1, 0, c1, 1, 1, 0);
    const v3 = b.vert(bx + px * w1, y1, bz + pz * w1, 0, 1, 0, c1, 1, 1, 0);
    b.quad(v0, v3, v2, v1);
  }
  // crater lake
  const lake = { x: -130, z: -830, r: 118, y: 290 };
  const c = b.vert(lake.x, lake.y, lake.z, 0, 1, 0, [0.04, 0.09, 0.1], 1, 1, 0);
  const ring = [];
  for (let i = 0; i < 28; i++) {
    const a = (i / 28) * Math.PI * 2;
    ring.push(b.vert(lake.x + Math.cos(a) * lake.r, lake.y, lake.z + Math.sin(a) * lake.r, 0, 1, 0, [0.05, 0.1, 0.11], 1, 1, 0));
  }
  for (let i = 0; i < 28; i++) b.tri(c, ring[(i + 1) % 28], ring[i]);
  /* Marsh: not one sheet but the water that is actually there. A grid over
     the basin keeps only the cells whose ground lies under the pool line, so
     the mangrove flats read as a lace of still pools and mud banks instead of
     a slab of grey hanging out over the beach. */
  const M = { x: -740, z: 520, r: 420, y: 6.8 };
  const STEP = 11;
  const N = Math.ceil((M.r * 2) / STEP);
  const under = (x, z) => heightAt(x, z) < M.y - 0.35 && coastField(x, z) > 24;
  const idxOf = new Map();
  const vertAt = (i, j) => {
    const key = j * (N + 1) + i;
    if (idxOf.has(key)) return idxOf.get(key);
    const x = M.x - M.r + i * STEP, z = M.z - M.r + j * STEP;
    const depth = clamp((M.y - heightAt(x, z)) / 7, 0, 1);
    // peat-stained water: almost black where it is deep, warm tannin at the
    // mud line, a green algal film in the stillest corners
    const algae = clamp(0.5 + 0.9 * fbm(x * 0.021 + 3.3, z * 0.021 - 7.1, 2), 0, 1);
    const col = [
      mix(0.085, 0.016, depth) + algae * 0.012,
      mix(0.082, 0.030, depth) + algae * 0.030,
      mix(0.046, 0.024, depth) + algae * 0.006,
    ];
    const id = b.vert(x, M.y + 0.22 * noise2(x * 0.05, z * 0.05), z, 0, 1, 0, col, 1, 1, MARSH_FLAG);
    idxOf.set(key, id);
    return id;
  };
  for (let j = 0; j < N; j++) for (let i = 0; i < N; i++) {
    const x0 = M.x - M.r + i * STEP, z0 = M.z - M.r + j * STEP;
    if (Math.hypot(x0 + STEP / 2 - M.x, z0 + STEP / 2 - M.z) > M.r) continue;
    if (!under(x0, z0) || !under(x0 + STEP, z0) || !under(x0 + STEP, z0 + STEP) || !under(x0, z0 + STEP)) continue;
    b.quad(vertAt(i, j), vertAt(i, j + 1), vertAt(i + 1, j + 1), vertAt(i + 1, j));
  }

  const mat = new THREE.ShaderMaterial({
    uniforms,
    vertexShader: /* glsl */`
      attribute vec3 lit;
      varying vec3 vWorld; varying vec3 vColor; varying float vMarsh;
      void main() {
        vec4 wp = modelMatrix * vec4(position, 1.0);
        vWorld = wp.xyz; vColor = color; vMarsh = lit.z;
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      ${WATER_PARS}
      varying vec3 vColor; varying float vMarsh;
      void main() {
        vec3 viewDir = normalize(cameraPosition - vWorld);
        // a swamp is barely moving: fine wrinkles, not a river's chop
        float ripple = mix(0.02, 0.006, vMarsh);
        vec3 n = waterNormal(vWorld.xz, uTime * mix(1.6, 0.42, vMarsh), mix(0.09, 0.21, vMarsh), ripple);
        float fres = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 4.0);
        vec3 refl = reflect(-viewDir, n);
        vec3 sky = skyAt(normalize(vec3(refl.x, abs(refl.y) + 0.02, refl.z))) * 0.8;
        // Tea-dark water reflects the canopy standing over it, not the sky:
        // cap the mirror hard, or the marsh renders as a slab of grey cloud.
        float mirror = mix(clamp(fres * 0.85 + 0.1, 0.0, 1.0), clamp(fres * 0.26, 0.0, 0.17), vMarsh);
        vec3 overhead = mix(sky, sky * vec3(0.22, 0.30, 0.18) + vec3(0.012, 0.018, 0.007), vMarsh);
        vec3 color = mix(vColor, overhead, mirror);

        if (vMarsh > 0.5) {
          // peat glow: a low sun goes through the top inch and comes back warm
          float toSun = max(0.0, dot(normalize(-viewDir), uSunDir));
          color += vec3(0.16, 0.10, 0.035) * pow(toSun, 2.4) * 0.5;
          // lily pads, duckweed and reed stubble, scattered in clumps
          vec2 q = vWorld.xz * 0.055;
          float pads = texture2D(uDetail, q).g * texture2D(uDetail, q * 0.31 + 0.17).r;
          float clump = smoothstep(0.30, 0.52, texture2D(uDetail, vWorld.xz * 0.0045).b);
          float leaf = smoothstep(0.17, 0.30, pads) * clump;
          vec3 pad = mix(vec3(0.055, 0.105, 0.030), vec3(0.14, 0.20, 0.055), texture2D(uDetail, q * 2.3).r);
          color = mix(color, pad, leaf * 0.88);
          // the duckweed catches the sun where the water does not
          color += uSunColor * leaf * clamp(dot(vec3(0.0, 1.0, 0.0), uSunDir), 0.0, 1.0) * 0.10;
          float glint = max(0.0, dot(reflect(-viewDir, n), uSunDir));
          color += uSunColor * pow(glint, 220.0) * 0.8 * (1.0 - leaf);
        } else {
          float toSun = max(0.0, dot(reflect(-viewDir, n), uSunDir));
          color += uSunColor * pow(toSun, 48.0) * 0.9;
        }
        color = applyAtmos(color, vWorld, -viewDir);
        gl_FragColor = vec4(color * uExposure, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
    vertexColors: true,
  });
  const mesh = new THREE.Mesh(b.geometry(), mat);
  mesh.name = "inland-water";
  return mesh;
}

/* ── waterfalls: scrolling sheets with a bright lip ─────────────────────── */
export function buildFalls(field, uniforms) {
  const pos = [], uv = [], idx = [];
  const push = (x, y, z, u, v) => { pos.push(x, y, z); uv.push(u, v); return pos.length / 3 - 1; };
  for (const f of FALLS) {
    const top = heightAt(f.x, f.z);
    // aim the sheet away from the plateau centre
    const ang = Math.atan2(f.z + 800, f.x - 430);
    const dx = Math.cos(ang), dz = Math.sin(ang);
    const px = -dz, pz = dx;
    const drop = top + 6;
    const x0 = f.x + dx * 18, z0 = f.z + dz * 18;
    const run = 62;
    const a = push(x0 + px * f.w, top + 3, z0 + pz * f.w, 0, 1);
    const b2 = push(x0 - px * f.w, top + 3, z0 - pz * f.w, 1, 1);
    const c = push(x0 - px * f.w * 1.5 + dx * run, top - drop, z0 - pz * f.w * 1.5 + dz * run, 1, 0);
    const d = push(x0 + px * f.w * 1.5 + dx * run, top - drop, z0 + pz * f.w * 1.5 + dz * run, 0, 0);
    idx.push(a, c, b2, a, d, c);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute("uv", new THREE.Float32BufferAttribute(uv, 2));
  g.setIndex(idx);
  const mat = new THREE.ShaderMaterial({
    uniforms,
    transparent: true,
    depthWrite: false,
    side: THREE.DoubleSide,
    vertexShader: `varying vec3 vWorld; varying vec2 vUv;
      void main(){ vec4 wp = modelMatrix * vec4(position,1.0); vWorld = wp.xyz; vUv = uv;
        gl_Position = projectionMatrix * viewMatrix * wp; }`,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      uniform sampler2D uDetail;
      varying vec2 vUv;
      void main() {
        float v = vUv.y;
        // fine vertical threads scrolling down, thinning as the fall breaks up
        vec2 p = vec2(vUv.x * 3.0, v * 2.2 + uTime * 0.6);
        float streak = texture2D(uDetail, p).r * 0.7 + texture2D(uDetail, p * vec2(4.0, 2.6) + 0.3).g * 0.6;
        float threads = 0.55 + 0.45 * sin(vUv.x * 46.0 + streak * 7.0);
        float body = smoothstep(0.30, 0.62, streak * 0.8 + threads * 0.35 + (1.0 - v) * 0.12);
        float sides = smoothstep(0.0, 0.22, vUv.x) * smoothstep(1.0, 0.78, vUv.x);
        float lip = smoothstep(0.93, 1.0, v);
        float alpha = clamp(body * sides * (0.42 + 0.5 * v) + lip * 0.75, 0.0, 1.0);
        alpha *= mix(0.9, 0.22, smoothstep(0.45, 0.0, v));   // breaks into spray
        vec3 color = mix(vec3(0.72, 0.82, 0.86), vec3(1.0), lip * 0.8 + 0.2);
        color *= 0.45 + 0.75 * uSunColor;
        vec3 viewDir = normalize(cameraPosition - vWorld);
        color = applyAtmos(color, vWorld, -viewDir);
        gl_FragColor = vec4(color * uExposure, alpha * 0.92);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
  });
  const mesh = new THREE.Mesh(g, mat);
  mesh.name = "falls";
  mesh.renderOrder = 4;
  return mesh;
}
