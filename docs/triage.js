/* bookmarker — "Sort your borks", the triage deck, on the web.
 *
 * One bork at a time with the Quick File dial under it, until everything has
 * a home. Two decks: "Not filed yet" (no topic that still exists, newest
 * first) and "Check our guesses" (automatic filings from the last 30 days
 * whose ranking today is not strong, each showing its current guess first).
 * Filing a card flies it into its tally chip — a View Transition where the
 * browser has them — and the next card is already ranked. Memory learns as you
 * go (FilingMemory.adding), so the second post from a creator you just filed
 * arrives already sure. The model is asked only when you are signed in, never
 * in the demo, only for the next two cards with no evidence at all, and at
 * most 12 times a session: its 200-a-day quota is shared with everything else.
 *
 *   Triage.summary(rows)        → { unfiled, guesses }
 *   Triage.open({ deck, id })   deck "unfiled" | "guesses" | "one" (one needs id)
 *   Triage.use(host)            how the page lends it rows, topics and writes
 *
 * Anything carrying data-triage="unfiled" | "guesses" | "one" (and data-id)
 * opens it through this file's own click listener, and F on a focused library
 * card opens a deck of one, so the page's shared click delegate never changes.
 * Inside: the dial's keys, S skip, Z undo, Backspace remove, Esc done.
 *
 * The host (index.html builds one; the lab page builds another in memory):
 *   rows()              live rows             row(id)      one of them (optional)
 *   valid(id)           a topic that exists   topic(id)    → {id, name, hue, art, subs}
 *   order()             taxonomy order        memory()     FilingMemory of your own filings
 *   display(row)        → {title, author}     picture(row) → image URL or null
 *   glyph(platform)     icon HTML             platform(p)  → "TikTok"     date(iso) → "2d ago"
 *   file(row, c)        write the filing, return the row as it was
 *   remove(row)         tombstone it, return the row as it was
 *   restore(prev)       put a row back exactly as it was
 *   ai(row)             Promise<{topic, subtopic, confidence} | null>
 *   more(row, c, done)  the full picker; done({categoryID, subcategory} | null)
 *   signedIn(), demo(), toast(msg, label, fn), changed(), track(name, props)
 *   compass             the end screen's clay art (a URL or a list to try)
 */
"use strict";

const Triage = (() => {
  const DAY = 86_400_000, GUESS_DAYS = 30;
  const AI_CAP = 12, AI_NEXT = 2, AI_LOOK = 6;
  const BUDGET_MS = 12;
  const KIND_WORD = { reel: "Reel", clip: "Clip", short: "Short", video: "Video", thread: "Thread", post: "Post", pin: "Pin", article: "Article" };

  let host = null;
  let S = null;                  // the open session
  let ui = null;                 // the dialog, built on first open
  let sweepTimer = null;
  const verdicts = new Map();    // row id → {stamp, strong}: is its guess strong today?
  const answers = new Map();     // row id → the model's answer; undefined while asking, null for none
  const badPics = new Set();     // covers that failed: drawn as posters from then on

  const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
  const clock = () => (typeof performance === "object" ? performance.now() : Date.now());
  const call = (name, ...args) => (host && typeof host[name] === "function" ? host[name](...args) : undefined);
  const reduced = () => (typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches)
    || !!document.querySelector(".qf-reduced");
  const firstArt = (art) => (Array.isArray(art) ? art.find(Boolean) : art) || null;
  const cssId = (s) => (typeof CSS === "object" && CSS.escape ? CSS.escape(s) : String(s).replace(/["\\]/g, "\\$&"));

  /* ── What counts ──────────────────────────────────────────────────────── */
  function valid(id) {
    if (!id) return false;
    if (host && typeof host.valid === "function") return !!host.valid(id);
    if (typeof topicFor === "function") return !!topicFor(id);   // the page, before use() has run
    return typeof TAXONOMY === "object" && TAXONOMY.some((t) => t.id === id);
  }
  const live = () => (call("rows") || []).filter((r) => r && !r.deleted_at);
  const rowByID = (id) => call("row", id) || live().find((r) => r.id === id) || null;
  const baseMemory = () => call("memory") || FilingMemory.empty();
  const order = () => call("order") || TAXONOMY.map((t) => t.id);
  const topic = (id) => (id && valid(id) && call("topic", id)) || null;
  const savedAt = (r) => Date.parse(r.saved_at || r.updated_at || "") || 0;
  const isGuess = (r, cutoff) => r.filing_source === "automatic" && valid(r.category_id) && savedAt(r) >= cutoff;

  function inputOf(r) {
    return { url: r.url || "", title: r.title || "", text: r.body_text || null, description: null, author: r.author || null, ocrText: null };
  }
  /* A filing the save already has leads the ring: a guess we stored, or one
     you chose (legacy saves with no source count as yours, never nagged). */
  function pinOf(r) {
    if (!valid(r.category_id)) return null;
    return { categoryID: r.category_id, subcategory: r.subcategory || null, reason: r.filing_source === "automatic" ? "guess" : "yours" };
  }
  function rank(r, memory, ai) {
    return FilingSuggest.rank(inputOf(r), memory, { ai: ai || null, pinned: pinOf(r), taxonomyOrder: order(), now: Date.now() });
  }
  function verdict(r, memory, until, later) {
    const hit = verdicts.get(r.id);
    if (hit && hit.stamp === r.updated_at) return hit.strong;
    if (until && clock() > until) { later.push(r); return null; }
    const strong = rank(r, memory).evidence === "strong";
    verdicts.set(r.id, { stamp: r.updated_at, strong });
    return strong;
  }

  /** How many saves each deck holds: { unfiled, guesses }. Cheap enough to
      call on every render: rankings are cached per row and stamp, and a big
      first pass is finished a slice at a time, after which the page is told
      to draw again (an unranked guess counts as one to check meanwhile). */
  function summary(rows) {
    const list = Array.isArray(rows) ? rows : live();
    const cutoff = Date.now() - GUESS_DAYS * DAY, until = clock() + BUDGET_MS, later = [];
    let unfiled = 0, guesses = 0, memory = null;
    for (const r of list) {
      if (!r || r.deleted_at) continue;
      if (!valid(r.category_id)) { unfiled++; continue; }
      if (!isGuess(r, cutoff)) continue;
      memory = memory || baseMemory();
      if (verdict(r, memory, until, later) !== true) guesses++;
    }
    if (later.length) sweep(later);
    return { unfiled, guesses };
  }
  function sweep(rows) {
    if (sweepTimer) return;
    const queue = rows.slice();
    const step = () => {
      const memory = baseMemory(), until = clock() + 10;
      while (queue.length && clock() < until) verdict(queue.pop(), memory);
      if (queue.length) { sweepTimer = setTimeout(step, 16); return; }
      sweepTimer = null;
      call("changed");
    };
    sweepTimer = setTimeout(step, 30);
  }

  function deck(kind, id) {
    const rows = live();
    const newest = (a, b) => (savedAt(b) - savedAt(a)) || (a.id < b.id ? -1 : a.id > b.id ? 1 : 0);
    if (kind === "one") return rows.filter((r) => r.id === id).map((r) => r.id);
    if (kind === "guesses") {
      const cutoff = Date.now() - GUESS_DAYS * DAY, memory = baseMemory();
      return rows.filter((r) => isGuess(r, cutoff) && verdict(r, memory) !== true).sort(newest).map((r) => r.id);
    }
    return rows.filter((r) => !valid(r.category_id)).sort(newest).map((r) => r.id);
  }

  /* ── A session ────────────────────────────────────────────────────────── */
  function begin(kind, id, carry) {
    const base = carry ? carry.base : baseMemory();
    S = {
      kind, id, queue: deck(kind, id), pos: 0,
      base, picks: carry ? carry.picks : [], memory: carry ? carry.memory : base, version: carry ? carry.version + 1 : 0,
      tallies: carry ? carry.tallies : new Map(), sorted: carry ? carry.sorted : 0,
      started: carry ? carry.started : Date.now(), aiCalls: carry ? carry.aiCalls : 0,
      undo: [], rankings: new Map(), dial: null, row: null,
    };
  }
  function current() {
    while (S && S.pos < S.queue.length) {
      const r = rowByID(S.queue[S.pos]);
      if (r) return r;
      S.queue.splice(S.pos, 1);   // deleted somewhere else meanwhile
    }
    return null;
  }
  function rankingFor(r) {
    const ai = answers.get(r.id) || null;
    const key = `${r.id}|${S.version}|${ai ? 1 : 0}`;
    let hit = S.rankings.get(key);
    if (!hit) { hit = rank(r, S.memory, ai); S.rankings.set(key, hit); }
    return hit;
  }

  /* ── The dialog ───────────────────────────────────────────────────────── */
  const UNDO_ICON = `<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M9 14 4 9l5-5"/><path d="M4 9h10.5a5.5 5.5 0 0 1 0 11H11"/></svg>`;
  function build() {
    if (ui) return ui;
    const d = document.createElement("dialog");
    d.className = "triage";
    d.id = "triage-dialog";
    d.setAttribute("aria-labelledby", "tri-h");
    d.innerHTML = `
  <div class="tri-top">
    <button type="button" class="tri-btn tri-done" data-tri="done">Done</button>
    <div class="tri-title"><h2 id="tri-h">Sort your borks</h2>
      <div class="tri-count"><span class="tri-n"></span><span class="tri-bar" aria-hidden="true"><i></i></span></div></div>
    <button type="button" class="tri-btn tri-undo" data-tri="undo" disabled>${UNDO_ICON}Undo</button>
  </div>
  <div class="tri-decks" role="tablist" aria-label="Which borks">
    <button type="button" role="tab" data-tri-deck="unfiled" aria-selected="true">Not filed yet<span class="n"></span></button>
    <button type="button" role="tab" data-tri-deck="guesses" aria-selected="false">Check our guesses<span class="n"></span></button>
  </div>
  <div class="tri-tally" aria-label="Sorted so far"></div>
  <div class="tri-body">
    <div class="tri-stack"></div>
    <div class="tri-side">
      <p class="tri-head"></p>
      <div class="tri-dial"></div>
      <div class="tri-actions">
        <button type="button" class="tri-btn tri-skip" data-tri="skip">Skip <kbd aria-hidden="true">S</kbd></button>
        <button type="button" class="tri-btn tri-remove" data-tri="remove">Remove</button>
      </div>
    </div>
  </div>
  <div class="tri-end" hidden>
    <img class="tri-end-art" alt="" decoding="async">
    <h2>Everything has a home.</h2>
    <p class="tri-end-sub"></p>
    <div class="tri-end-acts">
      <button type="button" class="btn tri-end-next" data-tri="guesses" hidden></button>
      <button type="button" class="btn ghost" data-tri="done">Done</button>
    </div>
  </div>
  <p class="qf-sr tri-live" aria-live="polite"></p>`;
    document.body.appendChild(d);
    const q = (sel) => d.querySelector(sel);
    ui = {
      d, n: q(".tri-n"), bar: q(".tri-bar i"), undo: q("[data-tri=undo]"), decks: q(".tri-decks"),
      tally: q(".tri-tally"), body: q(".tri-body"), stack: q(".tri-stack"), head: q(".tri-head"),
      dial: q(".tri-dial"), end: q(".tri-end"), endArt: q(".tri-end-art"), endSub: q(".tri-end-sub"),
      endNext: q(".tri-end-next"), live: q(".tri-live"),
    };
    d.addEventListener("click", onClick);
    d.addEventListener("keydown", onKey);
    d.addEventListener("cancel", (e) => { e.preventDefault(); close(); });
    d.addEventListener("error", (e) => {
      const img = e.target;
      if (!(img instanceof HTMLImageElement)) return;
      if (img.closest(".tri-cover")) {
        badPics.add(img.getAttribute("src"));
        const r = S && current();
        if (r) renderCard(r, false);
      } else if (img === ui.endArt) {
        nextImage(img);
      } else img.remove();
    }, true);
    return ui;
  }
  function setImage(img, art) {
    const list = (Array.isArray(art) ? art : [art]).filter(Boolean);
    img.dataset.chain = JSON.stringify(list);
    if (list[0] && img.getAttribute("src") !== list[0]) img.src = list[0];
  }
  function nextImage(img) {
    let list = [];
    try { list = JSON.parse(img.dataset.chain || "[]"); } catch { list = []; }
    const i = list.indexOf(img.getAttribute("src"));
    if (i >= 0 && list[i + 1]) img.src = list[i + 1]; else img.hidden = true;
  }
  const say = (text) => { if (!ui) return; ui.live.textContent = ""; setTimeout(() => { if (ui) ui.live.textContent = text; }, 30); };

  function onClick(e) {
    if (e.target === ui.d) {   // the backdrop, on a screen wide enough to have one
      const r = ui.d.getBoundingClientRect();
      if (e.clientX < r.left || e.clientX > r.right || e.clientY < r.top || e.clientY > r.bottom) close();
      return;
    }
    const b = e.target.closest("[data-tri], [data-tri-deck]");
    if (!b || b.disabled) return;
    if (b.dataset.triDeck) { switchDeck(b.dataset.triDeck); return; }
    const act = b.dataset.tri;
    if (act === "done") close();
    else if (act === "undo") undo();
    else if (act === "skip") skip();
    else if (act === "remove") remove();
    else if (act === "guesses") switchDeck("guesses");
  }
  function onKey(e) {
    if (!S || e.altKey || e.defaultPrevented) return;
    if (e.target instanceof Element && e.target.closest("input, textarea, select, [contenteditable]")) return;
    const k = e.key;
    if ((k === "z" || k === "Z") && !e.shiftKey) { e.preventDefault(); undo(); return; }
    if (e.metaKey || e.ctrlKey) return;
    if (k === "s" || k === "S") { e.preventDefault(); skip(); }
    else if (k === "Backspace" || k === "Delete") { e.preventDefault(); remove(); }
  }

  /* ── Drawing ──────────────────────────────────────────────────────────── */
  function render({ rise = false } = {}) {
    if (!S || !ui) return;
    const total = S.queue.length;
    const r = current();
    ui.n.textContent = !total ? "Nothing waiting" : r ? `${S.pos + 1} of ${total}` : `${total} of ${total}`;
    ui.bar.style.width = `${total ? Math.round((Math.min(S.pos, total) / total) * 100) : 100}%`;
    ui.undo.disabled = !S.undo.length;
    ui.decks.hidden = S.kind === "one";
    const counts = summary();
    for (const b of ui.decks.querySelectorAll("[data-tri-deck]")) {
      const on = b.dataset.triDeck === S.kind;
      b.setAttribute("aria-selected", String(on));
      b.querySelector(".n").textContent = String(on ? Math.max(0, total - S.pos) : counts[b.dataset.triDeck] || 0);
    }
    renderTally();
    ui.body.hidden = !r;
    ui.end.hidden = !!r;
    if (!r) { destroyDial(); renderEnd(); return; }
    renderCard(r, rise);
    mountDial(r);
    prefetch();
  }

  function renderTally() {
    if (!S.tallies.size) {
      const fine = typeof matchMedia === "function" && matchMedia("(hover: hover) and (pointer: fine)").matches;
      ui.tally.innerHTML = `<p class="tri-hint">${fine ? "Turn the dial · 1–7 files · S skips · Z undoes" : "Tap a topic, or turn the dial and tap the middle"}</p>`;
      return;
    }
    const P = Palette;
    ui.tally.innerHTML = [...S.tallies].map(([id, n]) => {
      const t = topic(id), hue = t ? t.hue : P.NEUTRAL_HUE, art = firstArt(t && t.art);
      return `<span class="tri-chip" data-topic="${esc(id)}" style="${P.chip(hue)}">`
        + (art ? `<img src="${esc(art)}" alt="">` : `<span class="tri-chip-ini">${esc((t?.name || id).charAt(0))}</span>`)
        + `${esc(t ? t.name : id)} <b>${n}</b></span>`;
    }).join("");
  }

  function cardHTML(r, rise) {
    const P = Palette;
    const d = call("display", r) || { title: r.title || r.url, author: r.author };
    const title = d.title || r.title || r.url || "Untitled";
    const t = topic(r.category_id);
    const hue = t ? t.hue : P.NEUTRAL_HUE;
    const g = call("glyph", r.platform) || "";
    const plat = call("platform", r.platform) || r.platform || "";
    const when = call("date", r.saved_at) || "";
    const where = t ? QuickFileDial.label({ categoryID: r.category_id, subcategory: r.subcategory }, t) : "Not filed yet";
    const cls = `tri-card${rise ? " is-rising" : ""}`;
    const pic = call("picture", r);
    const secs = Number(r.duration_seconds) || 0;
    const dur = secs ? `<span class="tri-dur"><span aria-hidden="true">▶</span>${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, "0")}</span>` : "";
    if (pic && !badPics.has(pic)) {
      return `<article class="${cls} tri-media" data-id="${esc(r.id)}">
        <div class="tri-cover" style="background-image:${P.gradient(hue)}"><img src="${esc(pic)}" alt="" decoding="async"><span class="badge" role="img" aria-label="${esc(plat)}">${g}</span>${dur}</div>
        <div class="tri-card-body"><div class="tri-who">${g}<span>${esc(d.author || plat)}</span></div>
          <div class="tri-title-t">${esc(title)}</div>
          <div class="tri-meta"><span class="tri-filed${t ? "" : " is-none"}"${t ? ` style="${P.chip(hue)}"` : ""}>${esc(where)}</span><span>${esc(when)}</span></div></div>
      </article>`;
    }
    const art = firstArt(t && t.art);
    const kind = KIND_WORD[r.kind] || plat;
    return `<article class="${cls} tri-poster${t ? "" : " is-unfiled"}" data-id="${esc(r.id)}" style="--tri-tint:color-mix(in srgb, ${P.tint(hue)} 58%, #fff);--tri-deep:${P.deep(hue)}">
      <span class="tri-wm" aria-hidden="true">${g}</span>
      <div class="tri-poster-top"><span class="badge" role="img" aria-label="${esc(plat)}">${g}</span><span>${esc(kind)}${d.author ? ` · ${esc(d.author)}` : ""}</span></div>
      <div class="tri-poster-title">${esc(title)}</div>
      <div class="tri-poster-foot"><span class="tri-stamp">${art ? `<img src="${esc(art)}" alt="">` : g}</span><span>${esc(where)}</span>${dur ? `<span>${dur.replace(/<[^>]+>/g, "")}</span>` : ""}<span class="when">${esc(when)}</span></div>
    </article>`;
  }
  function renderCard(r, rise) {
    const left = S.queue.length - S.pos - 1;
    ui.stack.innerHTML = (left >= 2 ? `<div class="tri-peek" style="--k:2" aria-hidden="true"></div>` : "")
      + (left >= 1 ? `<div class="tri-peek" style="--k:1" aria-hidden="true"></div>` : "")
      + cardHTML(r, rise && !reduced());
  }

  function mountDial(r) {
    destroyDial();
    S.row = r.id;
    const ranking = rankingFor(r);
    paintHead(r, ranking);
    S.dial = QuickFileDial.mount(ui.dial, {
      ranking, mode: "triage", topic: (id) => topic(id), input: inputOf(r),
      onConfirm: (c, how) => file(r.id, c, how),
      onMore: () => pickMore(r.id),
      onLater: () => close(),
    });
    S.dial.focus();
  }
  function paintHead(r, ranking) {
    const pin = pinOf(r);
    const h = QuickFileDial.header(ranking, { yours: pin?.reason === "yours" });
    ui.head.textContent = `${h.icon} ${h.text}`;
  }
  function destroyDial() {
    if (S && S.dial) { S.dial.destroy(); S.dial = null; }
  }

  function renderEnd() {
    const secs = Math.max(1, Math.round((Date.now() - S.started) / 1000));
    const took = secs < 60 ? `${secs} s` : `${Math.floor(secs / 60)} min${secs % 60 ? ` ${secs % 60} s` : ""}`;
    ui.endSub.textContent = S.sorted ? `${S.sorted} sorted in ${took}`
      : S.kind === "guesses" ? "Every guess we made looks right." : "Nothing waiting — every bork is filed.";
    setImage(ui.endArt, host.compass || "/img/quests/compass.jpg");
    ui.endArt.hidden = false;
    const counts = summary();
    const more = S.kind === "unfiled" && counts.guesses > 0;
    ui.endNext.hidden = !more;
    if (more) ui.endNext.textContent = `Check ${counts.guesses} ${counts.guesses === 1 ? "guess" : "guesses"}`;
    say(ui.endSub.textContent ? `Everything has a home. ${ui.endSub.textContent}` : "Everything has a home.");
    (more ? ui.endNext : ui.end.querySelector("[data-tri=done]")).focus();
  }

  /* ── Acting ───────────────────────────────────────────────────────────── */
  function file(id, c, how) {
    if (!S || S.row !== id) return;
    const r = rowByID(id);
    if (!r) return;
    const t = topic(c.categoryID);
    const prev = call("file", r, c) || { ...r };
    const item = {
      categoryID: c.categoryID, subcategory: c.subcategory || null,
      creator: FilingKeys.creator(r.author ?? null, r.url || ""), domain: FilingKeys.domain(r.url || ""),
      at: new Date().toISOString(),
    };
    S.picks.push(item);
    S.memory = FilingMemory.adding(S.memory, [item], { now: Date.now() });
    S.version++;
    S.tallies.set(c.categoryID, (S.tallies.get(c.categoryID) || 0) + 1);
    S.sorted++;
    S.undo.push({ kind: "file", id, prev, pos: S.pos, topic: c.categoryID });
    S.pos++;
    call("track", "triage_filed", { how, deck: S.kind });
    const where = QuickFileDial.label(c, t);
    say(`Filed under ${where}.`);
    if (S.kind === "one") {   // a deck of one closes on its own, with the undo in the toast
      close();
      call("toast", `Filed to ${where}`, "Undo", () => call("restore", prev));
      return;
    }
    advance(c.categoryID);
  }
  function advance(flyTo) {
    const card = ui.stack.querySelector(".tri-card");
    const canFly = flyTo && card && typeof document.startViewTransition === "function" && !reduced();
    if (!canFly) { render({ rise: true }); return; }
    card.style.viewTransitionName = "tri-fly";
    const rootEl = document.documentElement;
    rootEl.classList.add("tri-vt");
    let vt;
    try {
      vt = document.startViewTransition(() => {
        render({ rise: true });
        const chip = ui.tally.querySelector(`[data-topic="${cssId(flyTo)}"]`);
        if (chip) chip.style.viewTransitionName = "tri-fly";
      });
    } catch {
      rootEl.classList.remove("tri-vt");
      render({ rise: true });
      return;
    }
    const clean = () => {
      rootEl.classList.remove("tri-vt");
      if (ui) for (const chip of ui.tally.querySelectorAll(".tri-chip")) chip.style.viewTransitionName = "";
    };
    vt.finished.then(clean, clean);
  }
  function skip() {
    if (!S || !current()) return;
    S.undo.push({ kind: "skip", pos: S.pos });
    S.pos++;
    say("Skipped.");
    render({ rise: true });
  }
  function remove() {
    const r = S && current();
    if (!r) return;
    const prev = call("remove", r) || { ...r };
    S.undo.push({ kind: "remove", id: r.id, prev, pos: S.pos });
    S.pos++;
    say("Removed. Press Z to undo.");
    render({ rise: true });
  }
  function undo() {
    if (!S) return;
    const u = S.undo.pop();
    if (!u) return;
    if (u.kind === "file") {
      call("restore", u.prev);
      S.picks.pop();
      S.memory = S.picks.length ? FilingMemory.adding(S.base, S.picks, { now: Date.now() }) : S.base;
      S.version++;
      const n = (S.tallies.get(u.topic) || 1) - 1;
      if (n > 0) S.tallies.set(u.topic, n); else S.tallies.delete(u.topic);
      S.sorted = Math.max(0, S.sorted - 1);
    } else if (u.kind === "remove") {
      call("restore", u.prev);
    }
    S.pos = u.pos;
    say("Undone.");
    render({ rise: true });
  }
  function switchDeck(kind) {
    if (!S || kind === S.kind) return;
    destroyDial();
    begin(kind === "guesses" ? "guesses" : "unfiled", null, S);
    render({ rise: true });
  }
  function pickMore(id) {
    const r = rowByID(id);
    if (!r || !host || typeof host.more !== "function") return;
    const slot = S.dial ? S.dial.highlighted : null;
    const ranking = rankingFor(r);
    const c = slot !== null && slot < 7 ? ranking.candidates[slot] : ranking.candidates[0] || null;
    host.more(r, c, (picked) => {
      if (!S || S.row !== id) return;
      if (!picked || !picked.categoryID) { if (S.dial) S.dial.focus(); return; }
      file(id, { categoryID: picked.categoryID, subcategory: picked.subcategory || null, score: 0, reasons: ["yours"], altSubs: [], creator: null, creatorPicks: 0, matched: null }, "more");
    });
  }

  /* The model, for the next two cards that have nothing else to go on. */
  function prefetch() {
    if (!S || !host || typeof host.ai !== "function" || !call("signedIn") || call("demo")) return;
    let found = 0;
    for (let i = S.pos; i < S.queue.length && i < S.pos + AI_LOOK && found < AI_NEXT; i++) {
      const r = rowByID(S.queue[i]);
      if (!r || rankingFor(r).evidence !== "none") continue;
      found++;
      if (answers.has(r.id) || S.aiCalls >= AI_CAP) continue;
      S.aiCalls++;
      answers.set(r.id, undefined);
      const session = S;
      Promise.resolve(host.ai(r)).then((answer) => {
        answers.set(r.id, answer || null);
        if (!answer || S !== session || S.row !== r.id || !S.dial) return;
        const ranking = rankingFor(r);
        if (!S.dial.touched) paintHead(r, ranking);
        S.dial.offer(ranking);
      }, () => answers.set(r.id, null));
    }
  }

  /* ── Open and close ───────────────────────────────────────────────────── */
  function open({ deck: kind = "unfiled", id = null } = {}) {
    if (!host || typeof FilingSuggest !== "object" || typeof QuickFileDial !== "object") return false;
    const k = kind === "one" ? "one" : kind === "guesses" ? "guesses" : "unfiled";
    if (k === "one" && !id) return false;
    build();
    destroyDial();
    begin(k, id, null);
    render();
    if (!ui.d.open) {
      if (typeof openDlg === "function") openDlg(ui.d); else ui.d.showModal();
    }
    if (S.dial) S.dial.focus();
    call("track", "triage_opened", { deck: k, count: S.queue.length });
    return true;
  }
  function close() {
    if (!ui) return;
    destroyDial();
    const had = !!S;
    S = null;
    if (ui.d.open) {
      if (typeof closeDlg === "function") closeDlg(ui.d); else ui.d.close();
    }
    if (had) call("changed");
  }
  function use(h) { host = h || null; verdicts.clear(); }

  /* ── The page's doors ─────────────────────────────────────────────────── */
  if (typeof document === "object" && document && typeof document.addEventListener === "function") {
    // Capture, so the shared click delegate never also opens the card underneath.
    document.addEventListener("click", (e) => {
      const el = e.target instanceof Element ? e.target.closest("[data-triage]") : null;
      if (!el) return;
      e.preventDefault();
      e.stopPropagation();
      open({ deck: el.dataset.triage, id: el.dataset.id || null });
    }, true);
    // F on a focused library card: a deck of just that one.
    document.addEventListener("keydown", (e) => {
      if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey || e.repeat) return;
      if (e.key !== "f" && e.key !== "F") return;
      const card = e.target instanceof Element ? e.target : null;
      if (!card || !card.matches(".card[data-id]") || document.querySelector("dialog[open]")) return;
      if (open({ deck: "one", id: card.dataset.id })) e.preventDefault();
    });
  }

  return Object.freeze({ summary, open, close, use, get isOpen() { return !!S; } });
})();

if (typeof globalThis === "object") globalThis.Triage = Triage;
if (typeof module === "object" && module.exports) module.exports = { Triage };
