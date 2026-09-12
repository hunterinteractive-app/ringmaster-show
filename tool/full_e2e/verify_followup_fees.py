"""Focused fee/security regression on a retained synthetic event; all writes roll back."""
import json
from pathlib import Path
import sys
import uuid
from local import Local, SHOW, uid

lab=Local(sys.argv[1]);out=Path(sys.argv[2]);out.mkdir(parents=True,exist_ok=False)
admin=lab.sql(f"select user_id from role_assignments where show_id='{SHOW}' and role='admin' limit 1").strip()
entry=lab.rows(f"select e.id,e.exhibitor_id from entries e where e.show_id='{SHOW}' and e.section_id='{uid('951',2)}' and e.scratched_at is null and exists(select 1 from show_exhibitor_balances b where b.show_id=e.show_id and b.exhibitor_id=e.exhibitor_id and b.paid_manual_cents>0) order by e.id limit 1")[0]
eid=entry['exhibitor_id']; requests=[str(uuid.uuid4()) for _ in range(3)]
claims=json.dumps(dict(role='authenticated',sub=admin))
sql=f"""begin;
set local statement_timeout='30s'; set local lock_timeout='5s';
set local request.jwt.claims='{claims}';
create temporary table original_balances as select * from show_exhibitor_balances where show_id='{SHOW}' and exhibitor_id='{eid}';
create temporary table original_payments as select * from show_payments where show_id='{SHOW}' and exhibitor_id='{eid}';
create temporary table before_totals as select
  (select count(*) from entries where show_id='{SHOW}') entries,
  (select sum(paid_manual_cents) from original_balances) cash,
  (select sum((r->>'paid_manual_cents')::int) from report_show_exhibitor_balances_scoped('{SHOW}',array['{uid('951',1)}'::uuid]) r) open_cash,
  (select sum((r->>'paid_manual_cents')::int) from report_show_exhibitor_balances_scoped('{SHOW}',array['{uid('951',2)}'::uuid]) r) youth_cash;
"""
def assertion(condition,message):
    return f"do $check$ begin if not ({condition}) then raise exception '{message}'; end if; end; $check$;\n"

sql+=assertion("to_regprocedure('public.add_checkin_fee_charge(uuid,uuid,uuid,text,integer,jsonb)') is null",'Internal helper is still in public')
sql+=assertion("(select bool_and(relrowsecurity) from pg_class where oid in ('show_checkin_fee_carts'::regclass,'show_checkin_fee_charges'::regclass))",'Fee RLS is disabled')
for role in ('anon','authenticated'):
    for table in ('show_checkin_fee_carts','show_checkin_fee_charges'):
        for privilege in ('SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER'):
            sql+=assertion(f"not has_table_privilege('{role}','public.{table}','{privilege}')",f'{role} still has {privilege} on {table}')
    sql+=assertion(f"not has_function_privilege('{role}','report_generation_private.add_checkin_fee_charge(uuid,uuid,uuid,text,integer,jsonb)','EXECUTE')",'Internal helper can be called by clients')

for i,(request,amount) in enumerate(zip(requests,(750,250,300))):
    sql+=f"""insert into show_checkin_change_requests(id,show_id,exhibitor_id,entry_id,request_type,requested_changes,status,fee_cents,fee_breakdown)
values('{request}','{SHOW}','{eid}','{entry['id']}','entry_edit','{{"ear_number":"LOCAL-FEE-{i}"}}','pending_review',{amount},'{{"approval_fee_cents":{amount}}}');
set local role authenticated;
select review_checkin_change_request('{request}',true,'Local focused regression');
do $replay$ begin
 begin perform review_checkin_change_request('{request}',true,'Local replay');
 raise exception 'Repeated approval was accepted';
 exception when raise_exception then
   if sqlerrm<>'This request has already been reviewed' then raise; end if;
 end;
end; $replay$;
reset role;
"""
    due=(750,250,450)[i]
    sql+=assertion(f"(select sum(balance_due_cents) from show_exhibitor_balances where show_id='{SHOW}' and exhibitor_id='{eid}')={due}",f'New fee {i} missing from balance')
    paid=(750,100,450)[i]
    sql+=f"set local role authenticated; select record_checkin_manual_payment('{SHOW}','{eid}',{paid},'cash','LOCAL-FEE-{i}','no_receipt'); reset role;\n"
    sql+=f"select report_generation_private.add_checkin_fee_charge('{SHOW}','{eid}','{request}','entry_edit_approval',{amount},'{{\"approval_fee_cents\":{amount}}}');\n"
    sql+=assertion(f"(select count(*) from show_checkin_fee_charges where change_request_id='{request}')=1",'Replay duplicated a fee')

sql+=assertion(f"(select sum(balance_due_cents) from show_exhibitor_balances where show_id='{SHOW}' and exhibitor_id='{eid}')=0",'New payments did not clear balances')
sql+=assertion(f"(select sum(paid_manual_cents) from show_exhibitor_balances where show_id='{SHOW}' and exhibitor_id='{eid}')=(select cash+1300 from before_totals)",'Cash total is incorrect')
sql+=assertion(f"(select count(*) from entries where show_id='{SHOW}')=(select entries from before_totals)",'Fees created animal entries')
sql+=assertion("not exists(select 1 from original_balances o join show_exhibitor_balances b using(id) where to_jsonb(o)<>to_jsonb(b))",'Earlier balances changed')
sql+=assertion("not exists(select 1 from original_payments o join show_payments p using(id) where to_jsonb(o)<>to_jsonb(p))",'Earlier payments changed')
sql+=assertion(f"(select sum((r->>'paid_manual_cents')::int) from report_show_exhibitor_balances_scoped('{SHOW}',array['{uid('951',1)}'::uuid]) r)=(select open_cash from before_totals)",'Youth fees leaked into Open reports')
sql+=assertion(f"(select sum((r->>'paid_manual_cents')::int) from report_show_exhibitor_balances_scoped('{SHOW}',array['{uid('951',2)}'::uuid]) r)=(select youth_cash+1300 from before_totals)",'Youth report omitted later fees')
sql+=f"""do $changed$ begin
 begin perform report_generation_private.add_checkin_fee_charge('{SHOW}','{eid}','{requests[0]}','entry_edit_approval',999,'{{}}');
 raise exception 'Changed replay was accepted'; exception when invalid_parameter_value then null; end;
end; $changed$;
"""
# Exercise actual denied statements, not just grant inspection. Repeated calls
# must produce 42501 while keeping the backend alive after the hint mitigation.
for role in ('anon','authenticated'):
    sql+=f'set local role {role};\n'
    for statement in ('perform count(*) from public.show_checkin_fee_charges',
                      'delete from public.show_checkin_fee_carts where false',
                      f"perform report_generation_private.add_checkin_fee_charge('{SHOW}','{eid}',null,'denied',100,'{{}}')"):
        sql+=f"""do $denied$ begin for i in 1..25 loop
 begin {statement}; raise exception 'Unexpected direct access';
 exception when insufficient_privilege then null; end;
 end loop; end; $denied$;\n"""
    sql+='reset role;\n'
sql+='rollback;'
(out/'transaction.sql').write_text(sql)
try:
    result=lab.sql(sql);(out/'database-output.log').write_text(result)
    summary=dict(status='passed',rolled_back=True,followup_fees_cents=[750,250,300],
        cash_payments_cents=[750,100,450],remaining_due_cents=0,
        prior_balances_and_payments_unchanged=True,replay_duplicates=0,
        changed_replay_denied=True,section_attribution=True,added_animals=0,
        denied_operations=150,public_helper_removed=True)
except Exception as error:
    summary=dict(status='failed',error=str(error),rolled_back=True)
    raise
finally:
    (out/'summary.json').write_text(json.dumps(summary,indent=2));print(json.dumps(summary))
