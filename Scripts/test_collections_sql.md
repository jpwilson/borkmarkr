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
