-- Shared collections, part two — the curator's half.
--
-- 0011 built the door a stranger walks through. This is what the owner needs
-- on the other side of it: a way to make a collection in one call, and a way
-- to hand out a link that closes itself.
--
--   1. `collections.expires_at` — null means never. Past it, the link is
--      indistinguishable from one that never existed: both read RPCs return
--      the same `null` and the page is the same page, so an expired link
--      cannot be told apart from a wrong slug or a revoked one.
--   2. `collection_by_slug` and `collection_save` learn to look at it.
--   3. `collection_create` — one RPC that mints the collection, files the
--      caller's own borks into it in the order given, and returns the link.
--      It is SECURITY INVOKER on purpose: the caller's row-level security is
--      the lock, not this function, so a stranger's bookmark id is simply not
--      there to be joined, and the 0011 caps fire as triggers exactly as they
--      would on a direct insert.
--
-- The client contract (web + iOS build against this in parallel):
--   * expiry choices are Never / 1 day / 10 days — nothing else is accepted
--   * the public URL is https://bookmarker.lol/c/<slug>
--   * list / turn off / delete / change expiry go through PostgREST under the
--     0001 owner policies; only creation needs an RPC, because it is the one
--     write that touches two tables and has to come back with the slug
--
-- Idempotent, like 0011: production has drifted from 0001 and every statement
-- here is safe to run on the drifted database, a fresh one, or twice.
-- NOT APPLIED. Run `supabase db push`, then the probes appended to
-- Scripts/test_collections_sql.md, then redeploy `collection-page`.

-- ─────────────────────────────────────────────────────────────────────────────
-- expires_at
-- ─────────────────────────────────────────────────────────────────────────────

-- Null is "never". A timestamp is the moment the link stops answering; the
-- row stays, the owner still sees it, and setting a new time reopens it.
alter table public.collections add column if not exists expires_at timestamptz;

-- ─────────────────────────────────────────────────────────────────────────────
-- collection_by_slug — expired reads as missing
-- ─────────────────────────────────────────────────────────────────────────────

-- Identical to 0011 but for the `expires_at` test in `found` and the field in
-- the object. `now()` is stable within a statement, so the function stays
-- `stable` and PostgREST keeps accepting it on GET.
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
     where p_slug ~ '^[a-z0-9]{8,16}$'
       and c.slug = p_slug
       and c.visibility = 'public'
       and c.deleted_at is null
       and (c.expires_at is null or c.expires_at > now())
     limit 1
  )
  select jsonb_build_object(
    'id',         f.id,
    'name',       f.name,
    'note',       f.note,
    'owner_name', coalesce(nullif(btrim(p.display_name), ''),
                           nullif(btrim(p.handle), ''),
                           'Someone'),
    'updated_at', f.updated_at,
    -- The page prints "Link open until …" from this. Null when it never closes.
    'expires_at', f.expires_at,
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
-- collection_save — you cannot copy from a link that has closed
-- ─────────────────────────────────────────────────────────────────────────────

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
   where c.slug = p_slug
     and c.visibility = 'public'
     and c.deleted_at is null
     and (c.expires_at is null or c.expires_at > now());
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
-- collection_create — "share these as a link"
-- ─────────────────────────────────────────────────────────────────────────────

-- One call, one link. The collection is born `public` because the only reason
-- to make one from a client is to send it; the slug comes from the 0011
-- default; the items are the caller's own live borks, in the order the array
-- gave them, and anything else in the array — a stranger's id, a deleted
-- bork, a typo, a duplicate — is skipped rather than refused, because the
-- client has already shown the person what they picked and a stale id is not
-- their mistake to be told about.
--
-- SECURITY INVOKER, deliberately. Every insert here runs under the caller's
-- own RLS: "own collections writable" for the row, "own collection items
-- insertable" (bookmark_owner = auth.uid(), 0011's leak fix) for the items,
-- and "own bookmarks" for the join that decides what exists. There is nothing
-- this function can do that the same client could not do with three
-- PostgREST calls — it just does it atomically and hands back the slug.
--
-- The 0011 caps are `after` triggers and fire as they would on a direct
-- insert: a 201st bork or a 101st live collection raises and the whole call
-- rolls back, slug and all.
create or replace function public.collection_create(
  p_name         text,
  p_note         text   default null,
  p_category_id  text   default null,
  p_expiry_days  int    default null,
  p_bookmark_ids text[] default '{}'
)
returns jsonb
language plpgsql
volatile
security invoker
set search_path = public
as $$
declare
  v_uid     uuid := auth.uid();
  v_name    text := btrim(coalesce(p_name, ''));
  v_expires timestamptz;
  v_col     public.collections;
  v_added   int;
begin
  if v_uid is null then
    raise exception 'sign in to share a collection'
      using errcode = 'insufficient_privilege';
  end if;
  -- The three choices every client offers. Anything else is a bug upstream,
  -- and a bug that silently became "never" would be the wrong kind of quiet.
  if p_expiry_days is not null and p_expiry_days not in (1, 10) then
    raise exception 'a link stays open for 1 day, 10 days, or until you turn it off'
      using errcode = 'check_violation';
  end if;
  if length(v_name) not between 1 and 80 then
    raise exception 'a collection needs a name of 1 to 80 characters'
      using errcode = 'check_violation';
  end if;

  v_expires := case when p_expiry_days is null then null
                    else now() + p_expiry_days * interval '1 day' end;

  insert into public.collections (owner_id, name, note, category_id, visibility, expires_at)
  values (v_uid, v_name, nullif(btrim(coalesce(p_note, '')), ''), p_category_id, 'public', v_expires)
  returning * into v_col;

  -- `with ordinality` is the array order; `row_number` renumbers it from 0
  -- once the skipped ids are gone, so positions are dense (0, 1, 2 …) rather
  -- than the caller's indices with holes. The join is what skips ids that are
  -- not the caller's own live borks — under RLS there is no other kind to
  -- see. `distinct on` keeps the first of a repeated id, so a double-tap in a
  -- picker is one row.
  insert into public.collection_items (collection_id, bookmark_owner, bookmark_id, position)
  select v_col.id, v_uid, picked.id, (row_number() over (order by picked.ord) - 1)::int
    from (
      select distinct on (ids.id) ids.id, ids.ord
        from unnest(p_bookmark_ids) with ordinality as ids(id, ord)
        join public.bookmarks b
          on b.owner_id = v_uid and b.id = ids.id and b.deleted_at is null
       order by ids.id, ids.ord
    ) picked;

  get diagnostics v_added = row_count;

  return jsonb_build_object(
    'id',         v_col.id,
    'slug',       v_col.slug,
    'url',        'https://bookmarker.lol/c/' || v_col.slug,
    'expires_at', v_col.expires_at,
    'added',      v_added
  );
end $$;

revoke all on function public.collection_create(text, text, text, int, text[]) from public, anon, service_role;
grant execute on function public.collection_create(text, text, text, int, text[]) to authenticated;
