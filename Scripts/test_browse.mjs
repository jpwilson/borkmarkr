#!/usr/bin/env node
/**
 * Tests for docs/browse.js — Browse's ordering and the topic share message.
 *
 *     node Scripts/test_browse.mjs
 *
 * Both halves are ports whose contract is cross-platform: the chip labels and
 * the ordering must match `Core/BrowseSort.swift`, and the message must match
 * `Core/TopicShare.swift` to the character, because the message is the only
 * part of the app a stranger sees before they have it. So these are largely
 * the same checks as `Scripts/test_browse_sort.swift` and
 * `Scripts/test_topic_share.swift`, run against the JavaScript.
 *
 * Same shape as Scripts/test_revisit.mjs: the file is loaded into a vm context
 * exactly as the browser loads it, and nothing here touches a DOM.
 */
import fs from "node:fs";
import path from "node:path";
import vm from "node:vm";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const read = (p) => fs.readFileSync(p, "utf8");

const ctx = vm.createContext({ console, URL, TextEncoder });
vm.runInContext(read(path.join(ROOT, "docs", "browse.js")), ctx, { filename: "browse.js" });
const { BrowseSort, TopicShare } = vm.runInContext("({ BrowseSort, TopicShare })", ctx);

/* makeTopicID lives inline in index.html, above the helper block the other
   .mjs tests borrow, so it is sliced out on its own. If the block moves this
   throws rather than silently testing nothing. */
function topicIDHelpers() {
  const html = read(path.join(ROOT, "docs", "index.html"));
  const from = html.indexOf('const CUSTOM_PREFIX = "custom.";');
  const to = html.indexOf("/* CustomTopic.nextHue walks");
  if (from < 0 || to < 0 || to < from) {
    throw new Error("docs/index.html: couldn't find the topic-id block "
      + "(const CUSTOM_PREFIX … CustomTopic.nextHue). If it moved, update this test.");
  }
  return html.slice(from, to);
}
vm.runInContext(topicIDHelpers(), ctx, { filename: "index.html topic ids" });
const { makeTopicID, ART_ID } = vm.runInContext("({ makeTopicID, ART_ID })", ctx);

/* ── Tiny runner ── */
let failures = 0, checks = 0;
function ok(cond, message) {
  checks++;
  if (cond) return;
  failures++;
  console.log(`FAIL ${message}`);
}
function eq(actual, expected, message) {
  const a = JSON.stringify(actual), b = JSON.stringify(expected);
  ok(a === b, `${message}\n     expected ${b}\n     got      ${a}`);
}
function group(name, fn) { console.log(`\n${name}`); fn(); }

const DAY = 86_400_000;
const BASE = 1_800_000_000_000;
const day = (offset) => BASE + offset * DAY;
const entry = (id, name, count, recent, extra = {}) => ({ id, name, count, recent, ...extra });
const ids = (option, entries) => BrowseSort.orderedIDs(option, entries);

/* ══ BrowseSort ══════════════════════════════════════════════════════════ */

group("Labels are a cross-platform contract", () => {
  eq(BrowseSort.title("borks"), "Most borks", "the count option is Most borks");
  eq(BrowseSort.title("recent"), "Most recent", "the recency option is Most recent");
  eq(BrowseSort.title("alpha"), "A–Z", "the alphabetical option is A–Z, with an en dash");
  eq(BrowseSort.ALL.length, 3, "three options, no more");
  eq(BrowseSort.FALLBACK, "borks", "the default is Most borks — what Browse did before");
  eq(BrowseSort.named("alpha"), "alpha", "a persisted choice comes back");
  eq(BrowseSort.named("nonsense"), "borks", "a junk stored value falls back");
  eq(BrowseSort.named(null), "borks", "nothing persisted falls back");
  eq(BrowseSort.named(undefined), "borks", "and neither does undefined throw");
  const keys = Object.values(BrowseSort.KEY);
  eq(new Set(keys).size, 3, "each segment persists under its own key");
  ok(keys.every(k => k.startsWith("bm.")), "and under this app's localStorage prefix");
});

group("The topic grid", () => {
  const topics = [
    entry("fitness", "Fitness", 8, day(-1), { rank: 0 }),
    entry("crypto", "Crypto", 12, day(-40), { rank: 1 }),
    entry("art", "Art & design", 3, day(-2), { rank: 2 }),
    // A topic you made and have not filed anything into yet.
    entry("custom.bouldering", "Bouldering", 0, null, { rank: 3 }),
  ];
  eq(ids("borks", topics), ["crypto", "fitness", "art", "custom.bouldering"],
    "Most borks is count descending");
  eq(ids("recent", topics), ["fitness", "art", "crypto", "custom.bouldering"],
    "Most recent is newest bork first, and an empty topic is last");
  eq(ids("alpha", topics), ["art", "custom.bouldering", "crypto", "fitness"],
    "A–Z mixes a custom topic in among the built-ins");
});

group("Interests float, but only where floating is honest", () => {
  const pinned = [
    entry("garden", "Garden", 1, day(-9), { pinned: true, rank: 5 }),
    entry("crypto", "Crypto", 12, day(-40), { rank: 1 }),
  ];
  eq(ids("borks", pinned), ["garden", "crypto"], "a pinned topic still floats to the top of Most borks");
  eq(ids("alpha", pinned), ["crypto", "garden"], "A–Z ignores it — an A–Z that isn't alphabetical is not A–Z");
  eq(ids("recent", pinned), ["garden", "crypto"], "Most recent ignores it and answers only about dates");
});

group("Ties keep the list's own order, in both directions", () => {
  const tied = [
    entry("b", "Beta", 4, day(-3), { rank: 1 }),
    entry("a", "Alpha", 4, day(-3), { rank: 0 }),
    entry("c", "Gamma", 4, day(-3), { rank: 2 }),
  ];
  for (const option of BrowseSort.ALL) {
    eq(ids(option, tied), ids(option, [...tied].reverse()), `${BrowseSort.title(option)} does not depend on input order`);
  }
  eq(ids("borks", tied), ["a", "b", "c"], "equal counts fall back to canonical order");
  eq(ids("recent", [
    entry("x", "X", 0, null, { rank: 1 }),
    entry("y", "Y", 0, null, { rank: 0 }),
  ]), ["y", "x"], "two never-used entries keep canonical order rather than shuffling");
});

group("Sources", () => {
  const sources = [
    entry("x", "X", 4, day(-6), { rank: 0 }),
    entry("instagram", "Instagram", 9, day(-1), { rank: 1 }),
    entry("grok", "Grok", 0, null, { rank: 7 }),
    entry("web", "Web", 2, day(-30), { rank: 8 }),
  ];
  eq(ids("borks", sources), ["instagram", "x", "web", "grok"],
    "a source you have never saved from sinks to the bottom of Most borks");
  eq(ids("alpha", sources), ["grok", "instagram", "web", "x"], "A–Z on sources is by display name");
  eq(BrowseSort.order("borks", sources).length, sources.length, "sorting never drops a row");
});

group("Side quests", () => {
  // "Most recent" for a quest is the later of created and updated, so working
  // on an old one brings it back to the top; rank is the newest-first order.
  const quests = [
    entry("q1", "Run a faster 10k", 6, day(-20), { rank: 1 }),
    entry("q2", "Pick a van", 2, day(-1), { rank: 0 }),
    entry("q3", "Learn pottery", 6, day(-30), { rank: 2 }),
  ];
  eq(ids("borks", quests), ["q1", "q3", "q2"], "the fullest quest leads, ties by newest");
  eq(ids("recent", quests), ["q2", "q1", "q3"], "touched last leads");
  eq(ids("alpha", quests), ["q3", "q2", "q1"], "A–Z is by quest title");
});

group("A–Z is locale-aware, not byte order", () => {
  const awkward = [
    entry("z10", "Zone 10", 0, null, { rank: 0 }),
    entry("z2", "Zone 2", 0, null, { rank: 1 }),
    entry("eclair", "Éclairs", 0, null, { rank: 2 }),
    entry("east", "eastern europe", 0, null, { rank: 3 }),
  ];
  const order = ids("alpha", awkward);
  ok(order.indexOf("z2") < order.indexOf("z10"), "Zone 2 sorts before Zone 10, not after it");
  ok(order.indexOf("east") < order.indexOf("eclair") && order.indexOf("eclair") < order.indexOf("z2"),
    `an accent and a lowercase initial land where a reader expects them (${order.join(", ")})`);
});

group("Degenerate input", () => {
  for (const option of BrowseSort.ALL) {
    eq(BrowseSort.order(option, []), [], `${BrowseSort.title(option)} of nothing is nothing`);
    eq(BrowseSort.order(option, null), [], `${BrowseSort.title(option)} of null is nothing`);
  }
  const one = [entry("only", "Only", 3, day(-1), { rank: 0 })];
  eq(ids("alpha", one), ["only"], "one row is already sorted");
  const source = [entry("a", "A", 1, day(-1), { rank: 0 })];
  BrowseSort.order("alpha", source);
  eq(source.length, 1, "the input array is never sorted in place");
});

/* ══ TopicShare ══════════════════════════════════════════════════════════ */

const item = (title, url, offset) => ({ title, url, savedAt: day(offset) });

group("The heading and the count line", () => {
  eq(TopicShare.heading("Fitness"), "Fitness", "no subtopic, no separator");
  eq(TopicShare.heading("Fitness", "Strength"), "Fitness › Strength", "a selected subtopic is named");
  eq(TopicShare.heading("Fitness", "  "), "Fitness", "a blank subtopic is no subtopic");
  eq(TopicShare.countLine("Fitness", "Strength", 8),
    "Fitness › Strength — 8 borks I saved with bookmarker", "the count line reads as a person wrote it");
  eq(TopicShare.countLine("Fitness", null, 1),
    "Fitness — 1 bork I saved with bookmarker", "one bork is not 1 borks");
  eq(TopicShare.countedBorks(0), "0 borks", "and zero is borks too");
});

group("Ordering: newest first, deterministically", () => {
  const mixed = [
    item("Oldest", "https://example.com/a", -30),
    item("Newest", "https://example.com/b", -1),
    item("Middle", "https://example.com/c", -10),
  ];
  eq(TopicShare.newestFirst(mixed).map(i => i.title), ["Newest", "Middle", "Oldest"],
    "most recently saved first");
  eq(TopicShare.newestFirst([
    item("Beta", "https://example.com/b", -4),
    item("Alpha", "https://example.com/a", -4),
  ]).map(i => i.title), ["Alpha", "Beta"], "two saved in the same second still order the same way every time");
  const source = [item("A", "https://example.com/a", -1)];
  TopicShare.newestFirst(source);
  eq(source.length, 1, "and the caller's array is left alone");
});

const caption = "This 12 minute mobility routine completely changed how my hips feel after long runs and I cannot recommend it enough honestly";

group("Truncation: a caption is not a title", () => {
  const cut = TopicShare.shortTitle(caption);
  ok([...cut].length <= TopicShare.titleLimit + 1, "a caption is cut to roughly one line");
  ok(cut.endsWith("…"), "a cut title says it was cut");
  ok(!cut.endsWith(" …"), "no space before the ellipsis");
  ok(!cut.slice(0, -1).endsWith("hone"), "the cut lands on a word, not inside one");
  eq(TopicShare.shortTitle("Short enough"), "Short enough", "a title that fits is left alone");
  eq(TopicShare.shortTitle("Two\nlines   and  spaces"), "Two lines and spaces",
    "newlines and runs of whitespace collapse — captions arrive with both");
  ok(TopicShare.shortTitle("Averyverylongsingleunbrokenwordthatgoesonandonandonandonandonandonandonandonforever").endsWith("…"),
    "a title with no word boundary is still cut");
  ok(![...TopicShare.shortTitle("🏃‍♀️ " + "x".repeat(200))].some(c => c === "�"),
    "cutting counts characters, so an emoji is never sliced in half");
  eq(TopicShare.shortTitle(""), "", "nothing is nothing");
});

group("Links: short where short still works", () => {
  eq(TopicShare.shortLink("https://www.instagram.com/reel/C8xhamstring"), "instagram.com/reel/C8xhamstring",
    "the scheme and www. come off — Messages still detects the rest");
  eq(TopicShare.shortLink("https://example.com/a/"), "example.com/a", "a trailing slash comes off");
  eq(TopicShare.shortLink("https://www.youtube.com/watch?v=protein30"), null,
    "a query carries the identity, so that link is never shortened");
  eq(TopicShare.shortLink("https://example.com/page#section"), null,
    "a fragment is not thrown away either");
  eq(TopicShare.shortLink("https://example.com/" + "x".repeat(80)), null,
    "a path too long to fit is not truncated into a dead link");
  eq(TopicShare.shortLink("not a url at all"), null, "junk is not a link");
  eq(TopicShare.linkLine("https://www.youtube.com/watch?v=protein30"),
    "https://www.youtube.com/watch?v=protein30",
    "what cannot be shortened is printed whole, so it stays tappable");
  eq(TopicShare.linkLine("https://www.instagram.com/reel/C8xhamstring"), "instagram.com/reel/C8xhamstring",
    "what can be shortened is");
  eq(TopicShare.footer(), "bookmarker.lol/get", "the footer is shortened by the same rule");
  eq(TopicShare.getURL, "https://bookmarker.lol/get", "and points at the install page");
});

group("displayURL: the card, where nothing is tappable", () => {
  eq(TopicShare.displayURL("https://www.youtube.com/watch?v=protein30"), "youtube.com/watch?…",
    "the card shows a query as an ellipsis rather than a parameter dump");
  const long = TopicShare.displayURL("https://example.com/" + "x".repeat(80));
  ok([...long].length === TopicShare.linkLimit && long.endsWith("…"), "the card's link always fits");
  eq(TopicShare.displayURL("not a url"), "not a url", "junk is printed as it came");
});

group("The whole message", () => {
  const thirteen = Array.from({ length: 13 }, (_, i) =>
    item(`Bork number ${i + 1}`, `https://example.com/${i + 1}`, -(i + 1)));
  const message = TopicShare.message({ topic: "Fitness", subtopic: "Strength", items: thirteen });
  const lines = message.split("\n");

  eq(lines[0], "Fitness › Strength — 13 borks I saved with bookmarker",
    "the count is the whole slice, not the ten that got listed");
  eq(lines[1], "", "a blank line under the heading");
  eq(lines[2], "1. Bork number 1", "the newest bork is number 1");
  eq(lines[3], "   example.com/1", "its link is indented under it");
  ok(message.includes("10. Bork number 10"), "ten borks are listed");
  ok(!message.includes("11. "), "and no more than ten");
  ok(message.includes("\n+ 3 more"), "the rest are counted, not printed");
  eq(lines[lines.length - 1], "bookmarker.lol/get", "the last line is where to get the app");
  eq(lines[lines.length - 2], "", "with a blank line above it");
  ok(message.length < 700, `the whole thing fits in a chat bubble (${message.length} chars)`);
});

group("Never a caption, never body text", () => {
  const one = TopicShare.message({ topic: "Fitness", items: [item(caption, "https://www.instagram.com/reel/abc", -1)] });
  ok(one.includes("1. This 12 minute mobility routine"), "the title leads");
  ok(!one.includes("recommend it enough"), "the tail of a caption never ships");
  ok(one.includes("instagram.com/reel/abc"), "the link is there and it is short");
  ok(one.startsWith("Fitness — 1 bork I saved with bookmarker"), "one bork reads correctly");
  ok(!one.includes("+ 0 more"), "nothing left over means nothing to say about it");

  const exactlyTen = Array.from({ length: 10 }, (_, i) => item(`Bork ${i + 1}`, `https://example.com/${i + 1}`, -(i + 1)));
  ok(!TopicShare.message({ topic: "Fitness", items: exactlyTen }).includes("more"),
    "exactly ten borks does not claim there are more");

  const empty = TopicShare.message({ topic: "Fitness", items: [] });
  ok(empty.startsWith("Fitness — 0 borks"), "an empty slice still says something true");
  ok(empty.endsWith("bookmarker.lol/get"), "and still says where to get the app");
  eq(TopicShare.message({ topic: "Fitness" }).split("\n"),
    ["Fitness — 0 borks I saved with bookmarker", "", "", "bookmarker.lol/get"],
    "no items at all is a heading and a footer, spaced the same way");
});

group("The image card's titles", () => {
  const twelve = Array.from({ length: 12 }, (_, i) => item(`Bork ${i + 1}`, `https://example.com/${i + 1}`, -(i + 1)));
  const titles = TopicShare.cardTitles(twelve);
  eq(titles.length, 6, "six titles fit on the card");
  eq(titles[0], "Bork 1", "newest first, same as the message");
  ok(TopicShare.cardTitles([item(caption, "https://example.com/a", -1)])[0].endsWith("…"),
    "and a caption is cut shorter for the card than for the message");
  ok([...TopicShare.cardTitles([item(caption, "https://example.com/a", -1)])[0]].length <= 53,
    "to about 52 characters");
});

group("Topic ids match the phone", () => {
  /* Duplicated verbatim from Scripts/test_topic_art.swift. A topic invented
     here and the same topic invented on the phone have to land on one id, or
     the two disagree about which topic a bork is even in — and the web derives
     everything it knows about a custom topic from that id. If you change one
     table, change both. */
  const ids = [
    ["Juice", "custom.juice"],
    ["Looksmaxxing", "custom.looksmaxxing"],
    ["Trail running", "custom.trail-running"],
    ["Zone 2", "custom.zone-2"],
    ["Hair & grooming", "custom.hair-grooming"],
    ["  spaced  ", "custom.spaced"],
    ["Café culture", "custom.cafe-culture"],
    ["Cafe culture", "custom.cafe-culture"],
    ["Über alles", "custom.uber-alles"],
    ["Crème brûlée", "custom.creme-brulee"],
    ["Naïve", "custom.naive"],
    ["ÅNGSTRÖM", "custom.angstrom"],
    ["!!!", "custom.topic"],
    ["北京", "custom.topic-36943181"],
    ["Готовка", "custom.topic-9888f5f3"],
    ["Ελλάδα", "custom.topic-f49bab5a"],
  ];
  for (const [name, id] of ids) {
    eq(makeTopicID(name), id, `makeTopicID(${JSON.stringify(name)})`);
    ok(ART_ID.test(id), `${id} can be sent for art`);
  }
  eq(makeTopicID("Café culture"), makeTopicID("Cafe culture"), "the accent is not a second topic");
  ok(makeTopicID("北京") !== makeTopicID("Готовка"),
    "two names with no Latin in them are still two topics");
});

console.log(`\n${checks - failures}/${checks} checks passed`);
process.exit(failures ? 1 : 0);
