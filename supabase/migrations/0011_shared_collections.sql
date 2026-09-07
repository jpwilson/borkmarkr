-- Shared collections — the recipient's half.
--
-- 0001 wrote the shape of sharing and deliberately left it unwired. This turns
-- it on for exactly one door: **a link**. Everything else stays shut.
--
-- The model, in one sentence: a collection is private until its owner flips it
-- to `public`, which means *anyone with the link* — unlisted and unguessable,
-- not listed, not searchable, not enumerable — and the only way an anonymous
-- reader ever reaches it is `collection_by_slug`, a security-definer RPC that
-- takes a slug and returns a fixed, curated JSON shape. There is no table an
-- anonymous role can read, no PostgREST filter it can build, and nothing in
-- the returned object that the owner did not choose to put in the collection.
--
-- What changes here, and why each one:
--
--   1. `collections` gains a `note`, length bounds on `name`, and a slug that
--      is minted on insert instead of being the client's problem.
--   2. **A leak in 0001 is closed.** "own collection items writable" checked
--      only that you own the *collection* — never that you own the *bookmark*.
--      Any signed-in user could therefore insert someone else's (owner_id,
--      bookmark_id) into their own collection, and 0001's additive policy
--      "bookmarks visible through shared collections" would then hand them the
--      row. Since bookmark ids are the normalised URL, that is guessable: save
--      the same reel, learn the id, point it at a stranger's uuid, read their
--      copy — including `note_text`. Fixed below by requiring
--      `bookmark_owner = auth.uid()` on write.
--   3. **Public discovery is removed.** `can_view_collection` returned true for
--      *every* `visibility = 'public'` collection to *any* signed-in user, so
--      `GET /rest/v1/collections?select=*` was a directory of every shared
--      collection on the service, and `collection_items` + the additive
--      bookmarks policy made it a directory of their contents. A link is not a
--      publication. The branch is gone; anonymous and link access go through
--      the RPC, which requires knowing the slug.
--   4. Two RPCs: `collection_by_slug` (read, anon) and `collection_save`
--      (copy into my library, authenticated).
--
-- `visibility = 'people'` and `collection_grants` stay dormant in v1: nothing
-- creates a grant, so the branch is unreachable. It is kept, not deleted, so
-- the day we build it the policy is already the one place that decides.
--
-- NOT APPLIED. Run `supabase db push` (see Scripts/test_collections_sql.md for
-- the probes to run afterwards). Idempotent on purpose: production has drifted
-- from 0001 (see the profiles note at the bottom), so every statement here is
-- written to be safe on the drifted database and on a fresh one.

-- ─────────────────────────────────────────────────────────────────────────────
-- Slugs
-- ─────────────────────────────────────────────────────────────────────────────

-- 12 characters of [a-z0-9] — 36^12 ≈ 4.7 × 10^18, which is the whole security
-- model for an unlisted link, so it is minted from `gen_random_bytes` (CSPRNG)
-- and never from `random()`, a timestamp, or the name.
--
-- Rejection sampling rather than a plain `% 36`: 256 is not a multiple of 36,
-- so modulo alone would make the first four letters ~14% likelier than the
-- rest. Dropping bytes ≥ 252 (= 7 × 36) costs one extra byte in twenty and
-- keeps every character equally likely.
--
-- Deliberately NOT security definer: it reads nothing. It is a column default,
-- so it runs as whoever is inserting.
create or replace function public.collection_slug()
returns text
language plpgsql
volatile
-- pgcrypto lives in `extensions` on Supabase and in `public` on a plain
-- Postgres; naming both means this works either way.
set search_path = public, extensions
as $$
declare
  alphabet constant text := 'abcdefghijklmnopqrstuvwxyz0123456789';   -- 36
  s    text := '';
  raw  bytea;
  b    int;
  i    int;
begin
  while length(s) < 12 loop
    raw := gen_random_bytes(16);
    for i in 0..15 loop
      exit when length(s) >= 12;
      b := get_byte(raw, i);
      continue when b >= 252;
      s := s || substr(alphabet, (b % 36) + 1, 1);
    end loop;
  end loop;
  return s;
end $$;

revoke all on function public.collection_slug() from public;
grant execute on function public.collection_slug() to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- collections
-- ─────────────────────────────────────────────────────────────────────────────

-- A sentence under the title — "the twelve things that actually helped".
-- Bounded because it is rendered on a public page we serve.
alter table public.collections add column if not exists note text;
alter table public.collections drop constraint if exists collections_note_len;
alter table public.collections add constraint collections_note_len
  check (note is null or length(note) <= 500);

-- The name is the page's <title> and its OG card. Empty is not a title, and
-- 80 is the point past which it is a paragraph pretending to be one.
alter table public.collections drop constraint if exists collections_name_len;
alter table public.collections add constraint collections_name_len
  check (length(name) between 1 and 80);

-- Production drifted: 0001 declared this check inline and the live table does
-- not have it. Re-assert it, and allow null (a collection may have no slug on
-- an old row; the default below means new ones always do).
alter table public.collections drop constraint if exists collections_slug_format;
alter table public.collections add constraint collections_slug_format
  check (slug is null or slug ~ '^[a-z0-9]{8,16}$');

-- Every collection gets a slug at birth, private or not.
--
-- `visibility` is what the slug *means*:
--   'public'  — anyone with the link. Unlisted: the link is the credential.
--               Not indexed (the page sends `robots: noindex`), not listed
--               anywhere, and no longer enumerable through PostgREST.
--   'private' — the link is off. The slug is KEPT, so turning sharing back on
--               restores the same URL rather than orphaning every copy of it
--               someone already sent. That is a deliberate trade: an old link
--               starts working again when the owner re-enables it. Someone who
--               wants a permanently dead link deletes the collection.
--   'people'  — dormant in v1 (see the header).
alter table public.collections alter column slug set default public.collection_slug();
update public.collections set slug = public.collection_slug() where slug is null;

-- ─────────────────────────────────────────────────────────────────────────────
-- The 0001 leak, and the caps
-- ─────────────────────────────────────────────────────────────────────────────

-- 0001 had one `for all` policy whose `with check` never looked at
-- `bookmark_owner`. Replaced by three, split by command, because insert and
-- update do not want the same test — and because a `for all` policy makes it
-- too easy for the next person to widen four commands while thinking about one.
drop policy if exists "own collection items writable"   on public.collection_items;
drop policy if exists "own collection items insertable" on public.collection_items;
drop policy if exists "own collection items updatable"  on public.collection_items;
drop policy if exists "own collection items deletable"  on public.collection_items;

create policy "own collection items insertable" on public.collection_items
  for insert to authenticated
  with check (
    -- THE FIX: you may only put your own bookmarks in your own collection.
    bookmark_owner = auth.uid()
    and exists (
      select 1 from public.collections c
       where c.id = collection_items.collection_id
         and c.owner_id = auth.uid()
         and c.deleted_at is null
    )
  );

create policy "own collection items updatable" on public.collection_items
  for update to authenticated
  using (
    exists (select 1 from public.collections c
             where c.id = collection_items.collection_id and c.owner_id = auth.uid())
  )
  with check (
    bookmark_owner = auth.uid()
    and exists (select 1 from public.collections c
                 where c.id = collection_items.collection_id and c.owner_id = auth.uid())
  );

create policy "own collection items deletable" on public.collection_items
  for delete to authenticated
  using (
    exists (select 1 from public.collections c
             where c.id = collection_items.collection_id and c.owner_id = auth.uid())
  );

-- The caps are triggers, not policy predicates.
--
-- The obvious place for "at most 200 items" is the `with check` above, and it
-- does not work: a policy on `collection_items` whose expression counts
-- `collection_items` re-enters that table's policies and Postgres refuses the
-- statement outright — `infinite recursion detected in policy for relation
-- "collection_items"`. Worse, it fails on *every* insert, including legitimate
-- ones, and the error names recursion rather than the cap, so the leak fix
-- above would have been masked by it. Verified by running the probes in
-- Scripts/test_collections_sql.md against a scratch Postgres.
--
-- So both caps live in AFTER triggers instead: the new row is already there to
-- be counted, and `security definer` means the count is the real one rather
-- than whatever the caller's own RLS would let them see.
--
-- A shared page is a curation, not an export. 200 is far past any real
-- collection and well under "my whole library, rendered server-side".
create or replace function public.collection_items_cap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.collection_items ci
       where ci.collection_id = new.collection_id) > 200 then
    raise exception 'a collection holds at most 200 borks'
      using errcode = 'check_violation';
  end if;
  return null;
end $$;

drop trigger if exists collection_items_cap on public.collection_items;
create trigger collection_items_cap
  after insert on public.collection_items
  for each row execute function public.collection_items_cap();

-- A cap on collections themselves. Not a product limit anyone will meet — it
-- is the bound that stops a loop from minting a hundred thousand slugs.
create or replace function public.collections_cap()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.collections c
       where c.owner_id = new.owner_id and c.deleted_at is null) > 100 then
    raise exception 'a collection limit of 100 per account has been reached'
      using errcode = 'check_violation';
  end if;
  return null;
end $$;

drop trigger if exists collections_cap on public.collections;
create trigger collections_cap
  after insert or update of deleted_at, owner_id on public.collections
  for each row when (new.deleted_at is null)
  execute function public.collections_cap();

-- ─────────────────────────────────────────────────────────────────────────────
-- can_view_collection — the public branch comes out
-- ─────────────────────────────────────────────────────────────────────────────

-- Same signature, so every 0001 policy still defers to it and this stays the
-- one place visibility is decided. What is gone is `or c.visibility = 'public'`:
-- that made every shared collection readable by every signed-in account
-- through PostgREST, which is a directory, not a link. Owner and (dormant)
-- grant branches remain. Anonymous readers never reach a policy at all — they
-- go through `collection_by_slug`, below.
create or replace function public.can_view_collection(c public.collections)
returns boolean
language sql
stable
security invoker
set search_path = public
as $$
  select
    c.deleted_at is null
    and (
      c.owner_id = auth.uid()
      or (
        c.visibility = 'people'
        and exists (
          select 1 from public.collection_grants g
          where g.collection_id = c.id and g.viewer_id = auth.uid()
        )
      )
    )
$$;

-- Belt as well as braces. Supabase grants every role on a new public table by
-- default; nothing anonymous has any business touching these three, and the
-- RPC below does not need them to (it is security definer).
revoke all on public.collections from anon;
revoke all on public.collection_items from anon;
revoke all on public.collection_grants from anon;

-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at follows the contents
-- ─────────────────────────────────────────────────────────────────────────────

-- Adding or removing a bork changes the page; `collections.updated_at` is what
-- the page prints and what a cache would key on, so membership has to move it.
-- Definer because the write path (and a cascade) must not depend on the
-- caller's RLS; the exception handler is there because a cascade deletes the
-- items *and* the collection, and the parent row may already be gone.
create or replace function public.collection_items_touch()
returns trigger language plpgsql security definer set search_path = public as $$
declare cid uuid;
begin
  cid := case when tg_op = 'DELETE' then old.collection_id else new.collection_id end;
  update public.collections set updated_at = now() where id = cid;
  return null;
exception when others then
  return null;
end $$;

drop trigger if exists collection_items_touch on public.collection_items;
create trigger collection_items_touch
  after insert or delete on public.collection_items
  for each row execute function public.collection_items_touch();

-- ─────────────────────────────────────────────────────────────────────────────
-- Provenance
-- ─────────────────────────────────────────────────────────────────────────────

-- Where a saved copy came from. Written only by `collection_save`; no foreign
-- key, because the collection may later be deleted and the copy is the saver's
-- for good — provenance, not a dependency.
--
-- Clients never send this column and never need to: PostgREST upserts touch
-- only the columns in the request body, so a sync push that knows nothing
-- about it leaves it alone rather than nulling it. Same precedent as
-- `image_url` in 0004.
alter table public.bookmarks add column if not exists source_collection_id uuid;

-- ─────────────────────────────────────────────────────────────────────────────
-- collection_by_slug — the only anonymous door
-- ─────────────────────────────────────────────────────────────────────────────

-- Security definer because there is no policy that could express this: the
-- reader is anonymous and the rows belong to a stranger. The function is the
-- policy. What it will hand out is fixed here, in one place, and cannot be
-- widened by a query string the way a PostgREST view can:
--
--   * never `note_text` (your private note on a bork you shared is still yours)
--   * never an email, a user id, or any other row of the owner's library
--   * never a collection that is deleted, private, or does not exist — all
--     three return exactly `null`, so the page cannot be used as an oracle to
--     tell "wrong slug" from "you are not allowed". A wrong guess and a
--     revoked link are indistinguishable.
--
-- `stable` (not volatile) so PostgREST will accept it on GET as well as POST.
create or replace function public.collection_by_slug(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with found as (
    select c.*
      from public.collections c
     where p_slug ~ '^[a-z0-9]{8,16}$'      -- cheap gate before the index probe
       and c.slug = p_slug
       and c.visibility = 'public'
       and c.deleted_at is null
     limit 1
  )
  select jsonb_build_object(
    'id',         f.id,
    'name',       f.name,
    'note',       f.note,
    -- A name to put on the page, never an identifier. 'Someone' is the honest
    -- fallback: production creates bare profile rows with no handle at all.
    'owner_name', coalesce(nullif(btrim(p.display_name), ''),
                           nullif(btrim(p.handle), ''),
                           'Someone'),
    'updated_at', f.updated_at,
    'items', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'id',               b.id,
                 'url',              b.url,
                 'title',            b.title,
                 'author',           b.author,
                 'platform',         b.platform,
                 'kind',             b.kind,
                 'category_id',      b.category_id,
                 'subcategory',      b.subcategory,
                 'tags',             b.tags,
                 'image_url',        b.image_url,
                 'duration_seconds', b.duration_seconds,
                 'body_text',        b.body_text
               )
               order by ci.position, ci.added_at
             )
        from public.collection_items ci
        join public.bookmarks b
          on b.owner_id = ci.bookmark_owner
         and b.id       = ci.bookmark_id
       where ci.collection_id = f.id
         -- Only the owner's own borks. 0001's write policy let anyone put a
         -- stranger's row in a collection; that is fixed above, but the read
         -- refuses to serve such a row regardless, so a collection assembled
         -- before this migration cannot leak through the new page either.
         and b.owner_id = f.owner_id
         and b.deleted_at is null
    ), '[]'::jsonb)
  )
  from found f
  join public.profiles p on p.id = f.owner_id;
$$;

revoke all on function public.collection_by_slug(text) from public;
grant execute on function public.collection_by_slug(text) to anon, authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- collection_save — "save these to my library"
-- ─────────────────────────────────────────────────────────────────────────────

-- Copies, not references: the rows become the caller's, with their own
-- `saved_at`, and they survive the collection being deleted or turned off.
-- Signed-in only — there is nowhere to put a copy otherwise.
--
-- `on conflict do nothing` makes this idempotent, so tapping the button twice
-- (or saving from two devices) adds nothing the second time. Note that a bork
-- the caller previously deleted is a *conflict*, not an add: the tombstone
-- stays deleted rather than being quietly resurrected by someone else's link.
create or replace function public.collection_save(p_slug text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid   uuid := auth.uid();
  v_col   public.collections;
  v_total int;
  v_added int;
begin
  if v_uid is null then return null; end if;
  if p_slug !~ '^[a-z0-9]{8,16}$' then return null; end if;

  select c.* into v_col
    from public.collections c
   where c.slug = p_slug and c.visibility = 'public' and c.deleted_at is null;
  if not found then return null; end if;           -- same silence as the read

  select count(*) into v_total
    from public.collection_items ci
    join public.bookmarks b
      on b.owner_id = ci.bookmark_owner and b.id = ci.bookmark_id
   where ci.collection_id = v_col.id
     and b.owner_id = v_col.owner_id
     and b.deleted_at is null;

  insert into public.bookmarks (
    id, owner_id, url, title, author, platform, kind,
    category_id, subcategory, tags, body_text, duration_seconds, image_url,
    note_text, saved_at, updated_at, source_collection_id)
  select b.id, v_uid, b.url, b.title, b.author, b.platform, b.kind,
         b.category_id, b.subcategory, b.tags, b.body_text, b.duration_seconds, b.image_url,
         -- The curator's note is theirs. A copy starts blank.
         null, now(), now(), v_col.id
    from public.collection_items ci
    join public.bookmarks b
      on b.owner_id = ci.bookmark_owner and b.id = ci.bookmark_id
   where ci.collection_id = v_col.id
     and b.owner_id = v_col.owner_id
     and b.deleted_at is null
  on conflict (owner_id, id) do nothing;

  get diagnostics v_added = row_count;
  return jsonb_build_object('added', v_added, 'skipped', v_total - v_added);
end $$;

revoke all on function public.collection_save(text) from public, anon;
grant execute on function public.collection_save(text) to authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- Codifying production drift on `profiles`
-- ─────────────────────────────────────────────────────────────────────────────

-- Verified read-only against the live database before writing this (
-- `information_schema.columns`, `pg_constraint`, `pg_trigger`), not assumed:
--
--   * `profiles.handle` is NULLABLE in production and carries no format check,
--     though 0001 declares it `not null check (handle ~ '^[a-z0-9_]{3,24}$')`.
--     All four live profiles have a null handle. `collection_by_slug` above is
--     written for that reality — hence the 'Someone' fallback.
--   * A trigger `on_auth_user_created` on `auth.users` calls
--     `public.handle_new_user()`, which is `insert into public.profiles (id)
--     values (new.id) on conflict do nothing`. It is not in any migration.
--     That is why handles are null: nothing ever sets one.
--   * `profiles.avatar_hue` (0001, `int not null default 24`) does not exist in
--     production. Nothing reads it, so it is left alone here rather than
--     re-added — noted so the next person does not discover it the hard way.
--
-- Only the nullability is codified, because only it is load-bearing for this
-- migration. The trigger is deliberately NOT recreated: `auth.users` is owned
-- by `supabase_auth_admin`, so `create trigger` on it from a migration can
-- fail on ownership and take the whole push down with it, and the trigger
-- already exists where it matters. For a *fresh* project, run this once by
-- hand in the SQL editor after the first push:
--
--   create or replace function public.handle_new_user()
--   returns trigger language plpgsql security definer set search_path = public
--   as $fn$ begin
--     insert into public.profiles (id) values (new.id) on conflict do nothing;
--     return new;
--   end $fn$;
--   create trigger on_auth_user_created after insert on auth.users
--     for each row execute function public.handle_new_user();
alter table public.profiles alter column handle drop not null;
