// bookmarker — AI categorisation via OpenRouter (Claude Sonnet 5).
//
// The key is OPENROUTER_API_KEY on the function. It never ships in the app.

import { TAXONOMY, TOPIC_IDS } from "./taxonomy.ts";
import { completeJSON, consumeQuota, json } from "../_shared/openrouter.ts";

const DAILY_LIMIT = 200;
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
  you have too little to go on (a bare URL with no readable title).
- tags: 2 to 4 short lowercase keywords. No hashtags, no platform names.
- Judge the subject matter, not the format.

Return JSON: { "topic": string|null, "subtopic": string|null, "tags": string[] }

TAXONOMY (id (display name): subtopics)
${TAXONOMY}`;

interface Payload {
  url?: string;
  title?: string;
  author?: string;
  text?: string;
  tags?: string[];
}

const empty = () => json({ topic: null, subtopic: null, tags: [] });

const clamp = (value: unknown): string =>
  typeof value === "string" ? value.slice(0, MAX_FIELD).trim() : "";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

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

  if (!await consumeQuota(authorization, DAILY_LIMIT)) {
    console.warn("quota denied or unavailable");
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
    const parsed = await completeJSON(SYSTEM, facts, 400) as {
      topic?: unknown;
      subtopic?: unknown;
      tags?: unknown;
    } | null;
    if (!parsed) return empty();

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
    console.error("categorise failed", error);
    return empty();
  }
});
