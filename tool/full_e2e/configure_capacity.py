"""Budget Auth/REST pools and gateway connections in a disposable local stack.

The CLI does not expose this GoTrue setting in config.toml (verified in 2.95.4).
Recreate only this local project's stateless Auth/REST/gateway containers with their
original configuration and explicit pool budgets. No database rows or volumes
change. The REST metrics port is internal to the local Docker network.
Run after `supabase start` and before a burst; repeat after CLI stack recreation.
"""
import argparse
import copy
import http.client
import json
from pathlib import Path
import re
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

def _configure_service(lab,service,settings):
    name='supabase_'+service+'_'+lab.project
    info=json.loads(subprocess.check_output(['docker','inspect',name],text=True))[0]
    assert info['Config']['Labels'].get('com.supabase.cli.project')==lab.project
    env={item.split('=',1)[0]:item.split('=',1)[1] for item in info['Config']['Env']}
    old={k:env.get(k) for k in settings}
    entrypoint=copy.deepcopy(info['Config'].get('Entrypoint'))
    template_changed=False
    if service=='kong' and entrypoint and any('/home/kong/custom_nginx.template' in s for s in entrypoint):
        # CLI 2.95.4 supplies its own minimal template, bypassing Kong's
        # nginx_main/nginx_events environment injections. Change only its
        # exact events block; preserve embedded routes, keys and certificates.
        original='events {\n    multi_accept on;\n}'
        configured='worker_rlimit_nofile 4096;\n\nevents {\n    worker_connections 2048;\n    multi_accept on;\n}'
        matches=sum(s.count(original) for s in entrypoint)
        if matches==1:
            entrypoint=[s.replace(original,configured,1) for s in entrypoint]
            template_changed=True
        elif matches or sum(s.count(configured) for s in entrypoint)!=1:
            raise RuntimeError('Unrecognized local gateway template; refusing to alter it')
    if not template_changed and all(env.get(k)==v for k,v in settings.items()):
        return dict(service=service,changed=False,settings=settings)
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
    config['Entrypoint']=entrypoint
    env.update(settings)
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
            if service in ('rest','kong') and state['Running']:
                try:
                    lab.request('/rest/v1/shows?select=id&limit=1',timeout=2)
                    break
                except Exception:pass
            if not state['Running']:raise RuntimeError('Configured local service stopped')
            time.sleep(1)
        else:raise RuntimeError('Configured local service did not become healthy')
        api('DELETE',f'/containers/{backup}') # stopped, stateless container; never remove volumes
        return dict(service=service,changed=True,previous=old,settings=settings,
                    local_gateway_template_changed=template_changed)
    except Exception:
        if created:api('DELETE',f'/containers/{name}?force=true')
        if renamed:api('POST',f'/containers/{backup}/rename?name={quote(name)}')
        api('POST',f'/containers/{name}/start')
        raise
    finally:conn.close()

def configure(lab,pool_size=20,rest_pool=None):
    if not 1<=pool_size<=25:raise ValueError('Local Auth budget must be 1–25 connections')
    plan=lab.workspace/'rehearsal-capacity.json'
    if rest_pool is None:rest_pool=json.loads(plan.read_text()).get('rest_pool',10) if plan.exists() else 10
    if not 5<=rest_pool<=30:raise ValueError('Local REST budget must be 5–30 connections')
    maximum=int(lab.sql('show max_connections'))
    # Reserve 25 connections for platform services/administration, plus 20 spare.
    if pool_size+rest_pool+45>maximum:raise ValueError('Pool budgets leave insufficient database headroom')
    database=configure_database(lab)
    auth=_configure_service(lab,'auth',{'GOTRUE_DB_MAX_POOL_SIZE':str(pool_size),'GOTRUE_DB_MAX_IDLE_POOL_SIZE':'5'})
    rest=_configure_service(lab,'rest',{'PGRST_DB_POOL':str(rest_pool),'PGRST_ADMIN_SERVER_PORT':'3001'})
    # The pinned local Kong image defaults to 512 worker connections, counting
    # client and upstream sockets together. A 270-session navigation barrier
    # exhausted that limit even with spare database connections. Keep one
    # gateway worker and the same database budgets; permit the intended burst.
    gateway=_configure_service(lab,'kong',{
        'KONG_NGINX_EVENTS_WORKER_CONNECTIONS':'2048',
        'KONG_NGINX_MAIN_WORKER_RLIMIT_NOFILE':'4096'})
    nginx=subprocess.check_output(['docker','exec','supabase_kong_'+lab.project,
        'cat','/usr/local/kong/nginx.conf'],text=True)
    gateway_limits={name:int(re.search(r'\b'+name+r'\s+(\d+)\s*;',nginx).group(1))
                    for name in ('worker_connections','worker_rlimit_nofile')}
    assert gateway_limits==dict(worker_connections=2048,worker_rlimit_nofile=4096),gateway_limits
    dump=subprocess.check_output(['docker','exec','supabase_rest_'+lab.project,'postgrest','--dump-config'],text=True)
    settings={line.split(' = ',1)[0]:line.split(' = ',1)[1] for line in dump.splitlines() if ' = ' in line and line.split(' = ',1)[0] in ('db-pool','db-pool-acquisition-timeout','admin-server-port')}
    assert settings['db-pool']==str(rest_pool),settings
    return dict(auth_pool=pool_size,rest_pool=rest_pool,database_max_connections=maximum,
                reserved_connections=25,spare_connections=maximum-pool_size-rest_pool-25,
                database=database,auth=auth,rest=rest,gateway=gateway,
                verified_gateway_settings=gateway_limits,verified_rest_settings=settings)

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('workspace');p.add_argument('--auth-pool',type=int,default=20);p.add_argument('--rest-pool',type=int)
    args=p.parse_args();print(json.dumps(configure(Local(args.workspace),args.auth_pool,args.rest_pool)))
