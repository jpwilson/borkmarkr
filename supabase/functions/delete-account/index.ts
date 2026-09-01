// bookmarker — delete the signed-in user's account.
//
// A client must never hold the service role, so the only way to remove a row
// from auth.users is here. The gateway has already checked the JWT
// (verify_jwt), and we resolve the user from that same token rather than
// trusting anything in the body — the caller can only ever delete themself.
//
// Postgres does the rest: auth.users → profiles → bookmarks, collections,
// grants, and ai_usage all cascade.

// The web app's You page calls this from bookmarker.lol, so the browser's
// preflight must be answered before the gateway's JWT check gates the POST.
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    },
  });

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return json({}, 200);
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const base = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!base || !anonKey || !serviceKey) {
    console.error("missing SUPABASE_* environment");
    return json({ error: "Server misconfigured" }, 500);
  }

  const authorization = req.headers.get("Authorization") ?? "";
  if (!/^Bearer\s+\S+/i.test(authorization)) return json({ error: "Sign in first" }, 401);

  // Who is asking? The token says — nothing else is consulted.
  const who = await fetch(`${base}/auth/v1/user`, {
    headers: { apikey: anonKey, Authorization: authorization },
  });
  if (!who.ok) return json({ error: "Sign in first" }, 401);
  const user = await who.json() as { id?: string };
  if (typeof user.id !== "string" || user.id.length === 0) {
    return json({ error: "Sign in first" }, 401);
  }

  const gone = await fetch(`${base}/auth/v1/admin/users/${user.id}`, {
    method: "DELETE",
    headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
  });
  if (!gone.ok) {
    console.error("delete failed", gone.status, await gone.text());
    return json({ error: "Couldn't delete the account. Try again." }, 502);
  }

  return json({ ok: true });
});
