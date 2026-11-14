"""Independent sessions race the same receipt and the same outstanding cents."""
from concurrent.futures import ThreadPoolExecutor
import json, subprocess, uuid

def run(container, database):
    show, exhibitor, section, request = [str(uuid.uuid4()) for _ in range(4)]
    def execute(query, checked=True):
        result = subprocess.run(['docker','exec','-i',container,'psql','-U','postgres','-d',database,'-v','ON_ERROR_STOP=1','-At'],input=query,text=True,capture_output=True)
        if checked and result.returncode: raise RuntimeError(result.stderr)
        return result
    execute(f"""insert into shows(id,name) values('{show}','Concurrency');
    insert into exhibitors(id,display_name) values('{exhibitor}','Fixture');
    insert into show_sections(id,show_id,kind,letter,is_enabled) values('{section}','{show}','open','A',true);
    insert into show_fee_settings(show_id,currency) values('{show}','usd');
    insert into show_section_fee_settings(section_id,fee_per_entry,fur_fee,fee_per_show) values('{section}',5,0,0);
    insert into entries(id,show_id,section_id,exhibitor_id,status,is_fur) select gen_random_uuid(),'{show}','{section}','{exhibitor}','entered',false from generate_series(1,2);""")
    def payment(amount, key):
        return f"select public.record_show_finance_payment('{show}','{exhibitor}',{amount},'zelle','2026-01-01T12:00:00Z','Concurrent test','{key}');"
    def race(queries):
        def task(query):
            return execute("begin; set local request.jwt.claims='{\"sub\":\"00000000-0000-4000-8000-000000000001\",\"role\":\"authenticated\"}';"+query+"select pg_sleep(0.3); commit;",False)
        with ThreadPoolExecutor(max_workers=2) as pool: return list(pool.map(task,queries))
    results=race([payment(500,request),payment(500,request)])
    assert all(r.returncode==0 for r in results), [r.stderr for r in results]
    assert execute(f"select count(*) from show_payments where show_id='{show}'").stdout.strip()=='1'
    print('PASS concurrent duplicate requests create one receipt')
    results=race([payment(400,str(uuid.uuid4())),payment(400,str(uuid.uuid4()))])
    assert sum(r.returncode==0 for r in results)==1, [r.stderr for r in results]
    assert 'cannot exceed' in next(r.stderr for r in results if r.returncode)
    print('PASS competing receipts cannot overpay the balance')
    credit=f"select public.credit_show_finance_balance('{show}','{exhibitor}',100,'Concurrent credit','{uuid.uuid4()}');"
    results=race([payment(100,str(uuid.uuid4())),credit])
    assert sum(r.returncode==0 for r in results)==1, [r.stderr for r in results]
    row=json.loads(execute(f"select jsonb_build_object('due',balance_due_cents,'received',paid_manual_cents,'charges',calculated_total_cents) from show_exhibitor_balances where show_id='{show}' and source='entries'").stdout.strip())
    assert row['due']==0 and row['received']==row['charges']
    print('PASS payment and credit cannot spend the same outstanding cents')
