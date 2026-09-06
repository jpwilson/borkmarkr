-- Clay art for the topics you make yourself.
--
-- The 50 built-in topics each ship a bundled `topic{Id}` imageset, so Browse
-- is a wall of clay scenes. A topic you add yourself (`CustomTopic`, id
-- `custom.<slug>`) has no imageset and never will — we cannot bundle art for
-- a name nobody has typed yet — so `ClayArt` falls back to paper and the tile
-- reads as a bug: Marketing and Health have a scene, Juice and Looksmaxxing
-- are blank white.
--
-- So we generate one, once, on the server: the `topic-art` Edge Function
-- renders a scene in the locked style (Branding/ILLUSTRATION_STYLE.md), puts
-- it in the public `topic-art` bucket, and records it here. The phone stores
-- the returned URL on its local CustomTopic row and renders it exactly like a
-- bookmark cover.
--
-- Why a table and not just a bucket: **an image costs money to make**. This
-- table is the ledger that stops us paying twice for the same topic — one row
-- per (owner, topic), claimed before the model is called, so a retry loop, two
-- devices, or a user tapping create twice all collapse onto one generation.
-- `thumb_jobs` in 0008 is the same shape for the same reason; the difference
-- is that this one is claimed synchronously, because the caller is a phone
-- waiting for a URL rather than Postgres firing and forgetting.
--
-- Nothing here may ever block creating a topic. The phone inserts its
-- CustomTopic locally and returns; art arrives later or never, and a topic
-- with no art looks exactly like it does today.
--
-- One-time setup after this migration (the key is never in git):
--   supabase secrets set OPENAI_API_KEY=<key>
--   supabase functions deploy topic-art

-- ── Bucket ────────────────────────────────────────────────────────────────
-- Public read, same reasoning as `thumbs`: a clay drawing of a juice carton
-- is not a secret, and the object name is an owner id plus a hash. No
-- storage.objects policies, so anon and authenticated cannot list, upload or
-- delete — only the service role, from inside the function, writes.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('topic-art', 'topic-art', true, 2097152,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ── Ledger ────────────────────────────────────────────────────────────────
create table public.topic_art (
  owner_id     uuid not null references public.profiles on delete cascade,
  topic_id     text not null,                  -- CustomTopic.id, e.g. custom.looksmaxxing
  name         text not null,                  -- what it was called when we drew it

  status       text not null default 'pending'
               check (status in ('pending', 'running', 'done', 'failed')),
  public_url   text,                           -- set once status = 'done'
  object_path  text,                           -- its name in bucket 'topic-art'
  bytes        int,
  content_type text,

  attempts     int not null default 0,
  last_error   text,
  locked_at    timestamptz,                    -- set while running; reclaimable after 2 minutes
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  done_at      timestamptz,

  primary key (owner_id, topic_id)
);

create index topic_art_owner_done on public.topic_art (owner_id)
  where status = 'done';

alter table public.topic_art enable row level security;

-- Readable by its owner so the phone can pull art it generated on another
-- device, or re-read a URL it lost. Deliberately no insert/update/delete
-- policy: a client that could write this table could mark a topic 'done'
-- with a URL of its choosing, or reset the ledger and spend the key again.
create policy "own topic art is readable" on public.topic_art
  for select to authenticated using (owner_id = auth.uid());

create trigger topic_art_touch before update on public.topic_art
  for each row execute function public.touch_updated_at();

-- ── RPCs for the Edge Function (service role only) ────────────────────────

-- Claim the right to spend on this topic, atomically.
--
-- Returns one row telling the function what to do:
--   'done'    — we already have art; `public_url` is it, do not call the model
--   'claimed' — this call owns the generation, go ahead
--   'busy'    — another call is mid-generation, come back later
--   'failed'  — too many attempts; stop asking
--
-- `select … for update` is what makes the claim exclusive: a second caller
-- for the same topic blocks on the row until the first has decided, so two
-- devices racing cannot both come back 'claimed'. When there is no row yet
-- there is nothing to lock, and the primary key settles it instead — the
-- loser gets unique_violation and retries, by which time the row exists.
create or replace function public.topic_art_begin(
  p_owner uuid, p_topic_id text, p_name text, p_max_attempts int default 3)
returns table (outcome text, public_url text)
language plpgsql security definer set search_path = public as $$
declare
  art public.topic_art;
begin
  -- `return query` appends to the result set and keeps going, so every branch
  -- below is followed by a bare `return` — otherwise a claim would also emit
  -- the fallback row and the function would answer twice.
  for _attempt in 1..2 loop
    select * into art from public.topic_art a
     where a.owner_id = p_owner and a.topic_id = p_topic_id
     for update;

    if found then
      if art.status = 'done' and art.public_url is not null then
        return query select 'done'::text, art.public_url;
        return;
      elsif art.status = 'running' and art.locked_at > now() - interval '2 minutes' then
        return query select 'busy'::text, null::text;
        return;
      elsif art.attempts >= p_max_attempts then
        return query select 'failed'::text, null::text;
        return;
      end if;

      update public.topic_art a
         set status = 'running', attempts = a.attempts + 1, locked_at = now(),
             name = left(coalesce(p_name, ''), 80)
       where a.owner_id = p_owner and a.topic_id = p_topic_id;
      return query select 'claimed'::text, null::text;
      return;
    end if;

    -- Per-account cap. Art is the one thing here that costs per call, so a
    -- client that invents topics in a loop is bounded by a number rather
    -- than by trust. Built-ins are bundled, so this only counts custom ones.
    if (select count(*) from public.topic_art a
         where a.owner_id = p_owner and a.status in ('done', 'running')) >= 200 then
      return query select 'failed'::text, null::text;
      return;
    end if;

    begin
      insert into public.topic_art (owner_id, topic_id, name, status, attempts, locked_at)
      values (p_owner, p_topic_id, left(coalesce(p_name, ''), 80), 'running', 1, now());
      return query select 'claimed'::text, null::text;
      return;
    exception when unique_violation then
      -- Someone inserted between our select and our insert. Go round once
      -- more; the row is there now, so the locking path above decides.
      null;
    end;
  end loop;

  return query select 'busy'::text, null::text;
  return;
end $$;

-- Record the finished image.
create or replace function public.topic_art_apply(
  p_owner uuid, p_topic_id text, p_public_url text, p_path text,
  p_bytes int, p_content_type text)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.topic_art
     set status = 'done', public_url = p_public_url, object_path = p_path,
         bytes = p_bytes, content_type = p_content_type,
         locked_at = null, last_error = null, done_at = now()
   where owner_id = p_owner and topic_id = p_topic_id;
end $$;

-- Release a claim that didn't finish. Terminal once attempts run out, so a
-- topic whose name the model keeps refusing stops costing anything.
create or replace function public.topic_art_fail(
  p_owner uuid, p_topic_id text, p_error text, p_max_attempts int default 3)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.topic_art a
     set status = case when a.attempts >= p_max_attempts then 'failed' else 'pending' end,
         locked_at = null,
         last_error = left(coalesce(p_error, 'unknown'), 300)
   where a.owner_id = p_owner and a.topic_id = p_topic_id;
end $$;

-- Supabase grants execute on new public functions to anon/authenticated by
-- default; these three are the spend ledger and are for the service role only.
do $$ declare f text; begin
  foreach f in array array[
    'public.topic_art_begin(uuid,text,text,int)',
    'public.topic_art_apply(uuid,text,text,text,int,text)',
    'public.topic_art_fail(uuid,text,text,int)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;
