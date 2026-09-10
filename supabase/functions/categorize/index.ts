// bookmarker — AI categorisation via OpenRouter (Claude Sonnet 5).
//
// The key is OPENROUTER_API_KEY on the function. It never ships in the app.
//
// Second-pass filing for the links the offline keyword pass could not place
// or placed on thin evidence. The model gets everything the page said about
// the one link — title, author, caption, description, hashtags — and returns
// a topic with a confidence. Low confidence is dropped here, before the app
// sees it: "not filed" beats wrong, and a reel about hips filed under
// Relationships because its caption opened with "I'm not a relationship
// expert" is the exact failure this exists to stop.

import { TAXONOMY, TOPIC_IDS } from "./taxonomy.ts";
import { completeJSON, consumeQuota, json } from "../_shared/openrouter.ts";

const DAILY_LIMIT = 200;
const MAX_TITLE = 300;
const MAX_BODY = 1200;      // text + description together
const MAX_SHORT = 120;      // author, url
const MAX_HASHTAGS = 15;
const MAX_TAGS = 10;
const TEMPERATURE = 0.2;

const SYSTEM = `You file saved links into a fixed taxonomy.

The user saved a link from a social app or the web. You get its URL, title,
and sometimes the author, a caption, a description, the post's hashtags, and
tags the user typed. Choose where it belongs, and say how sure you are.

How to read a post:
- Judge the SUBJECT of the post, not its opening sentence. Captions open with a
  hook that sells the post ("I'm not a relationship expert but…", "nobody tells
  you this about money…"); the subject is what the rest of the caption, the
  hashtags and the author's field are actually about.
- Hashtags are the author's own filing of the post. They outweigh the first
  clause of the caption. #mobility #flatfeet on a reel means it is about
  mobility and feet, whatever the hook says.
- The author's name and bio are a hint to the subject ("The Mobility
  Framework", "Longevity Lab"), never the subject on their own.
- A word that happens to match a subtopic name ("communication", "space",
  "training") is not evidence unless the post is about that thing.
- Judge the subject matter, not the format (a reel about running is Fitness,
  not Creator).

Rules:
- topic MUST be one of the ids below, exactly as written, or null.
- subtopic MUST be one of that topic's listed subtopics, exactly as written, or
  null if none of them fit the link.
- confidence is "high" when a person who read the post would agree without
  hesitation; "medium" when the topic is probably right but you are working
  from a hint (a bio, one hashtag, a hook with little else); "low" when you
  are guessing. When confidence is low, topic and subtopic MUST be null — not
  filed beats filed wrong.
- Return null for topic when the link genuinely doesn't fit anywhere, or when
  you have too little to go on (a bare URL, a login-wall title like
  "Instagram", a caption that says nothing).
- tags: 2 to 4 short lowercase keywords about the subject. No hashes, no
  platform names. Empty when topic is null.
- reason: one short sentence, under 100 characters, saying what decided it.

Return JSON:
{ "topic": string|null, "subtopic": string|null, "tags": string[],
  "confidence": "high"|"medium"|"low", "reason": string }

Examples:

URL: https://www.instagram.com/reel/DBxHipReel/
Title: Sophie Rinkenbach | The Mobility Framework on Instagram: "I'm not a relationship expert but I do know a thing or two about hips, whi…"
Author: Sophie Rinkenbach | The Mobility Framework
→ { "topic": "fitness", "subtopic": "Mobility", "tags": ["hips", "mobility", "hip flexors"], "confidence": "high", "reason": "The hook is about relationships; the post is about hips, from a mobility coach." }

URL: https://www.instagram.com/reel/DBxFootReel/
Title: Gabby Q on Instagram: "Years ago, when I first started training my feet, I couldn't move my toes at all…"
Author: zachtrained
Description: Your feet weren't designed to be passengers. These exercises build toe strength, foot control and the muscles that support your arch from the ground up. #flatfeet #mobility #footarch #feet
Hashtags: flatfeet, mobility, footarch, feet
→ { "topic": "fitness", "subtopic": "Mobility", "tags": ["feet", "flat feet", "toe strength", "arch"], "confidence": "high", "reason": "Foot exercises; the author's hashtags say mobility and flat feet." }

URL: https://www.instagram.com/reel/DBxBread/
Title: Marco Bakes on Instagram: "Nobody tells you this about money. Sourdough needs 24 hours, not 4. #sourdough #baking"
Hashtags: sourdough, baking
→ { "topic": "recipes", "subtopic": "Baking", "tags": ["sourdough", "bread", "proofing"], "confidence": "high", "reason": "The money line is a hook; the post and its hashtags are about sourdough." }

URL: https://www.instagram.com/reel/DBxLongevity/
Title: Dr Rhonda | Longevity Lab on Instagram: "This one changed how I think about my 40s"
Author: Dr Rhonda | Longevity Lab
→ { "topic": "health", "subtopic": "Longevity", "tags": ["longevity", "ageing"], "confidence": "medium", "reason": "Only the bio says longevity; the caption says nothing about the subject." }

URL: https://www.instagram.com/reel/C9xyz123/
Title: Instagram
→ { "topic": null, "subtopic": null, "tags": [], "confidence": "low", "reason": "A login-wall title and a bare URL say nothing about the post." }

URL: https://x.com/someone/status/1
Text: This is your sign.
→ { "topic": null, "subtopic": null, "tags": [], "confidence": "low", "reason": "A four-word hook with no subject." }

TAXONOMY (id (display name): subtopics)
${TAXONOMY}`;

interface Payload {
  url?: string;
  title?: string;
  author?: string;
  text?: string;
  description?: string;
  hashtags?: string[];
  tags?: string[];
  platform?: string;
}

type Confidence = "high" | "medium" | "low";

const empty = () => json({ topic: null, subtopic: null, tags: [], confidence: "low", reason: null });

const clamp = (value: unknown, max: number): string =>
  typeof value === "string" ? value.slice(0, max).trim() : "";

const words = (value: unknown, max: number): string[] =>
  Array.isArray(value)
    ? value.filter((t): t is string => typeof t === "string")
      .map((t) => t.replace(/^#/, "").trim().toLowerCase())
      .filter((t) => t.length > 1 && t.length < 40)
      .slice(0, max)
    : [];

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

  const url = clamp(payload.url, MAX_SHORT * 4);
  const title = clamp(payload.title, MAX_TITLE);
  if (!url && !title) return json({ error: "url or title required" }, 400);

  if (!await consumeQuota(authorization, DAILY_LIMIT)) {
    console.warn("quota denied or unavailable");
    return empty();
  }

  // Text and description share one budget; the post body comes first because
  // on X it *is* the post, and the description gets whatever is left.
  const text = clamp(payload.text, MAX_BODY);
  const description = clamp(payload.description, Math.max(0, MAX_BODY - text.length));
  const hashtags = words(payload.hashtags, MAX_HASHTAGS);
  const userTags = words(payload.tags, MAX_TAGS);

  const facts = [
    `URL: ${url}`,
    payload.platform ? `Platform: ${clamp(payload.platform, 20)}` : null,
    title ? `Title: ${title}` : null,
    payload.author ? `Author: ${clamp(payload.author, MAX_SHORT)}` : null,
    text ? `Text: ${text}` : null,
    description ? `Description: ${description}` : null,
    hashtags.length ? `Hashtags: ${hashtags.join(", ")}` : null,
    userTags.length ? `User tags: ${userTags.join(", ")}` : null,
  ].filter(Boolean).join("\n");

  try {
    const parsed = await completeJSON(SYSTEM, facts, 400, TEMPERATURE) as {
      topic?: unknown;
      subtopic?: unknown;
      tags?: unknown;
      confidence?: unknown;
      reason?: unknown;
    } | null;
    if (!parsed) return empty();

    const confidence: Confidence =
      parsed.confidence === "high" || parsed.confidence === "medium" ? parsed.confidence : "low";
    // Low means the model was guessing. Drop the topic here so no client ever
    // has to decide whether to trust a guess.
    const topic = confidence !== "low" && typeof parsed.topic === "string" && TOPIC_IDS.has(parsed.topic)
      ? parsed.topic
      : null;

    return json({
      topic,
      subtopic: topic && typeof parsed.subtopic === "string" ? parsed.subtopic : null,
      tags: topic && Array.isArray(parsed.tags)
        ? parsed.tags
          .filter((t: unknown): t is string => typeof t === "string")
          .map((t: string) => t.toLowerCase().replace(/[^a-z0-9 -]/g, "").trim())
          .filter((t: string) => t.length > 1 && t.length < 24)
          .slice(0, 4)
        : [],
      confidence: topic ? confidence : "low",
      reason: typeof parsed.reason === "string" ? parsed.reason.slice(0, 160) : null,
    });
  } catch (error) {
    console.error("categorise failed", error);
    return empty();
  }
});
