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

AUTOMATIC FILING
Links are sorted into topics on-device by keyword matching. For links that can't be placed that way, a signed-in user's link URL and title are sent to our server, which asks a language model (Anthropic Claude) for a suggested topic. The suggestion is shown to the user and can be changed before saving. Signed-out users get on-device filing only. No API key ships in the app; the call is made server-side.

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

### Automatic filing — already covered above

The AI topic suggestion sends a signed-in user's link URL and title to Anthropic
via our own server. That's **User Content, used for App Functionality**, which
is exactly what's already ticked — Anthropic is a service provider acting on our
behalf, not a party we share data *with* in Apple's sense, and none of it is
used for tracking or advertising. So there is nothing extra to tick here.

It does need to be in the privacy policy, and it is: see the "Automatic filing"
section at `docs/privacy.html`.

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

**1. Anthropic API key** (optional — the app ships fine without it)

AI topic suggestion is dark until a key is set. Supabase dashboard →
**Edge Functions → categorize → Secrets**, or:
```
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
```
Get the key at console.anthropic.com. Nothing else needs it, and it never
leaves the server — do not put it in `Config.xcconfig`, the app, or the repo.

Until it's set, every save falls back to on-device filing, which is the same
behaviour signed-out users get. Nothing breaks, nothing errors.

**2. Review test code** (needed only if you keep the sign-in paragraph)

The review account only works once a fixed test code is configured, or the
reviewer cannot receive the email. Supabase dashboard →
**Authentication → Sign In / Providers → Email → Test OTPs**, add:
```
appreview@borkmarkr.app = 123456
```

That maps one specific address to one fixed code, without weakening sign-in for
anyone else. Takes about thirty seconds.

If you'd rather not, delete the "TESTING SIGN-IN" paragraph from the review
notes — "no account required" already covers the requirement on its own.

---

## Screenshots

Required: 6.9" iPhone — **1320 × 2868**, which is exactly what your iPhone 17
Pro Max produces. So: screenshot on your phone (side button + volume up),
AirDrop them to the Mac, upload. No editing, no mockup tool, no resizing.

Three practical notes:
- Apple accepts as few as one, but 3–5 is normal. You can reorder them later.
- Check nothing personal is on screen — a real saved link with your name, or a
  notification banner mid-screenshot.
- Use a library with real content. An empty app is a bad first impression, and
  the first screenshot is most of the decision.

Worth capturing, in this order:
1. **Library** with a full masonry feed — the visual signature
2. **Browse → Topics** showing the coloured topic tiles
3. **Search** with results
4. **A saved item** open, showing the note and "Open original"
5. **Import** screen — the "you already saved thousands of things" idea
