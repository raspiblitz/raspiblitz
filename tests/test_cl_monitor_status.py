#!/usr/bin/env python3
"""Run full cl.monitor.sh status entrypoint in a network-disabled container.
MIT licensed. Only synthetic RPC output and service fixtures are used.
"""
import json, os, pathlib, subprocess, sys
source = pathlib.Path(sys.argv[1]).read_text()
worker = r'''
import json, os, pathlib, subprocess
source = json.loads(input())
pathlib.Path('/src/cl.monitor.sh').write_text(source)
for name, data in {
 'systemctl': '#!/bin/sh\necho "active (running)"\n',
 'lightning-cli': '#!/bin/sh\ncase "$*" in *--version*) echo "lightning cli v25.12"; exit 0;; esac\nprintf "%s" "$RPC_BODY"\nprintf "%s" "$RPC_ERROR" >&2\nexit "$RPC_RC"\n'
}.items():
 p = pathlib.Path('/usr/local/bin') / name
 p.write_text(data); p.chmod(0o755)
cases = [
 ('healthy', '{"num_peers":2}', '', '0', '1', '1'),
 ('offline', '{"num_peers":0}', '', '0', '1', '0'),
 ('empty-success', '', '', '0', '0', '0'),
 ('silent-failure', '', '', '1', '0', '0'),
 ('failure-with-valid-body', '{"num_peers":2}', '', '1', '0', '0'),
 ('malformed-success', 'not JSON', '', '0', '0', '0'),
 ('stderr-failure', '', 'RPC unavailable', '1', '0', '0'),
 ('multiple-responses', '{"num_peers":1}\n{"num_peers":2}', '', '0', '0', '0'),
 ('stderr-with-valid-body', '{"num_peers":2}', 'RPC warning', '0', '0', '0'),
 ('empty-object', '{}', '', '0', '0', '0'),
 ('null-body', 'null', '', '0', '0', '0'),
 ('fractional-peers', '{"num_peers":1.5}', '', '0', '0', '0'),
 ('negative-peers', '{"num_peers":-1}', '', '0', '0', '0'),
]
results=[]
for name, body, err, rc, ready, online in cases:
 env=dict(os.environ, RPC_BODY=body, RPC_ERROR=err, RPC_RC=rc)
 p=subprocess.run(['/bin/bash','/src/cl.monitor.sh','mainnet','status'],env=env,capture_output=True,text=True,timeout=5)
 expected=["ln_cl_running='1'", "ln_cl_ready='%s'"%ready,"ln_cl_online='%s'"%online]
 passed=p.returncode == 0 and all(x in p.stdout for x in expected)
 results.append(dict(case=name,passed=passed,returncode=p.returncode,stdout=p.stdout,stderr=p.stderr))
print(json.dumps(results,indent=2))
raise SystemExit(0 if all(x['passed'] for x in results) else 1)
'''
cmd=['docker','run','--rm','-i','--network=none','--cap-drop=ALL','--security-opt=no-new-privileges','--read-only','--tmpfs','/src:rw,size=2m','--tmpfs','/usr/local/bin:rw,exec,size=2m','--tmpfs','/var/cache/raspiblitz:rw,size=2m',os.environ.get('CL_MONITOR_TEST_IMAGE', 'raspiblitz-cl-monitor-tests'),'python3','-c',worker]
p=subprocess.run(cmd,input=json.dumps(source)+'\n',text=True,capture_output=True,timeout=60)
print(p.stdout,end=''); print(p.stderr,file=sys.stderr,end=''); sys.exit(p.returncode)
