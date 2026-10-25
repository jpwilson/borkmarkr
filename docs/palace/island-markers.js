/* island-markers.js — one marker per bookmark, in its zone.

   Expedition camps, carved totems, banners, torches and cairns, instanced by
   kind. Each marker also carries a small warm glow that holds a minimum size
   on screen, so from the air a zone reads as a scatter of campfires rather
   than disappearing into the canopy. */
import * as THREE from "three";
import { ATMOS_PARS, sampleGrid } from "./island-terrain.js";
import { Build } from "./island-props.js";
import { clamp, mix } from "./island-layout.js";

const CANVAS = [0.30, 0.25, 0.165], CANVAS_LIT = [0.47, 0.40, 0.27];
const WOOD = [0.16, 0.115, 0.075], WOOD_LIT = [0.3, 0.22, 0.14];
const CLOTH = [0.72, 0.26, 0.13];
const STONE = [0.42, 0.4, 0.36];

function instancedMaterial(uniforms) {
  return new THREE.ShaderMaterial({
    uniforms,
    vertexShader: /* glsl */`
      attribute vec3 ilit;
      varying vec3 vWorld; varying vec3 vNormal; varying vec3 vColor; varying vec3 vLit;
      void main() {
        vec4 wp = modelMatrix * instanceMatrix * vec4(position, 1.0);
        vWorld = wp.xyz;
        vNormal = normalize(mat3(instanceMatrix) * normal);
        vColor = color * instanceColor;
        vLit = ilit;
        gl_Position = projectionMatrix * viewMatrix * wp;
      }
    `,
    fragmentShader: /* glsl */`
      ${ATMOS_PARS}
      varying vec3 vNormal; varying vec3 vColor; varying vec3 vLit;
      void main() {
        vec3 n = normalize(vNormal);
        vec3 viewDir = normalize(cameraPosition - vWorld);
        float sun = clamp(dot(n, uSunDir) * 0.75 + 0.25, 0.0, 1.0) * mix(0.3, 1.0, vLit.x);
        vec3 light = uSunColor * sun + uSkyColor * (0.4 + 0.3 * n.y) * vLit.y + uGroundColor * 0.12;
        vec3 color = vColor * light;
        vec3 hv = normalize(uSunDir + viewDir);
        color += uSunColor * pow(max(dot(n, hv), 0.0), 30.0) * 0.12 * vLit.x;
        color = applyAtmos(color, vWorld, -viewDir);
        gl_FragColor = vec4(color * uExposure, 1.0);
        #include <tonemapping_fragment>
        #include <colorspace_fragment>
      }
    `,
    vertexColors: true,
  });
}

/* ── the five marker shapes, each about a storey tall ───────────────────── */
function geoFor(kind) {
  const b = new Build();
  const one = (c) => c;
  if (kind === "camp") {
    // ridge tent: two canvas slopes, two dark ends, a guy pole
    const L = 0.75, W = 0.6, H = 0.78;
    const apexA = b.vert(-L, H, 0, 0, 1, 0, CANVAS_LIT, 1, 1);
    const apexB = b.vert(L, H, 0, 0, 1, 0, CANVAS_LIT, 1, 1);
    const f1 = b.vert(-L, 0, -W, 0, 0.4, -1, CANVAS, 1, 0.75);
    const f2 = b.vert(L, 0, -W, 0, 0.4, -1, CANVAS, 1, 0.75);
    const f3 = b.vert(L, 0, W, 0, 0.4, 1, CANVAS, 1, 0.75);
    const f4 = b.vert(-L, 0, W, 0, 0.4, 1, CANVAS, 1, 0.75);
    b.quad(apexA, apexB, f2, f1);
    b.quad(apexB, apexA, f4, f3);
    const e1 = b.vert(-L, H, 0, -1, 0.2, 0, [0.1, 0.08, 0.06], 1, 0.6);
    const e2 = b.vert(-L, 0, -W, -1, 0.2, 0, [0.09, 0.07, 0.05], 1, 0.6);
    const e3 = b.vert(-L, 0, W, -1, 0.2, 0, [0.09, 0.07, 0.05], 1, 0.6);
    b.tri(e1, e2, e3);
    b.cylinder(L + 0.5, 0, 0, 0.045, 0.035, 1.25, 5, WOOD, 1);
    b.box(L + 0.5, 1.3, 0.16, 0.04, 0.26, 0.34, 0.2, CLOTH, 1);
  } else if (kind === "totem") {
    b.box(0, 0.12, 0, 0.62, 0.24, 0.62, 0.3, STONE, 1, 0.8);
    b.box(0, 0.5, 0, 0.42, 0.6, 0.42, 0.12, WOOD_LIT, 1, 0.9);
    b.box(0, 1.0, 0, 0.5, 0.42, 0.5, -0.25, WOOD, 1, 0.9);
    b.box(0, 1.34, 0, 0.36, 0.3, 0.36, 0.5, [0.5, 0.42, 0.3], 1, 1);
    b.box(0.0, 1.62, 0, 0.72, 0.1, 0.16, 0.1, WOOD_LIT, 1, 1);
  } else if (kind === "banner") {
    b.cylinder(0, 0, 0, 0.05, 0.04, 1.75, 5, WOOD, 1);
    const top = 1.68, dropH = 0.95, w = 0.62;
    const a = b.vert(0.04, top, 0, 0, 0, 1, CLOTH, 1, 1);
    const c = b.vert(0.04 + w, top - 0.1, 0, 0, 0, 1, [CLOTH[0] * 1.15, CLOTH[1] * 1.15, CLOTH[2] * 1.15], 1, 1);
    const d = b.vert(0.04 + w, top - dropH - 0.12, 0, 0, 0, 1, [CLOTH[0] * 0.75, CLOTH[1] * 0.7, CLOTH[2] * 0.7], 1, 0.8);
    const e = b.vert(0.04, top - dropH, 0, 0, 0, 1, [CLOTH[0] * 0.8, CLOTH[1] * 0.75, CLOTH[2] * 0.75], 1, 0.8);
    b.quad(a, c, d, e);
    b.quad(e, d, c, a);
    b.box(0, 0.08, 0, 0.44, 0.16, 0.44, 0.4, STONE, 1, 0.8);
  } else if (kind === "torch") {
    b.box(0, 0.1, 0, 0.4, 0.2, 0.4, 0.25, STONE, 1, 0.8);
    b.cylinder(0, 0.16, 0, 0.06, 0.045, 1.5, 6, WOOD, 1);
    b.cylinder(0, 1.6, 0, 0.14, 0.1, 0.22, 7, [0.22, 0.16, 0.1], 1);
  } else {
    // cairn
    let y = 0;
    const sizes = [0.72, 0.56, 0.44, 0.3];
    sizes.forEach((s, i) => {
      b.box(0, y + s * 0.3, 0, s, s * 0.6, s * 0.86, i * 1.1, [STONE[0] * (1 - i * 0.06), STONE[1] * (1 - i * 0.05), STONE[2] * (1 - i * 0.04)], 1, 0.9 - i * 0.08);
      y += s * 0.6;
    });
  }
  return b.geometry();
}

/* A camp is a camp, not a circus: about a storey and a half on the ground.
   From the air the warm glow below carries them, not their silhouettes. */
const KIND_SCALE = { camp: 6.0, totem: 5.4, banner: 6.2, torch: 5.6, cairn: 4.6 };

export function buildMarkers(field, layout, uniforms) {
  const group = new THREE.Group();
  group.name = "markers";
  const byKind = new Map();
  layout.markers.forEach((m, i) => {
    if (!byKind.has(m.kind)) byKind.set(m.kind, []);
    m.index = i;
    byKind.get(m.kind).push(m);
  });
  const meshes = [];
  for (const [kind, list] of byKind) {
    const geo = geoFor(kind);
    const mesh = new THREE.InstancedMesh(geo, instancedMaterial(uniforms), list.length);
    const lit = new Float32Array(list.length * 3);
    const mtx = new THREE.Matrix4(), q = new THREE.Quaternion(), p = new THREE.Vector3(), s = new THREE.Vector3();
    const axis = new THREE.Vector3(0, 1, 0), col = new THREE.Color();
    list.forEach((m, i) => {
      const scale = KIND_SCALE[kind] * (0.9 + 0.2 * ((m.index * 37) % 10) / 10);
      q.setFromAxisAngle(axis, m.yaw);
      p.set(m.x, m.y, m.z);
      s.setScalar(scale);
      mtx.compose(p, q, s);
      mesh.setMatrixAt(i, mtx);
      col.setRGB(1, 1, 1);
      mesh.setColorAt(i, col);
      const shade = clamp(sampleGrid(field, field.shade, m.x, m.z) * 0.55 + 0.45, 0, 1);
      lit[i * 3] = shade; lit[i * 3 + 1] = clamp(sampleGrid(field, field.ao, m.x, m.z), 0, 1); lit[i * 3 + 2] = 0;
      m.worldY = m.y + scale * 1.3;
      m.mesh = mesh; m.slot = i;
    });
    mesh.geometry.setAttribute("ilit", new THREE.InstancedBufferAttribute(lit, 3));
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    mesh.name = `marker-${kind}`;
    mesh.userData.tris = (geo.index.count / 3) * list.length;
    group.add(mesh);
    meshes.push(mesh);
  }
  group.add(buildGlow(layout, uniforms));
  group.userData.meshes = meshes;
  return group;
}

/* ── the warm dot that keeps a marker on screen from altitude ───────────── */
function buildGlow(layout, uniforms) {
  const n = layout.markers.length;
  const pos = new Float32Array(n * 4 * 3);
  const corner = new Float32Array(n * 4 * 2);
  const params = new Float32Array(n * 4 * 2);
  const idx = [];
  const corners = [[-1, -1], [1, -1], [1, 1], [-1, 1]];
  layout.markers.forEach((m, i) => {
    for (let c = 0; c < 4; c++) {
      const v = i * 4 + c;
      pos[v * 3] = m.x; pos[v * 3 + 1] = m.y + 5; pos[v * 3 + 2] = m.z;
      corner[v * 2] = corners[c][0]; corner[v * 2 + 1] = corners[c][1];
      params[v * 2] = (i % 97) / 97;
      params[v * 2 + 1] = m.kind === "torch" ? 1.25 : 1;
    }
    const b = i * 4;
    idx.push(b, b + 1, b + 2, b, b + 2, b + 3);
  });
  const g = new THREE.BufferGeometry();
  g.setAttribute("position", new THREE.BufferAttribute(pos, 3));
  g.setAttribute("corner", new THREE.BufferAttribute(corner, 2));
  g.setAttribute("params", new THREE.BufferAttribute(params, 2));
  g.setIndex(idx);
  g.computeBoundingSphere();
  const mat = new THREE.ShaderMaterial({
    uniforms: { ...uniforms, uSelected: { value: -1 }, uGlow: { value: 1 } },
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
    vertexShader: /* glsl */`
      attribute vec2 corner; attribute vec2 params;
      uniform float uTime;
      varying vec2 vUv; varying float vFlicker; varying float vNear;
      void main() {
        vec3 c = position;
        float dist = length(c - cameraPosition);
        // A world-space ember that never drops below a readable pixel size —
        // but the floor is for altitude. Up close it is a campfire standing
        // next to a tent, and at 3.4 m it burned the tent out.
        float size = max(mix(1.1, 4.6, smoothstep(90.0, 520.0, dist)), dist * 0.0078) * params.y;
        vNear = smoothstep(26.0, 130.0, dist);
        vec3 right = vec3(viewMatrix[0][0], viewMatrix[1][0], viewMatrix[2][0]);
        vec3 up = vec3(viewMatrix[0][1], viewMatrix[1][1], viewMatrix[2][1]);
        vec3 world = c + right * corner.x * size + up * corner.y * size;
        vUv = corner;
        // a fire flicker over a slow breath, so a camp reads as lit rather
        // than as a dot: the slow term is what the eye picks up from altitude
        vFlicker = (0.74 + 0.26 * sin(uTime * 6.1 + params.x * 40.0) * sin(uTime * 2.7 + params.x * 11.0))
                 * (0.84 + 0.30 * sin(uTime * 1.15 + params.x * 6.3));
        gl_Position = projectionMatrix * viewMatrix * vec4(world, 1.0);
      }
    `,
    fragmentShader: /* glsl */`
      uniform float uGlow;
      varying vec2 vUv; varying float vFlicker; varying float vNear;
      void main() {
        float r = length(vUv);
        float core = smoothstep(0.5, 0.0, r);
        float halo = smoothstep(1.0, 0.1, r);
        float glow = smoothstep(1.0, 0.45, r);
        vec3 color = mix(vec3(1.0, 0.44, 0.13), vec3(1.0, 0.94, 0.78), core);
        float a = (halo * 0.26 + glow * 0.26 + core * 1.05) * vFlicker * uGlow * mix(0.3, 1.0, vNear);
        gl_FragColor = vec4(color * a, a);
      }
    `,
  });
  const mesh = new THREE.Mesh(g, mat);
  mesh.name = "marker-glow";
  mesh.renderOrder = 11;
  mesh.frustumCulled = false;
  return mesh;
}

/* A ring drawn on the ground under the selected marker. */
export function buildSelectRing(uniforms) {
  const g = new THREE.RingGeometry(0.72, 1, 48);
  g.rotateX(-Math.PI / 2);
  const mat = new THREE.ShaderMaterial({
    uniforms: { ...uniforms, uRing: { value: 1 } },
    transparent: true,
    depthWrite: false,
    vertexShader: `varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }`,
    fragmentShader: `uniform float uTime; varying vec2 vUv;
      void main(){
        float pulse = 0.65 + 0.35 * sin(uTime * 2.2);
        gl_FragColor = vec4(vec3(1.0, 0.86, 0.66) * pulse, 0.85 * pulse);
      }`,
  });
  const mesh = new THREE.Mesh(g, mat);
  mesh.name = "select-ring";
  mesh.visible = false;
  mesh.renderOrder = 12;
  return mesh;
}
