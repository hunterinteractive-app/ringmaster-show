create or replace function public.record_checkin_manual_payment(p_show_id uuid,p_exhibitor_id uuid,p_amount_cents integer,p_method text,p_reference text default null,p_receipt_preference text default 'no_receipt') returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.show_exhibitor_balances%rowtype; pid uuid; m text:=lower(btrim(coalesce(p_method,'')));
begin
 if not public.user_can_manage_entries(p_show_id) and not public.user_can_manage_show_settings(p_show_id) then raise exception 'Permission denied' using errcode='42501'; end if;
 if p_amount_cents<=0 or m not in ('cash','check','digital','stripe','square','paypal') then raise exception 'Invalid payment'; end if;
 select * into b from public.show_exhibitor_balances where show_id=p_show_id and exhibitor_id=p_exhibitor_id order by updated_at desc limit 1 for update;
 if not found then raise exception 'No exhibitor balance found'; end if;
 insert into public.show_payments(show_id,exhibitor_id,currency,status,payment_status,payment_method,payment_method_type,payment_type,provider,amount_cents,total_cents,paid_at,metadata) values(p_show_id,p_exhibitor_id,b.currency,'paid','paid',m,m,'manual',m,p_amount_cents,p_amount_cents,now(),jsonb_build_object('reference',p_reference,'receipt_preference',p_receipt_preference,'source','checkin')) returning id into pid;
 update public.show_exhibitor_balances set paid_manual_cents=paid_manual_cents+p_amount_cents,balance_due_cents=greatest(0,calculated_total_cents-paid_online_cents-(paid_manual_cents+p_amount_cents)+refunded_cents),payment_status=case when calculated_total_cents<=paid_online_cents+paid_manual_cents+p_amount_cents then 'paid' else 'partial' end,updated_at=now() where id=b.id;
 insert into public.show_checkin_audit_events(show_id,exhibitor_id,event_type,actor_type,actor_user_id,details) values(p_show_id,p_exhibitor_id,'manual_payment_recorded','secretary',auth.uid(),jsonb_build_object('payment_id',pid,'amount_cents',p_amount_cents,'method',m));
 return jsonb_build_object('payment_id',pid,'balance_id',b.id);
end; $$;
revoke all on function public.record_checkin_manual_payment(uuid,uuid,integer,text,text,text) from public;
grant execute on function public.record_checkin_manual_payment(uuid,uuid,integer,text,text,text) to authenticated,service_role;
