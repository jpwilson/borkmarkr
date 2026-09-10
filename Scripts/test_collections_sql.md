# Probes to run after `0011_shared_collections.sql`

A migration that closes a leak has to be checked by *trying the leak*, not by
reading the diff. These are the probes, in the order worth running them, with
the answer each one must give.

Every one of them has already been run — on a scratch PostgreSQL 15 stood up
from `0001` + `0004` + `0011`, with the production drift reproduced first
(`profiles.handle` nullable, no `avatar_hue`, no slug check, the
`on_auth_user_created` trigger present). They are here so they can be run
again, against the real database, after `supabase db push`.

## Running them

In the Supabase SQL editor (which runs as `postgres`, so `set local role` and
`set local request.jwt.claim.sub` are how you become somebody else). Each block
is wrapped in `begin … rollback` so nothing survives the probe.

```sql
-- Substitute two real account ids and a real public slug.
\set A  '<owner uuid>'
\set B  '<some other account uuid>'
\set S  '<a slug whose collection is visibility = public>'
\set P  '<a slug whose collection is visibility = private>'
```

`auth.uid()` on Supabase reads `request.jwt.claim.sub`, so:

```sql
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = '<uuid>';
  select auth.uid();          -- must echo the uuid back before you trust anything below
rollback;
```

---

## 1. Enumeration is blocked

The point of the migration. Before it, `GET /rest/v1/collections?select=*`
returned every shared collection on the service to any signed-in account.

```sql
begin; set local role anon; select count(*) from public.collections;       rollback;
begin; set local role anon; select count(*) from public.collection_items;  rollback;
begin; set local role anon; select count(*) from public.collection_grants; rollback;
```

**Expect:** `ERROR: permission denied for table …`, three times. Not "0 rows" —
denied.

```sql
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = :'B';
  select count(*) from public.collections;        -- only B's own
  select count(*) from public.collection_items;   -- only B's own
  select count(*) from public.bookmarks where owner_id = :'A';
rollback;
```

**Expect:** B sees only B's rows, and **0** of A's bookmarks — including the
ones in A's public collection. A link is not a publication.

## 2. The owner still sees their own

The fix must not have cost the owner anything.

```sql
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = :'A';
  select count(*) from public.collections;
  select count(*) from public.collection_items;
rollback;
```

**Expect:** A's real counts, unchanged.

## 3. The 0001 leak is closed

0001's `with check` never looked at `bookmark_owner`, so any signed-in account
could put *someone else's* `(owner_id, bookmark_id)` into its own collection —
and the additive "bookmarks visible through shared collections" policy would
then hand the row over, `note_text` and all. Bookmark ids are the normalised
URL, so the id is guessable.

```sql
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = :'B';
  insert into public.collections (id, owner_id, name)
    values ('bbbbbbbb-0000-0000-0000-000000000001', :'B', 'Mine');
  insert into public.collection_items (collection_id, bookmark_owner, bookmark_id)
    values ('bbbbbbbb-0000-0000-0000-000000000001', :'A', '<one of A''s bookmark ids>');
rollback;
```

**Expect:** the collection insert succeeds, the item insert fails with
`new row violates row-level security policy for table "collection_items"`.

> If this ever comes back as `infinite recursion detected in policy for
> relation "collection_items"`, something has put a `collection_items`
> subquery back into a `collection_items` policy. That is why both caps are
> triggers — see the comment in the migration.

## 4. Reading by slug works, and hands over only what it should

```sql
begin; set local role anon; select jsonb_pretty(public.collection_by_slug(:'S')); rollback;
```

**Expect:** the object — `id`, `name`, `note`, `owner_name`, `updated_at`,
`items` — ordered by `position` then `added_at`. Then the negative half, which
matters more:

```sql
begin; set local role anon;
  select public.collection_by_slug(:'S')::text like '%<a note only A can see>%' as leaks_note,
         public.collection_by_slug(:'S')::text like '%@%.%'                     as looks_like_an_email,
         public.collection_by_slug(:'S')::text like '%note_text%'               as leaks_the_column;
rollback;
```

**Expect:** `f`, `f`, `f`. Also confirm by eye that a soft-deleted bork
(`deleted_at is not null`) and any item whose `bookmark_owner` is not the
collection's owner are **absent** from `items`.

## 5. An unlisted link is silent

Missing, private, deleted and malformed are one answer. If they were not, the
page would be an oracle for "this slug exists but you may not have it".

```sql
begin; set local role anon;
  select public.collection_by_slug(:'P')          is null as private_is_null,
         public.collection_by_slug('zzzzzzzzzzzz') is null as missing_is_null,
         public.collection_by_slug('NOPE')         is null as malformed_is_null,
         public.collection_by_slug(null)           is null as null_is_null,
         public.collection_by_slug(''' or 1=1 --') is null as injection_is_null;
rollback;
```

**Expect:** `t` five times.

```sql
begin;
  update public.collections set visibility = 'private' where slug = :'S';
  set local role anon;
  select public.collection_by_slug(:'S') is null as hidden_once_private;
rollback;                                  -- ROLLBACK. Do not leave it off.
```

**Expect:** `t`. Same with `deleted_at = now()`.

## 6. Saving

```sql
begin; set local role anon; select public.collection_save(:'S'); rollback;
```

**Expect:** `ERROR: permission denied for function collection_save`.

```sql
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = :'B';
  select public.collection_save(:'S') as first_call;
  select public.collection_save(:'S') as second_call;
  select count(*) as copies, count(note_text) as notes_copied
    from public.bookmarks where owner_id = :'B' and source_collection_id is not null;
rollback;
```

**Expect:** `{"added": N, "skipped": 0}` then `{"added": 0, "skipped": N}` —
the dedupe. `copies` = N and `notes_copied` = **0**: a copy never carries the
curator's note.

```sql
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = :'B';
  select public.collection_save(:'P')           is null as private_refused,
         public.collection_save('zzzzzzzzzzzz') is null as missing_refused;
rollback;
```

**Expect:** `t`, `t`.

## 7. `updated_at` follows the contents

The page prints it and the cache would key on it, so adding or removing a bork
has to move it.

```sql
begin;
  select updated_at as before from public.collections where slug = :'S' \gset
  set local role authenticated;
  set local request.jwt.claim.sub = :'A';
  delete from public.collection_items
   where collection_id = (select id from public.collections where slug = :'S')
     and bookmark_id = '<one of them>';
  reset role;
  select updated_at > :'before' as moved from public.collections where slug = :'S';
rollback;
```

**Expect:** `t`.

## 8. Slugs

```sql
select count(*) filter (where slug !~ '^[a-z0-9]{8,16}$') as malformed,
       count(*) - count(distinct slug)                    as collisions,
       count(*) filter (where slug is null)               as missing
  from public.collections;
select count(distinct public.collection_slug()) as unique_out_of_500 from generate_series(1, 500);
```

**Expect:** `0, 0, 0` and `500`.

## 9. The caps

Both are triggers, so both raise rather than silently truncating.

```sql
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = :'A';
  insert into public.collections (owner_id, name)
    select :'A', 'cap test ' || g from generate_series(1, 200) g;
rollback;
```

**Expect:** `ERROR: a collection limit of 100 per account has been reached`,
once A is over 100 live collections.

```sql
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = :'A';
  insert into public.bookmarks (id, owner_id, url, platform, kind)
    select 'captest/' || g, :'A', 'https://example.com/' || g, 'web', 'article'
      from generate_series(1, 260) g;
  insert into public.collection_items (collection_id, bookmark_owner, bookmark_id)
    select (select id from public.collections where slug = :'S'), :'A', 'captest/' || g
      from generate_series(1, 260) g;
rollback;
```

**Expect:** `ERROR: a collection holds at most 200 borks`.

## 10. Bounds

```sql
begin;
  set local role authenticated;
  set local request.jwt.claim.sub = :'A';
  savepoint s; insert into public.collections (owner_id, name) values (:'A', '');                rollback to s;
  savepoint s; insert into public.collections (owner_id, name) values (:'A', repeat('x', 81));   rollback to s;
  savepoint s; insert into public.collections (owner_id, name, note)
                 values (:'A', 'ok', repeat('x', 501));                                          rollback to s;
rollback;
```

**Expect:** `collections_name_len`, `collections_name_len`, `collections_note_len`.

---

## Then the page

With a real public slug, before the Cloudflare Worker is live:

```sh
curl -s 'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/collection-page?slug=<slug>' \
  | grep -E '<title>|og:image|og:description|robots'
curl -sI 'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/collection-page?slug=zzzzzzzzzzzz'
```

**Expect:** the collection's name in the title, `noindex`, and a `404` on the
second with a `text/html` body. Then `node Scripts/test_collection_page.mjs`
for the renderer itself, and `cloudflare/README.md` for the domain.

---

# Probes to run after `0012_collection_expiry.sql`

Same rules as above: run in the SQL editor, every block wrapped in
`begin … rollback`, and every one of these has already been run on a scratch
PostgreSQL 15 built from `0001` + drift + `0004` + `0011` + `0012` (applied
three times in a row, clean) before it was written down here. `:'A'`, `:'B'`,
`:'S'` and `:'P'` are the same four values as before.

## 11. An expired link is a missing link

Expired, private, deleted and wrong are one answer — otherwise the page would
be an oracle for "this was a link once".

```sql
begin;
  update public.collections set expires_at = now() - interval '1 minute' where slug = :'S';
  set local role anon;
  select public.collection_by_slug(:'S') is null as expired_read_is_null;
  reset role; set local role authenticated; set local request.jwt.claim.sub = :'B';
  select public.collection_save(:'S') is null as expired_save_is_null;
rollback;
```

**Expect:** `t`, `t`.

```sql
begin;
  update public.collections set expires_at = now() + interval '10 days' where slug = :'S';
  set local role anon;
  select public.collection_by_slug(:'S') is not null as open_read_ok,
         (public.collection_by_slug(:'S')->>'expires_at')::timestamptz > now() as expires_in_future;
rollback;
begin; set local role anon;
  select public.collection_by_slug(:'S') ? 'expires_at' as key_present,
         public.collection_by_slug(:'S')->'expires_at' = 'null'::jsonb as is_json_null;
rollback;
```

**Expect:** `t, t` — a link with time left is open and the object says until
when — then `t, t`: with no expiry the key is there and is JSON `null`, so a
client can tell "never" from "old row" without a second call.

## 12. `collection_create`

```sql
begin;
  set local role authenticated; set local request.jwt.claim.sub = :'A';
  select public.collection_create('Leg day', '  the ones that helped  ', 'fitness', 10,
           array['<A bork 2>', '<a bork of B''s>', '<a soft-deleted bork of A''s>', 'nope/404', '<A bork 1>', '<A bork 2>']) as created \gset
  select :'created'::jsonb->>'added' as added,
         (:'created'::jsonb->>'slug') ~ '^[a-z0-9]{12}$' as slug_shape,
         :'created'::jsonb->>'url' = 'https://bookmarker.lol/c/' || (:'created'::jsonb->>'slug') as url_shape,
         (:'created'::jsonb->>'expires_at')::timestamptz
            between now() + interval '9 days 23 hours' and now() + interval '10 days 1 hour' as ten_days;
  select bookmark_id, position from public.collection_items
   where collection_id = (:'created'::jsonb->>'id')::uuid order by position;
  select name, note, category_id, visibility from public.collections where id = (:'created'::jsonb->>'id')::uuid;
  reset role; set local role anon;
  select jsonb_array_length(public.collection_by_slug(:'created'::jsonb->>'slug')->'items') as items_on_page,
         public.collection_by_slug(:'created'::jsonb->>'slug')::text like '%<a note only A can see>%' as leaks_note,
         public.collection_by_slug(:'created'::jsonb->>'slug')::text like '%<B''s bork title>%' as leaks_stranger;
rollback;
```

**Expect:** `added = 2`, `t`, `t`, `t`. Two items, **A bork 2 at position 0
and A bork 1 at position 1** — the array's order, renumbered densely once the
stranger's bork, the deleted one, the unknown id and the duplicate have been
skipped. The row is `public`, the note is trimmed. The anonymous read shows
exactly those two, no note, nothing of B's.

```sql
begin; set local role authenticated; set local request.jwt.claim.sub = :'A';
  select (public.collection_create('Never', null, null, null, array['<A bork 1>'])->>'expires_at') is null as never_is_null,
         (public.collection_create('One day', null, null, 1, array['<A bork 1>'])->>'expires_at')::timestamptz
            between now() + interval '23 hours' and now() + interval '25 hours' as one_day;
  savepoint s; select public.collection_create('Three', null, null, 3, array['<A bork 1>']);            rollback to s;
  savepoint s; select public.collection_create('Zero', null, null, 0, array['<A bork 1>']);             rollback to s;
  savepoint s; select public.collection_create('', null, null, null, array['<A bork 1>']);              rollback to s;
  savepoint s; select public.collection_create(repeat('x', 81), null, null, null, array['<A bork 1>']); rollback to s;
  savepoint s; select public.collection_create('Long note', repeat('n', 501), null, null, array['<A bork 1>']); rollback to s;
rollback;
```

**Expect:** `t, t`, then five errors in order: `a link stays open for 1 day,
10 days, or until you turn it off` (twice), `a collection needs a name of 1 to
80 characters` (twice), `collections_note_len`.

```sql
begin; set local role anon; select public.collection_create('x', null, null, null, '{}'); rollback;
```

**Expect:** `ERROR: permission denied for function collection_create`.

```sql
begin; set local role authenticated; set local request.jwt.claim.sub = :'B';
  select public.collection_create('Steal', null, null, null, array['<A bork 1>', '<A bork 2>', '<B bork 1>']) as r \gset
  select :'r'::jsonb->>'added' as added_for_b;
  select bookmark_owner, bookmark_id from public.collection_items where collection_id = (:'r'::jsonb->>'id')::uuid;
rollback;
```

**Expect:** `added_for_b = 1` and one row — B's own. A's ids are not refused,
they are simply not there to be joined: the function is `security invoker`
and B's RLS never sees A's rows.

```sql
begin; set local role authenticated; set local request.jwt.claim.sub = :'A';
  insert into public.bookmarks (id, owner_id, url, platform, kind)
    select 'captest/' || g, :'A', 'https://example.com/' || g, 'web', 'article' from generate_series(1, 210) g;
  select public.collection_create('Too many', null, null, null, (select array_agg('captest/' || g) from generate_series(1, 210) g));
rollback;
begin; set local role authenticated; set local request.jwt.claim.sub = :'A';
  select count(*) from (select public.collection_create('cap ' || g, null, null, null, '{}') from generate_series(1, 120) g) x;
rollback;
```

**Expect:** `ERROR: a collection holds at most 200 borks` and `ERROR: a
collection limit of 100 per account has been reached` — 0011's triggers,
firing through the RPC exactly as they would on a direct insert, and rolling
the slug back with everything else.

An empty array makes an empty collection (`added = 0`). The clients refuse
that before calling; the RPC does not, because an empty page is harmless and a
bork that has not synced yet is not a reason to fail the ones that have.

## 13. The owner manages it through PostgREST, and only the owner

What the web app and the iPhone actually send: a `select` with an embedded
count, and three `PATCH`es. Under the 0001 owner policies, no RPC needed.

```sql
begin; set local role authenticated; set local request.jwt.claim.sub = :'A';
  select name, slug, visibility, expires_at is null as never,
         (select count(*) from public.collection_items ci where ci.collection_id = c.id) as items
    from public.collections c where deleted_at is null order by updated_at desc;
  update public.collections set visibility = 'private' where slug = :'S';
  update public.collections set expires_at = now() + interval '1 day' where slug = :'S';
  update public.collections set deleted_at = now() where slug = :'P';
  reset role; set local role authenticated; set local request.jwt.claim.sub = :'B';
  update public.collections set visibility = 'public' where slug = :'S';
  select count(*) as b_sees_of_a from public.collections where owner_id = :'A';
rollback;
```

**Expect:** A's list, three `UPDATE 1`, then for B `UPDATE 0` and `0`.

```sql
begin;
  update public.collections set expires_at = now() - interval '1 day' where slug = :'S';
  set local role anon;
  select public.collection_by_slug(:'S') is null as closed;
  reset role; set local role authenticated; set local request.jwt.claim.sub = :'A';
  update public.collections set expires_at = now() + interval '10 days' where slug = :'S';
  reset role; set local role anon;
  select public.collection_by_slug(:'S') is not null as reopened_same_slug;
rollback;
```

**Expect:** `t`, `t`. Expiry is a time, not a tombstone: the owner picks a
new one and the same link answers again — the same trade as turning a link
off and on, made deliberately, and documented in DECISIONS.md.

## Then the page, again

After `supabase functions deploy collection-page`:

```sh
curl -s 'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/collection-page?slug=<slug>' \
  | grep -E 'apple-itunes-app|Get bookmarker|Link open until'
```

**Expect:** `app-argument=bookmarker://c/<slug>`, one `Get bookmarker` button
above the grid, and a `Link open until` line only when the collection has an
expiry. `node Scripts/test_collection_page.mjs` for the rest.
