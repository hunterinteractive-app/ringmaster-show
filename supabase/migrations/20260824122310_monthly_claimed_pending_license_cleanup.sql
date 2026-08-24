-- Claimed purchases have already been transferred to account_license_balances.
-- Keep only unclaimed rows here so this table remains an actionable queue.
create or replace function public.cleanup_claimed_pending_licenses(
  p_apply boolean default false
)
returns table (pending_license_id uuid)
language plpgsql
security invoker
set search_path = ''
as $function$
begin
  if not p_apply then
    return query
      select pending_license.id
      from public.pending_licenses as pending_license
      where pending_license.claimed_at is not null;
    return;
  end if;

  return query
    delete from public.pending_licenses as pending_license
    where pending_license.claimed_at is not null
    returning pending_license.id;
end;
$function$;

revoke all on function public.cleanup_claimed_pending_licenses(boolean)
  from public, anon, authenticated;

select cron.unschedule(jobid)
from cron.job
where jobname = 'monthly-claimed-pending-license-cleanup';

select cron.schedule(
  'monthly-claimed-pending-license-cleanup',
  '40 5 1 * *',
  $cron$select public.cleanup_claimed_pending_licenses(true);$cron$
);
