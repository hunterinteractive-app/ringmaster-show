create extension if not exists pgtap with schema extensions;
begin;
set local search_path = public, extensions;
select plan(7);
-- Reuse the small deterministic SQL fixture, never the retained event entries.
create temporary table count_target as
select id,show_id,section_id,species from public.entries
where show_id='20000000-0000-0000-0000-000000000004' order by id limit 1;
update public.entries set is_shown=true,scratched_at=null,status='submitted'
where id=(select id from count_target);
create temporary table before_count as select public.count_shown_species(show_id,section_id,species::text) n from count_target;
update public.entries set scratched_at=now() where id=(select id from count_target);
select is((select public.count_shown_species(show_id,section_id,species::text) from count_target),
  (select n-1 from before_count),'a scratch is excluded even while is_shown remains true');
update public.entries set tattoo=tattoo||'-EDIT',is_shown=true where id=(select id from count_target);
select is((select public.count_shown_species(show_id,section_id,species::text) from count_target),
  (select n-1 from before_count),'an unrelated edit cannot restore a scratched animal to the count');
update public.entries set scratched_at=null,status=' SCRATCHED ' where id=(select id from count_target);
select is((select public.count_shown_species(show_id,section_id,species::text) from count_target),
  (select n-1 from before_count),'legacy scratch status is normalized and excluded');
update public.entries set status='cancelled' where id=(select id from count_target);
select is((select public.count_shown_species(show_id,section_id,species::text) from count_target),
  (select n-1 from before_count),'cancelled entries are excluded');
update public.entries set status='submitted',is_shown=false where id=(select id from count_target);
select is((select public.count_shown_species(show_id,section_id,species::text) from count_target),
  (select n-1 from before_count),'an unshown active entry is excluded');
update public.entries set is_shown=true where id=(select id from count_target);
select is((select public.count_shown_species(show_id,section_id,species::text) from count_target),
  (select n from before_count),'restoring an active shown entry restores exactly one count');
select ok(not has_function_privilege('anon','public.count_shown_species(uuid,uuid,text)','execute'),'shown counts are not an anonymous endpoint');
select * from finish();
rollback;
