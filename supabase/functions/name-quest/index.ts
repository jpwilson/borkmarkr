// borkmarkr — name a side quest. Claude Sonnet 5 via OpenRouter.

import { completeJSON, consumeQuota, json } from "../_shared/openrouter.ts";

const DAILY_LIMIT = 200;
const MAX_FIELD = 160;

const SYSTEM = `You name SIDE QUESTS for a bookmark library.

A side quest is why someone kept a pile of links — become something, decide something, or go down a rabbit hole. It is NOT a category name.

Never write "Get into X". Nobody says that.

Good: Improve mobility for running; Marketing on socials; Go down the rabbit hole.
Bad: Get into conspiracies; Fitness; Beliefs.

Rules: 2 to 7 words. Sounds spoken. Infer the activity from the titles.
Return JSON: { "names": [ { "id": string, "title": string } ] }`;

interface Cluster {
  id?: string;
  topic?: string;
  subtopic?: string;
  titles?: string[];
}

const clamp = (value: unknown): string =>
  typeof value === "string" ? value.slice(0, MAX_FIELD).trim() : "";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const authorization = req.headers.get("Authorization") ?? "";

  let payload: { clusters?: Cluster[] };
  try {
    payload = await req.json();
  } catch {
    return json({ error: "Body must be JSON" }, 400);
  }

  const clusters = (payload.clusters ?? []).slice(0, 5);
  if (clusters.length === 0) return json({ names: [] });

  if (!await consumeQuota(authorization, DAILY_LIMIT)) {
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
    const parsed = await completeJSON(SYSTEM, facts, 350) as { names?: unknown } | null;
    const names = Array.isArray(parsed?.names)
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
