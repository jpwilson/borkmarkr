/* bookmarker — the arithmetic behind Revisit.
 *
 * "Captured, organised, revisited, shared" — this file is the third verb. It
 * answers, from the library alone: what did you save this week, what do you
 * keep coming back to, what did you save and never look at, what did a month
 * ago look like, which side quests are half-done, and what is shifting.
 *
 * Pure by design — rows in, plain objects out, no DOM, no clock of its own
 * (`now` is a parameter). The Revisit tab renders these objects today; a weekly
 * email digest can build the same ones tomorrow without touching the page.
 *
 * Depends on one thing the page defines, read at call time only so load order
 * doesn't matter: TOPIC_BY_ID (docs/taxonomy.js → index.html). Without it the
 * topic sections fall back to raw ids rather than throwing.
 *
 * Rows are the wire shape (docs/index.html): saved_at, platform, category_id,
 * subcategory, tags, plus the local open ledger the page hangs on them —
 * open_count and last_opened_at, which the sync row has never carried.
 */
"use strict";

const Revisit = (() => {
  const DAY = 86_400_000;

  const savedAt = (r) => Date.parse(r && r.saved_at) || 0;
  const opens = (r) => Math.max(0, Number(r && r.open_count) || 0);
  const openedAt = (r) => Date.parse(r && r.last_opened_at) || 0;
  const byId = (a, b) => (a < b ? -1 : a > b ? 1 : 0);

  /* The taxonomy, if the page loaded it. A topic we can't name is a topic we
     can't link to either, so it stays out of the counts. */
  const topics = () => (typeof TOPIC_BY_ID === "object" && TOPIC_BY_ID) || null;
  const known = (id) => !!id && (!topics() || !!topics()[id]);
  const topicName = (id) => (topics() && topics()[id] && topics()[id].name) || id;

  const between = (rows, from, to) => rows.filter(r => { const t = savedAt(r); return t >= from && t < to; });
  const since = (rows, from) => rows.filter(r => savedAt(r) >= from);

  /** Sources, biggest first: [{ key: "instagram", n: 6 }, …]. The caller names
      them — PLATFORM lives on the page, not here. */
  function platformSplit(rows) {
    const counts = new Map();
    for (const r of rows) {
      const k = (r && r.platform) || "web";
      counts.set(k, (counts.get(k) || 0) + 1);
    }
    return [...counts.entries()]
      .sort((a, b) => b[1] - a[1] || byId(a[0], b[0]))
      .map(([key, n]) => ({ key, n }));
  }

  function topicCounts(rows) {
    const counts = new Map();
    for (const r of rows) if (r && known(r.category_id)) counts.set(r.category_id, (counts.get(r.category_id) || 0) + 1);
    return counts;
  }

  /** Topics that grew, this window against the one before it. */
  function risingTopics(now, before, limit = 3) {
    const a = topicCounts(now), b = topicCounts(before);
    const out = [];
    for (const [id, n] of a) {
      const prev = b.get(id) || 0;
      if (n <= prev) continue;
      out.push({ id, name: topicName(id), n, prev, delta: n - prev });
    }
    return out.sort((x, y) => y.delta - x.delta || y.n - x.n || byId(x.id, y.id)).slice(0, limit);
  }

  /* A shift is a change in *share*, not in count — saving more of everything
     isn't a shift. Small wobbles and one-off topics aren't either, so a move
     has to clear three points and rest on more than a single bork. */
  const SHIFT_MIN_DELTA = 0.03;
  const SHIFT_MIN_BORKS = 2;

  function shifting(now, before, limit = 3) {
    if (!now.length || !before.length) return null;   // no "before" is not a trend
    const a = topicCounts(now), b = topicCounts(before);
    const items = [];
    for (const id of new Set([...a.keys(), ...b.keys()])) {
      const n = a.get(id) || 0, prev = b.get(id) || 0;
      if (Math.max(n, prev) < SHIFT_MIN_BORKS) continue;
      const share = n / now.length, prevShare = prev / before.length;
      const delta = share - prevShare;
      if (Math.abs(delta) < SHIFT_MIN_DELTA) continue;
      items.push({ id, name: topicName(id), n, prev, share, prevShare, delta, direction: delta > 0 ? "up" : "down" });
    }
    const top = items
      .sort((x, y) => Math.abs(y.delta) - Math.abs(x.delta) || byId(x.id, y.id))
      .slice(0, limit);
    if (!top.length) return null;
    return { items: top, line: shiftLine(top) };
  }

  /** "More Fitness, less Crypto" — the sentence, from the parts. */
  function shiftLine(items) {
    const line = items.map(i => `${i.direction === "up" ? "more" : "less"} ${i.name}`).join(", ");
    return line.charAt(0).toUpperCase() + line.slice(1);
  }

  const NEVER_SHOWN = 12;

  /**
   * @param rows     every live bork (deleted rows are dropped here anyway)
   * @param missions side quests, already filtered to the live ones
   * @param now      epoch ms — the only clock this file has
   * @returns { total, thin, week, repeat, never, monthAgo, quests, shifting }
   *          with every section either a plain object or null when it's empty.
   */
  function build(rows, missions, now) {
    const all = (Array.isArray(rows) ? rows : []).filter(r => r && !r.deleted_at);
    const t = Number(now) || Date.now();
    const total = all.length;

    // 1 · Saved this week, against the week before it.
    const thisWeek = since(all, t - 7 * DAY);
    const lastWeek = between(all, t - 14 * DAY, t - 7 * DAY);
    const week = thisWeek.length
      ? { n: thisWeek.length, platforms: platformSplit(thisWeek), rising: risingTopics(thisWeek, lastWeek) }
      : null;

    // 2 · What you actually go back to. Ties break on the most recent open.
    const reopened = all.filter(r => opens(r) > 0)
      .sort((a, b) => opens(b) - opens(a) || openedAt(b) - openedAt(a) || savedAt(b) - savedAt(a));
    const repeat = reopened.length ? { rows: reopened.slice(0, 5) } : null;

    // 3 · The pile. Saved long enough ago to count as ignored, never opened.
    const forgotten = all.filter(r => opens(r) === 0 && savedAt(r) > 0 && savedAt(r) < t - 7 * DAY)
      .sort((a, b) => savedAt(b) - savedAt(a));
    const never = forgotten.length
      ? { rows: forgotten, n: forgotten.length, shown: Math.min(NEVER_SHOWN, forgotten.length),
          more: Math.max(0, forgotten.length - NEVER_SHOWN) }
      : null;

    // 4 · A month ago today.
    const monthRows = between(all, t - 35 * DAY, t - 28 * DAY).sort((a, b) => savedAt(b) - savedAt(a)).slice(0, 3);
    const monthAgo = monthRows.length ? { rows: monthRows } : null;

    // 5 · Side quests with something left to tick off.
    const open = (Array.isArray(missions) ? missions : [])
      .filter(m => m && !m.deleted_at && !m.is_archived && (m.todos || []).some(td => td && !td.done));
    const quests = open.length ? { missions: open } : null;

    // 6 · What's shifting: the last 30 days against the 30 before, and only
    //     once there's enough on both sides of the line to mean anything.
    const now30 = since(all, t - 30 * DAY);
    const prev30 = between(all, t - 60 * DAY, t - 30 * DAY);
    const shift = now30.length + prev30.length >= 20 ? shifting(now30, prev30) : null;

    return { total, thin: total < 10, week, repeat, never, monthAgo, quests, shifting: shift };
  }

  return { build, DAY, NEVER_SHOWN, SHIFT_MIN_DELTA, SHIFT_MIN_BORKS,
           _platformSplit: platformSplit, _rising: risingTopics, _shifting: shifting, _line: shiftLine };
})();

const buildRevisit = (rows, missions, now) => Revisit.build(rows, missions, now);

/* Node (Scripts/test_revisit.mjs) rather than a browser. */
if (typeof module === "object" && module.exports) module.exports = { Revisit, buildRevisit };
