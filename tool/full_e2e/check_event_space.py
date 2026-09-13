import json,shutil,subprocess,sys
from pathlib import Path
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root/'tool/full_e2e'))
from local import Local
lab=Local(sys.argv[1]);scale=int(sys.argv[2]);assert scale in (2,4)
text=subprocess.check_output(['docker','exec',lab.container,'df','-Pk','/var/lib/postgresql/data'],text=True)
vm_free=int(text.strip().splitlines()[-1].split()[3])*1024
capacity=subprocess.check_output(['/usr/bin/swift','-module-cache-path','/tmp/ringmaster-swift-module-cache',str(root/'tool/full_e2e/volume_capacity.swift')],text=True)
mac=[json.loads(line) for line in capacity.splitlines()][0]
result=dict(status='passed',docker_free_bytes=vm_free,host_raw_free_bytes=shutil.disk_usage(root).free,macos_capacity=mac,required_docker_bytes=20_000_000_000,required_host_available_bytes=40_000_000_000,basis='Prior 51k measured host+Docker growth doubled with reserve. macOS capacity includes reclaimable storage; raw free blocks retained for pressure monitoring.')
if vm_free<result['required_docker_bytes'] or min(mac['important_usage_bytes'],mac['opportunistic_usage_bytes'])<result['required_host_available_bytes']:result['status']='insufficient_capacity'
print(json.dumps(result,indent=2))
if result['status']!='passed':raise SystemExit(2)
