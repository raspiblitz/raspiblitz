#!/usr/bin/env python3
"""Run actual appliance scripts in a disposable, network-disabled Docker OS.

No host mounts, node, plugin execution, credentials or third-party Python deps.
See feeadjuster.md for fixture boundaries and reproduction.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--image', default='feeadjuster-tests:local')
    parser.add_argument('--source', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--revision', help='Read production scripts from this local git revision')
    parser.add_argument('--payload', type=Path, help='Read an already captured script JSON payload')
    parser.add_argument('--test', help='Run one unittest method (default: all)')
    args = parser.parse_args()
    scripts = {}
    for name in ('cl-plugin.feeadjuster.sh', 'cl.install-service.sh', 'cl.check.sh'):
        relative = 'home.admin/config.scripts/' + name
        scripts[name] = (subprocess.check_output(['git', '-C', str(args.source), 'show',
                         args.revision + ':' + relative]).decode() if args.revision
                         else (args.source / relative).read_text())
    helper = 'home.admin/config.scripts/cl-plugin.feeadjuster-config.py'
    if args.revision:
        optional = subprocess.run(['git', '-C', str(args.source), 'show', args.revision + ':' + helper],
                                  text=True, capture_output=True)
        if optional.returncode == 0:
            scripts[Path(helper).name] = optional.stdout
    elif (args.source / helper).is_file():
        scripts[Path(helper).name] = (args.source / helper).read_text()
    if args.payload:
        scripts = json.loads(args.payload.read_text())
    print(json.dumps({'source_sha256': {name: hashlib.sha256(text.encode()).hexdigest()
                                      for name, text in scripts.items()},
                      'revision': str(args.payload) if args.payload else (args.revision or 'working-tree')}), flush=True)
    worker = Path(__file__).with_name('feeadjuster_worker.py').read_text()
    command = ['docker', 'run', '--rm', '--network=none', '--cap-drop=ALL',
               '--cap-add=SETUID', '--cap-add=SETGID', '--cap-add=CHOWN',
               '-e', 'FEEADJUSTER_TEST_METHOD=' + (args.test or ''),
               '--security-opt=no-new-privileges', '--pids-limit=128', '--memory=384m',
               '--cpus=2', '-i', args.image, 'python3', '-c', worker]
    result = subprocess.run(command, input=json.dumps(scripts), text=True, timeout=240)
    return result.returncode


if __name__ == '__main__':
    sys.exit(main())
