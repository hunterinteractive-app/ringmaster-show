create function public.sync_sweepstakes_portal_assignment_from_sanction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_portal_club_id uuid;
begin
  if nullif(btrim(new.sweepstakes_email), '') is null then
    return new;
  end if;

  select club.id into v_portal_club_id
  from public.sweepstakes_portal_clubs club
  where club.normalized_name = lower(btrim(new.club_name))
  limit 1;

  if v_portal_club_id is not null then
    insert into public.sweepstakes_portal_assignments (portal_club_id, recipient_email, is_active)
    values (v_portal_club_id, btrim(new.sweepstakes_email), true)
    on conflict (portal_club_id, normalized_email)
    do update set recipient_email = excluded.recipient_email, is_active = true, updated_at = now();
  end if;
  return new;
end;
$function$;

revoke all on function public.sync_sweepstakes_portal_assignment_from_sanction() from public;

drop trigger if exists sync_sweepstakes_portal_assignment_from_sanction on public.show_sanctions;
create trigger sync_sweepstakes_portal_assignment_from_sanction
after insert or update of sweepstakes_email, club_name on public.show_sanctions
for each row execute function public.sync_sweepstakes_portal_assignment_from_sanction();
