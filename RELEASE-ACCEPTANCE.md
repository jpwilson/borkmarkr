# Repair stack release acceptance

## What is complete versus what is live

The twelve modules are code changes on review branches, not a production
release. No production database, DNS, Edge Function or App Store build was
changed in this implementation pass. No billing, pricing, paywall or
gamification was added. The native Library above/through Side quests remains
the existing design; changes to its lower feed focus on containment and use.

## Deployment sequence (authorized operator)

1. Back up the database and verify migrations through 0012 are present.
2. Apply 0013 quest sync, 0014 custom taxonomy, 0015 open signals, 0016
   enrichment provenance/CAS, and 0017 public collection taxonomy, in order.
   Do this before main publishes clients that require those columns/RPCs.
   They are additive; do not drop the new columns when rolling clients back.
3. Deploy `quest-brief` and `collection-page`; preserve `verify_jwt=false`
   only for the public collection endpoint, not authenticated AI functions.
   Old brief clients can read the new response, but have titles-only inputs.
4. Merge PRs in [stack order](REPAIR-STACK.md) using merge commits. Retarget each
   next PR to main after its predecessor merges. Do not merge into a pending
   predecessor branch. Squash/rebase merges require restacking dependents.
5. Coordinate the `/c/*` Worker route separately with the domain owner. See
   [the routing runbook](cloudflare/README.md). Do not change nameservers or
   disable origin TLS validation as an incidental app-release step.
6. Produce a new signed iPhone build with an unused build number and verify
   both app and extension provisioning/App Group. Build 14 on the owner's
   physical phone was reviewed earlier; it does not contain this repair stack.

## Verified locally

- All `Scripts/test_*.mjs` suites, including legacy Browse (126), import (263),
  picker (44), Revisit (46), tag recency (20), and collection renderer (124).
- PostgreSQL-engine tests: quest revisions/tombstones, custom metadata and
  owner isolation, per-device open counters, preview compare-and-swap races,
  public collection expiry/revocation/field allowlists. Isolated PGlite, never
  the production database.
- Native simulator XCTest: 10 tests, 0 failures. Includes SwiftData roundtrips,
  legacy data/provenance, artwork, per-device opens, brief fingerprints and
  single-note sharing. Standalone brief and topic-sharing tests also passed.
- Debug app/extension build and Release simulator build.
- Browser demo at 390×844 and 1280×900: Library hierarchy, search-to-Browse,
  list→selection→grid retains the selected item, no horizontal page widening,
  selection toolbar clears the dock, combined subtopic/source filters.
- Local synthetic authenticated fixture: Profile on mobile/desktop, quest
  creation entry, search finding the 60th bookmark, attach/save, unavailable AI
  state, and single-share note excluded by default and removed when unchecked.
  The fixture is **not** proof of production authentication or cloud parity.
  Reproduce with `node Scripts/preview_web_fixture.mjs`, then visit its printed
  localhost URL and use the documented fixture email/code. No real emails,
  credentials or API writes leave that server.
- Prior native UI stress pass: 269 synthetic saves, list/grid and selection.
  The owner's exact physical-device overflow was not reproduced independently.

## Required before calling the release fixed

| Journey | Acceptance |
| --- | --- |
| Fresh web account | No save before sign-in, then save one URL; reload and see it once. Confirm email delivery on real auth. |
| Signed-out iPhone | First 20 usable saves; next save requires sign-in. Incoming extension shares are retained as waiting, never silently lost. Sign-in admits/syncs waiting items. |
| Instagram and X capture | On a physical iPhone, host share menu → system sheet → bookmarker saves promptly; cancel/retry and relaunch do not duplicate or hang. A host-controlled first row cannot be promised. |
| Existing owner library | 266+ mixed saves; long titles/tags; both densities; select 0/1/many; rotate; scroll to last card; large accessibility text; no overlap or horizontal page drift. |
| Quest parity | Existing phone quests appear on web; rename, steps, attachment, empty quest, archive/delete and offline retry converge both ways. A custom topic with zero bookmarks also appears, with its exact name. |
| Revisit parity | Open originals on each device; return and refresh. Counts accumulate without clearing notes or filing. Legacy counters may overlap where old installations independently recorded the same history; verify owner totals. |
| AI | Use real retained excerpts, thin title-only sources and an empty quest. Inspect relevance, source support, unavailable/quota/offline states and retry. Automated prompt/shape checks are not a live model-quality evaluation. |
| Enrichment | Existing manual titles/topics/tags/notes stay unchanged; missing captured content fills when available. Interrupted work resumes; unavailable sources stop after bounded retries. |
| Single share | Preview original URL, title, topic/subtopic and tags; note only after opt-in. Inspect received Messages/WhatsApp output, not only the composer. |
| Collection link | Active raw HTTP 200 with actual OG metadata; revoked/deleted/expired reveal no items within the cache window. Recipient opens originals and sees taxonomy/tags without an account. Large app CTA remains. |

Do not use private review screenshots or the owner's saved content as public
test fixtures. Do not announce deployment success based only on merged code.
