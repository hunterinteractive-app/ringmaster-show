"""Bound the CLI's otherwise unlimited Auth pool in a disposable local stack.

The CLI does not expose this GoTrue setting in config.toml (verified in 2.95.4).
Recreate ONLY this local project's Auth container with its exact configuration
and an explicit pool budget. No database rows, volumes or other services change.
Run after `supabase start` and before a burst; repeat after CLI stack recreation.
"""
import argparse
import copy
import http.client
import json
from pathlib import Path
import socket
import subprocess
import time
from urllib.parse import quote
from local import Local

def configure_database(lab):
    """Mitigate supautils #214 on the pinned local image, preserving ACL/RLS.

    Only its optional error hints are disabled. Never run this against hosted
    databases or relax permissions to avoid a denied-function crash.
    """
    image=subprocess.check_output(['docker','inspect',lab.container,
        '--format','{{.Config.Image}}'],text=True).strip()
    old=lab.sql("select current_setting('supautils.hint_roles',true)").strip()
    affected=image.endswith(':17.6.1.106')
    if affected and old:
        subprocess.run(['docker','exec','-i',lab.container,'sh','-c',
            'PGPASSWORD="$POSTGRES_PASSWORD" exec psql -X -U supabase_admin -d postgres -v ON_ERROR_STOP=1'],
            input="alter system set supautils.hint_roles='';\nselect pg_reload_conf();\n",
            text=True,capture_output=True,check=True)
        for _ in range(20):
            if not lab.sql("select current_setting('supautils.hint_roles',true)").strip():break
            time.sleep(.1)
        else:raise RuntimeError('Local error-hint mitigation did not take effect')
    return dict(image=image,optional_error_hints_disabled=affected,
                changed=bool(affected and old),permissions_unchanged=True)

class DockerConnection(http.client.HTTPConnection):
    def __init__(self,path):
        super().__init__('localhost',timeout=30);self.path=path
    def connect(self):
        self.sock=socket.socket(socket.AF_UNIX,socket.SOCK_STREAM)
        self.sock.settimeout(self.timeout);self.sock.connect(self.path)

def configure(lab,pool_size=20):
    if not 1<=pool_size<=25:raise ValueError('Local Auth budget must be 1–25 connections')
    database=configure_database(lab)
    name='supabase_auth_'+lab.project
    info=json.loads(subprocess.check_output(['docker','inspect',name],text=True))[0]
    assert info['Config']['Labels'].get('com.supabase.cli.project')==lab.project
    env={item.split('=',1)[0]:item.split('=',1)[1] for item in info['Config']['Env']}
    old=env.get('GOTRUE_DB_MAX_POOL_SIZE','unbounded (CLI default)')
    if old==str(pool_size):return dict(auth_pool=pool_size,changed=False,database=database)
    context=json.loads(subprocess.check_output(['docker','context','inspect'],text=True))[0]
    endpoint=context['Endpoints']['docker']['Host']
    if not endpoint.startswith('unix://'):raise ValueError('Only a local Docker socket is allowed')
    conn=DockerConnection(endpoint[7:])
    def api(method,path,body=None):
        raw=None if body is None else json.dumps(body)
        conn.request(method,path,body=raw,headers={'Content-Type':'application/json'})
        resp=conn.getresponse();data=resp.read()
        if resp.status>=300:raise RuntimeError(f'Docker {method} failed ({resp.status})')
        return json.loads(data) if data else None
    config=copy.deepcopy(info['Config'])
    env.update(GOTRUE_DB_MAX_POOL_SIZE=str(pool_size),GOTRUE_DB_MAX_IDLE_POOL_SIZE='5')
    config['Env']=[f'{k}={v}' for k,v in env.items()]
    config['Hostname']=''
    config['HostConfig']=info['HostConfig']
    config['NetworkingConfig']={'EndpointsConfig':{
        network:{'Aliases':[a for a in (details.get('Aliases') or []) if a!=info['Id'][:12]]}
        for network,details in info['NetworkSettings']['Networks'].items()}}
    backup=name+'-before-pool-budget'
    renamed=False;created=False
    try:
        api('POST',f'/containers/{name}/stop?t=10')
        api('POST',f'/containers/{name}/rename?name={quote(backup)}');renamed=True
        api('POST',f'/containers/create?name={quote(name)}',config);created=True
        api('POST',f'/containers/{name}/start')
        for _ in range(60):
            state=api('GET',f'/containers/{name}/json')['State']
            if state.get('Health',{}).get('Status')=='healthy':break
            if not state['Running']:raise RuntimeError('Bounded Auth container stopped')
            time.sleep(1)
        else:raise RuntimeError('Bounded Auth did not become healthy')
        api('DELETE',f'/containers/{backup}') # stopped, stateless container; never remove volumes
        return dict(auth_pool=pool_size,auth_idle_pool=5,previous_auth_pool=old,changed=True,database=database)
    except Exception:
        if created:api('DELETE',f'/containers/{name}?force=true')
        if renamed:api('POST',f'/containers/{backup}/rename?name={quote(name)}')
        api('POST',f'/containers/{name}/start')
        raise
    finally:conn.close()

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('workspace');p.add_argument('--auth-pool',type=int,default=20)
    args=p.parse_args();print(json.dumps(configure(Local(args.workspace),args.auth_pool)))
