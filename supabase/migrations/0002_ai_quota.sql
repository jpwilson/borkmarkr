-- Per-user daily cap on AI categorisation calls.
--
-- The Anthropic API key lives only in the Edge Function's environment, so it
-- can't be extracted from the app binary. But a key that can't be stolen can
-- still be *spent*: a signed-in client with a retry loop, or a bug that calls
-- categorise on every keystroke, bills the developer, not the user.
--
-- So the function consumes a quota before it ever calls Anthropic. One row per
-- user per UTC day, incremented atomically. Cost is therefore bounded by
-- (signed-in users × daily limit), which is a number you can actually reason
-- about, rather than by client behaviour, which you cannot.

create table public.ai_usage (
  user_id uuid not null references auth.users on delete cascade,
  day     date not null default (now() at time zone 'utc')::date,
  calls   int  not null default 0,
  primary key (user_id, day)
);

alter table public.ai_usage enable row level security;

-- Deliberately no policies. Nothing reaches this table except the
-- security-definer function below, so a client can't read other people's usage
-- and can't reset its own counter.

-- Increments the caller's counter and reports whether they were still inside
-- the limit. Returns false rather than raising, so the Edge Function can
-- degrade to the offline categoriser instead of failing the save.
create or replace function public.ai_quota_consume(daily_limit int default 200)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  uid  uuid := auth.uid();
  used int;
begin
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

revoke all on function public.ai_quota_consume(int) from public;
grant execute on function public.ai_quota_consume(int) to authenticated;
-- Supabase grants execute on new public functions to `anon` by default. The
-- function already fails closed for anonymous callers (auth.uid() is null, so
-- it returns false and the Edge Function skips the model), but a signed-out
-- caller shouldn't reach it at all. Two layers, because this one is what stands
-- between a public key and someone else's Anthropic bill.
revoke execute on function public.ai_quota_consume(int) from anon;
