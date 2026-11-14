#!/usr/bin/env python3
"""Run complete, unchanged installer entry points in a disposable offline container.

Host: python3 test/uv_installer_execution_test.py
No host mounts; only the scripts and this worker are streamed over stdin.
"""
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NAMES = ('cl.install.sh', 'cl-plugin.backup.sh')
IMAGE = 'python:3.14-slim'

# All external effects are inert recording fixtures. Filesystem operations stay real.
FIXTURE = r'''#!/usr/local/bin/python3
import json, os, pathlib, subprocess, sys
name = pathlib.Path(sys.argv[0]).name
args = sys.argv[1:]
with open('/run/fixtures/events.jsonl', 'a') as f:
    f.write(json.dumps([name, *args]) + '\n')
def put(path, text):
    p = pathlib.Path(path); p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text); p.chmod(0o755)

if name == 'sudo':
    if args[:1] == ['-u']: args = args[2:]
    while args and '=' in args[0]:
        key, value = args.pop(0).split('=', 1); os.environ[key] = value
    sys.exit(subprocess.call(args))
elif name == 'uv':
    if args == ['--version']: print(os.environ['UV_OUTPUT'])
    elif args[:1] == ['sync'] and os.environ['CASE'] == 'sync_failure': sys.exit(42)
elif name == 'cargo':
    if os.environ['CASE'] == 'cargo_failure': sys.exit(43)
    put('/opt/rust/bin/uv', pathlib.Path('/run/fixtures/dispatch').read_text())
elif name == 'curl':
    url = args[-1]
    if os.environ['CASE'] == 'download_failure': sys.exit(44)
    if os.environ['CASE'] == 'installer_failure':
        print('exit 45'); sys.exit(0)
    if 'uv-installer.sh' in url:
        # Deliberately unsigned executable payload: documents the trust boundary.
        print('echo "remote-payload $(uname -m)" >> /run/remote-executed')
        print('cp /run/fixtures/dispatch "$UV_INSTALL_DIR/uv"; chmod +x "$UV_INSTALL_DIR/uv"')
    else: print(': # inert rustup installer')
    if os.environ['CASE'] == 'partial_download': sys.exit(44)
elif name == 'wget':
    put(args[args.index('-O') + 1], 'fixture  clightning-v26.06.1.zip\n')
elif name == 'gpg':
    if '--show-keys' in args:
        print('fpr:::::::::616C52F99D0612B2A151B1074129A994AA7E9852:')
    else: print('Good signature')
elif name == 'sha256sum': print('fixture  archive')
elif name == 'unzip':
    put('/home/bitcoin/clightning-v26.06.1/configure', '#!/bin/sh\nexit 0\n')
elif name == 'git':
    if 'clone' in args:
        put('/home/bitcoin/cl-plugins-available/plugins/backup/backup.py', '# fixture\n')
elif name == 'lightning-cli':
    if args == ['--version']: print('v26.06.1')
    elif 'list' in args: print('/backup' if os.environ['CASE'] == 'loaded' else '{}')
elif name == 'crontab': print('backup-compact mainnet')
elif name in ('apt-get', 'pip', 'chown', 'chmod', 'usermod', 'groupadd', 'getent',
              'rustup', 'make', 'systemctl'): pass
else: sys.exit('Unexpected fixture: ' + name)
'''


def host():
    paths = [ROOT / 'home.admin/config.scripts' / name for name in NAMES]
    paths += [Path(__file__).resolve()]
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode='w') as archive:
        for path in paths:
            print(f'SOURCE {hashlib.sha256(path.read_bytes()).hexdigest()} {path.name}', flush=True)
            archive.add(path, arcname=path.name)
    platform = os.environ.get('UV_TEST_PLATFORM', 'linux/arm64')
    command = ['docker', 'run', '--rm', '-i', '--platform=' + platform, '--network=none', '--cap-drop=ALL',
               '--tmpfs=/home:exec', '--tmpfs=/opt:exec', '--tmpfs=/run:exec',
               '--tmpfs=/suite:exec', '--tmpfs=/var/cache:exec',
               '--security-opt=no-new-privileges', IMAGE, 'bash', '-c',
               'tar --no-same-owner -xf - -C /suite && '
               'python3 /suite/uv_installer_execution_test.py --worker']
    return subprocess.run(command, input=stream.getvalue()).returncode


class InstallerExecution(unittest.TestCase):
    def prepare(self, script, case, arch):
        for directory in ('/home/bitcoin', '/home/admin', '/opt/rust', '/run/fixtures'):
            shutil.rmtree(directory, ignore_errors=True)
        for path in ('/usr/local/bin/uv', '/run/fixtures/events.jsonl', '/run/remote-executed'):
            Path(path).unlink(missing_ok=True)
        Path('/run/fixtures').mkdir()
        Path('/run/fixtures/dispatch').write_text(FIXTURE)
        Path('/run/fixtures/dispatch').chmod(0o755)
        for name in ('sudo', 'cargo', 'curl', 'wget', 'gpg', 'sha256sum',
                     'unzip', 'git', 'lightning-cli', 'crontab', 'apt-get', 'pip',
                     'chown', 'chmod', 'usermod', 'groupadd', 'getent', 'make', 'systemctl'):
            Path('/run/fixtures', name).symlink_to('/run/fixtures/dispatch')
        Path('/opt/rust/bin').mkdir(parents=True)
        Path('/opt/rust/bin/rustup').symlink_to('/run/fixtures/dispatch')
        scripts = Path('/home/admin/config.scripts')
        scripts.mkdir(parents=True)
        (scripts / 'network.aliases.sh').write_text(
            "#!/bin/sh\necho 'CHAIN=mainnet; CLNETWORK=bitcoin; netprefix=; lightningcli_alias=lightning-cli'\n")
        (scripts / 'network.aliases.sh').chmod(0o755)
        Path('/home/admin/_cache.sh').write_text("#!/bin/sh\necho state=ready\n")
        Path('/home/admin/_cache.sh').chmod(0o755)
        Path('/home/bitcoin/cl-plugins-available').mkdir(parents=True)
        Path('/home/bitcoin/cl-plugins-enabled').mkdir()
        if case not in ('missing', 'download_failure', 'partial_download', 'installer_failure', 'cargo_failure'):
            Path('/usr/local/bin/uv').symlink_to('/run/fixtures/dispatch')
        output = {'vulnerable': 'uv 0.13.3', 'malformed': 'uv not-a-version',
                  'minimum': 'uv 0.13.4'}.get(case, 'uv 0.13.6 (fixture)')
        return {**os.environ, 'PATH': '/run/fixtures:/usr/local/bin:/usr/bin:/bin',
                'CASE': case, 'ARCH': arch, 'UV_OUTPUT': output}

    def exercise(self, script, case, arch):
        env = self.prepare(script, case, arch)
        result = subprocess.run(['bash', '/suite/' + script,
                                 'install' if script == NAMES[0] else 'on', 'mainnet'],
                                env=env, text=True, capture_output=True, timeout=120)
        events = [json.loads(line) for line in Path('/run/fixtures/events.jsonl').read_text().splitlines()]
        calls = [event for event in events if event[0] != 'sudo']
        failed = case in ('vulnerable', 'malformed', 'download_failure', 'partial_download', 'installer_failure', 'cargo_failure', 'sync_failure')
        details = result.stdout + result.stderr + '\n' + repr(calls)
        self.assertEqual(result.returncode == 0, not failed, details)
        sync = [event for event in calls if event[:2] == ['uv', 'sync']]
        if case in ('vulnerable', 'malformed', 'download_failure', 'partial_download', 'installer_failure', 'cargo_failure'):
            self.assertFalse(sync, details)
        elif case != 'loaded':
            self.assertEqual(len(sync), 1, details)
        if case in ('vulnerable', 'malformed'):
            self.assertIn('requires uv >= 0.13.4', result.stdout)
        if case == 'cargo_failure':
            self.assertIn(['cargo', 'install', '--locked', '--version', '0.13.6', 'uv'], calls)
        if case in ('download_failure', 'partial_download', 'installer_failure'):
            self.assertTrue(any(e[0] == 'curl' for e in calls), details)
        if failed:
            self.assertFalse(any(e[0] in ('make', 'systemctl') for e in calls), details)
            self.assertFalse(any(e[:2] == ['uv', 'run'] for e in calls), details)
        if script == NAMES[0] and not failed:
            self.assertIn(['cargo', 'install', '--locked', '--version', '0.13.6', 'uv'] in calls,
                          (True,) if case == 'missing' else (False,))
            self.assertTrue(any(e[0] == 'make' and 'install' in e for e in calls), details)
        if script == NAMES[1] and not failed:
            self.assertTrue(any(e[:2] == ['uv', 'run'] for e in calls), details)
            if case == 'loaded': self.assertFalse(sync, details)
        if script == NAMES[1] and case == 'missing':
            self.assertIn(['curl', '-LsSf', 'https://releases.astral.sh/github/uv/releases/download/0.13.6/uv-installer.sh'], calls)
            self.assertEqual(Path('/run/remote-executed').read_text(), f'remote-payload {arch}\n')
            self.assertFalse(any(e[0] in ('sha256sum', 'gpg') for e in calls))
        print(f'PASS {script} {arch} {case}', flush=True)


# Independent unittest identities keep CI totals and failures explicit.
for script in NAMES:
    cases = ['missing', 'vulnerable', 'minimum', 'fixed', 'malformed', 'download_failure', 'partial_download', 'installer_failure', 'sync_failure']
    cases += ['cargo_failure'] if script == NAMES[0] else ['loaded']
    for arch in (os.uname().machine,):
        for case in cases:
            def test(self, script=script, case=case, arch=arch):
                self.exercise(script, case, arch)
            setattr(InstallerExecution, 'test_' + script.replace('.', '_').replace('-', '_') + '_' + arch + '_' + case, test)

if __name__ == '__main__':
    if '--worker' not in sys.argv:
        sys.exit(host())
    if not Path('/.dockerenv').exists() or ROOT != Path('/'):
        sys.exit('Worker must run in the disposable container')
    unittest.main(argv=[sys.argv[0]], verbosity=2)
