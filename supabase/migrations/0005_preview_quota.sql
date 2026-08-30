-- Per-user daily cap on link-preview fetches, mirroring 0002_ai_quota.sql.
--
-- The preview Edge Function fetches user-chosen URLs from our egress. That
-- costs bandwidth and CPU rather than API dollars, but unmetered it is still
-- someone else's free proxy. Same design as ai_quota_consume: consume before
-- fetching, fail closed for anonymous callers.

create table public.preview_usage (
  user_id uuid not null references auth.users on delete cascade,
  day     date not null default (now() at time zone 'utc')::date,
  calls   int  not null default 0,
  primary key (user_id, day)
);

alter table public.preview_usage enable row level security;
-- No policies on purpose: only the security-definer function touches it.

create or replace function public.preview_quota_consume(daily_limit int default 500)
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

  insert into public.preview_usage (user_id, day, calls)
  values (uid, (now() at time zone 'utc')::date, 1)
  on conflict (user_id, day)
    do update set calls = public.preview_usage.calls + 1
  returning calls into used;

  return used <= daily_limit;
end $$;

revoke all on function public.preview_quota_consume(int) from public;
grant execute on function public.preview_quota_consume(int) to authenticated;
revoke execute on function public.preview_quota_consume(int) from anon;
