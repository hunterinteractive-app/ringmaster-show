"""Exercise a DISPOSABLE LOCAL support broker. No mail, payments or live accounts."""
import json, secrets, subprocess, uuid, urllib.request, urllib.error
root='/private/tmp/rm-delegation-e2e'
cfg=json.loads(subprocess.check_output(['supabase','status','--workdir',root,'-o','json'],stderr=subprocess.DEVNULL))
url='http://127.0.0.1:58721'
assert cfg['API_URL']==url
anon=cfg['ANON_KEY']; svc=cfg['SERVICE_ROLE_KEY']
def call(method,path,token,payload=None,session=None,expect=200):
    req=urllib.request.Request(url+path, method=method, data=None if payload is None else json.dumps(payload).encode(),
        headers={'apikey':anon,'Authorization':'Bearer '+token,'Content-Type':'application/json',**({'x-rm-session':session} if session else {})})
    try:
        with urllib.request.urlopen(req,timeout=30) as res: status=res.status;raw=res.read().decode()
    except urllib.error.HTTPError as e: status=e.code;raw=e.read().decode()
    try:x=json.loads(raw) if raw else None
    except ValueError:x=raw
    if status!=expect: raise RuntimeError(f'{method} {path.split("?")[0]} expected {expect}, got {status}: {str(x)[:240]}')
    return x
def sql(q):
    return subprocess.check_output(['docker','exec','-i','supabase_db_rm-delegation-e2e','psql','-U','postgres','-XAt','-v','ON_ERROR_STOP=1','-c',q],text=True).strip()
def user(name):
    email=f'{name}-{uuid.uuid4().hex[:10]}@example.invalid';pw=secrets.token_urlsafe(32)
    u=call('POST','/auth/v1/admin/users',svc,{'email':email,'password':pw,'email_confirm':True})
    session=call('POST','/auth/v1/token?grant_type=password',anon,{'email':email,'password':pw})
    return u['id'],session['access_token'],session['refresh_token']
aid,actor,actor_refresh=user('support-agent');tid,target,target_refresh=user('licensed-user');oid,other,_=user('outsider')
sql(f"insert into public.super_admins values ('{aid}'); insert into support_session_private.operators values ('{aid}'); insert into public.account_license_balances(user_id,purchased_show_days) values('{tid}',3),('{aid}',9);")
endpoint='/functions/v1/support-session'
call('POST',endpoint,other,{'action':'start','target_id':tid},expect=403)
call('POST',endpoint,actor,{'action':'start','target_id':aid},expect=403)
g=call('POST',endpoint,actor,{'action':'start','target_id':tid})
assert g['user']['id']==tid and set(g)=={'id','user','expires_at'}
sid=g['id']; print('Verified admin-only start and target identity',flush=True)
g=call('POST',endpoint,actor,{'action':'resume','session_id':sid})
assert g['user']['id']==tid
proxy=endpoint+'/proxy'
call('GET',proxy+'/rest/v1/shows?select=id',other,session=sid,expect=403)
call('GET',proxy+'/auth/v1/user',actor,session=sid,expect=403)
call('POST',proxy+'/rest/v1/rpc/manage_support_session',actor,{},sid,expect=403)
call('PATCH',proxy+'/rest/v1/profiles',actor,{'accepted_terms_version':'fixture'},sid,expect=403)
show=call('POST',proxy+'/rest/v1/rpc/create_show_with_license',actor,{'p_name':'Synthetic support smoke','p_start_date':'2027-03-06','p_end_date':'2027-03-07','p_location_name':'Test'},sid)
assert sql(f"select created_by=owner_user_id and owner_user_id='{tid}' from public.shows where id='{show}'")=='t'
assert sql(f"select consumed_show_days from public.account_license_balances where user_id='{tid}'")=='2'
assert sql(f"select consumed_show_days from public.account_license_balances where user_id='{aid}'")=='0'
assert sql(f"select count(*) from public.role_assignments where show_id='{show}' and user_id='{tid}' and role='admin'")=='1'
rows=call('GET',proxy+'/rest/v1/shows?select=id',actor,session=sid)
assert [x['id'] for x in rows]==[show]
call('PATCH',proxy+'/rest/v1/shows?id=eq.'+show,actor,{'name':'Edited by support'},sid,expect=204)
assert sql(f"select name from public.shows where id='{show}'")=='Edited by support'
assert sql(f"select count(*) from support_session_private.requests r join support_session_private.sessions s on s.id=r.session_id where s.actor='{aid}' and s.target='{tid}' and resource='rpc/create_show_with_license'")=='1'
identity=call('POST',proxy+'/functions/v1/payment-quote-preview',actor,{},sid)
assert identity['authenticated_as']==tid
blob=b'%PDF-1.4\nsynthetic report'
resource='/storage/v1/object/support-smoke/'+tid+'/example.pdf'
upload=urllib.request.Request(url+proxy+resource,method='POST',data=blob,headers={'apikey':anon,'Authorization':'Bearer '+actor,'x-rm-session':sid,'content-type':'application/pdf'})
with urllib.request.urlopen(upload,timeout=20) as res: assert res.status==200
download=urllib.request.Request(url+proxy+resource,headers={'apikey':anon,'Authorization':'Bearer '+actor,'x-rm-session':sid})
with urllib.request.urlopen(download,timeout=20) as res: assert res.read()==blob
print('Verified authenticated Edge action and RLS-protected binary report upload/download',flush=True)
print('Verified target show ownership, target-only licensing, staff assignment, RLS edit and admin audit',flush=True)
call('POST',endpoint,actor,{'action':'end','session_id':sid})
call('GET',proxy+'/rest/v1/shows?select=id',actor,session=sid,expect=403)
assert call('GET','/auth/v1/user',target)['id']==tid
assert call('GET','/auth/v1/user',actor)['id']==aid
assert call('POST','/auth/v1/token?grant_type=refresh_token',anon,{'refresh_token':target_refresh})['user']['id']==tid
actor=call('POST','/auth/v1/token?grant_type=refresh_token',anon,{'refresh_token':actor_refresh})['access_token']
print('Verified exit revokes delegation and preserves both original logins',flush=True)
g=call('POST',endpoint,actor,{'action':'start','target_id':tid})
sql(f"update support_session_private.sessions set expires_at=now()-interval '1 second' where id='{g['id']}';")
call('GET',proxy+'/rest/v1/shows?select=id',actor,session=g['id'],expect=403)
print('Verified expired sessions cannot read or write.',flush=True)
sql(f"delete from support_session_private.operators where user_id='{aid}';")
assert call('POST',endpoint,actor,{'action':'start','target_id':tid})=={'mode':'preview'}
sql(f"insert into support_session_private.operators values('{aid}');")
# Admin rights removed during an active session must take effect before another request.
g=call('POST',endpoint,actor,{'action':'start','target_id':tid})
sql(f"delete from public.super_admins where user_id='{aid}';")
call('GET',proxy+'/rest/v1/shows?select=id',actor,session=g['id'],expect=403)
print('Verified live super-admin revocation. Smoke test passed.',flush=True)
