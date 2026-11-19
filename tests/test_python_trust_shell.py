#!/usr/bin/env python3
"""Offline changed-shell-branch checks; external commands are inert fixtures.

Execute only in disposable Linux containers. These execute production blocks,
not rewritten installer logic; they do not establish full provisioning coverage.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

from test_python_trust_bootstrap import ROOT, policy_prefix


class InstallPaths(unittest.TestCase):
    def test_api_install_dependency_and_trust_gates(self):
        source = (ROOT / 'home.admin/config.scripts/blitz.web.api.sh').read_text()
        block = source[source.index('  # see https://github.com/raspiblitz/raspiblitz/issues/4169'):source.index('  # prepare systemd service')]
        header = r'''
sudo() {
  shift 2
  while [[ "$1" = --preserve-env=* ]]; do shift; done
  case "$*" in
    *blitz.python-trust.sh\ pip\ *) step=pip ;;
    *blitz.python-trust.sh\ app\ *) step=app ;;
    *Cython*) step=Cython ;;
    *rich-toolkit*) step=rich-toolkit ;;
    *requirements.txt*) step=requirements ;;
    *) echo UNEXPECTED >&2; return 99 ;;
  esac
  echo "reached $step"
  [ "$step" != "$FAIL_STEP" ]
}
'''
        steps = ['pip', 'Cython', 'rich-toolkit', 'requirements', 'app']
        for failure in ['', *steps]:
            with self.subTest(failure=failure):
                result = subprocess.run(['bash', '-c', header + policy_prefix(source) + '\n' + block + '\necho SERVICES_ALLOWED'],
                                        env=dict(os.environ, FAIL_STEP=failure), text=True, capture_output=True)
                reached = [line.removeprefix('reached ') for line in result.stdout.splitlines() if line.startswith('reached ')]
                self.assertEqual(reached, steps[:steps.index(failure) + 1] if failure else steps, result.stdout + result.stderr)
                self.assertEqual(result.returncode, 1 if failure else 0, result.stdout + result.stderr)
                self.assertEqual('SERVICES_ALLOWED' in result.stdout, not failure)

    def test_joinmarket_existing_and_new_posthook(self):
        source = (ROOT / 'home.admin/config.scripts/bonus.joinmarket.sh').read_text()
        start = source.index('if [ "$1" = "install" ]; then')
        end = source.index('\n# switch on', start)
        # Replace only the external owner's setup, already tested through the
        # real release gate in RestartPaths, not the install/posthook branches.
        external_start = source.index('    echo "# cleaning before install"', start)
        external_end = source.index('    if "${pip_sudo[@]}" /home/joinmarket/install.joinmarket.sh', external_start)
        block = source[start:end]
        block = block.replace(source[external_start:external_end], '    echo owner-setup-fixture\n    qtgui=false\n')
        header = r'''
sudo() {
  shift 2
  while [[ "$1" = --preserve-env=* ]]; do shift; done
  case "$1" in
    */install.joinmarket.sh) echo owner; return "$OWNER_STATUS" ;;
    */blitz.python-trust.sh) echo posthook; return "$HELPER_STATUS" ;;
    *) echo UNEXPECTED >&2; return 99 ;;
  esac
}
'''
        with tempfile.TemporaryDirectory() as temp:
            activate = Path(temp) / 'activate'
            block = block.replace('/home/joinmarket/joinmarket-clientserver/jmvenv/bin/activate', str(activate))
            for existing in (False, True):
                for owner, helper in ((0, 0), (0, 1), (1, 0)):
                    with self.subTest(existing=existing, owner=owner, helper=helper):
                        if existing:
                            activate.touch()
                        else:
                            activate.unlink(missing_ok=True)
                        result = subprocess.run(['bash', '-c', header + policy_prefix(source) + '\n' + block, 'fixture', 'install'],
                                                env=dict(os.environ, OWNER_STATUS=str(owner), HELPER_STATUS=str(helper)),
                                                text=True, capture_output=True)
                        self.assertEqual('owner' in result.stdout.splitlines(), not existing)
                        self.assertEqual('posthook' in result.stdout.splitlines(), existing or not owner)
                        self.assertEqual(result.returncode, int(bool(helper or (owner and not existing))), result.stdout + result.stderr)

    def test_provision_actual_python_hook(self):
        # Do not synthesize the companion vendor hook: this is this PR's actual
        # hook and its log redirection, independently of merge-order testing.
        source = (ROOT / 'home.admin/_provision.update.sh').read_text()
        line = next(line for line in source.splitlines() if 'blitz.python-trust.sh system-pip' in line)
        line = line.replace('/home/admin/config.scripts/blitz.python-trust.sh', 'python_trust')
        with tempfile.TemporaryDirectory() as temp:
            log = Path(temp) / 'log'
            for status in (0, 1):
                log.unlink(missing_ok=True)
                result = subprocess.run(['bash', '-c', 'python_trust() { echo "$*"; return "$STATUS"; }\n' + line + '\necho NEXT'],
                                        env=dict(os.environ, logFile=str(log), STATUS=str(status)), text=True, capture_output=True)
                self.assertEqual(log.read_text(), 'system-pip /usr/bin/python3\n')
                self.assertEqual(result.returncode, status)
                self.assertEqual('NEXT' in result.stdout, not status)


if __name__ == '__main__':
    unittest.main()
