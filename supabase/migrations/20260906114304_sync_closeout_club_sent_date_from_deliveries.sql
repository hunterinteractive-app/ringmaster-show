-- Keep the ARBA closeout date in sync regardless of which report-email UI
-- initiated a successful national breed club send.
create or replace function public.sync_closeout_club_sent_date_from_delivery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_metadata jsonb := '{}'::jsonb;
  v_is_club_delivery boolean := false;
begin
  if new.sent_at is null then
    return new;
  end if;

  select coalesce(a.metadata, '{}'::jsonb)
  into v_metadata
  from public.show_report_artifacts a
  where a.id = new.artifact_id;

  v_is_club_delivery :=
    lower(coalesce(v_metadata ->> 'delivery_type', '')) = 'club'
    or (
      new.report_name in ('sweepstakes_report', 'breed_results_detail_report')
      and nullif(btrim(coalesce(v_metadata ->> 'sweepstakes_email', '')), '')
        is not null
    );

  if not v_is_club_delivery then
    return new;
  end if;

  insert into public.show_closeout_state (show_id, club_reports_sent_at)
  values (new.show_id, new.sent_at)
  on conflict (show_id) do update
  set club_reports_sent_at = case
        when show_closeout_state.club_reports_sent_at is null
          then excluded.club_reports_sent_at
        else least(
          show_closeout_state.club_reports_sent_at,
          excluded.club_reports_sent_at
        )
      end,
      updated_at = now();

  return new;
end;
$$;

drop trigger if exists sync_closeout_club_sent_date_from_delivery
  on public.show_email_deliveries;

create trigger sync_closeout_club_sent_date_from_delivery
after insert or update of sent_at on public.show_email_deliveries
for each row
execute function public.sync_closeout_club_sent_date_from_delivery();

-- Repair historical closeouts, including sends made by the individual
-- "Email This Show" and "Email All Shows" actions.
with first_club_send as (
  select
    d.show_id,
    min(d.sent_at) as sent_at
  from public.show_email_deliveries d
  join public.show_report_artifacts a on a.id = d.artifact_id
  where d.sent_at is not null
    and (
      lower(coalesce(a.metadata ->> 'delivery_type', '')) = 'club'
      or (
        d.report_name in (
          'sweepstakes_report',
          'breed_results_detail_report'
        )
        and nullif(
          btrim(coalesce(a.metadata ->> 'sweepstakes_email', '')),
          ''
        ) is not null
      )
    )
  group by d.show_id
)
insert into public.show_closeout_state (show_id, club_reports_sent_at)
select show_id, sent_at
from first_club_send
on conflict (show_id) do update
set club_reports_sent_at = case
      when show_closeout_state.club_reports_sent_at is null
        then excluded.club_reports_sent_at
      else least(
        show_closeout_state.club_reports_sent_at,
        excluded.club_reports_sent_at
      )
    end,
    updated_at = now();
