// Shared OpenRouter caller. The key lives in the function environment —
// never in the iOS binary. Model is Claude Sonnet 5 as requested.

export const MODEL = "anthropic/claude-sonnet-5";

export async function completeJSON(
  system: string,
  user: string,
  maxTokens = 700,
): Promise<unknown | null> {
  const apiKey = Deno.env.get("OPENROUTER_API_KEY");
  if (!apiKey) {
    console.error("OPENROUTER_API_KEY is not set");
    return null;
  }

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
      temperature: 0.4,
      max_tokens: maxTokens,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: `${system}\n\nReply with a single JSON object only.` },
        { role: "user", content: user },
      ],
    }),
  });

  if (!response.ok) {
    console.error("openrouter", response.status, await response.text());
    return null;
  }

  const payload = await response.json();
  const text = payload?.choices?.[0]?.message?.content;
  if (typeof text !== "string" || text.trim().length === 0) return null;

  const cleaned = text.replace(/^```json\s*/i, "").replace(/```$/i, "").trim();
  try {
    return JSON.parse(cleaned);
  } catch {
    console.error("openrouter json parse failed");
    return null;
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
