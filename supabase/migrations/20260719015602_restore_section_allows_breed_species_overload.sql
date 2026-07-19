create or replace function public.section_allows_breed(
  p_section_id uuid,
  p_breed text,
  p_species public.species
)
returns boolean
language sql
stable
set search_path = ''
as $function$
  select public.section_allows_breed(
    p_section_id,
    p_breed,
    p_species::text
  );
$function$;

comment on function public.section_allows_breed(uuid, text, public.species)
is 'Enum-compatible overload used by entry and cart breed-scope enforcement triggers; delegates to the text implementation.';
