-- Rollback-only integration test. No payment provider or email is invoked.
-- Uses an existing staff identity only to authorize synthetic show fixtures.
begin;
do $test$
<<fixture>>
declare
  staff uuid; outsider uuid:=extensions.gen_random_uuid();
  show_id uuid:=extensions.gen_random_uuid(); other_show uuid:=extensions.gen_random_uuid();
  section_id uuid:=extensions.gen_random_uuid(); exhibitor_id uuid:=extensions.gen_random_uuid();
  paid_cart uuid:=extensions.gen_random_uuid(); draft_cart uuid:=extensions.gen_random_uuid();
  offering_id uuid:=extensions.gen_random_uuid(); contest_id uuid:=extensions.gen_random_uuid();
  orders_before jsonb; balances_before jsonb; carts_before jsonb; item jsonb;
  rejected boolean;
begin
  select id into staff from auth.users order by created_at limit 1;
  if staff is null then raise exception 'This test needs an existing Auth identity.'; end if;
  perform set_config('request.jwt.claim.sub',staff::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',staff,'role','authenticated')::text,true);
  insert into public.shows(id,created_by,owner_user_id,name,start_date,end_date,is_published,is_test,entry_close_at,payment_timing_mode,online_payment_fee_mode)
    values(show_id,staff,staff,'ROLLBACK ONLY add-on deletion',current_date,current_date+2,true,true,now()+interval '1 day','online_or_at_show','club_absorbs'),
      (other_show,staff,staff,'ROLLBACK ONLY other show',current_date,current_date+2,true,true,now()+interval '1 day','online_or_at_show','club_absorbs');
  insert into public.show_sections(id,show_id,kind,letter,display_name,sort_order) values(section_id,show_id,'open','A','Open A',1);
  insert into public.show_fee_settings(show_id,currency) values(show_id,'USD');
  insert into public.show_section_fee_settings(section_id,fee_per_entry,fee_per_show,fur_fee) values(section_id,10,0,3) on conflict on constraint show_section_fee_settings_pkey do nothing;
  insert into public.exhibitors(id,display_name,owner_user_id,email,is_active,is_test,type,phone,exhibitor_number)
    values(exhibitor_id,'ROLLBACK ONLY Add-On Buyer',staff,'addon-delete@example.invalid',true,true,'adult','0000000000',990077770000 + floor(random()*1000000)::bigint);
  insert into public.entry_carts(id,user_id,show_id) values(paid_cart,staff,show_id);
  perform public.set_show_addons_enabled(show_id,'extra',true);
  item:=jsonb_build_object('id',offering_id,'kind','extra','name','Delete Test Ticket','price_cents',700,'max_per_exhibitor',5);
  perform public.save_show_addon(show_id,item);
  perform public.save_show_addon(show_id,jsonb_build_object('id',contest_id,'kind','contest','name','Keep Contest','price_cents',0));
  perform public.save_cart_addon(paid_cart,offering_id,exhibitor_id,1,'{}');
  -- Submit a pay-at-show order: no charge or external provider call.
  perform public.commit_entry_cart_day_of(paid_cart);
  insert into public.entry_carts(id,user_id,show_id) values(draft_cart,staff,show_id);
  perform public.save_cart_addon(draft_cart,offering_id,exhibitor_id,1,'{}');
  orders_before:=public.get_show_addon_registrations(show_id,null);
  if jsonb_array_length(orders_before)<>1 then raise exception 'Missing submitted order fixture'; end if;
  select jsonb_agg(to_jsonb(b) order by b.id) into balances_before from public.show_exhibitor_balances b where b.show_id=fixture.show_id;
  select jsonb_agg(to_jsonb(c) order by c.id) into carts_before from public.entry_carts c where c.show_id=fixture.show_id;
  if has_function_privilege('anon','public.delete_show_addon(uuid,uuid)','EXECUTE')
    or has_function_privilege('anon','show_addons_private.delete_offering(uuid,uuid)','EXECUTE') then
    raise exception 'Anonymous deletion must not be granted';
  end if;
  if not has_function_privilege('authenticated','public.delete_show_addon(uuid,uuid)','EXECUTE') then raise exception 'Authenticated RPC is missing'; end if;
  perform set_config('request.jwt.claim.sub',outsider::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',outsider,'role','authenticated')::text,true);
  rejected:=false;
  begin perform public.delete_show_addon(show_id,offering_id); exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'Unrelated user could delete an add-on'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
  rejected:=false;
  begin perform public.delete_show_addon(show_id,offering_id); exception when insufficient_privilege then rejected:=true; end;
  if not rejected then raise exception 'Unsigned user could delete an add-on'; end if;
  perform set_config('request.jwt.claim.sub',staff::text,true);
  perform set_config('request.jwt.claims',jsonb_build_object('sub',staff,'role','authenticated')::text,true);
  rejected:=false;
  begin perform public.delete_show_addon(other_show,offering_id);
  exception when raise_exception then if sqlerrm='Add-on not found.' then rejected:=true; else raise; end if; end;
  if not rejected then raise exception 'Wrong show could delete an add-on'; end if;
  update public.shows s set is_locked=true where s.id=fixture.show_id;
  rejected:=false;
  begin perform public.delete_show_addon(show_id,offering_id);
  exception when raise_exception then if sqlerrm='This show is locked or finalized.' then rejected:=true; else raise; end if; end;
  if not rejected then raise exception 'Locked show allowed deletion'; end if;
  update public.shows s set is_locked=false where s.id=fixture.show_id;
  rejected:=false;
  begin perform public.delete_show_addon(show_id,contest_id);
  exception when raise_exception then if sqlerrm='Only show add-ons can be deleted here.' then rejected:=true; else raise; end if; end;
  if not rejected then raise exception 'Add-on endpoint deleted a contest'; end if;

  perform public.delete_show_addon(show_id,offering_id);
  perform public.delete_show_addon(show_id,offering_id); -- Safe retry.
  if not exists(select 1 from show_addons_private.offerings o where o.id=fixture.offering_id and not o.enabled and o.deleted_at is not null and o.deleted_by=staff) then
    raise exception 'Deletion status or actor missing'; end if;
  if exists(select 1 from jsonb_array_elements(public.get_show_addons(show_id,true)->'items') o where o->>'id'=offering_id::text)
    or exists(select 1 from jsonb_array_elements(public.get_show_addons(show_id,false)->'items') o where o->>'id'=offering_id::text) then
    raise exception 'Deleted add-on is still in a catalog'; end if;
  if not exists(select 1 from jsonb_array_elements(public.get_show_addons(show_id,true)->'items') o where o->>'id'=contest_id::text) then
    raise exception 'Unrelated contest disappeared'; end if;
  if public.get_show_addon_registrations(show_id,null) is distinct from orders_before then raise exception 'Existing order history changed'; end if;
  if (select jsonb_agg(to_jsonb(b) order by b.id) from public.show_exhibitor_balances b where b.show_id=fixture.show_id) is distinct from balances_before then raise exception 'Balances changed'; end if;
  if (select jsonb_agg(to_jsonb(c) order by c.id) from public.entry_carts c where c.show_id=fixture.show_id) is distinct from carts_before then raise exception 'Cart/payment state changed'; end if;
  rejected:=false;
  begin perform public.save_show_addon(show_id,item);
  exception when raise_exception then if sqlerrm='This add-on has been deleted. Reload the add-on list.' then rejected:=true; else raise; end if; end;
  if not rejected then raise exception 'Stale editor revived a deleted add-on'; end if;
  rejected:=false;
  begin perform public.save_cart_addon(draft_cart,offering_id,exhibitor_id,2,'{}');
  exception when raise_exception then if sqlerrm='This contest or add-on is not available.' then rejected:=true; else raise; end if; end;
  if not rejected then raise exception 'Deleted add-on accepted another selection'; end if;
  rejected:=false;
  begin perform public.commit_entry_cart_day_of(draft_cart);
  exception when raise_exception then if sqlerrm='This contest or add-on is not available.' then rejected:=true; else raise; end if; end;
  if not rejected then raise exception 'Existing draft could check out a deleted add-on'; end if;
  perform public.remove_cart_addon((select r.id from show_addons_private.selections r where r.cart_id=draft_cart));
  if jsonb_array_length(public.get_cart_addons(draft_cart))<>0 then raise exception 'Unavailable draft item cannot be removed'; end if;
  if exists(select 1 from public.show_exhibitor_balances where entry_cart_id=draft_cart) then raise exception 'Empty draft retained a balance'; end if;
  if public.get_show_addon_registrations(show_id,null) is distinct from orders_before then raise exception 'Removing a draft changed a submitted order'; end if;
end;
$test$;
select 'Add-on deletion integration checks passed; all fixtures rolled back.' as result;
rollback;
