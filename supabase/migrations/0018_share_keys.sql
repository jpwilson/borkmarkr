-- Share keys: how the share sheet asks `categorize` however long it has been
-- since the app was opened.
--
-- The Share Extension borrows the app's session (Core/SessionKeychain.swift)
-- and never refreshes it: Supabase rotates refresh tokens, so a refresh there
-- would leave the app holding a spent one. An access token lasts an hour, so
-- until now the sheet could ask the model only if the app had been opened in
-- about the last hour.
--
-- So the app also holds a second, much narrower credential. `share_key_issue`
-- gives a signed-in session 32 random bytes tied to that session's id (the
-- access token's `session_id` claim), and this table keeps only their SHA-256.
-- The extension sends the key as `x-share-key`, and `categorize` spends it
-- through `ai_quota_consume_shared`, which only the service role may call. A
-- key does exactly one thing: spend its owner's existing 200-a-day AI quota.
-- It reads and writes nothing else.
--
-- A key dies with its session. Every use checks that the session's row still
-- exists, and Supabase deletes that row on sign-out ("the sessions affected by
-- the sign-out are removed from the database entirely"), when the session is
-- ended from somewhere else, and with the account, which also cascades here.
--
-- Safe to run twice. Run it in the SQL editor rather than `db push`, because
-- production has drifted from these files, then the probes in
-- Scripts/test_share_keys_sql.md.

create table if not exists public.share_keys (
  key_hash     bytea primary key,   -- sha256 of the key; the key is never stored
  user_id      uuid not null references auth.users on delete cascade,
  session_id   uuid not null,       -- auth.sessions.id, checked on every use
  created_at   timestamptz not null default now(),
  last_used_at timestamptz
);
create index if not exists share_keys_user_id_idx on public.share_keys (user_id);

alter table public.share_keys enable row level security;
-- Deliberately no policies and no grants. Nothing reaches this table except
-- the two security-definer functions below.
revoke all on public.share_keys from anon, authenticated;

-- A new key for the caller's session. It replaces the one that session had,
-- and clears out the caller's keys whose sessions have ended. Returned once,
-- as 64 hex characters, for the app's Keychain.
create or replace function public.share_key_issue()
returns text
language plpgsql
volatile
security definer
-- pgcrypto lives in `extensions` on Supabase (see 0011).
set search_path = public, extensions
as $$
declare
  uid    uuid := auth.uid();
  sid    uuid := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  secret bytea;
begin
  if uid is null or sid is null then
    raise exception 'sign in first' using errcode = '42501';
  end if;

  delete from public.share_keys k
   where k.user_id = uid
     and (k.session_id = sid
          or not exists (select 1 from auth.sessions s where s.id = k.session_id));

  secret := gen_random_bytes(32);
  insert into public.share_keys (key_hash, user_id, session_id)
  values (digest(secret, 'sha256'), uid, sid);
  return encode(secret, 'hex');
end $$;

revoke all on function public.share_key_issue() from public, anon;
grant execute on function public.share_key_issue() to authenticated;

-- `ai_quota_consume` (0002) for a share key: the same counter and the same
-- limit, charged to the key's owner. False for a malformed key, an unknown
-- one, or one whose session has ended, rather than raising, so `categorize`
-- answers "no answer" exactly as it does when the quota is spent.
create or replace function public.ai_quota_consume_shared(p_key text, daily_limit int default 200)
returns boolean
language plpgsql
volatile
security definer
set search_path = public, extensions
as $$
declare
  uid  uuid;
  used int;
begin
  if p_key is null or p_key !~ '^[0-9a-f]{64}$' then
    return false;
  end if;

  update public.share_keys k
     set last_used_at = now()
   where k.key_hash = digest(decode(p_key, 'hex'), 'sha256')
     and exists (select 1 from auth.sessions s where s.id = k.session_id and s.user_id = k.user_id)
  returning k.user_id into uid;
  if uid is null then
    return false;
  end if;

  insert into public.ai_usage (user_id, day, calls)
  values (uid, (now() at time zone 'utc')::date, 1)
  on conflict (user_id, day)
    do update set calls = public.ai_usage.calls + 1
  returning calls into used;

  return used <= daily_limit;
end $$;

-- Only `categorize`, which holds the service role, may spend a key. No client
-- can, signed in or not.
revoke all on function public.ai_quota_consume_shared(text, int) from public, anon, authenticated;
grant execute on function public.ai_quota_consume_shared(text, int) to service_role;
