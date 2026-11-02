-- Confirmed breed sanctions must produce club reports even with no animals shown.
-- Pending requests without a sanction number are not no-show report targets.
create or replace function public.closeout_sanction_report_species(p_sanction_id uuid)
returns table(species text)
language sql stable security invoker set search_path = ''
as $sql$
  with sanction as (
    select * from public.show_sanctions where id = p_sanction_id
  ), shown_species as (
    select distinct lower(e.species::text) species
    from sanction ss join public.entries e
      on e.show_id = ss.show_id and e.section_id = ss.section_id
    where e.is_shown = true and e.scratched_at is null
      and (
        upper(btrim(ss.sanctioning_body)) = 'STATE CLUB'
        or (lower(btrim(ss.breed_name)) = 'cavy' and lower(e.species::text) = 'cavy')
        or lower(btrim(e.breed)) = lower(btrim(ss.breed_name))
      )
  )
  select species from shown_species
  union
  select inferred.species
  from sanction ss
  cross join lateral (
    select case when lower(btrim(ss.breed_name)) = 'cavy' then 'cavy'
      else (
        -- ACBA uses the aggregate Cavy sanction. For ambiguous catalog names
        -- such as American, a named rabbit breed sanction means the rabbit.
        select lower(b.species::text) from public.breeds b
        where lower(btrim(b.name)) = lower(btrim(ss.breed_name))
          and (b.local_show_id is null or b.local_show_id = ss.show_id)
        order by (lower(b.species::text) = 'rabbit') desc, b.id
        limit 1
      ) end species
  ) inferred
  where not exists (select 1 from shown_species)
    and upper(btrim(ss.sanctioning_body)) in ('NATIONAL CLUB','STATE BREED CLUB')
    and (nullif(btrim(ss.sanction_number), '') is not null or ss.request_status = 'received')
    and inferred.species in ('rabbit', 'cavy');
$sql$;
revoke all on function public.closeout_sanction_report_species(uuid) from public, anon;
grant execute on function public.closeout_sanction_report_species(uuid) to authenticated, service_role;

-- Patch only the manifest selection, preserving the installed authorization,
-- finalization checks, artifact identity, and queue implementation.
do $migration$
declare definition text;
begin
  select pg_get_functiondef('public.rebuild_closeout_club_report_manifest(uuid,uuid,text,text)'::regprocedure) into definition;
  if position($old$      join lateral (
        select distinct lower(entry.species::text) species
        from public.entries entry
        where entry.show_id = p_show_id
          and entry.section_id = sec.id
          and entry.is_shown = true
          and entry.scratched_at is null
          and (
            upper(btrim(ss.sanctioning_body)) = 'STATE CLUB'
            or (
              lower(btrim(coalesce(ss.breed_name, ''))) = 'cavy'
              and lower(entry.species::text) = 'cavy'
            )
            or lower(btrim(coalesce(entry.breed, ''))) =
              lower(btrim(coalesce(ss.breed_name, '')))
          )
      ) e_species on true$old$ in definition) = 0 then
    raise exception 'Unexpected rebuild_closeout_club_report_manifest definition; review migration before applying';
  end if;
  definition := replace(definition, $old$      join lateral (
        select distinct lower(entry.species::text) species
        from public.entries entry
        where entry.show_id = p_show_id
          and entry.section_id = sec.id
          and entry.is_shown = true
          and entry.scratched_at is null
          and (
            upper(btrim(ss.sanctioning_body)) = 'STATE CLUB'
            or (
              lower(btrim(coalesce(ss.breed_name, ''))) = 'cavy'
              and lower(entry.species::text) = 'cavy'
            )
            or lower(btrim(coalesce(entry.breed, ''))) =
              lower(btrim(coalesce(ss.breed_name, '')))
          )
      ) e_species on true$old$, $new$      cross join lateral public.closeout_sanction_report_species(ss.id) e_species$new$);
  execute definition;

  select pg_get_functiondef('public.finalize_show_scoped(uuid,uuid[],text,text)'::regprocedure) into definition;
  if position($old$    join lateral (
      select distinct lower(e.species::text) species
      from public.entries e
      where e.show_id = p_show_id and e.section_id = sec.id
        and e.is_shown = true and e.scratched_at is null
        and (
          upper(btrim(ss.sanctioning_body)) = 'STATE CLUB'
          or (
            lower(btrim(coalesce(ss.breed_name, ''))) = 'cavy'
            and lower(e.species::text) = 'cavy'
          )
          or lower(btrim(coalesce(e.breed, ''))) = lower(btrim(coalesce(ss.breed_name, '')))
        )
    ) e_species on true$old$ in definition) = 0 then
    raise exception 'Unexpected finalize_show_scoped definition; review migration before applying';
  end if;
  definition := replace(definition, $old$    join lateral (
      select distinct lower(e.species::text) species
      from public.entries e
      where e.show_id = p_show_id and e.section_id = sec.id
        and e.is_shown = true and e.scratched_at is null
        and (
          upper(btrim(ss.sanctioning_body)) = 'STATE CLUB'
          or (
            lower(btrim(coalesce(ss.breed_name, ''))) = 'cavy'
            and lower(e.species::text) = 'cavy'
          )
          or lower(btrim(coalesce(e.breed, ''))) = lower(btrim(coalesce(ss.breed_name, '')))
        )
    ) e_species on true$old$, $new$    cross join lateral public.closeout_sanction_report_species(ss.id) e_species$new$);
  if position($old$      and exists (
        select 1 from public.entries e
        where e.show_id = p_show_id and e.section_id = sec.id
          and e.is_shown = true and e.scratched_at is null
          and (
            upper(btrim(ss.sanctioning_body)) = 'STATE CLUB'
            or (
            lower(btrim(coalesce(ss.breed_name, ''))) = 'cavy'
            and lower(e.species::text) = 'cavy'
          )
          or lower(btrim(coalesce(e.breed, ''))) = lower(btrim(coalesce(ss.breed_name, '')))
          )
      );$old$ in definition) = 0 then
    raise exception 'Unexpected finalize_show_scoped definition; review migration before applying';
  end if;
  definition := replace(definition, $old$      and exists (
        select 1 from public.entries e
        where e.show_id = p_show_id and e.section_id = sec.id
          and e.is_shown = true and e.scratched_at is null
          and (
            upper(btrim(ss.sanctioning_body)) = 'STATE CLUB'
            or (
            lower(btrim(coalesce(ss.breed_name, ''))) = 'cavy'
            and lower(e.species::text) = 'cavy'
          )
          or lower(btrim(coalesce(e.breed, ''))) = lower(btrim(coalesce(ss.breed_name, '')))
          )
      );$old$, $new$;$new$);
  if position($old$-- filenames. Each target must have qualifying shown data in that section.$old$ in definition) = 0 then
    raise exception 'Unexpected finalize_show_scoped definition; review migration before applying';
  end if;
  definition := replace(definition, $old$-- filenames. Each target must have qualifying shown data in that section.$old$, $new$-- filenames. Confirmed breed sanctions also receive none-shown reports.$new$);
  if position($old$    v_reused := true;$old$ in definition) = 0 then
    raise exception 'Unexpected finalize_show_scoped definition; review migration before applying';
  end if;
  definition := replace(definition, $old$    v_reused := true;$old$, $new$    v_reused := true;
    perform public.rebuild_closeout_club_report_manifest(
      p_show_id, v_finalize_run_id, v_scope_key, null
    );$new$);
  execute definition;
end;
$migration$;
