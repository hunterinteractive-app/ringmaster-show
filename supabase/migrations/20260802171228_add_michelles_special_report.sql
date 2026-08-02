alter type public.report_type add value if not exists 'michelles_special_report';

create or replace function public.michelles_special_report_rows(p_show_id uuid)
returns table (
  exhibitor_name text,
  entered_animal_count integer
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null or (
    auth.uid() is distinct from '96d62792-7aad-49da-a27a-4fb496289176'::uuid
    and not public.is_super_admin()
  ) then
    raise exception 'Michelle’s Special Report is not available to this user';
  end if;

  if not exists (
    select 1
    from public.shows s
    where s.id = p_show_id
      and s.created_by = '96d62792-7aad-49da-a27a-4fb496289176'::uuid
  ) then
    raise exception 'Michelle’s Special Report is not available for this show';
  end if;

  return query
  select
    coalesce(
      nullif(trim(concat_ws(' ', e.first_name, e.last_name)), ''),
      nullif(trim(e.display_name), ''),
      'Unnamed Exhibitor'
    ) as exhibitor_name,
    count(en.id)::integer as entered_animal_count
  from public.entries en
  join public.exhibitors e on e.id = en.exhibitor_id
  where en.show_id = p_show_id
    and coalesce(en.is_shown, true)
    and en.scratched_at is null
  group by e.id, e.first_name, e.last_name, e.display_name
  order by exhibitor_name;
end;
$$;

revoke all on function public.michelles_special_report_rows(uuid) from public;
grant execute on function public.michelles_special_report_rows(uuid) to authenticated;
