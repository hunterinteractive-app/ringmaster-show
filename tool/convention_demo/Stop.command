#!/bin/zsh
set -eu
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/../.."
python3 - <<'PY'
from pathlib import Path
import os,signal,subprocess,time
p=Path('output/convention-demo/server.pid')
if p.exists():
 pid=int(p.read_text())
 command=subprocess.run(['ps','-p',str(pid),'-o','command='],capture_output=True,text=True).stdout
 if 'tool/convention_demo/serve.py' in command:
  os.kill(pid,signal.SIGTERM)
  for _ in range(30):
   try:os.kill(pid,0)
   except ProcessLookupError:break
   time.sleep(1)
p.unlink(missing_ok=True)
subprocess.run(['supabase','stop','--workdir','/tmp/ringmaster-convention-demo'],check=True)
print('Convention demo stopped. Sample data is retained.')
PY
