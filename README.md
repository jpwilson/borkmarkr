# bookmarker

Formerly borkmarkr; identifiers keep the old name on purpose.

One place for everything you save from everywhere.

You see something worth keeping on Instagram, X, TikTok, YouTube Shorts,
Pinterest or a plain website — you like it, and it disappears into a pile of
ten thousand other likes you can never search. bookmarker is the layer on top:
tap **Share → bookmarker**, and it's saved, categorised, and findable.

Native iOS app. SwiftUI + SwiftData, no backend, no account, no network calls.

## What's here

| Screen | What it does |
|---|---|
| **Feed** | Everything you've saved, newest first. Big cards or compact list. Filter by source. |
| **Add** | Paste a link → source detected, category/subcategory/tags suggested (all editable) → optional dated note → save. |
| **Explore** | Category tiles → drill into subcategories → share a whole collection. |
| **Search** | Live filtering across titles, tags, notes, people, URLs, plus source and category filters. |
| **Detail** | Full item, breadcrumb, tags, editable dated note, open original / share / delete. |
| **You** | Stats, where your saves live, and the accent / density / starting-tab knobs. |
| **Share Extension** | The important one. Save from inside any app without switching to this one. |

## Build

```bash
xcodegen generate          # after ANY edit to project.yml — never edit .xcodeproj directly
open borkmarkr.xcodeproj
```

To run on a real device or ship to TestFlight, set your Team ID in
`project.yml` under `settings.base.DEVELOPMENT_TEAM`. Putting it there means it
survives `xcodegen generate`; setting it inside Xcode gets wiped on every
regeneration.

Requires Xcode 26+, iOS 17+.

## How it fits together

`Core/` compiles into **both** the app and the Share Extension. That's what lets
the extension write a save that the app sees instantly — both open the same
SwiftData store inside the App Group `group.com.jpwilson.borkmarkr`.

- `Bookmark.swift` — the model. Everything except the URL is optional, because
  saving must never be blocked by organising.
- `Store.swift` — the shared container plus insert-or-update. Falls back to a
  local store if the App Group isn't provisioned yet, so a fresh clone still
  runs in the Simulator.
- `Platform.swift` — source detection from the URL host.
- `Taxonomy.swift` — 16 categories with subcategories. Add one by appending to
  `Taxonomy.all`; no view code changes.
- `Categorizer.swift` — keyword scorer over the URL slug and title. Offline,
  instant, and always a *suggestion* you can override.

### Deduplication

The same post shared from two places is one bookmark. `Bookmark.stableID`
normalises the URL — lowercases the host, strips `www.`/`m.`, drops tracking
params (`utm_*`, `igshid`, `si`, `s`, `fbclid`, …), removes trailing slashes —
so `x.com/foo/status/1?s=20` and `www.x.com/foo/status/1/` collide correctly.

## Known limits

- **No link previews.** Titles come from the share sheet's caption text or the
  URL slug. Real thumbnails would need per-platform work: Instagram's Basic
  Display API was deprecated, X's API is paywalled, and scraping breaks their
  terms. oEmbed covers YouTube and a few others and is the sensible first step.
- **Categorisation is keyword-based, not a model.** It does well on descriptive
  slugs and captions, and returns nothing rather than guessing wildly when a
  link is opaque. Swapping in something smarter means replacing
  `Categorizer.suggest(...)` only.
- **No sync.** Local device storage. iCloud via CloudKit is the natural next
  step and SwiftData supports it with little change.
- Sharing a collection produces plain text, which pastes cleanly anywhere but
  isn't a live shared list.

## Origin

Designed in Claude Design on 28–29 June 2026 as `borkmarkr.dc.html` — a mobile
prototype covering seven flows. This repo is the native build of that design.
An earlier, unrelated X-only prototype lives at `SGTG/x_bookmarks`.
