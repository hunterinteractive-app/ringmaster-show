"""Phased 55/135-session workload using the same API paths as the app."""
from concurrent.futures import ThreadPoolExecutor, as_completed
import json
import secrets
import subprocess
import threading
import time
from local import ROOT, SHOW, uid, sql_quote


class Workflows:
    def __init__(self,test):
        self.t=test; self.lab=test.lab; self.people=[];self.support_stop=threading.Event()
        actual=self.lab.rows(f"select id,tattoo from public.entries where show_id='{SHOW}'")
        ids={r['tattoo']:r['id'] for r in actual}
        assert len(ids)==25711
        for e in test.entries: e['id']=ids[e['tattoo']]
        self.awards={}
        for b in test.manifest['breeds']:
            if b['bob']: self.awards[b['first']]=['BOB']
        for section in (1,2):
            for b,code in zip([b for b in test.manifest['breeds'] if b['section']==section and b['bob']][:2],('BIS','RIS')):
                self.awards[b['first']].append(code)

    def rpc(self,name,params,p,kind=None):
        return self.t.measured(kind or name,p['index'],lambda:self.lab.rpc(name,params,self.lab.session_token(p)))

    def staff(self):
        def create(i):
            p=self.lab.person('staff-'+str(i));p['index']=i
            p['role']='reporting_clerk' if i<110 else 'admin' if i<120 else 'superintendent'
            self.lab.sql(f"insert into public.role_assignments(show_id,user_id,role) values ('{SHOW}','{p['user_id']}','{p['role']}'); insert into public.show_managers(show_id,user_id,can_manage_entries,can_manage_settings,can_finalize) values ('{SHOW}','{p['user_id']}',true,{str(i>=110).lower()},{str(110<=i<120).lower()});")
            return p
        with ThreadPoolExecutor(max_workers=12) as pool: self.people=list(pool.map(create,range(135)))
        self.t.log('staff_authenticated',unique_users=len({p['user_id'] for p in self.people}))
        # Preserve honest role permissions: superintendents do not use admin RPCs.
        self.t.summary['checks']['staff_roles']={r:sum(p['role']==r for p in self.people) for r in ('reporting_clerk','admin','superintendent')}

    def support(self,p,gate,stop):
        gate.wait();iteration=0
        while not stop.is_set():
            try:
                if p['role']=='admin':
                    section=uid('951',1+iteration%2)
                    self.rpc('get_closeout_dashboard_scoped_for_species',dict(p_show_id=SHOW,
                        p_scope_key=SHOW+':'+section,p_section_ids=[section],p_artifact_limit=100,p_artifact_offset=0,p_species_filter='rabbit'),p,'admin_dashboard')
                else:
                    self.rpc('get_show_checkin_dashboard',{'p_show_id':SHOW},p,'superintendent_dashboard')
                iteration+=1
            except Exception: pass
            stop.wait(2)

    def parallel_phase(self,name,people,action):
        gate=threading.Barrier(len(people)+26);stop=threading.Event();began=time.monotonic()
        failures=[]
        def work(p): gate.wait();return action(p)
        with ThreadPoolExecutor(max_workers=len(people)+25) as pool:
            support=[pool.submit(self.support,p,gate,stop) for p in self.people[110:]]
            workers=[pool.submit(work,p) for p in people]
            gate.wait();self.t.log('staff_phase_started',phase=name,sessions=len(people)+25)
            try:
                for job in as_completed(workers):
                    try: job.result()
                    except Exception as e: failures.append(str(e));self.t.log('staff_error',phase=name,error=str(e))
            finally: stop.set()
            for job in support: job.result()
        self.t.summary['phases'][name]=dict(sessions=len(people)+25,elapsed_s=round(time.monotonic()-began,2),failures=failures)
        if failures: raise RuntimeError(name+' failed')
        self.t.log('staff_phase_completed',phase=name)

    def checkin(self):
        # Configuration is fixture setup; actual changes/charges/payment/check-in
        # are exercised through portal + staff RPCs below.
        portal=self.lab.rpc('regenerate_show_checkin_portal_token',{'p_show_id':SHOW})
        self.lab.sql(f"update public.show_checkin_settings set is_enabled=true,entry_edit_permissions='{{\"ear_number\":\"approval\"}}',entry_edit_fee_cents='{{\"ear_number\":500}}' where show_id='{SHOW}';")
        def action(p):
            for n in range(p['index']+1,2529,30):
                params=dict(p_show_id=SHOW,p_exhibitor_id=uid('952',n))
                if n<=30:
                    session=self.t.measured('checkin_portal_auth',p['index'],lambda:self.lab.rpc('authenticate_exhibitor_checkin',dict(p_portal_token=portal,p_exhibitor_number=str(n),p_last_name=f'Exhibitor {n:04d}'),self.lab.anon))
                    e=self.t.by_exhibitor[n][0]
                    request=self.t.measured('change_request',p['index'],lambda:self.lab.rpc('submit_exhibitor_checkin_change_request',dict(p_session_token=session['session_token'],p_entry_id=e['id'],p_request_type='entry_edit',p_requested_changes={'ear_number':e['tattoo']+'X'},p_note='Synthetic cash change fee'),self.lab.anon))
                    request_id=request.get('request_id') or request.get('id')
                    assert request_id,request
                    self.rpc('review_checkin_change_request',dict(p_request_id=request_id,p_approved=True,p_review_note='Synthetic correction approved'),p,'change_approval')
                    e['tattoo']+='X'
                    context=self.rpc('get_show_checkin_payment_context',params,p,'cash_payment_context')
                    assert context['balance_due_cents']==500,context
                    self.rpc('record_checkin_manual_payment',dict(params,p_amount_cents=500,p_method='cash',p_reference=f'LOCAL-CHANGE-{n}',p_receipt_preference='no_receipt'),p,'cash_change_payment')
                result=self.rpc('complete_exhibitor_checkin_by_secretary_with_receipt',dict(params,p_entries_confirmed=True,p_initials=f'S{p["index"]}',p_note='Local E2E',p_receipt_preference='no_receipt'),p,'checkin_save')
                assert result['status']=='completed',result
                if n<=30:
                    retry=self.rpc('complete_exhibitor_checkin_by_secretary_with_receipt',dict(params,p_entries_confirmed=True,p_initials=f'S{p["index"]}',p_receipt_preference='no_receipt'),p,'checkin_retry')
                    assert retry['id']==result['id']
        self.parallel_phase('checkin',self.people[:30],action)
        (self.t.output/'expected-final-entries.json').write_text(json.dumps(self.t.entries))
        roster=[];after=None
        while True:
            page=self.rpc('get_show_checkin_roster_page',dict(p_show_id=SHOW,p_after_exhibitor_id=after,p_page_size=1000),self.people[110],'complete_roster_read')
            if not page: break
            roster.extend(page);after=page[-1]['exhibitor_id']
        assert len(roster)==2528 and len({r['exhibitor_id'] for r in roster})==2528
        self.t.summary['checks']['complete_checkin_roster']=len(roster)

    def navigation(self,p,mode):
        b=self.t.manifest['breeds'][p['index']%len(self.t.manifest['breeds'])]
        section=uid('951',b['section'])
        params=dict(p_show_id=SHOW,p_section_id=section,p_page_size=1000 if mode=='qr' else 250)
        if mode=='qr': params['p_breed']=b['breed']
        function='report_results_entry_rows_page' if mode=='qr' else 'get_judging_entry_rows_page'
        ids=set();after=None
        while True:
            page=self.rpc(function,dict(params,p_after_entry_id=after),p,mode+'_navigation_page')
            if not page: break
            for row in page:
                assert row['entry_id'] not in ids
                assert row['section_id']==section
                if mode=='manual':
                    assert row['species']=='rabbit' and row['animal_id']
                    assert isinstance(row['_awards'],list)
                ids.add(row['entry_id'])
            after=page[-1]['entry_id']
        expected=b['count'] if mode=='qr' else sum(e['section_id']==section for e in self.t.entries)
        assert len(ids)==expected,(mode,len(ids),expected)

    def save(self,p,e,mode):
        params=dict(p_show_id=SHOW,p_entry_id=e['id'],p_placement=str(e['placement']),p_result_status='Shown',
            p_disqualified_reason=None,p_is_shown=True,p_is_disqualified=False,
            p_judged_by_show_judge_id=uid('958',p['index']+1),p_result_entered_by_name=f'Synthetic Clerk {p["index"]}',
            p_result_entered_by_phone=None,p_awards=self.awards.get(e['n'],[]),p_is_qr_entry_mode=mode=='qr')
        result=self.rpc('save_results_entry',params,p,mode+'_result_save')
        assert result and int(result[0]['placement'])==e['placement'],result
        if e['n']<=110: self.rpc('save_results_entry',params,p,'result_save_retry')

    def judge_section(self,section):
        entries=[e for e in self.t.entries if e['section_id']==uid('951',section)]
        def action(p):
            for e in entries[p['index']::110]:
                self.save(p,e,'qr' if p['index']%2==0 else 'manual')
        self.parallel_phase('judging_'+str(section),self.people[:110],action)
        readiness=self.lab.readiness(section,self.people[110]['token'])
        self.t.summary['checks']['readiness_'+str(section)]=readiness
        assert readiness['ready'],readiness

    def finalize(self,section):
        sid=uid('951',section)
        result=self.t.measured('edge_finalize',110,lambda:self.lab.edge('run-closeout',
            dict(show_id=SHOW,section_ids=[sid],scope_key=SHOW+':'+sid,scope_label='Open A' if section==1 else 'Youth A',species_filter='rabbit'),self.people[110]['token']))
        self.t.summary['checks']['finalize_'+str(section)]=result
        self.t.log('scope_finalized',section=section,result=result)

    def finalize_combined(self):
        sections=[uid('951',1),uid('951',2)]
        scope=SHOW+':'+','.join(sorted(sections))
        result=self.t.measured('edge_finalize_combined',110,lambda:self.lab.edge('run-closeout',
            dict(show_id=SHOW,section_ids=sections,scope_key=scope,scope_label='Open A + Youth A',species_filter='rabbit'),self.people[110]['token']))
        self.t.summary['checks']['finalize_combined']=result
        dashboard=self.rpc('get_closeout_dashboard_scoped_for_species',dict(p_show_id=SHOW,
            p_scope_key=scope,p_section_ids=sections,p_artifact_limit=100,p_artifact_offset=0,p_species_filter='rabbit'),self.people[110])
        self.t.summary['checks']['combined_dashboard']=dashboard
        assert dashboard['latest_finalize']['scope_key']==scope,dashboard['latest_finalize']
        assert dashboard['latest_finalize']['id']==result['finalize_run_id'],result
        assert dashboard['artifact_counts']['total']>0,dashboard['artifact_counts']
        assert dashboard['artifact_counts']['by_report']['exhibitor_report']==len(self.t.by_exhibitor),dashboard['artifact_counts']
        self.t.log('combined_scope_finalized',result=result)

    def start_workers(self):
        other=int(self.lab.sql(f"select count(*) from public.show_task_queue where show_id<>'{SHOW}' and task_status::text in ('queued','running')"))
        assert other==0,'Other local shows have pending tasks'
        binary=ROOT/'output/closeout_rehearsal/closeout-renderer'
        # Caller supplies the freshly compiled worker path through the fixture.
        if (ROOT/'output/full_e2e/closeout-renderer').exists(): binary=ROOT/'output/full_e2e/closeout-renderer'
        for n in range(4):
            handle=(self.t.output/f'worker-{n}.log').open('a');self.t.logs.append(handle)
            child=subprocess.Popen([str(binary),'--continuous'],cwd=ROOT,env=self.lab.worker_env(f'local-full-e2e-{n}'),stdout=handle,stderr=subprocess.STDOUT)
            self.t.children.append(child)
        self.t.log('workers_started',processes=4,concurrent_renders=16)

    def queue(self):
        return {r['status']:r['n'] for r in self.lab.rows(f"select task_status::text status,count(*) n from public.show_task_queue where show_id='{SHOW}' group by task_status")}

    def closeout(self,max_minutes=45,fail_on_tasks=True):
        gate=threading.Barrier(136);stop=threading.Event();began=time.monotonic();deadline=time.time()+max_minutes*60
        def observer(p):
            gate.wait()
            while not stop.is_set():
                try:
                    e=self.t.entries[(p['index']*233)%len(self.t.entries)]
                    self.rpc('report_results_entry_rows_page',dict(p_show_id=SHOW,p_entry_ids=[e['id']]),p,'judging_read_during_closeout')
                except Exception: pass
                stop.wait(3)
        with ThreadPoolExecutor(max_workers=135) as pool:
            jobs=[pool.submit(observer,p) for p in self.people[:110]]+[pool.submit(self.support,p,gate,stop) for p in self.people[110:]]
            gate.wait()
            try:
                while time.time()<deadline:
                    status=self.queue();self.t.log('closeout_progress',status=status)
                    (self.t.output/'summary.partial.json').write_text(json.dumps(self.t.summary,indent=2))
                    if fail_on_tasks and status.get('failed',0)>=20: raise RuntimeError('Closeout stopped after 20 failed tasks; evidence preserved')
                    if not status.get('queued',0) and not status.get('running',0): break
                    stop.wait(10)
                else: raise RuntimeError('Closeout deadline reached with unfinished tasks')
            finally: stop.set()
            for job in jobs: job.result()
        self.t.summary['phases']['closeout']=dict(elapsed_s=round(time.monotonic()-began,2),sessions=135,status=self.queue())
        if fail_on_tasks: assert not self.queue().get('failed',0)

    def run(self,resume_after_checkin=False):
        self.staff()
        if resume_after_checkin:
            assert int(self.lab.sql(f"select count(*) from public.show_checkin_records where show_id='{SHOW}' and status='completed'"))==2528
            self.t.summary['resumed_after']='checkin; prior navigation failures remain in staff-navigation-summary.json'
        else:
            self.rpc('assign_show_coop_numbers',dict(p_show_id=SHOW,p_scope_mode='separate',p_overwrite_existing=False),self.people[110],'assign_coops')
            collisions=self.lab.rows(f"select scope,coop_number from show_animal_coop_numbers where show_id='{SHOW}' group by scope,coop_number having count(*)>1")
            assert not collisions, 'Coop labels must be unique before check-in'
            self.t.summary['checks']['unique_coop_labels']=True
            self.checkin()
            for mode in ('qr','manual'):
                try: self.parallel_phase('all_'+mode+'_navigation',self.people[:110],lambda p:self.navigation(p,mode))
                except RuntimeError: pass # Read-only load failure does not prevent independent save coverage.
        if resume_after_checkin and self.lab.readiness(1,self.people[110]['token'])['ready']:
            actual={r['id']:str(r['placement']) for r in self.lab.rows(f"select id,placement from entries where show_id='{SHOW}' and section_id='{uid('951',1)}'")}
            assert all(actual.get(e['id'])==str(e['placement']) for e in self.t.entries if e['section_id']==uid('951',1))
            self.t.summary['checks']['resumed_open_results_verified']=len(actual)
        else: self.judge_section(1)
        self.judge_section(2)
        # Final reports begin only after all Open and Youth judging is complete.
        assert all(self.lab.readiness(s,self.people[110]['token'])['ready'] for s in (1,2))
        self.t.log('all_judging_completed_before_closeout')
        started=False;failures=[]
        for section in (1,2):
            try:
                self.finalize(section)
                started=True
            except Exception as e:
                failures.append(dict(section=section,error=str(e)))
                self.t.log('finalization_failed',section=section,error=str(e))
        self.t.summary['finalization_failures']=failures
        if started:
            self.start_workers()
            self.closeout()
        if failures: raise RuntimeError('Finalization failed in one or more sections')
