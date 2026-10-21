/* island-water.js — ocean, lagoon, river, lake and waterfalls.

   The ocean shader reads a baked depth texture of the island, which is what
   gives the lagoon its turquoise shallows, puts a foam line exactly on the
   waterline and lets surf gather where the sea meets a cliff. Every animated
   term is driven by the uTime uniform, so a frame at t is the same frame
   whenever it is asked for. */
import * as THREE from "three";
import { ATMOS_PARS, PAL } from "./island-terrain.js";
import { clamp, mix, RIVER, FALLS, riverSample, heightAt } from "./island-layout.js";
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
        const ring = Math.max(0, 1 - Math.abs(d - r + 4) / 22);
        land[j * res + i] = Math.max(land[j * res + i], 7 * ring);
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
    const v0 = b.vert(ax + px * w0, y0, az + pz * w0, 0, 1, 0, c0, 1, 1, 1);
    const v1 = b.vert(ax - px * w0, y0, az - pz * w0, 0, 1, 0, c0, 1, 1, 1);
    const v2 = b.vert(bx - px * w1, y1, bz - pz * w1, 0, 1, 0, c1, 1, 1, 1);
    const v3 = b.vert(bx + px * w1, y1, bz + pz * w1, 0, 1, 0, c1, 1, 1, 1);
    b.quad(v0, v3, v2, v1);
  }
  // crater lake
  const lake = { x: -130, z: -830, r: 118, y: 290 };
  const c = b.vert(lake.x, lake.y, lake.z, 0, 1, 0, [0.04, 0.09, 0.1], 1, 1, 1);
  const ring = [];
  for (let i = 0; i < 28; i++) {
    const a = (i / 28) * Math.PI * 2;
    ring.push(b.vert(lake.x + Math.cos(a) * lake.r, lake.y, lake.z + Math.sin(a) * lake.r, 0, 1, 0, [0.05, 0.1, 0.11], 1, 1, 1));
  }
  for (let i = 0; i < 28; i++) b.tri(c, ring[(i + 1) % 28], ring[i]);
  // marsh pools: one low sheet, the mud shows through wherever it is higher
  const M = { x: -740, z: 520, r: 360, y: 6.5 };
  const mc = b.vert(M.x, M.y, M.z, 0, 1, 0, [0.07, 0.085, 0.05], 1, 1, 1);
  const mring = [];
  for (let i = 0; i < 34; i++) {
    const a = (i / 34) * Math.PI * 2;
    const rr = M.r * (0.8 + 0.3 * Math.sin(a * 3.1 + 1.2));
    mring.push(b.vert(M.x + Math.cos(a) * rr, M.y, M.z + Math.sin(a) * rr, 0, 1, 0, [0.06, 0.08, 0.05], 1, 1, 1));
  }
  for (let i = 0; i < 34; i++) b.tri(mc, mring[(i + 1) % 34], mring[i]);

  const mat = new THREE.ShaderMaterial({
    uniforms,
    vertexShader: /* glsl */`
      varying vec3 vWorld; varying vec3 vColor;
      void main() {
        vec4 wp = modelMatrix * vec4(position, 1.0);
        vWorld = wp.xyz; vColor = color;
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      ${WATER_PARS}
      varying vec3 vColor;
      void main() {
        vec3 viewDir = normalize(cameraPosition - vWorld);
        vec3 n = waterNormal(vWorld.xz, uTime * 1.6, 0.09, 0.02);
        float fres = pow(1.0 - clamp(dot(n, viewDir), 0.0, 1.0), 4.0);
        vec3 refl = reflect(-viewDir, n);
        vec3 sky = skyAt(normalize(vec3(refl.x, abs(refl.y) + 0.02, refl.z))) * 0.8;
        vec3 color = mix(vColor, sky, clamp(fres * 0.85 + 0.1, 0.0, 1.0));
        float toSun = max(0.0, dot(reflect(-viewDir, n), uSunDir));
        color += uSunColor * pow(toSun, 48.0) * 0.9;
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
    const x0 = f.x + dx * 10, z0 = f.z + dz * 10;
    const a = push(x0 + px * f.w, top + 3, z0 + pz * f.w, 0, 1);
    const b2 = push(x0 - px * f.w, top + 3, z0 - pz * f.w, 1, 1);
    const c = push(x0 - px * f.w * 1.45 + dx * 16, top - drop, z0 - pz * f.w * 1.45 + dz * 16, 1, 0);
    const d = push(x0 + px * f.w * 1.45 + dx * 16, top - drop, z0 + pz * f.w * 1.45 + dz * 16, 0, 0);
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
        vec2 p = vec2(vUv.x * 2.0, v * 1.6 + uTime * 0.55);
        float streak = texture2D(uDetail, p).r * 0.6 + texture2D(uDetail, p * vec2(3.0, 2.0) + 0.3).g * 0.5;
        float body = smoothstep(0.08, 0.3, streak + (1.0 - v) * 0.35);
        float sides = smoothstep(0.0, 0.16, vUv.x) * smoothstep(1.0, 0.84, vUv.x);
        float lip = smoothstep(0.86, 1.0, v);
        float alpha = clamp(body * sides * (0.55 + 0.45 * v) + lip * 0.8, 0.0, 1.0);
        alpha *= mix(0.95, 0.35, smoothstep(0.35, 0.0, v));   // breaks into spray
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
