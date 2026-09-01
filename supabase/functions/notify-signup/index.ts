// bookmarker — email JP when someone joins the beta or reserves the
// founders price. Fired by a database trigger (pg_net) on beta_signups,
// authenticated by a shared token rather than a JWT because Postgres is the
// caller. Sends through Resend using RESEND_API_KEY.

const TOKEN = "bork-notify-8253";
const TO = "jeanpaulwilson@gmail.com";

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });
  if (req.headers.get("x-notify-token") !== TOKEN) return new Response("no", { status: 401 });

  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return new Response(JSON.stringify({ error: "no key" }), { status: 500 });

  let body: { email?: string; source?: string; at?: string };
  try { body = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  const email = String(body.email ?? "?").slice(0, 200);
  const source = String(body.source ?? "?").slice(0, 60);
  const label = source === "lifetime30" ? "💰 LIFETIME ($30 reserved)" : `📥 ${source}`;

  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({
      from: "bookmarker <hello@bookmarker.lol>",
      to: [TO],
      subject: `${label} — ${email}`,
      text: `New signup on bookmarker.lol\n\nEmail:  ${email}\nSource: ${source}\nWhen:   ${body.at ?? new Date().toISOString()}\n\n— the notify-signup function`,
    }),
  });
  const out = await r.text();
  if (!r.ok) {
    console.error("resend", r.status, out.slice(0, 300));
    return new Response(JSON.stringify({ error: "resend failed" }), { status: 502 });
  }
  return new Response(JSON.stringify({ ok: true }), { headers: { "Content-Type": "application/json" } });
});
