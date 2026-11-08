#!/usr/bin/env python3
"""Destructive ONLY inside the disposable python-trust.Dockerfile container.

Run via docker run --rm --network=none --cap-drop=ALL IMAGE. No host mounts.
Writes the container's /usr/local and synthetic CA fixture, never the host's.
"""
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'home.admin/config.scripts/blitz.python-trust.sh'


class DebianSystem(unittest.TestCase):
    def test_actual_system_pip_and_entrypoints(self):
        self.assertTrue(Path('/.dockerenv').exists(), 'Refusing system writes outside Docker')
        self.assertEqual(sys.executable, '/usr/bin/python3')
        original = Path('/usr/lib/python3/dist-packages/pip')
        before = {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                  for path in original.rglob('*') if path.is_file()}
        self.assertTrue(before)
        externally_managed = Path('/usr/lib/python3.11/EXTERNALLY-MANAGED')
        marker = externally_managed.read_bytes()
        ca = Path('/clean.pem')
        with zipfile.ZipFile('/wheels/pip-26.2.2-py3-none-any.whl') as wheel:
            ca.write_bytes(wheel.read('pip/_vendor/certifi/cacert.pem'))
        env = {key: value for key, value in os.environ.items()
               if key not in ('REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE', 'PIP_CERT', 'SSL_CERT_FILE', 'SSL_CERT_DIR')}
        command = ['bash', str(HELPER), 'system-pip', '/usr/bin/python3', str(ca)]
        for attempt in range(2):
            result = subprocess.run(command, env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('Python trust bundle check passed', result.stdout)
            probe = subprocess.check_output(['/usr/bin/python3', '-c',
                'import pip; print(pip.__version__); print(pip.__file__)'], env=env, text=True)
            self.assertEqual(probe.splitlines(), ['26.2.2', '/usr/local/lib/python3.11/dist-packages/pip/__init__.py'])
            for entry in ('pip', 'pip3', 'pip3.11'):
                path = Path('/usr/local/bin') / entry
                self.assertEqual(path.stat().st_mode & 0o777, 0o755)
                self.assertIn('pip 26.2.2', subprocess.check_output([str(path), '--version'], env=env, text=True))
            self.assertEqual(before, {str(path): hashlib.sha256(path.read_bytes()).hexdigest()
                                     for path in original.rglob('*') if path.is_file()})
            self.assertEqual(externally_managed.read_bytes(), marker)
        print(f'Debian system-pip: two successful runs; {len(before)} distribution files unchanged; three entrypoints verified')


if __name__ == '__main__':
    unittest.main()
