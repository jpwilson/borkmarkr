# September 2026 repair stack

Owner-approved scope: preserve the native Library through Side quests, preserve
search-to-Browse and its three segments. No billing, paywall, or gamification.
Web library requires sign-in; iPhone allows 20 live saves without an account.
Shared incoming links are never silently discarded.

## Merge sequence

Each numbered branch is based on its predecessor so its PR contains only one
module. Merge in order; retarget the next PR to main after its predecessor is
merged. Do not merge a later branch into an unmerged predecessor.
Use **Create a merge commit**, not squash/rebase, so ancestry remains intact.
If a predecessor is squash-merged, the dependent branches need restacking
before their diffs are clean. No PR in this stack has been merged by Codex.

Before merging PR 5 or later into an automatically published main branch,
apply backend migrations 0013–0017 in order through your normal deployment
process. These additive migrations work with the existing clients. Deploy
the updated quest-brief and collection-page functions before releasing their
new clients. See [release acceptance](RELEASE-ACCEPTANCE.md).

1. [#75](https://github.com/jpwilson/borkmarkr/pull/75) Account rules: 20-save native gate; authenticated web saves.
2. [#76](https://github.com/jpwilson/borkmarkr/pull/76) Native feed containment and selection controls.
3. [#77](https://github.com/jpwilson/borkmarkr/pull/77) Recognizable content and consistent taxonomy on cards.
4. [#78](https://github.com/jpwilson/borkmarkr/pull/78) Search semantics and stable ordering.
5. [#79](https://github.com/jpwilson/borkmarkr/pull/79) Quest synchronization, including existing records.
6. [#80](https://github.com/jpwilson/borkmarkr/pull/80) Custom taxonomy synchronization.
7. [#81](https://github.com/jpwilson/borkmarkr/pull/81) Revisit cross-device state.
8. [#82](https://github.com/jpwilson/borkmarkr/pull/82) Responsive web Library and account design.
9. [#83](https://github.com/jpwilson/borkmarkr/pull/83) Quest editor, guidance, and artwork parity.
10. [#84](https://github.com/jpwilson/borkmarkr/pull/84) Source-grounded briefs and visible generation states.
11. [#85](https://github.com/jpwilson/borkmarkr/pull/85) Safe, resumable enrichment with preserved user decisions.
12. [#86](https://github.com/jpwilson/borkmarkr/pull/86) Single-save sharing, public routing, recipient experience, release checks.

Backend migrations and functions are reviewed as code before deployment.
Do not equate a merged PR with a deployed or physically verified release.
Physical Instagram/X capture and the owner's exact layout regression remain
release acceptance checks even when helper tests pass.

## Verification

Each PR records its own tests and limitations. No production library fixtures
or private review screenshots belong in this repository.
