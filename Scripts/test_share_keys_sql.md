# Probes to run after `0018_share_keys.sql`

A share key is a credential, so it has to be checked by *trying it*: that it
works once issued, that nobody but `categorize` can spend it, and that it
stops working with its session. These are the probes, in the order worth
running them, with the answer each one must give.

Every one of them has already been run on a scratch PostgreSQL 15 with
Supabase's roles reproduced (a `postgres` that is not a superuser and can only
read `auth.sessions`, plus `anon`, `authenticated` and `service_role`, with
pgcrypto in `extensions`), after `0002` and then `0018` twice. They are here
so they can be run again against the real database.

## Running them

In the Supabase SQL editor, which runs as `postgres`. Paste and run each block
on its own: the editor shows only the last result, and stops at the first
error. Every block that changes anything is wrapped in `begin … rollback`.

Replace `<your uuid>` with your account's id (Authentication → Users), and use
an account that is signed in on a phone. `auth.uid()` and `auth.jwt()` read
`request.jwt.claims`, the way PostgREST hands them a token, so this statement,
which opens several blocks below, makes you your newest session (the phone's,
if it refreshed last):

```sql
select set_config('request.jwt.claims',
         json_build_object('sub', s.user_id, 'role', 'authenticated', 'session_id', s.id)::text, true)
  from auth.sessions s where s.user_id = '<your uuid>'
 order by s.updated_at desc nulls last limit 1;
```

---

## 0. Postgres can read the sessions

Run this before the migration.

```sql
select count(*) from auth.sessions;
```

**Expect:** a number. If it says `permission denied for table sessions`, stop
here and don't apply 0018: every key check would fail closed, so the share
sheet would get no answers through a key and nothing would change for anyone.
The fallback is at the end.

## 1. Apply it, twice

Paste all of `supabase/migrations/0018_share_keys.sql` and run it. Then run it
again.

**Expect:** success both times. The second run only notes that `share_keys`
and its index already exist.

## 2. Only the server can spend a key

```sql
select has_function_privilege('anon',          'public.share_key_issue()', 'execute')                 as anon_issues,
       has_function_privilege('authenticated', 'public.share_key_issue()', 'execute')                 as user_issues,
       has_function_privilege('anon',          'public.ai_quota_consume_shared(text,int)', 'execute') as anon_spends,
       has_function_privilege('authenticated', 'public.ai_quota_consume_shared(text,int)', 'execute') as user_spends,
       has_function_privilege('service_role',  'public.ai_quota_consume_shared(text,int)', 'execute') as server_spends,
       has_table_privilege('anon',             'public.share_keys', 'select')                         as anon_reads,
       has_table_privilege('authenticated',    'public.share_keys', 'select')                         as user_reads;
```

**Expect:** `false, true, false, false, true, false, false`. Then try them, one
line at a time:

```sql
begin; set local role anon;          select public.share_key_issue();                          rollback;
begin; set local role anon;          select public.ai_quota_consume_shared(repeat('0', 64));   rollback;
begin; set local role authenticated; select public.ai_quota_consume_shared(repeat('0', 64));   rollback;
begin; set local role authenticated; select count(*) from public.share_keys;                    rollback;
```

**Expect:** `permission denied for function share_key_issue`, then `permission
denied for function ai_quota_consume_shared` twice, then `permission denied for
table share_keys`. Denied, not `false` or `0`. A signed-in user may be issued a
key but can never spend one: only `categorize`, with the service role, can.

```sql
begin; set local role authenticated; select public.share_key_issue(); rollback;
```

**Expect:** `ERROR: sign in first`. No token, no key.

## 3. A key works, and only its hash is kept

```sql
begin;
  select set_config('request.jwt.claims',
           json_build_object('sub', s.user_id, 'role', 'authenticated', 'session_id', s.id)::text, true)
    from auth.sessions s where s.user_id = '<your uuid>'
   order by s.updated_at desc nulls last limit 1;
  set local role authenticated;
  select set_config('probe.key', public.share_key_issue(), true);
  reset role;
  select set_config('probe.calls', coalesce((select calls from public.ai_usage
           where user_id = auth.uid() and day = (now() at time zone 'utc')::date), 0)::text, true);
  select set_config('probe.spent', public.ai_quota_consume_shared(current_setting('probe.key'))::text, true);
  select length(current_setting('probe.key'))                                as key_length,
         current_setting('probe.spent')                                      as real_key,
         (select calls from public.ai_usage
           where user_id = auth.uid() and day = (now() at time zone 'utc')::date)
           - current_setting('probe.calls')::int                             as quota_used,
         public.ai_quota_consume_shared(repeat('0', 64))                     as unknown_key,
         public.ai_quota_consume_shared(upper(current_setting('probe.key'))) as in_capitals,
         public.ai_quota_consume_shared('x')                                 as malformed,
         (select count(*) from public.share_keys
           where key_hash = extensions.digest(decode(current_setting('probe.key'), 'hex'), 'sha256')) as stored_hashed,
         (select count(*) from public.share_keys
           where encode(key_hash, 'hex') = current_setting('probe.key'))    as stored_plain;
rollback;   -- ROLLBACK. Committing replaces the phone's own key, and its share sheet gets no answers until the app issues another.
```

**Expect:** `64, true, 1, false, false, false, 1, 0`. A 64-character key; it
spends one call of today's quota, on the same counter as every other AI call
the account makes; an unknown key, the same key in capitals and a malformed
one are all refused; and the table holds the key's SHA-256, never the key.

## 4. A key dies with its session

Signing out deletes the session's row, so a key for a session that has no row
is a key after sign-out.

```sql
begin;
  select set_config('request.jwt.claims',
           json_build_object('sub', '<your uuid>', 'role', 'authenticated', 'session_id', gen_random_uuid())::text, true);
  set local role authenticated;
  select set_config('probe.key', public.share_key_issue(), true);
  reset role;
  select public.ai_quota_consume_shared(current_setting('probe.key')) as ended_session;
rollback;
```

**Expect:** `false`.

## 5. A new key replaces the old one

What the app does every 30 days.

```sql
begin;
  select set_config('request.jwt.claims',
           json_build_object('sub', s.user_id, 'role', 'authenticated', 'session_id', s.id)::text, true)
    from auth.sessions s where s.user_id = '<your uuid>'
   order by s.updated_at desc nulls last limit 1;
  set local role authenticated;
  select set_config('probe.first', public.share_key_issue(), true);
  select set_config('probe.second', public.share_key_issue(), true);
  reset role;
  select public.ai_quota_consume_shared(current_setting('probe.first'))  as first_key,
         public.ai_quota_consume_shared(current_setting('probe.second')) as second_key,
         (select count(*) from public.share_keys
           where session_id = (auth.jwt() ->> 'session_id')::uuid)       as keys_for_session;
rollback;   -- ROLLBACK, for the same reason as 3.
```

**Expect:** `false, true, 1`. One key per session, and the old one stops
working at once.

## 6. Keys for ended sessions are cleared out

```sql
begin;
  select set_config('request.jwt.claims',
           json_build_object('sub', '<your uuid>', 'role', 'authenticated', 'session_id', gen_random_uuid())::text, true);
  set local role authenticated;
  select public.share_key_issue();
  reset role;
  select set_config('request.jwt.claims',
           json_build_object('sub', s.user_id, 'role', 'authenticated', 'session_id', s.id)::text, true)
    from auth.sessions s where s.user_id = '<your uuid>'
   order by s.updated_at desc nulls last limit 1;
  set local role authenticated;
  select public.share_key_issue();
  reset role;
  select count(*) as keys_for_ended_sessions
    from public.share_keys k
   where k.user_id = '<your uuid>'
     and not exists (select 1 from auth.sessions s where s.id = k.session_id);
rollback;   -- ROLLBACK, for the same reason as 3.
```

**Expect:** `0`. Each new key sweeps away the account's keys whose sessions
are gone, so the table never holds more than one row per live session.

## 7. Deleting the account deletes its keys

```sql
select confdeltype = 'c' as cascades_with_the_account
  from pg_constraint
 where conrelid = 'public.share_keys'::regclass and contype = 'f';
```

**Expect:** `true`.

---

## Then the function

From the repo root, without changing which account this machine's CLI is
logged into:

```sh
SUPABASE_ACCESS_TOKEN=<owner personal access token> \
  supabase functions deploy categorize --project-ref pcjuxnhqxyfvgagnblzv --no-verify-jwt
```

JWT verification must now be off for `categorize` (`config.toml` says so too):

```sh
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/categorize' \
  -H 'Content-Type: application/json' -d '{"title":"Sourdough needs 24 hours #baking"}'
```

**Expect:** `200`. A `401` means it is still on: turn it off for `categorize`
in the dashboard (Edge Functions → categorize → Details) or deploy again with
`--no-verify-jwt`.

```sh
curl -s 'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/categorize' \
  -H 'apikey: sb_publishable_z0wBO4NZrMW3T0ZywSDfJA_UoFRHMKb' -H 'Content-Type: application/json' \
  -d '{"url":"https://x.com/someone/status/1","title":"Sourdough needs 24 hours #baking"}'
curl -s 'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/categorize' \
  -H 'apikey: sb_publishable_z0wBO4NZrMW3T0ZywSDfJA_UoFRHMKb' -H 'Content-Type: application/json' \
  -H 'x-share-key: 0000000000000000000000000000000000000000000000000000000000000000' \
  -d '{"url":"https://x.com/someone/status/1","title":"Sourdough needs 24 hours #baking"}'
```

**Expect:** `{"topic":null,"subtopic":null,"tags":[],"confidence":"low","reason":null}`
both times, and today's `ai_usage.calls` unchanged. No token and a wrong key
are both no answer, and neither reaches the model. The app and the web still
get answers: their path is unchanged.

## Then the phone

With a build that has the share key, signed in:

```sql
select k.session_id, k.created_at, k.last_used_at, s.updated_at as session_refreshed
  from public.share_keys k
  left join auth.sessions s on s.id = k.session_id
 where k.user_id = '<your uuid>';
select calls from public.ai_usage
 where user_id = '<your uuid>' and day = (now() at time zone 'utc')::date;
```

1. **Issued.** Open the app once (or sign in). **Expect:** one row with a
   `session_refreshed`.
2. **Asked.** Force-quit bookmarker and leave it closed for more than an hour
   (overnight is better), then share a post with a caption from X or Threads.
   **Expect:** the dial re-deals within about three seconds, `last_used_at`
   moves, and `calls` goes up by one. In a DEBUG build,
   `-quickFileShare <url> -quickFileShareKey` asks with the key on demand.
3. **Signed out.** Sign out in the app, then share. **Expect:** no answer, and
   the row's `session_refreshed` is empty. Sign back in: the new key's row
   replaces it, with a session.
4. **Signed out on the web.** Once `docs/index.html` is live, sign out on
   bookmarker.lol. **Expect:** the phone's row keeps its session, and shares
   keep getting answers.

---

## If `postgres` can't read `auth.sessions`

Then 0018 as written refuses every key, harmlessly. The fallback drops both
`exists` checks and adds a `share_key_revoke()` that the app calls when it
signs out. That needs an app change as well, and a sign-out anywhere else no
longer ends the key, so it is a decision, not a quick edit.
