-- Synthetic loader rehearsal only. Applied by prepare.py to a fresh LOCAL project.
-- 30,000 animals, 3,000 exhibitors, two sections, 60,000 entries.
-- Deliberately skewed: 24,000 Mini Rex and 6,000 Jersey Wooly per section.
begin;
set local statement_timeout = '120s';

insert into public.shows(id,name,start_date,end_date,coop_numbering_mode,
  secretary_name,secretary_email,is_national_show)
values ('90000000-0000-0000-0000-000000000001',
  'SYNTHETIC National Loader Rehearsal','2026-09-10','2026-09-11',
  'combined','Synthetic Secretary','secretary@example.test',true);

insert into public.show_sections(id,show_id,kind,letter,display_name,sort_order)
select ('91000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  '90000000-0000-0000-0000-000000000001','open',chr(64+n),
  'Synthetic Open ' || chr(64+n),n
from generate_series(1,2) n;

insert into public.show_sanctions(show_id,section_id,club_name,
  sanction_number,sanctioning_body)
select show_id,id,'Synthetic Host Club','SYNTHETIC-' || letter,'ARBA'
from public.show_sections
where show_id='90000000-0000-0000-0000-000000000001';

insert into public.exhibitors(id,display_name,first_name,last_name,
  exhibitor_number,email,city,state,arba_number)
select ('92000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'Synthetic Exhibitor ' || lpad(n::text,4,'0'),'Synthetic',
  'Exhibitor ' || lpad(n::text,4,'0'),n::text,
  'exhibitor-' || n || '@example.test','Localtown','IN','SYN-' || n
from generate_series(1,3000) n;

insert into public.animals(id,species,tattoo,name,breed,variety,sex,class_name)
select ('93000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid,
  'rabbit','N' || lpad(n::text,5,'0'),'Synthetic Animal ' || n,
  case when n <= 24000 then 'Mini Rex' else 'Jersey Wooly' end,
  'Black','Buck','Senior Buck'
from generate_series(1,30000) n;

insert into public.entries(id,show_id,section_id,exhibitor_id,animal_id,
  species,tattoo,animal_name,breed,variety,sex,class_name,placement,
  result_status,judged_by_show_judge_id)
select ('94000000-0000-0000-0000-' || lpad(((s-1)*30000+n)::text,12,'0'))::uuid,
  '90000000-0000-0000-0000-000000000001',
  ('91000000-0000-0000-0000-' || lpad(s::text,12,'0'))::uuid,
  ('92000000-0000-0000-0000-' || lpad((((n-1)%3000)+1)::text,12,'0'))::uuid,
  a.id,a.species,a.tattoo,a.name,a.breed,a.variety,a.sex,a.class_name,
  case when n <= 24000 then n else n-24000 end,'placed',
  '31000000-0000-0000-0000-000000000001'
from generate_series(1,30000) n cross join generate_series(1,2) s
join public.animals a on a.id =
  ('93000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid;

insert into public.show_animal_coop_numbers(show_id,animal_id,section_id,
  coop_number,scope,breed_name)
select '90000000-0000-0000-0000-000000000001',a.id,
  '91000000-0000-0000-0000-000000000001',
  substring(a.tattoo from 2),'all',a.breed
from public.animals a where a.id::text like '93000000-%';

-- Two breed winners per section, both owned by exhibitor 1.
insert into public.entry_awards(show_id,entry_id,award_code,award)
select show_id,id,'BOB','Best of Breed'
from public.entries where show_id='90000000-0000-0000-0000-000000000001'
  and placement=1;

do $$ begin
  if (select count(*) from public.entries
      where show_id='90000000-0000-0000-0000-000000000001') <> 60000
  then raise exception 'Synthetic entry count is incorrect'; end if;
end $$;
commit;
analyze public.entries;
analyze public.exhibitors;
analyze public.animals;
analyze public.entry_awards;
analyze public.show_animal_coop_numbers;
