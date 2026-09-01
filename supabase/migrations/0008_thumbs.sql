-- Thumbnails that outlive the CDN. Instagram, Facebook and TikTok sign their
-- image URLs (oe=/oh=) and they die in about five days, so every reel saved
-- last week has a cover that no longer loads. When a bookmark arrives
-- carrying one of those, a trigger queues a job and pokes the `thumb` Edge
-- Function, which copies the bytes into Storage and rewrites image_url to a
-- permanent public URL. Same pg_net shape as 0007, with three differences:
-- the shared token lives in Vault (never in git), work is queued in
-- thumb_jobs so it can be retried and backfilled, and one statement is one
-- wake — a phone pushing its whole library is one HTTP call, not hundreds.
--
-- Nothing here may ever fail a client's save. Bookkeeping is a side table so
-- `select=*` on bookmarks is unchanged for both clients, and nothing is
-- reachable from anon/authenticated: the triggers are security definer and
-- the RPCs are service-role only.
--
-- One-time setup after this migration (the token is never in git):
--   select vault.create_secret('<random>', 'thumb_token');   -- SQL editor
--   supabase secrets set THUMB_TOKEN=<same random>
--   supabase functions deploy thumb   (config.toml sets verify_jwt = false)

create extension if not exists pg_net;

-- ── Bucket ────────────────────────────────────────────────────────────────
-- Public read: a bookmark cover is not a secret, and the object name is an
-- owner id plus a hash. Deliberately NO storage.objects policies: anon and
-- authenticated cannot list, upload or delete. Only the service role — the
-- thumb function — writes.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('thumbs', 'thumbs', true, 2097152,
        array['image/jpeg', 'image/png', 'image/webp', 'image/gif'])
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ── Which URLs are on borrowed time ───────────────────────────────────────
-- Mirrored by urlExpires() in functions/thumb/index.ts — widen both together.
-- Our own Storage URLs are excluded first so a rewrite can never re-queue.
create or replace function public.thumb_is_expiring(u text)
returns boolean language sql immutable as $$
  select coalesce(
    u !~ '^https://pcjuxnhqxyfvgagnblzv\.supabase\.co/'
    and (
      u ~* '^https?://[^/?#]*\.(cdninstagram\.com|fbcdn\.net|tiktokcdn(-[a-z0-9]+)?\.com)([/?#]|$)'
      or u ~ '^https://pbs\.twimg\.com/card_img/'
      or u ~* '[?&](oe|oh|x-expires|x-amz-expires)='
    ), false)
$$;

-- ── Queue ─────────────────────────────────────────────────────────────────
create table public.thumb_jobs (
  owner_id        uuid        not null,
  bookmark_id     text        not null,
  source_url      text        not null,     -- the expiring URL we last saw
  public_url      text,                     -- our permanent copy, once status = 'done'
  object_path     text,                     -- its name in bucket 'thumbs'
  status          text        not null default 'pending'
                  check (status in ('pending', 'running', 'done', 'failed', 'skipped')),
  attempts        int         not null default 0,
  next_attempt_at timestamptz not null default now(),
  locked_at       timestamptz,              -- set while running; reclaimable after 5 minutes
  enqueued_at     timestamptz not null default now(),   -- the client write that queued it
  done_at         timestamptz,
  bytes           int,
  content_type    text,
  last_error      text,
  primary key (owner_id, bookmark_id),
  foreign key (owner_id, bookmark_id)
    references public.bookmarks (owner_id, id) on delete cascade
);
create index thumb_jobs_due on public.thumb_jobs (next_attempt_at)
  where status in ('pending', 'running');
alter table public.thumb_jobs enable row level security;
-- No policies: only the functions below touch it.

-- ── Fast path: a client re-pushes a stale expiring URL we already cached ──
-- The phone keeps whatever image_url it last saw and sends it back on every
-- edit. Swap our copy in before the row is written: zero HTTP, and the
-- bumped updated_at means the phone pulls the correction straight back.
create or replace function public.thumb_inline()
returns trigger language plpgsql security definer set search_path = public as $$
declare cached text;
begin
  if not public.thumb_is_expiring(new.image_url) then return new; end if;
  select public_url into cached from public.thumb_jobs
   where owner_id = new.owner_id and bookmark_id = new.id
     and status = 'done' and public_url is not null;
  if cached is not null then
    new.image_url := cached;
    -- bookmarks_touch stamps UPDATEs; an INSERT keeps the client's stamp
    -- unless we move it, and the client must learn about the swap.
    if tg_op = 'INSERT' then new.updated_at := greatest(coalesce(new.updated_at, now()), now()); end if;
  end if;
  return new;
exception when others then
  return new;
end $$;

create trigger bookmarks_thumb_inline
  before insert or update on public.bookmarks
  for each row execute function public.thumb_inline();

-- ── Enqueue + wake: one HTTP call per statement, however many rows ────────
create or replace function public.thumb_enqueue()
returns trigger language plpgsql security definer set search_path = public as $$
declare n int := 0; tok text;
begin
  insert into public.thumb_jobs (owner_id, bookmark_id, source_url)
  select r.owner_id, r.id, r.image_url
    from new_rows r
   where r.deleted_at is null and public.thumb_is_expiring(r.image_url)
  on conflict (owner_id, bookmark_id) do update
    set source_url      = excluded.source_url,
        enqueued_at     = now(),
        status          = case when thumb_jobs.status = 'running' then 'running' else 'pending' end,
        attempts        = case when thumb_jobs.status in ('failed', 'skipped') then 0 else thumb_jobs.attempts end,
        next_attempt_at = case when thumb_jobs.status = 'running' then thumb_jobs.next_attempt_at else now() end,
        last_error      = null;
  get diagnostics n = row_count;

  if n > 0 then
    begin
      select decrypted_secret into tok from vault.decrypted_secrets where name = 'thumb_token';
      if tok is not null then
        perform net.http_post(
          url     := 'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/thumb',
          headers := jsonb_build_object('Content-Type', 'application/json', 'x-thumb-token', tok),
          body    := jsonb_build_object('mode', 'drain', 'limit', 8, 'reason', lower(tg_op)),
          timeout_milliseconds := 8000);
      end if;
    exception when others then
      raise warning 'thumb wake failed: %', sqlerrm;   -- jobs stay queued; cron drains them
    end;
  end if;
  return null;
exception when others then
  raise warning 'thumb enqueue failed: %', sqlerrm;
  return null;
end $$;

-- A transition table is one event per trigger, hence two.
create trigger bookmarks_thumb_enqueue_ins
  after insert on public.bookmarks referencing new table as new_rows
  for each statement execute function public.thumb_enqueue();
create trigger bookmarks_thumb_enqueue_upd
  after update on public.bookmarks referencing new table as new_rows
  for each statement execute function public.thumb_enqueue();

-- ── RPCs for the Edge Function (service role only) ────────────────────────

-- Take up to p_limit due jobs (or one named job) and mark them running.
-- Returns what the function needs alongside: the page to re-read if the
-- CDN copy is dead, and whether the bookmark is still live.
create or replace function public.thumb_claim(
  p_limit int default 8, p_owner uuid default null, p_id text default null)
returns table (owner_id uuid, bookmark_id text, source_url text, page_url text,
               image_url text, deleted boolean, attempts int, enqueued_at timestamptz)
language plpgsql security definer set search_path = public as $$
begin
  return query
  with cand as (
    select j.owner_id, j.bookmark_id from public.thumb_jobs j
     where ( p_owner is null
             and ( (j.status = 'pending' and j.next_attempt_at <= now())
                or (j.status = 'running' and j.locked_at < now() - interval '5 minutes') )
             -- per-account cap: a hostile client cannot fill the bucket
             and (select count(*) from public.thumb_jobs d
                   where d.owner_id = j.owner_id and d.status = 'done') < 2000 )
        or ( p_owner is not null and j.owner_id = p_owner and j.bookmark_id = p_id )
     order by j.next_attempt_at, j.enqueued_at
     limit greatest(1, least(p_limit, 25))
     for update of j skip locked
  ), claimed as (
    update public.thumb_jobs j
       set status = 'running', locked_at = now(), attempts = j.attempts + 1
      from cand where j.owner_id = cand.owner_id and j.bookmark_id = cand.bookmark_id
    returning j.*
  )
  select c.owner_id, c.bookmark_id, c.source_url, b.url, b.image_url,
         (b.deleted_at is not null), c.attempts, c.enqueued_at
    from claimed c
    join public.bookmarks b on b.owner_id = c.owner_id and b.id = c.bookmark_id;
end $$;

-- Point the bookmark at our copy. Only if it still needs it: the user may
-- have replaced the image meanwhile. bookmarks_touch bumps updated_at, which
-- is how both clients learn about the new cover.
create or replace function public.thumb_apply(
  p_owner uuid, p_id text, p_public_url text, p_path text, p_bytes int, p_content_type text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  update public.bookmarks set image_url = p_public_url
   where owner_id = p_owner and id = p_id
     and deleted_at is null and public.thumb_is_expiring(image_url);
  get diagnostics n = row_count;
  update public.thumb_jobs
     set status = 'done', public_url = p_public_url, object_path = p_path,
         bytes = p_bytes, content_type = p_content_type,
         locked_at = null, last_error = null, done_at = now()
   where owner_id = p_owner and bookmark_id = p_id;
  return n;
end $$;

-- Release a job that didn't finish, with backoff; terminal after five tries.
create or replace function public.thumb_fail(
  p_owner uuid, p_id text, p_error text, p_status text default null)
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.thumb_jobs j
     set status = coalesce(p_status, case when j.attempts >= 5 then 'failed' else 'pending' end),
         next_attempt_at = now() + case j.attempts
                                     when 1 then interval '10 minutes'
                                     when 2 then interval '1 hour'
                                     when 3 then interval '6 hours'
                                     else interval '24 hours' end,
         locked_at = null,
         last_error = left(coalesce(p_error, 'unknown'), 300)
   where j.owner_id = p_owner and j.bookmark_id = p_id;
end $$;

-- Backfill: queue every live bookmark still pointing at an expiring URL.
create or replace function public.thumb_backfill(p_owner uuid default null)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into public.thumb_jobs (owner_id, bookmark_id, source_url, enqueued_at)
  select b.owner_id, b.id, b.image_url, now() - interval '1 minute'
    from public.bookmarks b
   where b.deleted_at is null and public.thumb_is_expiring(b.image_url)
     and (p_owner is null or b.owner_id = p_owner)
  on conflict (owner_id, bookmark_id) do update
    set status = 'pending', attempts = 0, next_attempt_at = now(), last_error = null,
        source_url = excluded.source_url
    where thumb_jobs.status <> 'running';
  get diagnostics n = row_count;
  return n;
end $$;

-- Supabase grants execute on new public functions to anon/authenticated by
-- default; these are for the service role only.
do $$ declare f text; begin
  foreach f in array array[
    'public.thumb_claim(int,uuid,text)',
    'public.thumb_apply(uuid,text,text,text,int,text)',
    'public.thumb_fail(uuid,text,text,text)',
    'public.thumb_backfill(uuid)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $$;

-- ── Retries and backfill: drain every minute, only when something is due ──
create extension if not exists pg_cron with schema pg_catalog;
grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

select cron.schedule('thumb-drain', '* * * * *', $$
  select net.http_post(
    url     := 'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/thumb',
    headers := jsonb_build_object('Content-Type', 'application/json',
                 'x-thumb-token', (select decrypted_secret from vault.decrypted_secrets where name = 'thumb_token')),
    body    := '{"mode":"drain","limit":8,"reason":"cron"}'::jsonb,
    timeout_milliseconds := 8000)
  where exists (select 1 from public.thumb_jobs
                 where (status = 'pending' and next_attempt_at <= now())
                    or (status = 'running' and locked_at < now() - interval '5 minutes'))
$$);

-- pg_cron logs every run; keep a week.
select cron.schedule('cron-log-prune', '0 12 * * *',
  $$ delete from cron.job_run_details where end_time < now() - interval '7 days' $$);
