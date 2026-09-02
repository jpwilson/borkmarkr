// bookmarker — email JP when something happens that a person should see:
// someone joins the beta / reserves the founders price, or sends feedback
// from the Help tab. Fired by database triggers (pg_net) on beta_signups and
// feedback, authenticated by a shared token rather than a JWT because
// Postgres is the caller. The token lives in NOTIFY_TOKEN (and in Vault for
// the trigger side) — never in code. Sends through Resend.

const TO = "jeanpaulwilson@gmail.com";
const FROM = "bookmarker <hello@bookmarker.lol>";

interface Body {
  kind?: string;
  // signup
  email?: string;
  source?: string;
  // feedback
  feedback_kind?: string;
  message?: string;
  contact?: string | null;
  user_id?: string | null;
  context?: string | null;
  at?: string;
}

const str = (v: unknown, max: number): string => (typeof v === "string" ? v : "").slice(0, max);

function signupMail(b: Body) {
  const email = str(b.email, 200) || "?";
  const source = str(b.source, 60) || "?";
  const label = source === "lifetime30" ? "💰 LIFETIME ($30 reserved)" : `📥 ${source}`;
  return {
    subject: `${label} — ${email}`,
    text: `New signup on bookmarker.lol\n\nEmail:  ${email}\nSource: ${source}\nWhen:   ${b.at ?? new Date().toISOString()}\n\n— the notify function`,
  };
}

function feedbackMail(b: Body) {
  const kind = str(b.feedback_kind, 20) || "other";
  const icon = kind === "problem" ? "🐛" : kind === "idea" ? "💡" : "💬";
  const contact = str(b.contact, 200);
  const uid = str(b.user_id, 40);
  const from = contact || (uid ? `user ${uid.slice(0, 8)}…` : "anonymous");
  return {
    subject: `${icon} ${kind} — ${from}`,
    text: [
      `Feedback from the web app (${kind})`,
      ``,
      str(b.message, 2000),
      ``,
      `From:  ${contact || "(no contact)"}${uid ? `  · user ${uid}` : ""}`,
      `Where: ${str(b.context, 160) || "?"}`,
      `When:  ${b.at ?? new Date().toISOString()}`,
      ``,
      `— the notify function`,
    ].join("\n"),
    reply_to: contact || undefined,
  };
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });
  const token = Deno.env.get("NOTIFY_TOKEN");
  if (!token) return new Response(JSON.stringify({ error: "no token" }), { status: 500 });
  if (req.headers.get("x-notify-token") !== token) return new Response("no", { status: 401 });

  const key = Deno.env.get("RESEND_API_KEY");
  if (!key) return new Response(JSON.stringify({ error: "no key" }), { status: 500 });

  let body: Body;
  try { body = await req.json(); } catch { return new Response("bad json", { status: 400 }); }
  const mail = body.kind === "feedback" ? feedbackMail(body) : signupMail(body);

  const r = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json" },
    body: JSON.stringify({ from: FROM, to: [TO], ...mail }),
  });
  const out = await r.text();
  if (!r.ok) {
    console.error("resend", r.status, out.slice(0, 300));
    return new Response(JSON.stringify({ error: "resend failed" }), { status: 502 });
  }
  return new Response(JSON.stringify({ ok: true }), { headers: { "Content-Type": "application/json" } });
});
