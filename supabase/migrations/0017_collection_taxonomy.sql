-- Preserve expiry/ownership gates and the explicit public field allowlist.
-- Private per-bookmark notes remain excluded; single-note sharing is opt-in text.
create or replace function public.collection_by_slug(p_slug text)
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  with found as (
    select c.*
      from public.collections c
     where p_slug ~ '^[a-z0-9]{8,16}$'
       and c.slug = p_slug
       and c.visibility = 'public'
       and c.deleted_at is null
       and (c.expires_at is null or c.expires_at > now())
     limit 1
  )
  select jsonb_build_object(
    'id',         f.id,
    'name',       f.name,
    'note',       f.note,
    'owner_name', coalesce(nullif(btrim(p.display_name), ''),
                           nullif(btrim(p.handle), ''),
                           'Someone'),
    'updated_at', f.updated_at,
    -- The page prints "Link open until …" from this. Null when it never closes.
    'expires_at', f.expires_at,
    'items', coalesce((
      select jsonb_agg(
               jsonb_build_object(
                 'id',               b.id,
                 'url',              b.url,
                 'title',            b.title,
                 'author',           b.author,
                 'platform',         b.platform,
                 'kind',             b.kind,
                 'category_id',      b.category_id,
                 'category_name',    ct.name,
                 'subcategory',      b.subcategory,
                 'tags',             b.tags,
                 'image_url',        b.image_url,
                 'duration_seconds', b.duration_seconds,
                 'body_text',        b.body_text
               )
               order by ci.position, ci.added_at
             )
        from public.collection_items ci
        join public.bookmarks b
          on b.owner_id = ci.bookmark_owner
         and b.id       = ci.bookmark_id
       left join public.custom_topics ct on ct.owner_id = f.owner_id and ct.id = b.category_id and ct.deleted_at is null
       where ci.collection_id = f.id
         and b.owner_id = f.owner_id
         and b.deleted_at is null
    ), '[]'::jsonb)
  )
  from found f
  join public.profiles p on p.id = f.owner_id;
$$;

revoke all on function public.collection_by_slug(text) from public;
grant execute on function public.collection_by_slug(text) to anon, authenticated, service_role;
