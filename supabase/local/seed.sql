-- Deterministic synthetic Closeout fixtures. No production identities or data.
insert into public.breeds(id,name,species,sort_order,has_varieties) values
 ('10000000-0000-0000-0000-000000000001','Mini Rex','rabbit',10,true),
 ('10000000-0000-0000-0000-000000000002','Jersey Wooly','rabbit',20,false),
 ('10000000-0000-0000-0000-000000000003','American','cavy',30,true),
 ('10000000-0000-0000-0000-000000000004','Teddy','cavy',40,true)
on conflict(id) do nothing;

insert into public.variety_groups(id,breed_id,name,sort_order) values
 ('11000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Self',10),
 ('11000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Agouti',20),
 ('11000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000003','American Color Groups',10)
on conflict(id) do nothing;
insert into public.varieties(id,breed_id,variety_group_id,name,sort_order) values
 ('12000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000001','Black',10),
 ('12000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','11000000-0000-0000-0000-000000000002','Castor',20),
 ('12000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000003','11000000-0000-0000-0000-000000000003','Black',10),
 ('12000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000003','11000000-0000-0000-0000-000000000003','Cream',20),
 ('12000000-0000-0000-0000-000000000005','10000000-0000-0000-0000-000000000004',null,'Teddy',10)
on conflict(id) do nothing;
update public.varieties set group_id = variety_group_id;
insert into public.shows(id,name,start_date,end_date,location_name,location_address,
 secretary_name,secretary_email,results_version,payment_timing_mode) values
 ('20000000-0000-0000-0000-000000000001','Local Mini Rex Grouped Variety Show','2026-08-01','2026-08-01','Local Hall','1 Test Way','Local Secretary','secretary@example.test',1,'pay_at_show_only'),
 ('20000000-0000-0000-0000-000000000002','Local Jersey Wooly Group Show','2026-08-02','2026-08-02','Local Hall','1 Test Way','Local Secretary','secretary@example.test',1,'pay_at_show_only'),
 ('20000000-0000-0000-0000-000000000003','Local Cavy Group Show','2026-08-03','2026-08-03','Local Hall','1 Test Way','Local Secretary','secretary@example.test',1,'pay_at_show_only'),
 ('20000000-0000-0000-0000-000000000004','Local Mixed Closeout E2E Show','2026-08-04','2026-08-05','Local Hall','1 Test Way','Local Secretary','secretary@example.test',1,'online_or_at_show')
on conflict(id) do nothing;
update public.shows set
  secretary_phone = '555-0100',
  secretary_address = '1 Test Way, Localtown, IN 46000',
  club_name = 'Synthetic Host Club',
  coop_numbering_mode = 'separate';

insert into public.show_sections(id,show_id,kind,letter,display_name,breed_scope,allowed_breed_ids,is_enabled,sort_order) values
 ('21000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','open','A','Mini Rex Open A','specialty',array['10000000-0000-0000-0000-000000000001']::uuid[],true,10),
 ('21000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000002','open','A','Jersey Wooly Open A','specialty',array['10000000-0000-0000-0000-000000000002']::uuid[],true,10),
 ('21000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000003','open','A','Cavy Open A','all_breed',array['10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004']::uuid[],true,10),
 ('21000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000004','open','A','Rabbit Open A','all_breed',array['10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002']::uuid[],true,10),
 ('21000000-0000-0000-0000-000000000005','20000000-0000-0000-0000-000000000004','youth','A','Rabbit Youth A','all_breed',array['10000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000002']::uuid[],true,20),
 ('21000000-0000-0000-0000-000000000006','20000000-0000-0000-0000-000000000004','open','B','Cavy Open B','all_breed',array['10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004']::uuid[],true,30),
 ('21000000-0000-0000-0000-000000000007','20000000-0000-0000-0000-000000000004','youth','B','Cavy Youth B','all_breed',array['10000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000004']::uuid[],true,40)
on conflict(id) do nothing;

insert into public.exhibitors(id,display_name,first_name,last_name,email,phone,type,arba_number) values
 ('30000000-0000-0000-0000-000000000001','Synthetic Rabbit Exhibitor','Synthetic','Rabbit','rabbit@example.test','555-0101','adult','R-LOCAL'),
 ('30000000-0000-0000-0000-000000000002','Synthetic Cavy Exhibitor','Synthetic','Cavy','cavy@example.test','555-0102','adult','C-LOCAL'),
 ('30000000-0000-0000-0000-000000000003','Empty Synthetic Exhibitor','Empty','Target','empty@example.test','555-0103','adult',null)
on conflict(id) do nothing;
update public.exhibitors set
  exhibitor_number = case id
    when '30000000-0000-0000-0000-000000000001' then 'E-101'
    when '30000000-0000-0000-0000-000000000002' then 'E-102'
    else 'E-103' end,
  address_line1 = '1 Test Way', city = 'Localtown', state = 'IN', zip = '46000';
insert into public.judges(id,display_name,first_name,last_name,arba_number) values
 ('31000000-0000-0000-0000-000000000001','Local Judge','Local','Judge','J-LOCAL')
on conflict(id) do nothing;
update public.judges set name = display_name, arba_judge_number = arba_number;
insert into public.show_judges(show_id,judge_id,section_id,sort_order,is_enabled)
select '20000000-0000-0000-0000-000000000004', '31000000-0000-0000-0000-000000000001', id, sort_order, true
from public.show_sections where show_id='20000000-0000-0000-0000-000000000004'
on conflict do nothing;

insert into public.entries(id,show_id,section_id,exhibitor_id,species,tattoo,animal_name,breed,variety,group_name,sex,class_name,status,is_shown,is_fur) values
 ('40000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','30000000-0000-0000-0000-000000000001','rabbit','R1','Local Black','Mini Rex','Black','Self','Buck','Senior Buck','entered',true,false),
 ('40000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','30000000-0000-0000-0000-000000000001','rabbit','R2','Local Castor','Mini Rex','Castor','Agouti','Doe','Senior Doe','entered',true,false),
 ('40000000-0000-0000-0000-000000000003','20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000005','30000000-0000-0000-0000-000000000001','rabbit','RY1','Local Youth Wooly','Jersey Wooly','Black',null,'Doe','Junior Doe','entered',true,false),
 ('40000000-0000-0000-0000-000000000004','20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000006','30000000-0000-0000-0000-000000000002','cavy','C1','Local American Black','American','Black','Black','Boar','Senior Boar','entered',true,false),
 ('40000000-0000-0000-0000-000000000005','20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000006','30000000-0000-0000-0000-000000000002','cavy','C2','Local Teddy','Teddy','Teddy','Teddy','Sow','Senior Sow','entered',true,false),
 ('40000000-0000-0000-0000-000000000006','20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000007','30000000-0000-0000-0000-000000000002','cavy','CY1','Local Youth American','American','Cream','Cream','Sow','Junior Sow','entered',true,false)
on conflict(id) do nothing;
update public.entries set
  judged_by_show_judge_id = '31000000-0000-0000-0000-000000000001',
  placement = 1,
  result_status = 'placed'
where show_id = '20000000-0000-0000-0000-000000000004';
insert into public.entry_awards(entry_id,award_code,award,points) values
 ('40000000-0000-0000-0000-000000000001','BOB','Best of Breed',10),
 ('40000000-0000-0000-0000-000000000002','BOSB','Best Opposite Sex of Breed',6),
 ('40000000-0000-0000-0000-000000000004','BOG','Best of Group',10),
 ('40000000-0000-0000-0000-000000000005','BOB','Best of Breed',8);
update public.entry_awards ea set show_id = e.show_id
from public.entries e where e.id = ea.entry_id;

insert into public.show_sanctions(show_id,section_id,breed_name,club_name,sanction_number,sanctioning_body,sweepstakes_email) values
 ('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004',null,'Synthetic Host Club','ARBA-LOCAL-A','ARBA',null),
 ('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000004','Mini Rex','Synthetic Mini Rex Club','MR-LOCAL','NATIONAL CLUB','club@example.test'),
 ('20000000-0000-0000-0000-000000000004','21000000-0000-0000-0000-000000000006','American','Synthetic Cavy Club',null,'NATIONAL CLUB','cavyclub@example.test');
insert into public.show_arba_report_details(show_id,club_name,club_number,secretary_name,secretary_email,location)
values('20000000-0000-0000-0000-000000000004','Synthetic Host Club','LOCAL-1','Local Secretary','secretary@example.test','Local Hall')
on conflict(show_id) do nothing;
update public.show_arba_report_details set
  secretary_phone = '555-0100',
  secretary_address = '1 Test Way, Localtown, IN 46000',
  superintendent_name = 'Local Superintendent',
  superintendent_arba_number = 'S-LOCAL'
where show_id = '20000000-0000-0000-0000-000000000004';

insert into public.show_fee_settings(show_id,currency,multi_show_discount_enabled,multi_show_discount_type,multi_show_discount_value,multi_show_discount_basis,multi_show_discount_scope,multi_show_discount_min_entries,multi_show_discount_required_shows)
values('20000000-0000-0000-0000-000000000004','usd',true,'amount',1,'each_show','both',2,2)
on conflict(show_id) do nothing;
insert into public.show_section_fee_settings(section_id,fee_per_entry,fee_per_show,fur_fee)
select id, 5, 2, 1 from public.show_sections where show_id='20000000-0000-0000-0000-000000000004'
on conflict(section_id) do nothing;

insert into public.show_exhibitor_balances(
 id,show_id,exhibitor_id,currency,entry_count,fur_count,entries_subtotal_cents,
 fur_subtotal_cents,show_fee_subtotal_cents,subtotal_before_discount_cents,
 discount_cents,calculated_total_cents,paid_online_cents,paid_manual_cents,
 refunded_cents,balance_due_cents,payment_status,source,section_breakdown
) values
 ('50000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000004','30000000-0000-0000-0000-000000000001','usd',3,0,1500,0,400,1900,0,1900,0,0,0,1900,'unpaid','local_fixture',jsonb_build_array(
   jsonb_build_object('section_id','21000000-0000-0000-0000-000000000004','kind','open','letter','A','label','Rabbit Open A','entry_count',2,'fur_count',0,'entries_subtotal_cents',1000,'fur_subtotal_cents',0,'show_fee_cents',200),
   jsonb_build_object('section_id','21000000-0000-0000-0000-000000000005','kind','youth','letter','A','label','Rabbit Youth A','entry_count',1,'fur_count',0,'entries_subtotal_cents',500,'fur_subtotal_cents',0,'show_fee_cents',200))),
 ('50000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000004','30000000-0000-0000-0000-000000000002','usd',3,0,1500,0,400,1900,200,1700,1700,0,0,0,'paid','local_fixture',jsonb_build_array(
   jsonb_build_object('section_id','21000000-0000-0000-0000-000000000006','kind','open','letter','B','label','Cavy Open B','entry_count',2,'fur_count',0,'entries_subtotal_cents',1000,'fur_subtotal_cents',0,'show_fee_cents',200),
   jsonb_build_object('section_id','21000000-0000-0000-0000-000000000007','kind','youth','letter','B','label','Cavy Youth B','entry_count',1,'fur_count',0,'entries_subtotal_cents',500,'fur_subtotal_cents',0,'show_fee_cents',200)))
on conflict(id) do nothing;

insert into public.show_closeout_state(show_id,sync_status,is_points_stale,has_blocking_errors,validation_checked_at)
select id,'ready',false,false,now() from public.shows on conflict(show_id) do nothing;
