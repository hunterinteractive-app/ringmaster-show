-- Normalize only NEW entries; never silently merge historically judged classes.
create or replace function public.normalize_new_angora_entry()
returns trigger language plpgsql set search_path = '' as $function$
begin
  if lower(btrim(new.breed)) in ('satin angora', 'french angora')
     and btrim(new.variety) ~* '^broken($|[[:space:]])'
     and not public.is_cod_entry(new.breed, new.variety) then
    new.variety := 'Colored';
  elsif lower(btrim(new.breed)) = 'english angora'
     and btrim(new.variety) ~* '^broken($|[[:space:]])'
     and not public.is_cod_entry(new.breed, new.variety) then
    new.variety := btrim(new.variety) || ' (COD)';
  end if;
  return new;
end;
$function$;
revoke all on function public.normalize_new_angora_entry() from public, anon;
create trigger normalize_new_angora_entry
before insert on public.entries
for each row execute function public.normalize_new_angora_entry();

-- Keep the entry picker aligned with the classification used when saving.
update public.varieties v set name = 'Broken (COD)'
from public.breeds b
where v.breed_id=b.id and lower(b.name)='english angora'
  and v.name='Broken'
  and not exists (select 1 from public.varieties x where x.breed_id=b.id and x.name='Broken (COD)');
update public.varieties v set is_active=false
from public.breeds b
where v.breed_id=b.id and lower(b.name) in ('satin angora','french angora')
  and lower(v.name)='broken';
