do $block$
begin
  if to_regprocedure(
       'public.calculate_cavy_sweepstakes_for_section_unlocked(uuid,text,text)'
     ) is null then
    alter function public.calculate_cavy_sweepstakes_for_section(
      uuid, text, text
    ) rename to calculate_cavy_sweepstakes_for_section_unlocked;
  end if;
end;
$block$;

create or replace function public.calculate_cavy_sweepstakes_for_section(
  p_show_id uuid,
  p_scope text,
  p_show_letter text
)
returns integer
language plpgsql
security invoker
set search_path = ''
as $function$
declare
  v_lock_key text := concat_ws(
    ':',
    p_show_id::text,
    upper(btrim(coalesce(p_scope, ''))),
    upper(btrim(coalesce(p_show_letter, '')))
  );
begin
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_lock_key, 0)
  );
  return public.calculate_cavy_sweepstakes_for_section_unlocked(
    p_show_id,
    p_scope,
    p_show_letter
  );
end;
$function$;

revoke all on function public.calculate_cavy_sweepstakes_for_section(
  uuid, text, text
) from public, anon;
grant execute on function public.calculate_cavy_sweepstakes_for_section(
  uuid, text, text
) to authenticated, service_role;

alter function public.calculate_cavy_sweepstakes_for_section_unlocked(
  uuid, text, text
) set search_path = '';
