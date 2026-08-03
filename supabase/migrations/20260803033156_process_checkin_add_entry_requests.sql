create or replace function public.apply_checkin_add_entry(
  p_show_id uuid, p_exhibitor_id uuid, p_changes jsonb, p_request_id uuid default null
) returns uuid language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype; u uuid; i uuid; section uuid := nullif(p_changes->>'section_id','')::uuid;
begin
  if section is null or not exists(select 1 from public.show_sections s where s.id=section and s.show_id=p_show_id) then raise exception 'A valid show section is required'; end if;
  select * into c from public.entry_carts where show_id=p_show_id and status='active' and payment_status not in ('paid','pending') and user_id in (
    select coalesce(e.exhibitor_user_id, x.owner_user_id, x.claimed_by_user_id) from public.exhibitors x left join public.entries e on e.exhibitor_id=x.id and e.show_id=p_show_id where x.id=p_exhibitor_id order by e.updated_at desc nulls last limit 1
  ) order by updated_at desc limit 1 for update;
  if not found then
    select coalesce(owner_user_id, claimed_by_user_id, (select exhibitor_user_id from public.entries where show_id=p_show_id and exhibitor_id=p_exhibitor_id order by updated_at desc limit 1)) into u from public.exhibitors where id=p_exhibitor_id;
    if u is null then raise exception 'This exhibitor does not have an account-backed cart. Please see the show secretary.'; end if;
    insert into public.entry_carts(user_id,show_id,status,payment_status,subtotal_cents,total_cents,currency) values(u,p_show_id,'active','unpaid',0,0,'usd') returning * into c;
  end if;
  insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,animal_name,breed,variety,class_name,sex,is_fur,fur_variety)
  values(c.id,section,p_exhibitor_id,coalesce(nullif(p_changes->>'species',''),'rabbit')::public.species,nullif(btrim(p_changes->>'ear_number'),''),nullif(btrim(p_changes->>'animal_name'),''),nullif(btrim(p_changes->>'breed'),''),nullif(btrim(p_changes->>'variety'),''),nullif(btrim(p_changes->>'class'),''),nullif(btrim(p_changes->>'sex'),''),coalesce((p_changes->>'is_fur')::boolean,false),nullif(btrim(p_changes->>'fur_variety'),'')) returning id into i;
  perform public.calculate_entry_cart_balance_internal(c.id);
  insert into public.show_checkin_audit_events(show_id,exhibitor_id,event_type,actor_type,details) values(p_show_id,p_exhibitor_id,'checkin_add_entry_cart_item_created','system',jsonb_build_object('cart_id',c.id,'cart_item_id',i,'change_request_id',p_request_id));
  return i;
end; $$;
revoke all on function public.apply_checkin_add_entry(uuid,uuid,jsonb,uuid) from public,anon,authenticated;

create or replace function public.submit_exhibitor_checkin_add_entry(p_session_token text,p_changes jsonb,p_note text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.show_checkin_sessions%rowtype; cfg public.show_checkin_settings%rowtype; r uuid; mode text; item uuid;
begin
 select * into s from public.show_checkin_sessions where session_token_hash=encode(extensions.digest(btrim(coalesce(p_session_token,'')),'sha256'),'hex') and revoked_at is null and expires_at>now() for update;
 if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode='42501'; end if;
 select * into cfg from public.show_checkin_settings where show_id=s.show_id;
 mode:=coalesce(cfg.entry_edit_permissions->>'add_entry','disabled'); if mode not in ('automatic','approval') then raise exception 'Adding entries is not available through this portal'; end if;
 insert into public.show_checkin_change_requests(show_id,exhibitor_id,request_type,requested_changes,exhibitor_note,status,reviewed_at,applied_changes)
 values(s.show_id,s.exhibitor_id,'add_entry',p_changes,nullif(btrim(coalesce(p_note,'')),''),case when mode='automatic' then 'approved' else 'pending_review' end,case when mode='automatic' then now() else null end,'{}') returning id into r;
 if mode='automatic' then item:=public.apply_checkin_add_entry(s.show_id,s.exhibitor_id,p_changes,r); update public.show_checkin_change_requests set applied_changes=jsonb_build_object('cart_item_id',item) where id=r; end if;
 return jsonb_build_object('id',r,'status',case when mode='automatic' then 'approved' else 'pending_review' end,'cart_item_id',item);
end; $$;
revoke all on function public.submit_exhibitor_checkin_add_entry(text,jsonb,text) from public;
grant execute on function public.submit_exhibitor_checkin_add_entry(text,jsonb,text) to anon,authenticated,service_role;
