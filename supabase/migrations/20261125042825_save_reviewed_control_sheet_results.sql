-- The experimental scan importer remains restricted at the database boundary.
-- Capture the entire section so another entry's result or a roster edit cannot
-- silently invalidate the placements/awards checked by the review screen.
create or replace function public.control_sheet_scan_snapshot(
  p_show_id uuid, p_section_ids uuid[]
) returns text
language plpgsql security definer set search_path = '' as $$
declare v_snapshot text;
begin
  if auth.uid() is null or not public.is_super_admin(auth.uid()) then
    raise exception 'Only super admins can save scanned results.' using errcode = '42501';
  end if;
  if coalesce(cardinality(p_section_ids), 0) = 0 or exists (
    select 1 from unnest(p_section_ids) s(id)
    where not exists (select 1 from public.show_sections ss where ss.id=s.id and ss.show_id=p_show_id)
  ) then
    raise exception 'The scanned section is unavailable for this show.';
  end if;
  if not exists (select 1 from public.shows where id=p_show_id and not is_locked) then
    raise exception 'This show is locked or unavailable. Unlock it before saving results.';
  end if;
  select md5(coalesce(jsonb_agg(
    to_jsonb(e) || jsonb_build_object('_awards', coalesce((
      select jsonb_agg(a.award_code order by a.award_code)
      from public.entry_awards a where a.entry_id=e.id and a.show_id=e.show_id
    ), '[]'::jsonb)) order by e.id
  ), '[]'::jsonb)::text) into v_snapshot
  from public.entries e where e.show_id=p_show_id and e.section_id=any(p_section_ids);
  return v_snapshot;
end;
$$;

create or replace function public.save_control_sheet_scan(
  p_show_id uuid, p_section_ids uuid[], p_snapshot text, p_changes jsonb
) returns integer
language plpgsql security definer set search_path = '' as $$
declare
  v_change jsonb;
  v_entry public.entries%rowtype;
  v_id uuid;
  v_status text;
  v_place text;
  v_awards text[];
  v_existing_awards text[];
  v_reason text;
  v_lock text;
  v_all_saved boolean := true;
  v_count integer;
begin
  if auth.uid() is null or not public.is_super_admin(auth.uid()) then
    raise exception 'Only super admins can save scanned results.' using errcode = '42501';
  end if;
  if jsonb_typeof(p_changes) is distinct from 'array' then
    raise exception 'The reviewed results must be a list.';
  end if;
  v_count := jsonb_array_length(p_changes);
  if v_count > 2000 then raise exception 'Save at most 2000 reviewed entries at a time.'; end if;
  if exists (select 1 from jsonb_array_elements(p_changes) c group by c->>'entry_id' having count(*)>1) then
    raise exception 'An entry appears more than once in the reviewed batch.';
  end if;

  -- Use the same locks as normal Results Entry, in a stable order for a batch.
  for v_lock in
    select distinct 'qr-results:'||e.show_id::text||':'||e.section_id::text||':'||lower(trim(e.breed))
    from public.entries e where e.show_id=p_show_id and e.section_id=any(p_section_ids)
    order by 1
  loop
    perform pg_advisory_xact_lock(hashtextextended(v_lock, 0));
  end loop;
  -- This also checks show/section access and lock state, including empty batches.
  v_lock := public.control_sheet_scan_snapshot(p_show_id, p_section_ids);

  for v_change in select c from jsonb_array_elements(p_changes) c order by c->>'entry_id'
  loop
    v_id := (v_change->>'entry_id')::uuid;
    select * into v_entry from public.entries
    where id=v_id and show_id=p_show_id and section_id=any(p_section_ids) for update;
    if not found then raise exception 'A reviewed entry is no longer in this show and section.'; end if;
    if lower(v_entry.status) in ('deleted','removed','withdrawn','cancelled','canceled') then
      raise exception 'A reviewed entry has been removed.';
    end if;
    v_status := v_change->>'result_status';
    v_place := nullif(v_change->>'placement', '');
    if v_status is null or v_status <> all(array[
      'Shown','No Show','Scratched','Unworthy of Award',
      'Disqualified - Wrong Sex','Disqualified - Wrong Variety','Disqualified - Wrong Class',
      'Disqualified - Overweight','Disqualified - Wrong Tattoo','Disqualified - Other'
    ]) then raise exception 'An outcome is invalid.'; end if;
    if jsonb_typeof(v_change->'awards') is distinct from 'array' then
      raise exception 'The reviewed awards must be a list.';
    end if;
    select coalesce(array_agg(distinct a order by a), array[]::text[]) into v_awards
    from jsonb_array_elements_text(v_change->'awards') a;
    if exists (select 1 from unnest(v_awards) a where a <> all(array['BOV','BOSV','BOG','BOSG','BOB','BOSB'])) then
      raise exception 'A special award is invalid.';
    end if;
    if v_status='Shown' then
      if v_place is null or v_place !~ '^(0|[1-9]|1[0-9]|20)$' then
        raise exception 'A placement must be 1 through 20, or NP.';
      end if;
      if cardinality(v_awards)>0 and (v_place<>'1' or v_entry.is_fur) then
        raise exception 'Only an eligible first-place breed entry can receive specials.';
      end if;
      if v_entry.scratched_at is not null or lower(v_entry.status)='scratched' then
        raise exception 'A scratched entry must be restored in Results Entry before placing it.';
      end if;
    elsif v_place is not null or cardinality(v_awards)>0 then
      raise exception 'Scratches, No Show, and disqualifications cannot also have placements or awards.';
    end if;
    v_reason := case when v_status like 'Disqualified - %' then substr(v_status,16) end;
    select coalesce(array_agg(a.award_code order by a.award_code), array[]::text[]) into v_existing_awards
    from public.entry_awards a where a.entry_id=v_id and a.show_id=p_show_id;
    v_all_saved := v_all_saved and (
      (case when v_entry.is_fur then v_entry.fur_placement::text else v_entry.placement end) is not distinct from v_place
      and v_entry.result_status is not distinct from v_status
      and v_entry.is_shown=(v_status not in ('No Show','Scratched'))
      and v_entry.is_disqualified=(v_status like 'Disqualified - %')
      and v_entry.disqualified_reason is not distinct from v_reason
      and (v_status<>'Scratched' or v_entry.scratched_at is not null)
      and v_existing_awards=v_awards
    );
  end loop;
  -- A committed batch can be retried after losing the response, without new
  -- timestamps, scratch audit events, or award/report side effects.
  if v_count>0 and v_all_saved then return v_count; end if;
  if p_snapshot is distinct from v_lock then
    raise exception 'The show entries or results changed during review. Check the results again before saving.';
  end if;

  for v_change in select c from jsonb_array_elements(p_changes) c order by c->>'entry_id'
  loop
    v_id := (v_change->>'entry_id')::uuid;
    select * into strict v_entry from public.entries where id=v_id;
    v_status := v_change->>'result_status';
    select coalesce(array_agg(distinct a order by a), array[]::text[]) into v_awards
      from jsonb_array_elements_text(v_change->'awards') a;
    if v_status='Scratched' and v_entry.scratched_at is null then
      perform public.set_entry_scratch_state(v_id, true);
    end if;
    perform public.save_results_entry(
      p_show_id, v_id, nullif(v_change->>'placement',''), v_status,
      case when v_status like 'Disqualified - %' then substr(v_status,16) end,
      v_status not in ('No Show','Scratched'), v_status like 'Disqualified - %',
      v_entry.judged_by_show_judge_id, null, null, v_awards, false
    );
  end loop;

  -- NP may repeat, positive placements may not. Fur results keep their own scope.
  if exists (
    select 1 from public.entries e
    where e.show_id=p_show_id and e.section_id=any(p_section_ids)
      and e.scratched_at is null and lower(e.status)<>'scratched'
      and e.is_shown and not e.is_disqualified
      and coalesce(case when e.is_fur then e.fur_placement::text else e.placement end,'') ~ '^[1-9][0-9]*$'
    group by e.section_id, e.species, lower(trim(e.breed)), e.is_fur,
      lower(trim(case when e.is_fur then coalesce(e.fur_variety,e.variety,'') else coalesce(e.variety,'') end)),
      case when e.is_fur then '' else lower(trim(coalesce(e.sex::text,''))) end,
      lower(trim(coalesce(e.class_name,''))),
      case when e.is_fur then e.fur_placement::text else e.placement end
    having count(*)>1 and bool_or(e.id in (select (c->>'entry_id')::uuid from jsonb_array_elements(p_changes) c))
  ) then raise exception 'Two reviewed entries have the same placement in one class.'; end if;
  return v_count;
end;
$$;

revoke all on function public.control_sheet_scan_snapshot(uuid,uuid[]) from public, anon;
revoke all on function public.save_control_sheet_scan(uuid,uuid[],text,jsonb) from public, anon;
grant execute on function public.control_sheet_scan_snapshot(uuid,uuid[]) to authenticated;
grant execute on function public.save_control_sheet_scan(uuid,uuid[],text,jsonb) to authenticated;
