-- Aggregate inside Postgres instead of serializing every entry for the dashboard.
-- Invoker security preserves the existing entry visibility/RLS rules.
create or replace function public.secretary_show_entry_counts(p_show_id uuid)
returns jsonb
language sql stable security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(to_jsonb(counts) order by counts.sort_order), '[]'::jsonb)
  from (
    select s.id as section_id, s.kind, s.letter, s.display_name, s.sort_order,
           count(e.id) as entry_count
    from public.show_sections s
    left join public.entries e
      on e.show_id = p_show_id and e.section_id = s.id
      and e.scratched_at is null
      and lower(coalesce(e.status, '')) <> 'scratched'
    where s.show_id = p_show_id and s.is_enabled = true
    group by s.id, s.kind, s.letter, s.display_name, s.sort_order
  ) counts;
$$;
revoke all on function public.secretary_show_entry_counts(uuid) from public, anon;
grant execute on function public.secretary_show_entry_counts(uuid) to authenticated, service_role;
