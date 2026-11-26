-- One definition of the current balance: use the exhibitor-level snapshot
-- when present, otherwise count only committed/submitted carts.
create function show_finances_private.current_balance_rows(p_show_id uuid)
returns setof public.show_exhibitor_balances
language sql stable set search_path='' as $$
  select b.*
  from public.show_exhibitor_balances b
  left join public.entry_carts c on c.id=coalesce(b.entry_cart_id,b.cart_id)
  where b.show_id=p_show_id
    and (b.source='entries' or (
      b.source='cart' and c.status='submitted'
      and not exists (
        select 1 from public.show_exhibitor_balances authoritative
        where authoritative.show_id=b.show_id and authoritative.exhibitor_id=b.exhibitor_id
          and authoritative.source='entries'
      )
    ));
$$;
revoke all on function show_finances_private.current_balance_rows(uuid) from public,anon,authenticated;

-- Retain the current Finance RPC contract, sorting, and settlement summary.
do $$
declare
  body text := pg_get_functiondef('public.get_show_finances(uuid)'::regprocedure);
  anchor text := $anchor$with selected as (
  select b.* from public.show_exhibitor_balances b left join public.entry_carts c on c.id=coalesce(b.entry_cart_id,b.cart_id)
  where b.show_id=p_show_id and (b.source='entries' or (b.source='cart' and c.status='submitted'
   and not exists(select 1 from public.show_exhibitor_balances a where a.show_id=b.show_id and a.exhibitor_id=b.exhibitor_id and a.source='entries')))
 ), totals as ($anchor$;
begin
  if (length(body)-length(replace(body,anchor,'')))/length(anchor)<>1 then
    raise exception 'Unexpected get_show_finances balance selection';
  end if;
  execute replace(body,anchor,'with selected as (select * from show_finances_private.current_balance_rows(p_show_id)), totals as (');
end;
$$;

-- The printable report has the same exhibitor/currency totals as Finance,
-- plus the contact and section breakdown needed for check-in.
create function public.report_current_show_balances(p_show_id uuid)
returns setof jsonb
language plpgsql stable security definer set search_path='' as $$
begin
  if coalesce(auth.jwt()->>'role','') <> 'service_role' then
    perform show_finances_private.authorize(p_show_id);
  end if;

  return query
  with selected as materialized (
    select * from show_finances_private.current_balance_rows(p_show_id)
  ), totals as (
    select exhibitor_id,currency,
      min(id::text) as balance_id,
      case when bool_or(source='entries') then 'entries' else 'cart' end as source,
      sum(entry_count) as entry_count,sum(fur_count) as fur_count,
      sum(entries_subtotal_cents) as entry_fee_subtotal_cents,
      sum(fur_subtotal_cents) as fur_fee_subtotal_cents,
      sum(show_fee_subtotal_cents) as show_fee_subtotal_cents,
      sum(subtotal_before_discount_cents) as subtotal_before_discount_cents,
      sum(discount_cents) as discount_cents,
      sum(calculated_total_cents) as calculated_total_cents,
      sum(paid_online_cents) as paid_online_cents,
      sum(paid_manual_cents) as paid_manual_cents,
      sum(refunded_cents) as refunded_cents,
      sum(balance_due_cents) as balance_due_cents
    from selected
    group by exhibitor_id,currency
  ), section_totals as (
    select b.exhibitor_id,b.currency,s->>'section_id' as section_id,
      min(s->>'kind') as kind,min(s->>'letter') as letter,min(s->>'label') as label,
      sum((s->>'entry_count')::int) as entry_count,
      sum((s->>'fur_count')::int) as fur_count,
      sum(coalesce(s->>'entries_subtotal_cents',s->>'entry_fee_subtotal_cents')::int) as entry_fee_subtotal_cents,
      sum(coalesce(s->>'fur_subtotal_cents',s->>'fur_fee_subtotal_cents')::int) as fur_fee_subtotal_cents,
      sum(coalesce(s->>'show_fee_cents',s->>'show_fee_subtotal_cents')::int) as show_fee_subtotal_cents
    from selected b
    cross join lateral jsonb_array_elements(
      case when jsonb_typeof(b.section_breakdown)='array' then b.section_breakdown else '[]'::jsonb end
    ) s
    group by b.exhibitor_id,b.currency,s->>'section_id'
  ), sections as (
    select s.exhibitor_id,s.currency,jsonb_agg(to_jsonb(s)-'exhibitor_id'-'currency'
      order by s.kind,s.letter,s.section_id) as section_breakdown
    from section_totals s group by s.exhibitor_id,s.currency
  )
  select to_jsonb(t)||jsonb_build_object(
    'exhibitor_user_id',ex.owner_user_id,
    'exhibitor_name',coalesce(nullif(btrim(ex.showing_name),''),nullif(btrim(ex.display_name),''),
      nullif(btrim(concat_ws(' ',ex.first_name,ex.last_name)),''),'Exhibitor'),
    'exhibitor_type',ex.type,'phone',ex.phone,'email',ex.email,
    'address_line1',ex.address_line1,'address_line2',ex.address_line2,
    'city',ex.city,'state',ex.state,'zip',ex.zip,'arba_number',ex.arba_number,
    'payment_status',case when t.balance_due_cents<=0 then 'paid'
      when coalesce(t.paid_online_cents,0)+coalesce(t.paid_manual_cents,0)>coalesce(t.refunded_cents,0)
      then 'partial' else 'unpaid' end,
    'section_breakdown',coalesce(s.section_breakdown,'[]'::jsonb)
  )
  from totals t join public.exhibitors ex on ex.id=t.exhibitor_id
  left join sections s on s.exhibitor_id=t.exhibitor_id and s.currency is not distinct from t.currency
  order by t.exhibitor_id,t.currency;
end;
$$;
revoke all on function public.report_current_show_balances(uuid) from public,anon;
grant execute on function public.report_current_show_balances(uuid) to authenticated,service_role;
notify pgrst,'reload schema';
