"""Small real-API fee/security probe on a separate registration test show."""
from concurrent.futures import ThreadPoolExecutor
import json
from pathlib import Path
import sys
import uuid
from local import Local, ApiError

lab=Local(sys.argv[1]);source=Path(sys.argv[2]);out=Path(sys.argv[3]);out.mkdir(parents=True,exist_ok=False)
probe=json.loads((source/'probe-show.json').read_text());show=probe['show_id'];section=probe['section_id']
assert lab.rows(f"select name from shows where id='{show}'")[0]['name'].startswith('LOCAL registration repair ')
entry=lab.rows(f"select id,exhibitor_id from entries where show_id='{show}' order by id limit 1")[0];eid=entry['exhibitor_id']
admin=lab.person('focused-fee-admin');stranger=lab.person('focused-fee-stranger')
lab.sql(f"insert into role_assignments(show_id,user_id,role) values('{show}','{admin['user_id']}','admin')")
result=dict(status='running',show_id=show,synthetic_only=True)
try:
    # Removal from public makes the helper unavailable to the REST API, even
    # before PostgreSQL reaches its function-permission error path.
    denied=[]
    for token in (lab.anon,stranger['token'],admin['token']):
        for table in ('show_checkin_fee_carts','show_checkin_fee_charges'):
            try:
                lab.request('/rest/v1/'+table+'?select=*&limit=1',token=token)
                raise AssertionError('Direct bookkeeping read succeeded')
            except ApiError as error:
                assert error.code in (401,403),error.code;denied.append(error.code)
        try:
            lab.rpc('add_checkin_fee_charge',dict(p_show_id=show,p_exhibitor_id=eid,
                p_change_request_id=None,p_action_key='forbidden',p_amount_cents=100,p_breakdown={}),token)
            raise AssertionError('Public internal helper is still reachable')
        except ApiError as error:
            assert error.code==404,error.code;denied.append(error.code)
    requests=[str(uuid.uuid4()) for _ in range(12)]
    for request in requests:
        lab.sql(f"""insert into show_checkin_change_requests(id,show_id,exhibitor_id,entry_id,request_type,requested_changes,status,fee_cents,fee_breakdown)
values('{request}','{show}','{eid}','{entry['id']}','entry_edit','{{"ear_number":"LOCAL-PARALLEL"}}','pending_review',500,'{{"approval_fee_cents":500}}')""")
    # Unauthorized staff operations must fail before changing a request/balance.
    for function,body in (
        ('review_checkin_change_request',dict(p_request_id=requests[0],p_approved=True)),
        ('record_checkin_manual_payment',dict(p_show_id=show,p_exhibitor_id=eid,p_amount_cents=500,p_method='cash')),
    ):
        try:lab.rpc(function,body,stranger['token']);raise AssertionError('Unrelated user was authorized')
        except ApiError as error:assert error.code==403,error.code
    def approve(request):
        return lab.rpc('review_checkin_change_request',dict(p_request_id=request,p_approved=True),admin['token'])
    with ThreadPoolExecutor(max_workers=12) as pool:assert len(list(pool.map(approve,requests)))==12
    fees=lab.rows(f"select count(*) fees,count(distinct cart_id) carts,sum(amount_cents) cents from show_checkin_fee_charges where show_id='{show}' and exhibitor_id='{eid}'")[0]
    assert fees==dict(fees=12,carts=1,cents=6000),fees
    payment=lab.rpc('record_checkin_manual_payment',dict(p_show_id=show,p_exhibitor_id=eid,p_amount_cents=6000,p_method='cash'),admin['token'])
    assert payment['amount_cents']==6000
    report=lab.rpc('report_show_exhibitor_balances_scoped',dict(p_show_id=show,p_section_ids=[section]),admin['token'])
    rows=[r for r in report if r['exhibitor_id']==eid]
    assert sum(r['paid_manual_cents'] for r in rows)==6000
    assert sum(r['entry_count'] for r in rows)==1
    assert sum(r['balance_due_cents'] for r in rows)==0
    result.update(status='passed',denied_api_operations=len(denied),unrelated_staff_operations_denied=2,
        concurrent_approvals=12,fee_carts=1,fee_total_cents=6000,report_entry_count=1,balance_due=0)
except Exception as error:
    result.update(status='failed',error=str(error));raise
finally:
    (out/'summary.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
