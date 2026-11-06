/* bookmarker — Quick File's ranking, on the web.
 *
 * A port of Core/FilingMemory.swift and Core/FilingSuggest.swift: which seven
 * topics go on the dial, in what order, and the one line that says why. The
 * iPhone and the web have to agree, so every number is an integer, every sort
 * is a total order, creator keys are plain ASCII and "now" is passed in.
 * Scripts/fixtures/filing_suggest_cases.json is what the Swift answers, and
 * Scripts/check_filing_parity.mjs holds this file to it.
 *
 *   FilingKeys     who made a post, and which website it came from
 *   FilingMemory   your own filings, folded into creators, domains and habits
 *   FilingSuggest  rank(), reasonLine(), cleanOCR(), historyFromRows()
 *
 * Looked up at call time only, so load order doesn't matter: TAXONOMY
 * (taxonomy.js), Filer (import.js), and detectPlatform and PLATFORM (the
 * page's helper block). No DOM, no storage and no network, so it loads in node
 * exactly as it is.
 */
"use strict";

const { FilingKeys, FilingMemory, FilingSuggest } = (() => {

  /* ══ Parity helpers ═════════════════════════════════════════════════════
   * FilingParity in Swift. Each is defined on code points (Swift's Unicode
   * scalars), so neither language's own idea of a character, a space or an
   * ordering can creep in. */

  const DAY = 86400;

  /* The union of what Swift's .whitespacesAndNewlines and JS's trim() call
     space, so both trim the same. */
  const SPACES = new Set([
    0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x85, 0xA0, 0x1680,
    0x2000, 0x2001, 0x2002, 0x2003, 0x2004, 0x2005, 0x2006, 0x2007, 0x2008, 0x2009, 0x200A,
    0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF,
  ]);

  /** Whole seconds since 1970, rounded down. Takes a Date, an ISO string or
      milliseconds; null when it can't be read. */
  function seconds(value) {
    if (value === null || value === undefined || value === "") return null;
    const ms = typeof value?.getTime === "function" ? value.getTime()
      : typeof value === "number" ? value
      : Date.parse(String(value));
    return Number.isFinite(ms) ? Math.floor(ms / 1000) : null;
  }

  /** Code-point order. */
  function compare(a, b) {
    if (a === b) return 0;
    const x = [...a], y = [...b];
    const n = Math.min(x.length, y.length);
    for (let i = 0; i < n; i++) {
      const p = x[i].codePointAt(0), q = y[i].codePointAt(0);
      if (p !== q) return p < q ? -1 : 1;
    }
    return x.length < y.length ? -1 : x.length > y.length ? 1 : 0;
  }

  /** Code-point order, null first. */
  function compareOptional(a, b) {
    if (a == null) return b == null ? 0 : -1;
    if (b == null) return 1;
    return compare(a, b);
  }

  /** Most recent first, null last. */
  function newerFirst(a, b) {
    if (a === b) return 0;
    if (a === null) return 1;
    if (b === null) return -1;
    return b - a;
  }

  function trim(raw) {
    const cps = [...String(raw ?? "")];
    let start = 0, end = cps.length;
    while (start < end && SPACES.has(cps[start].codePointAt(0))) start++;
    while (end > start && SPACES.has(cps[end - 1].codePointAt(0))) end--;
    return cps.slice(start, end).join("");
  }

  const length = (s) => [...s].length;
  const own = (table, key) =>
    (table && Object.prototype.hasOwnProperty.call(table, key) ? table[key] : null);

  /* ══ FilingKeys ═════════════════════════════════════════════════════════
   * Creator: the handle in the URL when the URL names one, otherwise the
   * stored author unless it is a placeholder; then decomposed, lowercased and
   * cut down to a–z 0–9. Web links have no creator (their author is usually
   * the site, which the domain already counts). Domain: the host without
   * "www.", web links only. */

  const RESERVED_X = new Set(["i", "home", "search", "hashtag", "intent", "share", "explore", "messages", "notifications", "settings"]);
  const POST_PATHS = new Set(["reel", "reels", "p", "tv"]);

  /** Non-empty and nothing but A–Z a–z 0–9 . _ - */
  const isHandle = (name) => name.length > 0 && /^[A-Za-z0-9._-]+$/.test(name);

  /** Platform.handle without the "@", restricted to ASCII. */
  function handleIn(rawURL, platform) {
    let u;
    try { u = new URL(rawURL); } catch { return null; }
    const segments = u.pathname.split("/").filter(Boolean).map((s) => {
      try { return decodeURIComponent(s); } catch { return s; }
    });
    const first = segments[0];
    if (!first) return null;
    const clean = (raw) => {
      const name = raw.startsWith("@") ? raw.slice(1) : raw;
      return length(name) <= 40 && isHandle(name) ? name : null;
    };
    switch (platform) {
      case "tiktok": case "threads": case "youtube": case "shorts":
        return first.startsWith("@") ? clean(first) : null;
      case "x":
        if (segments.length < 3 || segments[1] !== "status" || RESERVED_X.has(first.toLowerCase())) return null;
        return clean(first);
      case "instagram":
        if (first === "stories" && segments.length >= 2) return clean(segments[1]);
        if (segments.length < 3 || !POST_PATHS.has(segments[1]) || POST_PATHS.has(first)) return null;
        return clean(first);
      default:
        return null;
    }
  }

  function keyOf(raw) {
    let out = "";
    for (const c of String(raw).normalize("NFD").toLowerCase()) {
      if ((c >= "a" && c <= "z") || (c >= "0" && c <= "9")) out += c;
    }
    return out.length >= 2 ? out : null;
  }

  /* Mirrors Bookmark.isPlaceholderAuthor for social links: empty, a platform
     name, the link's own host, or any social platform's host. */
  function isPlaceholder(author, rawURL) {
    const raw = trim(author);
    if (!raw) return true;
    if (Filer.isSiteName(raw)) return true;
    const bare = (host) => {
      const lower = host.toLowerCase();
      return lower.startsWith("www.") ? lower.slice(4) : lower;
    };
    let host = "";
    try { host = new URL(rawURL).hostname; } catch { host = ""; }
    if (host && bare(raw) === bare(host)) return true;
    if (!raw.includes(".") || raw.includes(" ") || raw.startsWith("@")) return false;
    return detectPlatform(`https://${bare(raw)}/`) !== "web";
  }

  function resolve(author, rawURL) {
    const url = String(rawURL ?? "");
    const platform = detectPlatform(url);
    const handle = handleIn(url, platform);
    if (handle) {
      const key = keyOf(handle);
      if (key) return { key, label: "@" + handle };
    }
    if (platform === "web" || author === null || author === undefined || isPlaceholder(author, url)) return null;
    // The label is the author as stored: TikTok and X store "@handle",
    // YouTube a channel name. Adding an "@" here would invent a handle.
    const name = trim(author);
    const key = keyOf(name);
    if (!key) return null;
    return { key, label: name };
  }

  function domainOf(rawURL) {
    const url = String(rawURL ?? "");
    if (detectPlatform(url) !== "web") return null;
    let host;
    try { host = new URL(url).hostname.toLowerCase(); } catch { return null; }
    if (host.startsWith("www.")) host = host.slice(4);
    return host || null;
  }

  const FilingKeys = Object.freeze({
    /** The creator key for a post: ASCII a–z 0–9, or null. */
    creator: (author, url) => resolve(author, url)?.key ?? null,
    /** How the creator reads in a reason line: "@kayla.walks" for a handle in
        the URL, otherwise the author exactly as stored ("@kaylawalks" from
        TikTok, "Squat Mechanics" from YouTube). Null whenever creator() is. */
    creatorLabel: (author, url) => resolve(author, url)?.label ?? null,
    /** The host without "www.", for web links only. */
    domain: (url) => domainOf(url),
  });

  /* ══ FilingMemory ═══════════════════════════════════════════════════════
   * Your own ("user") filings from the last 365 days, as three tables:
   * creators and domains map a key to its 3 strongest picks
   * {categoryID, subcategory, count, last}, and habits lists the 24 strongest
   * topic › subtopic pairs {categoryID, subcategory, recent} with their 6 most
   * recent filing times. Times are seconds since 1970. Immutable: adding()
   * returns a new memory. */

  const LIMITS = Object.freeze({ creators: 400, domains: 200, picksPerKey: 3, habits: 24, recentPerHabit: 6, horizonDays: 365 });
  const RECENCY = Object.freeze({ week: 3, month: 2, year: 1 });

  /** 3 a filing in its first week, 2 in its first month, 1 in its first year. */
  function recency(times, now) {
    let total = 0;
    for (const at of times) {
      const age = now - at;
      if (age <= 7 * DAY) total += RECENCY.week;
      else if (age <= 30 * DAY) total += RECENCY.month;
      else if (age <= LIMITS.horizonDays * DAY) total += RECENCY.year;
    }
    return total;
  }

  const pairKey = (categoryID, subcategory) => `${categoryID}\u001f${subcategory ?? ""}`;

  function emptyMemory() {
    return { creators: Object.create(null), domains: Object.create(null), habits: [] };
  }

  function cloneTable(table) {
    const out = Object.create(null);
    if (!table) return out;
    for (const key of Object.keys(table)) {
      out[key] = (table[key] || []).map((p) => ({
        categoryID: p.categoryID, subcategory: p.subcategory ?? null, count: p.count, last: p.last,
      }));
    }
    return out;
  }

  function counted(picks, categoryID, subcategory, at) {
    const hit = picks.find((p) => p.categoryID === categoryID && p.subcategory === subcategory);
    if (hit) { hit.count += 1; hit.last = Math.max(hit.last, at); }
    else picks.push({ categoryID, subcategory, count: 1, last: at });
    return picks;
  }

  /* Most picks first, then the most recent, then A–Z: a total order. */
  const pickOrder = (a, b) =>
    (b.count - a.count) || (b.last - a.last)
    || compare(a.categoryID, b.categoryID) || compareOptional(a.subcategory, b.subcategory);

  function prunedTable(table, keep, horizon) {
    let kept = [];
    for (const key of Object.keys(table)) {
      const fresh = table[key].filter((p) => p.last >= horizon).sort(pickOrder).slice(0, LIMITS.picksPerKey);
      if (!fresh.length) continue;
      kept.push({
        key, picks: fresh,
        total: fresh.reduce((n, p) => n + p.count, 0),
        last: Math.max(...fresh.map((p) => p.last)),
      });
    }
    if (kept.length > keep) {
      kept.sort((a, b) => (b.total - a.total) || (b.last - a.last) || compare(a.key, b.key));
      kept = kept.slice(0, keep);
    }
    const out = Object.create(null);
    for (const entry of kept) out[entry.key] = entry.picks;
    return out;
  }

  function prunedHabits(habits, now, horizon) {
    const fresh = [];
    for (const h of habits) {
      const recent = h.recent.filter((t) => t >= horizon);
      if (!recent.length) continue;
      fresh.push({ categoryID: h.categoryID, subcategory: h.subcategory, recent: recent.slice(0, LIMITS.recentPerHabit) });
    }
    fresh.sort((a, b) =>
      (recency(b.recent, now) - recency(a.recent, now)) || (b.recent[0] - a.recent[0])
      || compare(a.categoryID, b.categoryID) || compareOptional(a.subcategory, b.subcategory));
    return fresh.slice(0, LIMITS.habits);
  }

  /** Folds history items {categoryID, subcategory, creator, domain, at} into
      `memory` and returns a new memory, pruned to the caps as of `now`. */
  function adding(memory, items, { now } = {}) {
    const nowSeconds = seconds(now ?? Date.now()) ?? seconds(Date.now());
    const horizon = nowSeconds - LIMITS.horizonDays * DAY;
    const creators = cloneTable(memory && memory.creators);
    const domains = cloneTable(memory && memory.domains);
    const habits = new Map();
    for (const h of (memory && memory.habits) || []) {
      const subcategory = h.subcategory ?? null;
      habits.set(pairKey(h.categoryID, subcategory), { categoryID: h.categoryID, subcategory, recent: [...h.recent] });
    }

    for (const item of items || []) {
      const categoryID = item && typeof item.categoryID === "string" ? item.categoryID : "";
      if (!categoryID) continue;
      const subcategory = typeof item.subcategory === "string" && item.subcategory ? item.subcategory : null;
      const at = seconds(item.at);
      if (at === null || at < horizon) continue;
      if (typeof item.creator === "string" && item.creator) {
        creators[item.creator] = counted(own(creators, item.creator) || [], categoryID, subcategory, at);
      }
      if (typeof item.domain === "string" && item.domain) {
        domains[item.domain] = counted(own(domains, item.domain) || [], categoryID, subcategory, at);
      }
      const pair = pairKey(categoryID, subcategory);
      const habit = habits.get(pair) || { categoryID, subcategory, recent: [] };
      habit.recent = [...habit.recent, at].sort((a, b) => b - a).slice(0, LIMITS.recentPerHabit);
      habits.set(pair, habit);
    }

    return {
      creators: prunedTable(creators, LIMITS.creators, horizon),
      domains: prunedTable(domains, LIMITS.domains, horizon),
      habits: prunedHabits([...habits.values()], nowSeconds, horizon),
    };
  }

  const FilingMemory = Object.freeze({
    LIMITS, RECENCY, recency,
    empty: emptyMemory,
    /** Memory from scratch: exactly adding(empty(), items, {now}). */
    build: (items, options = {}) => adding(emptyMemory(), items, options),
    adding,
  });

  /* ══ FilingSuggest ══════════════════════════════════════════════════════
   * Score per topic, whole numbers only:
   *     keywords (Filer.scores)
   *   + on-screen text ÷ 2, capped at 13
   *   + AI: high 28, medium 13
   *   + 12 per pick of this creator, capped at 36
   *   + 6 per pick of this website, capped at 18 (web links only)
   *   + recency of your filings in the topic, capped at 6
   * Order: score, your most recent filing there, taxonomy order. A pin leads;
   * the onboarding interests fill the seats left. */

  const RING_SIZE = 7;
  const WEIGHTS = Object.freeze({
    creatorPerPick: 12, creatorCap: 36, domainPerPick: 6, domainCap: 18,
    aiHigh: 28, aiMedium: 13, ocrCap: 13, habitCap: 6, preselectFloor: 6, strong: 14,
  });
  /* Taxonomy.onboardingInterests, which taxonomy.js doesn't carry. The fixture
     records the Swift list and the parity check compares the two. */
  const STARTERS = Object.freeze([
    "fitness", "health", "recipes", "money", "tech", "ai", "travel",
    "comedy", "sports", "parenting", "home", "beauty", "gaming", "music",
    "learning", "wellness", "cars", "books",
  ]);
  const EVIDENTIAL = new Set(["keyword", "hashtag", "ocr", "creator", "domain", "ai"]);
  const ABOUT_THE_LINK = new Set(["keyword", "hashtag", "creator", "domain", "ai"]);

  function newTally() {
    return {
      keyword: 0, keywordLabel: null, fromHashtag: false, ocr: 0, ocrLabel: null, ai: 0,
      creatorPicks: 0, domainPicks: 0, habit: 0, last: null, subs: new Map(),
    };
  }
  const creatorPoints = (t) => Math.min(WEIGHTS.creatorCap, WEIGHTS.creatorPerPick * t.creatorPicks);
  const domainPoints = (t) => Math.min(WEIGHTS.domainCap, WEIGHTS.domainPerPick * t.domainPicks);
  const ocrPoints = (t) => Math.min(WEIGHTS.ocrCap, Math.floor(t.ocr / 2));
  const habitPoints = (t) => Math.min(WEIGHTS.habitCap, t.habit);
  const total = (t) => t.keyword + ocrPoints(t) + t.ai + creatorPoints(t) + domainPoints(t) + habitPoints(t);

  function saw(t, at) {
    if (at !== null && at !== undefined && (t.last === null || at > t.last)) t.last = at;
  }

  function credit(t, sub, points, at) {
    if (points <= 0) return;
    const entry = t.subs.get(sub) || { score: 0, last: null };
    entry.score += points;
    if (at !== null && at !== undefined && (entry.last === null || at > entry.last)) entry.last = at;
    t.subs.set(sub, entry);
  }

  /* Each reason with points, biggest first, ties in declaration order. */
  function reasonsOf(t) {
    const parts = [
      ["creator", creatorPoints(t)], ["domain", domainPoints(t)], ["ai", t.ai],
      [t.fromHashtag ? "hashtag" : "keyword", t.keyword], ["ocr", ocrPoints(t)], ["habit", habitPoints(t)],
    ];
    return parts.map(([reason, points], i) => ({ reason, points, i }))
      .filter((p) => p.points > 0)
      .sort((a, b) => (b.points - a.points) || (a.i - b.i))
      .map((p) => p.reason);
  }

  /* Subtopics with evidence: most points, your most recent filing there, A–Z. */
  function rankedSubs(t) {
    return [...t.subs.entries()]
      .sort((a, b) => (b[1].score - a[1].score) || newerFirst(a[1].last, b[1].last) || compare(a[0], b[0]))
      .map((e) => e[0]);
  }

  function matchedOf(t, reasons) {
    for (const reason of reasons) {
      if (reason === "hashtag" || reason === "keyword") return t.keywordLabel;
      if (reason === "ocr") return t.ocrLabel;
    }
    return null;
  }

  /* The categorize function's answer, {topic, subtopic, confidence} (or
     {categoryID, subcategory, score}), as points: high 28, medium 13. */
  function aiPick(ai) {
    if (!ai) return null;
    const id = ai.categoryID ?? ai.topic;
    if (!id) return null;
    const rawSub = ai.subcategory ?? ai.subtopic ?? null;
    const sub = typeof rawSub === "string" && rawSub ? rawSub : null;
    const confidence = String(ai.confidence ?? "").toLowerCase();
    let points = confidence === "high" ? WEIGHTS.aiHigh : confidence === "medium" ? WEIGHTS.aiMedium : 0;
    if (!points && typeof ai.score === "number" && ai.score > 0) {
      points = ai.score >= WEIGHTS.strong ? WEIGHTS.aiHigh : WEIGHTS.aiMedium;
    }
    return points ? { id, sub, points } : null;
  }

  /**
   * Ranks the topics for `input` ({url, title, text, description, author,
   * ocrText}) → {candidates: [{categoryID, subcategory, score, reasons,
   * altSubs, creator, creatorPicks, matched}], preselect: 0|null, evidence}.
   * `pinned` is {categoryID, subcategory, reason: "yours"|"guess"};
   * `taxonomyOrder` is built-in ids then custom ids A–Z (a topic missing from
   * it never appears); `now` is a Date, an ISO string or milliseconds.
   */
  function rank(input, memory, { ai = null, pinned = null, taxonomyOrder = null, now = Date.now(), limit = RING_SIZE } = {}) {
    const nowSeconds = seconds(now) ?? seconds(Date.now());
    const order = taxonomyOrder || TAXONOMY.map((t) => t.id);
    const position = new Map();
    order.forEach((id, i) => { if (!position.has(id)) position.set(id, i); });
    const url = String(input?.url ?? "");
    const mem = memory || emptyMemory();

    const tallies = new Map();
    const tally = (id) => {
      if (!tallies.has(id)) tallies.set(id, newTally());
      return tallies.get(id);
    };

    for (const s of Filer.scores(url, input?.title ?? "", input?.text ?? null,
      { description: input?.description ?? null, author: input?.author ?? null })) {
      const t = tally(s.topic);
      t.keyword = s.score; t.keywordLabel = s.label; t.fromHashtag = s.hashtag;
      if (s.subtopic) credit(t, s.subtopic, s.subWeight, null);
    }
    const ocrText = input?.ocrText;
    if (typeof ocrText === "string" && ocrText) {
      for (const s of Filer.scores(null, "", ocrText, {})) {
        const t = tally(s.topic);
        t.ocr = s.score; t.ocrLabel = s.label;
        if (s.subtopic) credit(t, s.subtopic, Math.floor(s.subWeight / 2), null);
      }
    }
    const answer = aiPick(ai);
    if (answer) {
      const t = tally(answer.id);
      t.ai = answer.points;
      if (answer.sub) credit(t, answer.sub, answer.points, null);
    }
    const creator = resolve(input?.author ?? null, url);
    if (creator) {
      for (const p of own(mem.creators, creator.key) || []) {
        const t = tally(p.categoryID);
        t.creatorPicks += p.count;
        saw(t, p.last);
        if (p.subcategory) credit(t, p.subcategory, WEIGHTS.creatorPerPick * p.count, p.last);
      }
    }
    const domain = domainOf(url);
    if (domain) {
      for (const p of own(mem.domains, domain) || []) {
        const t = tally(p.categoryID);
        t.domainPicks += p.count;
        saw(t, p.last);
        if (p.subcategory) credit(t, p.subcategory, WEIGHTS.domainPerPick * p.count, p.last);
      }
    }
    for (const h of mem.habits || []) {
      const weight = recency(h.recent, nowSeconds);
      if (weight <= 0) continue;
      const t = tally(h.categoryID);
      t.habit += weight;
      saw(t, h.recent[0]);
      if (h.subcategory) credit(t, h.subcategory, Math.min(WEIGHTS.habitCap, weight), h.recent[0]);
    }

    function candidate(id, t, pin) {
      const subs = rankedSubs(t);
      let reasons = reasonsOf(t);
      let sub = subs.length ? subs[0] : null;
      if (pin) {
        reasons = [pin.reason, ...reasons.filter((r) => r !== pin.reason)];
        sub = pin.subcategory;
      }
      return {
        categoryID: id,
        subcategory: sub,
        score: total(t),
        reasons,
        altSubs: subs.filter((s) => s !== sub).slice(0, 3),
        creator: t.creatorPicks > 0 && creator ? creator.label : null,
        creatorPicks: t.creatorPicks,
        matched: matchedOf(t, reasons),
      };
    }

    const ranked = [];
    for (const [id, t] of tallies) {
      if (!position.has(id) || total(t) <= 0) continue;
      ranked.push({ id, t, position: position.get(id) });
    }
    ranked.sort((a, b) => (total(b.t) - total(a.t)) || newerFirst(a.t.last, b.t.last) || (a.position - b.position));

    let candidates = [];
    let pinnedID = null;
    if (pinned && position.has(pinned.categoryID)) {
      const pin = {
        categoryID: pinned.categoryID,
        subcategory: typeof pinned.subcategory === "string" && pinned.subcategory ? pinned.subcategory : null,
        reason: pinned.reason,
      };
      candidates.push(candidate(pin.categoryID, tallies.get(pin.categoryID) || newTally(), pin));
      pinnedID = pin.categoryID;
    }
    for (const entry of ranked) {
      if (entry.id !== pinnedID) candidates.push(candidate(entry.id, entry.t, null));
    }
    for (const id of STARTERS) {
      if (!position.has(id) || candidates.some((c) => c.categoryID === id)) continue;
      candidates.push({ categoryID: id, subcategory: null, score: 0, reasons: ["starter"], altSubs: [], creator: null, creatorPicks: 0, matched: null });
    }
    candidates = candidates.slice(0, Math.max(0, limit));

    const first = candidates[0];
    if (!first) return { candidates: [], preselect: null, evidence: "none" };
    const pinnedLead = first.reasons.includes("yours") || first.reasons.includes("guess");
    const hasEvidence = first.reasons.some((r) => EVIDENTIAL.has(r));
    const preselect = pinnedLead || (hasEvidence && first.score >= WEIGHTS.preselectFloor) ? 0 : null;
    const evidence = preselect === null ? "none"
      : first.score >= WEIGHTS.strong && first.reasons.some((r) => ABOUT_THE_LINK.has(r)) ? "strong"
      : "thin";
    return { candidates, preselect, evidence };
  }

  /** The one line under the dial for candidate `c`, from its first reason that
      has something to say; null for a starter. */
  function reasonLine(c, input) {
    for (const reason of (c && c.reasons) || []) {
      switch (reason) {
        case "creator":
          if (c.creator === null || c.creator === undefined || !(c.creatorPicks > 0)) continue;
          return c.creatorPicks >= 2
            ? `You filed ${c.creator} here ${c.creatorPicks} times`
            : `You filed ${c.creator} here last time`;
        case "hashtag":
          if (c.matched === null || c.matched === undefined) continue;
          return `#${c.matched} in the caption`;
        case "keyword":
          if (c.matched === null || c.matched === undefined) continue;
          return `“${c.matched}” in the title`;
        case "ocr":
          if (c.matched === null || c.matched === undefined) continue;
          return `On-screen text says “${c.matched}”`;
        case "ai":
          return "AI read the caption";
        case "domain": {
          const domain = domainOf(input?.url);
          if (!domain) continue;
          return `You file ${domain} here`;
        }
        case "habit":
          return "One of your usual spots";
        case "starter":
          return null;
        default:
          continue;   // yours, guess: the header already says it
      }
    }
    return null;
  }

  /* Interface text on social apps and login walls, matched as whole words. */
  const FURNITURE = Object.freeze([
    "log in", "login", "sign in", "signin", "sign up", "signup", "verify", "captcha",
    "cookie", "cookies", "open app", "open the app", "follow", "following", "followers",
    "subscribe", "subscribed", "original audio", "original sound", "liked by",
    "comment", "comments", "share", "shares",
  ]);

  /* "@name" and nothing else. */
  function isLoneHandle(line) {
    const cps = [...line];
    return cps.length >= 2 && cps[0] === "@" && cps.slice(1).every((c) => /^[A-Za-z0-9._]$/.test(c));
  }

  /* Counts, times and dates: "1.2M", "12:34", "0:15 / 1:02", "2024-05-01",
     "3h", "2d ago", "45%". */
  function isNumberish(line) {
    let digits = 0, rest = "";
    for (const c of line) {
      if (c >= "0" && c <= "9") digits++;
      else if (c.length === 1 && " .,:/%+-".includes(c)) continue;
      else if (c >= "A" && c <= "Z") rest += String.fromCharCode(c.charCodeAt(0) + 32);
      else rest += c;
    }
    if (!digits) return false;
    if (rest.endsWith("ago")) rest = rest.slice(0, -3);
    return ["", "k", "m", "b", "h", "d", "w", "y", "s", "x"].includes(rest);
  }

  function isFurniture(line) {
    let words = " ", word = "";
    for (const c of line) {
      if ((c >= "a" && c <= "z") || (c >= "0" && c <= "9")) word += c;
      else if (c >= "A" && c <= "Z") word += String.fromCharCode(c.charCodeAt(0) + 32);
      else if (word) { words += word + " "; word = ""; }
    }
    if (word) words += word + " ";
    return FURNITURE.some((p) => words.includes(` ${p} `));
  }

  /** Text recognised on a thumbnail, reduced to what might say what the post
      is about; null when under 8 characters survive. */
  function cleanOCR(lines) {
    const kept = [], seen = new Set();
    for (const raw of lines || []) {
      const line = trim(raw);
      if (length(line) < 3 || isLoneHandle(line) || isNumberish(line) || isFurniture(line) || seen.has(line)) continue;
      seen.add(line);
      kept.push(line);
    }
    let cps = [...kept.join("\n")];
    if (cps.length > 400) cps = cps.slice(0, 400);
    const text = trim(cps.join(""));
    return length(text) >= 8 ? text : null;
  }

  /** History items from the page's rows: your own filings only
      (filing_source "user", not deleted, with a topic), keyed the same way the
      app keys its Bookmarks. */
  function historyFromRows(rows) {
    const out = [];
    for (const row of rows || []) {
      if (!row || row.deleted_at || row.filing_source !== "user") continue;
      const categoryID = typeof row.category_id === "string" ? row.category_id : "";
      if (!categoryID) continue;
      const at = row.updated_at ?? row.saved_at ?? null;
      if (seconds(at) === null) continue;
      const url = typeof row.url === "string" ? row.url : "";
      out.push({
        categoryID,
        subcategory: typeof row.subcategory === "string" && row.subcategory ? row.subcategory : null,
        creator: url ? FilingKeys.creator(row.author ?? null, url) : null,
        domain: url ? FilingKeys.domain(url) : null,
        at,
      });
    }
    return out;
  }

  const FilingSuggest = Object.freeze({
    RING_SIZE, WEIGHTS, STARTERS, FURNITURE,
    rank, reasonLine, cleanOCR, historyFromRows,
  });

  return { FilingKeys, FilingMemory, FilingSuggest };
})();

if (typeof globalThis === "object") Object.assign(globalThis, { FilingKeys, FilingMemory, FilingSuggest });
if (typeof module === "object" && module.exports) module.exports = { FilingKeys, FilingMemory, FilingSuggest };
