create policy "Show managers can insert payment accounts"
on public.show_payment_accounts
for insert
to authenticated
with check (public.user_can_manage_show_settings(show_id));

create policy "Show managers can update payment accounts"
on public.show_payment_accounts
for update
to authenticated
using (public.user_can_manage_show_settings(show_id))
with check (public.user_can_manage_show_settings(show_id));

create policy "Show managers can insert payment account links"
on public.show_payment_account_links
for insert
to authenticated
with check (public.user_can_manage_show_settings(show_id));

create policy "Show managers can update payment account links"
on public.show_payment_account_links
for update
to authenticated
using (public.user_can_manage_show_settings(show_id))
with check (public.user_can_manage_show_settings(show_id));
