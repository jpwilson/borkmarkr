// bookmarker — what's interesting in the last day / week / month.
// Claude Sonnet 5 via OpenRouter. Titles and topics only — no notes, no URLs.

import { completeJSON, consumeQuota, json } from "../_shared/openrouter.ts";

const DAILY_LIMIT = 200;
const MAX_ITEMS = 40;
const MAX_FIELD = 140;

const SYSTEM = `You look at a person's recent bookmarks and say what is actually interesting.

They saved these links in the last day, week, or month. Find the thread — not a list of topics.

Write like a sharp friend, not a dashboard:
- headline: one line, spoken, no "Get into".
- summary: 2 or 3 short sentences. What they are circling. What spiked.
- spike: optional one-liner if one theme jumped.
- themes: 2 to 4 themes with a count and a why (one clause).
- suggestedQuest: a side-quest name they could start from this pile, or null.

No hashtags. No emoji. No medical or legal advice. If the pile is thin, say so plainly.

Return JSON:
{
  "headline": string,
  "summary": string,
  "spike": string|null,
  "themes": [ { "name": string, "count": number, "why": string } ],
  "suggestedQuest": string|null
}`;

interface Item {
  title?: string;
  topic?: string;
  subtopic?: string;
  platform?: string;
  tags?: string[];
}

const clamp = (value: unknown): string =>
  typeof value === "string" ? value.slice(0, MAX_FIELD).trim() : "";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const authorization = req.headers.get("Authorization") ?? "";

  let payload: { window?: string; items?: Item[] };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }

  const window = ["day", "week", "month"].includes(payload.window ?? "")
    ? payload.window
    : "week";
  const items = (payload.items ?? []).slice(0, MAX_ITEMS);
  if (items.length === 0) {
    return json({
      headline: "Nothing saved in this window",
      summary: "Save a few things and come back. The interesting part is the pile.",
      spike: null,
      themes: [],
      suggestedQuest: null,
    });
  }

  if (!await consumeQuota(authorization, DAILY_LIMIT)) {
    return json({ error: "quota" }, 429);
  }

  const lines = items.map((item, i) => {
    const tags = (item.tags ?? []).slice(0, 4).map(clamp).filter(Boolean);
    return [
      `${i + 1}. ${clamp(item.title) || "(untitled)"}`,
      clamp(item.topic) ? `topic=${clamp(item.topic)}` : null,
      clamp(item.subtopic) ? `sub=${clamp(item.subtopic)}` : null,
      clamp(item.platform) ? `from=${clamp(item.platform)}` : null,
      tags.length ? `tags=${tags.join(",")}` : null,
    ].filter(Boolean).join(" | ");
  }).join("\n");

  const user = `Window: last ${window}\nCount: ${items.length}\n\n${lines}`;

  try {
    const parsed = await completeJSON(SYSTEM, user, 700) as {
      headline?: unknown;
      summary?: unknown;
      spike?: unknown;
      themes?: unknown;
      suggestedQuest?: unknown;
    } | null;

    if (!parsed) {
      return json({ error: "model" }, 502);
    }

    const themes = Array.isArray(parsed.themes)
      ? parsed.themes.slice(0, 4).flatMap((row: { name?: unknown; count?: unknown; why?: unknown }) => {
        if (typeof row?.name !== "string") return [];
        return [{
          name: row.name.slice(0, 40),
          count: typeof row.count === "number" ? row.count : 0,
          why: typeof row.why === "string" ? row.why.slice(0, 140) : "",
        }];
      })
      : [];

    return json({
      headline: typeof parsed.headline === "string" ? parsed.headline.slice(0, 80) : "Here's the thread",
      summary: typeof parsed.summary === "string" ? parsed.summary.slice(0, 480) : "",
      spike: typeof parsed.spike === "string" ? parsed.spike.slice(0, 160) : null,
      themes,
      suggestedQuest: typeof parsed.suggestedQuest === "string"
        ? parsed.suggestedQuest.slice(0, 48)
        : null,
    });
  } catch (error) {
    console.error("insights failed", error);
    return json({ error: "model" }, 502);
  }
});
