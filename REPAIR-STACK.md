# September 2026 repair stack

Owner-approved scope: preserve the native Library through Side quests, preserve
search-to-Browse and its three segments. No billing, paywall, or gamification.
Web library requires sign-in; iPhone allows 20 live saves without an account.
Shared incoming links are never silently discarded.

## Merge sequence

Each numbered branch is based on its predecessor so its PR contains only one
module. Merge in order; retarget the next PR to main after its predecessor is
merged. Do not merge a later branch into an unmerged predecessor.

1. Account rules (20-save native gate; explicit authenticated web saves).
2. Native feed containment and selection controls.
3. Recognizable content and consistent taxonomy on cards.
4. Search semantics and stable ordering.
5. Quest synchronization, including existing records.
6. Custom taxonomy synchronization.
7. Revisit cross-device state.
8. Responsive web Library and account design.
9. Quest editor, guidance, and artwork parity.
10. Source-grounded briefs and visible generation states.
11. Safe, resumable enrichment with preserved user decisions.
12. Public collection routing, recipient experience, release checks.

Backend migrations and functions are reviewed as code before deployment.
Do not equate a merged PR with a deployed or physically verified release.
Physical Instagram/X capture and the owner's exact layout regression remain
release acceptance checks even when helper tests pass.

## Verification

Each PR records its own tests and limitations. No production library fixtures
or private review screenshots belong in this repository.
