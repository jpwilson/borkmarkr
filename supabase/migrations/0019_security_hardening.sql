-- Security hardening, November 2026 audit. Three independent tightenings;
-- none changes what either client does today.
--
-- 1. Profiles are readable by their owner only. 0001 made every profile
--    readable by every signed-in account so that people could look each
--    other up to grant a collection. That lookup was never built: both
--    clients read only their own row, and the public collection page gets
--    the owner's name through `collection_by_slug` (security definer), which
--    this does not touch. Until a lookup exists, nobody else's handle or
--    display name should be listable.
--
-- 2. A bookmark is only ever visible through a collection its OWN owner
--    curated. 0011 stopped new collection_items rows naming someone else's
--    bookmark, but the read policy from 0001 still trusted whatever rows
--    exist. Say the rule in the policy itself, and drop any row that breaks
--    it, so the guarantee does not depend on an insert check having always
--    been there.
--
-- 3. Signup notification emails get the same flood guard as feedback (0009):
--    beta_signups is insert-only for anon, so anyone can make the inbox ring.
--    Rows are still kept; only the email is skipped past 20 in ten minutes.

-- ── 1. Profiles ─────────────────────────────────────────────────────────
drop policy if exists "profiles are readable" on public.profiles;
drop policy if exists "own profile is readable" on public.profiles;
create policy "own profile is readable" on public.profiles
  for select to authenticated using (id = auth.uid());

-- ── 2. Shared bookmarks follow their own owner's collections only ───────
delete from public.collection_items ci
 using public.collections c
 where c.id = ci.collection_id
   and ci.bookmark_owner <> c.owner_id;

drop policy if exists "bookmarks visible through shared collections" on public.bookmarks;
create policy "bookmarks visible through shared collections" on public.bookmarks
  for select to authenticated using (
    deleted_at is null
    and exists (
      select 1
      from public.collection_items ci
      join public.collections c on c.id = ci.collection_id
      where ci.bookmark_owner = bookmarks.owner_id
        and ci.bookmark_id = bookmarks.id
        and c.owner_id = bookmarks.owner_id
        and public.can_view_collection(c)
    )
  );

-- ── 3. Signup notification flood guard ──────────────────────────────────
create or replace function public.notify_signup()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare tok text; recent int;
begin
  select count(*) into recent from public.beta_signups where created_at > now() - interval '10 minutes';
  if recent > 20 then return new; end if;
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
