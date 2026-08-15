// borkmarkr — name a side quest from a pile of saved titles.
//
// Same reason this is a function and not an iOS call: the key must not live
// in the binary. Authenticate with the user's JWT; charge the same daily
// quota as categorise. One request names a whole batch of suggestions.

import Anthropic from "npm:@anthropic-ai/sdk";

const MODEL = "claude-haiku-4-5";
const DAILY_LIMIT = 200;
const MAX_FIELD = 160;

const SYSTEM = `You name SIDE QUESTS for a bookmark library.

A side quest is why someone kept a pile of links — become something, decide something, or go down a rabbit hole. It is NOT a category name.

Never write "Get into X". Nobody says that.

Good:
- Improve mobility for running
- Marketing on socials
- Go down the rabbit hole
- Explore starting a business
- Undo the desk stiffness
- Learn pottery

Bad:
- Get into conspiracies
- Get into startups
- Get into social strategy
- Fitness
- Beliefs

Rules:
- 2 to 7 words.
- Sounds like something you'd say out loud.
- Read the titles to find the actual activity (running vs football, pottery vs painting).
- Return one title per cluster, same id you were given.
- No quotes, no emoji, no hashtags.`;

const SCHEMA = {
  type: "object",
  properties: {
    names: {
      type: "array",
      items: {
        type: "object",
        properties: {
          id: { type: "string" },
          title: { type: "string" },
        },
        required: ["id", "title"],
        additionalProperties: false,
      },
    },
  },
  required: ["names"],
  additionalProperties: false,
};

interface Cluster {
  id?: string;
  topic?: string;
  subtopic?: string;
  titles?: string[];
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

const clamp = (value: unknown): string =>
  typeof value === "string" ? value.slice(0, MAX_FIELD).trim() : "";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    console.error("ANTHROPIC_API_KEY is not set");
    return json({ names: [] });
  }

  const authorization = req.headers.get("Authorization") ?? "";

  let payload: { clusters?: Cluster[] };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }

  const clusters = (payload.clusters ?? []).slice(0, 5);
  if (clusters.length === 0) return json({ names: [] });

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
      return json({ names: [] });
    }
  } catch (error) {
    console.error("quota check failed", error);
    return json({ names: [] });
  }

  const facts = clusters.map((cluster, i) => {
    const titles = (cluster.titles ?? []).slice(0, 6).map(clamp).filter(Boolean);
    return [
      `Cluster ${i + 1} id=${clamp(cluster.id)}`,
      `Topic: ${clamp(cluster.topic)}`,
      cluster.subtopic ? `Subtopic: ${clamp(cluster.subtopic)}` : null,
      titles.length ? `Titles:\n- ${titles.join("\n- ")}` : null,
    ].filter(Boolean).join("\n");
  }).join("\n\n");

  try {
    const client = new Anthropic({ apiKey });
    const response = await client.messages.create({
      model: MODEL,
      max_tokens: 250,
      system: SYSTEM,
      output_config: { format: { type: "json_schema", schema: SCHEMA } },
      messages: [{ role: "user", content: facts }],
    });

    if (response.stop_reason === "refusal") return json({ names: [] });

    const text = response.content.find((b) => b.type === "text")?.text ?? "";
    const parsed = JSON.parse(text);
    const names = Array.isArray(parsed.names)
      ? parsed.names
        .filter((row: { id?: unknown; title?: unknown }) =>
          typeof row?.id === "string" && typeof row?.title === "string"
        )
        .map((row: { id: string; title: string }) => ({
          id: row.id.slice(0, 80),
          title: row.title.replace(/^get into\s+/i, "").slice(0, 48).trim(),
        }))
        .filter((row: { title: string }) => row.title.length >= 4)
      : [];

    return json({ names });
  } catch (error) {
    console.error("name-quest failed", error);
    return json({ names: [] });
  }
});
