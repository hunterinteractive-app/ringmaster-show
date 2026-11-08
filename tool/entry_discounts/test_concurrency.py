"""Disposable local Supabase checkout-concurrency regression test."""
import subprocess,uuid,concurrent.futures,time
import argparse
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--container', default='supabase_db_ringmaster-show-full-e2e-convention')
DB = parser.parse_args().container
if not DB.startswith('supabase_db_'):
 raise SystemExit('Only a local Supabase Docker database is supported.')
def sql(s):
 return subprocess.run(['docker','exec','-i',DB,'psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1','-At'],input=s,text=True,capture_output=True)
o,s,e,sec,a,b=[str(uuid.uuid4()) for _ in range(6)]
setup=f"""
insert into auth.users(id) values('{o}');
insert into public.shows(id,created_by,name,start_date,end_date,entry_close_at,payment_timing_mode,is_test) values('{s}','{o}','Discount concurrency test',current_date,current_date+1,now()+interval '1 day','online_or_at_show',true);
insert into public.show_sections(id,show_id,kind,letter) values('{sec}','{s}','open','A');
insert into public.show_fee_settings(show_id,currency) values('{s}','USD');
insert into public.show_section_fee_settings(section_id,fee_per_entry,fee_per_show,fur_fee) values('{sec}',12,0,0) on conflict(section_id) do update set fee_per_entry=12,fee_per_show=0,fur_fee=0;
insert into public.exhibitors(id,owner_user_id,type,display_name,email,is_test) values('{e}','{o}','adult','Concurrency Test','concurrency@example.invalid',true);
insert into public.entry_carts(id,user_id,show_id) values('{a}','{o}','{s}'),('{b}','{o}','{s}');
insert into public.entry_cart_items(cart_id,section_id,exhibitor_id,species,tattoo,breed,variety,sex,class_name) values('{a}','{sec}','{e}','rabbit','A','Dutch','Black','Buck','Senior'),('{b}','{sec}','{e}','rabbit','B','Dutch','Black','Buck','Senior');
select set_config('request.jwt.claims','{{"sub":"{o}","role":"authenticated"}}',false);
select public.manage_show_discount_code('{s}',p_code=>'MEMBER20',p_type=>'amount',p_basis=>'overall',p_value=>20,p_action=>'save');
select public.entry_cart_discounts('{a}','MEMBER20','{e}');
select public.entry_cart_discounts('{b}');
"""
try:
 r=sql(setup);assert r.returncode==0,r.stderr
 prefix=f"begin;select set_config('request.jwt.claims','{{\"sub\":\"{o}\",\"role\":\"authenticated\"}}',true);"
 with concurrent.futures.ThreadPoolExecutor(2) as pool:
  first=pool.submit(sql,prefix+f"select public.commit_free_entry_cart('{a}');select pg_sleep(1);commit;")
  time.sleep(.2)
  second=pool.submit(sql,prefix+f"select public.commit_free_entry_cart('{b}');commit;")
  one,two=first.result(),second.result()
 assert one.returncode==0,one.stderr
 assert two.returncode!=0 and 'outstanding amount' in two.stderr.lower(),two.stderr
 result=sql(f"select count(*) from public.entries where show_id='{s}';select discount_cents||','||balance_due_cents from public.calculate_entry_cart_balance_internal('{b}');")
 assert result.returncode==0,result.stderr
 assert result.stdout.strip().splitlines()==['1','800,400'],result.stdout
 print('PASS: simultaneous checkouts cannot reuse the same remaining discount; second checkout owes $4.')
finally:
 r=sql(f"delete from public.entries where show_id='{s}';delete from public.show_exhibitor_balances where show_id='{s}';delete from public.entry_cart_items where cart_id in(select id from public.entry_carts where show_id='{s}');delete from public.entry_carts where show_id='{s}';delete from public.shows where id='{s}';delete from public.exhibitors where id='{e}';delete from auth.users where id='{o}';")
 assert r.returncode==0,r.stderr
