# RUNBOOK-1.3 — taking 1.3 live

1.3 (build 17) is Quick File, the redesigned web library, the AI judging every
save, the Pro interest check, PostHog on every page and Langfuse on every AI
call. The order below keeps the 1.2 app on people's phones working at every
step. DECISIONS.md has the reasoning for each piece.

## 1. The website (goes live about a minute after the merge)

1. Merge `feat/quick-file` into `main`. GitHub Pages serves `main:/docs`.
2. Check:
   - https://bookmarker.lol/pro/?plan=yearly shows Yearly picked and "Pro isn't on sale yet".
   - https://bookmarker.lol/privacy has the section "Checking the AI's work".
3. Visit https://bookmarker.lol/?internal=1 once on each of your own browsers
   and phones, so your visits and taps don't count.

## 2. Supabase (project `pcjuxnhqxyfvgagnblzv`)

The Supabase CLI on the build Mac is signed into a different account, so use a
personal access token from the account that owns bookmarker (Supabase →
Account → Access Tokens) for each command, without changing the CLI login:
`SUPABASE_ACCESS_TOKEN=<token> supabase …`.

### 2.1 Langfuse

Dashboard → Edge Functions → Secrets:

| Name | Value |
| --- | --- |
| `LANGFUSE_PUBLIC_KEY` | `pk-lf-…` |
| `LANGFUSE_SECRET_KEY` | `sk-lf-…` |
| `LANGFUSE_BASE_URL` | `https://cloud.langfuse.com` (EU) or `https://us.cloud.langfuse.com` (US), matching the keys' region |

Set them only after step 1, because the privacy page that discloses the log
goes live with the website. The secrets do nothing until 2.3.

### 2.2 Share keys (migration 0018)

In the SQL editor:
1. Run `select count(*) from auth.sessions;`. It must return a number. If it
   says permission denied, stop and use the fallback at the end of
   `Scripts/test_share_keys_sql.md`.
2. Paste all of `supabase/migrations/0018_share_keys.sql` and run it. Running
   it twice is harmless.
3. Run blocks 2–7 of `Scripts/test_share_keys_sql.md`, one at a time. The
   probes that write end in `rollback`.

### 2.3 Deploy the functions

From the repo root:

```
SUPABASE_ACCESS_TOKEN=<token> supabase functions deploy categorize --project-ref pcjuxnhqxyfvgagnblzv --no-verify-jwt
SUPABASE_ACCESS_TOKEN=<token> supabase functions deploy insights --project-ref pcjuxnhqxyfvgagnblzv
SUPABASE_ACCESS_TOKEN=<token> supabase functions deploy name-quest --project-ref pcjuxnhqxyfvgagnblzv
SUPABASE_ACCESS_TOKEN=<token> supabase functions deploy quest-brief --project-ref pcjuxnhqxyfvgagnblzv
SUPABASE_ACCESS_TOKEN=<token> supabase functions deploy topic-art --project-ref pcjuxnhqxyfvgagnblzv
```

`categorize` needs `--no-verify-jwt` because the share sheet calls it with a
share key and no JWT; its quota checks are the gate. Leave the other
functions (preview, thumb, notify, delete-account, collection-page) alone.

### 2.4 Check

- Save a link while signed in. Within a minute, Langfuse → Tracing shows a
  `categorize` trace with tokens and cost. If nothing appears, look for
  `langfuse 401` in Supabase → Edge Functions → categorize → Logs (wrong keys
  or the wrong region).
- The curl checks and the phone checks in `Scripts/test_share_keys_sql.md`.

## 3. The App Store

1. Upload build 17, either from Xcode (Window → Organizer → the 1.3 (17)
   archive → Distribute App → App Store Connect) or with
   `xcodebuild -exportArchive` and `destination = upload`.
2. App Store Connect → bookmarker → add version **1.3**:
   - What's New: APPSTORE.md, "What's New in 1.3".
   - Build: 1.3 (17), once it has finished processing.
   - App Review Information → Notes: APPSTORE.md's notes paragraph, which now
     describes the Pro interest check. Apple requires every feature to be
     described there.
   - Submit for Review.
3. App Privacy needs no change: the app collects nothing new, and it opens
   /pro in Safari. Langfuse is server-side and sends no account details.
   Decide whether the description's "No analytics" line still reads right to
   you.

There are no in-app purchases in 1.3. Pro is an interest check: no App Store
Connect products, no Paid Apps agreement, no Stripe.

## 4. Reading the numbers

- **Visitors:** PostHog (us.posthog.com) → Web analytics.
- **Pro interest:** PostHog → a Trends insight on `pro_plan_chosen`, broken
  down by `plan` and by `from` (`app-milestone`, `app-you`, `web-you`,
  `web-milestone`), counting unique users. `pro_reserved` counts emails left.
- **Pro emails:**
  `select source, count(*) from public.beta_signups where source like 'pro-%' group by 1;`
  A repeat email keeps its first source, so someone already on the list shows
  up only in PostHog.
- **AI:** Langfuse → Tracing, filtered by name (`categorize` and the others),
  with the cost OpenRouter reports.
