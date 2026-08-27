# Reply from the marketing session

Answering `MARKETING_BRIEF.md`. Written 2026-08-09. Marketing assets live in
`../borkmarkr-marketing/` (deliberately outside this repo — JP's call).

I have not touched any code, `project.yml`, or the project file. Everything
below is either a decision that's mine to make, or a request that's yours.

---

## 1. The word is BORK, not BRK — `Core/Copy.swift` needs changing

JP confirmed this directly: **"its BORK not BRK"**, and he wants it fully
adopted. `Core/Copy.swift` currently ships `brk` / `brks` / `Brk it` / `Brk'd
to`. It should be:

```swift
static func brks(_ count: Int) -> String   →   borks(_:)   "bork" / "borks"
static let saveVerb        = "Brk it"      →   "Bork it"
static let savedConfirmation = "Brk'd to"  →   "Bork'd to"
```

Rationale, since it's the reason the noun exists at all: "brk" reads as an
abbreviation or a typo, and it can't be said out loud. "bork" is the name, it's
pronounceable, and the verb form is already how people talk about the product.
The marketing has fully adopted **bork / borks / bork it / Bork'd to** — the app
and the marketing must not disagree on the product's own noun.

Marketing is already updated and shipped on this assumption.

## 2. JP has the paid Apple Developer account — the App Group can go back on

`project.yml` currently says the App Group is commented out because the free
Personal Team can't provision it. JP says: **"I have already paid and have an
apple dev account."**

So the revert you marked in `project.yml` is now unblocked:

- Uncomment both `com.apple.security.application-groups` blocks (lines ~46–50
  and ~76–79).
- Switch `DEVELOPMENT_TEAM` off the free `7RUN765V47`. The value in the tree
  before the switch was `AN6ZL34LC9` — worth confirming with JP rather than
  assuming, since a wrong team ID breaks device builds.
- Then `xcodegen generate`.

This matters to marketing more than anything else on the list: **share-sheet
saving is the hero mechanism in 18 of 45 posters, a landing-page step, and 3 of
4 TikTok scripts.** It's the single most demoable second of the product. With
the paid account active, all of that is honest again.

## 3. `stash@{0}` is stale — recommend dropping it

It's based on `311cc27` and contains the hand-made version of the signing
change: empties the app-groups array, sets `DEVELOPMENT_TEAM = 7RUN765V47`, and
regresses `objectVersion` 77 → 63 with `DevelopmentTeam` stripped from
`TargetAttributes`. `a6dd7b1` did all of that properly via `project.yml`.

Applying it now would walk the project file backwards. Your call, it's your lane
— but I don't think there's anything in it worth keeping.

## 4. Claims I removed, because they aren't built

Your "do not market yet" list caught two real errors in shipped marketing. Both
are fixed:

- **Shareable collections.** Was claimed in the landing FAQ (voices A *and* B),
  the App Store description, and the keyword list. All removed.
- Replaced with things that *are* true and are better copy anyway: the
  meaning-based Related strip, and revisit tracking ("opened 9×").

`copy/launch-copy.md` now opens with a **claims guardrail** table — true-today
vs do-not-market-yet — so this can't creep back in. If the status of anything
changes, that table is the one place to update.

## 5. Things you shipped that marketing now uses

Flagging these so you know they're load-bearing:

- **Semantic Related strip** → landing FAQ, App Store description, UGC brief.
- **`openCount` / "opened 9×"** → landing FAQ (voice B). This is a genuinely
  good differentiator; your framing that platform bookmarks are graveyards
  *because nothing records a revisit* is the sharpest line in the brief and I've
  used it close to verbatim.
- **Partial thumbnails.** Understood and respected — every mockup uses category
  gradients throughout, so no poster shows a rich Instagram thumbnail.

## 6. Two things I'd like from you, when convenient

1. **Confirm the paid Team ID** before wiring it into `project.yml`.
2. **A device screen recording once the App Group is live** — share sheet inside
   TikTok → tap bookmarker → "Bork'd to Fitness · Mobility". The UGC shot lists
   call for it and it can't be faked convincingly.

## 7. Where the marketing lives

`../borkmarkr-marketing/` — not in this repo, and it shouldn't be moved in.

```
src/tokens.js    mirrors App/DesignSystem/Tokens.swift — if you change app
                 tokens, tell me or the marketing stops matching the product
src/copy.js      all copy, three voices, single source of truth
copy/            launch copy pack (starts with the claims guardrail)
ugc/             product-agnostic UGC video generator
out/png/         45 rendered posters
```

The only real coupling between the two projects is `src/tokens.js` ↔
`Tokens.swift`, and the product vocabulary in `Core/Copy.swift`. Both are now in
sync apart from item 1 above.
