-- Resolve legacy rows at read time. Existing assignments and results are
-- deliberately left intact by this migration.
create function private.lineup_breed_assignments(p_show_ids uuid[])
returns table (assignment_id uuid, show_id uuid, section_id uuid, breed_id text,
  variety_key text, species text, explicit_species boolean, judge_id uuid,
  judge_type text, sort_order integer)
language sql stable set search_path = '' as $$
  select a.id,a.show_id,a.section_id,lower(btrim(a.breed_id)),
    lower(btrim(coalesce(a.variety_key,''))),
    coalesce(nullif(lower(btrim(a.species)),''),case
      when cardinality(b.species)=1 then b.species[1]
      when lower(btrim(j.judge_type::text))=any(b.species)
        then lower(btrim(j.judge_type::text))
    end),
    nullif(btrim(a.species),'') is not null,
    active.judge_id,lower(btrim(j.judge_type::text)),a.sort_order
  from public.show_judging_assignments a
  left join lateral (
    select m.judge_id from public.show_judging_assignments m
    where m.show_id=a.show_id and m.table_number=a.table_number
      and (m.is_judge_change or m.breed_id='__judge_change__')
      and m.sort_order<=a.sort_order and m.judge_id is not null
    order by m.sort_order desc,m.id limit 1
  ) active on true
  left join public.judges j on j.id=active.judge_id
  left join lateral (
    select array_agg(distinct lower(btrim(e.species::text))) as species
    from public.entries e
    where nullif(btrim(a.species),'') is null
      and e.show_id=a.show_id and e.section_id=a.section_id
      and lower(btrim(e.breed::text))=lower(btrim(a.breed_id))
      and (coalesce(btrim(a.variety_key),'')=''
        or lower(btrim(a.variety_key))=lower(btrim(coalesce(e.variety::text,''))))
  ) b on true
  where a.show_id=any(p_show_ids) and not a.is_judge_change
    and a.breed_id<>'__judge_change__';
$$;
revoke all on function private.lineup_breed_assignments(uuid[]) from public,anon,authenticated;

create function public.get_species_show_judging_lineup(p_show_id uuid)
returns setof jsonb
language sql stable security definer set search_path = '' as $$
  select to_jsonb(a)||jsonb_build_object('species',b.species)
  from public.get_show_judging_lineup(p_show_id) a
  left join private.lineup_breed_assignments(array[p_show_id]) b on b.assignment_id=a.id
  where public.user_can_view_show_lineup(p_show_id)
  order by a.judging_date nulls last,a.table_number,a.sort_order,a.created_at,a.id;
$$;
revoke all on function public.get_species_show_judging_lineup(uuid) from public,anon;
grant execute on function public.get_species_show_judging_lineup(uuid) to authenticated,service_role;

-- Keep the existing RPC contract for older clients and judge-change markers.
create function public.add_species_show_judging_breed(
  p_show_id uuid,p_section_id uuid,p_breed_id text,p_variety_key text,
  p_table_number text,p_sort_order integer,p_scope text,p_entry_count_actual integer,
  p_notes text,p_species text
) returns public.show_judging_assignments
language plpgsql security invoker set search_path = '' as $$
declare v_row public.show_judging_assignments;
begin
  if not coalesce(public.user_can_manage_show_lineup(p_show_id),false) then
    raise exception 'You do not have permission to manage this show lineup' using errcode='42501';
  end if;
  if p_species is not null and p_species not in ('rabbit','cavy') then
    raise exception 'Choose rabbit or cavy for this breed.' using errcode='22023';
  end if;
  if not exists(select 1 from public.show_sections s where s.id=p_section_id and s.show_id=p_show_id) then
    raise exception 'This section does not belong to this show.' using errcode='42501';
  end if;
  if nullif(btrim(p_breed_id),'') is null or left(p_breed_id,2)='__' then
    raise exception 'Choose a breed.' using errcode='22023';
  end if;
  v_row := public.upsert_show_judging_assignment(
    p_show_id=>p_show_id,p_section_id=>p_section_id,p_breed_id=>p_breed_id,
    p_variety_key=>p_variety_key,p_table_number=>p_table_number,p_sort_order=>p_sort_order,
    p_scope=>p_scope,p_entry_count_actual=>p_entry_count_actual,p_notes=>p_notes);
  if p_species is not null then
    update public.show_judging_assignments set species=p_species where id=v_row.id returning * into strict v_row;
  end if;
  return v_row;
end;
$$;
revoke all on function public.add_species_show_judging_breed(uuid,uuid,text,text,text,integer,text,integer,text,text) from public,anon;
grant execute on function public.add_species_show_judging_breed(uuid,uuid,text,text,text,integer,text,integer,text,text) to authenticated,service_role;

-- Preserve the workspace transaction and its version checks. The breed insert
-- inside that transaction must carry the same species as a single-show insert.
do $$
declare
  definition text := pg_get_functiondef('private.mutate_workspace_lineup_core(uuid,jsonb,text,jsonb)'::regprocedure);
  old_call text := $old$perform public.upsert_show_judging_assignment(
         p_show_id=>v_show,p_section_id=>v_section,p_breed_id=>v_params->>'p_breed_id',
         p_variety_key=>v_params->>'p_variety_key',p_judge_id=>null,$old$;
  new_call text := $new$perform public.add_species_show_judging_breed(
         p_show_id=>v_show,p_section_id=>v_section,p_breed_id=>v_params->>'p_breed_id',
         p_variety_key=>v_params->>'p_variety_key',p_species=>v_params->>'p_species',$new$;
begin
  if strpos(definition,old_call)=0 then
    raise exception 'Unexpected workspace breed assignment implementation';
  end if;
  execute replace(definition,old_call,new_call);
end;
$$;

create or replace function private.workspace_lineup_entry_judges(p_show_ids uuid[])
returns table(entry_id uuid, judge_id uuid)
language sql stable set search_path = '' as $$
  with assignments as materialized (
    select * from private.lineup_breed_assignments(p_show_ids)
    where species is not null and judge_id is not null
      and (judge_type is null or judge_type not in ('rabbit','cavy') or judge_type=species)
  )
  select e.id,a.judge_id
  from public.entries e
  left join lateral (
    select a.judge_id from assignments a
    where a.show_id=e.show_id and a.section_id=e.section_id
      and a.species=lower(btrim(e.species::text))
      and a.breed_id=lower(btrim(e.breed::text))
      and (a.variety_key='' or a.variety_key=lower(btrim(coalesce(e.variety::text,''))))
    order by a.explicit_species desc,a.sort_order,a.assignment_id limit 1
  ) a on true
  where e.show_id=any(p_show_ids) and e.result_entered_at is null;
$$;

create or replace function public.apply_lineup_to_entries(p_show_id uuid)
returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not coalesce(public.user_can_manage_show_lineup(p_show_id),false) then
    raise exception 'You do not have permission to manage this show lineup' using errcode='42501';
  end if;
  update public.entries e
  set judged_by_show_judge_id=a.judge_id,updated_at=now()
  from private.workspace_lineup_entry_judges(array[p_show_id]) a
  where e.id=a.entry_id and e.show_id=p_show_id and a.judge_id is not null
    and e.result_entered_at is null and e.judged_by_show_judge_id is null;
end;
$$;
revoke all on function public.apply_lineup_to_entries(uuid) from public,anon;
grant execute on function public.apply_lineup_to_entries(uuid) to authenticated,service_role;
notify pgrst,'reload schema';
