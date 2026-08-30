-- Codify a column that exists in the live database but never made it into a
-- migration: the iOS client has pushed and pulled image_url since sync
-- shipped, so someone added it by hand. Idempotent, so it is safe both on the
-- drifted production database and on a fresh one.

alter table public.bookmarks add column if not exists image_url text;
