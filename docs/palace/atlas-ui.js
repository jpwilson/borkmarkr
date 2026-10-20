/* The application shell: layer rows, the overview tables, the timeline
   scrubber, the three linked charts, the key-moments list and the bookmark
   finder. Everything here is rendered from the atlas model — no number on
   screen is written by hand, and when the library has no dates the time UI
   says so instead of inventing one.

   Nothing in this file ever assigns a library string to innerHTML. Titles,
   topic names, subtopic names and URLs come from someone's account; they go
   in through textContent and through a sanitised href, never as markup. */

const MONTH = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAY = 86_400_000;
const SVG_NS = "http://www.w3.org/2000/svg";

export const fmtDate = (ms) => {
  const d = new Date(ms);
  return `${MONTH[d.getUTCMonth()]} ${d.getUTCDate()}, ${d.getUTCFullYear()}`;
};
export const fmtShort = (ms) => {
  const d = new Date(ms);
  return `${MONTH[d.getUTCMonth()]} ${d.getUTCDate()}`;
};
export const fmtMonth = (ms) => {
  const d = new Date(ms);
  return `${MONTH[d.getUTCMonth()]} ${d.getUTCFullYear()}`;
};
const num = (n) => Number(n || 0).toLocaleString("en-US");
const el = (id) => document.getElementById(id);
const clamp = (v, a, b) => Math.min(b, Math.max(a, v));

/* Tiny element builder. `text` is always set with textContent, so a hostile
   bookmark title is inert by construction. */
function h(tag, props = {}, children = []) {
  const node = document.createElement(tag);
  for (const [k, v] of Object.entries(props)) {
    if (v == null) continue;
    if (k === "text") node.textContent = String(v);
    else if (k === "class") node.className = v;
    else if (k === "style") Object.assign(node.style, v);
    else if (k === "data") for (const [dk, dv] of Object.entries(v)) node.dataset[dk] = dv;
    else if (k.startsWith("on") && typeof v === "function") node.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k in node && k !== "list") node[k] = v;
    else node.setAttribute(k, String(v));
  }
  for (const c of [].concat(children)) if (c) node.appendChild(typeof c === "string" ? document.createTextNode(c) : c);
  return node;
}
const svg = (tag, attrs = {}) => {
  const node = document.createElementNS(SVG_NS, tag);
  for (const [k, v] of Object.entries(attrs)) if (v != null) node.setAttribute(k, String(v));
  return node;
};

/* A 14px glyph per source, so the layer list reads like FireTrace's layer
   thumbnails rather than a row of anonymous colour chips. */
const SOURCE_GLYPH = {
  x: "M3 3l8 8M11 3l-8 8",
  youtube: "M2 4.2h10v5.6H2zM6 5.4l3 1.6-3 1.6z",
  reddit: "M2.4 8.4a4.6 3.4 0 0 1 9.2 0a4.6 3.4 0 0 1-9.2 0M5.2 7.8h.01M8.8 7.8h.01M9.4 3.2l.8 2.4",
  web: "M7 1.6a5.4 5.4 0 1 0 0 10.8A5.4 5.4 0 0 0 7 1.6M1.8 7h10.4M7 1.6c1.6 1.8 1.6 8 0 10.8M7 1.6C5.4 3.4 5.4 9.6 7 12.4",
};
function sourceSwatch(color, id) {
  const box = h("span", { class: "sw sw-src", style: { background: color } });
  const g = svg("svg", { viewBox: "0 0 14 14", "aria-hidden": "true" });
  g.appendChild(svg("path", {
    d: SOURCE_GLYPH[id] || SOURCE_GLYPH.web,
    fill: "none", stroke: "rgba(255,255,255,.92)", "stroke-width": "1.3",
    "stroke-linecap": "round", "stroke-linejoin": "round",
  }));
  box.appendChild(g);
  return box;
}
function regionSwatch(color, share) {
  const box = h("span", { class: "sw sw-reg", style: { background: color } });
  box.appendChild(h("i", { style: { width: `${Math.round(clamp(share, 0.06, 1) * 100)}%` } }));
  return box;
}
function gradientSwatch(css) {
  return h("span", { class: "sw", style: { background: css } });
}

const BASE_LAYERS = [
  { id: "terrain", name: "Terrain", note: "3D + relief", swatch: "linear-gradient(160deg,#d8c8a4,#8f877a)" },
  { id: "forest", name: "Forests", note: "canopy", swatch: "linear-gradient(160deg,#3d5130,#28381f)" },
  { id: "tints", name: "Region tints", note: "draped", swatch: "linear-gradient(90deg,#B4573A,#3F7D74,#5C6BA8)" },
  { id: "edges", name: "District edges", note: "dashed", swatch: "repeating-linear-gradient(90deg,#6E685E 0 3px,transparent 3px 6px)" },
  { id: "markers", name: "Bookmark markers", note: "pins", swatch: "radial-gradient(circle at 50% 32%,#fff 0 26%,#B4573A 28%)" },
  { id: "trail", name: "Reading trail", note: "dated", swatch: "repeating-linear-gradient(90deg,#D9482B 0 4px,transparent 4px 7px)" },
  { id: "labels", name: "Labels & pins", note: "", swatch: "linear-gradient(160deg,#ECE8DF,#CFC8B8)" },
];

export class AtlasUI {
  constructor({ atlas, state, actions }) {
    this.atlas = atlas;
    this.state = state;
    this.actions = actions;
    this.charts = [];
    this.layerRows = new Map();
    this.abort = new AbortController();
    this.dragging = null;
    this.chartCache = null;
  }

  on(node, type, fn, opts) {
    if (!node) return;
    node.addEventListener(type, fn, { ...(opts || {}), signal: this.abort.signal });
  }

  /* Every listener this instance adds is cancelled together, so switching
     library cannot leave a second copy of the shell wired to the buttons. */
  destroy() {
    this.abort.abort();
    for (const id of ["layers-base", "layers-data", "ov-kv", "ov-stats", "ov-list", "ov-notes", "moments", "charts", "tl-axis", "tl-events", "find-list"]) {
      const node = el(id);
      if (node) node.textContent = "";
    }
  }

  /* ── one-time build ─────────────────────────────────────────────────── */
  build() {
    const a = this.atlas;
    el("library-name").textContent = a.label;
    el("chip-count").textContent = `${num(a.total)} bookmarks`;
    el("vp-status-text").textContent = a.demo ? a.label : (a.label || "My library");
    el("range-text").textContent = a.range ? `${fmtMonth(a.range.start)} – ${fmtMonth(a.range.end)}` : "No save dates";
    el("badge-topics").textContent = a.regions.length;
    el("badge-sources").textContent = a.sources.length;
    el("badge-timeline").textContent = a.weeks.length ? `${a.weeks.length}w` : "—";
    el("tl-range").textContent = a.range
      ? `${fmtDate(a.range.start)} – ${fmtDate(a.range.end)}`
      : "This library has no save dates";
    el("tl-undated").textContent = a.stats.undated ? `${num(a.stats.undated)} undated` : "";
    el("tl-undated").hidden = !a.stats.undated;

    const warn = el("truncated");
    warn.hidden = !a.truncated;
    if (a.truncated) {
      warn.textContent = `Showing the ${num(a.total)} most recent bookmarks — this library is larger.`;
    }

    this.buildLayers();
    this.buildMoments();
    this.buildAxis();
    this.buildCharts();
    this.buildFinder();
    this.wire();
    this.refresh();
  }

  wire() {
    const { actions } = this;
    document.querySelectorAll("#mode-tabs button").forEach((b) => {
      this.on(b, "click", () => actions.setMode(b.dataset.mode));
    });
    document.querySelectorAll("#inspector-tabs button").forEach((b) => {
      this.on(b, "click", () => actions.setTab(b.dataset.tab));
    });
    document.querySelectorAll("#dim-toggle button").forEach((b) => {
      this.on(b, "click", () => actions.setDim(b.dataset.dim));
    });
    this.on(el("tp-play"), "click", () => actions.togglePlay());
    this.on(el("tp-prev"), "click", () => actions.stepMoment(-1));
    this.on(el("tp-next"), "click", () => actions.stepMoment(1));
    this.on(el("tp-speed"), "click", () => actions.cycleSpeed());
    this.on(el("detail-close"), "click", () => actions.select(null));
    this.on(el("d-fly"), "click", () => actions.flyToSelection());
    this.on(el("btn-reset"), "click", () => actions.resetView());
    this.on(el("ov-clear"), "click", () => actions.focusRegion(null));

    const track = el("tl-track");
    const scrub = (ev) => {
      const r = track.getBoundingClientRect();
      actions.setTime(clamp((ev.clientX - r.left) / r.width, 0, 1));
    };
    this.on(track, "pointerdown", (ev) => {
      if (!this.atlas.range) return;
      track.setPointerCapture(ev.pointerId);
      this.scrubbing = true;
      track.focus();
      scrub(ev);
    });
    this.on(track, "pointermove", (ev) => { if (this.scrubbing) scrub(ev); });
    this.on(track, "pointerup", () => { this.scrubbing = false; });
    this.on(track, "keydown", (ev) => {
      if (!this.atlas.range) return;
      const step = ev.shiftKey ? 0.1 : 1 / Math.max(8, this.atlas.weeks.length);
      const map = { ArrowLeft: -step, ArrowRight: step, PageDown: -step * 4, PageUp: step * 4, Home: -2, End: 2 };
      if (!(ev.key in map)) return;
      ev.preventDefault();
      const next = ev.key === "Home" ? 0 : ev.key === "End" ? 1 : this.state.time + map[ev.key];
      this.actions.setTime(clamp(next, 0, 1));
    });
    this.on(window, "resize", () => { this.chartCache = null; this.drawCharts(); });

    const find = el("find-input");
    this.on(find, "input", () => this.renderFinder(find.value));
  }

  /* ── layers ─────────────────────────────────────────────────────────── */

  /* A layer row is built once and then updated in place: the native range
     input keeps pointer capture through a whole drag, which it cannot do if
     the row is thrown away on every change. */
  layerRow(spec) {
    const row = h("div", { class: "layer", data: { key: spec.key } });
    const id = `ck-${spec.key.replace(/[^a-z0-9]+/gi, "-")}`;
    const check = h("input", {
      type: "checkbox", class: "ck", id, checked: spec.visible,
      onchange: () => spec.onToggle(check.checked),
    });
    // A region row doubles as the "focus this region" control, so its name is
    // a real button; a base layer's name is a label bound to its checkbox.
    const label = spec.onPick
      ? h("button", { type: "button", class: "nm nm-btn", title: spec.title || spec.name, onclick: spec.onPick })
      : h("label", { class: "nm", htmlFor: id, title: spec.title || spec.name });
    label.appendChild(document.createTextNode(spec.name));
    if (spec.note) label.appendChild(h("small", { text: spec.note }));
    const range = h("input", {
      type: "range", class: "op", min: 0, max: 100, step: 1,
      value: Math.round(spec.opacity * 100),
      "aria-label": `${spec.name} opacity`,
      oninput: () => {
        pc.textContent = spec.count != null ? num(spec.count) : `${range.value}%`;
        spec.onOpacity(Number(range.value) / 100);
      },
    });
    const pc = h("span", { class: "pc", text: spec.count != null ? num(spec.count) : `${Math.round(spec.opacity * 100)}%` });

    if (spec.onPick) row.classList.add("on-region");
    check.setAttribute("aria-label", `Show ${spec.name}`);
    row.append(check, spec.swatch, label, range, pc);
    row._parts = { check, range, pc, label };
    return row;
  }

  layerSpecs() {
    const s = this.state, a = this.atlas;
    const base = BASE_LAYERS.map((L) => ({
      key: L.id, name: L.name, note: L.note, swatch: gradientSwatch(L.swatch),
      opacity: s.layers[L.id].opacity, visible: s.layers[L.id].on,
      onToggle: (v) => this.actions.setLayerVisible(L.id, v),
      onOpacity: (v) => this.actions.setLayerOpacity(L.id, v),
    }));
    const bySource = s.mode === "sources";
    // Both filter dimensions are always listed: whichever one the mode leads
    // with comes first, the other sits under it. A marker needs its topic and
    // its source to both be on, which also stops the panel running out of
    // content in Sources mode.
    const sourceRows = a.sources.map((r) => ({
      key: `src:${r.id}`, name: r.label, title: `${r.label} · ${num(r.count)} saves`,
      note: r.kind, swatch: sourceSwatch(r.color, r.id), count: r.count, onPick: null,
    }));
    const regionRows = a.regions.map((r) => ({
      key: `reg:${r.id}`, name: r.name, title: `${r.name} · ${num(r.total)} saves`,
      note: `${r.districts.length} districts`, swatch: regionSwatch(r.color, r.total / Math.max(1, a.total)),
      count: r.total, onPick: () => this.actions.focusRegion(s.focus === r.id ? null : r.id),
    }));
    const wire = (spec) => ({
      ...spec,
      opacity: s.groupOpacity.get(spec.key) ?? 1,
      visible: !s.hidden.has(spec.key),
      onToggle: (v) => this.actions.setGroupVisible(spec.key, v),
      onOpacity: (v) => this.actions.setGroupOpacity(spec.key, v),
    });
    const data = (bySource ? sourceRows : regionRows).map(wire);
    const alt = (bySource ? regionRows : sourceRows).map(wire);
    return { base, data, alt, bySource };
  }

  buildLayers() {
    const { base, data, alt, bySource } = this.layerSpecs();
    const a = this.atlas;
    this.layerRows.clear();
    const fill = (host, specs) => {
      host.textContent = "";
      for (const spec of specs) {
        const row = this.layerRow(spec);
        host.appendChild(row);
        this.layerRows.set(spec.key, row);
      }
    };
    fill(el("layers-base"), base);
    fill(el("layers-data"), data);
    fill(el("layers-alt"), alt);
    el("layers-data-title").textContent = bySource ? "Sources" : "Topics";
    el("layers-data-meta").textContent = `${data.length} · ${num(a.total)} saves`;
    el("layers-alt-title").textContent = bySource ? "Topics" : "Sources";
    el("layers-alt-meta").textContent = `${alt.length}`;
    this.syncLayers();
  }

  /* Reflect state on the existing rows. Called every frame of the tour, so
     it reads state directly and allocates nothing. */
  syncLayers() {
    const s = this.state, a = this.atlas;
    for (const [key, row] of this.layerRows) {
      const { check, range, pc } = row._parts;
      let visible, opacity, count = null;
      if (key.includes(":")) {
        visible = !s.hidden.has(key);
        opacity = s.groupOpacity.get(key) ?? 1;
        const id = key.slice(4);
        const rec = key.startsWith("src:") ? a.sources.find((x) => x.id === id) : a.regions.find((x) => x.id === id);
        count = rec ? (rec.count ?? rec.total) : 0;
        row.classList.toggle("sel", key.startsWith("reg:") && s.focus === id);
      } else {
        visible = s.layers[key].on;
        opacity = s.layers[key].opacity;
      }
      if (check.checked !== visible) check.checked = visible;
      const want = String(Math.round(opacity * 100));
      if (range.value !== want && document.activeElement !== range) range.value = want;
      const text = count != null ? num(count) : `${want}%`;
      if (pc.textContent !== text) pc.textContent = text;
      row.classList.toggle("vis", visible);
    }
  }

  /* ── overview / notes ───────────────────────────────────────────────── */
  buildOverview() {
    const a = this.atlas, s = this.state;
    const region = s.focus ? a.regions.find((r) => r.id === s.focus) : null;
    el("ov-title").textContent = region ? `${region.name} overview` : "Library overview";
    el("ov-clear").hidden = !region;

    const asOf = a.asOf ? fmtDate(a.asOf) : null;
    const pairs = region
      ? [
        ["Region", region.name],
        ["Bookmarks", num(region.total)],
        ["Share of library", `${Math.round(region.share * 100)}%`],
        ["Districts", num(region.districts.length)],
        ["First save", region.first ? fmtDate(region.first) : "—"],
        ["Last save", region.last ? fmtDate(region.last) : "—"],
        ["Top district", region.districts.slice().sort((x, y) => y.total - x.total)[0]?.name || "—"],
        ["Top source", this.topSourceOf(region.items)],
      ]
      : [
        ["Library", a.label],
        ["Bookmarks", num(a.total) + (a.truncated ? " (partial)" : "")],
        ["Topics", num(a.regions.length)],
        ["Subtopics", num(a.stats.subtopics)],
        ["Sources", num(a.sources.length)],
        ["First save", a.range ? fmtDate(a.range.start) : "—"],
        ["Last save", a.range ? fmtDate(a.range.end) : "—"],
        ["Undated", a.stats.undated ? num(a.stats.undated) : "none"],
        ["Top source", a.stats.topSource ? `${a.stats.topSource.label} · ${num(a.stats.topSource.count)}` : "—"],
      ];
    const kv = el("ov-kv");
    kv.textContent = "";
    for (const [k, v] of pairs) kv.appendChild(h("div", {}, [h("dt", { text: k }), h("dd", { text: v, title: v })]));

    const items = region ? region.items : a.items;
    const dated = items.filter((i) => i.at != null);
    const last30 = a.range ? dated.filter((i) => i.at > a.range.end - 30 * DAY).length : 0;
    const perWeek = a.weeks.length ? Math.round((dated.length / a.weeks.length) * 10) / 10 : 0;
    const tiles = [
      [num(last30), asOf ? `saved · 30 days to ${fmtShort(a.asOf)}` : "saved · no dates"],
      [String(perWeek), "average per week"],
      [region ? num(region.districts.length) : num(a.stats.topRegion?.total ?? 0), region ? "districts" : `in ${a.stats.topRegion?.name || "—"}`],
      [a.stats.spanMonths ? `${a.stats.spanMonths} mo` : "—", "of history"],
    ];
    const stats = el("ov-stats");
    stats.textContent = "";
    for (const [b, c] of tiles) stats.appendChild(h("div", { class: "stat" }, [h("b", { text: b }), h("span", { text: c, title: c })]));

    el("ov-list-title").textContent = region ? "Districts" : s.mode === "sources" ? "Sources" : "Topics";
    const list = el("ov-list");
    list.textContent = "";
    const bars = region
      ? region.districts.map((d) => [d.name, d.total, region.color])
      : s.mode === "sources"
        ? a.sources.map((x) => [x.label, x.count, x.color])
        : a.regions.map((r) => [r.name, r.total, r.color]);
    this.barList(list, bars);

    const extraTitle = region ? "Sources here" : s.mode === "sources" ? "Topics" : "Sources";
    const extra = region
      ? [...region.items.reduce((m, i) => m.set(i.source, (m.get(i.source) || 0) + 1), new Map())]
        .sort((x, y) => y[1] - x[1])
        .map(([id, n]) => {
          const src = a.sources.find((q) => q.id === id);
          return [src ? src.label : id, n, src ? src.color : "#6E685E"];
        })
      : s.mode === "sources"
        ? a.regions.map((r) => [r.name, r.total, r.color])
        : a.sources.map((x) => [x.label, x.count, x.color]);
    el("ov-extra-title").textContent = extraTitle;
    el("ov-extra-meta").textContent = String(extra.length);
    const list2 = el("ov-extra");
    list2.textContent = "";
    this.barList(list2, extra);

    const notes = el("ov-notes");
    notes.textContent = "";
    for (const n of this.notes()) {
      notes.appendChild(h("div", { class: "note" }, [
        h("i", { style: { background: n.color } }),
        h("span", {}, n.parts.map((p) => (p.strong ? h("b", { text: p.text }) : document.createTextNode(p.text)))),
      ]));
    }
  }

  barList(host, bars) {
    const max = Math.max(1, ...bars.map((b) => b[1]));
    for (const [name, value, color] of bars.slice(0, 10)) {
      host.appendChild(h("div", { class: "bar-row" }, [
        h("span", { class: "lbl", text: name, title: name }),
        h("span", { class: "val", text: num(value) }),
        h("span", { class: "track" }, [h("i", { style: { width: `${Math.max(3, (value / max) * 100)}%`, background: color } })]),
      ]));
    }
  }

  topSourceOf(items) {
    const tally = new Map();
    for (const i of items) tally.set(i.source, (tally.get(i.source) || 0) + 1);
    const top = [...tally].sort((a, b) => b[1] - a[1])[0];
    if (!top) return "—";
    const src = this.atlas.sources.find((s) => s.id === top[0]);
    return `${src ? src.label : top[0]} · ${num(top[1])}`;
  }

  /* Short observations, each one arithmetic on the model, each one dated so
     "right now" can't mean "two years ago". */
  notes() {
    const a = this.atlas;
    const out = [];
    const asOf = a.asOf ? fmtDate(a.asOf) : null;
    if (a.demo) {
      out.push({ color: "#D9482B", parts: [
        { text: `${a.label}. `, strong: true },
        { text: `${num(a.total)} example bookmarks across ${a.regions.length} topics. Sign in on bookmarker.lol and this map is built from your own saves instead.` },
      ] });
    }
    if (a.truncated) {
      out.push({ color: "#9E4256", parts: [
        { text: "Partial library. ", strong: true },
        { text: `Only the ${num(a.total)} most recent bookmarks were loaded, so totals below are for that slice.` },
      ] });
    }
    if (a.stats.topRegion) {
      out.push({ color: a.stats.topRegion.color, parts: [
        { text: a.stats.topRegion.name, strong: true },
        { text: ` is the largest region — ${num(a.stats.topRegion.total)} saves, ${Math.round((a.stats.topRegion.total / a.total) * 100)}% of the library.` },
      ] });
    }
    if (a.range) {
      const recent = a.regions
        .map((r) => [r, r.items.filter((i) => i.at != null && i.at > a.range.end - 60 * DAY).length])
        .sort((x, y) => y[1] - x[1])[0];
      if (recent && recent[1] > 0) {
        out.push({ color: recent[0].color, parts: [
          { text: recent[0].name, strong: true },
          { text: ` led the last 60 days of saving — ${num(recent[1])} saves in the 60 days to ${asOf}.` },
        ] });
      }
      const newest = a.regions.filter((r) => r.first != null).sort((x, y) => y.first - x.first)[0];
      if (newest) {
        out.push({ color: newest.color, parts: [
          { text: "Newest region: ", strong: false },
          { text: newest.name, strong: true },
          { text: `, opened ${fmtDate(newest.first)}.` },
        ] });
      }
    }
    if (a.stats.topSource) {
      out.push({ color: a.stats.topSource.color, parts: [
        { text: a.stats.topSource.label, strong: true },
        { text: ` is where most of this library comes from — ${Math.round(a.stats.topSource.share * 100)}% of saves.` },
      ] });
    }
    if (a.stats.undated) {
      out.push({ color: "#5C6A77", parts: [
        { text: `${num(a.stats.undated)} bookmarks have no save date. `, strong: true },
        { text: "They sit outside the timeline and are drawn as short grey stubs." },
      ] });
    }
    out.push({ color: "#5C6A77", parts: [
      { text: "Marker height is recency", strong: true },
      { text: `: the taller the pin, the more recently it was saved${asOf ? `, measured against ${asOf}` : ""}.` },
    ] });
    return out;
  }

  /* ── finder: keyboard access to anything on the map ─────────────────── */
  buildFinder() {
    el("find-count").textContent = num(this.atlas.total);
    this.renderFinder("");
  }

  renderFinder(query) {
    const q = String(query || "").trim().toLowerCase();
    const list = el("find-list");
    list.textContent = "";
    const matches = (q
      ? this.atlas.items.filter((i) =>
        i.title.toLowerCase().includes(q)
        || i.regionName.toLowerCase().includes(q)
        || i.district.toLowerCase().includes(q)
        || i.sourceLabel.toLowerCase().includes(q))
      : this.atlas.items.slice().sort((a, b) => (b.at ?? 0) - (a.at ?? 0))
    ).slice(0, 60);
    el("find-count").textContent = q ? `${num(matches.length)} of ${num(this.atlas.total)}` : num(this.atlas.total);
    if (!matches.length) {
      list.appendChild(h("p", { class: "empty", text: "Nothing matches that." }));
      return;
    }
    for (const item of matches) {
      const btn = h("button", {
        type: "button", class: "find-row",
        onclick: () => this.actions.selectById(item.id, { fly: true }),
      }, [
        h("span", { class: "f-title", text: item.title, title: item.title }),
        h("span", { class: "f-meta", text: `${item.regionName} › ${item.district} · ${item.sourceLabel}${item.at != null ? ` · ${fmtShort(item.at)}` : " · no date"}` }),
      ]);
      list.appendChild(btn);
    }
  }

  /* ── key moments ────────────────────────────────────────────────────── */
  buildMoments() {
    const a = this.atlas;
    const box = el("moments");
    box.textContent = "";
    el("moments-count").textContent = a.moments.length;
    if (!a.moments.length) {
      box.appendChild(h("p", {
        class: "empty",
        text: a.range ? "Not enough history yet to call out any moments." : "This library has no save dates, so there is no timeline to read.",
      }));
      return;
    }
    a.moments.forEach((m, i) => {
      box.appendChild(h("button", {
        type: "button", class: "moment", data: { index: String(i) },
        onclick: () => this.actions.goToMoment(i),
      }, [
        h("i", { style: { background: m.color } }),
        h("span", { class: "m-lbl" }, [
          document.createTextNode(m.label),
          h("small", { text: m.detail, title: m.detail }),
        ]),
        h("span", { class: "m-date", text: fmtShort(m.at) }),
      ]));
    });
    const events = el("tl-events");
    events.textContent = "";
    for (const m of a.moments) {
      events.appendChild(h("i", { style: { background: m.color, left: `${this.frac(m.at) * 100}%` }, title: `${m.label} · ${fmtDate(m.at)}` }));
    }
  }

  frac(ms) {
    const r = this.atlas.range;
    if (!r || r.end === r.start) return 1;
    return clamp((ms - r.start) / (r.end - r.start), 0, 1);
  }
  timeAt(frac) {
    const r = this.atlas.range;
    return r ? r.start + (r.end - r.start) * frac : 0;
  }

  /* ── timeline axis ──────────────────────────────────────────────────── */
  buildAxis() {
    const a = this.atlas, axis = el("tl-axis");
    axis.textContent = "";
    if (!a.range) return;
    const start = new Date(a.range.start), end = new Date(a.range.end);
    const months = [];
    let y = start.getUTCFullYear(), m = start.getUTCMonth();
    while (Date.UTC(y, m) <= end.getTime()) {
      const t = Date.UTC(y, m);
      if (t >= a.range.start) months.push(t);
      m++; if (m > 11) { m = 0; y++; }
    }
    const step = months.length > 14 ? 2 : 1;
    months.forEach((t, i) => {
      const left = `${this.frac(t) * 100}%`;
      axis.appendChild(h("i", { style: { left } }));
      if (i % step) return;
      const d = new Date(t);
      axis.appendChild(h("span", {
        style: { left },
        text: d.getUTCMonth() === 0 || i === 0 ? `${MONTH[d.getUTCMonth()]} ${d.getUTCFullYear()}` : MONTH[d.getUTCMonth()],
      }));
    });
  }

  /* ── charts ─────────────────────────────────────────────────────────── */

  /* Series are cached per (mode, focus); only the cursor moves while the
     timeline plays, so a tour frame does no aggregation work. */
  chartSpecs() {
    const key = `${this.state.mode}|${this.state.focus || ""}`;
    if (this.chartCache && this.chartCache.key === key) return this.chartCache.specs;
    const specs = this.computeSpecs();
    this.chartCache = { key, specs };
    return specs;
  }

  computeSpecs() {
    const a = this.atlas, s = this.state;
    const region = s.focus ? a.regions.find((r) => r.id === s.focus) : null;
    const weeks = a.weeks;
    const times = weeks.map((w) => w.t);
    const scope = region ? region.name : s.mode === "sources" ? "all sources" : "all topics";

    const saves = {
      title: "Saves per week",
      sub: scope,
      kind: "area",
      times,
      series: [{
        key: "all", label: "Saves", color: region ? region.color : "#5C6A77",
        values: weeks.map((w) => (region ? w.byRegion[region.id] || 0 : w.count)),
      }],
    };

    /* Cumulative stack: every group is included, the small ones merged into
       "Other", and each band sits on the one below so the top line is the
       library total. */
    const stackFrom = (groups, pick, title, sub) => {
      const keep = groups.slice(0, 6);
      const rest = groups.slice(6);
      const series = keep.map((g) => ({ key: g.id, label: g.name, color: g.color, values: [] }));
      if (rest.length) series.push({ key: "other", label: `Other (${rest.length})`, color: "#8C8577", values: [] });
      const run = series.map(() => 0);
      for (const w of weeks) {
        keep.forEach((g, i) => { run[i] += pick(w, g); });
        if (rest.length) run[keep.length] += rest.reduce((n, g) => n + pick(w, g), 0);
        series.forEach((sv, i) => sv.values.push(run[i]));
      }
      return { title, sub, kind: "stack", times, series };
    };

    if (s.mode === "sources") {
      const byTopic = stackFrom(a.regions.map((r) => ({ id: r.id, name: r.name, color: r.color })),
        (w, g) => w.byRegion[g.id] || 0, "Library by topic", "cumulative, stacked");
      const bySource = stackFrom(a.sources.map((x) => ({ id: x.id, name: x.label, color: x.color })),
        (w, g) => w.bySource[g.id] || 0, "Library by source", "cumulative, stacked");
      return [saves, bySource, byTopic];
    }

    const second = region
      ? (() => {
        const districts = region.districts.map((d, i) => ({ id: d.name, name: d.name, color: shade(region.color, i), items: d.items }));
        const pick = (w, g) => g.items.filter((it) => it.at != null && it.at >= w.t && it.at < w.t + 7 * DAY).length;
        return stackFrom(districts, pick, "Districts over time", "cumulative, stacked");
      })()
      : stackFrom(a.regions.map((r) => ({ id: r.id, name: r.name, color: r.color })),
        (w, g) => w.byRegion[g.id] || 0, "Library by topic", "cumulative, stacked");

    const sources = a.sources.map((x) => ({ id: x.id, name: x.label, color: x.color }));
    const lines = sources.slice(0, 5).map((t) => ({ key: t.id, label: t.name, color: t.color, values: [] }));
    const runS = lines.map(() => 0);
    for (const w of weeks) {
      lines.forEach((sv, i) => {
        runS[i] += region
          ? region.items.filter((it) => it.source === sources[i].id && it.at != null && it.at >= w.t && it.at < w.t + 7 * DAY).length
          : (w.bySource[sources[i].id] || 0);
        sv.values.push(runS[i]);
      });
    }
    return [saves, second, { title: "Sources mix", sub: "cumulative", kind: "line", times, series: lines }];
  }

  buildCharts() {
    const box = el("charts");
    box.textContent = "";
    this.charts = [0, 1, 2].map(() => {
      const title = h("h3", {});
      const sub = h("small", {});
      const now = h("span", { class: "now" });
      const legend = h("div", { class: "legend" });
      const plot = svg("svg", { preserveAspectRatio: "none" });
      const card = h("div", { class: "chart" }, [h("div", { class: "chart-head" }, [title, sub, now]), legend, plot]);
      box.appendChild(card);
      return { card, title, sub, now, legend, plot };
    });
    this.drawCharts();
  }

  drawCharts() {
    const specs = this.chartSpecs();
    const a = this.atlas;
    const cursorT = a.range ? this.timeAt(this.state.time) : 0;
    this.charts.forEach((node, i) => {
      const spec = specs[i];
      node.title.textContent = spec.title;
      node.sub.textContent = spec.sub;
      const w = Math.max(80, node.plot.clientWidth || node.card.clientWidth - 24);
      const hgt = Math.max(36, node.plot.clientHeight || 64);
      node.plot.setAttribute("viewBox", `0 0 ${w} ${hgt}`);
      node.plot.textContent = "";
      if (!a.range || !a.weeks.length) {
        node.plot.appendChild(svg("text", { class: "ax", x: 6, y: hgt / 2 }));
        node.plot.lastChild.textContent = "no save dates in this library";
        node.now.textContent = "";
        node.legend.textContent = "";
        return;
      }
      this.drawChart(node.plot, spec, w, hgt, cursorT);

      // headline: the total at the cursor for a stack, the value for a line
      const idx = bucketIndex(spec.times, cursorT);
      // a stack's headline is the whole library at that date, not its tallest band
      const total = spec.kind === "stack"
        ? spec.series.reduce((m, s) => m + (s.values[idx] || 0), 0)
        : spec.series[0].values[idx] || 0;
      node.now.textContent = num(Math.round(total));

      node.legend.textContent = "";
      if (spec.series.length > 1) {
        for (const s of spec.series.slice(0, 7)) {
          node.legend.appendChild(h("span", { class: "lg" }, [
            h("i", { style: { background: s.color } }),
            document.createTextNode(s.label),
          ]));
        }
      }
    });
  }

  drawChart(host, spec, w, hgt, cursorT) {
    const padL = 26, padR = 5, padT = 5, padB = 13;
    const iw = w - padL - padR, ih = hgt - padT - padB;
    const t0 = spec.times[0], t1 = spec.times[spec.times.length - 1] || t0 + 1;
    const X = (t) => padL + (t1 === t0 ? iw / 2 : ((t - t0) / (t1 - t0)) * iw);

    // a stack's top line is the sum of its bands
    const stacked = [];
    if (spec.kind === "stack") {
      let base = spec.times.map(() => 0);
      for (const s of spec.series) {
        const top = s.values.map((v, i) => base[i] + v);
        stacked.push({ ...s, base, top });
        base = top;
      }
    }
    let max = 0;
    if (spec.kind === "stack") max = Math.max(...stacked[stacked.length - 1].top, 1);
    else for (const s of spec.series) for (const v of s.values) max = Math.max(max, v);
    max = Math.max(1, Math.ceil(max * 1.1));
    const Y = (v) => padT + ih - (v / max) * ih;

    for (const f of [0, 0.5, 1]) {
      const y = Y(max * f);
      host.appendChild(svg("line", { class: "gl", x1: padL, x2: w - padR, y1: y.toFixed(1), y2: y.toFixed(1) }));
      const label = svg("text", { class: "ax", x: padL - 4, y: (y + 3).toFixed(1), "text-anchor": "end" });
      label.textContent = num(Math.round(max * f));
      host.appendChild(label);
    }

    const line = (vals) => vals.map((v, i) => `${i ? "L" : "M"}${X(spec.times[i]).toFixed(1)} ${Y(v).toFixed(1)}`).join(" ");
    if (spec.kind === "stack") {
      for (let i = stacked.length - 1; i >= 0; i--) {
        const s = stacked[i];
        const down = s.base.map((v, k) => `L${X(spec.times[spec.times.length - 1 - k]).toFixed(1)} ${Y(s.base[spec.times.length - 1 - k]).toFixed(1)}`).join(" ");
        host.appendChild(svg("path", { d: `${line(s.top)} ${down} Z`, fill: s.color, "fill-opacity": 0.78 }));
        host.appendChild(svg("path", { d: line(s.top), fill: "none", stroke: "rgba(30,28,25,.22)", "stroke-width": 0.8 }));
      }
    } else {
      for (const s of spec.series) {
        if (spec.kind === "area") {
          host.appendChild(svg("path", {
            d: `${line(s.values)} L${X(t1).toFixed(1)} ${Y(0).toFixed(1)} L${X(t0).toFixed(1)} ${Y(0).toFixed(1)} Z`,
            fill: s.color, "fill-opacity": 0.22,
          }));
        }
        host.appendChild(svg("path", { d: line(s.values), fill: "none", stroke: s.color, "stroke-width": 1.4, "stroke-linejoin": "round" }));
      }
    }

    const first = svg("text", { class: "ax", x: padL, y: hgt - 3 });
    first.textContent = fmtMonth(t0);
    const last = svg("text", { class: "ax", x: w - padR, y: hgt - 3, "text-anchor": "end" });
    last.textContent = fmtMonth(t1);
    host.append(first, last);

    // the cursor sits at the real time, not at a rounded bucket index
    const cx = X(clamp(cursorT, t0, t1));
    host.appendChild(svg("line", { x1: cx.toFixed(1), x2: cx.toFixed(1), y1: padT, y2: padT + ih, stroke: "#1E1C19", "stroke-width": 1 }));
    const idx = bucketIndex(spec.times, cursorT);
    const marks = spec.kind === "stack" ? stacked.map((s) => s.top[idx]) : spec.series.map((s) => s.values[idx]);
    marks.forEach((v, i) => {
      if (v == null) return;
      host.appendChild(svg("circle", {
        cx: cx.toFixed(1), cy: Y(v).toFixed(1), r: 2.5,
        fill: "#ECE8DF", stroke: (spec.kind === "stack" ? stacked[i] : spec.series[i]).color, "stroke-width": 1.4,
      }));
    });
  }

  /* ── per-frame refresh ──────────────────────────────────────────────── */
  refresh() {
    const a = this.atlas, s = this.state;
    document.querySelectorAll("#mode-tabs button").forEach((b) => {
      const on = b.dataset.mode === s.mode;
      b.classList.toggle("on", on);
      b.setAttribute("aria-selected", String(on));
    });
    document.querySelectorAll("#inspector-tabs button").forEach((b) => {
      const on = b.dataset.tab === s.tab;
      b.classList.toggle("on", on);
      b.setAttribute("aria-selected", String(on));
      b.tabIndex = on ? 0 : -1;
    });
    document.querySelectorAll("#dim-toggle button").forEach((b) => {
      const on = b.dataset.dim === s.dim;
      b.classList.toggle("on", on);
      b.setAttribute("aria-pressed", String(on));
    });
    document.querySelectorAll(".pane").forEach((p) => { p.hidden = p.dataset.pane !== s.tab; });
    el("tp-play").querySelector(".i-play").hidden = s.playing;
    el("tp-play").querySelector(".i-pause").hidden = !s.playing;
    el("tp-play").setAttribute("aria-label", s.playing ? "Pause" : "Play");
    el("tp-speed").textContent = `${s.speed}×`;

    const pct = s.time * 100;
    el("tl-fill").style.width = `${pct}%`;
    el("tl-knob").style.left = `${pct}%`;
    const when = a.range ? fmtDate(this.timeAt(s.time)) : "—";
    el("tl-cursor").textContent = when;
    const track = el("tl-track");
    track.setAttribute("aria-valuenow", String(Math.round(pct)));
    track.setAttribute("aria-valuetext", when);
    document.querySelectorAll(".moment").forEach((m, i) => {
      m.classList.toggle("on", i === s.moment);
      m.setAttribute("aria-current", i === s.moment ? "true" : "false");
    });

    const signature = `${s.mode}:${s.mode === "sources" ? a.sources.length : a.regions.length}`;
    if (signature !== this.layerModeSignature) {
      this.layerModeSignature = signature;
      this.buildLayers();
    } else {
      this.syncLayers();
    }
    this.buildOverview();
    this.drawCharts();
    this.renderDetail();
  }

  renderDetail() {
    const item = this.state.selection;
    const box = el("detail");
    if (!item) { box.hidden = true; return; }
    box.hidden = false;
    const src = this.atlas.sources.find((s) => s.id === item.source);
    const pill = el("d-source");
    pill.textContent = "";
    pill.append(h("i", { style: { background: src ? src.color : "#6E685E" } }), document.createTextNode(item.sourceLabel));
    el("d-meta").textContent = item.meta || "";
    el("d-title").textContent = item.title;
    el("d-title").title = item.title;
    el("d-path").textContent = `${item.regionName} › ${item.district}`;
    const kv = el("d-kv");
    kv.textContent = "";
    for (const [k, v] of [
      ["Saved", item.at != null ? fmtDate(item.at) : "no date"],
      ["Source", item.sourceLabel],
      ["Region", item.regionName],
    ]) kv.appendChild(h("div", {}, [h("dt", { text: k }), h("dd", { text: v, title: v })]));

    const tags = el("d-tags");
    tags.textContent = "";
    for (const t of [item.district, item.sourceLabel, item.meta].filter(Boolean)) {
      tags.appendChild(h("span", { text: t, title: t }));
    }

    // Only an http(s) link is ever made clickable; anything else is shown as
    // unavailable rather than handed to the browser.
    const open = el("d-open");
    if (item.hasLink && item.url) {
      open.href = item.url;
      open.removeAttribute("aria-disabled");
      open.classList.remove("off");
      open.textContent = "Open link ↗";
    } else {
      open.removeAttribute("href");
      open.setAttribute("aria-disabled", "true");
      open.classList.add("off");
      open.textContent = "No usable link";
    }
    el("d-note").hidden = !this.atlas.demo;
  }

  setLower(title, sub) {
    const box = el("vp-lower");
    if (!title) { box.hidden = true; return; }
    box.hidden = false;
    el("lower-title").textContent = title;
    el("lower-sub").textContent = sub || "";
  }

  setTip(screen, item) {
    const tip = el("tip");
    if (!item || !screen) { tip.hidden = true; return; }
    tip.hidden = false;
    tip.style.left = `${screen.x}px`;
    tip.style.top = `${screen.y - 12}px`;
    tip.textContent = "";
    tip.append(
      h("b", { text: item.title }),
      h("span", { text: `${item.sourceLabel} · ${item.at != null ? fmtDate(item.at) : "no save date"} · ${item.regionName}` }),
    );
  }

  setZoom(text) { el("zoom-read").textContent = text; }
  setScale(px, midLabel, maxLabel) {
    const w = `${Math.max(40, Math.min(170, px))}px`;
    document.querySelector(".sb-ticks").style.width = w;
    document.querySelector(".sb-rule").style.width = w;
    el("sb-mid").textContent = midLabel;
    el("sb-max").textContent = maxLabel;
  }
  setCompass(rad) {
    const needle = document.getElementById("needle");
    if (needle) needle.setAttribute("transform", `rotate(${(-rad * 180) / Math.PI} 24 24)`);
  }
}

/* The bucket whose week contains `t` — index arithmetic on real timestamps,
   not a rounded fraction of the series length. */
function bucketIndex(times, t) {
  if (!times.length) return 0;
  let lo = 0, hi = times.length - 1;
  if (t <= times[0]) return 0;
  if (t >= times[hi]) return hi;
  while (lo < hi) {
    const mid = (lo + hi + 1) >> 1;
    if (times[mid] <= t) lo = mid; else hi = mid - 1;
  }
  return lo;
}

/* A darker/lighter step of a region colour, so one region's districts stay
   recognisably the same family. */
function shade(hex, i) {
  const n = parseInt(hex.slice(1), 16);
  const k = 1 + (i - 2.5) * 0.17;
  const ch = (v) => Math.max(0, Math.min(255, Math.round(v * k)));
  return `#${((ch((n >> 16) & 255) << 16) | (ch((n >> 8) & 255) << 8) | ch(n & 255)).toString(16).padStart(6, "0")}`;
}
