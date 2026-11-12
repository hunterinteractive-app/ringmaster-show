\set ON_ERROR_STOP on
begin;
\ir ../../supabase/migrations/20261112030048_validate_four_class_entry_intermediate.sql
-- Exercise the production trigger function without unrelated entry side effects.
create temporary table class_guard_entries (show_id uuid, species text, breed text, class_name text);
create trigger class_guard before insert or update on class_guard_entries
for each row execute function public.validate_entry_intermediate_class();
insert into public.breeds(id,name,species,class_system) values
 ('00000000-0000-0000-0000-000000000091','Class Guard Four','rabbit','four'),
 ('00000000-0000-0000-0000-000000000092','Class Guard Six','rabbit','six');
do $$
declare v_show uuid; rejected boolean := false;
begin
 select id into strict v_show from public.shows limit 1;
 begin
  insert into class_guard_entries values(v_show,'rabbit','Class Guard Four','Intermediate');
 exception when check_violation then rejected := true;
 end;
 assert rejected, 'Four-class Intermediate must fail';
 insert into class_guard_entries values(v_show,'rabbit','Class Guard Four','Junior');
 insert into class_guard_entries values(v_show,'rabbit','Class Guard Four','Senior');
 insert into class_guard_entries values(v_show,'rabbit','Class Guard Six','Intermediate');
 insert into class_guard_entries values(v_show,'cavy','Class Guard Four','Intermediate');
 insert into class_guard_entries values(v_show,'rabbit','Class Guard Four','Meat Pen');
 rejected := false;
 begin
  insert into class_guard_entries values(v_show,'rabbit','Class Guard Four (COD)','Intermediate');
 exception when check_violation then rejected := true;
 end;
 assert rejected, 'COD display suffix must not bypass validation';
 rejected := false;
 begin
  update class_guard_entries set class_name='Intermediate' where class_name='Senior';
 exception when check_violation then rejected := true;
 end;
 assert rejected, 'Update must be guarded';
 insert into public.show_breeds(show_id,breed_id,class_system_override) values(v_show,'00000000-0000-0000-0000-000000000091','six');
 insert into class_guard_entries values(v_show,'rabbit','Class Guard Four','Intermediate');
 update public.show_breeds set class_system_override='four' where show_id=v_show and breed_id='00000000-0000-0000-0000-000000000091';
 rejected := false;
 begin
  insert into class_guard_entries values(v_show,'rabbit','Class Guard Four','Intermediate');
 exception when check_violation then rejected := true;
 end;
 assert rejected, 'Show override must be respected';
 -- A show-local record takes priority over the global breed.
 insert into public.breeds(name,species,class_system,local_show_id) values('Class Guard Four','rabbit','six',v_show);
 insert into class_guard_entries values(v_show,'rabbit','Class Guard Four','Intermediate');
 raise notice '10 class guard cases passed';
end $$;
rollback;
