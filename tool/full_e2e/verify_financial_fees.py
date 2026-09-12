"""Transactional local regression for fee amount, attribution and retry safety."""
import json
from pathlib import Path
import sys
from local import Local,SHOW,uid

l=Local(sys.argv[1]);out=Path(sys.argv[2]);checks=[]
admin=l.sql(f"select user_id from role_assignments where show_id='{SHOW}' and role='admin' limit 1").strip()
for amount in (750,250):
    script=f"""begin;
set request.jwt.claims='{json.dumps(dict(role='authenticated',sub=admin))}';
insert into public.show_checkin_change_requests(id,show_id,exhibitor_id,entry_id,request_type,requested_changes,status)
select '99800000-0000-4000-8000-000000000001',show_id,exhibitor_id,id,'entry_edit','{{"ear_number":"TEST-FEE"}}','approved'
from public.entries where show_id='{SHOW}' and section_id='{uid('951',2)}' order by id limit 1;
select public.add_checkin_fee_charge('{SHOW}',(select exhibitor_id from show_checkin_change_requests where id='99800000-0000-4000-8000-000000000001'),'99800000-0000-4000-8000-000000000001','entry_edit_approval',{amount});
select public.add_checkin_fee_charge('{SHOW}',(select exhibitor_id from show_checkin_change_requests where id='99800000-0000-4000-8000-000000000001'),'99800000-0000-4000-8000-000000000001','entry_edit_approval',{amount});
select public.record_checkin_manual_payment('{SHOW}',(select exhibitor_id from show_checkin_change_requests where id='99800000-0000-4000-8000-000000000001'),{amount},'cash','LOCAL-FEE-REGRESSION','no_receipt');
do $$
declare b jsonb; n int;
begin
  select count(*) into n from show_checkin_fee_charges where change_request_id='99800000-0000-4000-8000-000000000001';
  if n<>1 then raise exception 'Retry duplicated the fee'; end if;
  select report_generation_private.balance_with_checkin_sections(to_jsonb(x)) into b
  from show_exhibitor_balances x join show_checkin_fee_charges c on c.cart_id=x.entry_cart_id
  where c.change_request_id='99800000-0000-4000-8000-000000000001';
  if (b->>'entry_count')::int<>0 or (b->>'calculated_total_cents')::int<>{amount}
    or (b->>'paid_manual_cents')::int<>{amount} or (b->>'balance_due_cents')::int<>0
    or b->'section_breakdown'->0->>'section_id'<>'{uid('951',2)}' then
    raise exception 'Incorrect fee balance: %',b;
  end if;
  if (select sum((r->>'paid_manual_cents')::int) from report_show_exhibitor_balances_scoped('{SHOW}',array['{uid('951',1)}'::uuid]) r)<>15000 then
    raise exception 'Youth fee leaked into Open';
  end if;
  if (select sum((r->>'paid_manual_cents')::int) from report_show_exhibitor_balances_scoped('{SHOW}',array['{uid('951',2)}'::uuid]) r)<>{amount} then
    raise exception 'Youth fee missing';
  end if;
end;
$$;
rollback;"""
    l.sql(script)
    checks.append(dict(amount_cents=amount,section='Youth',fee_rows=1,added_entries=0,balance_due=0,status='passed'))
result=dict(status='passed',transactions_rolled_back=True,checks=checks)
(out/'fee-regression.json').write_text(json.dumps(result,indent=2));print(json.dumps(result))
