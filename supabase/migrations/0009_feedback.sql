-- Feedback and problem reports from the Help tab, plus a fix for 0007: the
-- signup-notify token was a literal in the trigger body (so it is in git
-- history). Both notify triggers now read the token from Vault, and one
-- generalised `notify` Edge Function replaces `notify-signup`.
--
-- One-time setup (the token is never in git):
--   select vault.create_secret('<random>', 'notify_token');   -- SQL editor
--   supabase secrets set NOTIFY_TOKEN=<same random>
--   supabase functions deploy notify   (config.toml sets verify_jwt = false)
--   supabase functions delete notify-signup

-- ── The table ───────────────────────────────────────────────────────────
-- Insert-only through the API, like beta_signups: nothing can be read back
-- (no select policy), user_id is never client-settable (not in the column
-- grant; the default fills it), and a signed-in sender has no contact field
-- because their account already identifies them. Rows go with the account.
create table public.feedback (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid default auth.uid() references auth.users on delete cascade,
  kind       text not null check (kind in ('idea', 'problem', 'other')),
  message    text not null check (length(message) between 3 and 2000),
  contact    text check (contact is null or (length(contact) <= 254
               and contact ~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  context    text check (context is null or length(context) <= 160),   -- device / viewport, for bug reports
  created_at timestamptz not null default now()
);

alter table public.feedback enable row level security;

create policy "anyone may send feedback"
  on public.feedback for insert
  to anon, authenticated
  with check (user_id is not distinct from auth.uid()
              and (contact is null or auth.uid() is null));

revoke all on public.feedback from anon, authenticated;
grant insert (kind, message, contact, context) on public.feedback to anon, authenticated;

-- ── Notifications ───────────────────────────────────────────────────────
-- Fire-and-forget through pg_net: a failed notification must never fail the
-- insert. Security definer so the trigger can read Vault; not callable via
-- PostgREST (trigger functions are not exposed as RPC).
create or replace function public.notify_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare tok text;
begin
  select decrypted_secret into tok from vault.decrypted_secrets where name = 'notify_token';
  if tok is null then return new; end if;
  perform net.http_post(
    url     := 'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/notify',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-notify-token', tok),
    body    := jsonb_build_object('kind', 'signup', 'email', new.email, 'source', new.source, 'at', now()),
    timeout_milliseconds := 8000);
  return new;
exception when others then
  return new;
end $$;

-- Anyone can insert, so anyone can make the inbox ring. After 20 messages in
-- ten minutes the rows are still kept; only the email is skipped.
create or replace function public.notify_feedback()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare tok text; who text; recent int;
begin
  select count(*) into recent from public.feedback where created_at > now() - interval '10 minutes';
  if recent > 20 then return new; end if;
  select decrypted_secret into tok from vault.decrypted_secrets where name = 'notify_token';
  if tok is null then return new; end if;
  if new.user_id is not null then
    select email into who from auth.users where id = new.user_id;
  end if;
  perform net.http_post(
    url     := 'https://pcjuxnhqxyfvgagnblzv.supabase.co/functions/v1/notify',
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-notify-token', tok),
    body    := jsonb_build_object('kind', 'feedback', 'feedback_kind', new.kind, 'message', new.message,
                 'contact', coalesce(new.contact, who), 'user_id', new.user_id, 'context', new.context, 'at', now()),
    timeout_milliseconds := 8000);
  return new;
exception when others then
  return new;
end $$;

create trigger feedback_notify
  after insert on public.feedback
  for each row execute function public.notify_feedback();
