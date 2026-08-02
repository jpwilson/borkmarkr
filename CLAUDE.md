# Claude Code Instructions — borkmarkr

Native iOS app: save any link from any social app, categorise it, find it later.
SwiftUI + SwiftData, no backend. Sibling of `OFS_iOS/` and follows the same
XcodeGen conventions.

## Vision

The problem: people like thousands of posts across IG / X / TikTok / Shorts /
Pinterest and can never find any of them again — untitled, unorganised,
unsearchable, and locked inside each app. borkmarkr is the cross-app layer:
**Share → borkmarkr** saves it with a source, a category, tags and an optional
dated note.

Saving must ALWAYS be instant. Organising is optional and can happen later —
never gate a save behind categorisation. This is the core product rule.

## Critical rules

- **Never edit `.xcodeproj` directly.** Edit `project.yml`, then
  `xcodegen generate`. The project file is generated and committed.
- **`Core/` compiles into BOTH targets** (app + ShareExtension). Anything the
  extension needs must live there, not in `App/`.
- **App Group `group.com.jpwilson.borkmarkr` is the contract** between the app
  and the extension. Both open the same SwiftData store through it. Break that
  and shared saves silently vanish into two separate databases.
- **ShareExtension's bundle ID must stay nested** under the app's
  (`com.jpwilson.borkmarkr.ShareExtension`) or the embed step fails the build.
- **`DEVELOPMENT_TEAM` goes in `project.yml`**, not Xcode's UI — the UI value is
  wiped on every regeneration.
- `Bookmark.stableID` is content-derived URL normalisation and is what stops
  duplicates. Changing its rules changes bookmark identity — existing saves
  would orphan. Treat it as a migration if you touch it.
- `Categorizer` is advisory by contract. Every caller must let the user override
  the result before saving.

## Build & verify

```bash
xcodegen generate
xcodebuild -project borkmarkr.xcodeproj -scheme borkmarkr \
  -destination 'id=<simulator-udid>' -configuration Debug build CODE_SIGNING_ALLOWED=NO
```

`Core/Platform.swift` and `Core/Categorizer.swift` are pure Foundation, so they
can be compiled and exercised on macOS directly with `swiftc` — useful for
checking categorisation changes without booting a simulator.

## Status (2026-08-01)

- Scaffolded and building. Runs in the Simulator; all five tabs render.
- Share Extension implemented (URL + plain-text-with-link paths, caption used as
  title, auto-categorised, marked unread) — **not yet exercised on a device**,
  which is the next thing to verify.
- Categoriser verified against 6 real-world URLs; platform detection and URL
  dedupe confirmed correct.
- Not built yet: link preview/thumbnail fetching, iCloud sync, first-run
  onboarding, the full several-hundred-category taxonomy (16 shipped).
- Design source of truth: Claude Design project
  `542ac055-8bda-4d8e-8b0e-54b1339cf778` (`borkmarkr.dc.html`, 28–29 Jun 2026).
  Its expansion round — onboarding, full taxonomy, share-sheet explainer, accent
  variants — was cut off mid-session; the share-sheet explainer and accent
  variants are built here, onboarding and full taxonomy are not.
