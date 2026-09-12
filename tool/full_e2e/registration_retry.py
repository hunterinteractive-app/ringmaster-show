"""Bounded protocol equivalent of the app's registration write helper.

Explicit IDs survive retries. Ambiguous writes are read back under the same
owner's RLS and only missing rows are inserted. Never upsert or overwrite.
"""
import json
import random
import time
import urllib.error
from local import ApiError

TRANSIENT_DATABASE = {'PGRST003','53300','57P01','08000','08006','502','503','504'}

def transient(error, function=False):
    if isinstance(error, ApiError):
        if function:
            # FunctionException uses HTTP status, regardless of provider/runtime
            # diagnostic codes in its JSON body. PostgrestException uses code.
            return error.code in (500,502,503,504)
        body=error.body
        return (body.get('code') in TRANSIENT_DATABASE if isinstance(body,dict) and body.get('code')
                else str(error.code) in TRANSIENT_DATABASE)
    return isinstance(error,(urllib.error.URLError,TimeoutError,ConnectionError))

def retry(test,kind,session,call,*,function=False):
    for attempt in range(1,4):
        try:return call()
        except Exception as error:
            again=attempt<3 and transient(error,function=function)
            record=dict(kind=kind,session=session,attempt=attempt,retry=again,error=str(error)[:1000])
            with test.lock:
                with (test.output/'registration-http-failures.jsonl').open('a') as f:f.write(json.dumps(record)+'\n')
            if not again:raise
            time.sleep(((250 << (attempt-1))+random.randrange(250))/1000)

def insert(test,table,rows,token,session):
    if isinstance(rows,dict):rows=[rows]
    assert table in ('animals','exhibitors','entry_carts','entry_cart_items')
    ids=[r['id'] for r in rows];assert len(ids)==len(set(ids)) and ids
    def read():
        found=test.lab.request('/rest/v1/'+table+'?select=*&id=in.('+','.join(ids)+')',token=token)
        wanted={r['id']:r for r in rows}
        for row in found:
            assert all(row.get(k)==v for k,v in wanted[row['id']].items()),'Saved registration payload differs'
        return found
    attempts=0
    def save():
        nonlocal attempts
        existing=read() if attempts else [];attempts+=1
        present={r['id'] for r in existing};missing=[r for r in rows if r['id'] not in present]
        if not missing:return
        try:
            inserted=test.lab.request('/rest/v1/'+table,missing,token,prefer='return=representation')
            combined=existing+inserted
            assert len(combined)==len(rows),'The complete registration save was not returned'
            wanted={r['id']:r for r in rows}
            assert all(all(r.get(k)==v for k,v in wanted[r['id']].items()) for r in combined),'Saved registration payload differs'
        except ApiError as error:
            if not isinstance(error.body,dict) or error.body.get('code')!='23505':raise
            if len(read())!=len(rows):raise
    return retry(test,'insert_'+table,session,save)
