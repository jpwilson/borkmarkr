# App Store Connect — copy-paste

Every field below is filled in and ready. Nothing here claims a feature that
isn't in the build — a reviewer opens the app and checks, and an unbackable
claim is the most common avoidable rejection.

---

## App Information

**Name** (30 char max)
```
borkmarkr
```

**Subtitle** (30 char max — this is the line under the name in search)
```
All your links, in one place
```
*(28 chars. Alternative if you prefer the source emphasis: `Save links from every app`.)*

**Category** · Primary: `Productivity` · Secondary: `Utilities`

**Support URL**
```
https://jpwilson.github.io/borkmarkr/
```

**Marketing URL**
```
https://jpwilson.github.io/borkmarkr/
```

**Privacy Policy URL**
```
https://jpwilson.github.io/borkmarkr/privacy.html
```

---

## Promotional Text (170 char max — editable any time without a new build)

```
Everything you save on Instagram, X, TikTok and YouTube ends up in one library you can actually search. Save from any app's share sheet. Works offline.
```

---

## Description

```
You save things everywhere. A reel on Instagram, a thread on X, a clip on TikTok, a video on YouTube. Then you never find any of it again.

Every app has its own saved list. None of them are titled, sorted or searchable. borkmarkr is the one library that sits above all of them.

Put simply: it's a good way to organise all your useful links, from every app, in one place.

SAVE FROM ANYWHERE
Tap Share in any app and pick borkmarkr. The link is saved with its title, the account that posted it and a thumbnail. Or paste a link straight into the app.

IT SORTS ITSELF
Every link is filed into a topic and subtopic automatically — Fitness > Mobility, Recipes > Meal prep, Cars > Detailing. Fifty topics, over six hundred subtopics, and you can add your own. Change anything it gets wrong, or leave it and search instead.

TWO WAYS TO BROWSE
By topic, to see everything you've saved about running no matter where it came from. Or by app, to see everything you kept from TikTok. Each view filters by the other.

FIND IT AGAIN
Search titles, tags, notes, people and links. Related results surface saves that match what you meant, not just the words you typed.

YOUR OWN NOTES
Add a dated note to anything, so you remember why you kept it.

SIDE QUESTS
Working on something — running a marathon, choosing a car, planning a trip? Group the links that help, and add a daily habit if it needs one.

BRING WHAT YOU ALREADY HAVE
Import your browser bookmarks, or your data export from X, Instagram, TikTok or YouTube. Thousands of old saves become a sorted, searchable library in one step.

BUILT TO STAY YOURS
borkmarkr stores links, not content. Opening a save takes you to the original post in the app it came from.

Everything works offline and stays on your device. Sign in with just an email if you want your library backed up and synced — no password to create. No ads. No tracking. No analytics. Your library is nobody's business but yours.
```

---

## Keywords (100 char max, comma separated, no spaces)

```
bookmark,save,links,reels,tiktok,shorts,organize,tags,offline,library,read later,collect,sort
```

---

## App Review Information

**Sign-in required?** → **No** (untick "Sign-in required")

This is the honest answer and it removes the biggest review risk: every feature
works without an account. Sign-in only adds cloud backup.

**Notes**
```
No account is required. Every feature — saving links, automatic sorting, browsing, search, notes, side quests, import — works fully without signing in. Please tap "Not now" if the sign-in screen appears.

WHAT THE APP DOES
borkmarkr is a personal bookmark manager. Users save links they choose to save, from any app, into one searchable library. It stores the URL, a title, and a thumbnail supplied by the page's own Open Graph metadata.

The app does NOT display, embed, host, reproduce or scrape content from any social platform. Opening a saved item calls openURL and hands the user to the original app or website, where the content is viewed as normal. There is no in-app feed of anyone else's content and no login to any third-party service.

HOW TO TEST SAVING
1. Open the app and tap the + button.
2. Paste any link, e.g. https://www.youtube.com/watch?v=dQw4w9WgXcQ
   The title, author and thumbnail are fetched automatically.
3. Tap "Bork it" to save.
4. The item appears in Library. Tap it, then "Open original" to confirm it links out to the source.

TESTING THE SHARE EXTENSION (optional)
In Safari or another app, tap Share, then More, and enable "borkmarkr". Sharing a link saves it directly.

AUTOMATIC FILING AND HIGHLIGHTS
Links are sorted into topics on-device by keyword matching. For links that can't be placed that way, a signed-in user's link URL and title are sent to our server, which asks a language model (Anthropic Claude, accessed via OpenRouter) for a suggested topic. The suggestion is shown to the user and can be changed before saving. A signed-in user can also see a short summary of their recent saves; that sends titles, topics and tags of up to 40 recent items to the same model. Signed-out users get on-device filing only and no summaries. No API key ships in the app; all model calls are made server-side.

TESTING SIGN-IN (optional)
Sign-in uses a six-digit code sent by email — no password. If you wish to test it, use:
  Email: appreview@borkmarkr.app
  Code:  123456
This is a preconfigured review-only account.
```

**Demo account** (fill these in if you leave "Sign-in required" ticked)
- Username: `appreview@borkmarkr.app`
- Password: `123456` (the fixed six-digit code, not a password)

**Contact** — your name, phone, and `jeanpaulwilson@gmail.com`

---

## App Privacy ("nutrition label")

**Do you collect data from this app?** → **Yes**

**Contact Info → Email Address**
- Collected: Yes
- Linked to the user: **Yes**
- Used for tracking: **No**
- Purpose: **App Functionality** only

**User Content → Other User Content** (the links people save)
- Collected: Yes
- Linked to the user: **Yes**
- Used for tracking: **No**
- Purpose: **App Functionality** only

### Automatic filing & highlights — already covered above

The AI features send a signed-in user's link URL/title (filing) or recent
titles, topics and tags (highlights) to a language model via our own server.
The model is Anthropic's Claude, reached through OpenRouter. That's **User
Content, used for App Functionality**, which is exactly what's already ticked —
OpenRouter and Anthropic are service providers acting on our behalf, not
parties we share data *with* in Apple's sense, and none of it is used for
tracking or advertising. So there is nothing extra to tick here.

It does need to be in the privacy policy, and it is: see "Automatic filing" and
"Library highlights" at `docs/privacy.html`.

### Sharing — what to declare, and when

**Today: nothing extra.** The only sharing in the build is iOS's own share
sheet — you tap Share and *you* send a link or a plain-text list somewhere.
That's the user acting through the system, not the app collecting or
transmitting anything, and Apple doesn't ask you to declare it.

**When the friend feed ships, this changes** and both this label and the
privacy policy must be updated on the same day:
- User Content stays *Linked to the user*, but you must also tick that it is
  **shared with other users**.
- The policy needs a paragraph: which links become visible, to whom, that it
  only ever happens when the owner explicitly grants access, and how to revoke.

Worth being precise about what's shared even then: **the link and its title,
not the post**. Someone opening a shared collection gets a list of links that
take them to Instagram or YouTube. No content of anyone's is copied, stored or
republished — which is exactly why this stays a low-risk feature.

**Everything else** → Not Collected. Specifically say **No** to:
Identifiers, Usage Data, Diagnostics, Location, Contacts, Browsing History,
Search History, Purchases, Financial Info, Health, Sensitive Info.

**Tracking** → **No**, the app does not track users. (There is no ad SDK, no
analytics SDK, and no third-party SDK of any kind — the app uses only Apple
frameworks.)

---

## Age Rating

All content questions → **None**. Expected rating **4+**.

One judgement call: the questionnaire asks about *unrestricted web access*.
Answer **Yes** — the app opens saved links in Safari. This does not raise the
rating on its own and answering No would be untrue.

---

## Before you submit — the things only you can do

Supabase project: **bookmarker** (`pcjuxnhqxyfvgagnblzv`) in the
**JPGauntletProjects** organization — not the org that holds EVLineup/OFS.
Dashboard: https://supabase.com/dashboard/project/pcjuxnhqxyfvgagnblzv

**Tonight, in this order:** 1 → 2 → 5 → App Store Connect → Archive → Submit
with *manual release*. Then 3 (SMTP) during review, before you press Release.
4 is optional.

**1. Email templates — REQUIRED (2 minutes)**

The app asks for a six-digit code, but Supabase's default templates send a
*link*. A real user gets an email they can't use. Fix:
Authentication → Emails → Templates. Replace the body of BOTH
**Confirm sign up** and **Magic Link** with:

```html
<h2>Your borkmarkr code</h2>
<p>Enter this code in the app:</p>
<p style="font-size:32px;font-weight:700;letter-spacing:4px">{{ .Token }}</p>
<p>It expires in an hour. If you didn't ask for it, just ignore this email.</p>
```

Subject for both: `Your borkmarkr sign-in code`

**2. Site URL (1 minute)**

Authentication → URL Configuration → Site URL:
```
https://jpwilson.github.io/borkmarkr/
```
The default is `http://localhost:3000` and it leaks into any link Supabase
generates.

**3. Custom SMTP — REQUIRED before *release*, not before *submission***

Supabase's built-in mailer is dev-only: it refuses to deliver to addresses
outside your Supabase team and is capped at a couple of emails per hour. The
reviewer never hits this (the Test OTP below bypasses email), but the first
real user would. Needs a domain you own:

1. Buy **borkmarkr.com** (~$11/yr; Vercel or any registrar).
2. Resend (resend.com, free tier 3,000 emails/month) → Domains → add
   `borkmarkr.com` → add the DNS records it shows → wait for "Verified".
3. Resend → API Keys → create one (sending only).
4. Supabase → Authentication → SMTP Settings → enable custom SMTP:
   - Sender email: `hello@borkmarkr.com` · Sender name: `borkmarkr`
   - Host: `smtp.resend.com` · Port: `465` · Username: `resend`
   - Password: the Resend API key
5. Authentication → Rate Limits → raise "emails per hour" from 30 to
   something sane for launch (e.g. 300).
6. Sign out in the app and sign in with an address that is NOT your Supabase
   login to prove it end-to-end.

In App Store Connect choose **"Manually release this version"** so approval
doesn't put the app live before this is done.

**4. OpenRouter API key** (optional — the app ships fine without it)

All three AI functions (categorize, insights, name-quest) are dark until the
key is set. Edge Functions → Secrets, or:
```
supabase secrets set OPENROUTER_API_KEY=sk-or-...
```
Get the key at openrouter.ai. It never leaves the server — do not put it in
`Config.xcconfig`, the app, or the repo. Until it's set, every save falls back
to on-device filing, which is what signed-out users get anyway.

**5. Review test code** (do it — it makes review independent of email)

Authentication → Sign In / Providers → Email → Test OTPs, add:
```
appreview@borkmarkr.app = 123456
```
That maps one address to one fixed code without weakening sign-in for anyone
else. If you'd rather not, delete the "TESTING SIGN-IN" paragraph from the
review notes — "no account required" already covers the requirement.

**6. Submission day**

The free tier auto-pauses the project after about a week idle. Before you
archive, open the dashboard and confirm the project says ACTIVE (it does as of
25 Aug 2026); if paused, Restore and wait ~2 minutes.

---

## Screenshots

Required size: 6.9" iPhone — **1320 × 2868**. The finished files are in
`Marketing/screenshots/` (`01-library.png`, `02-browse.png`, `03-search.png`),
ready to upload as-is: no resizing.

They are *designed* screenshots — a real capture of the app inside a phone
frame on a coloured panel with a headline — which is what nearly every top
listing does and is allowed, because the UI shown is genuine. Apple's rule is
that the screenshots show the app as it actually is; it is not that they must
be raw captures.

**To regenerate after a UI change** (both scripts are in the repo):

```
bash Scripts/capture_screenshots.sh        # builds for the iPhone 17 Pro Max simulator,
                                           # seeds demo data, sets 9:41, captures to Marketing/captures/
python3 Scripts/make_screenshots.py        # composes the panels into Marketing/screenshots/ (needs Pillow)
```

The captures use a DEBUG-only seed (`-seed` launch argument), so nothing
personal is ever on screen. The panel headlines live at the top of
`make_screenshots.py` if you want different copy.

Three practical notes:
- Apple accepts as few as one, but 3–5 is normal. You can reorder them later.
- Upload in the numbered order — the first screenshot is most of the decision.
- If you change the Library layout, re-run both scripts before submitting; a
  screenshot that doesn't match the build is a legitimate rejection reason.
