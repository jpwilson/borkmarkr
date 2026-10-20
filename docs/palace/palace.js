/* Memory Palace — a library you can walk through.
   Rooms are topics, alcoves are subtopics, cards are bookmarks. This file
   owns the renderer, the camera (explore / map / tour / fly), picking and the
   HUD; geometry lives in world.js and cards.js, numbers in layout.js. */
import * as THREE from "three";
import { EffectComposer } from "three/addons/postprocessing/EffectComposer.js";
import { RenderPass } from "three/addons/postprocessing/RenderPass.js";
import { UnrealBloomPass } from "three/addons/postprocessing/UnrealBloomPass.js";
import { ShaderPass } from "three/addons/postprocessing/ShaderPass.js";
import { OutputPass } from "three/addons/postprocessing/OutputPass.js";
import { DIM, at, rightOf, computeLayout, views, tourPlan, routeBetween, roomAt } from "./layout.js";
import { buildWorld } from "./world.js";
import { buildCards } from "./cards.js";
import { Track } from "./tour.js";

const params = new URLSearchParams(location.search);
const CAPTURE = params.has("capture");
const $ = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
const lerp = (a, b, t) => a + (b - a) * t;
const ramp = (a, b, x) => { const t = clamp((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t); };
const plural = (n, one, many = `${one}s`) => `${Number(n).toLocaleString("en")} ${n === 1 ? one : many}`;
const UP = new THREE.Vector3(0, 1, 0);
const Data = typeof PalaceData !== "undefined" ? PalaceData : null;
const TAX = typeof TAXONOMY !== "undefined" ? TAXONOMY : [];

function webgl2() {
  try { return !!document.createElement("canvas").getContext("webgl2"); } catch { return false; }
}

async function boot() {
  const coarse = matchMedia("(pointer: coarse)").matches;
  const tier = ["high", "med", "low"].includes(params.get("tier")) ? params.get("tier") : CAPTURE ? "high" : coarse ? "low" : "med";
  document.body.classList.toggle("capture", CAPTURE);

  /* ── Renderer and post ── */
  const canvas = $("scene");
  const renderer = new THREE.WebGLRenderer({ canvas, antialias: false, stencil: false, powerPreference: "high-performance", preserveDrawingBuffer: CAPTURE });
  renderer.outputColorSpace = THREE.SRGBColorSpace;
  renderer.toneMapping = THREE.ACESFilmicToneMapping;
  renderer.toneMappingExposure = 1;
  renderer.shadowMap.enabled = true;
  renderer.shadowMap.type = THREE.PCFSoftShadowMap;
  renderer.shadowMap.autoUpdate = false;
  renderer.localClippingEnabled = true;

  const scene = new THREE.Scene();
  const FOG = new THREE.Color(0x1A120E);
  scene.background = FOG.clone();
  scene.fog = new THREE.FogExp2(FOG, 0.011);
  scene.environment = warmEnvironment(renderer);
  const camera = new THREE.PerspectiveCamera(55, innerWidth / innerHeight, 0.1, 800);

  const samples = params.has("msaa") ? clamp(Number(params.get("msaa")) || 0, 0, 8) : tier === "low" ? 0 : 4;
  const target = new THREE.WebGLRenderTarget(2, 2, { type: THREE.HalfFloatType, samples });
  const composer = new EffectComposer(renderer, target);
  composer.addPass(new RenderPass(scene, camera));
  const bloom = new UnrealBloomPass(new THREE.Vector2(2, 2), 0.6, 0.58, 0.92);
  composer.addPass(bloom);
  const finish = new ShaderPass(FINISH);
  composer.addPass(finish);
  composer.addPass(new OutputPass());

  let dpr = CAPTURE ? 1 : Math.min(devicePixelRatio || 1, tier === "low" ? 1.25 : 1.5);
  function resize() {
    const w = innerWidth, h = innerHeight;
    renderer.setPixelRatio(dpr);
    renderer.setSize(w, h, false);
    composer.setPixelRatio(dpr);
    composer.setSize(w, h);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
    finish.uniforms.uRes.value.set(w * dpr, h * dpr);
    if (S.L) {
      S.V = views(S.L, camera.aspect);
      if (S.mode !== "tour") { S.plan = tourPlan(S.L, camera.aspect); S.track = new Track(S.plan.keys); }
      S.world.setPixelRatio(dpr);
    }
    calloutSizes = null;
    captionRect = null;
  }

  /* ── State ── */
  const S = {
    model: null, L: null, world: null, cards: null, plan: null, track: null, V: null, hot: [],
    mode: "explore", place: { kind: "rotunda", facing: 0 },
    base: { p: new THREE.Vector3(), q: new THREE.Vector3(), fov: 55 },
    q: new THREE.Vector3(),
    look: { yaw: 0, pitch: 0, tyaw: 0, tpitch: 0 }, zoom: 1, tzoom: 1,
    mapYaw: 0, mapZoom: 1, tMapYaw: 0, tMapZoom: 1,
    fly: null, tourT: 0, capKey: null,
    hover: null, pointer: { x: -1, y: -1, dirty: false, down: null },
    mine: false, cut: -1, sunKey: "",
  };
  const pose = { p: new THREE.Vector3(), q: new THREE.Vector3(), fov: 55 };

  function setCamera(p, q, fov) {
    camera.position.copy(p);
    S.q.copy(q);
    camera.lookAt(q);
    camera.updateMatrixWorld();
    if (Math.abs(camera.fov - fov) > 1e-3) { camera.fov = fov; camera.updateProjectionMatrix(); }
  }

  function poseFor(place) {
    if (place.kind === "rotunda") return S.V.rotunda(place.facing ?? 0);
    if (place.kind === "room") return S.V.room(place.room);
    return S.V.overview;
  }
  function setBase(place) {
    const v = poseFor(place);
    S.base.p.set(...v.p); S.base.q.set(...v.q); S.base.fov = v.fov;
  }

  /* ── Building a palace from a model ── */
  function build(model) {
    if (S.world) {
      scene.remove(S.world.root, S.cards.group);
      S.world.dispose(); S.cards.dispose();
    }
    const L = computeLayout(model);
    S.model = model; S.L = L;
    S.world = buildWorld(L, { tier, renderer });
    S.cards = buildCards(L, { renderer, tier });
    scene.add(S.world.root, S.cards.group);
    S.V = views(L, camera.aspect);
    S.plan = tourPlan(L, camera.aspect);
    S.track = new Track(S.plan.keys);
    S.hot = hotspots(L);
    S.world.setPixelRatio(dpr);
    S.cut = -1; S.sunKey = "";
    S.mats = materialsOf(S.world.root);
    for (const m of S.mats) m.userData.envBase = m.envMapIntensity ?? 1;
    S.place = { kind: "rotunda", facing: 0 };
    setBase(S.place);
    S.mode = "explore";
    S.look = { yaw: 0, pitch: 0, tyaw: 0, tpitch: 0 };
    buildCallouts();
    updateChip();
    updateHUD();
  }

  function materialsOf(root) {
    const set = new Set();
    root.traverse((o) => { if (o.material && o.material.isMeshStandardMaterial) set.add(o.material); });
    return [...set];
  }

  function hotspots(L) {
    const mat = new THREE.MeshBasicMaterial({ side: THREE.DoubleSide });
    const door = new THREE.PlaneGeometry(DIM.doorW - 0.4, DIM.doorH - 0.3);
    const enf = new THREE.PlaneGeometry(DIM.enfW - 0.3, DIM.enfH - 0.3);
    const list = [];
    for (const room of L.rooms) {
      const d = new THREE.Mesh(door, mat);
      d.position.set(...at(L.R1 + L.T / 2, room.phi, (DIM.doorH - 0.3) / 2));
      d.lookAt(0, d.position.y, 0);
      d.userData = { kind: "door", room: room.index };
      const psi = room.phi - L.alpha / 2;
      const e = new THREE.Mesh(enf, mat);
      e.position.set(...at(L.pathR, psi, (DIM.enfH - 0.3) / 2));
      const r = rightOf(psi);
      e.lookAt(e.position.x + r[0], e.position.y, e.position.z + r[2]);
      e.userData = { kind: "enfilade", a: room.index, b: (room.index + 1) % L.N };
      for (const m of [d, e]) { m.updateMatrixWorld(true); list.push(m); }
    }
    return list;
  }

  /* ── Lighting that follows the camera out of the building ── */
  const sunIn = new THREE.Vector3(), sunOut = new THREE.Vector3(), sunDir = new THREE.Vector3(), sunAim = new THREE.Vector3();
  function atmosphere() {
    const W = S.world, L = S.L;
    const y = camera.position.y;
    const cut = S.mode === "map" || y > DIM.cutHero - 0.4 ? DIM.cutHero : 100;
    if (cut !== S.cut) { S.cut = cut; W.setCut(cut); renderer.shadowMap.needsUpdate = true; }
    const open = cut < 50 ? ramp(DIM.cutHero - 0.4, 34, y) : 0;
    /* Crossing the cut height swaps a roofed interior, sunlit only through
       the oculus, for an open one in full sun. Sun, shaft and floor
       reflections fade out just below the swap and the sun fades back in
       above it, so the swap itself happens with the sun off. */
    const sunK = cut < 50 ? ramp(DIM.cutHero - 0.4, 26, y) : 1 - ramp(6.4, DIM.cutHero - 0.4, y);
    sunIn.copy(W.sunInterior);
    const heroPhi = L.rooms[L.N - 1].phi + Math.PI;
    const az = heroPhi + Math.PI + 0.85, el = 0.62;
    sunOut.set(Math.cos(el) * Math.sin(az), Math.sin(el), Math.cos(el) * Math.cos(az));
    sunDir.copy(sunIn).lerp(sunOut, open).normalize();
    sunAim.set(...at(4.6, 0, 0)).multiplyScalar(1 - open);
    const key = `${sunDir.x.toFixed(4)},${sunDir.y.toFixed(4)},${sunDir.z.toFixed(4)}`;
    if (key !== S.sunKey) {
      S.sunKey = key;
      W.sun.position.copy(sunAim).addScaledVector(sunDir, 150);
      W.sun.target.position.copy(sunAim);
      W.sun.target.updateMatrixWorld();
      renderer.shadowMap.needsUpdate = true;
    }
    W.sun.intensity = lerp(6.5, 3.7, open) * sunK;
    W.hemi.intensity = lerp(0.16, 0.55, open);
    scene.fog.density = lerp(0.0105, 0.0034, open);
    renderer.toneMappingExposure = lerp(0.9, 0.86, open);
    bloom.strength = lerp(0.42, 0.3, open);
    bloom.radius = 0.42;
    bloom.threshold = lerp(1.0, 1.12, open);
    const env = lerp(0.2, 0.34, open);
    for (const m of S.mats) m.envMapIntensity = env * m.userData.envBase;
    W.setShaft(cut < 50 ? 0 : sunK);
    W.setReflection(sunK);
    S.open = open;
  }

  /* ── Camera per mode ── */
  function explorePose(t, dt) {
    const k = CAPTURE ? 1 : 1 - Math.exp(-dt * 9);
    S.look.yaw += (S.look.tyaw - S.look.yaw) * k;
    S.look.pitch += (S.look.tpitch - S.look.pitch) * k;
    S.zoom += (S.tzoom - S.zoom) * k;
    const dir = S.base.q.clone().sub(S.base.p);
    dir.applyAxisAngle(UP, S.look.yaw);
    const right = new THREE.Vector3().crossVectors(dir, UP).normalize();
    dir.applyAxisAngle(right, S.look.pitch);
    const p = S.base.p.clone();
    if (!CAPTURE) p.y += Math.sin(t * 0.7) * 0.02;
    setCamera(p, p.clone().add(dir), clamp(S.base.fov * S.zoom, 26, 70));
  }

  function mapPose(dt) {
    const k = CAPTURE ? 1 : 1 - Math.exp(-dt * 7);
    S.mapYaw += (S.tMapYaw - S.mapYaw) * k;
    S.mapZoom += (S.tMapZoom - S.mapZoom) * k;
    const o = S.V.overview;
    const p = new THREE.Vector3(...o.p).applyAxisAngle(UP, S.mapYaw).multiplyScalar(S.mapZoom);
    setCamera(p, new THREE.Vector3(...o.q), o.fov);
  }

  function placeFromCamera() {
    const p = camera.position, L = S.L;
    const r = Math.hypot(p.x, p.z), th = Math.atan2(p.x, p.z);
    if (p.y > DIM.cutHero - 0.4) return { kind: "overview" };
    if (r < L.R1 + L.T * 0.5) {
      const dir = S.q.clone().sub(p);
      return { kind: "rotunda", facing: roomAt(L, Math.atan2(dir.x, dir.z)).index };
    }
    return { kind: "room", room: roomAt(L, th).index };
  }

  function flyTo(place, opts = {}) {
    if (!S.L || S.mode === "tour") return;
    if (S.mode === "fly" && camera.position.y < DIM.cutHero) return;
    closePanel();
    const from = S.mode === "map" ? { kind: "overview" } : S.mode === "fly" ? S.fly.place : S.place;
    const dest = poseFor(place);
    const pts = routeBetween(S.L, from, place);
    const all = [...pts, dest.p];
    const keys = [{ t: 0, p: camera.position.toArray(), q: S.q.toArray(), fov: camera.fov }];
    let prev = camera.position.clone(), t = 0;
    all.forEach((p, i) => {
      const v = new THREE.Vector3(...p);
      t += Math.max(0.35, v.distanceTo(prev) / (opts.speed || 10));
      prev = v;
      const last = i === all.length - 1;
      const next = last ? null : all[i + 1];
      const q = last || place.kind === "overview" ? dest.q : [lerp(next[0], dest.q[0], 0.45), lerp(next[1], dest.q[1], 0.45), lerp(next[2], dest.q[2], 0.45)];
      keys.push({ t, p, q, fov: last ? dest.fov : lerp(camera.fov, dest.fov, (i + 1) / all.length) });
    });
    const want = clamp(t, opts.min ?? 1.2, opts.max ?? 4.4);
    for (const k of keys) k.t *= want / (t || 1);
    S.fly = { track: new Track(keys), t: 0, place };
    S.mode = "fly";
    S.look = { yaw: 0, pitch: 0, tyaw: 0, tpitch: 0 };
    S.tzoom = S.zoom = 1;
    setHover(null);
    updateHUD();
  }

  function arrive() {
    const place = S.fly.place;
    S.fly = null;
    if (place.kind === "overview") {
      S.mode = "map"; S.mapYaw = S.tMapYaw = 0; S.mapZoom = S.tMapZoom = 1;
    } else {
      S.mode = "explore"; S.place = place; setBase(place);
    }
    updateHUD();
  }

  /* ── Tour ── */
  function startTour() {
    if (!S.track) return;
    closePanel(); setHover(null);
    S.plan = tourPlan(S.L, camera.aspect);
    S.track = new Track(S.plan.keys);
    S.mode = "tour"; S.tourT = 0; S.capKey = null;
    updateHUD();
  }

  function stopTour(finished = false) {
    if (S.mode !== "tour") return;
    $("caption").style.opacity = 0;
    S.capKey = null;
    if (finished || camera.position.y > DIM.cutHero - 0.4) {
      S.mode = "map";
      flyTo({ kind: "overview" }, { min: 1.2, max: 1.6 });
    } else {
      S.mode = "explore";
      S.place = placeFromCamera();
      S.base.p.copy(camera.position); S.base.q.copy(S.q); S.base.fov = camera.fov;
    }
    updateHUD();
  }

  function tourCaption(t) {
    const c = S.plan.captions.find((x) => t >= x.from && t < x.to);
    const key = c ? `${c.kind}:${c.room ?? ""}` : "";
    if (key !== S.capKey) {
      S.capKey = key;
      if (c) fillCaption(c);
    }
    const o = c ? ramp(c.from, c.from + 0.5, t) * (1 - ramp(c.to - 0.5, c.to, t)) : 0;
    $("caption").style.opacity = o.toFixed(3);
    $("tour-progress").style.transform = `scaleX(${clamp(t / S.track.duration, 0, 1).toFixed(4)})`;
  }

  function fillCaption(c) {
    const M = S.model, rooms = M.rooms.length;
    let kicker = "", title = "", sub = "";
    if (c.kind === "title") {
      kicker = S.mine ? "Your memory palace" : "Bookmarker · Memory Palace";
      title = "Every link you save has a place.";
      sub = `${plural(M.total, "bookmark")} · ${plural(rooms, "room")} · one walk-through`;
    } else if (c.kind === "room") {
      const room = S.L.rooms[c.room];
      kicker = `Room ${c.room + 1} of ${S.L.N}`;
      if (room.data) {
        title = room.data.name;
        sub = `${plural(room.data.total, "bookmark")} · ${room.data.shelves.map((s) => s.name).join(" · ")}`;
      } else {
        title = "Room to grow";
        sub = "Save to a new topic and it gets a room here";
      }
    } else {
      kicker = "bookmarker.lol/palace";
      title = "Your whole library, at a glance.";
      sub = "Drag to orbit · click a room to walk in";
    }
    $("cap-kicker").textContent = kicker;
    $("cap-title").textContent = title;
    $("cap-sub").textContent = sub;
    $("caption").dataset.kind = c.kind;
    captionRect = null;
  }

  /* ── Room callouts for the map ── */
  let callouts = [], calloutSizes = null, captionRect = null;
  function buildCallouts() {
    const layer = $("callouts");
    layer.querySelectorAll(".callout").forEach((n) => n.remove());
    callouts = [];
    for (const room of S.L.rooms) {
      if (!room.data) continue;
      const el = document.createElement("button");
      el.className = "callout";
      el.type = "button";
      el.style.setProperty("--hue", room.data.hue);
      el.innerHTML = `<i></i><b></b><span></span>`;
      el.querySelector("b").textContent = room.data.name;
      el.querySelector("span").textContent = room.data.total.toLocaleString("en");
      el.title = `Walk into ${room.data.name}`;
      el.addEventListener("click", () => {
        if (S.mode === "tour") stopTour(true);
        flyTo({ kind: "room", room: room.index }, { max: 3.6 });
      });
      layer.appendChild(el);
      callouts.push({ el, room, anchor: new THREE.Vector3(...at((S.L.R1 + S.L.A) / 2 + 1, room.phi, DIM.cutHero + 0.3)) });
    }
    calloutSizes = null;
  }

  const proj = new THREE.Vector3();
  function layoutCallouts() {
    const alpha = S.mode === "map" ? 1 : ramp(20, 40, camera.position.y);
    const layer = $("callouts"), svg = $("leaders");
    layer.style.opacity = alpha.toFixed(3);
    layer.classList.toggle("live", alpha > 0.5);
    if (alpha <= 0.001) return;
    const W = innerWidth, H = innerHeight;
    if (!calloutSizes) calloutSizes = callouts.map((c) => [c.el.offsetWidth, c.el.offsetHeight]);
    const items = [];
    callouts.forEach((c, i) => {
      proj.copy(c.anchor).project(camera);
      const [w, h] = calloutSizes[i];
      const ax = (proj.x * 0.5 + 0.5) * W, ay = (-proj.y * 0.5 + 0.5) * H;
      items.push({ c, ax, ay, w, h, x: ax - w / 2, y: ay - h - 30, show: proj.z < 1 });
    });
    const top = 78, bottom = H - 96;
    /* A visible tour caption is a fixed obstacle: callouts move, it doesn't. */
    const cap = $("caption");
    const blocks = [];
    if (S.mode === "tour" && Number(cap.style.opacity) > 0.02) {
      if (!captionRect) {
        const r = cap.getBoundingClientRect();
        captionRect = { x: r.left - 16, y: r.top - 16, w: r.width + 32, h: r.height + 32 };
      }
      blocks.push(captionRect);
    }
    for (let it = 0; it < 60; it++) {
      let moved = false;
      for (let i = 0; i < items.length; i++) for (let j = i + 1; j < items.length; j++) {
        const a = items[i], b = items[j];
        const ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x) + 10;
        const oy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y) + 8;
        if (ox <= 0 || oy <= 0) continue;
        moved = true;
        if (oy <= ox) { const s = (oy / 2) * (a.y <= b.y ? 1 : -1); a.y -= s; b.y += s; }
        else { const s = (ox / 2) * (a.x <= b.x ? 1 : -1); a.x -= s; b.x += s; }
      }
      for (const a of items) for (const b of blocks) {
        const ox = Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x);
        const oy = Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y);
        if (ox <= 0 || oy <= 0) continue;
        moved = true;
        if (oy <= ox) a.y += a.y + a.h / 2 < b.y + b.h / 2 ? -oy : oy;
        else a.x += a.x + a.w / 2 < b.x + b.w / 2 ? -ox : ox;
      }
      for (const a of items) { a.x = clamp(a.x, 12, W - a.w - 12); a.y = clamp(a.y, top, bottom - a.h); }
      if (!moved) break;
    }
    for (const a of items) {
      if (blocks.some((b) => a.x < b.x + b.w && b.x < a.x + a.w && a.y < b.y + b.h && b.y < a.y + a.h)) a.show = false;
    }
    const placed = [];
    for (const a of [...items].sort((p, q) => q.c.room.data.total - p.c.room.data.total)) {
      if (a.show && placed.some((b) => a.x < b.x + b.w + 4 && b.x < a.x + a.w + 4 && a.y < b.y + b.h + 4 && b.y < a.y + a.h + 4)) a.show = false;
      if (a.show) placed.push(a);
    }
    let lines = "";
    for (const a of items) {
      a.c.el.style.transform = `translate(${a.x.toFixed(1)}px, ${a.y.toFixed(1)}px)`;
      a.c.el.style.visibility = a.show ? "visible" : "hidden";
      if (!a.show) continue;
      const lx = clamp(a.ax, a.x + 10, a.x + a.w - 10), ly = a.y + a.h;
      lines += `<line x1="${lx.toFixed(1)}" y1="${ly.toFixed(1)}" x2="${a.ax.toFixed(1)}" y2="${a.ay.toFixed(1)}"/><circle cx="${a.ax.toFixed(1)}" cy="${a.ay.toFixed(1)}" r="3.5"/>`;
    }
    svg.innerHTML = lines;
  }

  /* ── Picking ── */
  const ray = new THREE.Raycaster(), ndc = new THREE.Vector2();
  function pick(x, y) {
    if (!S.cards || S.mode !== "explore") return null;
    ndc.set((x / innerWidth) * 2 - 1, -(y / innerHeight) * 2 + 1);
    ray.setFromCamera(ndc, camera);
    let best = null;
    const card = ray.intersectObject(S.cards.mesh, false)[0];
    if (card) best = { kind: "card", index: card.instanceId, d: card.distance };
    const hot = ray.intersectObjects(S.hot, false)[0];
    if (hot && (!best || hot.distance < best.d)) best = { ...hot.object.userData, d: hot.distance };
    if (!best) return null;
    const wall = ray.intersectObjects(S.world.occluders, false)[0];
    if (wall && wall.distance < best.d - 0.05) return null;
    return best;
  }

  function setHover(h) {
    const same = (a, b) => (a && b ? a.kind === b.kind && a.index === b.index && a.room === b.room && a.a === b.a : a === b);
    if (same(h, S.hover)) return;
    S.hover = h;
    S.cards?.setHover(h && h.kind === "card" ? h.index : -1);
    canvas.style.cursor = h ? "pointer" : S.pointer.down ? "grabbing" : "grab";
    const tip = $("tip");
    if (!h) { tip.classList.remove("on"); return; }
    if (h.kind === "card") {
      const c = S.cards.items[h.index].card;
      tip.innerHTML = `<b></b><span>Click to open</span>`;
      tip.querySelector("b").textContent = c.sourceLabel;
    } else {
      const j = h.kind === "door" ? h.room : otherRoom(h);
      const room = S.L.rooms[j];
      tip.innerHTML = `<b></b><span></span>`;
      tip.querySelector("b").textContent = room.data ? room.data.name : "Empty room";
      tip.querySelector("span").textContent = h.kind === "door" ? "Enter →" : "Walk through →";
    }
    tip.classList.add("on");
  }

  function otherRoom(h) {
    const cur = S.place.kind === "room" ? S.place.room : h.a;
    return cur === h.a ? h.b : h.a;
  }

  function placeTip(x, y) {
    const tip = $("tip");
    const w = tip.offsetWidth, hgt = tip.offsetHeight;
    const tx = clamp(x + 16, 8, innerWidth - w - 8), ty = clamp(y + 18, 8, innerHeight - hgt - 8);
    tip.style.transform = `translate(${tx}px, ${ty}px)`;
  }

  function activate(h) {
    if (!h) return;
    if (h.kind === "card") openPanel(h.index);
    else if (h.kind === "door") flyTo({ kind: "room", room: h.room });
    else flyTo({ kind: "room", room: otherRoom(h) });
  }

  /* ── Info panel ── */
  function openPanel(i) {
    const it = S.cards.items[i], c = it.card;
    $("panel").dataset.src = c.source;
    $("panel-src").textContent = c.sourceLabel;
    $("panel-meta").textContent = c.meta || "";
    $("panel-title").textContent = c.title;
    $("panel-path").textContent = `${it.room.data.name} › ${it.shelf.shelf.name}`;
    const open = $("panel-open");
    open.href = c.url;
    open.textContent = c.source === "web" ? "Open link ↗" : `Open on ${c.sourceLabel} ↗`;
    $("panel-note").hidden = !S.model.demo;
    $("panel").classList.add("on");
    $("panel").setAttribute("aria-hidden", "false");
  }
  function closePanel() {
    $("panel").classList.remove("on");
    $("panel").setAttribute("aria-hidden", "true");
  }

  /* ── HUD ── */
  function updateChip() {
    const M = S.model;
    const shelves = M.rooms.reduce((n, r) => n + r.shelves.length, 0);
    $("chip-title").textContent = S.mine ? "Your palace" : "Demo palace";
    $("chip-sub").textContent = [
      plural(M.total, "bookmark"),
      M.shown < M.total ? `${M.shown.toLocaleString("en")} on display` : null,
      plural(M.rooms.length, "room"),
      plural(shelves, "shelf", "shelves"),
    ].filter(Boolean).join(" · ");
    $("btn-demo").hidden = !S.mine;
    $("btn-mine").hidden = S.mine;
  }

  function updateHUD() {
    const b = document.body;
    for (const m of ["explore", "map", "tour", "fly"]) b.classList.toggle(`mode-${m}`, S.mode === m);
    $("btn-tour").setAttribute("aria-pressed", String(S.mode === "tour"));
    $("btn-map").setAttribute("aria-pressed", String(S.mode === "map"));
    const place = S.mode === "fly" ? S.fly.place : S.mode === "map" ? { kind: "overview" } : S.place;
    let title = "Rotunda", sub = "";
    if (place.kind === "room") {
      const room = S.L.rooms[place.room];
      title = room.data ? room.data.name : "Room to grow";
      sub = room.data ? `${plural(room.data.total, "bookmark")} · ${plural(room.data.shelves.length, "shelf", "shelves")}` : "Empty for now";
    } else if (place.kind === "rotunda") {
      const room = S.L.rooms[place.facing ?? 0];
      sub = room.data ? `Facing ${room.data.name}` : "The entrance hall";
    } else {
      title = "Map"; sub = "Click a room to walk in";
    }
    $("nav-title").textContent = title;
    $("nav-sub").textContent = sub;
    if (S.mode !== "explore") setHover(null);
  }

  let toastTimer = 0;
  function toast(msg) {
    const t = $("toast");
    t.textContent = msg;
    t.classList.add("on");
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => t.classList.remove("on"), 4200);
  }

  function stepRoom(dir) {
    if (S.mode === "map") { S.tMapYaw += dir * S.L.alpha; return; }
    if (S.mode !== "explore") return;
    const N = S.L.N;
    if (S.place.kind === "room") flyTo({ kind: "room", room: (S.place.room + dir + N) % N });
    else if (S.place.kind === "rotunda") flyTo({ kind: "rotunda", facing: ((S.place.facing ?? 0) + dir + N) % N });
  }
  function goIn() {
    if (S.mode === "map") flyTo({ kind: "rotunda", facing: 0 }, { max: 3.4 });
    else if (S.mode === "explore" && S.place.kind === "rotunda") flyTo({ kind: "room", room: S.place.facing ?? 0 });
  }
  function goOut() {
    if (S.mode !== "explore") return;
    if (S.place.kind === "room") flyTo({ kind: "rotunda", facing: S.place.room });
    else flyTo({ kind: "overview" }, { max: 3.2 });
  }
  function toggleMap() {
    if (S.mode === "tour") stopTour();
    if (S.mode === "map") flyTo({ kind: "rotunda", facing: 0 }, { max: 3.4 });
    else if (S.mode === "explore") flyTo({ kind: "overview" }, { max: 3.2 });
  }

  /* ── Your own palace ── */
  function sessionPresent() { try { return !!Data.readSession(localStorage); } catch { return false; } }
  function refreshMineButton() {
    $("btn-mine").classList.toggle("signed-in", sessionPresent());
  }
  async function viewMine() {
    if (!sessionPresent()) { $("signin").hidden = false; return; }
    const btn = $("btn-mine");
    btn.disabled = true;
    btn.dataset.busy = "1";
    try {
      const { rows, customTopics } = await Data.loadOwnLibrary({ storage: localStorage, fetch: (...a) => fetch(...a) });
      const model = Data.buildModel(rows, { taxonomy: TAX, customTopics });
      if (!model.total) { toast("Your library is empty — save a few links, then come back."); return; }
      if (S.mode === "tour") stopTour();
      S.mine = true;
      build(model);
      toast(`Built from ${plural(model.total, "bookmark")} in your library.`);
    } catch (err) {
      if (err.status === 401) { $("signin").hidden = false; refreshMineButton(); }
      else toast(err.message || "Couldn't load your library.");
    } finally {
      btn.disabled = false;
      delete btn.dataset.busy;
    }
  }
  function viewDemo() {
    if (S.mode === "tour") stopTour();
    S.mine = false;
    build(Data.demoModel(TAX));
  }

  /* ── Input ── */
  canvas.addEventListener("pointerdown", (e) => {
    if (e.button !== 0) return;
    S.pointer.down = { x: e.clientX, y: e.clientY, yaw: S.look.tyaw, pitch: S.look.tpitch, mapYaw: S.tMapYaw, moved: false };
    canvas.setPointerCapture(e.pointerId);
    canvas.style.cursor = "grabbing";
  });
  canvas.addEventListener("pointermove", (e) => {
    S.pointer.x = e.clientX; S.pointer.y = e.clientY; S.pointer.dirty = true;
    const d = S.pointer.down;
    if (!d) return;
    const dx = e.clientX - d.x, dy = e.clientY - d.y;
    if (!d.moved && Math.hypot(dx, dy) > 6) d.moved = true;
    if (!d.moved) return;
    if (S.mode === "tour") stopTour();
    if (S.mode === "explore") {
      const yawLimit = S.place.kind === "room" ? 1.35 : Math.PI;
      S.look.tyaw = clamp(d.yaw + dx * 0.0042, -yawLimit, yawLimit);
      S.look.tpitch = clamp(d.pitch + dy * 0.0034, -0.42, 0.5);
    } else if (S.mode === "map") {
      S.tMapYaw = d.mapYaw - dx * 0.0055;
    }
  });
  const release = (e) => {
    const d = S.pointer.down;
    S.pointer.down = null;
    canvas.style.cursor = S.hover ? "pointer" : "grab";
    if (d && !d.moved && e.type === "pointerup") activate(pick(e.clientX, e.clientY));
  };
  canvas.addEventListener("pointerup", release);
  canvas.addEventListener("pointercancel", release);
  canvas.addEventListener("pointerleave", () => { S.pointer.x = -1; setHover(null); });
  canvas.addEventListener("wheel", (e) => {
    e.preventDefault();
    if (S.mode === "tour") return;
    if (S.mode === "explore") S.tzoom = clamp(S.tzoom * Math.exp(e.deltaY * 0.0011), 0.5, 1.15);
    else if (S.mode === "map") S.tMapZoom = clamp(S.tMapZoom * Math.exp(e.deltaY * 0.0009), 0.62, 1.4);
  }, { passive: false });

  addEventListener("keydown", (e) => {
    if (e.target.closest && e.target.closest("input, textarea, select")) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    const k = e.key;
    if (S.mode === "tour") { if (k === "Escape" || k === " ") { e.preventDefault(); stopTour(); } return; }
    if (k === "Escape" && $("panel").classList.contains("on")) { closePanel(); return; }
    if (k === "ArrowRight" || k === "d" || k === "D") stepRoom(1);
    else if (k === "ArrowLeft" || k === "a" || k === "A") stepRoom(-1);
    else if (k === "ArrowUp" || k === "w" || k === "W") goIn();
    else if (k === "ArrowDown" || k === "s" || k === "S" || k === "Escape") goOut();
    else if (k === "Enter" && S.hover) activate(S.hover);
    else if (k === "m" || k === "M") toggleMap();
    else if (k === "t" || k === "T") startTour();
    else return;
    e.preventDefault();
  });

  $("btn-tour").addEventListener("click", () => (S.mode === "tour" ? stopTour() : startTour()));
  $("tour-skip").addEventListener("click", () => stopTour());
  $("btn-map").addEventListener("click", toggleMap);
  $("btn-mine").addEventListener("click", viewMine);
  $("btn-demo").addEventListener("click", viewDemo);
  $("nav-prev").addEventListener("click", () => stepRoom(-1));
  $("nav-next").addEventListener("click", () => stepRoom(1));
  $("nav-out").addEventListener("click", () => (S.mode === "map" ? goIn() : goOut()));
  $("panel-close").addEventListener("click", closePanel);
  $("signin-close").addEventListener("click", () => { $("signin").hidden = true; });
  addEventListener("storage", (e) => { if (e.key === Data.SESSION_KEY) refreshMineButton(); });
  addEventListener("resize", resize);

  /* ── Frame ── */
  function update(t, dt) {
    if (S.mode === "tour") {
      S.track.sample(S.tourT, pose);
      setCamera(pose.p, pose.q, pose.fov);
      tourCaption(S.tourT);
    } else if (S.mode === "fly") {
      S.fly.track.sample(S.fly.t, pose);
      setCamera(pose.p, pose.q, pose.fov);
      if (S.fly.t >= S.fly.track.duration) arrive();
    } else if (S.mode === "map") {
      mapPose(dt);
    } else {
      explorePose(t, dt);
    }
    atmosphere();
    S.cards.update(t, dt);
    S.world.update(t);
    finish.uniforms.uTime.value = t;
    layoutCallouts();
    if (S.mode === "explore" && S.pointer.x >= 0 && (S.pointer.dirty || S.look.yaw !== S.look.tyaw) && !S.pointer.down) {
      S.pointer.dirty = false;
      setHover(pick(S.pointer.x, S.pointer.y));
      if (S.hover) placeTip(S.pointer.x, S.pointer.y);
    }
  }

  function render() { composer.render(); }

  /* ── Boot ── */
  resize();
  $("loading-text").textContent = "Setting the stones…";
  await Promise.race([
    Promise.all([
      document.fonts.load('800 64px "Bricolage Grotesque"'),
      document.fonts.load('700 40px "Bricolage Grotesque"'),
      document.fonts.load('600 24px "Instrument Sans"'),
      document.fonts.load('500 20px "Instrument Sans"'),
    ]),
    new Promise((r) => setTimeout(r, 3500)),
  ]);
  S.mine = false;
  build(Data.demoModel(TAX));
  refreshMineButton();
  resize();
  update(0, 0);
  render();
  $("loading").classList.add("done");
  setTimeout(() => { $("loading").hidden = true; }, 700);

  if (CAPTURE) {
    window.palace = {
      tier,
      duration: () => S.track.duration,
      plan: () => ({ duration: S.track.duration, heroAt: S.plan.heroAt, captions: S.plan.captions }),
      renderAt(t) {
        if (S.mode !== "tour") { S.mode = "tour"; S.capKey = null; updateHUD(); }
        S.tourT = t;
        update(t, 1 / 60);
        render();
        return true;
      },
      pose(name, o = {}) {
        closePanel();
        if (name === "overview") {
          S.mode = "map"; S.mapYaw = S.tMapYaw = o.yaw ?? 0; S.mapZoom = S.tMapZoom = o.zoom ?? 1;
          $("caption").style.opacity = 0;
        } else {
          S.mode = "explore";
          S.place = o.place || { kind: "room", room: o.room ?? 0 };
          setBase(S.place);
          S.look = { yaw: o.yaw ?? 0, pitch: o.pitch ?? 0, tyaw: o.yaw ?? 0, tpitch: o.pitch ?? 0 };
          S.zoom = S.tzoom = o.zoom ?? 1;
          if (o.p) { S.base.p.set(...o.p); S.base.q.set(...o.q); S.base.fov = o.fov ?? 55; }
          $("caption").style.opacity = 0;
        }
        updateHUD();
        setHover(null);
        update(o.t ?? 4, 1 / 60);
        if (name === "hover") {
          const i = o.card ?? S.cards.items.findIndex((it) => it.room.index === S.place.room);
          setHover({ kind: "card", index: i, d: 0 });
          S.cards.snapHover();
          const it = S.cards.items[i];
          proj.set(...it.pos).project(camera);
          const x = (proj.x * 0.5 + 0.5) * innerWidth, y = (-proj.y * 0.5 + 0.5) * innerHeight;
          placeTip(x + 40, y + 10);
          if (o.panel) openPanel(i);
        }
        update(o.t ?? 4, 1 / 60);
        render();
        return true;
      },
      cards: () => S.cards.items.map((it, i) => ({ i, room: it.room.index, title: it.card.title, source: it.card.source })),
      sync() {
        const gl = renderer.getContext(), px = new Uint8Array(4);
        gl.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
        return px[0];
      },
    };
    return;
  }

  setTimeout(() => $("hint").classList.add("on"), 900);
  setTimeout(() => $("hint").classList.remove("on"), 9000);
  if (params.get("tour") === "1") startTour();

  let last = performance.now(), clock = 0, slow = 0, acc = 0, frames = 0;
  function loop(now) {
    requestAnimationFrame(loop);
    const dt = Math.min(0.05, Math.max(0, (now - last) / 1000));
    last = now;
    clock += dt;
    if (S.mode === "tour") {
      S.tourT += dt;
      if (S.tourT >= S.track.duration) { S.tourT = S.track.duration; update(clock, dt); stopTour(true); }
    } else if (S.mode === "fly") {
      S.fly.t += dt;
    }
    update(clock, dt);
    render();
    acc += dt; frames++;
    if (acc >= 1) {
      const avg = acc / frames;
      acc = 0; frames = 0;
      slow = avg > 1 / 48 ? slow + 1 : 0;
      if (slow >= 2 && dpr > 0.75 && !document.hidden) {
        dpr = Math.max(0.75, +(dpr - 0.25).toFixed(2));
        slow = 0;
        resize();
      }
    }
  }
  requestAnimationFrame(loop);
}

/* Warm studio light for reflections: dark floor, amber ceiling glow. */
function warmEnvironment(renderer) {
  const env = new THREE.Scene();
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide, depthWrite: false,
    vertexShader: "varying vec3 vP; void main() { vP = position; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
    fragmentShader: `varying vec3 vP;
      void main() {
        vec3 d = normalize(vP);
        vec3 low = vec3(0.045, 0.03, 0.022), mid = vec3(0.36, 0.25, 0.17), top = vec3(1.05, 0.8, 0.56);
        vec3 c = d.y < 0.0 ? mix(mid, low, smoothstep(0.0, -0.45, d.y)) : mix(mid, top, smoothstep(0.0, 0.85, d.y));
        c += vec3(1.4, 1.0, 0.65) * pow(max(dot(d, normalize(vec3(0.5, 0.75, 0.4))), 0.0), 24.0);
        gl_FragColor = vec4(c, 1.0);
      }`,
  });
  env.add(new THREE.Mesh(new THREE.SphereGeometry(20, 48, 24), mat));
  const pm = new THREE.PMREMGenerator(renderer);
  const tex = pm.fromScene(env, 0.035).texture;
  pm.dispose();
  return tex;
}

const FINISH = {
  uniforms: { tDiffuse: { value: null }, uTime: { value: 0 }, uRes: { value: new THREE.Vector2(1, 1) }, uVignette: { value: 0.42 }, uGrain: { value: 0.012 } },
  vertexShader: "varying vec2 vUv; void main() { vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }",
  fragmentShader: `uniform sampler2D tDiffuse; uniform float uTime; uniform vec2 uRes; uniform float uVignette; uniform float uGrain; varying vec2 vUv;
    void main() {
      vec4 c = texture2D(tDiffuse, vUv);
      vec2 d = vUv - 0.5; d.x *= uRes.x / uRes.y;
      c.rgb *= mix(1.0, smoothstep(1.05, 0.28, length(d)), uVignette);
      float n = fract(sin(dot(floor(vUv * uRes) + fract(uTime * 7.31) * 113.0, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
      c.rgb += n * uGrain * (0.25 + c.rgb);
      gl_FragColor = c;
    }`,
};

if (!webgl2() || !Data) {
  $("loading").hidden = true;
  $("fallback").hidden = false;
} else {
  boot().catch((err) => {
    console.error(err);
    $("loading").hidden = true;
    $("fallback").hidden = false;
  });
}
