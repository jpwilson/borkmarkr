-- Side quests, synced. The iOS Mission model (Core/Mission.swift) has lived
-- only in SwiftData until now; the web needs them server-side, and the phone
-- will sync to this table in 1.1. Column shapes mirror the Swift model
-- field-for-field so that sync is a straight mapping.

create table public.missions (
  id            text not null,                 -- UUID string minted by whichever client created it
  owner_id      uuid not null references public.profiles on delete cascade,

  title         text not null,
  detail        text,
  category_id   text,
  bookmark_ids  text[] not null default '{}',  -- IDs, not FKs: deleting a bork must never cascade into a quest

  habit_name    text,
  completed_days date[] not null default '{}',
  todos         jsonb,                          -- [{id, text, done}] — matches QuestTodo

  is_archived   boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  deleted_at    timestamptz,                    -- tombstone, same rule as bookmarks

  primary key (owner_id, id)
);

create index missions_owner_updated on public.missions (owner_id, updated_at);

alter table public.missions enable row level security;

create policy "own missions" on public.missions
  for all to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

create trigger missions_touch before update on public.missions
  for each row execute function public.touch_updated_at();
