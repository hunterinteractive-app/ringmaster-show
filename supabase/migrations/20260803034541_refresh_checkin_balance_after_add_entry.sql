create or replace function public.get_exhibitor_checkin_payment_status(p_session_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.show_checkin_sessions%rowtype; v_due integer; v_currency text; v_status text; v_online boolean;
begin
 select * into s from public.show_checkin_sessions where session_token_hash=encode(extensions.digest(btrim(coalesce(p_session_token,'')),'sha256'),'hex') and revoked_at is null and expires_at>now();
 if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode='42501'; end if;
 select coalesce(sum(b.balance_due_cents),0)::integer, min(lower(b.currency)), case when coalesce(sum(b.balance_due_cents),0)<=0 then 'paid' else 'unpaid' end
 into v_due,v_currency,v_status
 from public.show_exhibitor_balances b join public.entry_carts c on c.id=b.entry_cart_id
 where b.show_id=s.show_id and b.exhibitor_id=s.exhibitor_id and b.source='cart' and c.status='active';
 if v_currency is null then
   select coalesce(sum(b.balance_due_cents),0)::integer,min(lower(b.currency)),case when coalesce(sum(b.balance_due_cents),0)<=0 then 'paid' else 'unpaid' end into v_due,v_currency,v_status
   from public.show_exhibitor_balances b where b.show_id=s.show_id and b.exhibitor_id=s.exhibitor_id and b.source='entries';
 end if;
 select exists(select 1 from public.shows sh join public.show_payment_settings ps on ps.show_id=sh.id join public.show_payment_account_links l on l.show_id=sh.id and l.provider='stripe' where sh.id=s.show_id and sh.payment_timing_mode in ('online_only','online_or_at_show') and coalesce(ps.stripe_enabled,false) and coalesce(l.charges_enabled,false) and coalesce(l.account_status,'')='ready') into v_online;
 return jsonb_build_object('balance_due_cents',coalesce(v_due,0),'currency',coalesce(v_currency,'usd'),'payment_status',coalesce(v_status,'paid'),'online_payment_available',v_online);
end; $$;
revoke all on function public.get_exhibitor_checkin_payment_status(text) from public;
grant execute on function public.get_exhibitor_checkin_payment_status(text) to anon,authenticated,service_role;
