-- User-selected changes are atomic and limited to one animal/exhibitor/event.
create schema if not exists entry_sections_private;
revoke all on schema entry_sections_private from public,anon;
grant usage on schema entry_sections_private to authenticated;
create or replace function entry_sections_private.apply_changes(
 p_entry_id uuid, p_section_ids uuid[], p_changes jsonb default '{}', p_is_scratched boolean default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare e public.entries; s public.shows; staff boolean; ids uuid[]; target uuid; changed integer;
begin
 if auth.uid() is null then raise exception 'Sign in to change entries' using errcode='42501'; end if;
 select * into e from public.entries where id=p_entry_id;
 if not found then raise exception 'Entry not found'; end if;
 select * into s from public.shows where id=e.show_id for share;
 if coalesce(s.is_locked,false) or s.finalized_at is not null then raise exception 'Show is locked. Changes are not allowed.'; end if;
 staff:=coalesce(public.user_can_manage_entries(e.show_id) or public.user_can_manage_show_settings(e.show_id),false);
 if not staff and not coalesce(household_private.has_access(e.exhibitor_user_id),false) then
  raise exception 'You do not have permission to update this entry' using errcode='42501'; end if;
 if not staff and (p_is_scratched is distinct from true) and s.entry_close_at is not null and now()>=s.entry_close_at then
  raise exception 'Entry deadline passed. Editing and restoring are locked.'; end if;
 if coalesce(cardinality(p_section_ids),0)=0 or cardinality(p_section_ids)>100 or array_position(p_section_ids,null) is not null then raise exception 'Choose show sections'; end if;
 if p_changes is null or jsonb_typeof(p_changes)<>'object' then raise exception 'Invalid entry changes'; end if;
 if exists(select 1 from jsonb_object_keys(p_changes) k where k not in ('tattoo','class_name','animal_name','breed','variety','sex','notes'))
  or (not staff and exists(select 1 from jsonb_object_keys(p_changes) k where k not in ('tattoo','class_name'))) then
  raise exception 'These fields cannot be changed together' using errcode='42501'; end if;
 if p_changes ? 'tattoo' and (length(btrim(coalesce(p_changes->>'tattoo','')))=0 or length(p_changes->>'tattoo')>100) then
  raise exception 'Enter a tattoo / ear number (100 characters or fewer)'; end if;
 if p_changes ? 'class_name' and coalesce(p_changes->>'class_name','') not in ('Pre-Junior','Junior','Intermediate','Senior') then raise exception 'Invalid class'; end if;
 if p_is_scratched is not null and p_changes<>'{}' then raise exception 'Save edits and scratches separately'; end if;
 if lower(coalesce(e.status,'')) in ('deleted','removed','withdrawn','cancelled','canceled') then raise exception 'Entry is no longer active'; end if;
 -- All targets must match the anchored animal and exhibitor; never match by tattoo.
 select array_agg(t.id order by t.id) into ids from public.entries t
 where t.show_id=e.show_id and t.exhibitor_id=e.exhibitor_id and t.section_id=any(p_section_ids)
  and ((e.animal_id is not null and t.animal_id=e.animal_id) or t.id=e.id)
  and lower(coalesce(t.status,'')) not in ('deleted','removed','withdrawn','cancelled','canceled');
 if ids is null or exists(select 1 from unnest(p_section_ids) section where not exists(
   select 1 from public.entries t where t.id=any(ids) and t.section_id=section)) then
  raise exception 'A selected section no longer contains this animal. Refresh and try again.'; end if;
 perform 1 from public.entries where id=any(ids) order by id for update;
 -- Re-check the anchor after locking against concurrent reassignment.
 if not exists(select 1 from public.entries where id=e.id and show_id=e.show_id and exhibitor_id=e.exhibitor_id
    and animal_id is not distinct from e.animal_id) then raise exception 'Entry changed. Refresh and try again.'; end if;
 if exists(select 1 from public.entries where id=any(ids) and (lower(coalesce(status,'')) in ('deleted','removed','withdrawn','cancelled','canceled') or show_id<>e.show_id or exhibitor_id<>e.exhibitor_id or animal_id is distinct from e.animal_id)) then raise exception 'An entry changed. Refresh and try again.'; end if;
 if not staff and p_is_scratched is null and exists(select 1 from public.entries where id=any(ids) and (scratched_at is not null or lower(status)='scratched')) then raise exception 'Restore scratched entries before editing them'; end if;
 if p_changes ? 'tattoo' and exists(select 1 from public.entries where id=any(ids) and meat_pen_id is not null) then
  raise exception 'Use the meat pen tattoo editor for meat pen entries'; end if;
 if p_is_scratched is not null then
  foreach target in array ids loop perform public.set_entry_scratch_state(target,p_is_scratched); end loop;
 else
  update public.entries t set
   tattoo=case when p_changes?'tattoo' then upper(btrim(p_changes->>'tattoo')) else t.tattoo end,
   class_name=case when p_changes?'class_name' then p_changes->>'class_name' else t.class_name end,
   animal_name=case when p_changes?'animal_name' then p_changes->>'animal_name' else t.animal_name end,
   breed=case when p_changes?'breed' then p_changes->>'breed' else t.breed end,
   variety=case when p_changes?'variety' and not coalesce(t.is_fur,false) then p_changes->>'variety' else t.variety end,
   sex=case when p_changes?'sex' then p_changes->>'sex' else t.sex end,
   notes=case when p_changes?'notes' then p_changes->>'notes' else t.notes end, updated_at=now()
  where t.id=any(ids);
  insert into public.show_checkin_audit_events(show_id,exhibitor_id,event_type,actor_type,actor_user_id,details)
  values(e.show_id,e.exhibitor_id,'entry_sections_edited',case when staff then 'secretary' else 'exhibitor_portal' end,
   auth.uid(),jsonb_build_object('entry_ids',ids,'section_ids',p_section_ids,'changes',p_changes));
 end if;
 return jsonb_build_object('entry_count',cardinality(ids),'entry_ids',ids);
end $$;
revoke all on function entry_sections_private.apply_changes(uuid,uuid[],jsonb,boolean) from public,anon;
grant execute on function entry_sections_private.apply_changes(uuid,uuid[],jsonb,boolean) to authenticated;
create or replace function public.apply_entry_section_changes(
 p_entry_id uuid,p_section_ids uuid[],p_changes jsonb default '{}',p_is_scratched boolean default null)
returns jsonb language sql security invoker set search_path='' as $$
 select entry_sections_private.apply_changes(p_entry_id,p_section_ids,p_changes,p_is_scratched);
$$;
revoke all on function public.apply_entry_section_changes(uuid,uuid[],jsonb,boolean) from public,anon;
grant execute on function public.apply_entry_section_changes(uuid,uuid[],jsonb,boolean) to authenticated;

-- Preserve checkout quotes/receipts. Record exact unpaid line amounts at the
-- time of a qualifying scratch, then project those lines out of current charges.
create table if not exists show_finances_private.unpaid_scratch_lines (
 entry_id uuid primary key, balance_id uuid not null references public.show_exhibitor_balances(id),
 show_id uuid not null, exhibitor_id uuid not null, section_id uuid not null,
 is_fur boolean not null, gross_cents integer not null check(gross_cents>=0),
 discount_cents integer not null check(discount_cents>=0 and discount_cents<=gross_cents),
 active boolean not null default true, scratched_at timestamptz not null, actor_user_id uuid,
 updated_at timestamptz not null default now()
);
create index if not exists unpaid_scratch_balance on show_finances_private.unpaid_scratch_lines(balance_id) where active;
alter table show_finances_private.unpaid_scratch_lines enable row level security;
revoke all on show_finances_private.unpaid_scratch_lines from public,anon,authenticated;

create or replace function show_finances_private.capture_unpaid_scratch() returns trigger
language plpgsql security definer set search_path='' as $$
declare b public.show_exhibitor_balances; c public.entry_carts; deadline timestamptz;
 gross integer; v_discount integer; before_active boolean; after_active boolean; quote_items jsonb;
begin
 before_active:=old.scratched_at is not null or lower(coalesce(old.status,''))='scratched';
 after_active:=new.scratched_at is not null or lower(coalesce(new.status,''))='scratched';
 if before_active=after_active then return new; end if;
 update show_finances_private.unpaid_scratch_lines set active=false,updated_at=now() where entry_id=new.id;
 if not after_active or new.source_cart_id is null or new.source_cart_item_id is null then return new; end if;
 select entry_close_at into deadline from public.shows where id=new.show_id;
 -- A missing deadline does not establish eligibility; no historical backfill.
 if deadline is null or now()>=deadline then return new; end if;
 select * into c from public.entry_carts where id=new.source_cart_id for update;
 if c.status<>'submitted' or c.active_payment_session_id is not null or c.payment_status='pending' then
  if c.active_payment_session_id is not null or c.payment_status='pending' then
   raise exception 'A payment is in progress. Finish or cancel it before scratching this entry.'; end if;
  return new;
 end if;
 select * into b from public.show_exhibitor_balances where source='cart' and show_id=new.show_id
  and exhibitor_id=new.exhibitor_id and coalesce(entry_cart_id,cart_id)=new.source_cart_id for update;
 if not found then return new; end if;
 -- Partial payments cannot be assigned to individual entries by guesswork.
 if coalesce(b.paid_online_cents,0)+coalesce(b.paid_manual_cents,0)+coalesce(b.refunded_cents,0)>0
  or exists(select 1 from public.show_exhibitor_balances a where a.show_id=new.show_id and a.exhibitor_id=new.exhibitor_id
    and a.source='entries' and coalesce(a.paid_online_cents,0)+coalesce(a.paid_manual_cents,0)+coalesce(a.refunded_cents,0)
     > (select coalesce(sum(coalesce(cb.paid_online_cents,0)+coalesce(cb.paid_manual_cents,0)+coalesce(cb.refunded_cents,0)),0)
        from public.show_exhibitor_balances cb where cb.show_id=new.show_id and cb.exhibitor_id=new.exhibitor_id and cb.source='cart'))
  then return new; end if;
 select q.quote_items into quote_items from show_finances_private.cart_quote_corrections q where q.balance_id=b.id;
 with items as (
  select i.*,row_number() over(partition by i.section_id,coalesce(i.is_fur,false) order by i.id) rn,
   count(*) over(partition by i.section_id,coalesce(i.is_fur,false)) cnt
  from public.entry_cart_items i where i.cart_id=c.id and i.exhibitor_id=new.exhibitor_id
   and not coalesce(i.is_show_addon_carrier,false) and not coalesce(i.is_checkin_fee_carrier,false)
   and not coalesce(i.is_exhibitor_fee_carrier,false)
   and (quote_items is null or exists(select 1 from jsonb_array_elements(quote_items) q where q->>'id'=i.id::text))
 ), amounts as (
  select i.*,show_finances_private.share(coalesce((s->>case when coalesce(i.is_fur,false) then 'fur_subtotal_cents' else 'entries_subtotal_cents' end)::integer,0),i.rn-1,1,i.cnt) cents,
   not coalesce(i.is_fur,false) and coalesce((s->>'discount_scope_eligible')::boolean,true) eligible,
   (s->>case when coalesce(i.is_fur,false) then 'fur_count' else 'entry_count' end)::integer=i.cnt valid
  from items i join jsonb_array_elements(b.section_breakdown) s on s->>'section_id'=i.section_id::text
 ), net as (
  select *,show_finances_private.share(coalesce(b.discount_cents,0),
   coalesce(sum(case when eligible then cents else 0 end) over(order by id rows between unbounded preceding and 1 preceding),0)::bigint,
   case when eligible then cents else 0 end,sum(case when eligible then cents else 0 end) over()) discount
  from amounts
 ) select net.cents,net.discount into gross,v_discount from net where id=new.source_cart_item_id and valid
  and section_id=new.section_id and coalesce(is_fur,false)=coalesce(new.is_fur,false);
 if gross is null or v_discount is null or v_discount>gross then
  raise exception 'The original entry fee needs review before this unpaid scratch can change the balance.'; end if;
 insert into show_finances_private.unpaid_scratch_lines(entry_id,balance_id,show_id,exhibitor_id,section_id,is_fur,gross_cents,discount_cents,scratched_at,actor_user_id)
 values(new.id,b.id,new.show_id,new.exhibitor_id,new.section_id,coalesce(new.is_fur,false),gross,v_discount,now(),auth.uid())
 on conflict(entry_id) do update set active=true,gross_cents=excluded.gross_cents,discount_cents=excluded.discount_cents,
  scratched_at=excluded.scratched_at,actor_user_id=excluded.actor_user_id,updated_at=now();
 return new;
end $$;
revoke all on function show_finances_private.capture_unpaid_scratch() from public,anon,authenticated;
drop trigger if exists unpaid_scratch_before_update on public.entries;
create trigger unpaid_scratch_before_update before update on public.entries
 for each row execute function show_finances_private.capture_unpaid_scratch();

do $$ begin if to_regprocedure('show_finances_private.cart_parts_before_unpaid_scratch(jsonb)') is null then alter function show_finances_private.cart_parts(jsonb) rename to cart_parts_before_unpaid_scratch; end if; end $$;
create or replace function show_finances_private.cart_parts(p_balance jsonb) returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
declare part jsonb; sections jsonb; removed_gross integer; removed_discount integer;
 removed_entries integer; removed_fur integer; removed_class integer; removed_fur_cents integer;
begin
 for part in select * from show_finances_private.cart_parts_before_unpaid_scratch(p_balance) loop
  with removed as (
   select x.* from show_finances_private.unpaid_scratch_lines x
   left join public.entries e on e.id=x.entry_id
   where x.balance_id=(p_balance->>'id')::uuid and x.active
    and coalesce(e.exhibitor_id,x.exhibitor_id)::text=part->>'exhibitor_id'
  ) select coalesce(sum(gross_cents),0),coalesce(sum(discount_cents),0),
   count(*) filter(where not is_fur),count(*) filter(where is_fur),
   coalesce(sum(gross_cents) filter(where not is_fur),0),coalesce(sum(gross_cents) filter(where is_fur),0)
  into removed_gross,removed_discount,removed_entries,removed_fur,removed_class,removed_fur_cents from removed;
  if removed_entries+removed_fur=0 then return next part; continue; end if;
  select jsonb_agg(s || jsonb_build_object(
   'entry_count',greatest(0,coalesce((s->>'entry_count')::integer,0)-r.entries),
   'fur_count',greatest(0,coalesce((s->>'fur_count')::integer,0)-r.fur),
   'entries_subtotal_cents',greatest(0,coalesce((s->>'entries_subtotal_cents')::integer,0)-r.class_cents),
   'fur_subtotal_cents',greatest(0,coalesce((s->>'fur_subtotal_cents')::integer,0)-r.fur_cents))) into sections
  from jsonb_array_elements(part->'section_breakdown') s cross join lateral (
   select count(*) filter(where not x.is_fur)::integer entries,count(*) filter(where x.is_fur)::integer fur,
    coalesce(sum(x.gross_cents) filter(where not x.is_fur),0)::integer class_cents,
    coalesce(sum(x.gross_cents) filter(where x.is_fur),0)::integer fur_cents
   from show_finances_private.unpaid_scratch_lines x left join public.entries e on e.id=x.entry_id
   where x.balance_id=(p_balance->>'id')::uuid and x.active
    and coalesce(e.exhibitor_id,x.exhibitor_id)::text=part->>'exhibitor_id'
    and coalesce(e.section_id,x.section_id)::text=s->>'section_id'
  ) r;
  return next part || jsonb_build_object('section_breakdown',sections,
   'entry_count',(part->>'entry_count')::integer-removed_entries,'fur_count',(part->>'fur_count')::integer-removed_fur,
   'entries_subtotal_cents',(part->>'entries_subtotal_cents')::integer-removed_class,
   'fur_subtotal_cents',(part->>'fur_subtotal_cents')::integer-removed_fur_cents,
   'subtotal_before_discount_cents',(part->>'subtotal_before_discount_cents')::integer-removed_gross,
   'discount_cents',coalesce((part->>'discount_cents')::integer,0)-removed_discount,
   'calculated_total_cents',(part->>'calculated_total_cents')::integer-removed_gross+removed_discount,
   'balance_due_cents',greatest(0,(part->>'calculated_total_cents')::integer-removed_gross+removed_discount
    -coalesce((part->>'paid_online_cents')::integer,0)-coalesce((part->>'paid_manual_cents')::integer,0)+coalesce((part->>'refunded_cents')::integer,0)));
 end loop;
end $$;
revoke all on function show_finances_private.cart_parts(jsonb) from public,anon,authenticated;

-- Show the same adjusted amount in the exhibitor portal. Original cart quotes
-- are historical; their balance_due must not be displayed as today's charge.
do $migration$
declare target regprocedure; definition text;
begin
 foreach target in array array[
  to_regprocedure('checkout_private.list_submitted_balances(uuid)'),
  to_regprocedure('public.support_submitted_balances(uuid,uuid)')
 ] loop
  if target is null then continue; end if;
  definition:=pg_get_functiondef(target);
  if strpos(definition,'current_part.value')>0 then continue; end if;
  if strpos(definition,'sum(b.balance_due_cents)')=0 or strpos(definition,'join public.exhibitors e on e.id=b.exhibitor_id')=0 then raise exception 'Unexpected submitted balance function: %',target; end if;
  definition:=replace(definition,'sum(b.balance_due_cents)',
    'sum((current_part.value->>''balance_due_cents'')::integer)');
  definition:=replace(definition,'join public.exhibitors e on e.id=b.exhibitor_id',
    'cross join lateral show_finances_private.cart_parts(to_jsonb(b)) current_part(value) join public.exhibitors e on e.id=(current_part.value->>''exhibitor_id'')::uuid');
  execute definition;
 end loop;
end $migration$;

-- Existing online checkout reprices and replaces the submitted cart quote.
-- Require secretary review for adjusted submissions, just as for other edited
-- submissions, rather than subtracting a waiver twice from a replacement quote.
do $migration$
declare definition text;
begin
 if to_regprocedure('checkout_private.validate_submitted_cart(uuid)') is null then return; end if;
 definition:=pg_get_functiondef('checkout_private.validate_submitted_cart(uuid)'::regprocedure);
 if strpos(definition,'unpaid_scratch_lines')>0 then return; end if;
 if strpos(definition,E'begin\n')=0 then raise exception 'Unexpected submitted checkout validator'; end if;
 definition:=replace(definition,E'begin\n',E'begin\n if exists(select 1 from show_finances_private.unpaid_scratch_lines x join public.show_exhibitor_balances b on b.id=x.balance_id where x.active and coalesce(b.entry_cart_id,b.cart_id)=p_cart_id) then raise exception ''This submission has adjusted scratch fees. Please contact the show secretary to confirm payment of the remaining balance.''; end if;\n');
 execute definition;
end $migration$;
notify pgrst,'reload schema';
