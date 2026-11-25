create schema if not exists cart_review_private;
revoke all on schema cart_review_private from public, anon, authenticated;

create table cart_review_private.confirmed_matches (
  cart_id uuid not null references public.entry_carts(id) on delete cascade,
  match_key text not null,
  confirmed_by uuid not null,
  confirmed_at timestamptz not null default now(),
  primary key (cart_id, match_key)
);
alter table cart_review_private.confirmed_matches enable row level security;
revoke all on cart_review_private.confirmed_matches from public, anon, authenticated;

create function cart_review_private.normalized(p_text text)
returns text language sql immutable set search_path='' as $$
  select lower(regexp_replace(btrim(coalesce(p_text,'')), '[[:space:]]+', ' ', 'g'));
$$;

create function cart_review_private.animal_signature(
  p_species text, p_tattoo text, p_breed text, p_variety text,
  p_sex text, p_class text, p_is_fur boolean, p_fur_variety text
) returns text[] language sql immutable set search_path='' as $$
  select array[
    cart_review_private.normalized(p_species),
    regexp_replace(cart_review_private.normalized(p_tattoo), '[[:space:]]', '', 'g'),
    cart_review_private.normalized(p_breed),
    cart_review_private.normalized(case when p_is_fur then p_fur_variety else p_variety end),
    cart_review_private.normalized(case when not p_is_fur then p_sex end),
    cart_review_private.normalized(case when not p_is_fur then p_class end)
  ];
$$;

create function cart_review_private.matches(p_cart_id uuid)
returns table (
  match_key text, item_id uuid, other_id uuid, already_submitted boolean,
  section_id uuid, tattoo text, exhibitor_name text, other_exhibitor_name text,
  already_same_animal boolean, confirmed boolean
)
language sql stable set search_path='' as $$
  with cart as (
    select id,show_id,user_id from public.entry_carts
    where id=p_cart_id and status='active'
  ), draft as materialized (
    select i.id,i.section_id,i.animal_id,i.exhibitor_id,i.tattoo,
      coalesce(i.is_fur,false) as fur,
      cart_review_private.animal_signature(i.species::text,i.tattoo,i.breed,i.variety,
        i.sex,i.class_name,coalesce(i.is_fur,false),i.fur_variety) as signature
    from cart c join public.entry_cart_items i on i.cart_id=c.id
    where not coalesce(i.is_show_addon_carrier,false)
      and not coalesce(i.is_checkin_fee_carrier,false)
      and not coalesce(i.is_exhibitor_fee_carrier,false) and i.meat_pen_id is null
  ), other_lines as (
    select d.*,false as submitted from draft d
    union all
    select e.id,e.section_id,e.animal_id,e.exhibitor_id,e.tattoo,
      coalesce(e.is_fur,false),
      cart_review_private.animal_signature(e.species::text,e.tattoo,e.breed,e.variety,
        e.sex,e.class_name,coalesce(e.is_fur,false),e.fur_variety),true
    from cart c join public.exhibitors x on x.owner_user_id=c.user_id
    join public.entries e on e.exhibitor_id=x.id and e.show_id=c.show_id
    where e.scratched_at is null and e.meat_pen_id is null
      and lower(coalesce(e.status,'')) not in ('scratched','deleted','removed','withdrawn','cancelled','canceled')
      and exists(select 1 from draft d where d.section_id=e.section_id)
  ), pairs as (
    select md5(jsonb_build_array(d.id,o.id,o.submitted,d.section_id,d.fur,
      d.exhibitor_id,o.exhibitor_id,d.animal_id,o.animal_id,d.signature,o.signature)::text) as key,
      d.id,o.id as other_id,o.submitted,d.section_id,d.tattoo,
      coalesce(nullif(x.showing_name,''),x.display_name,'Exhibitor') as exhibitor,
      coalesce(nullif(y.showing_name,''),y.display_name,'Exhibitor') as other_exhibitor,
      coalesce(d.animal_id=o.animal_id,false) as same_animal
    from draft d join other_lines o on o.section_id=d.section_id and o.fur=d.fur
      and (o.submitted or d.id<o.id)
      and (d.animal_id=o.animal_id or (d.signature[2]<>'' and d.signature=o.signature))
    left join public.exhibitors x on x.id=d.exhibitor_id
    left join public.exhibitors y on y.id=o.exhibitor_id
  )
  select p.key,p.id,p.other_id,p.submitted,p.section_id,p.tattoo,p.exhibitor,p.other_exhibitor,
    p.same_animal,(ack.match_key is not null)
  from pairs p left join cart_review_private.confirmed_matches ack
    on ack.cart_id=p_cart_id and ack.match_key=p.key and not p.same_animal;
$$;

-- Called with the cart row locked, before creating a payment attempt or entries.
-- Paid webhooks continue to honor the quote that passed these checks.
create function cart_review_private.validate_cart(p_cart_id uuid)
returns void language plpgsql set search_path='' as $$
declare
  repeated_animal boolean;
  unconfirmed_match boolean;
begin
  select bool_or(already_same_animal),bool_or(not confirmed)
  into repeated_animal,unconfirmed_match from cart_review_private.matches(p_cart_id);
  if repeated_animal then
    raise exception 'The same animal is already entered in this section. Remove the extra line from your cart.';
  end if;
  if unconfirmed_match then
    raise exception 'Review the possible duplicate entries in your cart before submitting.';
  end if;
end;
$$;

create function cart_review_private.review(p_cart_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.entry_carts%rowtype;
begin
  select * into c from public.entry_carts where id=p_cart_id;
  if not found or auth.uid() is null or not household_private.has_access(c.user_id) then
    raise exception 'Cart not found' using errcode='42501';
  end if;

  return (
    with exhibitors as (
      select id,coalesce(nullif(showing_name,''),display_name,'Exhibitor') as name
      from public.exhibitors where owner_user_id=c.user_id
    ), current_entries as (
      select e.id,e.exhibitor_id,x.name as exhibitor_name,e.section_id,e.tattoo,e.animal_name,
        e.breed,e.variety,e.sex,e.class_name,e.is_fur,e.fur_variety,e.meat_pen_id,e.meat_pen_tattoos
      from exhibitors x join public.entries e on e.exhibitor_id=x.id and e.show_id=c.show_id
      where e.scratched_at is null
        and lower(coalesce(e.status,'')) not in ('scratched','deleted','removed','withdrawn','cancelled','canceled')
    ), balance_parts as (
      select lower(b.currency) as currency,b.balance_due_cents as due_cents
      from exhibitors x join public.show_exhibitor_balances b on b.exhibitor_id=x.id and b.show_id=c.show_id
      where b.source='entries'
      union all
      select lower(b.currency),(part.value->>'balance_due_cents')::integer
      from public.entry_carts submitted join public.show_exhibitor_balances b
        on coalesce(b.entry_cart_id,b.cart_id)=submitted.id and b.source='cart'
      cross join lateral show_finances_private.cart_parts(to_jsonb(b)) part(value)
      join exhibitors x on x.id=(part.value->>'exhibitor_id')::uuid
      where submitted.show_id=c.show_id and submitted.user_id=c.user_id and submitted.status='submitted'
        and not exists (
          select 1 from public.show_exhibitor_balances authoritative
          where authoritative.show_id=c.show_id and authoritative.exhibitor_id=x.id and authoritative.source='entries'
        )
    ), current_balances as (
      select currency,sum(due_cents) as due_cents from balance_parts group by currency
    )
    select jsonb_build_object(
      'entries',coalesce((select jsonb_agg(e order by e.exhibitor_name,e.tattoo,e.section_id) from current_entries e),'[]'::jsonb),
      'balances',coalesce((select jsonb_agg(b order by b.currency) from current_balances b),'[]'::jsonb),
      'matches',coalesce((select jsonb_agg(m order by m.tattoo,m.match_key) from cart_review_private.matches(c.id) m),'[]'::jsonb)
    )
  );
end;
$$;

create function cart_review_private.confirm_match(p_cart_id uuid,p_match_key text)
returns void language plpgsql security definer set search_path='' as $$
declare c public.entry_carts%rowtype;
begin
  select * into c from public.entry_carts where id=p_cart_id for update;
  if not found or auth.uid() is null or not household_private.has_access(c.user_id) then
    raise exception 'Cart not found' using errcode='42501';
  end if;
  if c.status<>'active' or c.active_payment_session_id is not null
    or c.payment_status in ('pending','paid','refunded') then
    raise exception 'This cart is no longer editable.';
  end if;
  if not exists (
    select 1 from cart_review_private.matches(p_cart_id)
    where match_key=p_match_key and not already_same_animal
  ) then raise exception 'This match changed. Refresh your cart and check again.'; end if;

  insert into cart_review_private.confirmed_matches(cart_id,match_key,confirmed_by)
  values(p_cart_id,p_match_key,auth.uid()) on conflict do nothing;
end;
$$;

create function public.get_entry_cart_review(p_cart_id uuid)
returns jsonb language sql stable security invoker set search_path='' as $$
  select cart_review_private.review(p_cart_id);
$$;

create function public.confirm_distinct_cart_entry(p_cart_id uuid,p_match_key text)
returns void language sql security invoker set search_path='' as $$
  select cart_review_private.confirm_match(p_cart_id,p_match_key);
$$;

revoke all on all functions in schema cart_review_private from public,anon,authenticated;
grant usage on schema cart_review_private to authenticated;
grant execute on function cart_review_private.review(uuid),cart_review_private.confirm_match(uuid,text) to authenticated;
revoke all on function public.get_entry_cart_review(uuid),public.confirm_distinct_cart_entry(uuid,text) from public,anon;
grant execute on function public.get_entry_cart_review(uuid),public.confirm_distinct_cart_entry(uuid,text) to authenticated;

do $$
declare
  sig text;
  body text;
  anchor constant text := '  perform show_addons_private.validate_cart(p_cart_id);';
begin
  foreach sig in array array[
    'public.create_payment_quote_attempt(uuid,uuid,text,numeric,numeric,integer)',
    'public.commit_entry_cart_day_of(uuid)',
    'public.commit_free_entry_cart(uuid)'
  ] loop
    body:=pg_get_functiondef(sig::regprocedure);
    if (length(body)-length(replace(body,anchor,'')))/length(anchor)<>1 then
      raise exception 'Checkout guard anchor changed: %',sig;
    end if;
    execute replace(body,anchor,E'  perform cart_review_private.validate_cart(p_cart_id);\n'||anchor);
  end loop;
end;
$$;

-- A staff removal uses the original net charge, even when fees have since
-- changed. Existing scratch credits remain in the same ledger and are reused.
create function show_finances_private.capture_unpaid_staff_removal()
returns trigger language plpgsql security definer set search_path='' as $$
declare
  c public.entry_carts%rowtype;
  b public.show_exhibitor_balances%rowtype;
  i public.entry_cart_items%rowtype;
  quote_items jsonb;
  gross integer;
  discount integer;
begin
  if old.source_cart_id is null or old.source_cart_item_id is null
    or auth.uid() is null or not public.user_can_manage_entries(old.show_id) then return old; end if;

  select * into c from public.entry_carts where id=old.source_cart_id for update;
  if not found or c.status<>'submitted' then return old; end if;
  if c.active_payment_session_id is not null or c.payment_status='pending' then
    raise exception 'A payment is in progress. Finish or cancel it before removing this entry.';
  end if;
  if c.payment_status<>'unpaid' then return old; end if;

  select * into i from public.entry_cart_items where id=old.source_cart_item_id and cart_id=c.id;
  if not found then return old; end if;
  select * into b from public.show_exhibitor_balances
  where source='cart' and show_id=old.show_id and exhibitor_id=i.exhibitor_id
    and coalesce(entry_cart_id,cart_id)=c.id for update;
  if not found then return old; end if;

  -- Lock current balances in case a secretary is recording a payment at the
  -- same time. Cart-part allocations may have moved to another exhibitor.
  perform 1 from public.show_exhibitor_balances
    where show_id=old.show_id and source='entries' and exhibitor_id in (i.exhibitor_id,old.exhibitor_id)
    order by id for update;
  if coalesce(b.paid_online_cents,0)+coalesce(b.paid_manual_cents,0)+coalesce(b.refunded_cents,0)>0
    or exists (
      select 1 from public.show_exhibitor_balances a where a.show_id=old.show_id
        and a.exhibitor_id in (i.exhibitor_id,old.exhibitor_id) and a.source='entries'
        and coalesce(a.paid_online_cents,0)+coalesce(a.paid_manual_cents,0)+coalesce(a.refunded_cents,0)>0
    ) then return old; end if;

  select q.quote_items into quote_items from show_finances_private.cart_quote_corrections q where q.balance_id=b.id;
  if quote_items is not null and not exists (
    select 1 from jsonb_array_elements(quote_items) q where q->>'id'=i.id::text
  ) then return old; end if;

  with items as (
    select ci.id,ci.section_id,coalesce(ci.is_fur,false) as fur,
      row_number() over(partition by ci.section_id,coalesce(ci.is_fur,false) order by ci.id) as rn,
      count(*) over(partition by ci.section_id,coalesce(ci.is_fur,false)) as cnt
    from public.entry_cart_items ci where ci.cart_id=c.id and ci.exhibitor_id=i.exhibitor_id
      and not coalesce(ci.is_show_addon_carrier,false) and not coalesce(ci.is_checkin_fee_carrier,false)
      and not coalesce(ci.is_exhibitor_fee_carrier,false)
      and (quote_items is null or exists(select 1 from jsonb_array_elements(quote_items) q where q->>'id'=ci.id::text))
  ), amounts as (
    select items.id,
      show_finances_private.share(coalesce((s->>case when fur then 'fur_subtotal_cents' else 'entries_subtotal_cents' end)::integer,0),rn-1,1,cnt) as cents,
      not fur and coalesce((s->>'discount_scope_eligible')::boolean,true) as eligible,
      (s->>case when fur then 'fur_count' else 'entry_count' end)::integer=cnt as valid
    from items join jsonb_array_elements(b.section_breakdown) s on s->>'section_id'=items.section_id::text
  ), net as (
    select id,cents,valid,show_finances_private.share(coalesce(b.discount_cents,0),
      coalesce(sum(case when eligible then cents else 0 end) over(order by id rows between unbounded preceding and 1 preceding),0)::bigint,
      case when eligible then cents else 0 end,
      sum(case when eligible then cents else 0 end) over()) as discount
    from amounts
  )
  select net.cents,net.discount into gross,discount from net where id=i.id and valid;
  if gross is null or discount is null or discount>gross then
    raise exception 'The original charge could not be verified. Review the balance before removing this entry.';
  end if;

  -- Once the entry is deleted, cart_parts assigns the frozen item to the
  -- original exhibitor and section. Record the waiver against that same line.
  insert into show_finances_private.unpaid_scratch_lines(
    entry_id,balance_id,show_id,exhibitor_id,section_id,is_fur,gross_cents,discount_cents,scratched_at,actor_user_id
  ) values(old.id,b.id,old.show_id,i.exhibitor_id,i.section_id,coalesce(i.is_fur,false),gross,discount,now(),auth.uid())
  on conflict(entry_id) do update set
    active=true,balance_id=excluded.balance_id,exhibitor_id=excluded.exhibitor_id,
    section_id=excluded.section_id,is_fur=excluded.is_fur,gross_cents=excluded.gross_cents,
    discount_cents=excluded.discount_cents,updated_at=now(),actor_user_id=excluded.actor_user_id;
  return old;
end;
$$;

create function show_finances_private.refresh_removed_cart_balances()
returns trigger language plpgsql security definer set search_path='' as $$
declare r record;
begin
  for r in
    select distinct l.show_id,l.exhibitor_id from removed_entries e
    join show_finances_private.unpaid_scratch_lines l on l.entry_id=e.id and l.active
    where l.exhibitor_id is distinct from e.exhibitor_id
    order by l.show_id,l.exhibitor_id
  loop
    perform manual_entry_balances_private.refresh(r.show_id,r.exhibitor_id);
  end loop;
  return null;
end;
$$;

revoke all on function show_finances_private.capture_unpaid_staff_removal(),
  show_finances_private.refresh_removed_cart_balances() from public,anon,authenticated;
create trigger unpaid_staff_entry_removal before delete on public.entries
  for each row execute function show_finances_private.capture_unpaid_staff_removal();
create trigger z_refresh_removed_cart_balances after delete on public.entries
  referencing old table as removed_entries for each statement
  execute function show_finances_private.refresh_removed_cart_balances();
notify pgrst,'reload schema';
