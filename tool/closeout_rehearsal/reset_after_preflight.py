"""Reset only this synthetic show's rehearsal work after preserving run logs."""
import json
import sys
from lab import Lab, ROOT, SHOW

lab = Lab(sys.argv[1])
out = ROOT / 'output/closeout_rehearsal'
if not list(out.glob('run-*/summary.json')):
    raise RuntimeError('Preserve the completed preflight summary before resetting')
# The worker was killed while holding five tasks. Advance only those synthetic
# leases to test recovery without waiting ten minutes; never mutate real work.
lab.sql(f"update public.show_task_queue set lease_expires_at=now()-interval '1 second', heartbeat_at=now()-interval '11 minutes' where show_id='{SHOW}' and task_status='running';")
recovered = lab.rpc('recover_stale_report_render_tasks', {'p_limit': 50})
remaining = int(lab.sql(f"select count(*) from public.show_task_queue where show_id='{SHOW}' and task_status='running';").strip())
(out / 'preflight-recovery.json').write_text(json.dumps({
    'recovered_after_worker_kill': recovered, 'remaining_running': remaining,
    'lease_expiry_advanced_locally': True,
}, indent=2))
print('Recovered tasks:', recovered, 'remaining running:', remaining)
lab.sql(f"""
begin;
do $$ begin
  if not exists(select 1 from public.shows where id='{SHOW}' and name='SYNTHETIC 2024 Convention Counts') then
    raise exception 'Refusing to reset an unrecognized show';
  end if;
  if exists(select 1 from public.show_payments where show_id='{SHOW}') then
    raise exception 'Preserve and reconcile payments before resetting';
  end if;
end $$;
alter table public.shows add column if not exists is_closed boolean not null default false;
create unique index if not exists local_rehearsal_award_identity on public.entry_awards(entry_id,award_code);
delete from public.show_task_queue where show_id='{SHOW}';
delete from public.show_report_artifacts where show_id='{SHOW}';
delete from public.show_finalize_runs where show_id='{SHOW}';
update public.entries set placement=null,result_entered_by_user_id=null,
  result_entered_by_name=null,result_entered_at=null
where show_id='{SHOW}' and id between '95400000-0000-0000-0000-000000018868' and '95400000-0000-0000-0000-000000019867';
update public.shows set results_version=results_version+1 where id='{SHOW}';
commit;
analyze public.entry_awards;
""")
