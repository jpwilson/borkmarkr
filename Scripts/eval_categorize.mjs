#!/usr/bin/env node
/**
 * Quality check for the categorize Edge Function.
 *
 *     CATEGORIZE_URL=https://<ref>.supabase.co/functions/v1/categorize-canary \
 *     REVIEW_PASSWORD=… node Scripts/eval_categorize.mjs
 *
 * Signs in as the review account (APPSTORE.md — `REVIEW_EMAIL` defaults to it,
 * `REVIEW_PASSWORD` is never in the repo) or uses a ready access token in
 * `CATEGORIZE_JWT`, then POSTs every case in Scripts/fixtures/categorize_eval.json
 * exactly as the app would and scores the answers:
 *
 *   topic accuracy   — of the cases that have a right topic, how many got it
 *   subtopic accuracy — of those, how many also got an acceptable subtopic
 *   null precision   — when the model declined to file, how often that was right
 *   null recall      — of the cases that should be null, how many were
 *   wrong filings    — filed under a topic that is not acceptable (what Seb saw)
 *
 * Run it against a canary deploy before touching production `categorize`: the
 * daily AI quota is per user (200) and each case is one call. Nothing here
 * prints a credential.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const SUPABASE_URL = process.env.SUPABASE_URL || "https://pcjuxnhqxyfvgagnblzv.supabase.co";
const ANON_KEY = process.env.SUPABASE_ANON_KEY || "sb_publishable_z0wBO4NZrMW3T0ZywSDfJA_UoFRHMKb";
const CATEGORIZE_URL = process.env.CATEGORIZE_URL || `${SUPABASE_URL}/functions/v1/categorize-canary`;
const CASES = process.env.EVAL_CASES || path.join(ROOT, "Scripts", "fixtures", "categorize_eval.json");
const CONCURRENCY = Number(process.env.EVAL_CONCURRENCY || 3);

async function accessToken() {
  if (process.env.CATEGORIZE_JWT) return process.env.CATEGORIZE_JWT;
  const email = process.env.REVIEW_EMAIL || "review@bookmarker.lol";
  const password = process.env.REVIEW_PASSWORD;
  if (!password) {
    console.error("Set CATEGORIZE_JWT, or REVIEW_PASSWORD for the review account (see APPSTORE.md).");
    process.exit(2);
  }
  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email, password }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok || !body.access_token) {
    console.error(`Sign-in failed (${res.status}): ${body.error_description || body.msg || body.error || "no token"}`);
    process.exit(2);
  }
  return body.access_token;
}

/* The payload the iOS app and the web app send — see SmartCategorizer.swift
   and suggestTopicFor in docs/index.html. */
function payload(c) {
  const hashtags = [...new Set(
    [c.title, c.text, c.description].filter(Boolean).join(" ").match(/#[\p{L}\p{N}_]+/gu)?.map(h => h.slice(1).toLowerCase()) ?? []
  )];
  return {
    url: c.url, title: c.title ?? null, author: c.author ?? null, text: c.text ?? null,
    description: c.description ?? null, hashtags, tags: c.tags ?? [], platform: c.platform ?? null,
  };
}

async function ask(token, c) {
  const res = await fetch(CATEGORIZE_URL, {
    method: "POST",
    headers: { apikey: ANON_KEY, Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(payload(c)),
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`${res.status} ${text.slice(0, 120)}`);
  return JSON.parse(text);
}

function judge(c, got) {
  const e = c.expect;
  const acceptable = e.topics || [];
  const wantsNull = acceptable.length === 0;
  const isNull = !got.topic;
  const topicRight = !isNull && acceptable.includes(got.topic);
  const declinedOk = isNull && (wantsNull || e.nullOk === true);
  const never = (e.never || []).includes(got.topic);
  const subRight = topicRight && (!e.subtopics || e.subtopics.includes(got.subtopic));
  const ok = wantsNull ? isNull : (topicRight && (!e.subtopics || subRight)) || declinedOk;
  return { ok, isNull, topicRight, declinedOk, never, subRight, wantsNull };
}

async function main() {
  const doc = JSON.parse(fs.readFileSync(CASES, "utf8"));
  const token = await accessToken();
  console.log(`categorize eval → ${CATEGORIZE_URL}\n${doc.cases.length} cases, concurrency ${CONCURRENCY}\n`);

  const results = new Array(doc.cases.length);
  let next = 0;
  await Promise.all(Array.from({ length: CONCURRENCY }, async () => {
    while (next < doc.cases.length) {
      const i = next++;
      const c = doc.cases[i];
      try {
        results[i] = { c, got: await ask(token, c) };
      } catch (error) {
        results[i] = { c, error: String(error.message || error) };
      }
    }
  }));

  const tally = { withTopic: 0, topicRight: 0, subCases: 0, subRight: 0, nulls: 0, nullsRight: 0, wantNull: 0, wantNullRight: 0, wrong: 0, never: 0, errors: 0, ok: 0 };
  for (const r of results) {
    const { c } = r;
    if (r.error) {
      tally.errors++;
      console.log(`ERR  ${c.name}\n       ${r.error}`);
      continue;
    }
    const got = r.got;
    const j = judge(c, got);
    const filed = got.topic ? `${got.topic}${got.subtopic ? " › " + got.subtopic : ""}` : "null";
    const want = j.wantsNull ? "null" : c.expect.topics.join("|") + (c.expect.subtopics ? ` › ${c.expect.subtopics.join("|")}` : "") + (c.expect.nullOk ? " (or null)" : "");
    const mark = j.ok ? "ok  " : "FAIL";
    console.log(`${mark} ${c.seb ? "[SEB] " : ""}${c.name}\n       got ${filed} (${got.confidence}) — want ${want}${got.reason ? `\n       "${got.reason}"` : ""}`);

    if (j.ok) tally.ok++;
    if (!j.wantsNull) {
      tally.withTopic++;
      if (j.topicRight) tally.topicRight++;
      if (j.topicRight && c.expect.subtopics) { tally.subCases++; if (j.subRight) tally.subRight++; }
    } else {
      tally.wantNull++;
      if (j.isNull) tally.wantNullRight++;
    }
    if (j.isNull) { tally.nulls++; if (j.declinedOk) tally.nullsRight++; }
    if (!j.isNull && !j.topicRight) tally.wrong++;
    if (j.never) tally.never++;
  }

  const pct = (a, b) => b ? `${Math.round(100 * a / b)}% (${a}/${b})` : "n/a";
  console.log(`
── Summary
   cases passing      ${pct(tally.ok, results.length - tally.errors)}
   topic accuracy     ${pct(tally.topicRight, tally.withTopic)}
   subtopic accuracy  ${pct(tally.subRight, tally.subCases)}
   null precision     ${pct(tally.nullsRight, tally.nulls)}
   null recall        ${pct(tally.wantNullRight, tally.wantNull)}
   wrong filings      ${tally.wrong}${tally.never ? ` (${tally.never} on a topic the case forbids)` : ""}
   errors             ${tally.errors}`);
  process.exit(tally.errors || tally.never ? 1 : 0);
}

main();
