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
Save links from every app
```

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

## Before you submit — the one thing that needs doing

The review account above only works once a fixed test code is configured, or
the reviewer cannot receive the email. In the Supabase dashboard:

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

Required: 6.9" iPhone (1320 × 2868). Use your own device with a real library —
an empty app makes a bad first screenshot.

Worth capturing, in this order:
1. **Library** with a full masonry feed — the visual signature
2. **Browse → Topics** showing the coloured topic tiles
3. **Search** with results
4. **A saved item** open, showing the note and "Open original"
5. **Import** screen — the "you already saved thousands of things" idea
