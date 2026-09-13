import { completeJSON, consumeQuota, json } from "../_shared/openrouter.ts";
import { SYSTEM, shape, cleanBrief } from "../_shared/quest-brief.mjs";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return json({}, 200);
  if (req.method !== "POST") return json({ error: "POST only" }, 405);
  let input;
  try { input = shape(await req.json()); }
  catch { return json({ error: "Body must be JSON" }, 400); }
  if (!input) return json({ summary:null, steps:[], reason:"missing_title" }, 400);
  if (!await consumeQuota(req.headers.get("Authorization") ?? "", 200)) {
    return json({ summary:null, steps:[], reason:"quota_or_unavailable" });
  }
  try {
    const parsed = await completeJSON(SYSTEM, JSON.stringify(input), 650);
    const brief = cleanBrief(parsed, input);
    return json(brief ?? { summary:null, steps:[], reason:"unavailable" });
  } catch {
    return json({ summary:null, steps:[], reason:"unavailable" });
  }
});
