// Shared OpenRouter caller. The key lives in the function environment —
// never in the iOS binary. Model is Claude Sonnet 5 as requested.
//
// Every call is traced to Langfuse under the feature that made it, which is
// why `feature` comes first and is required (see langfuse.ts). Without the
// LANGFUSE_* keys the tracing is a no-op.

import { Generation } from "./langfuse.ts";

export const MODEL = "anthropic/claude-sonnet-5";

export async function completeJSON(
  feature: string,
  system: string,
  user: string,
  maxTokens = 700,
  temperature = 0.4,
): Promise<unknown | null> {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) {
    console.error("OPENROUTER_API_KEY is not set");
    return null;
  }

  const messages = [
    { role: "system", content: `${system}\n\nReply with a single JSON object only.` },
    { role: "user", content: user },
  ];
  const generation = new Generation(feature, MODEL, messages, { temperature, max_tokens: maxTokens });
  try {
    const response = await fetch("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
        "HTTP-Referer": "https://bookmarker.lol/",
        "X-Title": "bookmarker",
      },
      body: JSON.stringify({
        model: MODEL,
        temperature,
        max_tokens: maxTokens,
        response_format: { type: "json_object" },
        messages,
      }),
    });

    if (!response.ok) {
      const detail = await response.text();
      console.error("openrouter", response.status, detail);
      generation.error = `openrouter ${response.status}: ${detail.slice(0, 300)}`;
      return null;
    }

    const payload = await response.json();
    generation.usage = payload?.usage;
    // "length" here is the usual reason a reply won't parse: maxTokens ran out.
    const finish = payload?.choices?.[0]?.finish_reason ?? "unknown";
    const text = payload?.choices?.[0]?.message?.content;
    generation.output = text;
    if (typeof text !== "string" || text.trim().length === 0) {
      generation.error = `empty reply (finish_reason ${finish})`;
      return null;
    }

    const cleaned = text.replace(/^```json\s*/i, "").replace(/```$/i, "").trim();
    try {
      return JSON.parse(cleaned);
    } catch {
      // Models still sometimes wrap the object in a sentence despite
      // `response_format`. Take the outermost braces before giving up.
      const first = cleaned.indexOf("{"), last = cleaned.lastIndexOf("}");
      if (first >= 0 && last > first) {
        try { return JSON.parse(cleaned.slice(first, last + 1)); } catch { /* fall through */ }
      }
      console.error("openrouter json parse failed", cleaned.slice(0, 120));
      generation.error = `reply was not JSON (finish_reason ${finish})`;
      return null;
    }
  } catch (error) {
    // A network failure still reaches the caller exactly as it always has.
    generation.error = error instanceof Error ? error.message : String(error);
    throw error;
  } finally {
    generation.end();
  }
}

// The web app calls these from bookmarker.lol, so the browser's preflight
// must be answered; the JWT check at the gateway still gates the real call.
export const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    },
  });

export async function consumeQuota(authorization: string, dailyLimit: number): Promise<boolean> {
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
        body: JSON.stringify({ daily_limit: dailyLimit }),
      },
    );
    return allowed.ok && (await allowed.json()) === true;
  } catch (error) {
    console.error("quota check failed", error);
    return false;
  }
}
