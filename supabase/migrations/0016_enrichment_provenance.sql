-- Nullable = legacy/unknown. Never infer that an old choice was machine-made.
alter table public.bookmarks
  add column if not exists filing_source text check (filing_source in ('automatic','user')),
  add column if not exists tags_edited boolean,
  add column if not exists title_edited boolean,
  add column if not exists enrichment_version integer,
  add column if not exists enrichment_attempts integer,
  add column if not exists enrichment_attempted_at timestamptz;
comment on column public.bookmarks.filing_source is 'Null preserves legacy filing; automatic permits enrichment; user never auto-refiles.';

-- Background web enrichment is a compare-and-swap, never a whole-row upsert.
-- A manual edit made during the fetch wins. RLS and auth.uid scope every write.
create or replace function public.apply_bookmark_preview(p_id text, p_expected timestamptz, p_preview jsonb)
returns setof public.bookmarks language sql security invoker set search_path = public as $$
  update public.bookmarks set
    title = case when title_edited is true then title else coalesce(nullif(p_preview->>'title',''),title) end,
    body_text = coalesce(nullif(body_text,''), nullif(p_preview->>'body_text','')),
    image_url = coalesce(nullif(p_preview->>'image_url',''),image_url),
    author = coalesce(author,nullif(p_preview->>'author','')),
    enrichment_version = (p_preview->>'enrichment_version')::integer,
    enrichment_attempts = coalesce(enrichment_attempts,0)+1,
    enrichment_attempted_at = now(), updated_at = now()
  where owner_id = auth.uid() and id = p_id and updated_at = p_expected and deleted_at is null
  returning *;
$$;
revoke all on function public.apply_bookmark_preview(text,timestamptz,jsonb) from public;
grant execute on function public.apply_bookmark_preview(text,timestamptz,jsonb) to authenticated;
