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

**Search stopped being a tab, and Revisit took the slot.** Search was one of
five tabs and the only one that opened onto nothing: an empty field, a recents
list most people never had, and no library in sight. Meanwhile Browse *is* the
screen you are on when you are looking for something, and it made you leave it
to type. So in 1.1 the field moved to the top of Browse — results replace the
topic grid while a query is live, clearing it puts the grid back — and the dock
slot went to a tab that had something to show. `AppTab.resolve` maps a
persisted or deep-linked `search` to `browse` rather than falling through to the
Library: a phone updating from 1.0.x can be carrying `startingTab = "search"`,
and dropping that person on the Library when they asked to search is the kind of
silent wrong answer a default hides.

Two things the old tab had are deliberately gone, and one is new:

- **Recents** had no home once the empty state became the topic grid. There is
  no longer a screen whose default content is a list of words you typed.
- **The Topic and Side quest filter axes** are replaced by the scope chips.
  Filtering to a topic is what Browse's grid already does, and two
  differently-shaped filter systems stacked on one screen made it look like two
  apps. Finding a bork by the name of a side quest it is on survives, unscoped.
- **Scope chips — Topics · Subtopics · Tags.** None selected is the pre-1.1
  behaviour exactly (`searchBlob`, one substring test per bork), which matters:
  that is what every existing user's muscle memory is built on. With one or more
  selected, every query term has to land in a selected field and the scopes OR
  together per term, so "hip mobility" with Subtopics+Tags matches a bork tagged
  `hips` filed under `Mobility`, and a two-word query can't be satisfied by one
  word matching twice. The rules live in `Core/SearchScope.swift` as a pure
  `SearchSubject.matches(query:scopes:)` over plain values — no SwiftData, so
  `Scripts/test_search.swift` compiles and runs under `swiftc` in about two
  seconds. Search is the feature people judge the app on; it should be the part
  with tests that run in two seconds.

**Revisit is the "revisited" verb, given a home.** The thesis is *everything
interesting you scroll past every day, captured, organised, revisited, shared*.
Capture is the Share Extension, organising is Browse, sharing is coming — and
revisiting was the one verb with no surface. Nothing in the app ever said "you
saved eleven things last month and opened none of them", which is the single
most useful sentence a bookmark app can say and precisely the sentence platform
bookmarks never say, which is why they are write-only graveyards. The tab is six
stacked sections — saved this week, what you keep opening, **saved and never
opened**, a month ago, side quests with steps left, what's shifting — each
hidden when it has nothing to show, ordered by how likely they are to send
someone back into their library rather than by how clever they are. Under ten
borks it is one warm card naming what the sections will be, because six empty
headings is not an empty state.

It reads only what was already on the device: `openCount` and `lastOpenedAt`
have been recorded since 1.0 — that was their entire purpose — so the tab has a
history to show on the day someone updates rather than starting blank.

**Every section is a value, not a view.** `Revisit.build` is a pure function
over plain structs (`Core/Revisit.swift`), and `Core/RevisitSource.swift` is the
only file where it meets `Bookmark` and `Mission`. Two reasons, one of them
immediate:

1. Every section here is a perfectly good paragraph of a weekly digest — "you
   saved 14 things, 11 of them you never opened, a month ago you were reading
   about X". Computing it inside a SwiftUI view means writing it all again the
   day that ships. A digest built server-side from Postgres rows writes a second
   adapter and reuses every line of the computation.
2. It is testable in two seconds (`Scripts/test_revisit.swift`) against a fixed
   `now`, which is the only honest way to check date windows. Three of them are
   subtle: "a month ago" is a 28–35 day *window* because an exact 30-days-ago
   lookup is empty most days and reads as broken; "never opened" needs a week of
   age before it means anything, because not opening something the afternoon you
   saved it is normal; and "what's shifting" compares *share* of saves rather
   than counts, or a quiet month reads as "less of everything".

The view builds the model off the main actor and never blocks the tab switch —
on a large library the sections arrive a frame later rather than the dock
hanging.

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

**Custom topics on the web are derived from ids, not synced.** There is no
`custom_topics` table on the server: on iOS a `CustomTopic` is a SwiftData row
with a name, a hue and its art, and all that ever reaches the server is a
`bookmarks.category_id` of the shape `custom.<slug>`. So the web reads the topic
back out of the id — `makeTopicID` is a verbatim port of `CustomTopic.makeID`
(so a topic invented on either platform lands on one id and merges), and
`customTopicName` runs it backwards. Three things are lost and each is
deliberate rather than accidental: punctuation in the name ("Hair & grooming"
comes back "Hair grooming"), the hue (hashed onto the same grid of 7° steps
`CustomTopic.nextHue` walks, minus the ones a built-in sits on — the phone's
answer depends on creation order, which the server doesn't keep), and any topic
with nothing filed under it (which the Browse hint says out loud: "Topics appear
here once something is filed under them"). **A real `custom_topics` sync table —
name, hue, order, tombstones, LWW like `bookmarks` — is the fix, and it is the
right next step for both platforms**: it would give the phone rename/delete
across devices and give the web the name as typed.

**Custom topics are installed into `TOPIC_BY_ID`, not held beside it.** The
phone does exactly this — `MergedTaxonomy.init` calls
`Taxonomy.installCustomTopics` — and it is why one lookup change fixes every
call site at once: cards, chips, the search blob, search scopes, the Library
pills, `docs/revisit.js` (which reads the global at call time) and the quest
form all resolve a custom id without knowing custom topics exist. `TAXONOMY`
itself stays the shipped 50, so the picker and the quest form still list the
built-ins as a group, and the model's answer from `categorize` is still checked
against `BUILTIN_IDS` rather than "every topic we happen to know".

**Browse's three segments share one sort, and one set of labels.** Topics,
Sources and Side quests each get *Most borks · Most recent · A–Z*, because it is
the same three questions on each of them, and answering "how is this list
ordered" three different ways would make Browse look like three screens. The
ordering itself is `BrowseSort` in `docs/browse.js` — a port of
`Core/BrowseSort.swift`, entry for entry — so a chip cannot come to mean
something different on the two platforms; the labels are asserted in both test
suites for the same reason. The choice persists per segment
(`bm.browseSort.<segment>`): picking A–Z once to find a platform should not
permanently reorder the topic grid. Every branch that cannot decide falls
through to `rank`, the list's own canonical order — taxonomy order, `PLATFORM`
order, newest quest — so a grid of equal-count topics does not reshuffle on
each redraw, and the answer does not depend on the order the rows arrived in.

**One consequence, deliberately taken: "Most borks" now ranks your topics by
their borks like any other.** The first custom-topics pass put every built-in
before every custom one. That grouping cannot survive a chip that claims to
order by count — a topic of yours with eleven borks sitting below a built-in
with one is not "most borks" — and the phone has always mixed them. So the
grouping now lives only in `rank`, where it decides ties, and A–Z mixes them
alphabetically exactly as `MergedTaxonomy` does.

**The topic page opens with the tile you tapped, not with a line of text.** The
old header meant every topic page looked like every other topic page and none of
them looked like the tile that got you there. The hero band is the tile's own
composition at full width. Two details are load-bearing: the name and count sit
on the topic's tint *below* the art rather than over it — nothing then depends
on the contrast of a generated scene we cannot predict, and a long name grows
the band instead of overflowing a fixed image — and the band is deliberately
compact (120px, 96px on a phone), because the thing a topic page is for is the
borks, and the first one has to stay above the fold at 390×700.

**Sharing a topic is two different jobs, so it is two options.** *Share links*
is for someone who is going to tap them; *Share as image* is for a story or a
group chat, where nothing is tappable and the only job is to look like something
worth asking about. The message is `TopicShare` in `docs/browse.js`, the same
port as the phone's, and its rules are the interesting part: titles only and
never body text (an Instagram "title" is the whole caption), ten of them newest
first, a count line that says how many there really are, and links shortened
only where shortening leaves a link that still works — a query string carrying
the identity, a fragment, or a path too long to fit prints in full instead,
because a truncated URL is not a link and the entire point is that the other
person can tap it.

**The share card is rendered when the page opens, not when the button is
pressed.** A share sheet that stalls on an image is worse than one that only
offers a link, so the canvas runs on arrival and the image option appears once
it exists — the same thing `TopicPage` does with `ImageRenderer`. It is laid out
in the app's points and multiplied by three to 1080×1350, which is the 4:5 every
feed crops least, so the two cards are one design rather than two that rhyme.
The art is loaded `crossorigin="anonymous"` (the public `topic-art` bucket sends
the header and `/img` is ours); a scene that cannot be read falls back to the
tint band rather than tainting the canvas. Where `navigator.share` cannot take
files the PNG opens in a tab with a line about long-pressing it, and where there
is no share sheet at all the message goes to the clipboard — the point is that
every browser can do *something*, not that every browser does the same thing.

**"+ New topic" opens the Add sheet, not a bare naming dialog.** On the phone,
creating a topic from Browse inserts a row that persists on its own. On the web
a topic is only a `category_id`, so a name with nothing filed under it survives
exactly as long as the tab does. Rather than pretend otherwise, the Browse tile
opens the sheet that makes it real — Add, with the picker on top and the name
field already focused — so naming a topic and filing the first thing into it is
one gesture. The picker's own "+ Add a topic" row keeps the phone's copy and the
phone's behaviour: select, expand, stay open.

**A link you already have replaces the sheet, and never re-files itself.** The
Add sheet used to accept a duplicate all the way to "Bork it" and then refuse
it with one red line, *"Already in your library."* — a form filled in twice for
nothing, and no answer to the only question worth asking, which is where the
first one went. The moment the pasted link parses, `borks.get(stableID(url))`
is checked and a live match swaps the preview, "Sorted for you", the tags, the
quests, the title and the note for one card: the bork's own cover and title,
its topic in the topic's own colour, and when it was saved. "Bork it" stands
down; **Open it** hands over that bork's editor, which is where filing is
changed, and **Save again anyway** goes down the ordinary save path. A
tombstoned match is a new link again, the same rule `saveAdd` already used.

Two deviations from the brief, both about what "runs the existing save path"
should mean. (1) *The sheet is seeded from the bork you already have* —
its topic, subtopic, tags, note, title and picture — and the offline filer and
the model are both stood down for that link (`source: "user"`, which is true:
a person chose that filing). Without it the save path would happily write back
whatever the filer had just guessed for the URL, so "Save again anyway" could
silently move a bork out of the topic you had put it in. `Core/Store.save`'s
contract is that a second save *enriches a link in place* and never replaces
it, and this is how the web keeps that promise. `body_text` — which no control
on this sheet writes — is carried across for the same reason. (2) *No preview
is fetched for a duplicate.* There is nothing on the card that a fetch would
fill in, and letting one land would overwrite a title someone had written by
hand with the platform's SEO version. `saved_at` does move to now, so you land
on the bork at the top of the Library rather than on a wall where nothing
appears to have happened. `bork_added` gains `duplicate: true`, and only when
true, so existing events keep their exact shape.

**The picker ranks a topic's own name above a topic that only matched through
a subtopic.** Typing "runn" used to list Fitness — which merely has a *Running*
in it — above the person's own topic called Running, because the sheet listed
the shipped 50 first and put a "Your topics" heading in front of the rest. A
group heading can only ever put all of one kind above all of the other, so with
a query the two run together in one ranked list and every row keeps its "yours"
badge to say which is which; with nothing typed the heading comes back, because
there is nothing to rank by and fifty rows need the split to scan. The rule is
`TopicPickerQuery.order` in **`docs/picker.js`**, a port of
`Core/TopicPickerQuery.swift` with iOS 1.1.1's tiers — 2 a name match, 1 a
subtopic-only match, 0 no match — then exact, prefix and anywhere-else inside a
tier, then A–Z. *What* matches is unchanged: subtopics are still token-prefix
only, so "run" still never drags Gaming in through Speedruns. Its own file for
the reason `browse.js` and `revisit.js` are theirs — `Scripts/test_picker.mjs`
runs the ranking in node, and `fold` moved there so the page and the tests fold
identically. The auto-expanded row is now simply the first one, which is the
row you were about to tap, and "Add topic “runn”" moves below the matches when
there are any: a list a search returns should start with what the search found.

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

## Topic art

The 50 built-in topics each ship a bundled `topic{Id}` imageset, so Browse is a
wall of clay scenes. A topic you add yourself cannot have one — nobody bundles a
picture for "Looksmaxxing" before someone types it — so `TopicMotif.asset(for:)`
resolved to a name with no imageset, `ClayArt` fell back to paper, and the tile
read as a bug sitting next to Marketing and Health. **So the server draws it:**
`topic-art` renders one scene per custom topic, once, into a public bucket, and
the URL lands on `CustomTopic.imageURLString` to render through the same
`AsyncImage` path as a bookmark cover.

**Generated, not picked from a set.** Side quests take the opposite decision —
`QuestMotif` resolves a free-form title onto one of ten fixed scenes, because a
quest is a sentence and there are unbounded sentences. A topic is a noun the user
chose and will see on a tile forever, and the style guide is explicit that no
scene is ever shared between two topics. Ten reused scenes would put the same
clay heart on Juice and Looksmaxxing.

**Edit from the locked master, don't generate free.**
`Branding/ILLUSTRATION_STYLE.md` requires new scenes to be `image_edit`ed from
`questRabbit` because independent generations drift off the style. The function
does that, and falls back to a plain generation only when the master can't be
fetched — a slightly-off scene beats a blank tile, and it's the only path where
drift is possible.

**One AI key, not two.** The drawing goes through OpenRouter's Image API on the
same `OPENROUTER_API_KEY` as categorise and name-quest, rather than a second
credential for `api.openai.com`. The model is still `openai/gpt-image-1` and the
reference image still rides along as the edit source — OpenRouter routes to the
same endpoint — so scenes drawn before and after the switch match, which is the
only thing the style lock actually cares about. A second key would have been one
more secret to rotate for no difference in the picture.

**The spend ledger is the point of the table.** Unlike categorise and name-quest,
each call here costs real money for an artefact that is kept forever, so
`topic_art_begin` is a claim taken under `select … for update` *before* the model
is called, not a cache read afterwards. Two devices, a double tap and a retry
loop collapse onto one generation; three failures give up permanently; a
per-account cap bounds a client that invents topics in a loop. The daily AI quota
is consumed on top of all that.

**Art can never block a topic.** The phone inserts its `CustomTopic` locally and
returns before it ever calls out — creating a topic is offline-first like
everything else. Every failure (signed out, offline, quota spent, `OPENROUTER_API_KEY`
not deployed, model refusing the name) returns `{ url: null }` and leaves the tile
as paper, which is exactly what it looks like today. Browse asks for a few missing
scenes per appearance, oldest first, rather than firing fifteen generations the
first time someone with a lot of topics opens the tab.

**Both platforms now.** This was iOS-only while the web app's Browse filtered
everything through `TOPIC_BY_ID`, the fixed taxonomy. The web has custom topics
as of `web/custom-topics` and calls the same function on the same contract —
`{id, name}` in, `{url, reason}` out, three per Browse render, stamped whether
or not it worked. Two differences, both because a tab is not an app: it retries
after an hour rather than a day (a browser is reloaded far more often than an
app is launched, and `topic_art_begin` refuses to spend twice regardless), and
it reads `public.topic_art` over REST on every pull, so a scene drawn on the
phone appears on the web without generating anything. That read needed no new
grant: 0010's `own topic art is readable` policy and the default `select` on
public tables already allow it.

---

## Your own topics, impossible to miss — and whose initial that is

**Three offers, because one was never found.** The picker offered "Add a
topic" exactly once, as the first row of the list, and the first outside
tester filed everything under Fitness › Running because he never saw it. He
could not have: the sheet opens scrolled to the topic that is already picked
(`scrollToExpanded`, anchor `.top`), which is precisely where the first row is
not. `TopicPickerSheet` now offers it three ways. With nothing typed, a card
at the top — "Make your own topic — Anything you like: Foot mobility, Van
life, Sourdough" — says what a topic can be, which the row never did. A
footer pinned under the list (`safeAreaInset`, so it also rides above the
keyboard) says "New topic" wherever you have scrolled to, and "Add topic
“Van life”" once you have typed one. And a search that matches nothing is no
longer a hint under an empty list: it is the add itself, named, one tap —
with "Use “Van life” as a subtopic of Fitness" under it when a topic is open
or picked, which is where the web already put it. Browse's "New topic" tile
moves from the end of the grid to the front, with the same "Anything you
like" line, because the end of the grid is also one scroll away.

**Named adds create; unnamed adds ask.** "Add topic “Van life”" — from the
empty state or the footer — makes the topic on the spot (`addTopic`, which
already folds a name onto an existing built-in or custom topic instead of
doubling it) and opens it, the way "Use “x” as a subtopic" always did. It
used to open the name alert with the name filled in: a second tap to confirm
what the button had just said. "New topic" and "Add a subtopic", with no name
to go on, still ask through the existing `.alert` — kept because it is what
was there, not because it is the app's look; a designed name sheet is a
follow-up.

**Every new surface copies one that exists.** The picker card and the Browse
tile are the topic tile's tint and the suggested-quest card's dashed edge
(`QuestCard(dashed:)`); the footer is the dashed "Add a note" / "New side
quest" affordance in accent ink; "+ Add a subtopic" and "Use “x” as a
subtopic" are the dashed capsule chips from the Add sheet's side-quest row,
in the topic's own palette, under its pills instead of as a line of small
text. The web mirrors all four with the same tokens; its footer is
`position: sticky` inside the list, and its named add still opens the inline
name field with the name filled in, because a one-tap create there needs a
click handler in a region another PR of this round owns.

**Whose initial.** `LibraryView`'s header avatar was `Text("J")` — the
founder's initial, shipped to every phone, signed in or not. `Core/Initials`
is now the one rule both avatars use: the display name's first letter or
digit, else the email local part's, uppercased, one grapheme ("ß" is "S",
"🦊 Sam" is "S", "élodie" is "É"); `nil` signed out, and `nil` draws a neutral
`person.fill` in the same circle. iOS has no display name yet, so it passes
`nil` and the email decides; the parameter is there so a profile name lands in
one place when it arrives. The web's `initial()` already did this and is
untouched.

**Deliberately not done.** The ranking (`TopicPickerQuery`) is unchanged —
the problem was visibility, not order. No custom name sheet to replace the
two alerts. Nothing about what "Just Fitness — no subtopic" does.

---

## Sharing a topic

**A share is an invitation, not an archive.** The first version pasted up to
fifty `title` + `url` pairs using whatever the share extension had captured as
the title — which for Instagram is the entire caption. In Messages that lands
as a wall of text nobody reads. `Core/TopicShare.swift` sends ten instead,
newest first, **titles only** (a bork's `text` — an X thread's body, an IG
caption — cannot reach the message at all), a count line saying how many there
really are, "+ N more" for the rest, and one line pointing at
`bookmarker.lol/get`. Someone who wants all four hundred can install the app;
that is what sharing one is for.

**Shortened only where shortening keeps the link alive.** Links read as
`instagram.com/reel/abc` — scheme and `www.` dropped, which data detectors
still linkify. A URL whose identity is in its query (`youtube.com/watch?v=…`),
or one too long to fit, prints whole instead. Plain text has no display
strings, so a truncated URL is not a shorter link, it is a dead one, and the
entire value of a share is that the other person can tap it. The image card,
where nothing is tappable, uses the ellipsised form.

**And a picture, because half of sharing isn't links.** `TopicShareCard`
renders the band, the name and the first six titles as a 1080×1350 4:5 card
through `ImageRenderer` — the version that goes in a story or a group chat,
where a list of URLs is the wrong object entirely. Two items on the one button:
links for someone who will tap them, a picture for someone who will look.

---

## The signed-out save limit

**Twenty live borks without an account** (`Core/SaveLimit.swift`). Signed in
there is no limit and none of it applies.

**Why a limit at all.** The app has always worked signed out and the You tab
has always said the library lives only on this phone. People did not know: the
tab a happy user never opens is where that sentence lived. 1.0.2 added a
Library banner and a milestone sheet (`SignInNudge`), which made the fact
visible without making it land — someone with four hundred borks and no account
still loses all four hundred with the phone, and still can't open
bookmarker.lol and find anything. The limit is the first version of that
sentence that has consequences.

**Why twenty.** Twenty is past *trying it* — you have borked from three apps,
watched it file things, found one again — and short of the point where losing
the library would actually hurt. A limit that bites at two hundred arrives
after the damage it exists to prevent; one that bites at five arrives before
the app has shown what it does. The countdown starts at fifteen, which is
roughly a week of use in hand.

**Why waiting instead of refusing.** *Saving must always be instant and a save
is never gated* is the core product rule (`CLAUDE.md`), and it is not
negotiable — so the limit gates the twenty-first **slot**, never the act of
saving:

- The **Share Extension is untouched**. It writes its JSON draft to the App
  Group inbox in the same few milliseconds, over the top of Instagram, knowing
  nothing about the library. It cannot fail on a limit it never reads.
- A draft that drains over the limit is **saved as a real `Bookmark`** and
  flagged `waitingSince`. It is in the Library, greyed, with a "Waiting" pill,
  and it can be opened and deleted like anything else. It is held out of
  Browse, search, topic counts and the stats line, and never pushed to the
  server. Signing in admits every one; a delete admits the oldest first.
- The only place anything is refused is the **Add sheet and the + button**,
  where a person is in the app, looking at the screen, and can read a sheet.

Refusing the share instead would have meant a toast in an extension the user
has already dismissed, or worse, a silent drop — the one failure this
architecture was built to make impossible (see *Share Extension writes to an
inbox* above).

**Why signed-in is unlimited.** Because that is the offer, and an offer with an
asterisk is not one. A cap behind the sign-up would make the sign-up a lie and
the limit a toll rather than a reason.

**The privacy line is a promise the code keeps.** The wall says *"Your borks
are always private. Never sold, never shared, never visible to anyone else."*
That is checkable, not marketing: `bookmarks` rows are owner-scoped by RLS
(`supabase/migrations/0001_init.sql`), there is no sharing feature to leak them
through — the friend feed is schema-only and deliberately unwired — and there
is no analytics SDK in the app at all. If any of those three change, that
sentence has to change with them, and `Scripts/test_save_limit.swift` asserts
its exact wording so it cannot drift quietly.

**Deviations from the brief, and why.**

- *"Make room instead" was specified to show a toast reading "Swipe a bork to
  delete it."* There is no swipe-to-delete, on the masonry feed or the compact
  list — deleting is a tap into a bork and the bin in its footer. Shipping copy
  that names a gesture the app does not have would send someone swiping at a
  card until they gave up, which is worse than the wall it was trying to
  soften. The toast reads **"Open any bork and tap the bin to make room"**.
  Building swipe-to-delete was out of scope and would have been a second
  feature smuggled in under a toast.
- *The Library card and the wall were specified to read "20 borks on this
  phone".* They count the **real** library instead, so someone who signed out
  of an account holding thirty-four sees thirty-four. At exactly twenty the
  rendered string is identical to the brief's; over it, printing "20" would
  have the app arguing with the screen behind it.
- *The milestone sheet's 25 and 100.* Both are now unreachable signed out, so
  as sign-up prompts they are dead code. They survive as **signed-in backup
  reminders, and only when the account has never once synced** — the one case
  where a signed-in library is still in the danger the account was supposed to
  remove. When the backup is working, which is the normal case, both are
  skipped entirely.

**Known limitation.** A library that is *over* the limit — someone who signed
out of an account holding more than twenty — can view everything and add
nothing until they sign back in or delete down under twenty. Viewing is never
blocked, and deleting is the same delete as always. Re-saving a soft-deleted
bork also resurrects it past the limit rather than re-queuing it as waiting;
that is a one-tap edge case and the limit is a save gate, not a hard ceiling on
what may be on screen.

---

## The Add sheet (build 13)

**The paste card is a system `PasteButton` over a `Transferable` that accepts
both a URL and text.** The card used to be `PasteButton(payloadType:
String.self)`, and it showed three different faces after copying a link out of
Instagram or X: a working button, no button, and a greyed-out one. All three
are the control matching the pasteboard's *content types* against the declared
payload. "Copy link" in a number of apps writes a `public.url` item and no
plain-text item, which a `String` payload does not match, and the control
re-evaluates asynchronously, which is the third face. `PastedLink` declares an
importing `ProxyRepresentation` for each, so both match; the URL is then pulled
out of whatever arrives by one pure function with its own test.

**It stays a system control.** A custom `Button` that reads
`UIPasteboard.general.string` is what produced "bookmarker would like to paste
from…" on every tap. iOS grants the system paste control the same access with
no dialog, so the control is not negotiable and the payload type is the only
thing that could be fixed.

**The card exists only when there is a link to paste** — gated on `hasURLs`,
then `hasStrings`, then `detectPatterns(for: [.probableWebURL])` for text that
might have a link inside it. None of the three exposes a byte of the value, so
none of them raises the banner; the pasteboard is still never read. It is
re-asked on `scenePhase == .active` as well as on `UIPasteboard.changedNotification`,
because that notification only fires for changes this process can see, and
coming back from Instagram is the case that matters. An empty pasteboard is
still `hasStrings == true`, which is why the pattern check is the last word
rather than the first.

**Saving a link you already have now says so.** `Store.save` has always merged
a repeat save into the existing bork rather than making a second one, which is
what `stableID` is for — but the sheet gave no sign, so a link you saved a
month ago and filed by hand came back, got re-categorised by the guesser, and
merged silently. The sheet now looks the id up before it shows the form and
offers the bork instead: where it is filed, when it was saved, **Open it** (the
same `DetailSheet` as the Library, where the filing can be changed) and **Save
again anyway**. That second button keeps the existing bork's topic rather than
the guess for the link, because a re-save is not a re-filing. A tombstoned
match is not a duplicate: deleting a bork and saving it again is a new save.
The Share Extension is deliberately unchanged — one tap over someone else's
app, no screen to ask on, and merging silently is the right answer there.

**The topic picker ranks name matches above subtopic matches.** `matchRank`
already scored them (0 name token/prefix, 1 name contains, 2 subtopic) and
`shown` threw the score away and sorted A–Z, so typing "runn" listed Fitness —
which has a Running subtopic — above the user's own topic called Running. The
list is now ordered by rank and then A–Z within each tier, the auto-expanded
row is the first one rather than the first subtopic hit, and "Add topic “runn”"
moved below the matches, since offering to make a second topic with a name you
already have is not the first thing to read. Being a custom topic is not a
tier: yours and the built-ins are ranked by the same rule.

---

## Custom topic ids fold to ASCII (build 13)

`CustomTopic.makeID` kept any character Unicode calls a letter, so "Café
culture" was stored as `custom.café-culture` — while `TopicArt.isCustomID`, the
`topic-art` function's `TOPIC_ID` and the web's `ART_ID` all require ASCII. The
topic could never be sent for art and sat as blank paper, and because the web
derives its whole idea of a custom topic from `bookmarks.category_id`, the two
platforms disagreed about which topic a bork was in. The slug now lives in
`TopicArt.customID`, beside the check it has to satisfy: NFD, drop combining
marks, lowercase, everything still outside `[a-z0-9]` becomes a separator.
`makeTopicID` in `docs/index.html` is the same three steps in the same order —
spelled out with `normalize("NFD")` and `\p{M}` rather than ICU folding, so the
two are one algorithm rather than two that agree on the cases someone tried.
One table of names and ids is duplicated between `Scripts/test_topic_art.swift`
and `Scripts/test_browse.mjs` to hold them together.

**Deviation: a hash tail when the fold loses letters.** Folding alone maps every
name with no Latin in it — Chinese, Cyrillic, Greek, Arabic — onto the empty
slug and therefore onto one id, and `CustomTopic.id` is `.unique`: a Russian
speaker's second custom topic would silently overwrite their first. So when a
letter or digit is lost, eight hex digits of FNV-1a over the folded name are
appended. Unreadable, deterministic, identical in both languages, and drawable.

**Migration.** `Store.foldCustomTopicIDs` re-keys topics, their subtopics and
their borks on launch. It runs every launch rather than once behind a flag: it
is idempotent by construction (a folded id folds to itself), and the case that
keeps happening is a bork syncing down from an account whose other device is
still on the old build, long after any one-time flag was set. Two topics that
fold onto one id merge, oldest keeps the id. A bork carrying a custom id with
no topic row behind it — which is everything the web sends — is repaired from
its own slug.

## Shared collections

The recipient's half: `bookmarker.lol/c/<slug>` — a page a stranger opens, and
the backend that answers it. `supabase/migrations/0011_shared_collections.sql`,
`supabase/functions/collection-page/`, `cloudflare/`. Nothing in the client
creates a collection yet; that is PR 2.

**The model is server-authoritative, and the RPC is the only anonymous door.**
0001 imagined sharing as a widening of row-level security: mark a collection
`public` and let the policy hand out the rows. That was the wrong shape twice
over. It made *every* signed-in account able to read *every* public collection
through PostgREST — `GET /rest/v1/collections?select=*` was a directory of
everything anyone had ever shared, and `collection_items` plus 0001's additive
bookmarks policy made it a directory of the contents — and it could not serve
an anonymous reader at all, which is the only reader that matters for a link
you send to a friend. So the public branch is gone from
`can_view_collection`, `anon` is revoked on all three tables, and the single
way in is `collection_by_slug(text)`: security definer, given a slug, returning
one fixed JSON shape. The shape is the policy. There is no query string a
caller can build to widen it, no column it forgot to exclude, and nothing to
enumerate — a wrong slug, a revoked link and a deleted collection all return
`null`, so the page cannot be asked whether a collection exists.

**`public` means "anyone with the link", not "published".** The slug is twelve
characters of `[a-z0-9]` from `gen_random_bytes` — 36¹² ≈ 4.7 × 10¹⁸, the whole
security model of an unlisted link, which is why it is a CSPRNG and not
`random()` or the name. The page sends `robots: noindex`. Nothing lists it.
This is the one place the ROADMAP's framing is deliberately not followed: it
calls a shared collection "an SEO asset", and indexing someone's curated links
under their display name is not a thing to do to people by default. Making a
collection indexable is a switch we can add when someone asks for it; making
one *un*-indexed after Google has it is not.

**Turning the link off keeps the slug.** `visibility = 'private'` is the link
off; the slug stays on the row, so turning sharing back on restores the same
URL instead of orphaning every copy of it already sent. The trade is explicit —
an old link starts working again when the owner re-enables it — and someone who
wants a permanently dead link deletes the collection.

**A leak in 0001, found while wiring this up.** The policy "own collection
items writable" checked that you owned the *collection* and never that you
owned the *bookmark*. Since a bookmark's id is its normalised URL, any signed-in
account could save the same reel, learn the id, insert `(a-stranger's-uuid,
that-id)` into a collection of its own, and read the stranger's row back —
`note_text` included — through the additive "bookmarks visible through shared
collections" policy. `bookmark_owner = auth.uid()` is now required on write,
and `collection_by_slug` refuses to serve an item whose owner is not the
collection's owner regardless, so a collection assembled before the fix cannot
leak through the new page either. The one `for all` policy is now three, split
by command: a `for all` policy is how four commands get widened by someone
thinking about one.

**Both caps are triggers, and that is not a style choice.** The obvious home
for "at most 200 items in a collection" is the policy's `with check`, and
Postgres refuses it: a policy on `collection_items` that counts
`collection_items` re-enters the table's own policies and every insert dies
with `infinite recursion detected in policy for relation "collection_items"` —
including the legitimate ones, and with an error that names recursion rather
than the cap, which masked the leak fix above until the probe found it. So 200
items per collection and 100 collections per account are `after` triggers,
where the new row is there to be counted and `security definer` means the count
is the real one.

**Why Cloudflare.** The page has to be server-rendered at a `bookmarker.lol`
URL, because the thing that decides whether a shared link gets tapped is the
card Messages and X draw for it, and every link scraper reads the HTML the
server returned and runs no JavaScript. GitHub Pages cannot proxy, rewrite or
render. The alternatives were pre-rendering each collection into
`docs/c/<slug>.html` — which makes a stale page the default and turns "turn the
link off" into a deploy — or moving the whole site to another host to add one
route. A Worker on the free plan changes nothing else about the site and is
reversible by putting the nameservers back. `cloudflare/README.md` is the
runbook; until it is run, `docs/404.html` fetches the same function from the
browser, so links work for people today and only the unfurls wait.

**The page trusts none of its own data.** Every string on it — the name, the
note, a title, an author, a URL, a thumbnail host — was written by the person
who made the collection, so `_shared/collection_html.ts` escapes every
interpolation, emits an `href` only for plain http(s) (a saved `javascript:`
URL renders as a card you cannot click), and renders an `<img>` only for hosts
known to serve permanent thumbnails. That last one is stricter than the "our
storage bucket" the brief asked for and stricter than "any https image" would
be: without it a collection could be assembled to make every viewer's browser
call a host of the owner's choosing. Instagram and TikTok covers are absent
from that list because everything those CDNs hand out expires — 0008 already
mirrors them into our own bucket, which is on it. The page's CSP is the
backstop, with a per-response nonce, which is why there is not one inline
`onerror` or `style=` attribute in the file. The image-error listener lives in
the `<head>` for a reason found by looking: at the end of the body it is
registered after the covers have already failed, and the reader gets Chrome's
broken-image icon instead of the topic gradient.

**What it measures.** One event, `collection_viewed {items}`, with
`persistence: 'memory'` — no cookie, no localStorage, no replay, no
autocapture, no pageview, no `identify`. A viewer arriving from someone else's
link is not someone to give an identity to; the only question worth asking is
whether shared links are opened at all.

**Copies, not references.** `collection_save` inserts the collection's live
borks into the caller's own library — `on conflict do nothing`, so tapping
twice adds nothing, and `note_text` starts empty because the curator's note is
theirs. The copies carry `source_collection_id` and survive the collection
being deleted or turned off. A bork the saver had previously deleted stays
deleted rather than being resurrected by somebody else's link.

**One thing this PR knowingly leaves wrong.** `Core/SaveLimit.swift` promises
*"Never sold, never shared, never visible to anyone else"*, and
`Scripts/test_save_limit.swift` asserts that wording so it cannot drift
quietly. It is still true today — nothing in the client can create a
collection, and a collection is private until its owner turns a link on — but
the sentence has to change in the PR that ships the sharing UI, along with the
App Store copy that repeats it. Shipping the change now would make the app
claim a feature it does not have.

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
