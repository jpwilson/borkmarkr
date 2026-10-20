/* Bookmark cards: one InstancedMesh for every card in the palace, faces in a
   single texture array, plus an additive glow and a floor reflection that
   reuse the same instances. Floating and hover lift happen in the vertex
   shader, so animating 150+ cards costs nothing on the CPU. */
import * as THREE from "three";
import { DIM, wallPoint } from "./layout.js";
import { CARD_PX, drawCard, canvas } from "./art.js";

const W = DIM.card.w, H = DIM.card.h;

const VERT = /* glsl */`
  attribute float aLayer;
  attribute vec3 aAccent;
  attribute float aPhase;
  attribute float aHover;
  uniform float uTime;
  uniform float uMirror;
  uniform float uFloat;
  uniform float uGrow;
  uniform float uBack;
  varying vec2 vUv;
  varying float vLayer;
  varying vec3 vAccent;
  varying float vHover;
  varying float vDim;
  #include <common>
  #include <fog_pars_vertex>
  void main() {
    vUv = uv;
    vLayer = aLayer;
    vAccent = aAccent;
    vHover = aHover;
    vec3 p = position * uGrow;
    p.z -= uBack;
    float sway = sin(uTime * 0.55 + aPhase * 11.0) * 0.035 * uFloat;
    float c = cos(sway), s = sin(sway);
    p = vec3(c * p.x + s * p.z, p.y, -s * p.x + c * p.z);
    p.xy *= 1.0 + aHover * 0.1;
    p.z += aHover * 0.38;
    p.y += sin(uTime * 0.9 + aPhase * 6.2831) * 0.05 * uFloat;
    vec4 world = modelMatrix * instanceMatrix * vec4(p, 1.0);
    vDim = 1.0;
    if (uMirror > 0.5) { vDim = clamp(1.0 - world.y * 0.16, 0.0, 1.0); world.y = -world.y; }
    vec4 mvPosition = viewMatrix * world;
    gl_Position = projectionMatrix * mvPosition;
    #include <fog_vertex>
  }`;

const SDF = /* glsl */`
  float sdRound(vec2 p, vec2 b, float r) {
    vec2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
  }`;

const FACE_FRAG = /* glsl */`
  precision highp sampler2DArray;
  uniform sampler2DArray uMap;
  uniform float uFace;
  uniform float uRim;
  uniform float uMirror;
  uniform float uFocus;
  varying vec2 vUv;
  varying float vLayer;
  varying vec3 vAccent;
  varying float vHover;
  varying float vDim;
  #include <common>
  #include <fog_pars_fragment>
  ${SDF}
  void main() {
    vec2 hb = vec2(${(W / 2).toFixed(3)}, ${(H / 2).toFixed(3)});
    vec2 p = (vUv - 0.5) * hb * 2.0;
    float d = sdRound(p, hb, 0.075);
    float aa = max(fwidth(d), 1e-4);
    float mask = 1.0 - smoothstep(-aa, aa, d);
    if (mask < 0.02) discard;
    vec3 col;
    if (gl_FrontFacing || uMirror > 0.5) {
      col = texture(uMap, vec3(vUv.x, 1.0 - vUv.y, vLayer)).rgb * uFace;
    } else {
      col = mix(vec3(0.62, 0.56, 0.5), vAccent, 0.25) * 0.42;
    }
    float rim = smoothstep(-0.03 - vHover * 0.012, -0.004, d);
    col = mix(col, vAccent * (uRim + vHover * 1.1), rim * 0.9);
    col *= mix(1.0, 0.66 + 0.34 * vHover, uFocus);
    gl_FragColor = vec4(col * vDim, mask);
    #include <fog_fragment>
  }`;

const GLOW_FRAG = /* glsl */`
  uniform float uGlow;
  uniform float uFocus;
  varying vec2 vUv;
  varying vec3 vAccent;
  varying float vHover;
  varying float vDim;
  #include <common>
  #include <fog_pars_fragment>
  ${SDF}
  void main() {
    vec2 size = vec2(${W.toFixed(3)}, ${H.toFixed(3)}) * 1.6;
    vec2 p = (vUv - 0.5) * size;
    float d = sdRound(p, vec2(${(W / 2).toFixed(3)}, ${(H / 2).toFixed(3)}), 0.075);
    float g = exp(-max(d, 0.0) * 9.0) * smoothstep(-0.02, 0.03, d);
    vec3 col = mix(vec3(1.0, 0.72, 0.5), vAccent, 0.55) * g * uGlow * (1.0 + vHover * 0.6) * vDim;
    col *= mix(1.0, 0.45 + 0.55 * vHover, uFocus);
    #ifdef USE_FOG
      #ifdef FOG_EXP2
        col *= exp(-fogDensity * fogDensity * vFogDepth * vFogDepth);
      #else
        col *= 1.0 - smoothstep(fogNear, fogFar, vFogDepth);
      #endif
    #endif
    gl_FragColor = vec4(col, 1.0);
  }`;

function accentLinear(hue) {
  return new THREE.Color().setHSL(hue / 360, 0.75, 0.56, THREE.SRGBColorSpace);
}

export function buildCards(L, { renderer, tier }) {
  const items = [];
  for (const room of L.rooms) for (const shelf of room.shelves) for (const slot of shelf.cards) {
    const p = wallPoint(room, slot.s, slot.y, DIM.card.standoff);
    const toe = -Math.atan(slot.s / 11) * 0.28;
    items.push({ card: slot.card, room, shelf, pos: p, yaw: toe });
  }
  const count = Math.max(items.length, 1);
  const scale = tier === "low" ? 0.625 : 1;
  const tw = Math.round(CARD_PX.w * scale), th = Math.round(CARD_PX.h * scale);
  const data = new Uint8Array(tw * th * 4 * count);
  const { c, g } = canvas(CARD_PX.w, CARD_PX.h, { readback: scale === 1 });
  const small = scale < 1 ? canvas(tw, th, { readback: true }) : null;
  items.forEach((it, i) => {
    drawCard(g, it.card);
    let src = g;
    if (small) { small.g.clearRect(0, 0, tw, th); small.g.drawImage(c, 0, 0, tw, th); src = small.g; }
    data.set(src.getImageData(0, 0, tw, th).data, i * tw * th * 4);
  });
  const map = new THREE.DataArrayTexture(data, tw, th, count);
  map.format = THREE.RGBAFormat;
  map.type = THREE.UnsignedByteType;
  map.colorSpace = THREE.SRGBColorSpace;
  map.minFilter = THREE.LinearMipmapLinearFilter;
  map.magFilter = THREE.LinearFilter;
  map.generateMipmaps = true;
  map.anisotropy = Math.min(8, renderer.capabilities.getMaxAnisotropy());
  map.needsUpdate = true;

  const geo = new THREE.PlaneGeometry(W, H);
  const layer = new Float32Array(count), accent = new Float32Array(count * 3), phase = new Float32Array(count), hover = new Float32Array(count);
  const m = new THREE.Matrix4(), q = new THREE.Quaternion(), basis = new THREE.Matrix4();
  const mesh = new THREE.InstancedMesh(geo, null, count);
  items.forEach((it, i) => {
    const room = it.room;
    const right = new THREE.Vector3(...room.right), up = new THREE.Vector3(0, 1, 0), n = new THREE.Vector3(...room.normal);
    basis.makeBasis(right, up, n);
    q.setFromRotationMatrix(basis).multiply(new THREE.Quaternion().setFromAxisAngle(up, it.yaw));
    m.compose(new THREE.Vector3(...it.pos), q, new THREE.Vector3(1, 1, 1));
    mesh.setMatrixAt(i, m);
    layer[i] = i;
    const a = accentLinear(it.card.hue);
    accent.set([a.r, a.g, a.b], i * 3);
    phase[i] = ((i * 0.6180339) % 1);
  });
  geo.setAttribute("aLayer", new THREE.InstancedBufferAttribute(layer, 1));
  geo.setAttribute("aAccent", new THREE.InstancedBufferAttribute(accent, 3));
  geo.setAttribute("aPhase", new THREE.InstancedBufferAttribute(phase, 1));
  const hoverAttr = new THREE.InstancedBufferAttribute(hover, 1);
  hoverAttr.setUsage(THREE.DynamicDrawUsage);
  geo.setAttribute("aHover", hoverAttr);
  mesh.instanceMatrix.needsUpdate = true;
  mesh.count = items.length;
  mesh.frustumCulled = false;

  const shared = {
    uTime: { value: 0 }, uFloat: { value: 1 }, uFocus: { value: 0 },
  };
  const make = (frag, extra, opts) => new THREE.ShaderMaterial({
    uniforms: THREE.UniformsUtils.merge([THREE.UniformsLib.fog, extra]),
    vertexShader: VERT, fragmentShader: frag, fog: true, ...opts,
  });
  const faceUniforms = { uMap: { value: null }, uFace: { value: 0.9 }, uRim: { value: 2.1 }, uMirror: { value: 0 }, uGrow: { value: 1 }, uBack: { value: 0 } };
  const face = make(FACE_FRAG, faceUniforms, { side: THREE.DoubleSide, alphaToCoverage: tier !== "low", transparent: false });
  const glowUniforms = { uGlow: { value: 0.6 }, uMirror: { value: 0 }, uGrow: { value: 1.6 }, uBack: { value: 0.03 } };
  const glow = make(GLOW_FRAG, glowUniforms, { blending: THREE.AdditiveBlending, depthWrite: false, transparent: true, side: THREE.DoubleSide });
  const share = (mat) => Object.assign(mat.uniforms, shared);
  share(face); share(glow);
  face.uniforms.uMap.value = map;
  mesh.material = face;

  const halo = new THREE.InstancedMesh(geo, glow, count);
  halo.instanceMatrix = mesh.instanceMatrix;
  halo.count = items.length;
  halo.frustumCulled = false;
  halo.renderOrder = 2;

  const mirrors = [];
  if (tier !== "low") {
    const faceM = face.clone();
    faceM.uniforms.uMap.value = map;
    share(faceM);
    faceM.uniforms.uMirror = { value: 1 };
    faceM.uniforms.uFace = { value: 0.6 };
    faceM.alphaToCoverage = false;
    const glowM = glow.clone();
    share(glowM);
    glowM.uniforms.uMirror = { value: 1 };
    glowM.uniforms.uGlow = { value: 0.42 };
    for (const [mat, order] of [[faceM, -3], [glowM, -2]]) {
      const im = new THREE.InstancedMesh(geo, mat, count);
      im.instanceMatrix = mesh.instanceMatrix;
      im.count = items.length;
      im.frustumCulled = false;
      im.renderOrder = order;
      mirrors.push(im);
    }
  }

  const group = new THREE.Group();
  group.add(mesh, halo, ...mirrors);

  const target = new Float32Array(count);
  let hovered = -1;
  return {
    group, mesh, items, map,
    uniforms: shared,
    setHover(i) { hovered = i; for (let k = 0; k < target.length; k++) target[k] = k === i ? 1 : 0; },
    get hovered() { return hovered; },
    snapHover() { hover.set(target); hoverAttr.needsUpdate = true; shared.uFocus.value = hovered >= 0 ? 1 : 0; },
    update(t, dt) {
      shared.uTime.value = t;
      /* Focus rises fast and fades slowly, so sweeping the pointer across
         neighbouring cards doesn't flicker the whole wall. */
      const focus = hovered >= 0 ? 1 : 0, f = shared.uFocus.value;
      const rate = focus > f ? 8 : 2.5;
      shared.uFocus.value = Math.abs(focus - f) < 0.002 ? focus : f + (focus - f) * Math.min(1, dt * rate);
      let dirty = false;
      for (let k = 0; k < items.length; k++) {
        const v = hover[k], to = target[k];
        if (v === to) continue;
        const next = v + (to - v) * Math.min(1, dt * 10);
        hover[k] = Math.abs(next - to) < 0.002 ? to : next;
        dirty = true;
      }
      if (dirty) hoverAttr.needsUpdate = true;
    },
    dispose() {
      geo.dispose(); map.dispose(); face.dispose(); glow.dispose();
      for (const im of mirrors) im.material.dispose();
    },
  };
}
