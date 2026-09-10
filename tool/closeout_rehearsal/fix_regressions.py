"""Run focused local read/render/recovery checks; never launches staff or workers."""
import json
import subprocess
import sys
from lab import Lab, ROOT

lab=Lab(sys.argv[1])
command = [sys.argv[2]] if len(sys.argv)>2 else ['dart','--enable-asserts','run','bin/fix_regression_probe.dart']
result=subprocess.run(command,
    cwd=ROOT/'worker/closeout_renderer',env=lab.worker_env('five-fix-probe'),
    text=True,capture_output=True,timeout=180)
print(result.stdout,end='')
if result.returncode:
    print(result.stderr[-5000:],file=sys.stderr)
raise SystemExit(result.returncode)
