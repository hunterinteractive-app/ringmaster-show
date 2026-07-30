update public.sweepstakes_portal_assignments assignment
set can_manage_points = true,
    updated_at = now()
from public.sweepstakes_portal_clubs club
join public.show_sanctions sanction
  on club.normalized_name = lower(btrim(sanction.club_name))
where assignment.portal_club_id = club.id
  and assignment.normalized_email = lower(btrim(sanction.sweepstakes_email))
  and assignment.is_active
  and nullif(btrim(sanction.sweepstakes_email), '') is not null;

create or replace function public.sync_sweepstakes_portal_assignment_from_sanction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare v_portal_club_id uuid;
begin
  if nullif(btrim(new.sweepstakes_email), '') is null then return new; end if;
  select club.id into v_portal_club_id from public.sweepstakes_portal_clubs club
  where club.normalized_name = lower(btrim(new.club_name)) limit 1;
  if v_portal_club_id is not null then
    insert into public.sweepstakes_portal_assignments (portal_club_id, recipient_email, is_active, can_manage_points)
    values (v_portal_club_id, btrim(new.sweepstakes_email), true, true)
    on conflict (portal_club_id, normalized_email)
    do update set recipient_email = excluded.recipient_email, is_active = true, can_manage_points = true, updated_at = now();
  end if;
  return new;
end;
$function$;

revoke all on function public.sync_sweepstakes_portal_assignment_from_sanction() from public;
