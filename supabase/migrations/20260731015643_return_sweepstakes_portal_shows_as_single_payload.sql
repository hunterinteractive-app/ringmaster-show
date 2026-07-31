-- PostgREST applies the project row limit before the browser can request a
-- later page of an RPC result. Returning one JSON value avoids that cap while
-- preserving the authorization enforced by the existing portal function.
create or replace function public.get_sweepstakes_portal_shows_payload()
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    jsonb_agg(
      to_jsonb(portal_show)
      order by portal_show.show_date desc nulls last,
               portal_show.show_name,
               portal_show.section_label,
               portal_show.sanction_number
    ),
    '[]'::jsonb
  )
  from public.list_sweepstakes_portal_shows() as portal_show;
$$;

revoke all on function public.get_sweepstakes_portal_shows_payload() from public;
grant execute on function public.get_sweepstakes_portal_shows_payload() to authenticated;
