#!/usr/bin/env python3
"""Exercise the actual installer guards without installing or executing packages.

Run on Debian: python3 test/uv_trust_version_test.py
"""
import os
from pathlib import Path
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = [ROOT / 'home.admin/config.scripts' / name for name in
           ('cl.install.sh', 'cl-plugin.backup.sh')]


class UvTrustVersionTest(unittest.TestCase):
    def test_actual_guards(self):
        cases = {'uv 0.10.4': False, 'uv 0.13.3': False, 'uv 0.13.4': True,
                 'uv 0.13.6 (aarch64-unknown-linux-gnu)': True,
                 'uv 0.14.0': True, 'uv 1.0.0': True,
                 'uv 0.13.6rc1': False, 'uv not-a-version': False, '': False}
        for script in SCRIPTS:
            text = script.read_text()
            start = text.index('  uvVersion=')
            end = text.index('\n  fi', start) + len('\n  fi')
            guard = text[start:end]
            self.assertLess(start, text.index('uv sync'))
            for output, allowed in cases.items():
                with self.subTest(script=script.name, output=output):
                    shell = 'sudo() { printf "%s\\n" "$UV_TEST_OUTPUT"; };\n'
                    shell += guard + '\nprintf "GUARD_ACCEPTED\\n"\n'
                    result = subprocess.run(['bash', '-c', shell], text=True,
                                            capture_output=True,
                                            env={**os.environ, 'UV_TEST_OUTPUT': output})
                    self.assertEqual(result.returncode == 0, allowed, result.stdout + result.stderr)
                    self.assertEqual('GUARD_ACCEPTED' in result.stdout, allowed)

    def test_installers_pin_fixed_release(self):
        cl, backup = (script.read_text() for script in SCRIPTS)
        self.assertIn('cargo install --locked --version 0.13.6 uv', cl)
        self.assertIn('/download/0.13.6/uv-installer.sh', backup)
        self.assertLess(backup.index('  uvVersion='), backup.index('plugin list'))


if __name__ == '__main__':
    unittest.main(verbosity=2)
