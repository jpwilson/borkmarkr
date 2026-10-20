/* The application shell: layer rows, the overview tables, the timeline
   scrubber, the three linked charts and the key-moments list. Everything
   here is rendered from the atlas model — no number on screen is written by
   hand, and when the library has no dates the time UI says so instead of
   inventing one. */

const MONTH = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const DAY = 86_400_000;

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
const num = (n) => n.toLocaleString("en-US");
const el = (id) => document.getElementById(id);

const BASE_LAYERS = [
  { id: "terrain", name: "Terrain", note: "3D", swatch: "linear-gradient(160deg,#cdbb95,#9b9386)" },
  { id: "forest", name: "Forests", note: "", swatch: "linear-gradient(160deg,#5c6b3e,#33462f)" },
  { id: "tints", name: "Region tints", note: "", swatch: "linear-gradient(160deg,#B4573A,#3F7D74)" },
  { id: "edges", name: "District edges", note: "", swatch: "repeating-linear-gradient(90deg,#6E685E 0 3px,#E2DDD0 3px 6px)" },
  { id: "markers", name: "Bookmark markers", note: "", swatch: "radial-gradient(circle at 50% 35%,#fff 0 30%,#B4573A 32%)" },
  { id: "trail", name: "Reading trail", note: "", swatch: "repeating-linear-gradient(90deg,#D9482B 0 4px,#E2DDD0 4px 7px)" },
  { id: "labels", name: "Labels & pins", note: "", swatch: "linear-gradient(160deg,#ECE8DF,#CFC8B8)" },
];

export class AtlasUI {
  constructor({ atlas, state, actions }) {
    this.atlas = atlas;
    this.state = state;
    this.actions = actions;
    this.charts = [];
  }

  /* ── one-time build ─────────────────────────────────────────────────── */
  build() {
    const a = this.atlas, s = this.state;
    el("library-name").textContent = a.label;
    el("chip-count").textContent = `${num(a.total)} bookmarks`;
    el("vp-status-text").textContent = a.demo ? "Demo library" : a.label;
    el("range-text").textContent = a.range ? `${fmtMonth(a.range.start)} – ${fmtMonth(a.range.end)}` : "No dates";
    el("badge-topics").textContent = a.regions.length;
    el("badge-sources").textContent = a.sources.length;
    el("badge-timeline").textContent = a.weeks.length ? `${a.weeks.length}w` : "—";
    el("tl-range").textContent = a.range ? `${fmtDate(a.range.start)} – ${fmtDate(a.range.end)}` : "This library has no save dates";

    this.buildLayers();
    this.buildMoments();
    this.buildAxis();
    this.buildCharts();
    this.wire();
    this.refresh();
  }

  wire() {
    const { actions } = this;
    document.querySelectorAll("#mode-tabs button").forEach((b) => {
      b.addEventListener("click", () => actions.setMode(b.dataset.mode));
    });
    document.querySelectorAll("#inspector-tabs button").forEach((b) => {
      b.addEventListener("click", () => actions.setTab(b.dataset.tab));
    });
    document.querySelectorAll("#dim-toggle button").forEach((b) => {
      b.addEventListener("click", () => actions.setDim(b.dataset.dim));
    });
    el("tp-play").addEventListener("click", () => actions.togglePlay());
    el("tp-prev").addEventListener("click", () => actions.stepMoment(-1));
    el("tp-next").addEventListener("click", () => actions.stepMoment(1));
    el("tp-speed").addEventListener("click", () => actions.cycleSpeed());
    el("detail-close").addEventListener("click", () => actions.select(null));
    el("d-fly").addEventListener("click", () => actions.flyToSelection());
    el("btn-reset").addEventListener("click", () => actions.resetView());
    el("ov-clear").addEventListener("click", () => actions.focusRegion(null));

    const track = el("tl-track");
    const scrub = (ev) => {
      const r = track.getBoundingClientRect();
      actions.setTime(Math.min(1, Math.max(0, (ev.clientX - r.left) / r.width)));
    };
    track.addEventListener("pointerdown", (ev) => {
      if (!this.atlas.range) return;
      track.setPointerCapture(ev.pointerId);
      this.scrubbing = true;
      scrub(ev);
    });
    track.addEventListener("pointermove", (ev) => { if (this.scrubbing) scrub(ev); });
    track.addEventListener("pointerup", () => { this.scrubbing = false; });
    window.addEventListener("resize", () => this.drawCharts());
  }

  /* ── layers ─────────────────────────────────────────────────────────── */
  layerRow({ key, swatch, name, note, count, opacity, visible, onToggle, onOpacity, onPick, selected }) {
    const row = document.createElement("div");
    row.className = `layer${visible ? " vis" : ""}${onPick ? " on-region" : ""}${selected ? " sel" : ""}`;
    row.dataset.key = key;
    row.innerHTML = `
      <span class="ck" role="checkbox" aria-checked="${visible}" tabindex="0"><svg viewBox="0 0 12 12" aria-hidden="true"><path d="M2.5 6.2 4.9 8.6 9.5 3.6" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/></svg></span>
      <span class="sw" style="background:${swatch}"></span>
      <span class="nm">${name}${note ? `<small>${note}</small>` : ""}</span>
      <span class="op"><i style="width:${Math.round(opacity * 100)}%"></i><u style="left:${Math.round(opacity * 100)}%"></u></span>
      <span class="pc">${count != null ? num(count) : `${Math.round(opacity * 100)}%`}</span>`;
    row.querySelector(".ck").addEventListener("click", (e) => { e.stopPropagation(); onToggle(); });
    const op = row.querySelector(".op");
    const drag = (ev) => {
      const r = op.getBoundingClientRect();
      onOpacity(Math.min(1, Math.max(0, (ev.clientX - r.left) / r.width)));
    };
    op.addEventListener("pointerdown", (ev) => { ev.stopPropagation(); op.setPointerCapture(ev.pointerId); op._d = true; drag(ev); });
    op.addEventListener("pointermove", (ev) => { if (op._d) drag(ev); });
    op.addEventListener("pointerup", () => { op._d = false; });
    if (onPick) row.addEventListener("click", onPick);
    return row;
  }

  buildLayers() {
    const s = this.state, a = this.atlas;
    const base = el("layers-base");
    base.textContent = "";
    for (const L of BASE_LAYERS) {
      base.appendChild(this.layerRow({
        key: L.id, swatch: L.swatch, name: L.name, note: L.note,
        opacity: s.layers[L.id].opacity, visible: s.layers[L.id].on,
        onToggle: () => this.actions.toggleLayer(L.id),
        onOpacity: (v) => this.actions.setLayerOpacity(L.id, v),
      }));
    }
    const data = el("layers-data");
    data.textContent = "";
    const bySource = s.mode === "sources";
    el("layers-data-title").textContent = bySource ? "Sources" : "Topics";
    el("layers-data-meta").textContent = bySource
      ? `${a.sources.length} · ${num(a.total)} saves`
      : `${a.regions.length} · ${num(a.total)} saves`;
    const rows = bySource ? a.sources : a.regions;
    for (const r of rows) {
      const key = (bySource ? "src:" : "reg:") + r.id;
      data.appendChild(this.layerRow({
        key, swatch: r.color, name: bySource ? r.label : r.name,
        note: bySource ? r.kind : `${r.districts.length} districts`,
        count: r.count ?? r.total,
        opacity: s.groupOpacity.get(key) ?? 1,
        visible: !s.hidden.has(key),
        selected: !bySource && s.focus === r.id,
        onToggle: () => this.actions.toggleGroup(key),
        onOpacity: (v) => this.actions.setGroupOpacity(key, v),
        onPick: bySource ? null : () => this.actions.focusRegion(s.focus === r.id ? null : r.id),
      }));
    }
  }

  /* ── overview / notes ───────────────────────────────────────────────── */
  buildOverview() {
    const a = this.atlas, s = this.state;
    const region = s.focus ? a.regions.find((r) => r.id === s.focus) : null;
    el("ov-title").textContent = region ? `${region.name} overview` : "Library overview";
    el("ov-clear").hidden = !region;

    const kv = el("ov-kv");
    kv.textContent = "";
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
        ["Bookmarks", num(a.total)],
        ["Topics", num(a.regions.length)],
        ["Subtopics", num(a.stats.subtopics)],
        ["Sources", num(a.sources.length)],
        ["First save", a.range ? fmtDate(a.range.start) : "—"],
        ["Last save", a.range ? fmtDate(a.range.end) : "—"],
        ["Top source", a.stats.topSource ? `${a.stats.topSource.label} · ${num(a.stats.topSource.count)}` : "—"],
      ];
    for (const [k, v] of pairs) {
      const row = document.createElement("div");
      row.innerHTML = `<dt>${k}</dt><dd>${v}</dd>`;
      kv.appendChild(row);
    }

    const stats = el("ov-stats");
    stats.textContent = "";
    const items = region ? region.items : a.items;
    const dated = items.filter((i) => i.at != null);
    const last30 = a.range ? dated.filter((i) => i.at > a.range.end - 30 * DAY).length : 0;
    const perWeek = a.weeks.length ? Math.round((dated.length / a.weeks.length) * 10) / 10 : 0;
    const tiles = [
      [num(last30), "saved · last 30 days"],
      [String(perWeek), "average per week"],
      [region ? num(region.districts.length) : num(a.stats.topRegion?.total ?? 0), region ? "districts" : `in ${a.stats.topRegion?.name || "—"}`],
      [a.range ? `${Math.max(1, Math.round((a.range.end - a.range.start) / DAY / 30.44))} mo` : "—", "of history"],
    ];
    for (const [b, c] of tiles) {
      const d = document.createElement("div");
      d.className = "stat";
      d.innerHTML = `<b>${b}</b><span>${c}</span>`;
      stats.appendChild(d);
    }

    el("ov-list-title").textContent = region ? "Districts" : s.mode === "sources" ? "Sources" : "Topics";
    const list = el("ov-list");
    list.textContent = "";
    for (const extraNode of document.querySelectorAll("[data-extra]")) extraNode.remove();
    const bars = region
      ? region.districts.map((d) => [d.name, d.total, region.color])
      : s.mode === "sources"
        ? a.sources.map((x) => [x.label, x.count, x.color])
        : a.regions.map((r) => [r.name, r.total, r.color]);
    const max = Math.max(1, ...bars.map((b) => b[1]));
    for (const [name, value, color] of bars.slice(0, 9)) {
      const row = document.createElement("div");
      row.className = "bar-row";
      row.innerHTML = `<span class="lbl">${name}</span><span class="val">${num(value)}</span>
        <span class="track"><i style="width:${Math.max(3, (value / max) * 100)}%;background:${color}"></i></span>`;
      list.appendChild(row);
    }

    // Second breakdown, so the inspector column stays full: topics mode shows
    // the source split underneath, sources mode shows the topic split.
    const extraTitle = region ? "Sources in this region" : s.mode === "sources" ? "Topics" : "Sources";
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
    const head = document.createElement("div");
    head.dataset.extra = "1";
    head.className = "pane-head";
    head.innerHTML = `<h2>${extraTitle}</h2><span class="pane-meta">${extra.length}</span>`;
    list.after(head);
    const list2 = document.createElement("div");
    list2.dataset.extra = "1";
    list2.className = "bar-list";
    const max2 = Math.max(1, ...extra.map((b) => b[1]));
    for (const [name, value, color] of extra.slice(0, 9)) {
      const row = document.createElement("div");
      row.className = "bar-row";
      row.innerHTML = `<span class="lbl">${name}</span><span class="val">${num(value)}</span>
        <span class="track"><i style="width:${Math.max(3, (value / max2) * 100)}%;background:${color}"></i></span>`;
      list2.appendChild(row);
    }
    head.after(list2);

    const notes = el("ov-notes");
    notes.textContent = "";
    for (const n of this.notes()) {
      const d = document.createElement("div");
      d.className = "note";
      d.innerHTML = `<i style="background:${n.color}"></i><span>${n.text}</span>`;
      notes.appendChild(d);
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

  /* Short observations, each one arithmetic on the model. */
  notes() {
    const a = this.atlas;
    const out = [];
    if (a.demo) out.push({ color: "#D9482B", text: `<b>Demo library.</b> ${num(a.total)} example bookmarks across ${a.regions.length} topics. Sign in on bookmarker.lol and this map is built from your own saves instead.` });
    if (a.stats.topRegion) out.push({ color: a.stats.topRegion.color, text: `<b>${a.stats.topRegion.name}</b> is the largest region — ${num(a.stats.topRegion.total)} saves, ${Math.round((a.stats.topRegion.total / a.total) * 100)}% of the library.` });
    if (a.range) {
      const recent = a.regions
        .map((r) => [r, r.items.filter((i) => i.at != null && i.at > a.range.end - 60 * DAY).length])
        .sort((x, y) => y[1] - x[1])[0];
      if (recent && recent[1] > 0) out.push({ color: recent[0].color, text: `<b>${recent[0].name}</b> is the most active topic right now: ${num(recent[1])} saves in the last 60 days.` });
      const newest = a.regions.filter((r) => r.first != null).sort((x, y) => y.first - x.first)[0];
      if (newest) out.push({ color: newest.color, text: `Newest region: <b>${newest.name}</b>, opened ${fmtDate(newest.first)}.` });
    }
    if (a.stats.topSource) out.push({ color: a.stats.topSource.color, text: `<b>${a.stats.topSource.label}</b> is where most of this library comes from — ${Math.round(a.stats.topSource.share * 100)}% of saves.` });
    if (a.stats.undated) out.push({ color: "#5C6A77", text: `${num(a.stats.undated)} bookmarks have no save date, so they sit outside the timeline.` });
    out.push({ color: "#5C6A77", text: `Marker height is recency: the taller the pin, the more recently it was saved.` });
    return out;
  }

  /* ── key moments ────────────────────────────────────────────────────── */
  buildMoments() {
    const a = this.atlas;
    const box = el("moments");
    box.textContent = "";
    el("moments-count").textContent = a.moments.length;
    if (!a.moments.length) {
      box.innerHTML = `<p class="empty">${a.range ? "Not enough history yet to call out any moments." : "This library has no save dates, so there is no timeline to read."}</p>`;
      return;
    }
    a.moments.forEach((m, i) => {
      const row = document.createElement("div");
      row.className = "moment";
      row.dataset.index = i;
      row.innerHTML = `<i style="background:${m.color}"></i>
        <span class="m-lbl">${m.label}<small>${m.detail}</small></span>
        <span class="m-date">${fmtShort(m.at)}</span>`;
      row.addEventListener("click", () => this.actions.goToMoment(i));
      box.appendChild(row);
    });
    const events = el("tl-events");
    events.textContent = "";
    for (const m of a.moments) {
      const i = document.createElement("i");
      i.style.background = m.color;
      i.style.left = `${this.frac(m.at) * 100}%`;
      events.appendChild(i);
    }
  }

  frac(ms) {
    const r = this.atlas.range;
    if (!r || r.end === r.start) return 1;
    return Math.min(1, Math.max(0, (ms - r.start) / (r.end - r.start)));
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
      const left = this.frac(t) * 100;
      const tick = document.createElement("i");
      tick.style.left = `${left}%`;
      axis.appendChild(tick);
      if (i % step) return;
      const label = document.createElement("span");
      const d = new Date(t);
      label.textContent = d.getUTCMonth() === 0 || i === 0 ? `${MONTH[d.getUTCMonth()]} ${d.getUTCFullYear()}` : MONTH[d.getUTCMonth()];
      label.style.left = `${left}%`;
      axis.appendChild(label);
    });
  }

  /* ── charts ─────────────────────────────────────────────────────────── */
  chartSpecs() {
    const a = this.atlas, s = this.state;
    const region = s.focus ? a.regions.find((r) => r.id === s.focus) : null;
    const weeks = a.weeks;
    const countsFor = (pick) => weeks.map((w) => pick(w));
    const scope = region ? region.name : s.mode === "sources" ? "all sources" : "all topics";

    const saves = {
      title: "Saves per week",
      sub: scope,
      unit: "saves",
      series: [{
        key: "all", color: region ? region.color : "#5C6A77", fill: true,
        values: countsFor((w) => (region ? w.byRegion[region.id] || 0 : w.count)),
      }],
    };

    if (s.mode === "sources") {
      const top = a.sources.slice(0, 5);
      let acc = new Map(top.map((t) => [t.id, 0]));
      const cumulative = top.map((t) => ({ key: t.id, color: t.color, label: t.label, values: [], fill: true }));
      weeks.forEach((w) => top.forEach((t, i) => {
        acc.set(t.id, acc.get(t.id) + (w.bySource[t.id] || 0));
        cumulative[i].values.push(acc.get(t.id));
      }));
      const share = top.slice(0, 4).map((t) => ({
        key: t.id, color: t.color, label: t.label, values: [],
      }));
      let run = new Map(top.map((t) => [t.id, 0])), tot = 0;
      weeks.forEach((w) => {
        top.forEach((t) => run.set(t.id, run.get(t.id) + (w.bySource[t.id] || 0)));
        tot += w.count;
        share.forEach((sv, i) => sv.values.push(tot ? (run.get(top[i].id) / tot) * 100 : 0));
      });
      return [
        saves,
        { title: "Library by source", sub: "cumulative", unit: "saves", stacked: true, series: cumulative },
        { title: "Source share", sub: "% of library", unit: "%", series: share, max: 100 },
      ];
    }

    const tops = region ? [] : a.regions.slice(0, 6);
    const stackSeries = (region ? region.districts.slice(0, 6) : tops).map((r, i) => ({
      key: r.id || r.name, color: region ? shade(region.color, i) : r.color, label: r.name, values: [], fill: true,
    }));
    if (region) {
      const run = region.districts.slice(0, 6).map(() => 0);
      weeks.forEach((w) => {
        region.districts.slice(0, 6).forEach((d, i) => {
          run[i] += d.items.filter((it) => it.at != null && it.at >= w.t && it.at < w.t + 7 * DAY).length;
          stackSeries[i].values.push(run[i]);
        });
      });
    } else {
      const run = tops.map(() => 0);
      weeks.forEach((w) => tops.forEach((r, i) => {
        run[i] += w.byRegion[r.id] || 0;
        stackSeries[i].values.push(run[i]);
      }));
    }

    const srcTop = a.sources.slice(0, 4);
    const lines = srcTop.map((t) => ({ key: t.id, color: t.color, label: t.label, values: [] }));
    const runS = srcTop.map(() => 0);
    weeks.forEach((w) => srcTop.forEach((t, i) => {
      runS[i] += (region ? (region.items.filter((it) => it.source === t.id && it.at != null && it.at >= w.t && it.at < w.t + 7 * DAY).length) : (w.bySource[t.id] || 0));
      lines[i].values.push(runS[i]);
    }));

    return [
      saves,
      { title: region ? "Districts over time" : "Library by topic", sub: "cumulative", unit: "saves", stacked: true, series: stackSeries },
      { title: "Sources mix", sub: "cumulative", unit: "saves", series: lines },
    ];
  }

  buildCharts() {
    const box = el("charts");
    box.textContent = "";
    this.charts = [0, 1, 2].map(() => {
      const c = document.createElement("div");
      c.className = "chart";
      c.innerHTML = `<div class="chart-head"><h3></h3><small></small><span class="now"></span></div><svg preserveAspectRatio="none"></svg>`;
      box.appendChild(c);
      return c;
    });
    this.drawCharts();
  }

  drawCharts() {
    const specs = this.chartSpecs();
    const a = this.atlas;
    this.charts.forEach((node, i) => {
      const spec = specs[i];
      node.querySelector("h3").textContent = spec.title;
      node.querySelector("small").textContent = spec.sub;
      const svg = node.querySelector("svg");
      const w = Math.max(80, svg.clientWidth || node.clientWidth - 24);
      const h = Math.max(40, svg.clientHeight || 70);
      if (!a.range || !a.weeks.length) {
        svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
        svg.innerHTML = `<text class="ax" x="6" y="${h / 2}">no save dates in this library</text>`;
        node.querySelector(".now").textContent = "";
        return;
      }
      svg.setAttribute("viewBox", `0 0 ${w} ${h}`);
      svg.innerHTML = this.chartSVG(spec, w, h);
      const cursorIndex = Math.min(a.weeks.length - 1, Math.round(this.state.time * (a.weeks.length - 1)));
      const nowVal = spec.stacked
        ? spec.series.reduce((m, s) => Math.max(m, s.values[cursorIndex] || 0), 0)
        : spec.series[0].values[cursorIndex] || 0;
      node.querySelector(".now").textContent = spec.unit === "%" ? `${Math.round(nowVal)}%` : num(Math.round(nowVal));
    });
  }

  chartSVG(spec, w, h) {
    const a = this.atlas;
    const padL = 24, padR = 4, padT = 6, padB = 13;
    const iw = w - padL - padR, ih = h - padT - padB;
    const n = a.weeks.length;
    const X = (i) => padL + (n < 2 ? iw / 2 : (i / (n - 1)) * iw);
    let max = spec.max || 0;
    if (!max) {
      for (const s of spec.series) for (const v of s.values) max = Math.max(max, v);
      if (spec.stacked) max = Math.max(max, ...spec.series.map((s) => Math.max(...s.values, 0)));
      max = Math.max(1, Math.ceil(max * 1.12));
    }
    const Y = (v) => padT + ih - (v / max) * ih;
    let out = "";
    // gridlines + y labels
    for (const frac of [0, 0.5, 1]) {
      const v = max * frac, y = Y(v);
      out += `<line class="gl" x1="${padL}" x2="${w - padR}" y1="${y.toFixed(1)}" y2="${y.toFixed(1)}"/>`;
      out += `<text class="ax" x="${padL - 4}" y="${(y + 3).toFixed(1)}" text-anchor="end">${spec.unit === "%" ? Math.round(v) : num(Math.round(v))}</text>`;
    }
    const path = (vals) => vals.map((v, i) => `${i ? "L" : "M"}${X(i).toFixed(1)} ${Y(v).toFixed(1)}`).join(" ");
    const ordered = spec.stacked ? spec.series.slice().reverse() : spec.series;
    for (const s of ordered) {
      if (s.fill) {
        out += `<path d="${path(s.values)} L${X(n - 1).toFixed(1)} ${Y(0).toFixed(1)} L${X(0).toFixed(1)} ${Y(0).toFixed(1)} Z" fill="${s.color}" fill-opacity="${spec.stacked ? 0.55 : 0.22}"/>`;
      }
      out += `<path d="${path(s.values)}" fill="none" stroke="${s.color}" stroke-width="1.4" stroke-linejoin="round"/>`;
    }
    // x labels: first and last month
    out += `<text class="ax" x="${padL}" y="${h - 3}">${fmtMonth(a.weeks[0].t)}</text>`;
    out += `<text class="ax" x="${w - padR}" y="${h - 3}" text-anchor="end">${fmtMonth(a.weeks[n - 1].t)}</text>`;
    // shared cursor
    const ci = Math.min(n - 1, Math.round(this.state.time * (n - 1)));
    const cx = X(ci);
    out += `<line x1="${cx.toFixed(1)}" x2="${cx.toFixed(1)}" y1="${padT}" y2="${padT + ih}" stroke="#1E1C19" stroke-width="1"/>`;
    for (const s of spec.series) {
      const v = s.values[ci];
      if (v == null) continue;
      out += `<circle cx="${cx.toFixed(1)}" cy="${Y(v).toFixed(1)}" r="2.6" fill="#ECE8DF" stroke="${s.color}" stroke-width="1.5"/>`;
    }
    return out;
  }

  /* ── per-frame refresh ──────────────────────────────────────────────── */
  refresh() {
    const a = this.atlas, s = this.state;
    document.querySelectorAll("#mode-tabs button").forEach((b) => b.classList.toggle("on", b.dataset.mode === s.mode));
    document.querySelectorAll("#inspector-tabs button").forEach((b) => b.classList.toggle("on", b.dataset.tab === s.tab));
    document.querySelectorAll("#dim-toggle button").forEach((b) => b.classList.toggle("on", b.dataset.dim === s.dim));
    document.querySelectorAll(".pane").forEach((p) => { p.hidden = p.dataset.pane !== s.tab; });
    el("tp-play").querySelector(".i-play").hidden = s.playing;
    el("tp-play").querySelector(".i-pause").hidden = !s.playing;
    el("tp-speed").textContent = `${s.speed}×`;

    const pct = s.time * 100;
    el("tl-fill").style.width = `${pct}%`;
    el("tl-knob").style.left = `${pct}%`;
    el("tl-cursor").textContent = a.range ? fmtDate(this.timeAt(s.time)) : "—";
    document.querySelectorAll(".moment").forEach((m, i) => m.classList.toggle("on", i === s.moment));

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
    el("d-source").innerHTML = `<i style="background:${src ? src.color : "#6E685E"}"></i>${item.sourceLabel}`;
    el("d-meta").textContent = item.meta || "";
    el("d-title").textContent = item.title;
    el("d-path").textContent = `${item.regionName} › ${item.district}`;
    const kv = el("d-kv");
    kv.textContent = "";
    const rows = [
      ["Saved", item.at != null ? fmtDate(item.at) : "no date"],
      ["Source", item.sourceLabel],
      ["Region", item.regionName],
    ];
    for (const [k, v] of rows) {
      const d = document.createElement("div");
      d.innerHTML = `<dt>${k}</dt><dd>${v}</dd>`;
      kv.appendChild(d);
    }
    const tags = el("d-tags");
    tags.textContent = "";
    for (const t of [item.district, item.sourceLabel, item.meta].filter(Boolean)) {
      const s = document.createElement("span");
      s.textContent = t;
      tags.appendChild(s);
    }
    const open = el("d-open");
    open.href = item.url || "#";
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
    tip.innerHTML = `<b>${item.title}</b><span>${item.sourceLabel} · ${item.at != null ? fmtDate(item.at) : "no date"} · ${item.regionName}</span>`;
  }

  setZoom(text) { el("zoom-read").textContent = text; }
  setScale(px, midLabel, maxLabel) {
    const w = `${Math.max(40, Math.min(190, px))}px`;
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

/* A darker/lighter step of a district colour, so one region's districts stay
   recognisably the same family. */
function shade(hex, i) {
  const n = parseInt(hex.slice(1), 16);
  const k = 1 + (i - 2.5) * 0.17;
  const ch = (v) => Math.max(0, Math.min(255, Math.round(v * k)));
  return `#${((ch((n >> 16) & 255) << 16) | (ch((n >> 8) & 255) << 8) | ch(n & 255)).toString(16).padStart(6, "0")}`;
}
