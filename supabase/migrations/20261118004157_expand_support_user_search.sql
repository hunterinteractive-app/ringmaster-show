-- Search login identities even when their optional profile fields are blank.
-- The privileged auth lookup stays outside the exposed API schema.
create schema if not exists support_search_private;
revoke all on schema support_search_private from public, anon;
grant usage on schema support_search_private to authenticated;

create or replace function support_search_private.search_users(
  p_query text default '', p_limit integer default 100
)
returns table(user_id uuid, email text, display_name text, exhibitor_name text)
language plpgsql stable security definer set search_path = ''
as $$
declare
  q text := btrim(coalesce(p_query, ''));
  tokens text[];
begin
  if auth.uid() is null or not coalesce(public.is_super_admin(auth.uid()), false) then
    raise exception 'Super administrator access is required.' using errcode = '42501';
  end if;
  if length(q) > 256 then
    raise exception 'Search must be 256 characters or fewer.' using errcode = '22023';
  end if;
  tokens := array(select t from regexp_split_to_table(lower(q), '[[:space:],]+') t where t <> '');
  if q <> '' and (length(q) < 2 or cardinality(tokens) = 0) then return; end if;

  return query
  with exhibitor_names as (
    select e.owner_user_id,
      string_agg(distinct coalesce(nullif(btrim(e.display_name), ''),
        nullif(btrim(e.showing_name), ''),
        nullif(btrim(concat_ws(' ', e.first_name, e.last_name)), '')), '; ') as names,
      string_agg(concat_ws(' ', e.email, e.display_name, e.showing_name,
        e.first_name, e.last_name), ' ') as search_text
    from public.exhibitors e
    where e.owner_user_id is not null and not coalesce(e.is_merged, false)
    group by e.owner_user_id
  ), candidates as (
    select u.id,
      coalesce(nullif(u.email, ''), p.email, '')::text as login_email,
      coalesce(nullif(btrim(p.display_name), ''),
        nullif(btrim(u.raw_user_meta_data->>'display_name'), ''),
        nullif(btrim(u.raw_user_meta_data->>'full_name'), ''),
        nullif(btrim(u.raw_user_meta_data->>'name'), ''), '')::text as profile_name,
      coalesce(e.names, '') as names,
      lower(concat_ws(' ', u.id::text, u.email, p.email, p.display_name,
        u.raw_user_meta_data->>'display_name', u.raw_user_meta_data->>'full_name',
        u.raw_user_meta_data->>'name', u.raw_user_meta_data->>'first_name',
        u.raw_user_meta_data->>'last_name', e.search_text)) as search_text
    from auth.users u
    left join public.profiles p on p.user_id = u.id
    left join exhibitor_names e on e.owner_user_id = u.id
    where u.deleted_at is null
  )
  select c.id, c.login_email, c.profile_name, c.names
  from candidates c
  where not exists (
    select 1 from unnest(tokens) t where strpos(c.search_text, t) = 0
  )
  order by case when lower(c.login_email) = lower(q) then 0 else 1 end,
    lower(c.login_email), c.id
  limit greatest(1, least(coalesce(p_limit, 100), 200));
end;
$$;
revoke all on function support_search_private.search_users(text, integer) from public, anon;
grant execute on function support_search_private.search_users(text, integer) to authenticated;

create or replace function public.search_support_users(
  p_query text default '', p_limit integer default 100
)
returns table(user_id uuid, email text, display_name text, exhibitor_name text)
language sql stable security invoker set search_path = ''
as $$
  select * from support_search_private.search_users(p_query, p_limit);
$$;
revoke all on function public.search_support_users(text, integer) from public, anon;
grant execute on function public.search_support_users(text, integer) to authenticated;
