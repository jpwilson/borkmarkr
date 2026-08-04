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
