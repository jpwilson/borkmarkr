// bookmarker — the brief under THE THREAD on a side quest: what the quest is
// about, in two sentences, and three next actions. Claude Sonnet 5 via
// OpenRouter. The quest's name, topic, the titles on it and its steps go up —
// no notes, no URLs.

import { completeJSON, consumeQuota, json } from "../_shared/openrouter.ts";

const DAILY_LIMIT = 200;
const MAX_TITLES = 12;
const MAX_TODOS = 8;
const MAX_FIELD = 140;
const MAX_SUMMARY = 320;
const MAX_STEPS = 3;
const MAX_STEP = 80;

const SYSTEM = `You write the short brief at the top of a SIDE QUEST in a bookmark app.

A side quest is why someone kept a pile of links — become something, decide something, get through something. Topics file what a link IS; a side quest is WHY they kept it. You get the quest's name, its topic, the titles of the links on it (there may be none yet) and the steps they have written so far.

Write like a sharp friend, not a dashboard:
- summary: at most 2 short sentences, second person, plain words. Say what they are after and what the pile says about it. If nothing is on the quest yet, say what the first thing worth pulling in would be — never just "nothing here yet".
- steps: exactly 3 next actions, each 3 to 8 words, imperative and concrete, drawn from the titles when you can. Do not repeat a step they already wrote. No "read more", no "do some research".

No hashtags, no emoji, no bullet characters, no medical or legal advice. Never write "Get into".

Return JSON: { "summary": string, "steps": [string, string, string] }`;

interface Todo {
  title?: string;
  done?: boolean;
}

interface Payload {
  id?: string;
  title?: string;
  topic?: string;
  subtopic?: string;
  titles?: string[];
  todos?: (Todo | string)[];
}

// What the app shows the template for. Quota, no key, a bad reply and a
// quest with no name all land here — the client treats a null summary as
// "no brief", never as an error.
const EMPTY = { summary: null, steps: [] as string[] };

const clamp = (value: unknown, max = MAX_FIELD): string =>
  typeof value === "string" ? value.trim().slice(0, max).trim() : "";

const cleanStep = (value: unknown): string =>
  clamp(value, MAX_STEP + 20).replace(/^[-•*·\d.)\s]+/, "").trim();

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return json({}, 200);
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const authorization = req.headers.get("Authorization") ?? "";

  let payload: Payload;
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }

  const title = clamp(payload.title);
  if (!title) return json(EMPTY);

  if (!await consumeQuota(authorization, DAILY_LIMIT)) {
    return json(EMPTY);
  }

  const topic = clamp(payload.topic);
  const subtopic = clamp(payload.subtopic);
  const titles = (payload.titles ?? []).slice(0, MAX_TITLES).map((t) => clamp(t)).filter(Boolean);
  const todos = (payload.todos ?? []).slice(0, MAX_TODOS).flatMap((row) => {
    const text = typeof row === "string" ? clamp(row) : clamp(row?.title);
    if (!text) return [];
    const done = typeof row === "object" && row?.done === true;
    return [`${done ? "[done]" : "[ ]"} ${text}`];
  });

  const facts = [
    `Quest: ${title}`,
    topic ? `Topic: ${topic}${subtopic ? ` › ${subtopic}` : ""}` : null,
    titles.length
      ? `Links on it (${titles.length}):\n- ${titles.join("\n- ")}`
      : "Links on it: none yet",
    todos.length ? `Steps so far:\n- ${todos.join("\n- ")}` : "Steps so far: none",
  ].filter(Boolean).join("\n");

  try {
    const parsed = await completeJSON(SYSTEM, facts, 400) as {
      summary?: unknown;
      steps?: unknown;
    } | null;

    const summary = clamp(parsed?.summary, MAX_SUMMARY);
    if (!summary) return json(EMPTY);

    const seen = new Set<string>();
    const steps: string[] = [];
    for (const raw of Array.isArray(parsed?.steps) ? parsed.steps : []) {
      const step = cleanStep(raw);
      if (!step || step.length > MAX_STEP) continue;
      const key = step.toLowerCase();
      if (seen.has(key)) continue;
      seen.add(key);
      steps.push(step);
      if (steps.length === MAX_STEPS) break;
    }

    return json({ summary, steps });
  } catch (error) {
    console.error("quest-brief failed", error);
    return json(EMPTY);
  }
});
