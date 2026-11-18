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

    # Two additions can race for one original paid scratch. The balance lock
    # must preserve both additions while allowing only one automatic offset.
    from pathlib import Path
    fixture=(Path(__file__).resolve().parents[2]/'supabase/tests/scratch_replacement_offsets_test.sql').read_text()
    fixture=fixture[:fixture.index("insert into entries(id,show_id,section_id,exhibitor_id,is_fur,status,species,tattoo,created_at)")]
    fixture=fixture.replace('begin;', '').replace('set local search_path', 'set search_path').replace("select no_plan();", "select no_plan();")
    fixture=fixture.replace("create temporary table ids", "create table replacement_race_ids").replace('from ids', 'from replacement_race_ids').replace('into ids', 'into replacement_race_ids')
    execute(fixture)
    def fixture_id(key):
        return execute(f"select id from replacement_race_ids where k='{key}'").stdout.strip()
    rs,rp,ra,old=[fixture_id(k) for k in ('show','person','A','oldA')]
    def addition():
        return f"insert into entries(id,show_id,section_id,exhibitor_id,status,is_fur,species,created_at) values(gen_random_uuid(),'{rs}','{ra}','{rp}','entered',false,'rabbit',clock_timestamp());"
    results=race([addition(),addition()])
    assert all(r.returncode==0 for r in results),[r.stderr for r in results]
    def snapshot():
        return json.loads(execute(f"select jsonb_build_object('due',balance_due_cents,'offset',fee_snapshot->'replacement_credit_cents','pairs',jsonb_array_length(fee_snapshot->'replacement_offsets')) from show_exhibitor_balances where show_id='{rs}' and source='entries'").stdout.strip())
    assert snapshot()=={'due':500,'offset':500,'pairs':1},snapshot()
    print('PASS concurrent additions consume a scratch only once')
    results=race([addition(),f"update entries set scratched_at=null,status='entered' where id='{old}';"])
    assert all(r.returncode==0 for r in results),[r.stderr for r in results]
    assert snapshot()=={'due':1500,'offset':0,'pairs':0},snapshot()
    print('PASS concurrent addition and unscratch preserve all charges')
