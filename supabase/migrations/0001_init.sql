-- bookmarker — Supabase schema (project name: `bookmarker`)
--
-- SCAFFOLDING ONLY. Nothing in the app talks to this yet. The friend feed is a
-- deliberate post-launch fast-follow; this exists so the shape is settled
-- before the client is written against it, and so the local SwiftData model
-- already carries the columns sync needs (`updated_at`, `deleted_at`).
--
-- To create the project when you want it:
--   supabase projects create bookmarker
--   supabase link --project-ref <ref>
--   supabase db push
--
-- Design rules this encodes:
--   1. Local-first. The phone is the source of truth for your own saves;
--      this is a replica. Saving must never require the network.
--   2. Private by default. A row is invisible to everyone but its owner until
--      the owner explicitly puts it in a collection AND grants access.
--   3. Deletes are tombstones, never hard deletes — otherwise a device that
--      was offline during a delete happily re-uploads the row.

-- ─────────────────────────────────────────────────────────────────────────────
-- Profiles
-- ─────────────────────────────────────────────────────────────────────────────

create table public.profiles (
  id          uuid primary key references auth.users on delete cascade,
  handle      text unique not null check (handle ~ '^[a-z0-9_]{3,24}$'),
  display_name text,
  avatar_hue  int not null default 24,
  created_at  timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Profiles are readable by anyone signed in: you cannot share a collection
-- with someone you cannot look up.
create policy "profiles are readable" on public.profiles
  for select to authenticated using (true);

create policy "own profile is writable" on public.profiles
  for all to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- Bookmarks
-- ─────────────────────────────────────────────────────────────────────────────

create table public.bookmarks (
  -- Matches Bookmark.stableID on the client: the normalised URL. Scoped per
  -- owner so two people saving the same reel are two rows, not a conflict.
  id            text not null,
  owner_id      uuid not null references public.profiles on delete cascade,

  url           text not null,
  title         text not null default '',
  author        text,
  platform      text not null,
  kind          text not null,

  category_id   text,
  subcategory   text,
  tags          text[] not null default '{}',

  body_text     text,
  duration_seconds int,

  note_text     text,
  note_date     date,

  saved_at      timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,

  primary key (owner_id, id)
);

create index bookmarks_owner_saved on public.bookmarks (owner_id, saved_at desc)
  where deleted_at is null;
create index bookmarks_owner_category on public.bookmarks (owner_id, category_id)
  where deleted_at is null;
-- Sync pulls "everything changed since my last cursor".
create index bookmarks_owner_updated on public.bookmarks (owner_id, updated_at);

alter table public.bookmarks enable row level security;

create policy "own bookmarks" on public.bookmarks
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- Collections — the unit of sharing
-- ─────────────────────────────────────────────────────────────────────────────

create type public.collection_visibility as enum ('private', 'people', 'public');

create table public.collections (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid not null references public.profiles on delete cascade,
  name        text not null,
  category_id text,
  visibility  public.collection_visibility not null default 'private',
  -- Public-link slug. Null unless visibility = 'public', so a collection can
  -- never be guessed at a URL before the owner opts in.
  slug        text unique check (slug ~ '^[a-z0-9]{8,16}$'),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz,

  constraint public_needs_slug
    check (visibility <> 'public' or slug is not null)
);

create table public.collection_items (
  collection_id uuid not null references public.collections on delete cascade,
  bookmark_owner uuid not null,
  bookmark_id   text not null,
  position      int not null default 0,
  added_at      timestamptz not null default now(),
  primary key (collection_id, bookmark_owner, bookmark_id),
  foreign key (bookmark_owner, bookmark_id)
    references public.bookmarks (owner_id, id) on delete cascade
);

-- Explicit grants. "browse what your friends browse" = the curator grants you
-- a collection; there is no implicit follow that exposes anything.
create table public.collection_grants (
  collection_id uuid not null references public.collections on delete cascade,
  viewer_id     uuid not null references public.profiles on delete cascade,
  granted_at    timestamptz not null default now(),
  primary key (collection_id, viewer_id)
);

alter table public.collections enable row level security;
alter table public.collection_items enable row level security;
alter table public.collection_grants enable row level security;

-- Helper keeps the visibility rule in ONE place. Every policy below defers to
-- it, so widening access is a single-function change and can't drift.
create or replace function public.can_view_collection(c public.collections)
returns boolean
language sql
stable
security invoker
as $$
  select
    c.deleted_at is null
    and (
      c.owner_id = auth.uid()
      or c.visibility = 'public'
      or (
        c.visibility = 'people'
        and exists (
          select 1 from public.collection_grants g
          where g.collection_id = c.id and g.viewer_id = auth.uid()
        )
      )
    )
$$;

create policy "collections readable when permitted" on public.collections
  for select to authenticated using (public.can_view_collection(collections));

create policy "own collections writable" on public.collections
  for all to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy "collection items follow their collection" on public.collection_items
  for select to authenticated using (
    exists (
      select 1 from public.collections c
      where c.id = collection_id and public.can_view_collection(c)
    )
  );

create policy "own collection items writable" on public.collection_items
  for all to authenticated using (
    exists (select 1 from public.collections c
            where c.id = collection_id and c.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.collections c
            where c.id = collection_id and c.owner_id = auth.uid())
  );

create policy "grants visible to owner and grantee" on public.collection_grants
  for select to authenticated using (
    viewer_id = auth.uid()
    or exists (select 1 from public.collections c
               where c.id = collection_id and c.owner_id = auth.uid())
  );

create policy "only owner grants access" on public.collection_grants
  for all to authenticated using (
    exists (select 1 from public.collections c
            where c.id = collection_id and c.owner_id = auth.uid())
  ) with check (
    exists (select 1 from public.collections c
            where c.id = collection_id and c.owner_id = auth.uid())
  );

-- A bookmark becomes visible to someone else ONLY through a collection they
-- can view. Deliberately a separate, additive policy: your library as a whole
-- is never exposed, only the slices you curated.
create policy "bookmarks visible through shared collections" on public.bookmarks
  for select to authenticated using (
    deleted_at is null
    and exists (
      select 1
      from public.collection_items ci
      join public.collections c on c.id = ci.collection_id
      where ci.bookmark_owner = bookmarks.owner_id
        and ci.bookmark_id = bookmarks.id
        and public.can_view_collection(c)
    )
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- updated_at maintenance
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

create trigger bookmarks_touch before update on public.bookmarks
  for each row execute function public.touch_updated_at();
create trigger collections_touch before update on public.collections
  for each row execute function public.touch_updated_at();
