alter table public.show_checkin_records
  add column if not exists receipt_sent_at timestamptz,
  add column if not exists receipt_provider_message_id text;

create or replace function public.get_checkin_receipt_context(p_session_token text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.show_checkin_sessions%rowtype; r public.show_checkin_records%rowtype; e public.exhibitors%rowtype; sh public.shows%rowtype;
begin
 select * into s from public.show_checkin_sessions where session_token_hash=encode(extensions.digest(btrim(coalesce(p_session_token,'')),'sha256'),'hex') and revoked_at is null and expires_at>now();
 if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode='42501'; end if;
 select * into r from public.show_checkin_records where show_id=s.show_id and exhibitor_id=s.exhibitor_id;
 if not found or r.status <> 'completed' or r.receipt_preference <> 'email_receipt' or r.receipt_sent_at is not null then raise exception 'Receipt email is not available'; end if;
 select * into e from public.exhibitors where id=s.exhibitor_id; select * into sh from public.shows where id=s.show_id;
 return jsonb_build_object('record_id',r.id,'email',e.email,'show_name',sh.name,'exhibitor_name',coalesce(nullif(e.display_name,''),trim(coalesce(e.first_name,'')||' '||coalesce(e.last_name,''))),'checked_in_at',r.completed_at);
end; $$;
revoke all on function public.get_checkin_receipt_context(text) from public;
grant execute on function public.get_checkin_receipt_context(text) to service_role;
