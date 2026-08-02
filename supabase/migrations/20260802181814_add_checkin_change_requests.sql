create table public.show_checkin_change_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  show_id uuid not null references public.shows(id) on delete cascade,
  exhibitor_id uuid not null references public.exhibitors(id) on delete cascade,
  entry_id uuid references public.entries(id) on delete set null,
  request_type text not null,
  requested_changes jsonb not null default '{}'::jsonb,
  exhibitor_note text,
  status text not null default 'submitted',
  reviewed_at timestamptz,
  reviewed_by_user_id uuid,
  review_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint show_checkin_change_requests_type_chk check (request_type in ('entry_edit','scratch_entry','add_entry')),
  constraint show_checkin_change_requests_status_chk check (status in ('submitted','pending_payment','pending_review','approved','denied','cancelled'))
);
create index show_checkin_change_requests_queue_idx on public.show_checkin_change_requests(show_id, status, created_at);
alter table public.show_checkin_change_requests enable row level security;
create policy "Managers read check-in change requests" on public.show_checkin_change_requests for select to authenticated using (public.user_can_manage_entries(show_id) or public.user_can_manage_show_settings(show_id));

create or replace function public.submit_exhibitor_checkin_change_request(
  p_session_token text, p_entry_id uuid, p_request_type text, p_requested_changes jsonb default '{}'::jsonb, p_note text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_session public.show_checkin_sessions%rowtype; v_id uuid;
begin
  select * into v_session from public.show_checkin_sessions where session_token_hash = encode(extensions.digest(btrim(coalesce(p_session_token,'')), 'sha256'),'hex') and revoked_at is null and expires_at > now() for update;
  if not found then raise exception 'Your check-in session has expired. Please verify again.' using errcode = '42501'; end if;
  if p_request_type not in ('entry_edit','scratch_entry','add_entry') then raise exception 'Invalid change request type'; end if;
  if p_entry_id is not null and not exists (select 1 from public.entries e where e.id=p_entry_id and e.show_id=v_session.show_id and e.exhibitor_id=v_session.exhibitor_id) then raise exception 'Entry not found'; end if;
  insert into public.show_checkin_change_requests(show_id, exhibitor_id, entry_id, request_type, requested_changes, exhibitor_note)
  values(v_session.show_id,v_session.exhibitor_id,p_entry_id,p_request_type,coalesce(p_requested_changes,'{}'::jsonb),nullif(btrim(coalesce(p_note,'')),'')) returning id into v_id;
  insert into public.show_checkin_audit_events(show_id,exhibitor_id,event_type,actor_type,session_id,details)
  values(v_session.show_id,v_session.exhibitor_id,'change_request_submitted','exhibitor_portal',v_session.id,jsonb_build_object('change_request_id',v_id,'entry_id',p_entry_id,'request_type',p_request_type));
  return jsonb_build_object('id',v_id,'status','submitted');
end; $$;
revoke all on function public.submit_exhibitor_checkin_change_request(text,uuid,text,jsonb,text) from public;
grant execute on function public.submit_exhibitor_checkin_change_request(text,uuid,text,jsonb,text) to anon,authenticated,service_role;
