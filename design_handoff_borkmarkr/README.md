# Handoff: borkmarkr — universal social bookmark app (v2)

## Overview
**borkmarkr** is an iOS app that saves (bookmarks) any link from any social platform or website into one library, auto-files it into a **deep topic taxonomy** (category → subcategory → tags) plus the **source platform** it came from, supports dated personal notes, universal search, and shareable collections.

**The product's core idea — two browse axes that cross:**
1. **Topics** (deep taxonomy): Fitness → Mobility → #marathoners. Items in one topic come from many apps.
2. **Sources** (platform): everything saved from X, or TikTok, or Instagram…

Either axis can lead, and the *other* axis is always available as a secondary filter: a topic page has source chips ("From: All · TikTok · IG…"), a source page has topic chips. This dual-axis model is the spine of the IA — preserve it exactly.

## About the Design Files
`borkmarkr v2.dc.html` is a **working HTML prototype used as the design spec** — not production code. It runs on an in-house preview runtime (custom `<x-dc>`, `<sc-if>`, `<sc-for>`, `<x-import>` tags + a `DCLogic` class). **Do not port the runtime.** Read it as:
- Template markup (`<x-dc>…</x-dc>`) = exact structure, styling values, copy.
- `class Component extends DCLogic {…}` = the complete state model + interaction logic in plain JS. Read methods as pseudocode.

`ios-frame.jsx` and `support.js` exist only so the prototype renders; ignore both for implementation.

**Recommended stack** if none exists: React Native (Expo) or Flutter for a real iOS/Android app; React + Vite if a mobile-web PWA is acceptable for v1. Use real navigation, a real design-token/theme system, and real persistence.

## Fidelity
**High-fidelity.** Recreate colors, type, spacing, radii, and layout faithfully. Production deltas expected:
- **Add smooth transitions/springs** (tab changes, chip selection, sheet presentation). The prototype intentionally omits CSS transitions on reactive elements (preview-runtime limitation) — production should feel fluid, ~150–300ms, iOS-native easing.
- **Real thumbnails**: media covers are category-hued gradients standing in for real fetched preview images (see Integrations).
- **AI categorization is simulated** (`detectPreview()` keyword heuristics + ~950ms fake latency).

---

## Design Tokens

### Base
- App background (paper): `#F6F3EE` (warm near-white)
- Surface / cards: `#FFFFFF`; hairline border: `#EAE4DA`; lighter divider: `#F1EBE1`
- Muted control bg: `#EEE8DE`; segmented-control track: `#ECE6DC`; toggle-off / grabber: `#DBD2C4`; dashed borders: `#D7CDBD`
- Ink (primary text): `#191510`; secondary: `#6E655A`; tertiary/meta: `#A39A8D`; faint: `#C6BEB1`; body-on-white: `#332C23`; muted heading: `#8A8072`
- Dark button / selected filter pill: bg `#191510`, white text
- Destructive: `#C2545A`; toast success check: `#7BE3A4`; toast bg `#191510`
- Note (amber) block: gradient `#FFFBEA→#FFF5D8`, border `#F0E0AC`, icon bg `#FFE7A0`/`#FFEFC2`, text `#8A6D14`/`#5C4E25`/`#9A7B1A`

### Accent (user-selectable, 4 ramps)
| Name | `--ac` | `--ac-dk` | `--ac-tint` | `--ac-deep` |
|---|---|---|---|---|
| Coral (default) | `#FF5A2D` | `#E8451C` | `#FFE7DE` | `#AE3512` |
| Violet | `#7C5CFC` | `#6A47F0` | `#ECE7FF` | `#5538C9` |
| Blue | `#2E8CF0` | `#1F77D6` | `#E2F0FF` | `#1E66B8` |
| Green | `#1FA971` | `#178A5C` | `#DFF4EA` | `#147A52` |

Picked in onboarding, persisted, applied app-wide as theme variables (primary buttons, FAB, active tab, active accents, tint washes).

### Category color system (24 hues)
Each category has a `hue` (H). Derive:
- chip/tile tint: `hsl(H, 55%, 92%)`
- deep text on tint: `hsl(H, 46%, 31%)`
- **media cover gradient**: `linear-gradient(155deg, hsl(H,52%,44%), hsl(H,60%,22%))` + overlay `radial-gradient(90% 60% at 12% 0%, rgba(255,255,255,.16), transparent 60%)` + bottom scrim `linear-gradient(180deg, transparent 30%, rgba(10,6,2,.52))`
- category dot: `hsl(H, 50%, 52%)`

### Platform brand (badges + source-page headers)
| key | Name | Badge label | Badge style | Source header gradient |
|---|---|---|---|---|
| x | X | X | `#0F1014`/white | `#17181D→#000` |
| instagram | Instagram | IG | gradient `#7B3FE4→#DB2E7A 55%→#FF7A3D`/white | same gradient |
| tiktok | TikTok | TT | `#0D0E12`/`#5CE8E4` | `#17181D→#000` |
| youtube | YouTube | YT | `#CC1B2B`/white | `#B3121F→#5E0A12` |
| shorts | Shorts | SH | `#D5202F`/white | `#C11723→#5E0A12` |
| pinterest | Pinterest | PIN | `#B8121F`/white | `#A50F1B→#4E070D` |
| threads | Threads | TH | `#141416`/white | `#1B1B1E→#000` |
| web | Web | WWW | `#48505C`/white | `#3E4550→#20242B` |

Badges are small rounded squares (18–26px, radius 6–9) with 7.5–12px/800 labels. **Status bar must switch to light content on dark source-page headers** (prototype passes `dark` to the device frame; in iOS use `preferredStatusBarStyle` / SwiftUI `.toolbarColorScheme`).

### Typography
- **Display**: `Bricolage Grotesque` (Google Fonts) 500–800 — wordmark, large titles (32px/800/-0.8), sheet titles (18–19/700), stat numbers (23–24/800), tile counts, onboarding headlines (28–31/800), detail title (20/700), article-card headlines (14.5/600).
- **Body/UI**: `Instrument Sans` 400–700 — everything else. Card titles 13.5/600, body 13–15, chips 10–13/600–700, meta 10.5–12/500, eyebrows 10/800/uppercase/+0.6 tracking.
- **Mono**: `ui-monospace, Menlo` — share URL, pasted-link mock.

### Shape & depth
- Cards 18–20px radius; category tiles 20; sheets 30 (top corners); buttons 16–17; chips/pills full; FAB 17; masonry media cover top-only rounding (card is 20 with overflow hidden).
- Card shadow: `0 1px 2px rgba(25,21,16,.03), 0 10px 28px -14px rgba(25,21,16,.10)` (media cards slightly stronger).
- Floating tab dock: inset 14px sides/bottom, height 64, radius 24, `rgba(255,255,255,.88)` + 20px blur + hairline border, shadow `0 18px 44px -12px rgba(25,21,16,.30)`.
- FAB: 50px, accent, raised −24px above dock, 3px paper-colored border, shadow `0 8px 20px rgba(ac,.45)`.
- Accent button shadow: `0 8px 20–22px rgba(ac,.32–.34)`.
- Sheet presentation: slide-up 0.3s `cubic-bezier(.22,1,.36,1)` + scrim `rgba(20,15,10,.46)` fade 0.25s. Toast: rise+fade 0.26s.

---

## Taxonomy (24 categories, ~230 subcategories)
Seed data — copy the `CATS` array verbatim from the prototype (`key`, `name`, `hue`, `subs[]`). Categories: Fitness(150), Health(352), Wellness(270), Food(36), Sports(210), Money(168), Learning(246), Home & DIY(26), Tech(192), Funny(46), Beliefs(300), Travel(200), Style(326), Parenting(130), Work(232), Business(178), Art & Design(8), Music(284), Gaming(258), Nature(100), Pets(18), Relationships(338), News(220), Science(186). Health is deliberately deep (Conditions, Medications, Symptoms, Sleep, Mental health, Gut health, Heart & BP, Diabetes, Pain relief, Women's/Men's/Kids' health, Dental, Skin, Immunity, Supplements).

**Level 3 = tags**: freeform lowercase tags act as the third taxonomy level (e.g. Fitness › Mobility › `#marathoners`). Topic pages surface the most-common tags of the current subcategory as "Refine" chips (show tags with ≥2 items, top 6).

## Data model
```
SavedItem {
  id, platform: <platform key>, title, author,      // author = handle or hostname
  cat: <category key>, sub: <subcategory>, tags: string[],
  date: 'YYYY-MM-DD',                               // date saved
  kind: 'clip'|'reel'|'short'|'video'|'thread'|'pin'|'article'|'post',
  dur: 'M:SS' | '',                                 // non-empty == video
  text: string,                                     // post body for X/Threads text posts
  note: { text, date } | null
}
Collection { name, cat, count, vis }                 // vis: 'Public link'|'N people'|'Private'
```
Prototype ships 26 seed items + 4 collections as sample data.

## Content-native card system (the visual signature)
The Library feed is a **2-column masonry** of cards whose form follows the content type:
- **Text post** (X/Threads, has `text`): white card — platform badge + author, up-to-6-line snippet, footer: category chip + relative date + note dot.
- **Media cover** (TikTok clip / IG reel / Short = 200px tall; YouTube video = 118px; Pinterest pin = 176px; IG post = 148px): category-hue gradient cover, platform badge top-left, glassy duration pill top-right (videos), 3-line white title bottom, footer strip: subcategory chip + date + note dot.
- **Article** (web): white card — category dot + uppercase domain, Bricolage headline (3-line clamp), footer chips.

**Masonry ordering:** items alternate columns L,R,L,R (evens→left stack, odds→right stack) so reading order zigzags and recency holds at the top. Do NOT use CSS `column-count` (it fills columns sequentially and breaks recency).

**List view** (toggle): uniform rows — 58px gradient thumbnail (mini play for videos, "quote mark" tile for text posts), platform badge + author + date, 2-line title, "Category · Sub" chip + note marker.

## Screens
- **Library (Home)**: wordmark + avatar; large title "Your library" + live stats line ("26 saves · 8 apps · 14 topics"); search entry pill; source filter chips (All + per platform present) + masonry/list toggle; the feed; empty state per filter.
- **Browse**: large title + **Topics | Sources segmented control**.
  - Topics: 2-col grid of tinted tiles (count + "saves" + name in category deep color, decorative offset circle). Sorted: user's onboarding interests (with saves) first, then count desc. → Topic page.
  - Sources: rows per platform with saves — brand badge tile, name, "N saves · top categories", 3 mini cover swatches, chevron. → Source page.
- **Topic page**: tinted gradient header (back, dark Share pill, title + count), subcategory chips (All + present subs w/ counts), **"From" source chips** (cross-axis), **"Refine" tag chips** (appear when a subcategory is selected and ≥1 tag qualifies; dashed outline, selected = filled deep). List rows. Empty state. Share = shares the current slice as a collection ("Fitness › Mobility").
- **Source page**: full-bleed dark brand-gradient header (light status bar!), translucent back + count pill, brand badge + name + descriptor, **"Topic" chips** (cross-axis; each chip in its category tint). List rows (platform badge omitted — redundant).
- **Search**: large title, accent-bordered field, Source chips + Topic chips (multi-select toggles, both axes), live results ("N results") on any query/filter, recent-search chips when idle. Matches title, author, post text, category, subcategory, tags.
- **Item detail** (near-fullscreen sheet): text posts render the post (badge, author, full text); media/articles render a 200px cover (play + duration for video). Bricolage title, "author · Platform" line, **category chip (tappable → jumps to that Topic page)** › subcategory, tag chips, amber note block (or dashed add-note) with editable text + date, "Saved <date> · from <Platform>", footer: delete + "Open original".
- **Add sheet** (3 steps): paste (URL field, Fetch preview CTA disabled <4 chars, "Saving from another app? See how →", 4 sample links) → loading (spinner, "Reading the link…") → details (preview row, **"Sorted for you"** accent card with sparkle icon: Category › Sub pill (opens picker) + removable tags + inline "+ tag" input, optional dated note, "Save to borkmarkr"). Saves prepend to Library + toast "Saved to Category › Sub".
- **Topic picker sheet**: all 24 categories (tint dot, name, count, chevron) → expand subcategory pills → pick sets cat+sub.
- **Share sheet**: item or collection; preview row, "Anyone with the link" toggle + copyable `bork.mr/…` URL, "Send to" people avatars (multi-select accent ring), Copy link / Share now.
- **You**: avatar, name/handle, 3 stat cards (saved / topics / this week), Collections list (category-tinted bookmark icons, visibility), Help & setup: "Save from other apps" (how-to sheet), "Replay welcome tour".
- **How-to sheet**: mock iOS share sheet (IG reel row + share tray with borkmarkr highlighted) + numbered 3 steps + "Got it".
- **Onboarding** (first run, persisted flag; 4 steps + Skip): ① value prop (logo motif, "Everything you save, finally in one place.", 8 platform badges) ② share-sheet demo ③ "It sorts itself." (URL → Sorted-for-you card; copy mentions both axes) ④ "Make it yours." (accent swatches — selected = ring `0 0 0 3px paper, 0 0 0 6px accent` + 1.08 scale; 14 interest chips). Progress dots (active = 20px accent bar). "Get started" persists accent+interests.
- **Floating tab dock**: Library · Browse · [+ FAB] · Search · You. Active = accent; inactive `#A39A8D`.

## Interactions & rules
- Navigation state machine and every handler live in the prototype's `Component` methods (`openCat`, `openSrc`, `submitUrl`, `detectPreview`, `saveAdd`, `saveNote`, `deleteItem`, `openShare`, `finishOnboarding`…). One overlay at a time; scrim-tap dismisses; sheet inner taps don't.
- Cross-axis filters reset appropriately: opening a topic resets sub/source/tag; picking a subcategory clears the tag; opening a source resets its topic chip.
- Relative dates: Today / Yesterday / `Nd` (<7d) / `MMM D`; full `MMM D, YYYY` on notes.
- Interests (onboarding) float those categories to the top of Browse › Topics.
- Delete/copy/share/open-original show toasts in the prototype; wire real actions in production.

## Integrations to build for real
1. **OS share extension** (iOS Share Extension / Android intent) — the primary acquisition path; the in-app paste box is the fallback. Build early.
2. **Link unfurling**: OG/oEmbed metadata (title, author, thumbnail, duration, post text for X/Threads). Replace gradient covers with real thumbnails; keep the gradient as loading/fallback state.
3. **AI auto-categorization**: classifier (LLM) returns `{cat, sub, tags}` from URL + metadata; user can always override (keep the "Sorted for you" UX verbatim).
4. **Persistence & sync**: local-first store synced to cloud; accent, onboarded flag, interests, items, collections.
5. **Share backend**: real short links (`bork.mr/s/<id>`, `bork.mr/c/<slug>`) with visibility levels.

## Assets
No binary assets. All icons are inline SVG line icons; wordmark is a CSS bookmark glyph (needs a real logo eventually); fonts are Google Fonts (Bricolage Grotesque, Instrument Sans). Media covers are CSS gradients standing in for fetched thumbnails.

## Files in this bundle
- `borkmarkr v2.dc.html` — the full prototype/spec (all screens, tokens, copy, logic). **Primary reference.**
- `ios-frame.jsx`, `support.js` — preview-runtime scaffolding only; do not port.
