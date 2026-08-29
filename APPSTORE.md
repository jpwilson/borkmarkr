# App Store Connect — copy-paste

Every field below is filled in and ready. Nothing here claims a feature that
isn't in the build — a reviewer opens the app and checks, and an unbackable
claim is the most common avoidable rejection.

---

## App Information

**Name** (30 char max)
```
bookmarker
```

**Subtitle** (30 char max — this is the line under the name in search)
```
All your links, in one place
```
*(28 chars. Alternative if you prefer the source emphasis: `Save links from every app`.)*

**Category** · Primary: `Productivity` · Secondary: `Utilities`

**Support URL**
```
https://bookmarker.lol/
```

**Marketing URL**
```
https://bookmarker.lol/
```

**Privacy Policy URL**
```
https://bookmarker.lol/privacy
```
*(If HTTPS on bookmarker.lol isn't live yet when you fill this in, use
`https://jpwilson.github.io/borkmarkr/` and `…/privacy.html` — they keep
working and redirect once the domain is up. All three URLs can be edited
any time without a new build.)*

---

## Promotional Text (170 char max — editable any time without a new build)

```
Thousands of saved reels, threads and clips across five apps — and you can't find one of them. bookmarker puts every save in one library, filed by topic, searchable.
```

---

## Description

```
You've saved thousands of things. The reel that finally explained mobility work. A thread on sleep supplements. A recipe you meant to cook, a car you meant to research, a place you meant to go. You know you saved them. You just can't find a single one.

That's because every app keeps your saves in its own pile — untitled, unsorted, unsearchable, and locked inside that app. Instagram doesn't know about YouTube. YouTube doesn't know about X. Your "saved" folders are where good things go to disappear.

bookmarker is the library that sits above all of them.

SAVE FROM ANYWHERE, IN ONE TAP
Tap Share in Instagram, X, TikTok, YouTube or any other app and pick bookmarker. Done. The title, the account and a thumbnail come along automatically. Or paste a link straight in.

IT FILES ITSELF
Every save lands in a topic and subtopic — Fitness › Mobility, Recipes › Meal prep, Cars › Detailing. Fifty topics, over six hundred subtopics, and room to add your own. It's a suggestion, not a sentence: change anything it gets wrong, or just search.

FIND IT AGAIN IN SECONDS
Search titles, tags, notes, people and links. A Related strip surfaces the saves that match what you meant, not just the words you typed. Browse by topic to see everything about running, from every app. Or by app, to see everything you kept from TikTok.

REMEMBER WHY YOU SAVED IT
Add a dated note to anything. bookmarker also keeps count of how many times you've gone back to it, so you can see what you actually use.

SIDE QUESTS
Training for a marathon? Choosing a car? Planning a trip? Group the saves that help, give the quest a name, and add a daily habit if it needs one. Your saves stop being a pile and start being a plan.

BRING THE THOUSANDS YOU ALREADY HAVE
Import your browser bookmarks, or your data export from X, Instagram, TikTok or YouTube. Years of saves become a sorted, searchable library in one step. That's the moment it clicks.

YOURS, AND ONLY YOURS
bookmarker stores links, not content — opening a save takes you to the original post, in the app it came from. Everything works offline and lives on your phone. Sign in with just an email, no password, if you want it backed up and synced. No ads. No tracking. No analytics.

Your saves were never the problem. Finding them was.
```

---

## Keywords (100 char max, comma separated, no spaces)

```
bookmark,save,links,reels,tiktok,shorts,organize,tags,offline,library,read later,collect,sort
```

---

## App Review Information

**Sign-in required?** → **Yes.** Apple's first review (28 Aug 2026, Guideline
2.1 "Information Needed") asked for a demo login even though no feature needs
an account, so we give them one.

- User name: `review@bookmarker.lol`
- Password: whatever you set when you created that user in Supabase
  (Authentication → Users → Add user → *Create new user*, email +
  password, **Auto Confirm User on**). Keep it in ASC and Supabase only.

The app recognises that one address (`Supabase.passwordAccounts`) and asks for
a password instead of emailing a code. Every other account stays on codes.
If a reviewer taps "Delete account" the user is gone — re-create it before the
next submission.

**Contact phone**: currently the Porkbun registrant number; swap if you'd
rather Apple call a different one.

**Notes** (paste the block below; keep it under 4,000 characters)
```
DEMO ACCOUNT
Use the sign-in details above (review@bookmarker.lol). You tab → Sign in → enter the email → the app asks for the password. This is the one address that uses a password: every other user receives a six-digit code by email, and a review address can't receive mail. No account is needed for any feature; tapping "Not now" also works.

WHAT THE APP IS, AND FOR WHOM
bookmarker is a personal bookmark manager for people who save reels, threads, videos and articles across several apps and can't find them again. Users save links they chose — via the Share sheet or by pasting — into one library. Each save is filed under a topic, tagged, searchable, and can carry a note. "Side quests" group saves into a small to-do (recipes to cook, places to visit). Audience: general, rated 4+; typical users are adults who save a lot on social apps.

The app does NOT display, embed, host, reproduce or scrape platform content. It stores the URL plus the title and thumbnail from the page's own Open Graph metadata, and opening a save calls openURL to hand off to the original app or site. There is no feed, no content visible to other users, and no login to any third-party service.

HOW TO TEST
1. Tap + → paste any link (e.g. https://www.youtube.com/watch?v=dQw4w9WgXcQ). Title/thumbnail fetch automatically → tap "Bork it".
2. Library shows the save. Tap it → "Open original" hands off to the source.
3. Search tab: type a word from the title. Browse tab: topics.
4. Share extension (optional): Safari → Share → "bookmarker".
5. Account: You tab → Sign in with the demo account → "Backed up" appears on the You card. "Sign out" and "Delete account" are on the same card. Delete account asks for confirmation, deletes the account and all server-side data, and signs out.

EXTERNAL SERVICES
- Supabase (auth, Postgres, Edge Functions): email-code sign-in and optional backup/sync of the user's own bookmarks.
- Resend: delivers the sign-in code emails from hello@bookmarker.lol.
- OpenRouter → Anthropic Claude: when on-device keyword filing can't place a link, a signed-in user's link URL and title are sent from our server to suggest a topic; "Highlights" summarises up to 40 recent titles/topics. Signed-out users get on-device filing only. No API key ships in the app; calls are server-side and capped per user per day.
- Link previews are fetched directly from the saved page (its Open Graph tags).
- Website and privacy policy: https://bookmarker.lol (GitHub Pages).

DEVICES TESTED
iPhone 17 Pro Max on iOS 26.6 (physical device, via TestFlight); iPhone 17 Pro Max simulator, Xcode 26.6.

REGIONS
Identical features and content in every region. Not a regulated industry. No protected third-party material: users save links to content they chose, and the app links out to it.

PERMISSIONS
None requested — no location, contacts, camera, photos, tracking or notifications. The only system UI is the iOS Share sheet.
```

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

The questionnaire asks about *unrestricted web access*. Answer **No**: it means
browsing the web *inside* the app (a web view), and bookmarker has none — it
hands every link to iOS with `openURL`. Answering Yes is what pushes the rating
to 16+ under Apple's 2025 scheme. Set 2026-08-27: 4+.

**Digital Services Act (EU):** App Information → App Store Regulations &
Permits → Digital Services Act → Set Up. Apple needs a trader/non-trader
declaration before the app can be sold in the EU. It's an account-level legal
statement, so JP does it himself.

---

## Before you submit — the things only you can do

Supabase project: **bookmarker** (`pcjuxnhqxyfvgagnblzv`) in the
**JPGauntletProjects** organization — not the org that holds EVLineup/OFS.
Dashboard: https://supabase.com/dashboard/project/pcjuxnhqxyfvgagnblzv

**Order:** 3 (SMTP — Supabase locks template editing until custom SMTP is on)
→ 1 → 2 → App Store Connect → Archive → Submit with *manual release*. 4 is
optional. Templates: run `python3 Scripts/gen_email_templates.py` and paste
from `supabase/templates/`, or use the copy page linked in the README of that
folder.

**1. Email templates — REQUIRED (2 minutes)**

The app asks for a six-digit code, but Supabase's default templates send a
*link*. A real user gets an email they can't use. Fix:
Authentication → Emails → Templates. Replace the body of BOTH
**Confirm sign up** and **Magic Link** with `supabase/templates/confirm-signup.html`
and `supabase/templates/magic-link.html` (generated by
`Scripts/gen_email_templates.py`; the other four templates are there too).
Subject for both: `Your bookmarker code`

**2. Site URL (1 minute)**

Authentication → URL Configuration → Site URL:
```
https://bookmarker.lol
```
The default is `http://localhost:3000` and it leaks into any link Supabase
generates.

**3. Custom SMTP — REQUIRED before *release*, not before *submission***

Supabase's built-in mailer is dev-only: it refuses to deliver to addresses
outside your Supabase team and is capped at a couple of emails per hour. The
reviewer never hits this (the review notes say no account is needed), but the first
real user would. Needs a domain you own:

1. Domain: **bookmarker.lol** (bought 25 Aug 2026 at Porkbun; bkmrkr.lol
   forwards to it).
2. Resend (resend.com, free tier 3,000 emails/month) → Domains → add
   `bookmarker.lol` → add the DNS records it shows at Porkbun → "Verified".
3. Resend → API Keys → create one (sending only).
4. Supabase → Authentication → SMTP Settings → enable custom SMTP:
   - Sender email: `hello@bookmarker.lol` · Sender name: `bookmarker`
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

**5. Review sign-in** — nothing to configure. Supabase has no test codes for
email (only for SMS), so the review notes simply say no account is required,
which is true: every feature works signed out and the reviewer can tap
"Not now".

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

A 6.5" set (1284 × 2778) is in `Marketing/screenshots-6.5/` for the other iPhone
slot; App Store Connect shows whichever slot it feels like first — "View All
Sizes in Media Manager" reveals both.

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
