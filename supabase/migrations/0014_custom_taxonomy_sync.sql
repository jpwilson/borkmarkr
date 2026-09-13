create table public.custom_topics (
  owner_id uuid not null references public.profiles on delete cascade,
  id text not null check (id like 'custom.%'),
  name text not null check (length(trim(name)) > 0),
  hue double precision not null,
  image_url text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  primary key(owner_id, id)
);
create table public.custom_subtopics (
  owner_id uuid not null references public.profiles on delete cascade,
  id text not null,
  category_id text not null,
  name text not null check (length(trim(name)) > 0),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  deleted_at timestamptz,
  primary key(owner_id, id)
);
alter table public.custom_topics enable row level security;
alter table public.custom_subtopics enable row level security;
create policy "own custom topics" on public.custom_topics for all to authenticated
  using(owner_id = auth.uid()) with check(owner_id = auth.uid());
create policy "own custom subtopics" on public.custom_subtopics for all to authenticated
  using(owner_id = auth.uid()) with check(owner_id = auth.uid());
create trigger custom_topics_revision before update on public.custom_topics
  for each row execute function public.preserve_client_revision();
create trigger custom_subtopics_revision before update on public.custom_subtopics
  for each row execute function public.preserve_client_revision();
