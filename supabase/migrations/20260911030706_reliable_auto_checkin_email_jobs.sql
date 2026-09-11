-- Service-only leases and durable delivery receipts for scheduled check-in mail.
create table public.auto_checkin_email_runs (
 show_id uuid primary key references public.shows(id) on delete cascade,
 lease_until timestamptz not null default '-infinity',
 lease_token uuid,
 updated_at timestamptz not null default now()
);
create table public.auto_checkin_email_deliveries (
 show_id uuid not null references public.shows(id) on delete cascade,
 exhibitor_id uuid not null references public.exhibitors(id),
 status text not null check (status in ('pending','sent','skipped')),
 payload jsonb,
 provider_message_id text,
 error text,
 first_attempt_at timestamptz not null default now(),
 sent_at timestamptz,
 primary key (show_id, exhibitor_id)
);
alter table public.auto_checkin_email_runs enable row level security;
alter table public.auto_checkin_email_deliveries enable row level security;
revoke all on public.auto_checkin_email_runs, public.auto_checkin_email_deliveries from public,anon,authenticated;
grant all on public.auto_checkin_email_runs, public.auto_checkin_email_deliveries to service_role;
create function public.claim_auto_checkin_email_run(p_show_id uuid,p_token uuid)
returns boolean language plpgsql security invoker set search_path='' as $$
begin
 insert into public.auto_checkin_email_runs(show_id,lease_until,lease_token)
 values(p_show_id,now()+interval '5 minutes',p_token)
 on conflict(show_id) do update set lease_until=excluded.lease_until,lease_token=excluded.lease_token,updated_at=now()
 where public.auto_checkin_email_runs.lease_until < now();
 return found;
end; $$;
revoke all on function public.claim_auto_checkin_email_run(uuid,uuid) from public,anon,authenticated;
grant execute on function public.claim_auto_checkin_email_run(uuid,uuid) to service_role;
-- Keep credentials in the existing job; never copy them into migrations/logs.
do $$ declare j record; c text; begin
 for j in select jobid,command from cron.job where jobname='auto-email-checkin-sheets' loop
 c := replace(j.command,'body :=', 'timeout_milliseconds := 60000, body :=');
 perform cron.alter_job(j.jobid,schedule := '* * * * *',command := c);
 end loop;
end $$;
notify pgrst,'reload schema';
