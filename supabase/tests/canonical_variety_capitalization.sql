begin;
select plan(1);
do $$
declare
 b uuid := gen_random_uuid(); u uuid := gen_random_uuid(); s uuid := gen_random_uuid();
 ex uuid := gen_random_uuid(); sec uuid := gen_random_uuid(); c uuid := gen_random_uuid(); a uuid; e uuid; ci uuid; actual text;
begin
 insert into auth.users(id,email) values(u,'variety-test@example.invalid');
 insert into public.shows(id,created_by,name,start_date,end_date,is_test)
 values(s,u,'Variety capitalization test',current_date,current_date,true);
 insert into public.show_sections(id,show_id,kind,letter,display_name) values(sec,s,'open','A','Open A');
 insert into public.breeds(id,name,species) values(b,'Capitalization Test Rex','rabbit');
 insert into public.show_breeds(show_id,breed_id,is_enabled) values(s,b,true);
 insert into public.exhibitors(id,owner_user_id,display_name,type,email,phone,is_test) values(ex,u,'Label test','adult','variety-test@example.invalid','555-0100',true);
 insert into public.varieties(breed_id,name) values(b,'Otter'),(b,'REW'),(b,'Black Otter');
 insert into public.show_varieties(show_id,breed_id,variety_id,custom_name,is_enabled)
 values(s,b,null,'Custom ABC',true);
 if variety_labels_private.canonical_breed('rabbit',' capitalization test rex ') <> 'Capitalization Test Rex'
 or variety_labels_private.canonical_breed('cavy','capitalization test rex') <> 'capitalization test rex'
 or variety_labels_private.canonical_breed('rabbit','Unknown Breed') <> 'Unknown Breed'
 or variety_labels_private.canonical_variety('rabbit','Capitalization Test Rex','rew') <> 'REW'
 or variety_labels_private.canonical_variety('rabbit','Capitalization Test Rex',' BLACK  otter ') <> 'Black Otter'
 or variety_labels_private.canonical_variety('rabbit','Capitalization Test Rex','custom abc',s) <> 'Custom ABC'
 or variety_labels_private.canonical_variety('rabbit','Capitalization Test Rex','Unknown XYZ') <> 'Unknown XYZ'
 or variety_labels_private.canonical_variety('cavy','Capitalization Test Rex','otter') <> 'otter'
 then raise exception 'catalog matching failed'; end if;
 perform set_config('request.jwt.claims',json_build_object('sub',u,'role','authenticated')::text,true);
 set local role authenticated;
 if variety_labels_private.canonical_variety('rabbit','Capitalization Test Rex','otter') <> 'Otter'
 or variety_labels_private.canonical_breed('rabbit','capitalization test rex') <> 'Capitalization Test Rex'
 then raise exception 'authenticated catalog access failed'; end if;
 reset role;
 insert into public.animals(species,breed,variety) values('rabbit','capitalization test rex','otter') returning id,variety into a,actual;
 if actual <> 'Otter' or (select breed from public.animals where id=a)<>'Capitalization Test Rex' then raise exception 'animal insert failed'; end if;
 update public.animals set breed='CAPITALIZATION TEST REX',variety='rew' where id=a returning variety into actual;
 if actual <> 'REW' or (select breed from public.animals where id=a)<>'Capitalization Test Rex' then raise exception 'animal update failed'; end if;
 insert into public.entry_carts(id,show_id,user_id) values(c,s,u);
 insert into public.entry_cart_items(cart_id,section_id,species,breed,variety)
 values(c,sec,'rabbit','capitalization test rex','otter') returning id,variety into ci,actual;
 if actual <> 'Otter' or (select breed from public.entry_cart_items where id=ci)<>'Capitalization Test Rex' then raise exception 'cart insert failed'; end if;
 insert into public.entries(show_id,section_id,species,breed,variety,is_test,exhibitor_id,exhibitor_user_id)
 values(s,sec,'rabbit','capitalization test rex','otter',true,ex,u) returning id,variety into e,actual;
 if actual <> 'Otter' or (select breed from public.entries where id=e)<>'Capitalization Test Rex' then raise exception 'entry insert failed'; end if;
 update public.entries set breed='CAPITALIZATION TEST REX',variety='rew' where id=e returning variety into actual;
 if actual <> 'REW' or (select breed from public.entries where id=e)<>'Capitalization Test Rex' then raise exception 'entry update failed'; end if;
end $$;
select pass('catalog spelling preserved across animal, cart and entry saves');
select * from finish();
rollback;
