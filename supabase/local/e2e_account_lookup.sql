-- Local prerequisite for the restored deployed account Edge Function (v16).
-- Exact normalized verified-email lookup, available only to its service client.
create or replace function public.find_unclaimed_exhibitors_by_email(p_email text)
returns table(id uuid,display_name text,showing_name text,first_name text,last_name text,
  email text,phone text,city text,state text,created_at timestamptz)
language sql security definer set search_path = '' as $$
  select e.id,e.display_name,e.showing_name,e.first_name,e.last_name,e.email,e.phone,e.city,e.state,e.created_at
  from public.exhibitors e where e.owner_user_id is null
    and lower(btrim(e.email))=lower(btrim(p_email))
    and coalesce(e.is_active,true) and not coalesce(e.is_test,false) and not coalesce(e.is_merged,false)
  order by e.updated_at desc nulls last,e.created_at desc limit 10;
$$;
revoke all on function public.find_unclaimed_exhibitors_by_email(text) from public,anon,authenticated;
grant execute on function public.find_unclaimed_exhibitors_by_email(text) to service_role;
