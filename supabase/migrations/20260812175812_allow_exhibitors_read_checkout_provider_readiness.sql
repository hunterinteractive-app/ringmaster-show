-- Exhibitors cannot read payment-account rows directly (they contain provider
-- connection metadata), but checkout needs the derived enabled/ready flags.
-- Run this narrow, public-show lookup as the function owner so RLS on
-- show_payment_account_links does not make every provider look unavailable.
create or replace function public.get_show_checkout_options(p_show_id uuid)
returns jsonb
language sql
security definer
set search_path = public, pg_temp
as $$
  select jsonb_build_object(
    'show_id', s.id,
    'payment_timing_mode', s.payment_timing_mode,
    'allow_online', s.payment_timing_mode in ('online_only', 'online_or_at_show'),
    'allow_at_show', s.payment_timing_mode in ('pay_at_show_only', 'online_or_at_show'),
    'require_online_payment', s.payment_timing_mode = 'online_only',
    'default_online_provider', ps.default_online_provider,
    'providers', jsonb_build_array(
      jsonb_build_object('provider', 'stripe', 'enabled', coalesce(ps.stripe_enabled, false),
        'ready', coalesce(exists (
          select 1 from public.show_payment_account_links l
          where l.show_id = s.id and l.provider = 'stripe'
            and coalesce(l.charges_enabled, false)
            and coalesce(l.account_status, '') = 'ready'
        ), false)),
      jsonb_build_object('provider', 'square', 'enabled', coalesce(ps.square_enabled, false),
        'ready', coalesce(exists (
          select 1 from public.show_payment_account_links l
          where l.show_id = s.id and l.provider = 'square'
            and l.provider_account_id is not null
            and l.provider_location_id is not null
            and coalesce(l.status, '') = 'ready'
        ), false)),
      jsonb_build_object('provider', 'paypal', 'enabled', coalesce(ps.paypal_enabled, false),
        'ready', coalesce(exists (
          select 1 from public.show_payment_account_links l
          where l.show_id = s.id and l.provider = 'paypal'
            and l.provider_account_id is not null
            and coalesce(l.status, '') in ('ready', 'connected', 'active')
        ), false))
    )
  )
  from public.shows s
  left join public.show_payment_settings ps on ps.show_id = s.id
  where s.id = p_show_id;
$$;

revoke all on function public.get_show_checkout_options(uuid) from public;
grant execute on function public.get_show_checkout_options(uuid) to authenticated;
