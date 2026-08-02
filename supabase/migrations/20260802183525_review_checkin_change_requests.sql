create or replace function public.review_checkin_change_request(p_request_id uuid,p_approved boolean,p_review_note text default null) returns jsonb language plpgsql security definer set search_path='' as $$
declare r public.show_checkin_change_requests%rowtype; v_status text := case when p_approved then 'approved' else 'denied' end;
begin
 select * into r from public.show_checkin_change_requests where id=p_request_id for update;
 if not found then raise exception 'Change request not found'; end if;
 if not public.user_can_manage_entries(r.show_id) and not public.user_can_manage_show_settings(r.show_id) then raise exception 'Permission denied' using errcode='42501'; end if;
 if r.status not in ('submitted','pending_review') then raise exception 'This request has already been reviewed'; end if;
 update public.show_checkin_change_requests set status=v_status,reviewed_at=now(),reviewed_by_user_id=auth.uid(),review_note=nullif(btrim(coalesce(p_review_note,'')),''),updated_at=now() where id=r.id;
 insert into public.show_checkin_audit_events(show_id,exhibitor_id,event_type,actor_type,actor_user_id,details) values(r.show_id,r.exhibitor_id,case when p_approved then 'change_request_approved' else 'change_request_denied' end,'secretary',auth.uid(),jsonb_build_object('change_request_id',r.id,'entry_id',r.entry_id));
 return jsonb_build_object('id',r.id,'status',v_status);
end; $$;
revoke all on function public.review_checkin_change_request(uuid,boolean,text) from public;
grant execute on function public.review_checkin_change_request(uuid,boolean,text) to authenticated,service_role;
