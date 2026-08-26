-- Beta-tester email list for bookmarker.lol. Insert-only from the public
-- site; nothing can be read back through the API (no select policy).
-- Applied to project pcjuxnhqxyfvgagnblzv on 2026-08-25.
create table public.beta_signups (
  id         uuid primary key default gen_random_uuid(),
  email      text not null,
  source     text,
  created_at timestamptz not null default now()
);
create unique index beta_signups_email_idx on public.beta_signups (lower(email));

alter table public.beta_signups enable row level security;

create policy "anyone may join the list"
  on public.beta_signups for insert
  to anon, authenticated
  with check (
    email ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'
    and length(email) <= 254
    and (source is null or length(source) <= 40)
  );

revoke all on public.beta_signups from anon, authenticated;
grant insert (email, source) on public.beta_signups to anon, authenticated;
