#!/usr/bin/env node
/**
 * Builds docs/lab/quick-file.html, the Quick File lab: the real dial and the
 * real triage deck, on ten made-up saves, in one file with no dependencies
 * but the Google Fonts link.
 *
 *     node Scripts/build_quick_file_demo.mjs
 *
 * Nothing in the page is a copy. It inlines docs/taxonomy.js, docs/import.js
 * (Filer), docs/filing-suggest.js, docs/palette.js, docs/quick-file.js,
 * docs/triage.js and docs/quick-file.css, plus three things cut out of
 * docs/index.html: its :root tokens, the platform glyph sprite, and the
 * helper block from `const ENT = {` to `/* ── Session ── *\/` (PLATFORM,
 * detectPlatform, glyph). So the lab can never drift from the product: change
 * a source, run this again.
 *
 * The page is `noindex`, and it is not in sitemap.xml or Scripts/check-seo.mjs
 * (which lists its pages by hand). Two modes, "After a share" and "Sort my
 * borks", plus a late-AI toggle, reduced motion, list mode and an optional
 * tick. URL switches for screenshots: ?mode=triage opens the deck at once,
 * &save=N starts on save N, &ai=1, &reduced=1, &list=1.
 *
 * Try it on a phone: python3 -m http.server 8765 --bind 0.0.0.0 --directory docs
 * then open http://<your-mac>:8765/lab/quick-file.html. Topic art comes from
 * ../img/topics, then https://bookmarker.lol/img/topics, then a colour disc.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => fs.readFileSync(path.join(ROOT, p), "utf8");
const OUT = path.join(ROOT, "docs", "lab", "quick-file.html");

const html = read("docs/index.html");
function cut(from, to, what) {
  const a = html.indexOf(from);
  const b = to ? html.indexOf(to, a) : -1;
  if (a < 0 || (to && b < 0)) throw new Error(`docs/index.html: couldn't find ${what} (${from} … ${to}). If it moved, update this script.`);
  return html.slice(a, to ? b : undefined);
}
const helpers = cut("const ENT = {", "/* ── Session ── */", "the helper block");
const spriteStart = html.indexOf('<svg width="0" height="0"');
const spriteEnd = html.indexOf("</defs></svg>", spriteStart);
if (spriteStart < 0 || spriteEnd < 0) throw new Error("docs/index.html: couldn't find the platform glyph sprite.");
const sprite = html.slice(spriteStart, spriteEnd + "</defs></svg>".length);
const tokens = (html.match(/:root\s*\{[^}]*\}/) || [])[0];
if (!tokens) throw new Error("docs/index.html: couldn't find the :root tokens.");
const fonts = (html.match(/<link href="https:\/\/fonts\.googleapis\.com\/css2[^"]*" rel="stylesheet">/) || [])[0] || "";

// Inlined scripts must not be able to close their own <script>.
const js = (p) => read(p).replace(/<\/(script)/gi, "<\\/$1");
const css = read("docs/quick-file.css");

const LAB_CSS = String.raw`
${tokens}
* { box-sizing: border-box; }
html { color-scheme: light; }
body { margin: 0; min-height: 100vh; background: var(--paper); color: var(--ink); font: 15px/1.5 var(--font-body);
  -webkit-tap-highlight-color: transparent; }
button { font: inherit; color: inherit; cursor: pointer; }
[hidden] { display: none !important; }
h1, h2, h3 { font-family: var(--font-head); letter-spacing: -.02em; }
:focus-visible { outline: 2px solid var(--coral); outline-offset: 2px; }
.pg { width: 12px; height: 12px; fill: currentColor; display: inline-block; vertical-align: -1px; flex: 0 0 auto; }
.pg-txt { font-size: 10px; font-weight: 800; letter-spacing: .04em; }
.badge { position: absolute; left: 10px; top: 10px; width: 26px; height: 26px; display: grid; place-items: center;
  background: rgba(25,21,16,.66); color: #fff; border-radius: 8px; }
.badge .pg { width: 13px; height: 13px; }
.btn { width: 100%; height: 48px; border: 0; border-radius: 14px; background: var(--coral); color: #fff; font-weight: 700; font-size: 15px; }
.btn.ghost { background: var(--tint); color: var(--accent-text); }
dialog { border: 0; border-radius: 20px; background: var(--surface); color: var(--ink); padding: 22px;
  box-shadow: 0 24px 70px -20px rgba(25,21,16,.35); width: min(480px, calc(100vw - 32px)); max-height: calc(100dvh - 48px); overflow-y: auto; }
dialog::backdrop { background: rgba(25,21,16,.42); backdrop-filter: blur(2px); }
@media (prefers-reduced-motion: no-preference) {
  @keyframes dlg-in { from { opacity: 0; transform: translateY(10px) scale(.97); } }
  dialog[open] { animation: dlg-in .22s var(--ease-out); }
}

/* ── The lab ── */
.lab-top { display: flex; align-items: center; gap: 18px; flex-wrap: wrap; max-width: 1180px; margin: 0 auto; padding: 18px clamp(16px, 3vw, 28px) 6px; }
.lab-brand { display: flex; align-items: center; gap: 9px; color: var(--ink); text-decoration: none; font: 800 18px var(--font-head); }
.lab-brand img { width: 28px; height: 28px; border-radius: 8px; }
.lab-title { flex: 1 1 260px; min-width: 0; }
.lab-title h1 { margin: 0; font-size: clamp(26px, 3.4vw, 38px); line-height: 1.02; letter-spacing: -.035em; }
.lab-title p { margin: 4px 0 0; color: var(--ink-2); font-size: 15px; }
.lab-title .tag { display: inline-flex; align-items: center; height: 20px; margin-left: 8px; padding: 0 8px; border-radius: 999px; vertical-align: 6px;
  background: var(--ink); color: var(--paper); font: 800 10px/1 var(--font-body); letter-spacing: .08em; text-transform: uppercase; }
.lab-modes { display: flex; gap: 3px; padding: 3px; border-radius: 999px; background: var(--control); }
.lab-modes button { height: 38px; padding: 0 16px; border: 0; border-radius: 999px; background: none; color: var(--ink-2); font-weight: 650; font-size: 14px; white-space: nowrap; }
.lab-modes button[aria-selected="true"] { background: var(--surface); color: var(--ink); box-shadow: 0 1px 2px rgba(25,21,16,.08); }
.lab-main { display: grid; grid-template-columns: minmax(0, 1fr) 360px; gap: clamp(20px, 3vw, 40px); align-items: start;
  max-width: 1180px; margin: 0 auto; padding: 14px clamp(16px, 3vw, 28px) 48px; }
.lab-stage { display: flex; justify-content: center; }
/* The share sheet, as it rises over somebody else's app. */
.lab-phone { position: relative; width: min(392px, 100%); padding: 18px 20px 20px; border-radius: 34px; background: var(--surface);
  box-shadow: 0 1px 2px rgba(25,21,16,.05), 0 40px 80px -40px rgba(25,21,16,.45), 0 0 0 1px var(--hairline); }
.lab-grab { width: 38px; height: 5px; margin: -6px auto 14px; border-radius: 999px; background: #DBD2C4; }
.lab-saved { display: flex; justify-content: center; }
.lab-saved span { display: inline-flex; align-items: center; gap: 7px; height: 34px; padding: 0 15px; border-radius: 999px;
  background: var(--ink); color: var(--paper); font-weight: 700; font-size: 13.5px; }
.lab-saved i { font-style: normal; color: #7BE3A4; font-weight: 900; }
.lab-item { display: flex; align-items: center; gap: 11px; margin: 14px 2px 0; }
.lab-item .badge { position: static; flex: 0 0 auto; width: 30px; height: 30px; border-radius: 9px; background: var(--ink); }
.lab-item b { display: -webkit-box; -webkit-line-clamp: 2; -webkit-box-orient: vertical; overflow: hidden; font-size: 14.5px; line-height: 1.3; font-weight: 700; }
.lab-item small { display: block; margin-top: 2px; color: var(--meta); font-size: 12px; font-weight: 600; }
.lab-head { margin: 16px 0 20px; text-align: center; color: var(--accent-text); font-size: 13px; font-weight: 800; }
.lab-notnow { display: block; width: 100%; height: 46px; margin-top: 14px; border: 0; border-radius: 999px; background: var(--control);
  color: var(--ink-2); font-weight: 700; font-size: 14.5px; }
.lab-done { display: flex; flex-direction: column; align-items: center; gap: 10px; padding: 34px 6px 10px; text-align: center; }
.lab-done b { font: 800 22px/1.15 var(--font-head); letter-spacing: -.02em; }
.lab-done-acts { display: flex; gap: 8px; }
.lab-done-acts button { height: 40px; padding: 0 16px; border: 0; border-radius: 999px; background: var(--control); font-weight: 700; }
.lab-done-acts .go { background: var(--coral); color: #fff; }
.lab-sort { display: flex; flex-direction: column; align-items: center; gap: 10px; width: min(460px, 100%); padding: 30px 26px 28px;
  border-radius: 34px; background: var(--surface); text-align: center; box-shadow: 0 40px 80px -40px rgba(25,21,16,.4), 0 0 0 1px var(--hairline); }
.lab-sort img { width: 200px; height: 200px; border-radius: 30px; object-fit: cover; }
.lab-sort h2 { margin: 6px 0 0; font-size: 26px; line-height: 1.1; }
.lab-sort p { margin: 0; color: var(--ink-2); }
.lab-sort .btn { max-width: 260px; margin-top: 8px; }
.lab-panel { display: flex; flex-direction: column; gap: 14px; }
.lab-card { padding: 16px 18px; border-radius: 22px; background: var(--surface); box-shadow: 0 0 0 1px var(--hairline), var(--shadow-card); }
.lab-card h2 { margin: 0 0 10px; font-size: 17px; }
.lab-row { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
.lab-next { height: 40px; padding: 0 16px; border: 0; border-radius: 999px; background: var(--coral); color: #fff; font-weight: 700; }
.lab-count { color: var(--meta); font-size: 13px; font-weight: 700; font-variant-numeric: tabular-nums; }
.lab-toggles { display: grid; gap: 2px; margin-top: 10px; }
.lab-toggles label { display: flex; align-items: center; gap: 10px; min-height: 36px; color: var(--ink-2); font-size: 14px; font-weight: 600; cursor: pointer; }
.lab-toggles input { width: 18px; height: 18px; accent-color: var(--coral); }
.lab-scores { width: 100%; border-collapse: collapse; font-size: 12.5px; }
.lab-scores td { padding: 7px 4px; border-top: 1px solid var(--hairline); vertical-align: top; }
.lab-scores tr:first-child td { border-top: 0; }
.lab-scores td:first-child { width: 18px; color: var(--meta); font-weight: 800; }
.lab-scores .t { font-weight: 700; }
.lab-scores .t small { display: block; color: var(--meta); font-weight: 600; }
.lab-scores .n { text-align: right; font-weight: 800; font-variant-numeric: tabular-nums; }
.lab-scores tr.on td { background: var(--tint); }
.lab-scores tr.on td:first-child { border-radius: 8px 0 0 8px; } .lab-scores tr.on td:last-child { border-radius: 0 8px 8px 0; }
.lab-dot { display: inline-block; width: 9px; height: 9px; margin-right: 6px; border-radius: 50%; vertical-align: 0; }
.lab-why { margin: 8px 0 0; color: var(--ink-2); font-size: 12.5px; }
.lab-note { margin: 0; color: var(--meta); font-size: 12px; line-height: 1.5; }
.lab-note code { font-size: 11.5px; }
#lab-toast { position: fixed; left: 50%; bottom: 24px; z-index: 60; transform: translate(-50%, 14px); opacity: 0; pointer-events: none;
  display: flex; gap: 14px; align-items: center; max-width: calc(100vw - 32px); padding: 10px 18px; border-radius: 999px;
  background: var(--ink); color: var(--paper); font-size: 14px; transition: opacity .2s ease, transform .24s var(--ease-out); }
#lab-toast.show { opacity: 1; transform: translate(-50%, 0); pointer-events: auto; }
#lab-toast button { border: 0; background: none; color: var(--coral); font-weight: 700; }
#lab-more h2 { margin: 0 0 10px; font-size: 20px; }
#lab-more input { width: 100%; height: 44px; padding: 0 14px; border: 1px solid var(--hairline); border-radius: 13px; font: inherit; }
.lab-topics { display: grid; gap: 2px; max-height: 52vh; overflow-y: auto; margin: 10px 0; }
.lab-topics button { display: flex; align-items: center; gap: 10px; min-height: 44px; padding: 6px 4px; border: 0; border-bottom: 1px solid var(--hairline);
  background: none; text-align: left; font-weight: 600; }
.lab-topics img { width: 30px; height: 30px; border-radius: 50%; object-fit: cover; mix-blend-mode: multiply; }
@media (max-width: 900px) {
  .lab-main { grid-template-columns: minmax(0, 1fr); }
  .lab-panel { max-width: 560px; width: 100%; margin: 0 auto; }
}
@media (max-width: 520px) {
  .lab-top { padding-top: 12px; gap: 10px 14px; }
  .lab-title { flex-basis: 100%; order: 3; }
  .lab-title h1 { font-size: 26px; }
  .lab-title p { font-size: 14px; }
  .lab-modes { margin-left: auto; }
  .lab-modes button { padding: 0 12px; font-size: 13px; }
  .lab-main { padding: 8px 12px 40px; }
  .lab-phone { padding: 16px 14px 18px; border-radius: 28px; }
}
`;

const LAB_JS = String.raw`
"use strict";
/* ── The lab: ten saves, one owner, the real dial and the real deck ── */
const DAY = 86_400_000, HOUR = 3_600_000;
const art = (dir, id) => ["../img/" + dir + "/" + id + ".jpg", "https://bookmarker.lol/img/" + dir + "/" + id + ".jpg"];
const TOPICS = Object.fromEntries(TAXONOMY.map((t) => [t.id, t]));
const topic = (id) => { const t = TOPICS[id]; return t ? { id: t.id, name: t.name, hue: t.hue, art: art("topics", t.id), subs: t.subs } : null; };
const label = (c) => QuickFileDial.label(c, topic(c.categoryID));

/* What the owner filed before: three @kaylawalks walks, two meal-prep reels,
   two New York Times pieces. That is the whole of the "memory". */
const PAST = [
  ["fitness", "Mobility", "@kaylawalks", "https://www.tiktok.com/@kaylawalks/video/1", 2],
  ["fitness", "Mobility", "@kaylawalks", "https://www.tiktok.com/@kaylawalks/video/2", 9],
  ["fitness", "Mobility", "@kaylawalks", "https://www.tiktok.com/@kaylawalks/video/3", 20],
  ["recipes", "Meal prep", "@mealprepmanny", "https://www.instagram.com/mealprepmanny/reel/A1/", 5],
  ["news", null, "nytimes.com", "https://www.nytimes.com/2026/09/01/world/a.html", 12],
  ["news", null, "nytimes.com", "https://www.nytimes.com/2026/08/11/us/b.html", 40],
];
const item = (categoryID, subcategory, author, url, at) =>
  ({ categoryID, subcategory, creator: FilingKeys.creator(author, url), domain: FilingKeys.domain(url), at });
let memory = FilingMemory.build(PAST.map(([c, s, a, u, d]) => item(c, s, a, u, new Date(Date.now() - d * DAY).toISOString())), { now: Date.now() });

/* Ten saves. Some the dial is sure about, some it can only guess, one it has
   no idea about until the model answers (turn on "Late AI answer"). */
const SAVES = [
  { url: "https://www.tiktok.com/@kaylawalks/video/7312345678901", title: "3 hip openers I do before every run", author: "@kaylawalks", platform: "tiktok", kind: "clip", dur: 42 },
  { url: "https://www.instagram.com/mealprepmanny/reel/C7xQ2LpS9aB/", title: "High-protein overnight oats, four ways", author: "@mealprepmanny", platform: "instagram", kind: "reel", image: "recipes" },
  { url: "https://www.youtube.com/watch?v=dl4St4llx", title: "Why your deadlift stalls at 100kg — a form breakdown", author: "Squat Mechanics", platform: "youtube", kind: "video", dur: 754 },
  { url: "https://x.com/growthnotes/status/1849000000000000001", title: "How I'd learn marketing from zero in 2026, step by step", author: "@growthnotes", platform: "x", kind: "thread", ai: { topic: "marketing", subtopic: "Content", confidence: "medium" } },
  { url: "https://www.tiktok.com/@wanderfrugal/video/7312345678902", title: "Osaka on $60 a day — the full itinerary", author: "@wanderfrugal", platform: "tiktok", kind: "clip", image: "travel" },
  { url: "https://www.nytimes.com/2026/10/30/style/paper-maps-comeback.html", title: "The quiet comeback of the paper map", author: "nytimes.com", platform: "web", kind: "article" },
  { url: "https://www.instagram.com/skinbydrlee/reel/C8aB3dEfGh1/", title: "The only skincare routine three dermatologists agree on", author: "@skinbydrlee", platform: "instagram", kind: "reel" },
  { url: "https://www.youtube.com/shorts/s0urd0ugh01", title: "Rescue a sluggish sourdough starter in 60 seconds", author: "@crumbcoach", platform: "shorts", kind: "short", ai: { topic: "recipes", subtopic: "Baking", confidence: "high" } },
  { url: "https://www.tiktok.com/@slowsundays/video/7312345678903", title: "This changed how I spend Sunday mornings", author: "@slowsundays", platform: "tiktok", kind: "clip", ai: { topic: "wellness", subtopic: "Morning routines", confidence: "high" } },
  { url: "https://www.pinterest.com/pin/1122334455/", title: "Small balcony, big harvest: 12 container ideas", author: "Pinterest", platform: "pinterest", kind: "pin", image: "garden", ai: { topic: "garden", subtopic: "Vegetables", confidence: "medium" } },
];
const inputOf = (s) => ({ url: s.url, title: s.title, text: null, description: null, author: s.author, ocrText: null });
const rankOf = (s, ai) => FilingSuggest.rank(inputOf(s), memory, { ai: ai || null, now: Date.now() });

const $ = (id) => document.getElementById(id);
const params = new URLSearchParams(location.search);
const state = { mode: params.get("mode") === "triage" ? "triage" : "share", at: 0, dial: null, ranking: null, timer: null };
state.at = Math.max(0, Math.min(SAVES.length - 1, (Number(params.get("save")) || 1) - 1));

/* ── Little things: the toast, the tick ── */
let toastTimer = null;
function toast(msg, act, fn) {
  const t = $("lab-toast");
  t.querySelector("span").textContent = msg;
  const b = t.querySelector("button");
  b.hidden = !act;
  if (act) { b.textContent = act; b.onclick = () => { t.classList.remove("show"); fn(); }; }
  t.classList.add("show");
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.classList.remove("show"), act ? 6000 : 2600);
}
let audio = null;
function tick() {
  if (!$("tick").checked) return;
  try {
    audio = audio || new (window.AudioContext || window.webkitAudioContext)();
    const o = audio.createOscillator(), g = audio.createGain(), t = audio.currentTime;
    o.frequency.value = 1200; o.type = "square";
    g.gain.setValueAtTime(0.05, t); g.gain.exponentialRampToValueAtTime(0.0001, t + 0.006);
    o.connect(g).connect(audio.destination); o.start(t); o.stop(t + 0.01);
  } catch { /* no audio here */ }
}

/* ── "After a share" ── */
function paintScores(ranking, highlighted) {
  const s = SAVES[state.at];
  $("scores").innerHTML = ranking.candidates.map((c, i) => {
    const t = topic(c.categoryID);
    return '<tr' + (i === highlighted ? ' class="on"' : "") + '><td>' + (i + 1) + '</td><td class="t"><span class="lab-dot" style="background:' + Palette.solid(t.hue) + '"></span>'
      + esc(label(c)) + '<small>' + esc(c.reasons.join(" · ")) + (c.altSubs.length ? " — also " + esc(c.altSubs.join(", ")) : "") + '</small></td><td class="n">' + c.score + '</td></tr>';
  }).join("");
  const h = QuickFileDial.header(ranking);
  $("why").textContent = "Evidence: " + ranking.evidence + (ranking.preselect === null ? " — nothing preselected" : "") + ". " + h.text + ".";
}
function show(i) {
  clearTimeout(state.timer);
  if (state.dial) state.dial.destroy();
  state.at = (i + SAVES.length) % SAVES.length;
  const s = SAVES[state.at];
  $("count").textContent = (state.at + 1) + " of " + SAVES.length;
  $("item-badge").innerHTML = glyph(s.platform);
  $("item-title").textContent = s.title;
  $("item-meta").textContent = (PLATFORM[s.platform] || PLATFORM.web).name + " · " + s.author;
  $("sheet").hidden = false; $("done").hidden = true;
  state.ranking = rankOf(s, null);
  const h = QuickFileDial.header(state.ranking);
  $("head").textContent = h.icon + " " + h.text;
  state.dial = QuickFileDial.mount($("dial-host"), {
    ranking: state.ranking, topic, mode: "sheet", input: inputOf(s),
    onConfirm: (c) => filed(c),
    onMore: () => more(),
    onLater: () => notNow(),
  });
  paintScores(state.ranking, state.dial.highlighted);
  if ($("late-ai").checked && s.ai) {
    state.timer = setTimeout(() => {
      if (!state.dial) return;
      const r = rankOf(s, s.ai);
      const touched = state.dial.touched;
      state.dial.offer(r);
      if (!touched) { state.ranking = r; const h2 = QuickFileDial.header(r); $("head").textContent = h2.icon + " " + h2.text; }
      paintScores(r, state.dial.highlighted);
      toast("The model answered: " + label({ categoryID: s.ai.topic, subcategory: s.ai.subtopic }) + " (" + s.ai.confidence + ")");
    }, 1500);
  }
}
function filed(c) {
  const s = SAVES[state.at];
  const before = memory;
  memory = FilingMemory.adding(memory, [item(c.categoryID, c.subcategory || null, s.author, s.url, new Date().toISOString())], { now: Date.now() });
  setTimeout(() => {
    $("sheet").hidden = true; $("done").hidden = false;
    $("done-what").textContent = "Filed to " + label(c);
  }, 360);
  toast("Filed to " + label(c), "Undo", () => { memory = before; show(state.at); });
}
function notNow() { toast("Kept our guess. It waits in Sort your borks."); show(state.at + 1); }
function more() {
  const d = $("lab-more");
  const list = $("lab-topics");
  const paint = (q) => {
    const needle = q.trim().toLowerCase();
    list.innerHTML = TAXONOMY.filter((t) => !needle || t.name.toLowerCase().includes(needle) || t.subs.some((x) => x.toLowerCase().includes(needle)))
      .sort((a, b) => a.name.localeCompare(b.name))
      .map((t) => '<button type="button" data-topic="' + t.id + '" style="color:' + Palette.deep(t.hue) + '"><img src="' + art("topics", t.id)[0] + '" alt="">' + esc(t.name) + '</button>').join("");
  };
  $("lab-q").value = ""; paint("");
  $("lab-q").oninput = (e) => paint(e.target.value);
  list.onclick = (e) => {
    const b = e.target.closest("[data-topic]");
    if (!b) return;
    d.close();
    filed({ categoryID: b.dataset.topic, subcategory: null, score: 0, reasons: ["yours"], altSubs: [], creator: null, creatorPicks: 0, matched: null });
  };
  d.onclose = () => { if (state.dial) state.dial.focus(); };
  d.showModal();
}

/* ── "Sort my borks": the same ten, unfiled, through the real deck ── */
let rows = [], run = null;
function freshRows() {
  rows = SAVES.map((s, i) => ({
    id: "lab-" + i, url: s.url, title: s.title, author: s.author, platform: s.platform, kind: s.kind,
    image_url: s.image ? art("topics", s.image)[0] : null, duration_seconds: s.dur || null,
    category_id: null, subcategory: null, filing_source: null,
    saved_at: new Date(Date.now() - i * 3 * HOUR).toISOString(), updated_at: new Date(Date.now() - i * 3 * HOUR).toISOString(), deleted_at: null,
  }));
}
const ago = (iso) => { const h = Math.round((Date.now() - Date.parse(iso)) / HOUR); return h < 1 ? "just now" : h < 24 ? h + "h ago" : Math.round(h / 24) + "d ago"; };
const swap = (next) => { const i = rows.findIndex((r) => r.id === next.id); if (i >= 0) rows[i] = next; else rows.push(next); };
Triage.use({
  rows: () => rows,
  row: (id) => rows.find((r) => r.id === id) || null,
  valid: (id) => !!TOPICS[id],
  topic, order: () => TAXONOMY.map((t) => t.id), memory: () => memory,
  display: (r) => ({ title: r.title, author: r.author }),
  picture: (r) => r.image_url,
  glyph: (p) => glyph(p), platform: (p) => (PLATFORM[p] || PLATFORM.web).name, date: ago,
  file(r, c) {
    const prev = { ...r };
    swap({ ...r, category_id: c.categoryID, subcategory: c.subcategory || null, filing_source: "user", updated_at: new Date().toISOString() });
    return prev;
  },
  remove(r) { const prev = { ...r }; swap({ ...r, deleted_at: new Date().toISOString() }); return prev; },
  restore(prev) { swap({ ...prev, deleted_at: null, updated_at: new Date().toISOString() }); },
  more(r, c, done) {
    const d = $("lab-more");
    const list = $("lab-topics");
    $("lab-q").value = "";
    const paint = (q) => {
      const needle = q.trim().toLowerCase();
      list.innerHTML = TAXONOMY.filter((t) => !needle || t.name.toLowerCase().includes(needle))
        .sort((a, b) => a.name.localeCompare(b.name))
        .map((t) => '<button type="button" data-topic="' + t.id + '" style="color:' + Palette.deep(t.hue) + '"><img src="' + art("topics", t.id)[0] + '" alt="">' + esc(t.name) + '</button>').join("");
    };
    paint("");
    $("lab-q").oninput = (e) => paint(e.target.value);
    let picked = null;
    list.onclick = (e) => { const b = e.target.closest("[data-topic]"); if (b) { picked = { categoryID: b.dataset.topic, subcategory: null }; d.close(); } };
    d.onclose = () => done(picked);
    d.showModal();
  },
  signedIn: () => false, demo: () => true,
  toast, compass: art("quests", "compass"),
  changed() {
    if (!run || Triage.isOpen) return;
    const secs = (Date.now() - run.started) / 1000;
    const n = rows.filter((r) => r.filing_source === "user" && !r.deleted_at).length;
    $("sort-last").textContent = n ? n + " sorted in " + Math.round(secs) + " s — " + (secs / n).toFixed(1) + " s a save" : "Nothing sorted that time.";
    run = null;
  },
});
function sortTen() {
  freshRows();
  run = { started: Date.now() };
  Triage.open({ deck: "unfiled" });
}

/* ── Modes and switches ── */
function setMode(mode) {
  state.mode = mode;
  for (const b of document.querySelectorAll("[data-mode]")) b.setAttribute("aria-selected", String(b.dataset.mode === mode));
  $("phone").hidden = mode !== "share";
  $("sort").hidden = mode !== "triage";
  $("share-panel").hidden = mode !== "share";
  if (mode === "share") show(state.at);
  else if (state.dial) { state.dial.destroy(); state.dial = null; }
}
document.querySelector(".lab-modes").addEventListener("click", (e) => { const b = e.target.closest("[data-mode]"); if (b) setMode(b.dataset.mode); });
$("next").addEventListener("click", () => show(state.at + 1));
$("again").addEventListener("click", () => show(state.at));
$("go-next").addEventListener("click", () => show(state.at + 1));
$("not-now").addEventListener("click", notNow);
$("sort-go").addEventListener("click", sortTen);
$("lab-more-cancel").addEventListener("click", () => $("lab-more").close());
$("late-ai").addEventListener("change", () => { if (state.mode === "share") show(state.at); });
$("reduced").addEventListener("change", (e) => document.documentElement.classList.toggle("qf-reduced", e.target.checked));
$("list").addEventListener("change", (e) => $("phone").classList.toggle("qf-list-mode", e.target.checked));
$("dial-host").addEventListener("quickfile:turn", (e) => { tick(); if (state.ranking) paintScores(state.ranking, e.detail.highlighted); });
$("dial-host").addEventListener("quickfile:confirm", () => tick());
document.addEventListener("keydown", (e) => {
  if (e.target.closest && e.target.closest("input, dialog")) return;
  if (state.mode === "share" && !$("done").hidden && (e.key === "n" || e.key === "ArrowRight")) show(state.at + 1);
});
if (params.get("ai") === "1") $("late-ai").checked = true;
if (params.get("reduced") === "1") { $("reduced").checked = true; document.documentElement.classList.add("qf-reduced"); }
if (params.get("list") === "1") { $("list").checked = true; $("phone").classList.add("qf-list-mode"); }
freshRows();
setMode(state.mode);
if (state.mode === "triage") sortTen();
`;

const page = `<!DOCTYPE html>
<!-- GENERATED by Scripts/build_quick_file_demo.mjs from docs/taxonomy.js, docs/import.js,
     docs/filing-suggest.js, docs/palette.js, docs/quick-file.js, docs/triage.js,
     docs/quick-file.css and docs/index.html. Do not edit by hand: change a source and run
     node Scripts/build_quick_file_demo.mjs -->
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex, nofollow">
<title>Quick File lab · bookmarker</title>
<meta name="description" content="The Quick File dial and the Sort your borks deck, running the real code on ten made-up saves. A lab page, not part of the site.">
<meta name="theme-color" content="#F6F3EE">
<link rel="icon" href="../favicon.png">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
${fonts}
<style>${LAB_CSS}</style>
<style>${css}</style>
</head>
<body>
${sprite}
<header class="lab-top">
  <a class="lab-brand" href="/"><img src="../img/mark-192.png" alt="">bookmarker</a>
  <div class="lab-title"><h1>Quick File<span class="tag">Lab</span></h1><p>Saved in one tap. Filed in one more.</p></div>
  <nav class="lab-modes" role="tablist" aria-label="Mode">
    <button type="button" role="tab" data-mode="share" aria-selected="true">After a share</button>
    <button type="button" role="tab" data-mode="triage" aria-selected="false">Sort my borks</button>
  </nav>
</header>
<main class="lab-main">
  <section class="lab-stage">
    <div class="lab-phone" id="phone">
      <div class="lab-grab" aria-hidden="true"></div>
      <div id="sheet">
        <div class="lab-saved"><span><i aria-hidden="true">✓</i> Saved to bookmarker</span></div>
        <div class="lab-item"><span class="badge" id="item-badge" role="img" aria-hidden="true"></span><div><b id="item-title"></b><small id="item-meta"></small></div></div>
        <p class="lab-head" id="head"></p>
        <div id="dial-host"></div>
        <button type="button" class="lab-notnow" id="not-now">Not now</button>
      </div>
      <div class="lab-done" id="done" hidden>
        <b id="done-what"></b>
        <div class="lab-done-acts"><button type="button" id="again">Again</button><button type="button" class="go" id="go-next">Next save →</button></div>
      </div>
    </div>
    <div class="lab-sort" id="sort" hidden>
      <img src="../img/quests/compass.jpg" alt="" width="200" height="200">
      <h2>Sort your borks</h2>
      <p>The same ten saves, unfiled, through the real deck. Your filings teach it as you go.</p>
      <button type="button" class="btn" id="sort-go">Sort 10</button>
      <p class="lab-why" id="sort-last"></p>
    </div>
  </section>
  <aside class="lab-panel">
    <div class="lab-card" id="share-panel">
      <div class="lab-row"><button type="button" class="lab-next" id="next">Next save →</button><span class="lab-count" id="count"></span></div>
      <div class="lab-toggles">
        <label><input type="checkbox" id="late-ai"> Late AI answer in 1.5 s</label>
        <label><input type="checkbox" id="reduced"> Reduced motion</label>
        <label><input type="checkbox" id="list"> List mode</label>
        <label><input type="checkbox" id="tick"> Tick sound</label>
      </div>
    </div>
    <div class="lab-card">
      <h2>Why these seven</h2>
      <table class="lab-scores"><tbody id="scores"></tbody></table>
      <p class="lab-why" id="why"></p>
    </div>
    <p class="lab-note">Scroll, ←/→ or J/K turn the dial; 1–7 file; Enter files the middle; / opens every topic. In the deck: S skips, Z undoes, Backspace removes. Built from the real files by <code>Scripts/build_quick_file_demo.mjs</code>.</p>
  </aside>
</main>
<div id="lab-toast" role="status" aria-live="polite"><span></span><button type="button" hidden></button></div>
<dialog id="lab-more" aria-labelledby="lab-more-h">
  <h2 id="lab-more-h">Pick a topic</h2>
  <input type="search" id="lab-q" placeholder="Find a topic" aria-label="Find a topic" autocomplete="off">
  <div class="lab-topics" id="lab-topics"></div>
  <button type="button" class="btn ghost" id="lab-more-cancel">Cancel</button>
</dialog>
<script>
"use strict";
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
${helpers.replace(/<\/(script)/gi, "<\\/$1")}
</script>
<script>${js("docs/taxonomy.js")}</script>
<script>${js("docs/import.js")}</script>
<script>${js("docs/palette.js")}</script>
<script>${js("docs/filing-suggest.js")}</script>
<script>${js("docs/quick-file.js")}</script>
<script>${js("docs/triage.js")}</script>
<script>${LAB_JS}</script>
</body>
</html>
`;

fs.mkdirSync(path.dirname(OUT), { recursive: true });
fs.writeFileSync(OUT, page);
console.log(`wrote ${path.relative(ROOT, OUT)} (${Math.round(page.length / 1024)} KB)`);
