-- Read-only, RLS-bound eligibility shared by the UI and database write guard.
-- Match animals, not tattoos; two different animals may share an ear number.
create or replace function public.report_fur_breed_eligibility(
 p_show_id uuid, p_entry_ids uuid[]
) returns table(entry_id uuid, blocked_reason text)
language sql stable security invoker set search_path='' as $$
 select f.id, case
   when b.id is null then 'No matching breed entry in this show section.'
   when b.scratched_at is not null or lower(coalesce(b.status,''))='scratched'
     then 'The breed entry is scratched.'
   when b.is_disqualified or lower(coalesce(b.result_status,'')) like 'disqualified%'
     then 'Breed entry disqualified: ' || coalesce(nullif(b.disqualified_reason,''),nullif(b.result_status,''),'reason not recorded')
   when lower(coalesce(b.result_status,''))='no show' or b.is_shown=false
     then 'The animal did not show in its breed class.'
   when b.result_status is null and b.placement is null and b.result_entered_at is null
     then 'Record the breed judging result first.'
   else null end
 from public.entries f
 left join lateral (
   select e.* from public.entries e
   where e.show_id=f.show_id and e.section_id=f.section_id
     and e.exhibitor_id=f.exhibitor_id and e.animal_id=f.animal_id
     and not coalesce(e.is_fur,false) and not coalesce((to_jsonb(e)->>'is_commercial')::boolean,false)
     -- Never use the legacy extra breed row created from a fur cart item.
     and not exists(select 1 from public.entry_cart_items i
       where i.id=e.source_cart_item_id and i.cart_id=e.source_cart_id and i.is_fur)
   order by (e.scratched_at is null and lower(coalesce(e.status,''))<>'scratched') desc,
     e.created_at,e.id limit 1
 ) b on true
 where f.show_id=p_show_id and f.id=any(p_entry_ids) and f.is_fur
$$;
revoke all on function public.report_fur_breed_eligibility(uuid,uuid[]) from public,anon;
grant execute on function public.report_fur_breed_eligibility(uuid,uuid[]) to authenticated,service_role;

-- Trigger-only definer: see the complete breed record even if a writer only
-- has permission to edit the fur class. This grants no new write privileges.
create or replace function checkout_private.guard_fur_result_eligibility()
returns trigger language plpgsql security definer set search_path='' as $$
declare reason text;
begin
 -- Payments, notes, and report bookkeeping must remain independently editable.
 if tg_op='UPDATE' and (
   new.is_fur,new.animal_id,new.show_id,new.section_id,new.exhibitor_id,
   new.result_status,new.fur_placement,new.placement,new.is_disqualified,
   new.is_shown,new.result_entered_at,to_jsonb(new)->>'fur_award'
 ) is not distinct from (
   old.is_fur,old.animal_id,old.show_id,old.section_id,old.exhibitor_id,
   old.result_status,old.fur_placement,old.placement,old.is_disqualified,
   old.is_shown,old.result_entered_at,to_jsonb(old)->>'fur_award'
 ) then return new; end if;
 if coalesce(new.is_fur,false) and (
   lower(coalesce(new.result_status,''))='shown'
   or coalesce(new.fur_placement,0)>0
   or coalesce(new.placement,'') not in ('','0')
   or coalesce(to_jsonb(new)->>'fur_award','')<>''
 ) then
   select blocked_reason into reason from public.report_fur_breed_eligibility(new.show_id,array[new.id]);
   if reason is not null then
     raise exception 'Fur / Wool result cannot be saved: %',reason;
   end if;
 end if;
 return new;
end $$;
revoke all on function checkout_private.guard_fur_result_eligibility() from public,anon,authenticated;
create trigger guard_fur_result_eligibility
 after insert or update on public.entries
 for each row execute function checkout_private.guard_fur_result_eligibility();

-- Reviewed Oregon duplicates: both their legitimate breed rows already carry
-- the same No Show result. Preserve evidence, do not change real judging rows.
do $$
declare e public.entries; candidate uuid;
begin
 foreach candidate in array array[
   'cc49b1f3-eb48-47e2-a02f-44b23f5679a4'::uuid,
   '05714113-f7f4-471f-87c3-6938a88b8377'::uuid
 ] loop
   select * into e from public.entries where id=candidate for update;
   if not found then continue; end if;
   if e.show_id<>'2f3246f9-7174-4ce8-a4fd-9ae80cbcf35f'::uuid
     or coalesce(e.is_fur,false) or e.result_status is distinct from 'No Show'
     or e.placement is not null or e.fur_placement is not null
     or nullif(to_jsonb(e)->>'special_awards','') is not null
     or nullif(to_jsonb(e)->>'fur_award','') is not null
     or checkout_private.entry_has_references(e.id)
     or exists(select 1 from entry_refunds_private.entries where entry_id=e.id)
     or exists(select 1 from public.shows where id=e.show_id and is_locked)
     or not exists(select 1 from public.entry_cart_items i where i.id=e.source_cart_item_id and i.cart_id=e.source_cart_id and i.is_fur)
     or not exists(select 1 from public.entries f where f.is_fur and f.source_cart_item_id=e.source_cart_item_id and f.source_cart_id=e.source_cart_id)
     or not exists(select 1 from public.entries r join public.entry_cart_items i on i.id=r.source_cart_item_id and i.cart_id=r.source_cart_id
       where r.show_id=e.show_id and r.section_id=e.section_id and r.animal_id=e.animal_id
       and r.exhibitor_id=e.exhibitor_id and r.source_cart_id=e.source_cart_id and not coalesce(r.is_fur,false)
       and not coalesce(i.is_fur,false) and r.result_status='No Show')
   then raise exception 'Oregon duplicate % changed since review; inspect before cleanup',candidate; end if;
   insert into checkout_private.fur_duplicate_audit(entry_id,entry_snapshot,disposition)
   values(e.id,to_jsonb(e),'removed_reviewed_no_show_duplicate')
   on conflict(entry_id) do update set disposition=excluded.disposition,reviewed_at=now();
   delete from public.entries where id=e.id;
 end loop;
end $$;
