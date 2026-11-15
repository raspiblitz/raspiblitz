#!/usr/bin/env python3
"""Command-level TLS regressions using real GNU wget and loopback fixtures.

Never execute installers, real sudo, GPG imports or service operations.
Run test/public-download-tls.sh for syntax/static checks as well.
"""
import http.server
import os
from pathlib import Path
import re
import shlex
import ssl
import subprocess
import tempfile
import threading
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'home.admin/config.scripts'
KEY_SCRIPTS = ['lnd.install.sh', 'lnd.update.sh', 'bonus.pool.sh', 'bonus.chantools.sh']
MODES = ['dns&letsencrypt', 'ip2tor&letsencrypt', 'dns&selfsigned',
         'ip2tor&selfsigned', 'tor', 'localnetwork']


class QuietHandler(http.server.BaseHTTPRequestHandler):
    def handle(self):
        # Certificate rejection can reset the socket before an HTTP request.
        try:
            super().handle()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        self.send_response(500 if self.path.startswith('/http-error') else 200)
        body = b'OTHER' if self.path.startswith('/not-index') else b'INDEX'
        # /partial deliberately sends INDEX but advertises an incomplete body.
        self.send_header('Content-Length', '10' if self.path.startswith('/partial') else str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


class TLSRegression(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.scenarios = []
        version = subprocess.check_output(['wget', '--version'], text=True)
        if not version.startswith('GNU Wget '):
            raise RuntimeError('These regressions require real GNU wget')
        cls.tmp = tempfile.TemporaryDirectory(prefix='download-tls-')
        cls.directory = Path(cls.tmp.name)
        cls.cert = cls.directory / 'cert.pem'
        key = cls.directory / 'key.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048',
                        '-nodes', '-days', '1', '-subj', '/CN=localhost',
                        '-addext', 'subjectAltName=DNS:localhost',
                        '-keyout', str(key), '-out', str(cls.cert)],
                       check=True, capture_output=True)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cls.cert, key)
        cls.server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), QuietHandler)
        cls.server.socket = context.wrap_socket(cls.server.socket, server_side=True)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f'https://localhost:{cls.server.server_port}'
        cls.http = http.server.ThreadingHTTPServer(('127.0.0.1', 0), QuietHandler)
        cls.http_thread = threading.Thread(target=cls.http.serve_forever, daemon=True)
        cls.http_thread.start()

    @classmethod
    def tearDownClass(cls):
        print(f'Executed {len(cls.scenarios)} download/readiness scenarios', flush=True)
        for server, thread in [(cls.server, cls.thread), (cls.http, cls.http_thread)]:
            server.shutdown()
            server.server_close()
            thread.join()
        cls.tmp.cleanup()

    def run_shell(self, code, trusted=False, url=None):
        # Strip only sudo's identity switch. torsocks is a route-recording stub;
        # wget itself always performs the real transfer and TLS verification.
        ca = f'--ca-certificate={shlex.quote(str(self.cert))}' if trusted else ''
        url = shlex.quote(url or self.url)
        prelude = f'''wget() {{ command wget --no-config --no-proxy --timeout=2 --tries=1 {ca} "$@"; }}
sudo() {{ test "$1" = -u && test "$2" = admin || return 99; shift 2; "$@"; }}
torsocks() {{ echo TOR_ROUTE >&2; "$@"; }}
gpg() {{ echo SIGNER_KEY_CONSUMED; }}
PGPpkeys={url}
lndUpdatePGPpkeys={url}
downloadDir={shlex.quote(str(self.directory))}
'''
        env = os.environ.copy()
        # Do not inherit client trust overrides or a real home directory.
        env.update(HOME=str(self.directory), LC_ALL='C')
        for name in ['WGETRC', 'SSL_CERT_FILE', 'SSL_CERT_DIR']:
            env.pop(name, None)
        return subprocess.run(['bash', '-c', prelude + code], cwd=self.directory,
                              env=env, capture_output=True, text=True, timeout=15)

    def download_cases(self):
        return [('untrusted', self.url, False, False),
                ('hostname', self.url.replace('localhost', '127.0.0.1'), True, False),
                ('http-error', self.url + '/http-error', True, False),
                ('partial', self.url + '/partial', True, False),
                ('trusted', self.url, True, True)]

    def check_download(self, command, output):
        # A failed transfer must exit even when stale signer material exists.
        # No `set -e`: this must test the production command's explicit guard.
        for existing in [False, True]:
            for case, url, trusted, success in self.download_cases():
                with self.subTest(existing=existing, case=case):
                    self.scenarios.append(('download', existing, case))
                    output.unlink(missing_ok=True)
                    if existing:
                        output.write_bytes(b'STALE_SIGNER_KEY')
                    code = command + '\ngpg --import ' + shlex.quote(str(output)) + '\necho CONTINUED'
                    result = self.run_shell(code, trusted=trusted, url=url)
                    self.assertEqual(result.returncode, 0 if success else 1, result.stderr)
                    for marker in ['SIGNER_KEY_CONSUMED', 'CONTINUED']:
                        self.assertEqual(marker in result.stdout, success, result.stdout)
                    if success:
                        self.assertEqual(output.read_bytes(), b'INDEX')
                    if case in ['untrusted', 'hostname']:
                        self.assertRegex(result.stderr.lower(), 'certificate|issuer')

    def test_key_downloads(self):
        for name in KEY_SCRIPTS:
            with self.subTest(script=name):
                text = (SCRIPTS / name).read_text()
                commands = [line.strip() for line in text.splitlines()
                            if 'sudo -u admin wget' in line and 'pgp_keys.asc' in line]
                self.assertEqual(len(commands), 1)
                self.check_download(commands[0], self.directory / 'pgp_keys.asc')

    def test_packer_download(self):
        text = (ROOT / 'alternative.platforms/amd64/packer/scripts/init.sh').read_text()
        match = re.search(r'^wget .*?authorized_keys[^\n]*', text, re.M | re.S)
        self.assertIsNotNone(match)
        assert match is not None
        command = match.group()
        original_url = 'https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub'
        self.assertIn(original_url, command)
        # Substitute the fixture variable, not the URL after the TLS options.
        command = command.replace(original_url, '"${PGPpkeys}"')
        output = self.directory / 'authorized_keys'
        command = command.replace('/home/vagrant/.ssh/authorized_keys', str(output))
        self.check_download(command, output)

    def test_sphinx_all_modes(self):
        text = (SCRIPTS / 'bonus.sphinxrelay.sh').read_text()
        block = text[text.index('  connectionTest="n/a"'):text.index('  # check if already an app')]
        for mode in MODES + ['unknown']:
            for route in ['tor', 'direct']:
                cases = [('untrusted', self.url, False, mode.endswith('&selfsigned')),
                         ('hostname', self.url.replace('localhost', '127.0.0.1'), True, mode.endswith('&selfsigned')),
                         ('trusted', self.url, True, True),
                         ('not-index', self.url + '/not-index', True, False),
                         ('http-error', self.url + '/http-error', True, False),
                         ('partial', self.url + '/partial', True, False),
                         ('http', f'http://127.0.0.1:{self.http.server_port}', False, True)]
                for case, url, trusted, success in cases:
                    with self.subTest(mode=mode, route=route, case=case):
                        self.scenarios.append(('sphinx', mode, route, case))
                        code = f'''connection={shlex.quote(mode)}
sphinxrelay_connection={shlex.quote(route)}
publicURL={shlex.quote(url)}
connectionResponse=INDEX
connectionTLS=(--no-check-certificate)
''' + block
                        # Record routing outside the block's redirected stderr.
                        code = 'torsocks() { echo used > route-used; "$@"; }; rm -f route-used\n' + code
                        result = self.run_shell(code, trusted=trusted)
                        self.assertEqual(result.returncode, 0, result.stderr)
                        expected = 'OK' if success else 'fail'
                        self.assertIn(f"connectionTest='{expected}'", result.stdout)
                        self.assertEqual((self.directory / 'route-used').exists(), route == 'tor')


if __name__ == '__main__':
    unittest.main(verbosity=2)
