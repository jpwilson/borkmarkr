-- Additive: deploy before clients that write brief fields.
alter table public.missions
  add column if not exists brief_text text,
  add column if not exists brief_at timestamptz,
  add column if not exists brief_bork_count integer;

-- A server-receipt timestamp cannot represent an offline user's edit time.
-- Reject stale/equal updates atomically, including from older direct-upsert
-- clients. Keep tombstones and original creation times intact.
create or replace function public.preserve_client_revision()
returns trigger language plpgsql set search_path = public as $$
begin
  if new.updated_at <= old.updated_at then return null; end if;
  new.created_at = old.created_at;
  return new;
end $$;

drop trigger if exists missions_touch on public.missions;
create trigger missions_client_revision before update on public.missions
  for each row execute function public.preserve_client_revision();
