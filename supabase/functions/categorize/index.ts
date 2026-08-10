// borkmarkr — AI categorisation.
//
// WHY THIS IS A SERVER FUNCTION AND NOT A LIBRARY IN THE APP
//
// Calling Anthropic from the iOS app would mean shipping an API key inside the
// binary. Anyone can run `strings` on an .ipa; a shipped key is a stolen key,
// and the bill lands on the developer. So the key lives here, in the function's
// environment, and the app authenticates as itself with the user's Supabase
// JWT. The app never sees the key and never talks to Anthropic directly.
//
// WHAT THIS IS FOR
//
// Core/Categorizer.swift already files most links offline, instantly and for
// free, by matching the title and URL against the taxonomy. It is deliberately
// honest about not knowing — when nothing scores well enough it returns no
// topic, and the link shows as "Not filed yet".
//
// This function exists for exactly those. The app calls it only when the
// offline pass came back empty or weak, so cost tracks the hard cases rather
// than every save.
//
// IT IS STILL ONLY A SUGGESTION. The app shows the result and the user can
// change it before saving — same contract as the offline categoriser.

import Anthropic from "npm:@anthropic-ai/sdk";
import { TAXONOMY, TOPIC_IDS } from "./taxonomy.ts";

const MODEL = "claude-haiku-4-5";

// Deliberately the cheap model. This is single-label classification against a
// fixed list, not reasoning — the taxonomy in the prompt does the hard part.
// At ~2.2k input tokens per call it costs roughly a quarter of a cent, and only
// the links the offline pass couldn't place get here.

/** Per-user, per-UTC-day ceiling. See supabase/migrations/0002_ai_quota.sql. */
const DAILY_LIMIT = 200;

/** Guards against a client pasting a novel into `text` and inflating the bill. */
const MAX_FIELD = 600;

const SYSTEM = `You file saved links into a fixed taxonomy.

The user saved a link from a social app or the web. You get its URL, title, and
sometimes the author, a caption, and tags the user typed. Choose where it
belongs.

Rules:
- topic MUST be one of the ids below, exactly as written, or null.
- subtopic MUST be one of that topic's listed subtopics, exactly as written, or
  null if none of them fit the link.
- Return null for topic when the link genuinely doesn't fit anywhere, or when
  you have too little to go on (a bare URL with no readable title). A wrong
  confident answer is worse than no answer — the app has an honest
  "Not filed yet" state and the user can file it themselves.
- tags: 2 to 4 short lowercase keywords describing the actual subject. Words a
  person would search for later. No hashtags, no punctuation, no platform names
  (the app adds those itself), no generic filler like "video" or "tips".
- Judge the subject matter, not the format. A cooking video is recipes, not
  filmtv.

TAXONOMY (id (display name): subtopics)
${TAXONOMY}`;

const SCHEMA = {
  type: "object",
  properties: {
    topic: { type: ["string", "null"] },
    subtopic: { type: ["string", "null"] },
    tags: { type: "array", items: { type: "string" } },
  },
  required: ["topic", "subtopic", "tags"],
  additionalProperties: false,
};

interface Payload {
  url?: string;
  title?: string;
  author?: string;
  text?: string;
  tags?: string[];
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

/** Empty suggestion. The app falls back to its offline result on this. */
const empty = () => json({ topic: null, subtopic: null, tags: [] });

const clamp = (value: unknown): string =>
  typeof value === "string" ? value.slice(0, MAX_FIELD).trim() : "";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    // Not configured yet — say so plainly rather than pretending it worked.
    // The app treats this as "no suggestion" and uses the offline result.
    console.error("ANTHROPIC_API_KEY is not set");
    return empty();
  }

  // verify_jwt is on, so we already know the caller is authenticated. Forward
  // their token so the quota is charged to them and RLS applies as usual.
  const authorization = req.headers.get("Authorization") ?? "";

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }

  const url = clamp(payload.url);
  const title = clamp(payload.title);
  if (!url && !title) return json({ error: "url or title required" }, 400);

  // Consume quota BEFORE spending money. Fail closed: if the quota check itself
  // errors we skip the model rather than risk an unmetered call.
  try {
    const allowed = await fetch(
      `${Deno.env.get("SUPABASE_URL")}/rest/v1/rpc/ai_quota_consume`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
          Authorization: authorization,
        },
        body: JSON.stringify({ daily_limit: DAILY_LIMIT }),
      },
    );
    if (!allowed.ok || (await allowed.json()) !== true) {
      console.warn("quota denied or unavailable", allowed.status);
      return empty();
    }
  } catch (error) {
    console.error("quota check failed", error);
    return empty();
  }

  const facts = [
    `URL: ${url}`,
    title ? `Title: ${title}` : null,
    payload.author ? `Author: ${clamp(payload.author)}` : null,
    payload.text ? `Caption: ${clamp(payload.text)}` : null,
    payload.tags?.length
      ? `User tags: ${payload.tags.slice(0, 10).map(clamp).join(", ")}`
      : null,
  ].filter(Boolean).join("\n");

  try {
    const client = new Anthropic({ apiKey });
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 300,
      system: [{
        type: "text",
        text: SYSTEM,
        // The taxonomy is a stable prefix, so mark it cacheable. On Haiku 4.5
        // the minimum cacheable prefix is 4096 tokens and this is ~2.2k, so
        // today this is a no-op that costs nothing — it starts paying the day
        // the taxonomy grows or the model changes.
        cache_control: { type: "ephemeral" },
      }],
      output_config: { format: { type: "json_schema", schema: SCHEMA } },
      messages: [{ role: "user", content: facts }],
    });

    // Structured outputs guarantee the shape, but a refusal returns no JSON.
    if (response.stop_reason === "refusal") return empty();

    const text = response.content.find((b) => b.type === "text")?.text ?? "";
    const parsed = JSON.parse(text);

    // Validate the topic id against the same list we sent. Belt and braces —
    // structured outputs constrain the type, not the vocabulary.
    const topic = typeof parsed.topic === "string" && TOPIC_IDS.has(parsed.topic)
      ? parsed.topic
      : null;

    return json({
      topic,
      subtopic: topic && typeof parsed.subtopic === "string" ? parsed.subtopic : null,
      tags: Array.isArray(parsed.tags)
        ? parsed.tags
          .filter((t: unknown): t is string => typeof t === "string")
          .map((t: string) => t.toLowerCase().replace(/[^a-z0-9 -]/g, "").trim())
          .filter((t: string) => t.length > 1 && t.length < 24)
          .slice(0, 4)
        : [],
    });
  } catch (error) {
    // Never fail the user's save because categorisation failed. The app has a
    // working offline answer already; this was only ever an upgrade.
    console.error("categorise failed", error);
    return empty();
  }
});
