/* Floor plan, shelf/card slots and camera choreography for the Memory Palace.
   Pure numbers — no three.js — so Scripts/test_palace.mjs can check the rules
   the renderer relies on (labels fit their walls and never overlap, every
   room is visited) without a GPU.

   Plan: a domed rotunda with one arched doorway per topic, ringed by wedge
   rooms that also connect to each other (an enfilade), so the tour can walk
   the whole ring without turning back. Polar angle θ runs from +z towards +x;
   rooms run clockwise (decreasing θ) so that walking the ring, and reading a
   shelf wall, both go left to right. */

export const DIM = {
  wall: 0.8, backSlab: 0.5,
  roomH: 9.6, roofT: 0.45, drumH: 14,
  cutHero: 9.0,                       // section height for map / hero views
  doorW: 5.0, doorH: 7.6,             // rotunda → room
  enfW: 3.2, enfH: 5.6,               // room → room
  sill: 0.5, nicheTop: 5.5, nicheRise: 1.25,
  colInset: 1.35, colR: 0.48, colH: 11.4, entH: 1.4,
  card: { w: 1.4, h: 0.92, gapX: 0.2, gapY: 0.22, mid: 2.62, standoff: 0.45 },
  plaque: { y: 5.86, h: 0.56 },
  title: { y: 6.95, h: 1.3 },
  inscription: { y: 8.6, h: 0.72 },
  eye: 2.6,
  margin: 0.95,
};

const TAU = Math.PI * 2;
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));
export const at = (r, th, y = 0) => [r * Math.sin(th), y, r * Math.cos(th)];
export const rightOf = (th) => [-Math.cos(th), 0, Math.sin(th)];

export function computeLayout(model) {
  const list = model.rooms;
  const N = Math.min(10, Math.max(6, list.length));
  const alpha = TAU / N, half = alpha / 2, tanH = Math.tan(half), cosH = Math.cos(half);
  const T = DIM.wall;
  const R1 = Math.max(11.4, (DIM.doorW + 4.8) / (2 * tanH));
  const A = Math.max(R1 + T + 13, 21.4 / (2 * tanH));
  const pathR = A - 5.7;
  const rooms = [];
  for (let j = 0; j < N; j++) {
    const phi = -j * alpha;
    const data = list[j] || null;
    const wallLen = 2 * A * tanH;
    const usable = wallLen - 2 * DIM.margin;
    const shelves = [];
    if (data) {
      const k = data.shelves.length;
      const pitch = usable / k;
      const nicheW = clamp(pitch - 0.6, 2.2, 5.0);
      const cols = nicheW >= 3 * DIM.card.w + 2 * DIM.card.gapX + 0.2 ? 3 : 2;
      data.shelves.forEach((shelf, i) => {
        const s = -usable / 2 + pitch * (i + 0.5);
        const n = shelf.cards.length;
        const rows = Math.ceil(n / cols);
        const cards = shelf.cards.map((card, c) => {
          const row = Math.floor(c / cols);
          const inRow = Math.min(cols, n - row * cols);
          const col = c - row * cols;
          return {
            card,
            s: s + (col - (inRow - 1) / 2) * (DIM.card.w + DIM.card.gapX),
            y: DIM.card.mid + ((rows - 1) / 2 - row) * (DIM.card.h + DIM.card.gapY),
          };
        });
        shelves.push({
          shelf, s, pitch, nicheW, cols, rows, cards,
          plaque: { s, y: DIM.plaque.y, w: Math.min(nicheW + 0.3, pitch - 0.3, 3.6), h: DIM.plaque.h },
        });
      });
    }
    rooms.push({
      index: j, phi, data, wallLen, usable, shelves,
      center: at(A, phi), normal: [-Math.sin(phi), 0, -Math.cos(phi)], right: rightOf(phi),
      title: { s: 0, y: DIM.title.y, w: Math.min(usable - 1.2, 13), h: DIM.title.h },
      inscription: { y: DIM.inscription.y, w: Math.min(DIM.doorW + 1.6, 2 * R1 * tanH - 3.4), h: DIM.inscription.h },
      light: at((R1 + A) / 2 + 1, phi, 8.0),
    });
  }
  return {
    N, alpha, R1, A, T, pathR, rooms, cosH, tanH,
    colR: R1 - DIM.colInset,
    radius: (A + T + DIM.backSlab) / cosH,
    total: model.total, shown: model.shown, demo: !!model.demo,
  };
}

/* World position of a point on a room's shelf wall: s metres to the viewer's
   right of the wall centre, `out` metres into the room. */
export function wallPoint(room, s, y, out = 0) {
  const [cx, , cz] = room.center, [rx, , rz] = room.right, [nx, , nz] = room.normal;
  return [cx + rx * s + nx * out, y, cz + rz * s + nz * out];
}

export function roomAt(L, theta) {
  const j = Math.round(((-theta % TAU) + TAU) % TAU / L.alpha) % L.N;
  return L.rooms[j];
}

function heroFit(aspect) { return aspect < 0.8 ? 1.75 : aspect < 1.2 ? 1.4 : aspect < 1.5 ? 1.15 : 1; }
const MAP = { r: 52, y: 68 };
const HERO = { r: 56, y: 73.5 };

/* The closing shot of the tour, seen from polar angle phi. On wide screens
   the camera slides left so the palace sits right of the end caption. */
function heroPose(phi, aspect) {
  const fit = heroFit(aspect), shift = aspect > 1.3 ? 10.5 : 0;
  const r = rightOf(phi + Math.PI), p = at(HERO.r * fit, phi, HERO.y * fit);
  return { p: [p[0] - r[0] * shift, p[1], p[2] - r[2] * shift], q: [-r[0] * shift, -1.5, -r[2] * shift] };
}

/* Named camera poses: p = camera position, q = look target. The room pose
   frames the whole shelf wall, title to floor, below the HUD bars; on
   narrow screens it stands further back and the visitor pans. */
export function views(L, aspect = 16 / 9) {
  const fit = heroFit(aspect);
  const heroPhi = L.rooms[L.N - 1].phi + Math.PI;
  const tanX = Math.tan((55 / 2) * Math.PI / 180) * aspect;
  const back = aspect < 1.2 ? 12.5 : clamp((L.rooms[0].usable / 2 + 0.45) / tanX, 9.3, 11.6);
  return {
    rotunda: (k = 0) => {
      const phi = L.rooms[k].phi;
      return { p: at(L.R1 - 4.4, phi + Math.PI, 3.1), q: at(L.R1 * 0.7, phi, 5.2), fov: 55, cut: 100 };
    },
    overview: { p: at(MAP.r * fit, heroPhi, MAP.y * fit), q: [0, -1.5, 0], fov: 38, cut: DIM.cutHero },
    room: (j) => {
      const room = L.rooms[j];
      return { p: at(L.A - back, room.phi, DIM.eye + 0.15), q: wallPoint(room, 0, 3.95, DIM.card.standoff), fov: 55, cut: 100 };
    },
  };
}

function lerp3(a, b, t) { return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]; }
const smooth = (t) => t * t * (3 - 2 * t);

/* The guided tour: rotunda → every room through the enfilade → crane up and
   back to the hero shot. Times are seconds; the renderer runs splines through
   positions and targets and eases speed between keys. */
export function tourPlan(L, aspect = 16 / 9) {
  const { N, alpha, pathR, A, R1 } = L;
  const keys = [];
  const key = (t, p, q, fov = 55, cut = 100) => keys.push({ t, p, q, fov, cut });
  const wallTarget = (th) => {
    const room = roomAt(L, th);
    const r = (A - DIM.card.standoff) / Math.cos(th - room.phi);
    return at(r, th, 3.25);
  };

  key(0.0, at(R1 - 3.2, Math.PI - 0.62, 2.3), at(3.0, -0.15, 9.5));
  key(2.3, at(R1 - 7.2, Math.PI - 1.05, 2.5), at(R1 - 3.3, -0.1, 6.0));
  key(4.2, at(R1 - 2.4, 0.03, 2.7), at(R1 + 5.2, -0.12, 3.6));
  key(5.3, at(R1 + 1.8, -0.03, 2.7), at(A - 1.3, -0.16, 3.1));

  const per = 3.6, steps = 4, t0 = 6.9, dt = per / steps;
  const last = (N - 1) * steps;
  for (let s = 1; s <= last; s++) {
    const th = -s * alpha / steps;
    const room = roomAt(L, th);
    const w = Math.cos((th - room.phi) * Math.PI / alpha) ** 2;
    const p = at(pathR, th, DIM.eye + 0.12 * w);
    const r = rightOf(th);
    const ahead = [p[0] + r[0] * 8, 2.75, p[2] + r[2] * 8];
    key(t0 + (s - 1) * dt, p, lerp3(ahead, wallTarget(th - 0.2), 0.15 + 0.85 * w));
  }
  const phiEnd = -last * alpha / steps;
  const tEnd = t0 + (last - 1) * dt;

  const start = at(pathR + 0.3, phiEnd - 0.1, 2.9);
  const startQ = wallTarget(phiEnd - 0.26);
  const craneT0 = tEnd + 1.4, craneDur = 5.0;
  key(craneT0, start, startQ);
  const heroPhi = phiEnd + Math.PI;
  const hero = heroPose(heroPhi, aspect);
  for (const s of [0.25, 0.5, 0.75, 1]) {
    const e = smooth(s), eh = 1 - (1 - s) ** 2.2;
    const p = lerp3(start, hero.p, e);
    p[1] = start[1] + (hero.p[1] - start[1]) * eh;
    key(craneT0 + s * craneDur, p, lerp3(startQ, hero.q, smooth(Math.min(1, s * 1.25))), 55 + (38 - 55) * e, DIM.cutHero);
  }
  const tHero = craneT0 + craneDur;
  for (const [i, d] of [[1, 0.035], [2, 0.075], [3, 0.11]]) {
    const h = heroPose(heroPhi - d, aspect);
    key(tHero + i * 1.45, h.p, h.q, 38, DIM.cutHero);
  }
  const duration = keys[keys.length - 1].t;

  const captions = [{ kind: "title", from: 0.25, to: 4.0 }];
  /* A room's caption takes over just before the camera passes its enfilade
     door, when the room already fills the view. */
  const doorT = (j) => t0 + (steps * j - 3) * dt - 0.5;
  for (let j = 0; j < N; j++) {
    const from = j === 0 ? 4.4 : doorT(j);
    const to = j === N - 1 ? craneT0 + 0.6 : doorT(j + 1);
    captions.push({ kind: "room", room: j, from, to });
  }
  captions.push({ kind: "end", from: tHero - 0.6, to: duration + 1 });
  return { keys, duration, captions, cutAt: craneT0 + 0.15, heroAt: tHero, craneT0, craneDur };
}

/* Waypoints for an interactive fly between places, routed through doorways
   so the camera never passes through a wall. Places are
   { kind: "room", room } | { kind: "rotunda", facing } | { kind: "overview" }.
   Leaving for the map, the camera first rises straight up through the
   section cut, where nothing is left to hit. */
export function routeBetween(L, from, to) {
  const pts = [];
  const doorIn = (j) => at(L.R1 + 2.6, L.rooms[j].phi, DIM.eye);
  const doorOut = (j) => at(L.R1 - 2.4, L.rooms[j].phi, DIM.eye + 0.2);
  const above = DIM.cutHero + 4;
  if (to.kind === "overview") {
    if (from.kind === "room") pts.push(at(L.pathR - 1, L.rooms[from.room].phi, above));
    if (from.kind === "rotunda") pts.push(at(L.R1 - 5.5, L.rooms[from.facing ?? 0].phi + Math.PI, above));
    return pts;
  }
  if (from.kind === "overview") {
    pts.push(to.kind === "room" ? at(L.pathR - 2, L.rooms[to.room].phi, 22) : [0.01, 30, 0.01]);
    return pts;
  }
  if (from.kind === "rotunda" && to.kind === "rotunda") {
    const a = L.rooms[from.facing ?? 0].phi, b = L.rooms[to.facing ?? 0].phi;
    const d = Math.atan2(Math.sin(b - a), Math.cos(b - a));
    if (Math.abs(d) > 0.35) pts.push(at(L.R1 - 5.2, a + Math.PI + d / 2, 3.1));
    return pts;
  }
  if (from.kind === "room" && to.kind === "room") {
    const gap = (to.room - from.room + L.N) % L.N;
    if (gap === 0) return pts;
    if (gap === 1 || gap === L.N - 1) {
      pts.push(at(L.pathR, L.rooms[from.room].phi + (gap === 1 ? -1 : 1) * L.alpha / 2, DIM.eye));
      return pts;
    }
  }
  if (from.kind === "room") pts.push(doorIn(from.room), doorOut(from.room));
  if (to.kind === "room") {
    if (from.kind === "room") {
      const a = L.rooms[from.room].phi, b = L.rooms[to.room].phi;
      const d = Math.atan2(Math.sin(b - a), Math.cos(b - a));
      pts.push(at(L.R1 - 5.5, a + d / 2, DIM.eye + 0.4));
    }
    pts.push(doorOut(to.room), doorIn(to.room));
  }
  return pts;
}
