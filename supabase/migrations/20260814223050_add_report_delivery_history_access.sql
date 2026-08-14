-- Delivery history is read from show_email_deliveries by authorized show
-- managers.  These indexes keep the popup and Resend webhook updates quick
-- without changing the existing audit data or its RLS policy.
do $$
begin
  if to_regclass('public.show_email_deliveries') is not null then
    execute 'create index if not exists show_email_deliveries_show_sent_idx
      on public.show_email_deliveries (show_id, sent_at desc, created_at desc)';
    execute 'create index if not exists show_email_deliveries_provider_message_idx
      on public.show_email_deliveries (provider_message_id)
      where provider_message_id is not null';
  end if;
end;
$$;
