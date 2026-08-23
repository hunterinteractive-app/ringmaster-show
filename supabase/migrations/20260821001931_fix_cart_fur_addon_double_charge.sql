-- Fur/Wool rows are separate add-ons. They must not be charged at both the
-- regular entry fee and the Fur/Wool fee when a cart is quoted for checkout.
do $$
declare
  v_definition text;
begin
  select pg_get_functiondef(
    'public.calculate_entry_cart_balance_internal(uuid)'::regprocedure
  )
  into v_definition;

  -- A production hotfix may already have applied the same change before this
  -- migration is recorded in the migration history.  Treat that exact,
  -- already-correct definition as a successful no-op; retain the guard for
  -- genuinely unknown function versions.
  if position('count(*)::integer as entry_count' in v_definition) = 0 then
    if position(
      'count(*) filter (where not pi.is_fur)::integer as entry_count'
      in v_definition
    ) > 0 then
      raise notice 'calculate_entry_cart_balance_internal already excludes Fur/Wool rows';
      return;
    end if;

    raise exception
      'calculate_entry_cart_balance_internal no longer matches the expected definition';
  end if;

  -- Applies to both per-section and per-exhibitor regular-entry totals.
  v_definition := replace(
    v_definition,
    'count(*)::integer as entry_count',
    'count(*) filter (where not pi.is_fur)::integer as entry_count'
  );
  v_definition := replace(
    v_definition,
    E'round(\n        sum(pi.fee_per_entry) * 100\n      )::integer as entries_subtotal_cents',
    E'round(\n        sum(case when not pi.is_fur then pi.fee_per_entry else 0 end) * 100\n      )::integer as entries_subtotal_cents'
  );

  -- Fur/Wool add-ons do not participate in entry-count based discounts.
  v_definition := replace(
    v_definition,
    E'count(*)::integer as eligible_entry_count\n\n    from priced_items pi\n\n    where pi.eligible_for_discount = true',
    E'count(*) filter (where not pi.is_fur)::integer as eligible_entry_count\n\n    from priced_items pi\n\n    where pi.eligible_for_discount = true\n      and not pi.is_fur'
  );
  v_definition := replace(
    v_definition,
    E'where pi.eligible_for_discount\n      )::integer as eligible_entry_count',
    E'where pi.eligible_for_discount\n          and not pi.is_fur\n      )::integer as eligible_entry_count'
  );
  v_definition := replace(
    v_definition,
    E'where pi.eligible_for_discount = true\n  ),\n\n  discount_eligible_items',
    E'where pi.eligible_for_discount = true\n      and not pi.is_fur\n  ),\n\n  discount_eligible_items'
  );

  execute v_definition;
end;
$$;
