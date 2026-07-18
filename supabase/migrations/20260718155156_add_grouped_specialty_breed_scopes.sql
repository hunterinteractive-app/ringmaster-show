create or replace function public.section_allows_breed(
  p_section_id uuid,
  p_breed text,
  p_species text default null
)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when ss.id is null then false
    when lower(btrim(coalesce(ss.breed_scope, 'all'))) in ('all', 'all_breed', 'meat_only') then true
    when nullif(btrim(coalesce(p_breed, '')), '') is null then false
    when lower(btrim(coalesce(ss.breed_scope, 'all'))) in ('single', 'limited')
         or lower(btrim(coalesce(ss.breed_scope, 'all'))) like 'grouped\_%' escape '\' then exists (
      select 1
      from public.breeds b
      where b.id = any(coalesce(ss.allowed_breed_ids, array[]::uuid[]))
        and lower(btrim(b.name)) = lower(btrim(p_breed))
        and (
          nullif(btrim(coalesce(p_species, '')), '') is null
          or lower(btrim(b.species::text)) = lower(btrim(p_species))
        )
    )
    else false
  end
  from public.show_sections ss
  where ss.id = p_section_id;
$$;

revoke all on function public.section_allows_breed(uuid, text, text) from public;
grant execute on function public.section_allows_breed(uuid, text, text)
  to authenticated, service_role;

comment on function public.section_allows_breed(uuid, text, text) is
  'Canonical validation for single, selected, and grouped specialty section breed scope.';
