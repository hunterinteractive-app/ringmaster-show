-- Let authorized secretaries limit the Canada Special to one or more show
-- letters. An empty array intentionally means every letter so existing shows
-- retain their current pricing until the setting is explicitly saved.

alter table public.show_fee_settings
  add column if not exists canada_special_show_letters text[] not null
    default '{}'::text[];

comment on column public.show_fee_settings.canada_special_show_letters is
  'Show letters eligible for Canada Special. Empty means every show letter.';

create or replace function public.enforce_canada_special_discount_access()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_changed boolean;
begin
  if tg_op = 'INSERT' then
    v_changed :=
      new.canada_special_discount_enabled
      or new.canada_special_discount_type <> 'amount'
      or new.canada_special_discount_value <> 0
      or new.canada_special_discount_scope <> 'both'
      or cardinality(new.canada_special_show_letters) > 0;
  else
    v_changed :=
      new.canada_special_discount_enabled is distinct from old.canada_special_discount_enabled
      or new.canada_special_discount_type is distinct from old.canada_special_discount_type
      or new.canada_special_discount_value is distinct from old.canada_special_discount_value
      or new.canada_special_discount_scope is distinct from old.canada_special_discount_scope
      or new.canada_special_show_letters is distinct from old.canada_special_show_letters;
  end if;

  if not v_changed then
    return new;
  end if;

  if current_user in ('postgres', 'service_role')
     or coalesce(auth.jwt() ->> 'role', '') = 'service_role'
     or public.is_super_admin((select auth.uid())) then
    return new;
  end if;

  if not exists (
    select 1
    from public.secretary_feature_access access
    where access.feature_key = 'canada_special_discount'
      and access.user_id = (select auth.uid())
  ) then
    raise exception 'Canada Special is not enabled for this secretary account'
      using errcode = '42501';
  end if;

  return new;
end;
$$;

revoke all on function public.enforce_canada_special_discount_access()
  from public, anon, authenticated;

create or replace function public.calculate_entry_cart_balance_internal(
  p_cart_id uuid
)
returns setof public.show_exhibitor_balances
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_show_id uuid;
  v_enabled boolean := false;
  v_type text := 'amount';
  v_value numeric := 0;
  v_scope text := 'both';
  v_show_letters text[] := '{}'::text[];
begin
  perform 1
  from public.calculate_entry_cart_balance_without_canada_special(p_cart_id);

  select c.show_id
  into v_show_id
  from public.entry_carts c
  where c.id = p_cart_id;

  select
    coalesce(sfs.canada_special_discount_enabled, false),
    lower(coalesce(sfs.canada_special_discount_type, 'amount')),
    greatest(coalesce(sfs.canada_special_discount_value, 0), 0),
    lower(coalesce(sfs.canada_special_discount_scope, 'both')),
    coalesce(sfs.canada_special_show_letters, '{}'::text[])
  into v_enabled, v_type, v_value, v_scope, v_show_letters
  from public.show_fee_settings sfs
  where sfs.show_id = v_show_id;

  if coalesce(v_enabled, false) then
    with canada_discount_by_exhibitor as (
      select
        eci.exhibitor_id,
        round(
          sum(
            least(
              coalesce(sffs.fee_per_entry, 0),
              greatest(
                case
                  when v_type = 'fixed_rate' then
                    coalesce(sffs.fee_per_entry, 0) - v_value
                  when v_type = 'percent' then
                    coalesce(sffs.fee_per_entry, 0)
                    * case when v_value <= 1 then v_value else v_value / 100 end
                  when v_type = 'amount' then v_value
                  else 0
                end,
                0
              )
            )
          ) * 100
        )::integer as special_discount_cents
      from public.entry_cart_items eci
      join public.exhibitors exhibitor
        on exhibitor.id = eci.exhibitor_id
      join public.show_sections section
        on section.id = eci.section_id
       and section.show_id = v_show_id
      left join public.show_section_fee_settings sffs
        on sffs.section_id = eci.section_id
      where eci.cart_id = p_cart_id
        and not coalesce(eci.is_fur, false)
        and public.is_canadian_exhibitor_address(
          exhibitor.state,
          exhibitor.zip
        )
        and (
          v_scope = 'both'
          or lower(section.kind::text) = v_scope
        )
        and (
          cardinality(v_show_letters) = 0
          or exists (
            select 1
            from unnest(v_show_letters) as selected_letter
            where upper(btrim(selected_letter)) = upper(btrim(section.letter))
          )
        )
      group by eci.exhibitor_id
    ), chosen_discounts as (
      select
        balance.id,
        balance.discount_cents as volume_discount_cents,
        greatest(
          balance.discount_cents,
          canada.special_discount_cents
        )::integer as chosen_discount_cents,
        canada.special_discount_cents
      from public.show_exhibitor_balances balance
      join canada_discount_by_exhibitor canada
        on canada.exhibitor_id = balance.exhibitor_id
      where balance.entry_cart_id = p_cart_id
        and balance.source = 'cart'
    )
    update public.show_exhibitor_balances balance
    set
      discount_cents = chosen.chosen_discount_cents,
      calculated_total_cents = greatest(
        balance.subtotal_before_discount_cents - chosen.chosen_discount_cents,
        0
      ),
      balance_due_cents = greatest(
        balance.subtotal_before_discount_cents
          - chosen.chosen_discount_cents
          - balance.paid_online_cents
          - balance.paid_manual_cents
          + balance.refunded_cents,
        0
      ),
      payment_status = case
        when greatest(
          balance.subtotal_before_discount_cents
            - chosen.chosen_discount_cents
            - balance.paid_online_cents
            - balance.paid_manual_cents
            + balance.refunded_cents,
          0
        ) = 0 then 'paid'
        else 'unpaid'
      end,
      fee_snapshot = coalesce(balance.fee_snapshot, '{}'::jsonb)
        || jsonb_build_object(
          'discount_strategy', 'better_discount',
          'volume_discount_cents', chosen.volume_discount_cents,
          'special_discount_eligible', true,
          'special_discount_cents', chosen.special_discount_cents,
          'applied_discount', case
            when chosen.special_discount_cents > chosen.volume_discount_cents
              then 'special'
            when chosen.volume_discount_cents > 0 then 'volume'
            else 'none'
          end,
          'discount_cents', chosen.chosen_discount_cents,
          'calculated_total_cents', greatest(
            balance.subtotal_before_discount_cents
              - chosen.chosen_discount_cents,
            0
          )
        ),
      calculated_at = now(),
      updated_at = now()
    from chosen_discounts chosen
    where balance.id = chosen.id;
  end if;

  return query
  select balance.*
  from public.show_exhibitor_balances balance
  where balance.entry_cart_id = p_cart_id
    and balance.source = 'cart'
  order by balance.exhibitor_id;
end;
$$;

revoke all on function public.calculate_entry_cart_balance_internal(uuid)
  from public, anon, authenticated;
grant execute on function public.calculate_entry_cart_balance_internal(uuid)
  to service_role;
