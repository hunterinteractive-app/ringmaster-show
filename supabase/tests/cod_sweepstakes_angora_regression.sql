-- Run inside a transaction after the two migrations; always ROLLBACK afterward.
create temporary table angora_entry_probe (breed text, variety text);
create trigger probe before insert on angora_entry_probe
for each row execute function public.normalize_new_angora_entry();
insert into angora_entry_probe values
 ('Satin Angora','Broken'), ('French Angora','Broken Black'),
 ('English Angora','Broken'), ('English Angora','Broken (COD)'),
 ('Satin Angora','White'), ('Giant Angora','Chocolate Agouti (COD)'),
 ('Mini Satin','Broken'), ('Satin Angora','Unrecognized (COD)');
do $test$
begin
 if (select count(*) from angora_entry_probe where variety='Colored') <> 2
 or (select count(*) from angora_entry_probe where variety='Broken (COD)') <> 2
 or not exists (select 1 from angora_entry_probe where breed='Mini Satin' and variety='Broken')
 or not exists (select 1 from angora_entry_probe where breed='Satin Angora' and variety='White')
 or not exists (select 1 from angora_entry_probe where breed='Giant Angora' and variety='Chocolate Agouti (COD)') then
   raise exception 'Angora entry normalization regression';
 end if;
end;
$test$;
-- Old rows must not be rewritten by ordinary updates.
update angora_entry_probe set variety='Broken' where breed='Satin Angora' and variety='Colored';
do $test$
begin
 if not exists (select 1 from angora_entry_probe where breed='Satin Angora' and variety='Broken') then
   raise exception 'Historical entry was rewritten';
 end if;
end;
$test$;

-- Calumet contains two COD English Angoras per Open section alongside five
-- recognized entries. Recompute ONLY within this rollback transaction.
select count(*) from public.calculate_sweepstakes_for_breed(
 'f2756369-4d16-4261-a0b7-12b6d1214360','English Angora','OPEN','A');
do $test$
begin
 if exists (
   select 1 from public.sweepstakes_entry_results r join public.entries e on e.id=r.entry_id
   where r.show_id='f2756369-4d16-4261-a0b7-12b6d1214360' and r.breed_name='English Angora'
     and r.scope='OPEN' and r.show_letter='A' and public.is_cod_entry(e.breed,e.variety)
 ) then raise exception 'COD entries received sweepstakes points'; end if;
 if not exists (
   select 1 from public.sweepstakes_entry_results r
   where r.show_id='f2756369-4d16-4261-a0b7-12b6d1214360' and r.breed_name='English Angora'
     and r.scope='OPEN' and r.show_letter='A' and r.points>0
 ) then raise exception 'Recognized entry points disappeared'; end if;
end;
$test$;
