create table public.bookmark_opens (
  owner_id uuid not null references public.profiles on delete cascade,
  id text not null,
  bookmark_id text not null,
  device_id text not null,
  open_count integer not null check(open_count >= 0),
  last_opened_at timestamptz,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  primary key(owner_id,id),
  unique(owner_id,bookmark_id,device_id)
);
alter table public.bookmark_opens enable row level security;
create policy "own open signals" on public.bookmark_opens for all to authenticated
  using(owner_id = auth.uid()) with check(owner_id = auth.uid());
create function public.merge_open_signal() returns trigger language plpgsql set search_path = public as $$
begin
  new.open_count = greatest(old.open_count, new.open_count);
  new.last_opened_at = greatest(old.last_opened_at, new.last_opened_at);
  new.updated_at = greatest(old.updated_at, new.updated_at);
  new.created_at = old.created_at;
  new.bookmark_id = old.bookmark_id;
  new.device_id = old.device_id;
  return new;
end $$;
create trigger bookmark_opens_merge before update on public.bookmark_opens
  for each row execute function public.merge_open_signal();
