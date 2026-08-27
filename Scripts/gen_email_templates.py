#!/usr/bin/env python3
"""Generate the Supabase Auth email templates from one shared layout.

    python3 Scripts/gen_email_templates.py            # writes supabase/templates/*.html
    python3 Scripts/gen_email_templates.py --preview  # also writes previews with sample values

Paste each file's contents as the BODY of the matching template in
Supabase → Authentication → Emails → Templates. Subjects are in SUBJECTS.
Images are served from bookmarker.lol, so they render in any mail client.
No viewport meta on purpose: Supabase's mailer sends the body without
quoted-printable escaping, so "=de" in "width=device-width" arrives mangled.
"""
import sys, pathlib, re

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "supabase" / "templates"
SITE = "https://bookmarker.lol"

FONT = "-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif"
MONO = "'SF Mono',SFMono-Regular,Menlo,Consolas,'Liberation Mono',monospace"

PAPER, INK, INK2, HAIR, CORAL, CORAL_TEXT = "#F6F3EE", "#191510", "#6E655A", "#EAE4DA", "#FF5A2D", "#C93A12"

def code_block(token="{{ .Token }}"):
    return f"""
              <tr><td style="padding:6px 0 22px 0;">
                <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
                  <tr><td align="center" style="background:{PAPER};border-radius:16px;padding:22px 12px;font:700 40px/1 {MONO};color:{INK};letter-spacing:10px;">{token}</td></tr>
                </table>
              </td></tr>"""

def button(label, href):
    return f"""
              <tr><td style="padding:6px 0 22px 0;">
                <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                  <tr><td style="background:{INK};border-radius:14px;">
                    <a href="{href}" style="display:inline-block;padding:15px 24px;font:600 16px/1 {FONT};color:#ffffff;text-decoration:none;">{label}</a>
                  </td></tr>
                </table>
              </td></tr>"""

def screens(caption):
    imgs = "".join(
        f'<td style="padding:0 6px;"><img src="{SITE}/img/{n}.png" width="136" height="296" alt="{a}" style="display:block;width:136px;height:296px;border-radius:18px;border:1px solid {HAIR};" /></td>'
        for n, a in (("browse", "Browse by topic"), ("library", "Your library"), ("search", "Search everything you saved"))
    )
    return f"""
        <tr><td style="padding:28px 0 0 0;">
          <table role="presentation" cellspacing="0" cellpadding="0" border="0" align="center"><tr>{imgs}</tr></table>
          <p style="margin:14px 0 0 0;text-align:center;font:400 13px/1.5 {FONT};color:{INK2};">{caption}</p>
        </td></tr>"""

def layout(*, preheader, eyebrow, headline, sub, middle, note, screens_caption=None):
    strip = screens(screens_caption) if screens_caption else ""
    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="color-scheme" content="light">
<title>{headline}</title>
</head>
<body style="margin:0;padding:0;background:{PAPER};">
<div style="display:none;max-height:0;overflow:hidden;font-size:1px;line-height:1px;color:{PAPER};">{preheader}&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;&nbsp;&zwnj;</div>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background:{PAPER};">
  <tr>
    <td align="center" style="padding:36px 16px 44px 16px;">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:480px;">

        <tr><td style="padding:0 4px 18px 4px;">
          <table role="presentation" cellspacing="0" cellpadding="0" border="0"><tr>
            <td style="width:44px;"><img src="{SITE}/img/mark-192.png" width="44" height="44" alt="" style="display:block;width:44px;height:44px;border-radius:12px;" /></td>
            <td style="padding-left:12px;font:700 19px/1 {FONT};color:{INK};letter-spacing:-0.02em;">borkmarkr</td>
          </tr></table>
        </td></tr>

        <tr><td style="background:#ffffff;border:1px solid {HAIR};border-radius:24px;padding:34px 32px 30px 32px;">
          <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0">
            <tr><td style="padding:0 0 10px 0;font:700 12px/1 {FONT};color:{CORAL_TEXT};letter-spacing:0.12em;text-transform:uppercase;">{eyebrow}</td></tr>
            <tr><td style="padding:0 0 10px 0;font:800 30px/1.15 {FONT};color:{INK};letter-spacing:-0.025em;">{headline}</td></tr>
            <tr><td style="padding:0 0 22px 0;font:400 16px/1.55 {FONT};color:{INK2};">{sub}</td></tr>{middle}
            <tr><td style="font:400 13px/1.55 {FONT};color:{INK2};">{note}</td></tr>
          </table>
        </td></tr>
{strip}
        <tr><td style="padding:26px 8px 0 8px;font:400 12px/1.6 {FONT};color:#A39A8D;">
          <a href="{SITE}" style="color:#A39A8D;text-decoration:none;font-weight:600;">bookmarker.lol</a>
          &nbsp;&middot;&nbsp; <a href="{SITE}/privacy" style="color:#A39A8D;">Privacy</a><br>
          You're getting this because this address was entered in the borkmarkr app. If that wasn't you, nothing happens &mdash; just ignore it.
        </td></tr>

      </table>
    </td>
  </tr>
</table>
</body>
</html>
"""

SUBJECTS = {
    "confirm-signup":   "Your borkmarkr code",
    "magic-link":       "Your borkmarkr code",
    "change-email":     "Confirm your new borkmarkr email",
    "reauthentication": "Your borkmarkr confirmation code",
    "reset-password":   "borkmarkr has no passwords — here's what to do",
    "invite":           "You're invited to borkmarkr",
}

TEMPLATES = {
    "confirm-signup": dict(
        preheader="Your sign-in code is {{ .Token }}",
        eyebrow="Welcome to the library",
        headline="Your code&rsquo;s here.",
        sub="Type it into the app and your borks get a home &mdash; one that survives lost phones, new phones and everything in between.",
        middle=code_block(),
        note="Good for an hour. Didn&rsquo;t ask for it? Ignore this email &mdash; nothing happens without the code.",
        screens_caption="Everything you save on Instagram, X, TikTok and YouTube. One library. Actually searchable.",
    ),
    "magic-link": dict(
        preheader="Your sign-in code is {{ .Token }}",
        eyebrow="Welcome back",
        headline="Your code&rsquo;s here.",
        sub="Your library is exactly where you left it. Type this in and you&rsquo;re back.",
        middle=code_block(),
        note="Good for an hour. Didn&rsquo;t ask for it? Ignore this email &mdash; nothing happens without the code.",
        screens_caption="Browse by topic, or by the app it came from. Find it again in seconds.",
    ),
    "change-email": dict(
        preheader="Your confirmation code is {{ .Token }}",
        eyebrow="Change of address",
        headline="Confirm your new email.",
        sub="You asked to move your borkmarkr account to <strong style=\"color:#191510;\">{{ .NewEmail }}</strong>. Enter this code in the app to make it official.",
        middle=code_block(),
        note="If this wasn&rsquo;t you, don&rsquo;t enter the code &mdash; your account stays exactly as it is.",
    ),
    "reauthentication": dict(
        preheader="Your confirmation code is {{ .Token }}",
        eyebrow="Quick check",
        headline="Just making sure it&rsquo;s you.",
        sub="Enter this code in the app to confirm the change you&rsquo;re making.",
        middle=code_block(),
        note="Good for a few minutes. If you weren&rsquo;t changing anything, ignore this and nothing happens.",
    ),
    "reset-password": dict(
        preheader="borkmarkr doesn't use passwords — here's how to get back in",
        eyebrow="About that password",
        headline="There isn&rsquo;t one.",
        sub="borkmarkr never had passwords, so there&rsquo;s nothing to reset. Open the app, type your email, and we&rsquo;ll send you a fresh six-digit code. That&rsquo;s the whole login.",
        middle=button("Open borkmarkr", f"{SITE}/app"),
        note="If you didn&rsquo;t request this, you can ignore it.",
    ),
    "invite": dict(
        preheader="Someone saved you a seat in borkmarkr",
        eyebrow="You&rsquo;re invited",
        headline="Someone saved you a seat.",
        sub="You&rsquo;ve been invited to borkmarkr &mdash; one library for everything you save on Instagram, X, TikTok and YouTube, filed automatically and actually searchable.",
        middle=button("Accept the invite", "{{ .ConfirmationURL }}"),
        note="The link is for you only and expires after a while. If you weren&rsquo;t expecting an invite, ignore this.",
        screens_caption="Save from any app. It files itself. Find it again.",
    ),
}

SAMPLE = {"{{ .Token }}": "482913", "{{ .NewEmail }}": "you@example.com", "{{ .ConfirmationURL }}": SITE, "{{ .Email }}": "old@example.com", "{{ .SiteURL }}": SITE}

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    preview = "--preview" in sys.argv
    pdir = pathlib.Path(sys.argv[sys.argv.index("--preview") + 1]) if preview and len(sys.argv) > sys.argv.index("--preview") + 1 else OUT / "_preview"
    if preview: pdir.mkdir(parents=True, exist_ok=True)
    for name, spec in TEMPLATES.items():
        html = layout(**spec)
        (OUT / f"{name}.html").write_text(html)
        if preview:
            p = html
            for k, v in SAMPLE.items(): p = p.replace(k, v)
            (pdir / f"{name}.html").write_text(p)
        print(f"{name:18s} {len(html):6d} bytes  subject: {SUBJECTS[name]}")

if __name__ == "__main__":
    main()
