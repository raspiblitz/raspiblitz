#!/usr/bin/env python3
"""Offline branch tests of exact appliance hook blocks (not full provisioning).

Only trust gates and surrounding installer branches are extracted: all actual
OS/service operations are inert functions. Full image/install acceptance is not
claimed. Whole scripts additionally receive syntax and full-file static checks.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = '/home/admin/config.scripts/blitz.trust.sh'


def execute(block, setup='', args=()):
    with tempfile.TemporaryDirectory() as tmp:
        prefix = '''gate() { echo "GATE $*" >&2; return "${GATE_STATUS:-0}"; }
sudo() { echo "SUDO $*"; return 0; }
'''
        return subprocess.run(['bash', '-c', prefix + setup + '\n' +
                               block.replace(HELPER, 'gate') + '\necho CONTINUED',
                               'hook', *args], cwd=tmp, capture_output=True, text=True)


class HookTests(unittest.TestCase):
    def test_each_image_setup_update_gate_success_and_failure(self):
        for name in ('build_sdcard.sh', 'home.admin/_provision.setup.sh',
                     'home.admin/_provision.update.sh'):
            script = (ROOT / name).read_text()
            gates = [line for line in script.splitlines() if line.lstrip().startswith(HELPER + ' update')]
            self.assertEqual(len(gates), 1, name)
            for code in (0, 1):
                with self.subTest(path=name, status=code):
                    result = execute(gates[0], f'GATE_STATUS={code}; logFile=hook.log')
                    # The update path redirects the gate log, but not the sentinel.
                    self.assertEqual(result.returncode, code, result.stderr)
                    self.assertEqual('CONTINUED' in result.stdout, code == 0)
            # Keep these gates before the consumer/bootstrap portions of scripts.
            if name == 'build_sdcard.sh':
                self.assertLess(script.index(HELPER + ' update'), script.index('cp -r /home/admin/raspiblitz/home.admin/setup.scripts'))
            else:
                marker = '# LOGFILE' if name.endswith('setup.sh') else '# MIGRATION'
                self.assertLess(script.index(HELPER + ' update'), script.index(marker))

    def test_release_normal_fatal_success_and_explicit_quick_bypass(self):
        script = (ROOT / 'home.admin/config.scripts/blitz.release.sh').read_text()
        start = script.index('if [ "$1" != "-quick" ]; then')
        end = script.index('\nfi', start) + len('\nfi')
        block = script[start:end]
        self.assertIn(HELPER + ' update || exit 1', block)
        for quick, code in ((False, 0), (False, 1), (True, 1)):
            with self.subTest(quick=quick, status=code):
                result = execute(block, f'GATE_STATUS={code}', ('-quick' if quick else '',))
                self.assertEqual(result.returncode, 0 if quick else code, result.stderr)
                self.assertEqual('GATE update' in result.stderr, not quick)
                self.assertEqual('CONTINUED' in result.stdout, quick or code == 0)
                if code and not quick:
                    self.assertNotIn('SUDO ', result.stdout)

    def test_fints_jdk_maven_install_failures_and_refresh_gate(self):
        script = (ROOT / 'home.admin/config.scripts/bonus.fints.sh').read_text()
        start = script.index('  # install java & build tool')
        end = script.index('  # make sure mysql', start)
        block = script[start:end]
        for fail in ('default-jdk', 'maven', 'refresh', ''):
            with self.subTest(fail=fail):
                setup = 'sudo() { echo "INSTALL $*"; [[ "$*" != *"' + (fail or 'never-match') + '"* ]]; };'
                if fail == 'refresh':
                    setup += ' GATE_STATUS=1;'
                result = execute(block, setup)
                self.assertEqual(result.returncode, 1 if fail else 0, result.stderr)
                self.assertEqual('CONTINUED' in result.stdout, not fail)
                self.assertEqual('GATE update' in result.stderr, fail not in ('default-jdk', 'maven'))
                if fail == 'default-jdk':
                    self.assertNotIn('INSTALL apt install -y maven', result.stdout)

    def test_fints_compile_config_gate_and_maven_failure(self):
        script = (ROOT / 'home.admin/config.scripts/bonus.fints.sh').read_text()
        start = script.index('  # Maven startup files')
        # Include the actual Maven error branch, stopping before database setup.
        end = script.index('\n  fi', script.index('  if ! [ $? -eq 0 ]; then', start)) + len('\n  fi')
        block = script[start:end]
        for config, gate, maven in ((True, 0, 0), (False, 1, 0), (False, 0, 1), (False, 0, 0)):
            with self.subTest(config=config, gate=gate, maven=maven):
                setup = f'''GATE_STATUS={gate}; APPID=fints
sudo() {{
  if [ "$1" = test ]; then return {0 if config else 1}; fi
  echo "SUDO $*"
  if [ "$1" = -u ]; then return {maven}; fi
  return 0
}}
readlink() {{ echo /usr/lib/jvm/fixture/bin/java; }}
'''
                result = execute(block, setup)
                self.assertEqual(result.returncode, 1 if config or gate or maven else 0, result.stderr)
                reached = not config and not gate
                self.assertEqual('/usr/bin/mvn package' in result.stdout, reached)
                if reached:
                    self.assertIn('JAVA_HOME=/usr/lib/jvm/fixture MAVEN_SKIP_RC=true', result.stdout)
                if config:
                    self.assertNotIn('GATE', result.stderr)


if __name__ == '__main__':
    unittest.main()
