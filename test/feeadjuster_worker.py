"""Container-only unittest worker; never invoke directly on a host."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import unittest

if not Path('/.dockerenv').exists() or not os.environ.get('FEEADJUSTER_TEST_CONTAINER'):
    raise SystemExit('Only run through test/feeadjuster.py with the test image')
SCRIPTS = json.load(sys.stdin)
P = Path
BASE = '/home/admin/config.scripts/'
CONFIG = '/mnt/hdd/app-data/raspiblitz.conf'
SHARED = '/home/bitcoin/cl-plugins-available/plugins/feeadjuster/feeadjuster.py'
OLD = '/home/bitcoin/cl-plugins-available/previous/feeadjuster.py'


def write(path, text, mode=0o755):
    p = P(path)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(text)
    p.chmod(mode)


# A single recording dispatcher, with one-shot failures so rollback can succeed.
MOCK = r'''#!/usr/bin/python3
import json, os, pathlib, sys, shutil
P=pathlib.Path
name=P(sys.argv[0]).name
args=sys.argv[1:]
with open('/fixture/events','a') as f: f.write(json.dumps([name,args,os.getcwd()])+'\n')
with open('/fixture/identities','a') as f: f.write(json.dumps([name,os.geteuid(),os.getegid(),os.getcwd()])+'\n')
mode=os.environ.get('FAIL','')
def fail(point):
 if mode==point and not P('/fixture/failed').exists():
  P('/fixture/failed').touch(); sys.exit(42)
if name=='sudo':
 if args[:1]==['-u']:
  user=args[1]; args=args[2:]
  if os.environ.get('UV_USER_BAD') and 'uv' in pathlib.Path(args[0]).name:
   sys.exit(127)
  if os.environ.get('REAL_UID') and user=='bitcoin':
   os.setgroups([]); os.setgid(1000); os.setuid(1000)
 os.execvpe(args[0],args,os.environ)
if name=='git':
 command=next((x for x in args if x in ('clone','fetch','checkout','reset')),None)
 if command: fail('checkout' if command=='reset' else command)
 if command=='clone':
  dest=args[-1] if args[-1]!='https://github.com/lightningd/plugins.git' else 'plugins'
  target=P(dest); (target/'feeadjuster').mkdir(parents=True,exist_ok=True)
  (target/'feeadjuster/feeadjuster.py').write_text('# INERT NEW PLUGIN; DO NOT EXECUTE\n')
  (target/'.git').mkdir(exist_ok=True)
 if 'rev-parse' in args: print('a'*40)
 sys.exit(0)
if name=='uv':
 if '--version' in args:
  print(os.environ.get('UV_VERSION','uv 0.13.4')); sys.exit(0)
 fail('sync'); sys.exit(0)
if name=='lightning-cli':
 runtime=P('/fixture/runtime')
 if 'list' in args:
  if os.environ.get('PLUGIN_LIST'):
   print(os.environ['PLUGIN_LIST']); sys.exit(0)
  active=runtime.read_text()
  print(json.dumps({'plugins':[{'name':active,'active':True}] if active else []})); sys.exit(0)
 if 'start' in args:
  if mode=='rollback-start':
   P('/fixture/failed').touch(); sys.exit(42)
  if os.environ.get('REQUIRE_OPTIONS'):
   if 'feeadjuster-threshold=0.05' not in P('/home/bitcoin/cl.conf').read_text().splitlines(): sys.exit(43)
  fail('start'); runtime.write_text(args[-1])
 if 'stop' in args:
  if mode=='stop-after-effect' and not P('/fixture/failed').exists():
   runtime.write_text(''); P('/fixture/failed').touch(); sys.exit(42)
  fail('stop'); runtime.write_text('')
 print('{}'); sys.exit(0)
if name=='blitz.conf.sh':
 if mode=='rollback-config' and args[0]=='set':
  P('/fixture/failed').touch(); sys.exit(42)
 fail('config')
 p=P('/mnt/hdd/app-data/raspiblitz.conf')
 if args[0]=='set':
  key,value=args[1:3]; lines=p.read_text().splitlines()
  lines=[x for x in lines if not x.startswith(key+'=')]; lines.append(key+'='+value)
  p.write_text('\n'.join(lines)+'\n')
 elif args[0]=='get':
  for x in p.read_text().splitlines():
   if len(args)<2 or x.startswith(args[1]+'='): print(x)
 sys.exit(0)
if name=='systemctl': sys.exit(0)
if name=='chown': sys.exit(0)
if name=='chmod' and any('feeadjuster.py' in x for x in args): fail('chmod')
if name=='ln' and mode=='rollback-link' and any('cl-plugins-enabled' in x for x in args):
 P('/fixture/failed').touch(); sys.exit(42)
if name in ('ln','mv') and any('cl-plugins-enabled' in x for x in args): fail('link')
os.execv('/bin/'+name,[name]+args)
'''


class Feeadjuster(unittest.TestCase):
    maxDiff = None

    def setUp(self):
        os.chdir('/')
        for directory in ('/fixture', '/home/bitcoin', '/home/admin', '/mnt/hdd', '/mock'):
            shutil.rmtree(directory, ignore_errors=True)
        write('/fixture/events', '', 0o644)
        for name, source in SCRIPTS.items():
            # Transfer the actual prestart script as well as installer scripts.
            write(BASE + name, source)
        write('/fixture/identities', '', 0o644)
        write('/mock/dispatch', MOCK)
        for name in ('sudo', 'git', 'lightning-cli', 'systemctl', 'chmod', 'ln', 'mv', 'chown'):
            P('/mock/' + name).symlink_to('/mock/dispatch')
        write('/usr/local/bin/uv', MOCK)
        write(BASE + 'blitz.conf.sh', MOCK)
        write(BASE + 'network.aliases.sh', '''#!/bin/bash
network="${3:-mainnet}"
case "$network" in mainnet) prefix="";; testnet) prefix="t";; signet) prefix="s";; *) exit 1;; esac
printf 'netprefix="%s"\nCHAIN="%s"\nCLCONF="/home/bitcoin/%scl.conf"\nlightningcli_alias="/mock/lightning-cli"\n' "$prefix" "$network" "$prefix"
''')
        write('/home/admin/_cache.sh', '#!/bin/bash\nprintf \'state="%s"\\n\' "${STATE:-ready}"\n')
        write(CONFIG, 'feeadjuster=on\ntfeeadjuster=on\nsfeeadjuster=on\n', 0o644)
        write('/fixture/runtime', OLD, 0o644)
        write(SHARED, '# INERT SHARED ORIGINAL\n', 0o644)
        write(OLD, '# INERT PREVIOUS WORKING VERSION\n', 0o755)
        for prefix in ('', 't', 's'):
            write('/home/bitcoin/' + prefix + 'cl.conf', 'feeadjuster-threshold=0.05\nalias=fixture\n', 0o644)
            link = P('/home/bitcoin/' + prefix + 'cl-plugins-enabled/feeadjuster.py')
            link.parent.mkdir(parents=True, exist_ok=True)
            link.symlink_to(OLD)
        P('/etc/systemd/system').mkdir(parents=True, exist_ok=True)
        self.env = dict(os.environ, PATH='/mock:/usr/local/bin:/usr/bin:/bin', HOME='/root', LC_ALL='C')
        self.before = self.snapshot()

    def snapshot(self):
        return {'config': dict(line.split('=', 1) for line in P(CONFIG).read_text().splitlines()),
                'shared': P(SHARED).read_bytes() if P(SHARED).exists() else None,
                'shared_mode': P(SHARED).stat().st_mode if P(SHARED).exists() else None,
                'links': [os.readlink('/home/bitcoin/' + p + 'cl-plugins-enabled/feeadjuster.py')
                          if P('/home/bitcoin/' + p + 'cl-plugins-enabled/feeadjuster.py').is_symlink()
                          else None for p in ('', 't', 's')],
                'clconf': [P('/home/bitcoin/' + p + 'cl.conf').read_bytes()
                           for p in ('', 't', 's')]}

    def events(self):
        return [json.loads(line) for line in P('/fixture/events').read_text().splitlines()]

    def run_script(self, args, stdin='\n', service=False, **env):
        result = subprocess.run(['/bin/bash', BASE + ('cl.install-service.sh' if service else 'cl-plugin.feeadjuster.sh')] + args,
                                input=stdin, text=True, capture_output=True,
                                env=dict(self.env, **env), timeout=10)
        self.detail = '\nargv=%r rc=%s\nstdout=%s\nstderr=%s\nevents=%r' % (args, result.returncode, result.stdout, result.stderr, self.events())
        return result

    def assert_failed_preserved(self, result):
        self.assertNotEqual(result.returncode, 0, self.detail)
        self.assertEqual(self.snapshot(), self.before, self.detail)
        self.assertNotIn('installed and enabled', result.stdout, self.detail)

    def test_valid_networks_and_default(self):
        for args, index in ((['on'], 0), (['on', 'mainnet'], 0), (['on', 'testnet'], 1), (['on', 'signet'], 2)):
            with self.subTest(args=args):
                self.setUp()
                r = self.run_script(args)
                self.assertEqual(r.returncode, 0, self.detail)
                after = self.snapshot()
                self.assertNotEqual(after['links'][index], OLD, self.detail)
                self.assertTrue(P(after['links'][index]).is_file(), self.detail)
                self.assertTrue(os.access(after['links'][index], os.X_OK), self.detail)
                self.assertTrue(P(after['links'][index]).is_relative_to('/home/bitcoin/cl-plugins-available'), self.detail)
                self.assertTrue((P(after['links'][index]).parents[1] / '.git').is_dir(), self.detail)
                self.assertEqual(after['shared'], self.before['shared'], self.detail)
                self.assertEqual(after['shared_mode'], self.before['shared_mode'], self.detail)
                for i in range(3):
                    if i != index: self.assertEqual(after['links'][i], OLD, self.detail)
                self.assertTrue(any(n == 'lightning-cli' and 'start' in a for n, a, c in self.events()), self.detail)
                events = self.events()
                sync = next(i for i, (n, a, c) in enumerate(events) if n == 'uv' and 'sync' in a)
                link = next(i for i, (n, a, c) in enumerate(events) if n == 'ln')
                start = next(i for i, (n, a, c) in enumerate(events) if n == 'lightning-cli' and 'start' in a)
                self.assertLess(sync, link, self.detail)
                self.assertLess(link, start, self.detail)
                self.assertEqual(P(events[sync][2]), P(after['links'][index]).parent, self.detail)

    def test_fresh_enable(self):
        P('/home/bitcoin/cl-plugins-enabled/feeadjuster.py').unlink()
        write(CONFIG, 'feeadjuster=off\ntfeeadjuster=on\nsfeeadjuster=on\n', 0o644)
        write('/fixture/runtime', '', 0o644)
        r = self.run_script(['on', 'mainnet'])
        self.assertEqual(r.returncode, 0, self.detail)
        self.assertEqual(self.snapshot()['config']['feeadjuster'], 'on', self.detail)
        self.assertIsNotNone(self.snapshot()['links'][0], self.detail)
        self.assertEqual(self.snapshot()['clconf'], self.before['clconf'], self.detail)

    def test_commit_and_norestart_argument_orders(self):
        commit = 'a' * 40
        for tail in (['--commit=' + commit, 'norestart'], ['norestart', '--commit=' + commit]):
            with self.subTest(tail=tail):
                self.setUp()
                r = self.run_script(['on', 'testnet'] + tail, stdin='')
                self.assertEqual(r.returncode, 0, self.detail)
                self.assertTrue(any(n == 'git' and commit in a and ('checkout' in a or 'reset' in a) for n, a, c in self.events()), self.detail)
                self.assertFalse(any(n == 'lightning-cli' and 'start' in a for n, a, c in self.events()), self.detail)

    def test_rejected_arguments_before_mutation(self):
        cases = [['bogus'], ['on', 'regtest'], ['on', 'mainnet', '--unknown'],
                 ['off', 'mainnet', '--unknown'], ['on', 'mainnet', 'norestart', 'norestart'],
                 ['on', 'mainnet', '--commit=' + 'a'*40, '--commit=' + 'b'*40],
                 ['on', 'mainnet', '--commit=bad!'], ['on', 'mainnet', 'testnet']]
        cases += [['off', 'mainnet', 'norestart'], ['off', 'mainnet', '--commit=' + 'a'*40],
                  ['on', 'mainnet', '--commit='], ['on', 'mainnet', '--commit=--help']]
        for args in cases:
            with self.subTest(args=args):
                self.setUp()
                self.assert_failed_preserved(self.run_script(args))
                self.assertFalse(self.events(), self.detail)

    def test_eof_aborts(self):
        self.assert_failed_preserved(self.run_script(['on', 'mainnet'], stdin=''))
        self.assertFalse(any(n in ('git', 'uv', 'ln', 'mv', 'chmod', 'blitz.conf.sh')
                             or (n == 'lightning-cli' and 'list' not in a)
                             for n, a, c in self.events()), self.detail)

    def test_uv_prerequisites_before_git(self):
        for mode in ('missing', 'old', 'malformed', 'bitcoin-executable'):
            with self.subTest(mode=mode):
                self.setUp()
                extra = {}
                if mode == 'missing': P('/usr/local/bin/uv').unlink()
                if mode == 'old': extra['UV_VERSION'] = 'uv 0.13.3'
                if mode == 'malformed': extra['UV_VERSION'] = 'not-a-version'
                if mode == 'bitcoin-executable': extra['UV_USER_BAD'] = '1'
                self.assert_failed_preserved(self.run_script(['on', 'mainnet', 'norestart'], **extra))
                self.assertFalse(any(n == 'git' for n, a, c in self.events()), self.detail)

    def test_transaction_failures(self):
        for point in ('clone', 'fetch', 'checkout', 'sync', 'chmod', 'link', 'config', 'start'):
            with self.subTest(point=point):
                self.setUp()
                if point == 'clone':
                    shutil.rmtree(P(SHARED).parents[1])
                if point == 'link':
                    P('/home/bitcoin/cl-plugins-enabled/feeadjuster.py').unlink()
                self.before = self.snapshot()
                result = self.run_script(['on', 'mainnet'], FAIL=point)
                self.assertTrue(P('/fixture/failed').exists(), 'Injection not reached: ' + point + self.detail)
                self.assert_failed_preserved(result)
                if point == 'start':
                    starts = [a for n, a, c in self.events() if n == 'lightning-cli' and 'start' in a]
                    self.assertGreaterEqual(len(starts), 2, self.detail)
                    self.assertIn(starts[-1][-1], (OLD, '/home/bitcoin/cl-plugins-enabled/feeadjuster.py'), self.detail)
                    self.assertEqual(P('/fixture/runtime').read_text(), starts[-1][-1], self.detail)

    def test_repeat_on_isolated_updates(self):
        for _ in range(2):
            self.assertEqual(self.run_script(['on', 'testnet', 'norestart']).returncode, 0, self.detail)
        after = self.snapshot()
        self.assertEqual(after['links'][0], OLD, self.detail)
        self.assertEqual(after['links'][2], OLD, self.detail)
        self.assertEqual(after['shared'], self.before['shared'], self.detail)
        self.assertEqual(after['shared_mode'], self.before['shared_mode'], self.detail)
        self.assertEqual(after['clconf'], self.before['clconf'], self.detail)
        clones = [a for n, a, c in self.events() if n == 'git' and 'clone' in a]
        self.assertEqual(len(clones), 2, self.detail)
        self.assertNotEqual(clones[0][-1], clones[1][-1], self.detail)

    def test_off_and_service_regeneration(self):
        # Stable prestart inputs avoid unrelated config normalization changes.
        for prefix in ('', 't', 's'):
            path = '/home/bitcoin/' + prefix + 'cl.conf'
            write(path, P(path).read_text() + 'plugin-dir=/home/bitcoin/' + prefix +
                  'cl-plugins-enabled\ngrpc-port=4772\n# retained user comment\n', 0o644)
        self.before = self.snapshot()
        result = self.run_script(['off', 'mainnet'])
        self.assertEqual(result.returncode, 0, self.detail)
        self.assertIn('feeadjuster=off\n', P(CONFIG).read_text(), self.detail)
        self.assertIsNone(self.snapshot()['links'][0], self.detail)
        parked = P('/home/bitcoin/cl.conf').read_text()
        self.assertNotIn('feeadjuster-threshold=0.05', parked.splitlines(), self.detail)
        self.assertTrue(any(line.startswith('#') and 'feeadjuster-threshold=0.05' in line
                            for line in parked.splitlines()), self.detail)
        nonfee = lambda text: [x for x in text.splitlines() if 'feeadjuster-' not in x]
        self.assertEqual(nonfee(parked), nonfee(self.before['clconf'][0].decode()), self.detail)
        write('/fixture/events', '', 0o644)
        result = self.run_script(['mainnet'], service=True)
        self.assertEqual(result.returncode, 0, self.detail)
        unit = P('/etc/systemd/system/lightningd.service').read_text()
        prestart = next(line.split('=', 1)[1].lstrip('-') for line in unit.splitlines()
                        if line.startswith('ExecStartPre='))
        self.assertEqual(prestart.split(), [BASE + 'cl.check.sh', 'prestart', 'mainnet'])
        checked = subprocess.run(prestart.split(), env=self.env, capture_output=True, text=True)
        self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
        self.assertEqual(P('/home/bitcoin/cl.conf').read_text(), parked, checked.stdout + checked.stderr)
        self.assertIsNone(self.snapshot()['links'][0], self.detail)
        self.assertFalse(any(n in ('git', 'uv') for n, a, c in self.events()), self.detail)
        result = self.run_script(['on', 'mainnet'], REQUIRE_OPTIONS='1')
        self.assertEqual(result.returncode, 0, self.detail)
        self.assertEqual(P('/home/bitcoin/cl.conf').read_bytes(), self.before['clconf'][0], self.detail)
        self.assertEqual(self.snapshot()['clconf'][1:], self.before['clconf'][1:], self.detail)

    def test_prestart_as_bitcoin_with_no_new_privileges(self):
        # Match the generated unit's User=bitcoin and NoNewPrivileges=true.
        # Use real sudo here: same-user sudo is forbidden by that kernel flag.
        target = P('/home/bitcoin/cl.conf')
        write(target, 'network=bitcoin\nplugin-dir=/home/bitcoin/cl-plugins-enabled\n'
              'grpc-port=4772\nfeeadjuster-threshold=0.05\n', 0o644)
        os.chown(target, 1000, 1000)
        P('/home/bitcoin/cl-plugins-enabled/feeadjuster.py').unlink()
        write(CONFIG, 'feeadjuster=off\n', 0o644)
        for filename in ('events', 'identities'):
            P('/fixture/' + filename).chmod(0o666)
        sudo = P('/mock/sudo')
        sudo.unlink()
        shutil.copyfile('/usr/bin/sudo', sudo)
        sudo.chmod(0o755)
        try:
            launcher = ('import ctypes,os; os.setgroups([]); os.setgid(1000); '
                        'os.setuid(1000); '
                        'assert ctypes.CDLL(None).prctl(38,1,0,0,0)==0; '
                        'os.execv("/home/admin/config.scripts/cl.check.sh", '
                        '["cl.check.sh","prestart","mainnet"])')
            result = subprocess.run(['/usr/bin/python3', '-c', launcher],
                                    env=self.env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('# raspiblitz-feeadjuster-disabled: feeadjuster-threshold=0.05',
                          target.read_text(), result.stdout + result.stderr)
        finally:
            sudo.unlink()
            sudo.symlink_to('/mock/dispatch')

    def test_off_stop_failure(self):
        result = self.run_script(['off', 'mainnet'], FAIL='stop')
        self.assertTrue(P('/fixture/failed').exists(), self.detail)
        self.assert_failed_preserved(result)
        self.assertNotIn('was disabled', result.stdout, self.detail)

    def test_stop_error_after_effect_restores_runtime(self):
        for action in ('on', 'off'):
            with self.subTest(action=action):
                self.setUp()
                result = self.run_script([action, 'mainnet'], FAIL='stop-after-effect')
                self.assertTrue(P('/fixture/failed').exists(), 'Injection not reached' + self.detail)
                self.assert_failed_preserved(result)
                self.assertEqual(P('/fixture/runtime').read_text(), OLD, self.detail)
                rpc = [a for n, a, c in self.events() if n == 'lightning-cli']
                stop = next(i for i, a in enumerate(rpc) if 'stop' in a)
                self.assertTrue(any('list' in a for a in rpc[stop + 1:]), self.detail)
                self.assertTrue(any('start' in a and OLD in a for a in rpc[stop + 1:]), self.detail)

    def test_malformed_plugin_list_fails_closed(self):
        cases = ('not-json', '{}', '{"plugins":{}}', '{"plugins":[null]}',
                 '{"plugins":[{"name":42}]}',
                 json.dumps({'plugins': [{'name': OLD}, {'name': SHARED}]}))
        for response in cases:
            with self.subTest(response=response):
                self.setUp()
                self.assert_failed_preserved(self.run_script(['off', 'mainnet'], PLUGIN_LIST=response))
                self.assertTrue(any(n == 'lightning-cli' and 'list' in a for n, a, c in self.events()), self.detail)
                self.assertFalse(any(n == 'lightning-cli' and ('stop' in a or 'start' in a)
                                     for n, a, c in self.events()), self.detail)

    def test_rollback_restart_failure_reports_retained_sources(self):
        result = self.run_script(['on', 'mainnet'], FAIL='rollback-start')
        self.assertTrue(P('/fixture/failed').exists(), self.detail)
        self.assert_failed_preserved(result)
        self.assertIn('Rollback incomplete', result.stderr, self.detail)
        starts = [a for n, a, c in self.events() if n == 'lightning-cli' and 'start' in a]
        self.assertEqual(len(starts), 2, self.detail)
        self.assertEqual(starts[-1][-1], OLD, self.detail)
        destinations = [a[-1] for n, a, c in self.events() if n == 'git' and 'clone' in a]
        self.assertTrue(destinations, self.detail)
        self.assertTrue(all(P(dest).is_dir() for dest in destinations), self.detail)
        self.assertEqual(P('/fixture/runtime').read_text(), '', self.detail)

    def test_rollback_file_restoration_failures_report_incomplete(self):
        for point, operation in (('rollback-link', 'ln'), ('rollback-config', 'blitz.conf.sh')):
            with self.subTest(point=point):
                self.setUp()
                result = self.run_script(['on', 'mainnet'], FAIL=point)
                self.assertTrue(P('/fixture/failed').exists(), self.detail)
                self.assertNotEqual(result.returncode, 0, self.detail)
                self.assertNotIn('installed and enabled', result.stdout, self.detail)
                self.assertIn('Rollback incomplete', result.stderr, self.detail)
                calls = [a for n, a, c in self.events() if n == operation]
                self.assertGreaterEqual(len(calls), 2, 'Restoration not attempted' + self.detail)
                destinations = [a[-1] for n, a, c in self.events() if n == 'git' and 'clone' in a]
                self.assertTrue(destinations, self.detail)
                self.assertTrue(all(P(dest).is_dir() for dest in destinations), self.detail)

    def test_z_distinct_uid_private_stage_cwd(self):
        # Keep only CHOWN/SETUID/SETGID capabilities, NOT DAC_OVERRIDE: even
        # root cannot cd into bitcoin's mode-0700 stage before switching UID.
        self.assertEqual(os.geteuid(), 0)
        P('/fixture').chmod(0o777)
        for p in P('/fixture').iterdir(): p.chmod(0o666)
        probe = P('/home/bitcoin/private-probe')
        probe.mkdir(mode=0o700)
        for p in [P('/home/bitcoin')] + list(P('/home/bitcoin').rglob('*')):
            if not p.is_symlink(): os.chown(p, 1000, 1000)
        denied = subprocess.run(['/bin/bash', '-c', 'cd "$1"', 'probe', str(probe)], capture_output=True)
        self.assertNotEqual(denied.returncode, 0, 'Isolation lacks Unix DAC enforcement')
        result = self.run_script(['on', 'mainnet', 'norestart'], REAL_UID='1')
        self.assertEqual(result.returncode, 0, self.detail)
        identities = [json.loads(x) for x in P('/fixture/identities').read_text().splitlines()]
        sync_cwd = next(c for n, a, c in self.events() if n == 'uv' and 'sync' in a)
        self.assertIn(['uv', 1000, 1000, sync_cwd], identities, self.detail)
        self.assertTrue(any(n == 'git' and uid == 1000 for n, uid, gid, c in identities), self.detail)
        # Inspect stage ownership as its real owner; root deliberately lacks access.
        inspected = subprocess.run(['/usr/bin/python3', '-c',
            'import os,sys; os.setgroups([]); os.setgid(1000); os.setuid(1000); '
            's=os.stat(sys.argv[1]); print(s.st_uid, oct(s.st_mode & 0o777))',
            str(P(sync_cwd).parents[1])], capture_output=True, text=True)
        self.assertEqual(inspected.returncode, 0, inspected.stderr)
        self.assertEqual(inspected.stdout.strip(), '1000 0o700')

    def test_notready_and_norestart_never_start(self):
        for args, state in ((['on', 'mainnet'], 'starting'), (['on', 'mainnet', 'norestart'], 'ready')):
            with self.subTest(args=args, state=state):
                self.setUp()
                r = self.run_script(args, STATE=state)
                self.assertEqual(r.returncode, 0, self.detail)
                self.assertFalse(any(n == 'lightning-cli' and 'start' in a for n, a, c in self.events()), self.detail)


method = os.environ.get('FEEADJUSTER_TEST_METHOD', '')
unittest.main(argv=['feeadjuster'] + (['Feeadjuster.' + method] if method else []), verbosity=2)
