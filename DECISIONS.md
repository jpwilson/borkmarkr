# Engineering decisions

Where this implementation deliberately departs from `design_handoff_borkmarkr/README.md`.

The handoff is authoritative on look, feel and flow. It was produced from a
prototype with 26 fixed sample items, so it doesn't model what happens at three
thousand saves, across timezones, or with a second process writing. Everything
below is a place where following the spec literally would have shipped a worse
product. Each one is also commented at the code site.

---

## Data model

| Spec | Here | Why |
|---|---|---|
| `date: 'YYYY-MM-DD'` | `savedAt: Date` | String dates sort incorrectly across timezones and can't be range-queried. |
| `dur: 'M:SS' \| ''` | `durationSeconds: Int?` | The spec encodes *"is a video"* in whether a string is empty. Duration is a quantity; `"12:48"` can't be compared or summed. Formatting belongs in the view. |
| `id: 'n' + seq` | content-derived `stableID` | A sequential counter can't dedupe and collides immediately once two devices sync. |
| — | `updatedAt`, `deletedAt` | Required by the sync fast-follow. Free now, a migration later. Deletes are tombstones: a device that was offline during a delete would otherwise re-upload the row. |
| — | `searchBlob` | Precomputed lowercase haystack. Search becomes one `contains` per item instead of six. |

## Correctness

**Platform detection.** The spec's `detectPreview` matches substrings against the
whole URL: `url.includes('x.com')` files **netflix.com**, **max.com** and
**sfx.com** as X, and `includes('threads')` catches any URL with "threads" in its
path. Detection here matches the registrable host instead, which removes the
whole bug class.

**Deduplication.** The spec has none — sharing the same reel twice creates two
items. `Bookmark.stableID` normalises the URL (drops `utm_*`, `igshid`, `si`,
`s`, `t`, `fbclid`; strips `www.`/`m.`, trailing slashes; sorts query params), so
share-sheet duplicates collide into one bookmark.

**Relative dates.** The prototype anchors both dates to noon and rounds the
millisecond gap, which drifts across DST and in non-hour-offset timezones. This
uses calendar day differences.

## Layout

**Masonry packing.** The spec mandates strict alternation — "evens→left,
odds→right" — and correctly warns that CSS `column-count` destroys recency
ordering. But alternation ignores card height. Cards here range ~96pt to ~260pt;
a run of tall media into one column and short text posts into the other leaves
the columns hundreds of points apart and the feed ends in a one-sided stack.
`MasonryVStack` places each item into whichever column is currently shorter,
still in strict recency order. Where heights are equal it degenerates to the
spec's alternation — which is what the design was reaching for.

## Performance

**Category colours** are precomputed once into an immutable table rather than
recomputed from HSL per render. A masonry feed does thousands of colour
conversions per scroll otherwise.

**Search** matches the precomputed `searchBlob` and debounces input by 180ms.
The prototype re-scans six fields per item per keystroke.

**No fake latency.** The spec fakes 950ms in the Add flow to make the categoriser
look like it's thinking. Ours is genuinely instant; a fabricated spinner costs a
second of the user's time on every save. The `reading` step remains in the state
machine because real link unfurling will need it.

## Architecture

**Share Extension writes to an inbox, not the database.** v1 opened the SwiftData
container inside the extension. Two processes on one SQLite store risks
corruption and lost writes when the app is backgrounded and the extension
launches. The extension now writes an atomic JSON draft into the App Group inbox
and exits; the app drains it on launch and foreground. Single writer, no
coordination, and a crash mid-save loses nothing — the draft is still queued.

This also respects the extension's ~120MB memory cap: booting a persistent store
to save one URL is slow and risky while the user waits over someone else's app.

**Expiring covers are copied server-side, never re-fetched by clients.** Instagram,
Facebook and TikTok sign their CDN image URLs and let them die in about five days,
so a library of reels goes grey a week after it was saved. `0008_thumbs.sql` queues
a job whenever a bookmark arrives with one of those URLs (statement-level trigger:
a phone pushing 500 rows is one wake-up, not 500) and pokes the `thumb` Edge
Function through pg_net; pg_cron retries every minute while anything is due. The
function copies the bytes into the public `thumbs` bucket — magic-byte sniffed,
1.5MB cap, same SSRF guard as `preview` — and rewrites `image_url` to a permanent
URL. Three rules fell out of the clients' sync model:

1. **Nothing here may fail a save.** Bookkeeping lives in `thumb_jobs`, not on
   `bookmarks`, every trigger swallows its own errors, and the RPCs are
   service-role only. `select=*` on `bookmarks` is unchanged for both clients.
2. **The rewrite must bump `updated_at`** (the existing `bookmarks_touch` trigger
   does it) or neither client ever pulls the new cover — and it waits ~8s after
   the client's write so the phone has stamped its sync cursor first.
3. **A stale client re-pushing the dead URL is swapped back in-row** by a BEFORE
   trigger, so the copy is never lost to last-writer-wins.

The shared token lives in Vault and in the function's secrets, never in git — the
hard-coded token in `0007_signup_notify.sql` is the anti-pattern this replaces.

**Feedback is a write-only table, and the inbox is email.** The Help tab posts to
`public.feedback` over REST (`0009_feedback.sql`). The table grants `insert` on
four columns and nothing else: no `select` for anyone, `user_id` outside the grant
so it can only be the default `auth.uid()`, and a contact address accepted only
from signed-out senders (a signed-in user's address is already on the account).
A trigger then mails the row through the `notify` function — the same function
`beta_signups` uses, so there is one Vault token and one place to rotate it — and
stops mailing after 20 rows in ten minutes, so a script hitting the public
endpoint fills a table, not an inbox. Nothing about the sender is sent to PostHog
beyond `{kind, signed_in}`, and the message field is `ph-no-capture`.

**Sync pulls the whole library, every time — there is no since-cursor.** The
obvious optimisation is `updated_at > lastSynced`, and 1.0 shipped it. It is
wrong here, because `updated_at` is stamped by whichever **client** wrote the
row and never by the database. A row therefore reaches the server routinely
carrying a timestamp *older* than a cursor this device already saved — a phone
that saved offline and pushed on the next foreground, a second device a few
seconds behind, or a phone save at 20:48Z followed by a web edit that advanced
the cursor past it. Once that happens the row is never newer than the cursor
again and the device simply cannot see it: not a delayed sync, a permanent hole,
and two devices editing on the same day quietly diverge. iOS 1.0.1 now reads
every row on every sync — 1,000 per request, ordered `updated_at.asc,id.asc`
(the `id` tiebreak matters: a bulk import stamps hundreds of rows inside one
millisecond), merged last-writer-wins with tombstones respected, with the page
offset held in a local variable and never written down. The web app got here
first (`pull()` in `docs/index.html`).

Two deliberate differences from the web:

- **Offset paging, not the web's `updated_at=gte.<last>` keyset.** With ties —
  and an import produces thousands — a keyset page can repeat the same rows
  forever or skip past them. Offset with a total order can't. The cost is that a
  row rewritten *during* a pull can shift between pages; it arrives on the next
  sync, which is a delay rather than a hole.
- **`lastSynced` stays, and stays persisted.** It is no longer a download
  filter, which was the bug; it remains the *upload* watermark (`push` uploads
  what changed since it) and the "Backed up 5 minutes ago" line. Dropping it
  entirely would make every launch re-push the entire library, and since the
  upsert is `resolution=merge-duplicates` — an unconditional overwrite — that
  re-push would clobber a second device's newer edits with this device's older
  copies. Both sides of the push comparison are stamped by the same device's
  clock, so it can only over-send, never under-send.

Nothing changes on the push side, and missions/side quests are untouched because
iOS doesn't sync them at all yet — `Mission` is local SwiftData only, and the
`missions` table has just the one client (the web app).

**Signed out is a state the app has to show, not a modal it has to sell.** People
were using bookmarker for weeks without knowing their library was only on the
phone. Saving is never gated behind an account and never will be — which is
exactly why the app owes them the sentence: the only place that said it was the
You tab, and the You tab is the one tab a happy user never opens. `SignInNudge`
holds the whole policy (the `ReviewPrompter` shape: one small type, one-line
call sites): a persistent Library banner from the third bork, a dot on the You
tab, and a sheet at the 5th, 25th and 100th bork.

Three rules keep it a statement rather than nagging:

1. **Never on launch.** A milestone fires only on a crossing the app can
   *prove*, against a watermark of the count it last looked at. A library
   already past 25 the first time the policy sees it never gets a sheet for 25 —
   opening the app is not an achievement, and a modal on launch is the thing we
   refuse to ship. The count comes from the store, so a bork saved through the
   Share Extension counts exactly as much as one saved in the app.
2. **Never on top of something else.** A milestone that can't be shown (another
   sheet, the Add flow, the first-run tour) leaves the watermark alone and stays
   due for the next Library appearance, rather than being spent on a sheet
   nobody saw.
3. **Fourteen days of quiet after any dismissal**, ✕ or "Not now", and at most
   one sheet per fourteen days however many milestones a bulk import crosses at
   once. Two weeks is long enough that a second ask reads as new information
   instead of pestering, and short enough to still reach someone before they
   drop the phone in a river. Signing in removes every surface permanently.

The banner's message is "this only lives on this phone", never "you must sign
in": the honest fact, with the fix next to it.


## Web app

**The topic picker is the iOS sheet, not a `<select>`.** Two native selects gave
the web app no way to add a subtopic, and on a phone the second one sat under the
keyboard. `#topic-dialog` ports `TopicPickerSheet`: one searchable list, A–Z,
subtopics as wrapping pills, "Just <Topic>", and an inline "add a subtopic" —
the same interaction on both platforms. A user's own subtopics have no table of
their own on either platform: they are whatever non-built-in `subcategory` values
their borks carry, so the web derives the list from the loaded library plus
anything added this session, exactly as the app does from SwiftData.

**The web app files through `categorize` on every signed-in save.** The iOS app
has an offline word-matcher and asks the model only when that falls through; the
web app has no such matcher, so it asks straight away — under the same per-user
daily quota, and only after the preview has resolved so the title travels with
the URL. The suggestion is marked `source: "ai"` and is dropped the moment the
user touches the picker; a slow answer for an earlier URL is discarded by
sequence number. Signed out, nothing is sent and the bork is simply "not filed".

## Accessibility

**Small-text contrast.** The spec's tertiary ink `#A39A8D` on `#F6F3EE` paper is
about **2.4:1**, well under the WCAG AA floor of 4.5:1, and it's paired with
10–10.5px type. `Tokens.inkMeta` is darkened to `#6E655A` (~4.9:1) for anything
carrying information; the original remains as `inkFaint` for decorative marks
only.

**Tap targets.** Spec chips are ~24pt tall against Apple's 44pt minimum.
`tappableChip()` keeps the visual size and expands the hit area.

## Taxonomy

Rebuilt from 24 categories / ~230 subcategories to **50 / ~612**.

The handoff's set has real gaps for what actually gets saved off short-form feeds
in 2026: no cars, books, true crime, creator economy, cleaning/organising,
trades, anime, or photo/video — and AI sat as one sub-item under Tech. It also
merged audiences that behave nothing alike (Beauty inside Style, Nutrition inside
Food, Mental health inside Health). The original product brief asked for "a few
hundred" categories, which 24 never approached.

**Hues are assigned semantically**, in families (body/self, making/home,
growth/nature, money/commerce, screens/motion, play/mind, story/meaning) rather
than arbitrarily. Known trade-off: in a library concentrated in one family — a
lot of fitness and nutrition, say — the feed reads as mostly one colour. Spreading
hues randomly would give more variety at the cost of the colour meaning anything.
Worth revisiting with real usage.

**The categoriser derives its index from the taxonomy.** Every subcategory name is
already a keyword, so ~612 matchers come for free and stay correct as categories
are added; a curated hint layer covers only the phrases people actually write
that no label contains. Includes light stemming (both sides), so "stretches"
matches "Stretching" and "detailed" matches "Detailing".

**AI categorisation is a second pass, not the first one.** The keyword categoriser
still runs first on every save: it's instant, free, works offline and signed out,
and handles most links. The model is called only when that pass came back empty or
on thin evidence (`Suggestion.isConfident`), and only when signed in. Three reasons
that ordering rather than "always ask the model":

1. **Saving must never wait on the network** — the core product rule. The offline
   answer is on screen before the request is even sent, and the sheet is fully
   interactive; the AI result arrives and updates a chip, or doesn't.
2. **Cost tracks the hard cases.** ~2.2k input tokens per call on Haiku is about a
   quarter of a cent. Paying that on every save is roughly $25 per 10,000 saves;
   paying it only on the fall-through is a fraction of that, for the same
   user-visible quality — the easy links were already right.
3. **Every failure mode is already handled.** Signed out, offline, quota spent, key
   unset, server down, taxonomy drift — all of them mean "keep the offline answer",
   which is a working answer, not an error state.

**The Anthropic key is server-side, and that is not negotiable.** It lives in a
Supabase Edge Function's environment. A key shipped inside an iOS binary is a key
published to everyone who downloads the app — `strings` on an `.ipa` is all it
takes — and the bill lands on the developer. The app authenticates with the user's
own Supabase JWT and never sees the key.

**Spend is bounded server-side, not by client behaviour.** A per-user daily quota
(`ai_quota_consume`) is consumed *before* the model is called, and fails closed:
anonymous callers are denied at the grant level, and if the quota check itself
errors the function skips the model rather than risk an unmetered call. A public
anon key plus a retry loop is otherwise all it takes to spend someone else's money.

**The model's answer is validated against the app's own taxonomy.** The function
embeds a generated copy of the taxonomy (`Scripts/gen_taxonomy_ts.py`), which can
drift from the app across a redeploy-without-release. So `SmartCategorizer` drops
topic IDs this build doesn't have and case-matches subtopics against the real list.
Drift degrades to "not filed" rather than to a bookmark filed under a category that
doesn't exist and is invisible in Browse.

---

## Known gaps

- **Fonts.** The spec calls for Bricolage Grotesque + Instrument Sans. Neither is
  bundled — both are OFL Google Fonts and need adding as binary assets. `Typo`
  currently maps to system faces; swapping is a one-enum change.
- **Link previews.** Media covers are category-hue gradients, as in the
  prototype. Real thumbnails need per-platform work: Instagram's Basic Display
  API is gone, X's is paywalled. YouTube oEmbed is the honest first step.
- **Not visually verified.** Library is confirmed rendering on device. Browse,
  Topic page, Source page, Search, Detail, Add and Onboarding compile and are
  wired, but have not been screenshotted.
- **Friend feed.** Schema only (`supabase/migrations/0001_init.sql`), nothing
  wired to the client. Deliberate — post-launch fast-follow.
