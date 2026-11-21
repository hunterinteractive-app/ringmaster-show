-- Reviewed one-show repair. Run inside a transaction; assertions abort on drift.
-- User approved $4 class / $2 fur, excluding currently scratched/removed entries.
-- No payments are created; original cart items and entry ownership are retained.
-- False-paid entry flags are audited and corrected to unpaid.
set local lock_timeout='3s';
set local statement_timeout='60s';
lock table public.entries,public.entry_cart_items,public.entry_carts,
 public.show_exhibitor_balances,public.show_payments,public.show_payment_sessions
 in share row exclusive mode;
do $$
declare
 p_show constant uuid:='791ef44c-d980-4e96-91f4-6446fb907d5f';
 b record; x record; v_items jsonb; v_sections jsonb; v_class int; v_fur int;
 v_reason constant text:='Owner-approved correction: Southern Adirondack active class entries $4, fur $2; unpaid scratches and removed entries excluded. No recorded payments, discounts or credits. Original zero/incorrect checkout snapshots retained in private audit.';
begin
 if not exists(select 1 from public.shows where id=p_show and name='Southern Adirondack Hops & Harvest 2026') then raise exception 'Unexpected show'; end if;
 if exists(select 1 from public.show_payments where show_id=p_show)
  or exists(select 1 from public.show_payment_sessions s join public.entry_carts c on c.id=s.cart_id where c.show_id=p_show)
  or exists(select 1 from public.show_exhibitor_balances where show_id=p_show and
   (coalesce(paid_online_cents,0)<>0 or coalesce(paid_manual_cents,0)<>0 or coalesce(refunded_cents,0)<>0 or coalesce(discount_cents,0)<>0))
  or exists(select 1 from show_finances_private.events where show_id=p_show and kind in('payment','credit'))
  or exists(select 1 from entry_discount_private.accepted_codes where show_id=p_show)
  then raise exception 'Payment/discount/credit state changed; review before repair'; end if;
 if exists(select 1 from show_finances_private.cart_quote_corrections where show_id=p_show) then raise exception 'Already corrected; do not reprice twice'; end if;
 if (select count(*) from public.show_sections where show_id=p_show)<>8
  or exists(select 1 from public.show_sections s left join public.show_section_fee_settings f on f.section_id=s.id
    where s.show_id=p_show and (f.fee_per_entry is distinct from 4::numeric or f.fur_fee is distinct from 2::numeric or coalesce(f.fee_per_show,0)<>0))
  then raise exception 'Fee configuration changed'; end if;
 if (select count(*) from public.entries where show_id=p_show)<>3278 then raise exception 'Entry population changed'; end if;
 perform set_config('ringmaster.manual_balance_refresh','on',true);
 perform set_config('ringmaster.payment_state_write','on',true);
 for b in select cb.* from public.show_exhibitor_balances cb join public.entry_carts c on c.id=coalesce(cb.entry_cart_id,cb.cart_id)
  where cb.show_id=p_show and cb.source='cart' and (c.status='submitted' or exists(select 1 from public.entries e where e.source_cart_id=c.id and e.show_id=p_show))
  order by cb.id
 loop
  select coalesce(jsonb_agg(to_jsonb(i) order by i.id),'[]') into v_items
  from public.entry_cart_items i join public.entries e on e.source_cart_item_id=i.id and e.source_cart_id=i.cart_id
   and e.show_id=p_show and coalesce(e.is_fur,false)=coalesce(i.is_fur,false)
  where i.cart_id=coalesce(b.entry_cart_id,b.cart_id) and i.exhibitor_id=b.exhibitor_id
   and not coalesce(i.is_show_addon_carrier,false) and not coalesce(i.is_checkin_fee_carrier,false) and not coalesce(i.is_exhibitor_fee_carrier,false)
   and e.scratched_at is null and not coalesce(e.is_test,false) and lower(coalesce(e.status,'')) not in('deleted','cancelled','canceled','scratched');
  insert into show_finances_private.cart_quote_corrections(balance_id,show_id,original_balance,original_cart,quote_items,reason)
   select b.id,p_show,to_jsonb(b),to_jsonb(c),v_items,v_reason from public.entry_carts c where c.id=coalesce(b.entry_cart_id,b.cart_id);
  with parts as (
   select (i->>'section_id')::uuid section_id,count(*) filter(where not coalesce((i->>'is_fur')::boolean,false)) ec,
    count(*) filter(where coalesce((i->>'is_fur')::boolean,false)) fc
   from jsonb_array_elements(v_items) i group by i->>'section_id'
  ) select coalesce(jsonb_agg(jsonb_build_object('section_id',s.id,'kind',s.kind,'letter',s.letter,
   'label',coalesce(nullif(s.display_name,''),initcap(s.kind::text)||' '||s.letter),
   'entry_count',p.ec,'fur_count',p.fc,'entries_subtotal_cents',p.ec*400,'fur_subtotal_cents',p.fc*200,
   'show_fee_cents',0,'discount_scope_eligible',true) order by s.id),'[]'),coalesce(sum(ec),0),coalesce(sum(fc),0)
   into v_sections,v_class,v_fur from parts p join public.show_sections s on s.id=p.section_id and s.show_id=p_show;
  update public.show_exhibitor_balances set entry_count=v_class,fur_count=v_fur,
   entries_subtotal_cents=v_class*400,fur_subtotal_cents=v_fur*200,show_fee_subtotal_cents=0,addons_subtotal_cents=0,
   subtotal_before_discount_cents=v_class*400+v_fur*200,discount_cents=0,calculated_total_cents=v_class*400+v_fur*200,
   balance_due_cents=v_class*400+v_fur*200,payment_status=case when v_class+v_fur>0 then 'unpaid' else 'paid' end,
   section_breakdown=v_sections,fee_snapshot=coalesce(b.fee_snapshot,'{}')||jsonb_build_object(
    'reviewed_quote_correction',true,'correction_reason',v_reason,'corrected_at',now(),'section_breakdown',v_sections,
    'entry_count',v_class,'fur_count',v_fur,'eligible_entry_count',v_class,
    'entries_subtotal_cents',v_class*400,'fur_subtotal_cents',v_fur*200,'show_fee_subtotal_cents',0,'addons_subtotal_cents',0,
    'subtotal_before_discount_cents',v_class*400+v_fur*200,'calculated_total_cents',v_class*400+v_fur*200),calculated_at=now(),updated_at=now()
   where id=b.id;
 end loop;
 -- Repair only the old false-paid checkout status; no receipt or paid_at is fabricated.
 update public.entry_carts c set payment_status=case when q.total>0 then 'unpaid' else 'paid' end,updated_at=now()
 from (select coalesce(entry_cart_id,cart_id) cart_id,sum(calculated_total_cents) total from public.show_exhibitor_balances
  where show_id=p_show and source='cart' and id in(select balance_id from show_finances_private.cart_quote_corrections where show_id=p_show)
  group by coalesce(entry_cart_id,cart_id)) q where c.id=q.cart_id;
 insert into show_finances_private.events(show_id,exhibitor_id,kind,reason,details)
 select p_show,exhibitor_id,'allocation',v_reason,jsonb_build_object('original_entry_payment_states',
  jsonb_agg(jsonb_build_object('entry_id',id,'payment_status',payment_status,'paid_at',paid_at) order by id))
 from public.entries where show_id=p_show and scratched_at is null and not coalesce(is_test,false)
  and lower(coalesce(status,'')) not in('deleted','cancelled','canceled','scratched')
  and (payment_status is distinct from 'unpaid' or paid_at is not null) group by exhibitor_id;
 update public.entries set payment_status='unpaid',paid_at=null where show_id=p_show
  and scratched_at is null and not coalesce(is_test,false)
  and lower(coalesce(status,'')) not in('deleted','cancelled','canceled','scratched')
  and (payment_status is distinct from 'unpaid' or paid_at is not null);
 perform set_config('ringmaster.manual_balance_refresh','off',true);
 for x in select exhibitor_id from public.entries where show_id=p_show union select exhibitor_id from public.show_exhibitor_balances where show_id=p_show and source='entries'
 loop perform manual_entry_balances_private.refresh(p_show,x.exhibitor_id); end loop;
 -- Compare every maintained balance to an independent active-entry calculation.
 if exists(
  with expected as(select exhibitor_id,count(*) filter(where not coalesce(is_fur,false)) ec,
   count(*) filter(where coalesce(is_fur,false)) fc,sum(case when coalesce(is_fur,false) then 200 else 400 end) due
   from public.entries where show_id=p_show and scratched_at is null and not coalesce(is_test,false)
    and lower(coalesce(status,'')) not in('deleted','cancelled','canceled','scratched') group by exhibitor_id),
  actual as(select * from public.show_exhibitor_balances where show_id=p_show and source='entries')
  select 1 from expected e full join actual a on a.exhibitor_id=e.exhibitor_id
   where coalesce(e.due,0) is distinct from a.balance_due_cents or coalesce(e.ec,0) is distinct from a.entry_count
    or coalesce(e.fc,0) is distinct from a.fur_count or a.calculated_total_cents is distinct from coalesce(e.due,0)
 ) then raise exception 'Per-exhibitor reconciliation failed'; end if;
 if (select sum(balance_due_cents) from public.show_exhibitor_balances where show_id=p_show and source='entries')<>1264200
  or (select count(*) from public.show_exhibitor_balances where show_id=p_show and source='entries' and balance_due_cents>0)<>148
 then raise exception 'Unexpected show totals'; end if;
 perform set_config('ringmaster.payment_state_write','off',true);
end $$;
select count(*) filter(where balance_due_cents>0) exhibitors,sum(entry_count) class_entries,sum(fur_count) fur_entries,
 sum(balance_due_cents) balance_due_cents from public.show_exhibitor_balances
 where show_id='791ef44c-d980-4e96-91f4-6446fb907d5f' and source='entries';
