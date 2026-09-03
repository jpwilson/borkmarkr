# Launch posts — X thread + Reddit

All bookmarker.lol links carry UTM params:
`https://bookmarker.lol/?utm_source=<platform>&utm_medium=<post|reply>&utm_campaign=<slug>`.
Launch-day campaign slug: `launch-day`.

---

## X launch thread (8–10 posts, build-in-public voice)

Post as a numbered thread the morning of 2 Sep 2026, first reply within the
hour is the pinned reply with screenshots (not scripted here — grab three
from `Marketing/screenshots/`).

**1/10**
bookmarker is live on the App Store today. Free, iOS 17+, 8MB.

It's the library that sits above every app you save things in — Instagram,
X, TikTok, YouTube — because none of those saved lists talk to each other or
let you search them.

https://apps.apple.com/app/id6799805479

**2/10**
The idea: you save constantly and can never find any of it again. Every
platform's "saved" list is a write-only pile — no titles, no search, no
order. bookmarker files what you save into topics automatically and makes
it searchable.

**3/10**
What's real today: save from the share sheet, it's filed into one of 50
topics automatically, search across titles/tags/notes, "side quests" to
group saves into a to-do, and bulk import from your Instagram, TikTok, X or
YouTube export, or your browser bookmarks.

**4/10**
It also syncs between iPhone and the web app now
(https://bookmarker.lol/?utm_source=x&utm_medium=post&utm_campaign=launch-day),
and the app itself asks for zero permissions — no location, no contacts, no
camera, no ads, no tracking.

**5/10**
Quick recap, because the last week was rougher than the App Store listing
lets on. Submitted 27 Aug. 28 Aug, Apple came back under Guideline 2.1 —
"Information Needed": a demo login, a screen recording, some written
answers. Not a rejection, just paperwork.

**6/10**
Fixed everything they asked for the same day — in-app account deletion (an
Apple requirement anyway), a real demo account, and a session-refresh bug
that was silently killing sync an hour after sign-in. That last one mattered
more than the App Store stuff, honestly.

**7/10**
29 Aug: split "sign in" into proper sign up / sign in flows, and found the
actual bug — a bulk-upsert quirk — that was blocking first backups
entirely. My own library, 87 saves, backed up to the server for the first
time that day. Builds 2 through 6, same week.

**8/10**
30 Aug: screen recording done, resubmitted, status "Waiting for Review."
Same day, I built and shipped a whole working web app — sign-in, library,
search, topics — in one day. It's now the easiest way to try bookmarker
without installing anything.

**9/10**
2 Sep: approved, and I hit release. Live now:
https://apps.apple.com/app/id6799805479 (iPhone) and
https://bookmarker.lol/?utm_source=x&utm_medium=post&utm_campaign=launch-day
(web — works without an account, there's a demo library).

**10/10**
I'm a solo developer, building this with AI coding agents, in the open. If
you're the person with 2,000 saved reels and no idea where the good ones
are — that's who I built this for. Try it, tell me what's broken:
hello@bookmarker.lol

---

## r/SideProject post

**Title:** I shipped a bookmark manager after Apple bounced it once — live today (iOS + web)

**Body:**
Backstory first because it's more interesting than the pitch: submitted to
the App Store on 27 Aug, got an "Information Needed" reply from Apple the
next day (Guideline 2.1 — wanted a demo login, a screen recording, and some
written answers, not a rejection, just paperwork). Fixed everything, found
and fixed a real sync bug along the way (a bulk-upsert quirk that was
silently blocking first backups), resubmitted 30 Aug, and — on a whim, same
day — built and shipped a full web version in about 24 hours. Approved and
live today, 2 Sep.

**What it is:** bookmarker files everything you save from Instagram, TikTok,
X, YouTube (or wherever) into one searchable library, automatically sorted
into topics. The wedge is bulk import — drop in your Instagram/TikTok/X/
YouTube data export or your browser bookmarks and years of saves become a
sorted, searchable library in one step. Syncs between iPhone and the web
app. No ads, no tracking, no third-party SDKs in the app.

Solo dev, built with AI coding agents. iPhone: https://apps.apple.com/app/id6799805479
Web (no install, has a demo library): https://bookmarker.lol/?utm_source=reddit&utm_medium=post&utm_campaign=launch-day

Would genuinely like feedback on the import flow especially — that's the
part I think is the actual differentiator and I want to know if it lands.

---

## r/iosapps post

Note: r/iosapps allows self-promotion once per 30 days; disclose you're the
developer up front; don't link-spam (one link, in the body, not the title).

**Title:** bookmarker — I'm the developer, launched today, would love feedback

**Body:**
Hey — I'm the solo developer of bookmarker, launching today. Posting once,
disclosing that up front per the sub's rules.

What it does: saves anything you share to it from any app, files it into a
topic automatically (50 topics, ~600 subtopics), and makes it searchable —
titles, tags, notes, the people you saved from. The part I'd actually like
feedback on is bulk import: it reads your Instagram/TikTok/X/YouTube data
export or your browser bookmarks file and turns years of saves into a
sorted library in one step.

Free, iOS 17+, 8MB, no ads, no tracking, no third-party SDKs in the app —
sign-in is optional and only adds backup/sync to the web app.

Link: https://apps.apple.com/app/id6799805479

Happy to answer anything about the build, the App Store review process (it
wasn't smooth — got an "Information Needed" round first), or the import
logic specifically.

---

## r/InternetIsBeautiful post (web app)

Note: this sub wants a link post with a plain, factual title — the "why" goes
in the first comment, not the title.

**Title:** bookmarker.lol — a searchable library for everything you save
across Instagram, TikTok, X and YouTube (works without an account)

**Link:** https://bookmarker.lol/?utm_source=reddit&utm_medium=post&utm_campaign=launch-day

**First comment (post immediately after submitting):**
Made this — it's the iPhone app's sibling, but works fully in the browser
with no install and no account. There's a demo library if you just want to
click around before deciding whether to sign in. The point of it: every
platform's "saved" list is a dead end with no search and no order, so this
is the one library that sits above all of them, filed by topic
automatically. Bulk import (your platform's data export, or browser
bookmarks) is on iPhone today; a web importer is coming this week. No ads,
no tracking on the core app experience. I'm the solo dev, happy to answer
anything.

---

## Reddit reply templates (5)

Rules for all five: disclose in the first sentence, answer the real
question with real, useful information before mentioning bookmarker at all,
and mention the app once, at the end, low-key. Never post to r/ADHD — it
bans app posts outright; if a thread like this shows up there, don't reply.

### Template 1 — "How do I search my saved reels on Instagram?"

Disclosure: I built an app for exactly this, so I'm biased, but here's the
actual answer first.

Instagram's Saved tab doesn't have a search bar — you can only filter by
the collections you've manually created, and if you never made any, it's
one long grid in save order. Your best free option inside Instagram: start
making Saved Collections now (tap Save, "Add to collection," name it) so at
least future saves are grouped by topic. It won't help with what you've
already saved, though — there's no bulk way to sort old saves inside the
app.

If you want the old saves sorted too: request your data (Settings →
Accounts Center → Download your information), and an app like bookmarker
can import that export and file it into topics automatically, then make it
searchable. Not the only option, but it's what I built it to solve.

### Template 2 — "Is there a way to search TikTok favorites?"

Disclosure: I make an app that deals with this, so take the recommendation
with that in mind — but here's what actually works first.

TikTok's Favorites tab has no search of its own either, same problem as
Instagram. The one thing that helps a little: TikTok lets you sort
Favorites into folders manually (tap the video, Favorite, then organize
from the Favorites screen) — tedious for a backlog, fine going forward if
you keep up with it.

For an existing pile: TikTok's data export (Settings → Account → Download
your data → include "Favorite Videos") gives you the URLs and dates. An app
like bookmarker can import that file and sort it into topics automatically
so it's searchable afterward — that's the gap I built it for.

### Template 3 — "Anyone know how to export X/Twitter bookmarks?"

Disclosure: I build a bookmarking app, so full disclosure before I answer.

X's own "Download an archive of your data" (Settings → Your account →
Download an archive of your data) includes your bookmarks along with likes
— it takes X a few hours to a day to prepare, then you get a JSON/HTML
archive you can browse locally. That's the real, first-party way to get
them out; there's no in-app search for bookmarks beyond scrolling.

If you want that archive turned into something searchable and sorted by
topic afterward instead of just sitting as a raw file, that's what
bookmarker's import does with it.

### Template 4 — "I've lost track of everything I've saved across apps"

Disclosure: I built bookmarker specifically for this problem, so obvious
bias here, but the underlying issue is real regardless of what you pick to
fix it.

The actual problem is structural: every platform's save button writes to a
private, unsearchable list that only that platform can see, so nothing you
save on Instagram shows up when you're looking on TikTok or X, and none of
them let you search well even within themselves. There's no single-app fix
inside any one platform — the only ways out are (a) manually re-organizing
inside each app's own folders/collections, which most people don't keep up
with, or (b) pulling your saves out via each platform's data export and
consolidating them somewhere else.

bookmarker is the "somewhere else" I built — it imports those exports (or
just takes new saves via the share sheet going forward) and files
everything into one searchable library, auto-sorted by topic.

### Template 5 — "Best way to organize YouTube Watch Later / saved playlists?"

Disclosure: I make a bookmarking app, mentioning it at the end, but here's
the real answer to your actual question first.

Inside YouTube: Watch Later has no folders and can't be split up; regular
playlists can, so the practical fix going forward is making topic playlists
(Fitness, Recipes, etc.) instead of dumping everything into Watch Later.
For an existing backlog, Google Takeout (takeout.google.com → select
YouTube → Watch history and Watch Later / playlists) gets you a CSV of
everything you've saved, video IDs and titles included.

If you want that CSV turned into a sorted, searchable library afterward
instead of a spreadsheet, bookmarker's import reads Google Takeout exports
and files them into topics automatically.
