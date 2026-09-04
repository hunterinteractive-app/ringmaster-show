-- Canada Special is an internal, secretary-scoped pricing rule.  Eligible
-- exhibitors only see the resulting generic discount at checkout.

create table if not exists public.secretary_feature_access (
  feature_key text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (feature_key, user_id)
);

create index if not exists secretary_feature_access_user_id_idx
  on public.secretary_feature_access (user_id);

comment on table public.secretary_feature_access is
  'Allowlist for secretary-only features that may expand to more users.';

alter table public.secretary_feature_access enable row level security;

revoke all on table public.secretary_feature_access from public, anon;
revoke all on table public.secretary_feature_access from authenticated;
grant select on table public.secretary_feature_access to authenticated;
grant all on table public.secretary_feature_access to service_role;

drop policy if exists "Users can view their own feature access"
  on public.secretary_feature_access;
create policy "Users can view their own feature access"
  on public.secretary_feature_access
  for select
  to authenticated
  using ((select auth.uid()) = user_id);

insert into public.secretary_feature_access (feature_key, user_id)
select
  'canada_special_discount',
  '8bbd00a2-5659-4828-a686-009f7a58f085'::uuid
where exists (
  select 1
  from auth.users
  where id = '8bbd00a2-5659-4828-a686-009f7a58f085'::uuid
)
on conflict (feature_key, user_id) do nothing;

alter table public.show_fee_settings
  add column if not exists canada_special_discount_enabled boolean not null default false,
  add column if not exists canada_special_discount_type text not null default 'amount',
  add column if not exists canada_special_discount_value numeric not null default 0,
  add column if not exists canada_special_discount_scope text not null default 'both';

alter table public.show_fee_settings
  drop constraint if exists show_fee_settings_canada_special_type_check,
  add constraint show_fee_settings_canada_special_type_check
    check (canada_special_discount_type in ('fixed_rate', 'amount', 'percent')),
  drop constraint if exists show_fee_settings_canada_special_value_check,
  add constraint show_fee_settings_canada_special_value_check
    check (
      canada_special_discount_value >= 0
      and (
        canada_special_discount_type <> 'percent'
        or canada_special_discount_value <= 100
      )
    ),
  drop constraint if exists show_fee_settings_canada_special_scope_check,
  add constraint show_fee_settings_canada_special_scope_check
    check (canada_special_discount_scope in ('both', 'open', 'youth'));

comment on column public.show_fee_settings.canada_special_discount_enabled is
  'Internal Canada Special switch. The public checkout uses a generic Discount label.';

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
      or new.canada_special_discount_scope <> 'both';
  else
    v_changed :=
      new.canada_special_discount_enabled is distinct from old.canada_special_discount_enabled
      or new.canada_special_discount_type is distinct from old.canada_special_discount_type
      or new.canada_special_discount_value is distinct from old.canada_special_discount_value
      or new.canada_special_discount_scope is distinct from old.canada_special_discount_scope;
  end if;

  if not v_changed then
    return new;
  end if;

  -- Server jobs use service_role. Interactive changes require an allowlist row.
  if current_user in ('postgres', 'service_role')
     or coalesce(auth.jwt() ->> 'role', '') = 'service_role' then
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

drop trigger if exists enforce_canada_special_discount_access
  on public.show_fee_settings;
create trigger enforce_canada_special_discount_access
before insert or update on public.show_fee_settings
for each row execute function public.enforce_canada_special_discount_access();

revoke all on function public.enforce_canada_special_discount_access()
  from public, anon, authenticated;

create or replace function public.is_canadian_exhibitor_address(
  p_state_or_province text,
  p_postal_code text
)
returns boolean
language sql
immutable
parallel safe
set search_path = public, pg_temp
as $$
  select
    upper(regexp_replace(coalesce(p_state_or_province, ''), '[^A-Za-z]', '', 'g'))
      in (
        'AB', 'ALBERTA',
        'BC', 'BRITISHCOLUMBIA',
        'MB', 'MANITOBA',
        'NB', 'NEWBRUNSWICK',
        'NL', 'NEWFOUNDLAND', 'LABRADOR', 'NEWFOUNDLANDANDLABRADOR',
        'NS', 'NOVASCOTIA',
        'NT', 'NORTHWESTTERRITORIES',
        'NU', 'NUNAVUT',
        'ON', 'ONTARIO',
        'PE', 'PEI', 'PRINCEEDWARDISLAND',
        'PQ', 'QC', 'QUBEC', 'QUEBEC',
        'SK', 'SASKATCHEWAN',
        'YK', 'YT', 'YUKON'
      )
    or upper(regexp_replace(coalesce(p_postal_code, ''), '[^A-Za-z0-9]', '', 'g'))
      ~ '^[ABCEGHJ-NPRSTVXY][0-9][ABCEGHJ-NPRSTV-Z][0-9][ABCEGHJ-NPRSTV-Z][0-9]$';
$$;

revoke all on function public.is_canadian_exhibitor_address(text, text)
  from public, anon, authenticated;
grant execute on function public.is_canadian_exhibitor_address(text, text)
  to service_role;

-- Preserve the proven volume-discount calculator and wrap it with the
-- Canada Special comparison.  The public authorization wrapper continues to
-- call calculate_entry_cart_balance_internal(uuid), so payment quotes and
-- balance records use this logic automatically.
do $$
begin
  if to_regprocedure(
    'public.calculate_entry_cart_balance_without_canada_special(uuid)'
  ) is null then
    alter function public.calculate_entry_cart_balance_internal(uuid)
      rename to calculate_entry_cart_balance_without_canada_special;
  end if;
end;
$$;

revoke all on function
  public.calculate_entry_cart_balance_without_canada_special(uuid)
  from public, anon, authenticated;
grant execute on function
  public.calculate_entry_cart_balance_without_canada_special(uuid)
  to service_role;

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
begin
  -- This performs the existing calculation, authorization checks, and balance
  -- upsert before the two mutually-exclusive discounts are compared.
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
    lower(coalesce(sfs.canada_special_discount_scope, 'both'))
  into v_enabled, v_type, v_value, v_scope
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
