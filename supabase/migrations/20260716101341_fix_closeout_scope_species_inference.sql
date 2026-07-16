-- A sanctioned breed name can differ from the master breed/entry spelling.
-- Prefer an unambiguous club-name species token before falling back to every
-- entry in a mixed-species section, and never allow a null species to pass the
-- canonical scope validation check.

create or replace function public.resolve_closeout_artifact_scope(
  p_show_id uuid,
  p_finalize_run_id uuid,
  p_report_name public.report_type,
  p_metadata jsonb
)
returns table(
  is_repairable boolean,
  failure_reason text,
  scope_key text,
  section_ids uuid[],
  metadata jsonb,
  artifact_key text
)
language plpgsql
stable
security invoker
set search_path = ''
as $function$
declare
  v_run public.show_finalize_runs%rowtype;
  v_metadata jsonb := coalesce(p_metadata, '{}'::jsonb);
  v_section public.show_sections%rowtype;
  v_section_id uuid;
  v_exhibitor_id uuid;
  v_sections uuid[];
  v_species text;
  v_club_name text;
  v_identity text;
begin
  select f.* into v_run
  from public.show_finalize_runs f
  where f.id = p_finalize_run_id and f.show_id = p_show_id;

  if v_run.id is null or cardinality(coalesce(v_run.section_ids, '{}'::uuid[])) = 0 then
    return query select false, 'missing_finalize_run_scope', null::text,
      '{}'::uuid[], v_metadata, null::text;
    return;
  end if;

  if p_report_name::text in (
    'arba_report', 'sweepstakes_report', 'breed_results_detail_report',
    'details_by_breed', 'exh_by_breed', 'best_display_report'
  ) then
    if coalesce(v_metadata ->> 'section_id', '') !~*
       '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return query select false, 'missing_section_id', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    v_section_id := (v_metadata ->> 'section_id')::uuid;
    select s.* into v_section
    from public.show_sections s
    where s.id = v_section_id and s.show_id = p_show_id
      and s.id = any(v_run.section_ids);
    if v_section.id is null then
      return query select false, 'section_not_in_finalize_scope', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    if nullif(btrim(v_metadata ->> 'scope'), '') is not null
       and upper(btrim(v_metadata ->> 'scope')) <> upper(v_section.kind::text) then
      return query select false, 'section_kind_mismatch', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    if nullif(btrim(v_metadata ->> 'show_letter'), '') is not null
       and upper(btrim(v_metadata ->> 'show_letter')) <> upper(v_section.letter) then
      return query select false, 'show_letter_mismatch', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    v_sections := array[v_section.id];
    v_metadata := v_metadata || jsonb_build_object(
      'section_id', v_section.id,
      'scope', upper(v_section.kind::text),
      'show_letter', upper(v_section.letter)
    );

    if p_report_name::text in (
      'sweepstakes_report', 'breed_results_detail_report',
      'details_by_breed', 'exh_by_breed', 'best_display_report'
    ) then
      if nullif(btrim(v_metadata ->> 'breed_name'), '') is null
         and p_report_name::text in ('sweepstakes_report', 'breed_results_detail_report') then
        return query select false, 'missing_breed_name', null::text,
          '{}'::uuid[], v_metadata, null::text;
        return;
      end if;
      v_species := lower(nullif(btrim(v_metadata ->> 'species'), ''));
      if v_species is null and nullif(btrim(v_metadata ->> 'breed_name'), '') is not null then
        select case when count(distinct lower(b.species::text)) = 1
                    then min(lower(b.species::text)) end
        into v_species
        from public.breeds b
        where lower(btrim(b.name)) = lower(btrim(v_metadata ->> 'breed_name'));
      end if;
      if v_species is null then
        v_club_name := lower(coalesce(v_metadata ->> 'club_name', ''));
        v_species := case
          when v_club_name ~ '(^|[^a-z])rabbit([^a-z]|$)'
               and v_club_name !~ '(^|[^a-z])cavy([^a-z]|$)'
            then 'rabbit'
          when v_club_name ~ '(^|[^a-z])cavy([^a-z]|$)'
               and v_club_name !~ '(^|[^a-z])rabbit([^a-z]|$)'
            then 'cavy'
          else null
        end;
      end if;
      if v_species is null then
        select case when count(distinct lower(e.species::text)) = 1
                    then min(lower(e.species::text)) end
        into v_species
        from public.entries e
        where e.show_id = p_show_id and e.section_id = v_section.id
          and e.is_shown = true and e.scratched_at is null;
      end if;
      if v_species is null or v_species not in ('rabbit', 'cavy') then
        return query select false, 'ambiguous_species', null::text,
          '{}'::uuid[], v_metadata, null::text;
        return;
      end if;
      v_metadata := v_metadata || jsonb_build_object('species', v_species);
    end if;
  elsif p_report_name::text in ('exhibitor_report', 'checkin_sheet', 'legs') then
    if coalesce(v_metadata ->> 'exhibitor_id', '') !~*
       '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return query select false, 'missing_exhibitor_id', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
    v_exhibitor_id := (v_metadata ->> 'exhibitor_id')::uuid;
    select array_agg(distinct e.section_id order by e.section_id)
    into v_sections
    from public.entries e
    where e.show_id = p_show_id and e.exhibitor_id = v_exhibitor_id
      and e.section_id = any(v_run.section_ids)
      and e.is_shown = true
      and e.scratched_at is null
      and coalesce(e.is_disqualified, false) = false
      and coalesce(e.is_test, false) = false
      and lower(coalesce(e.status, '')) not in (
        'deleted', 'cancelled', 'canceled', 'scratched'
      )
      and lower(btrim(coalesce(e.result_status, ''))) not in (
        'no show', 'no_show', 'noshow', 'disqualified', 'dq',
        'unworthy of award', 'unworthy'
      );
    if cardinality(coalesce(v_sections, '{}'::uuid[])) = 0 then
      return query select false, 'missing_exhibitor_entries', null::text,
        '{}'::uuid[], v_metadata, null::text;
      return;
    end if;
  elsif p_report_name::text in (
    'unpaid_balances_report', 'paid_exhibitor_report',
    'entered_exhibitors_contact_report', 'ribbon_payout_report',
    'payback_report', 'judge_report', 'breed_judged_totals_report'
  ) then
    v_sections := v_run.section_ids;
  else
    return query select false, 'unsupported_report_scope', null::text,
      '{}'::uuid[], v_metadata, null::text;
    return;
  end if;

  v_sections := array(
    select distinct section_id from unnest(v_sections) section_id order by section_id
  );
  v_metadata := v_metadata || jsonb_build_object(
    'run_scope_key', v_run.scope_key,
    'section_ids', to_jsonb(v_sections)
  );
  v_identity := public.closeout_artifact_identity(p_report_name, v_metadata);
  scope_key := public.closeout_artifact_scope_key(
    p_show_id, p_report_name, v_sections, v_metadata
  );
  metadata := v_metadata || jsonb_build_object('scope_key', scope_key);
  section_ids := v_sections;
  artifact_key := v_identity;
  is_repairable := true;
  failure_reason := null;
  return next;
end;
$function$;

comment on function public.resolve_closeout_artifact_scope(
  uuid, uuid, public.report_type, jsonb
)
is 'Resolves canonical Closeout scope and species, including unambiguous rabbit/cavy club-name inference before mixed-section fallback.';
