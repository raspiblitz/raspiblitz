#!/usr/bin/env python3
"""Real isolated pip installs. Requires Python >=3.10 and HTTPS access to PyPI.

Run with Python 3.10 or 3.11 (pip 23.0.1 predates Python 3.12):
python3.11 -m unittest discover -s tests -p 'test_python_trust_bootstrap.py' -v
No services, SSH, or system package writes in this suite. The separate
python-trust-system.py test requires the disposable Debian Docker fixture.
"""
import contextlib
import http.server
import json
import ssl
import threading
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / 'home.admin/config.scripts/blitz.python-trust.sh'


def clean_environment():
    return {key: value for key, value in os.environ.items()
            if not key.startswith('PIP_') and key not in
            ('REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE', 'SSL_CERT_FILE', 'SSL_CERT_DIR')}


def policy_prefix(source):
    return source[source.index('pip_sudo=('):source.index('done < <(compgen -e)') + len('done < <(compgen -e)')]


def reset_sudo(path, policy, probe=False):
    """Model sudo env_reset, then execute real commands, with no privileges."""
    shim = path / 'sudo-reset.py'
    shim.write_text('import os, subprocess, sys\n' +
                    'args = sys.argv[1:]\nnames = []\n' +
                    "while args and args[0].startswith('-'):\n" +
                    '    option = args.pop(0)\n' +
                    "    if option == '-u': args.pop(0)\n" +
                    "    elif option.startswith('--preserve-env='): names.extend(option.split('=', 1)[1].split(','))\n" +
                    "    elif option != '-H': raise SystemExit('Unexpected sudo option')\n" +
                    'expected = ' + repr(policy) + '\n' +
                    "assert set(names) == set(expected), 'Download policy whitelist differs'\n" +
                    "env = {'PATH': '/usr/bin:/bin', 'HOME': " + repr(str(path)) + '}\n' +
                    'for name in names:\n' +
                    "    assert os.environ[name] == expected[name], 'Download policy value differs'\n" +
                    '    env[name] = os.environ[name]\n' +
                    "assert not any(name in env for name in ('PYTHONPATH', 'PYTHONHOME', 'BASH_ENV', 'UNRELATED_SECRET'))\n" +
                    'sys.exit(subprocess.call(' + ("[\'/usr/bin/true\']" if probe else 'args') + ', env=env))\n')
    return f'{shlex.quote(sys.executable)} -E {shlex.quote(str(shim))}'


class Bootstrap(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.base = Path(cls.tmp.name)
        cls.env = clean_environment()
        cls.env.update(PIP_CONFIG_FILE=os.devnull, PIP_DISABLE_PIP_VERSION_CHECK='1', PIP_NO_CACHE_DIR='1')
        cls.wheels = cls.base / 'wheels'
        cls.wheels.mkdir()
        for version in ('23.0.1', '26.0.1', '26.2.2'):
            cls.run_cmd([sys.executable, '-m', 'pip', 'download', '--no-deps',
                         '--dest', str(cls.wheels), 'pip==' + version])
        for version in ('2025.4.26', '2026.10.19'):
            cls.run_cmd([sys.executable, '-m', 'pip', 'download', '--no-deps',
                         '--dest', str(cls.wheels), 'certifi==' + version])
        cls.ca = cls.base / 'clean.pem'
        cls.bad_ca = cls.base / 'affected.pem'
        for version, dest in (('26.2.2', cls.ca), ('26.0.1', cls.bad_ca)):
            with zipfile.ZipFile(cls.wheels / f'pip-{version}-py3-none-any.whl') as wheel:
                dest.write_bytes(wheel.read('pip/_vendor/certifi/cacert.pem'))
        cls.env.update(PIP_NO_INDEX='1', PIP_FIND_LINKS=str(cls.wheels))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    @classmethod
    def run_cmd(cls, args, env=None, ok=True):
        proc = subprocess.run(args, env=env or cls.env, text=True, capture_output=True)
        if ok and proc.returncode:
            raise AssertionError(f'{args}\n{proc.stdout}\n{proc.stderr}')
        return proc

    def venv(self, version):
        path = self.base / self.id().split('.')[-1]
        self.run_cmd([sys.executable, '-m', 'venv', str(path)])
        python = path / 'bin/python'
        self.run_cmd([str(python), '-m', 'pip', 'install', 'pip==' + version])
        return python

    def helper(self, python, ca=None, env=None, mode='pip'):
        return self.run_cmd(['bash', str(HELPER), mode, str(python), str(ca or self.ca)],
                            env=env, ok=False)

    def test_missing_pip_fails_before_download(self):
        path = self.base / 'without-pip'
        self.run_cmd([sys.executable, '-m', 'venv', '--without-pip', str(path)])
        result = self.helper(path / 'bin/python')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No module named 'pip'", result.stderr)
        self.assertNotIn('Collecting', result.stdout)

    def test_download_transport_failure(self):
        python = self.venv('23.0.1')
        # A bound but non-listening local socket guarantees no external contact.
        import socket
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            env = dict(self.env, PIP_FIND_LINKS=f'https://127.0.0.1:{sock.getsockname()[1]}/pip-26.2.2-py3-none-any.whl',
                       PIP_RETRIES='0', PIP_TIMEOUT='1', NO_PROXY='127.0.0.1')
            result = self.helper(python, env=env)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Connection refused', result.stdout + result.stderr)
        self.assertIn('23.0.1', self.run_cmd([str(python), '-m', 'pip', '--version']).stdout)

    def test_insecure_download_policy_refused(self):
        python = self.venv('26.0.1')
        for policy, message in (({'PIP_TRUSTED_HOST': 'localhost'}, 'trusted-host'),
                                ({'PIP_FIND_LINKS': 'http://127.0.0.1:1/pip.whl'}, 'requires HTTPS'),
                                ({'PIP_NO_INDEX': '0', 'PIP_INDEX_URL': 'http://127.0.0.1:1/simple'}, 'requires HTTPS'),
                                ({'PIP_NO_INDEX': '0', 'PIP_EXTRA_INDEX_URL': 'http://127.0.0.1:1/simple'}, 'requires HTTPS')):
            with self.subTest(policy=policy):
                result = self.helper(python, env=dict(self.env, **policy))
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(message, result.stderr)
                self.assertNotIn('Collecting', result.stdout)

    def test_app_missing_and_affected_certifi(self):
        python = self.venv('26.2.2')
        result = self.helper(python, mode='app')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("No module named 'certifi'", result.stderr)
        site = Path(self.run_cmd([str(python), '-c', 'import sysconfig; print(sysconfig.get_path("purelib"))']).stdout.strip())
        with zipfile.ZipFile(self.wheels / 'certifi-2025.4.26-py3-none-any.whl') as wheel:
            for name in wheel.namelist():
                if name.startswith('certifi/') and not name.endswith('/'):
                    dest = site / name
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(wheel.read(name))
        result = self.helper(python, mode='app')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Affected emSign anchor', result.stderr)

    def test_actual_pip23_fresh_venv(self):
        python = self.venv('23.0.1')
        result = self.helper(python)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('26.2.2', self.run_cmd([str(python), '-m', 'pip', '--version']).stdout)

    def test_standalone_helper_trust_gate(self):
        source = (ROOT / 'build_sdcard.sh').read_text()
        gate = source.split("/usr/bin/python3 - <<'PY' || exit 1\n", 1)[1].split('\nPY\n', 1)[0]
        for bundle, accepted in ((self.ca, True), (self.bad_ca, False)):
            code = gate.replace('"/etc/ssl/certs/ca-certificates.crt"', repr(str(bundle)))
            result = self.run_cmd([sys.executable, '-c', code], ok=False)
            self.assertEqual(result.returncode == 0, accepted, result.stderr)

    def test_rich_toolkit_override_preserves_configured_policy(self):
        source = (ROOT / 'home.admin/config.scripts/blitz.web.api.sh').read_text()
        line = next(line for line in source.splitlines() if 'rich-toolkit==0.14.6' in line)
        tokens = shlex.split(line)
        overrides = {}
        for token in tokens[tokens.index('env') + 1:]:
            if '=' not in token:
                break
            key, value = token.split('=', 1)
            overrides[key] = value
        self.assertNotIn('PIP_CONFIG_FILE', overrides)
        self.assertEqual(overrides['PIP_EXTRA_INDEX_URL'], ' ')
        config = self.base / 'operator-policy.conf'
        constraints = self.base / 'operator-policy-constraints.txt'
        constraints.write_text('pip==26.0.1\n')
        content = ('[global]\nindex-url = https://mirror.example.invalid/simple\n'
                   'extra-index-url = https://www.piwheels.org/simple\n'
                   f'constraint = {constraints}\ncert = {self.ca}\n')
        config.write_text(content)
        env = {key: value for key, value in os.environ.items() if not key.startswith('PIP_')}
        env.update(PIP_CONFIG_FILE=str(config), PIP_DISABLE_PIP_VERSION_CHECK='1')
        python = self.venv('26.0.1')
        probe = ('import json;from pip._internal.commands import create_command;'
                 'o,_=create_command("install").parse_args([]);'
                 'print(json.dumps([o.index_url,o.extra_index_urls,o.constraints,o.cert]))')
        effective = dict(env, **overrides)
        options = json.loads(self.run_cmd([str(python), '-c', probe], env=effective).stdout)
        self.assertEqual(options, ['https://pypi.org/simple', [], [str(constraints)], str(self.ca)])
        result = self.run_cmd([str(python), '-m', 'pip', 'install', '--no-index',
                               '--find-links', str(self.wheels), 'pip==26.2.2'],
                              env=effective, ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('conflict', (result.stdout + result.stderr).lower())
        restored = json.loads(self.run_cmd([str(python), '-c', probe], env=env).stdout)
        self.assertEqual(restored[:2], ['https://mirror.example.invalid/simple',
                                       ['https://www.piwheels.org/simple']])
        self.assertEqual(config.read_text(), content)
        start = source.index('  # Keep the rich-toolkit PyPI workaround')
        end = source.index('  if ! "${pip_sudo[@]}" ./venv/bin/pip install --no-cache-dir -r requirements.txt', start)
        block = source[start:end]
        self.assertNotIn('/etc/pip.conf', block)
        failure = self.run_cmd(['bash', '-c', 'pip_sudo=(sudo)\nsudo() { return 1; }\n' +
                                block + '\necho NEXT_PACKAGE\n'], ok=False)
        self.assertEqual(failure.returncode, 1)
        self.assertNotIn('NEXT_PACKAGE', failure.stdout)

    def test_actual_modern_pip26(self):
        result = self.helper(self.venv('26.0.1'))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_https_bootstrap_pip23(self):
        python = self.venv('23.0.1')
        env = {k: v for k, v in self.env.items() if k not in ('PIP_NO_INDEX', 'PIP_FIND_LINKS')}
        result = self.helper(python, env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_https_bootstrap_modern(self):
        python = self.venv('26.0.1')
        env = {k: v for k, v in self.env.items() if k not in ('PIP_NO_INDEX', 'PIP_FIND_LINKS')}
        result = self.helper(python, env=env)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    @contextlib.contextmanager
    def https_wheel(self):
        path = self.base / (self.id().split('.')[-1] + '-https')
        path.mkdir()
        config = path / 'openssl.cnf'
        config.write_text('[req]\ndistinguished_name=dn\nx509_extensions=ext\nprompt=no\n'
                          '[dn]\nCN=localhost\n[ext]\nbasicConstraints=critical,CA:TRUE\n'
                          'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\n'
                          'extendedKeyUsage=serverAuth\nsubjectKeyIdentifier=hash\n'
                          'authorityKeyIdentifier=keyid:always\nsubjectAltName=DNS:localhost\n')
        cert, key = path / 'ca.pem', path / 'key.pem'
        self.run_cmd(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                      '-days', '1', '-config', str(config), '-out', str(cert), '-keyout', str(key)])
        wheel = self.wheels / 'pip-26.2.2-py3-none-any.whl'
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                body = wheel.read_bytes()
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def log_message(self, format, *args):
                pass

        server = http.server.ThreadingHTTPServer(('localhost', 0), Handler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        server.socket = context.wrap_socket(server.socket, server_side=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        env = dict(self.env, PIP_FIND_LINKS=f'https://localhost:{server.server_port}/{wheel.name}',
                   PIP_NO_CACHE_DIR='1', NO_PROXY='localhost', no_proxy='localhost')
        try:
            yield cert, env, requests
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_https_explicit_ca_precedence(self):
        python = self.venv('23.0.1')
        with self.https_wheel() as (cert, env, requests):
            config = self.base / 'https-cert.conf'
            # The public fallback bundle cannot authenticate this private server.
            negative = self.helper(python, env=dict(env, PIP_RETRIES='0'))
            self.assertNotEqual(negative.returncode, 0)
            self.assertIn('CERTIFICATE_VERIFY_FAILED', negative.stdout + negative.stderr)
            self.assertEqual(requests, [])
            for version in ('23.0.1', '26.0.1'):
                for selected in ('REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE', 'PIP_CERT', 'config', 'SSL_CERT_FILE', 'argument'):
                    with self.subTest(version=version, selected=selected):
                        self.run_cmd([str(python), '-m', 'pip', 'install', 'pip==' + version])
                        config.write_text('[global]\ncert = ' + str(cert if selected == 'config' else self.ca) + '\n')
                        policy = dict(env, PIP_CONFIG_FILE=str(config))
                        if selected in ('REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE', 'PIP_CERT'):
                            policy[selected] = str(cert)
                            policy['SSL_CERT_FILE'] = str(self.ca)
                            if selected == 'CURL_CA_BUNDLE':
                                policy['REQUESTS_CA_BUNDLE'] = ''
                        elif selected in ('SSL_CERT_FILE', 'argument'):
                            config.write_text('[global]\n')
                            if selected == 'SSL_CERT_FILE':
                                policy[selected] = str(cert)
                                policy.update(REQUESTS_CA_BUNDLE='', CURL_CA_BUNDLE='', PIP_CERT='')
                        if selected == 'REQUESTS_CA_BUNDLE':
                            policy['CURL_CA_BUNDLE'] = str(self.ca)
                        before = len(requests)
                        result = self.helper(python, ca=cert if selected == 'argument' else self.ca, env=policy)
                        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertGreater(len(requests), before)
                        self.assertIn('26.2.2', self.run_cmd([str(python), '-m', 'pip', '--version']).stdout)

    def test_explicit_unsafe_ca_refused_before_https(self):
        python = self.venv('26.0.1')
        malformed = self.base / 'broken-ca.pem'
        malformed.write_text('not a certificate\n')
        marker = python.parent / 'pip-download-invoked'
        wrapper = python.parent / 'precheck-python'
        wrapper.write_text('#!/bin/bash\nif [ "$1" = -m ] && [ "$2" = pip ]; then\n'
                           'touch ' + shlex.quote(str(marker)) + '\nfi\nexec ' +
                           shlex.quote(str(python)) + ' "$@"\n')
        wrapper.chmod(0o755)
        with self.https_wheel() as (cert, env, requests):
            for source in ('REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE', 'PIP_CERT', 'config', 'SSL_CERT_FILE'):
                for bad in (self.bad_ca, malformed, self.base / 'missing-ca.pem', self.base):
                    with self.subTest(source=source, bad=bad):
                        policy = dict(env, REQUESTS_CA_BUNDLE=str(cert))
                        if source == 'config':
                            config = self.base / 'bad-cert.conf'
                            config.write_text('[global]\ncert = ' + str(bad) + '\n')
                            policy['PIP_CONFIG_FILE'] = str(config)
                        else:
                            policy[source] = str(bad)
                        marker.unlink(missing_ok=True)
                        result = self.helper(wrapper, env=policy)
                        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertFalse(marker.exists(), 'pip download invoked before CA refusal')
                        self.assertEqual(requests, [])
                        self.assertIn('26.0.1', self.run_cmd([str(python), '-m', 'pip', '--version']).stdout)

    def test_explicit_ca_postconditions(self):
        python = self.venv('26.2.2')
        # Use the standalone wheel: vendored certifi.core refers back to pip's
        # package resources even when copied to a top-level certifi directory.
        site = Path(self.run_cmd([str(python), '-c', 'import sysconfig; print(sysconfig.get_path("purelib"))']).stdout.strip())
        with zipfile.ZipFile(self.wheels / 'certifi-2026.10.19-py3-none-any.whl') as wheel:
            for name in wheel.namelist():
                if name.startswith('certifi/') and not name.endswith('/'):
                    dest = site / name
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(wheel.read(name))
        clean_app = self.helper(python, mode='app')
        self.assertEqual(clean_app.returncode, 0, clean_app.stdout + clean_app.stderr)
        override = self.base / 'postcheck.pem'
        for source in ('REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE', 'PIP_CERT', 'config', 'SSL_CERT_FILE'):
            for bad in (self.bad_ca.read_text(), 'broken certificate\n'):
                for mode in ('app', 'pip'):
                    with self.subTest(source=source, bad=bad[:20], mode=mode):
                        policy = dict(self.env)
                        if source == 'config':
                            config = self.base / 'postcheck.conf'
                            config.write_text('[global]\ncert = ' + str(override) + '\n')
                            policy['PIP_CONFIG_FILE'] = str(config)
                        else:
                            policy[source] = str(override)
                        wrapper = python.parent / 'postcheck-python'
                        if mode == 'pip':
                            override.write_bytes(self.ca.read_bytes())
                            # Mutation at install boundary forces the actual pip postcheck
                            # (not merely the pre-download validation) to reject the file.
                            payload = self.base / 'postcheck-input.pem'
                            payload.write_text(bad)
                            wrapper.write_text('#!/bin/bash\nif [ "$1" = -m ] && [ "$2" = pip ]; then\n'
                                               'cp ' + shlex.quote(str(payload)) + ' ' + shlex.quote(str(override)) +
                                               '\nexit $?\nfi\nexec ' + shlex.quote(str(python)) + ' "$@"\n')
                            wrapper.chmod(0o755)
                        else:
                            override.write_text(bad)
                        result = self.helper(wrapper if mode == 'pip' else python, env=policy, mode=mode)
                        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
                        self.assertEqual(override.read_text(), bad)
                        self.assertIn('Affected emSign anchor' if 'BEGIN CERTIFICATE' in bad
                                      else 'No trust anchors found', result.stderr)

    def test_postcondition_rejects_unchanged_affected_pip(self):
        python = self.venv('26.0.1')
        wrapper = python.parent / 'no-op-installer'
        wrapper.write_text('#!/bin/bash\nif [ "$1" = -m ] && [ "$2" = pip ]; then exit 0; fi\nexec '
                           + repr(str(python)) + ' "$@"\n')
        wrapper.chmod(0o755)
        result = self.helper(wrapper)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Affected emSign anchor', result.stderr)

    def test_debian_scheme_selection(self):
        source = HELPER.read_text().split('local_packages=$("$python" - <<\'PY\'\n', 1)[1].split('\nPY', 1)[0]
        # Exercise production scheme selection without touching Linux or /usr/local.
        prefix = ('import sys, pathlib; sys.platform="linux"; sys.prefix=sys.base_prefix; '
                  'sys.path.insert(0, f"/usr/local/lib/python{sys.version_info.major}.{sys.version_info.minor}/dist-packages"); '
                  'pathlib.Path.is_file=lambda self: str(self)=="/etc/debian_version";\n')
        result = self.run_cmd([sys.executable, '-c', prefix + source])
        self.assertEqual(result.stdout.strip(), f'/usr/local/lib/python{sys.version_info.major}.{sys.version_info.minor}/dist-packages')
        self.assertNotIn('/usr/local/local/', result.stdout)

    def test_constraint_fails_closed(self):
        python = self.venv('26.0.1')
        constraint = self.base / 'constraints.txt'
        constraint.write_text('pip==26.0.1\n')
        result = self.helper(python, env=dict(self.env, PIP_CONSTRAINT=str(constraint)))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('26.0.1', self.run_cmd([str(python), '-m', 'pip', '--version']).stdout)

    def test_outer_update_constraints_stop_restart(self):
        python = self.venv('26.0.1')
        path = python.parent.parent
        source = (ROOT / 'home.admin/config.scripts/blitz.web.api.sh').read_text()
        block = source[source.index('if [ "$1" = "update-code" ]; then'):]
        block = block[:block.index('\n###################')]
        block = block.replace('/home/blitzapi/blitz_api', str(path))
        block = block.replace('ls /etc/systemd/system/blitzapi.service', 'printf blitzapi.service')
        block = block.replace('/home/admin/config.scripts/blitz.python-trust.sh',
                              'bash ' + shlex.quote(str(HELPER)))
        block = block.replace('./venv/bin/python', './venv/bin/python ' + shlex.quote(str(self.ca)))
        block = block.replace('./venv/bin/', shlex.quote(str(python.parent)) + '/')
        constraint = path / 'constraint.txt'
        policy = {k: v for k, v in self.env.items() if k.startswith('PIP_')}
        policy.update(PIP_CONSTRAINT=str(constraint), REQUESTS_CA_BUNDLE=str(self.ca),
                      CURL_CA_BUNDLE=str(self.ca), SSL_CERT_FILE=str(self.ca), SSL_CERT_DIR=str(path))
        runner = reset_sudo(path, policy)
        header = '''
systemctl() { echo "service $*"; }
sudo() {
  if [ "$1" = chown ]; then return 0; fi
  if [ "$3" = git ]; then
    if [ "$4" = rev-parse ]; then
      if [ -f marker ]; then echo new; else touch marker; echo old; fi
    fi
    return 0
  fi
  ''' + runner + ''' "$@"
}
'''
        # Real helper conflict, then successful helper and real requirements conflict.
        for helper_failure in (True, False):
            (path / 'marker').unlink(missing_ok=True)
            constraint.write_text('pip==26.0.1\n' if helper_failure else 'pip==26.2.2\n')
            (path / 'requirements.txt').write_text('pip==26.0.1\n')
            result = subprocess.run(['bash', '-c', header + policy_prefix(source) + '\n' + block,
                                     'test', 'update-code', 'main'],
                                    env=dict(clean_environment(), **policy, UNRELATED_SECRET='do-not-forward'),
                                    text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('ResolutionImpossible', result.stdout + result.stderr)
            self.assertIn('service stop ', result.stdout)
            self.assertNotIn('service start ', result.stdout)
            self.assertEqual('Code changed, updating dependencies' in result.stdout, not helper_failure)

    def test_stale_index_fails_closed(self):
        python = self.venv('23.0.1')
        stale = self.base / 'stale'
        stale.mkdir()
        shutil.copy(self.wheels / 'pip-23.0.1-py3-none-any.whl', stale)
        result = self.helper(python, env=dict(self.env, PIP_FIND_LINKS=str(stale)))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('23.0.1', self.run_cmd([str(python), '-m', 'pip', '--version']).stdout)

    def test_affected_bootstrap_refused(self):
        result = self.helper(self.venv('26.0.1'), ca=self.bad_ca)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Affected emSign anchor', result.stderr)
        self.assertNotIn('Successfully installed', result.stdout)

    def test_old_opt_in_truststore_refused(self):
        result = self.helper(self.venv('23.0.1'), env=dict(self.env, PIP_USE_FEATURE='truststore'))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('opt-in truststore', result.stderr)

    def test_unsupported_python(self):
        # Run the actual production version guard under a synthetic old version.
        source = HELPER.read_text().split('  "$python" - <<\'PY\'\n', 1)[1].split('\nPY', 1)[0]
        result = self.run_cmd([sys.executable, '-c',
                               'import sys; sys.version_info=(3,9,0);\n' + source], ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Python >=3.10', result.stderr)

    def test_system_mode_rejects_venv(self):
        result = self.helper(self.venv('26.0.1'), mode='system-pip')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('system-pip requires Debian system Python', result.stderr)

    def test_target_preserves_existing_pip_and_generates_entrypoints(self):
        python = self.venv('23.0.1')
        target = self.base / 'local/lib/python3/dist-packages'
        # Same installation primitive as production, isolated from /usr/local.
        self.run_cmd([str(python), '-m', 'pip', 'install', '--upgrade', '--target', str(target), 'pip>=26.2.2'])
        self.assertIn('23.0.1', self.run_cmd([str(python), '-m', 'pip', '--version']).stdout)
        self.assertTrue((target / 'bin/pip3').is_file())
        result = self.run_cmd([str(python), '-c', 'import pip; print(pip.__version__)'],
                              env=dict(self.env, PYTHONPATH=str(target)))
        self.assertEqual(result.stdout.strip(), '26.2.2')
        helper = HELPER.read_text()
        self.assertNotIn('--prefix=', helper.split('target=(')[-1])
        self.assertNotIn('--break-system-packages', helper)


class RestartPaths(unittest.TestCase):
    def test_joininbox_verified_release_gate_before_owner(self):
        source = (ROOT / 'home.admin/config.scripts/bonus.joinmarket.sh').read_text()
        start = source.index('    # The late pip posthook')
        end = source.index('    echo "# Set ssh access off', start)
        self.assertLess(source.index('"${PGPpubkeyFingerprint}" "${JBTAG}" || exit 1'), start)
        self.assertLess(source.index('cp /home/joinmarket/joininbox/scripts/*'), start)
        self.assertLess(end, source.index('"${pip_sudo[@]}" /home/joinmarket/install.joinmarket.sh'))
        self.assertIn('JBTAG="v0.9.0"', source)
        hooks = ('  "${trust_sudo[@]}" python3 "${trust_scripts}/joinmarket-python-trust.py" prerequisites || exit 1\n'
                 '  "${trust_sudo[@]}" patch --batch --forward --fuzz=0 -p1 < "${trust_scripts}/joinmarket-python-trust.patch" || exit 1\n'
                 '  sudo -u "${user}" cp "${trust_scripts}/joinmarket-python-trust.py" install-python-trust.py || exit 1\n')
        names = ('install.joinmarket.sh', 'joinmarket-python-trust.py', 'joinmarket-python-trust.patch')
        for case in ('legacy', 'untracked-helpers', 'untracked-new-installer', 'no-hooks',
                     'commented-hooks', 'copied-tamper', 'missing-copy', 'reviewed'):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as temp:
                home = Path(temp)
                repo = home / 'joininbox'
                scripts = repo / 'scripts'
                scripts.mkdir(parents=True)
                legacy = case in ('legacy', 'untracked-helpers', 'untracked-new-installer')
                installer = '#!/bin/bash\n' + (hooks if not legacy and case != 'no-hooks' else 'exit 0\n')
                if case == 'commented-hooks':
                    installer = '#!/bin/bash\n' + ''.join('#' + line + '\n' for line in hooks.splitlines())
                (scripts / names[0]).write_text(installer)
                if not legacy:
                    (scripts / names[1]).write_text('# mock owner helper\n')
                    (scripts / names[2]).write_text('# mock archived installer backport\n')

                def git(*args):
                    result = subprocess.run(['git', '-c', 'user.name=Trust Fixture',
                                             '-c', 'user.email=fixture@example.invalid', *args],
                                            cwd=repo, text=True, capture_output=True)
                    self.assertEqual(result.returncode, 0, result.stderr)

                git('init', '-q')
                git('add', 'scripts')
                git('commit', '-qm', 'Synthetic release gate fixture')
                git('tag', 'v0.9.0')
                if case in ('untracked-helpers', 'untracked-new-installer'):
                    (scripts / names[1]).write_text('# stale untracked helper\n')
                    (scripts / names[2]).write_text('# stale untracked backport\n')
                    if case == 'untracked-new-installer':
                        (scripts / names[0]).write_text('#!/bin/bash\n' + hooks)
                for file in scripts.iterdir():
                    shutil.copy(file, home / file.name)
                if case == 'copied-tamper':
                    (home / names[1]).write_text('# different helper\n')
                elif case == 'missing-copy':
                    (home / names[2]).unlink()
                gate = source[start:end].replace('/home/joinmarket', str(home))
                # Existing signature verification is an earlier owner boundary;
                # this tests the real gate using real Git refs and copied files.
                header = 'JBTAG=v0.9.0\nsudo() { shift 2; "$@"; }\n'
                result = subprocess.run(['bash', '-c', header + gate + '\necho OWNER_INVOKED\n'],
                                        text=True, capture_output=True)
                accepted = case == 'reviewed'
                self.assertEqual(result.returncode == 0, accepted, result.stdout + result.stderr)
                self.assertEqual('OWNER_INVOKED' in result.stdout, accepted)
                if not accepted:
                    self.assertIn('maintained signed JoininBox release', result.stderr)

    def test_download_policy_at_every_outer_boundary(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            policy = {name: 'policy with spaces\nand punctuation=;'
                      for name in ('PIP_CONSTRAINT', 'PIP_BUILD_CONSTRAINT', 'PIP_CERT',
                                   'PIP_FUTURE_SETTING', 'REQUESTS_CA_BUNDLE', 'CURL_CA_BUNDLE',
                                   'SSL_CERT_FILE', 'SSL_CERT_DIR')}
            runner = reset_sudo(path, policy, probe=True)
            for file, expected in (('build_sdcard.sh', 5),
                                   ('home.admin/config.scripts/blitz.web.api.sh', 8),
                                   ('home.admin/config.scripts/bonus.joinmarket.sh', 2)):
                source = (ROOT / file).read_text()
                # Run every production prefix invocation; command side effects
                # alone are replaced. Sudo's reset strips all non-policy vars.
                lines = [line for line in source.splitlines() if '"${pip_sudo[@]}"' in line]
                self.assertEqual(len(lines), expected)
                self.assertNotRegex(source, r'sudo -(?:u (?:blitzapi|joinmarket)|H) (?:[^\n]*blitz.python-trust|[^\n]* -m pip|\./venv/bin/pip|/home/joinmarket/install.joinmarket)')
                for line in lines:
                    command = line[line.index('"${pip_sudo[@]}"'):].split('; then', 1)[0].split(' ||', 1)[0].split(' >', 1)[0].rstrip('\\; ')
                    header = 'sudo() { ' + runner + ' "$@"; }\n'
                    result = subprocess.run(['bash', '-c', header + policy_prefix(source) + '\n' + command],
                                            env=dict(clean_environment(), **policy, PYTHONPATH='not-forwarded',
                                                     PYTHONHOME='not-forwarded', UNRELATED_SECRET='not-forwarded'),
                                            capture_output=True, text=True)
                    self.assertEqual(result.returncode, 0, file + ': ' + result.stdout + result.stderr)
                    self.assertNotIn('policy with spaces', result.stdout + result.stderr)

    def test_update_paths(self):
        # Execute the production update block, replacing external state only.
        source = (ROOT / 'home.admin/config.scripts/blitz.web.api.sh').read_text()
        block = source[source.index('if [ "$1" = "update-code" ]; then'):]
        block = block[:block.index('\n###################')]
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            block = block.replace('/home/blitzapi/blitz_api', temp)
            block = block.replace('ls /etc/systemd/system/blitzapi.service', 'printf blitzapi.service')
            header = '''
currentBranch=main
systemctl() {
  printf 'service %s\\n' "$*"
  [ "$1" != "$FAIL_COMMAND" ]
}
sudo() {
  shift 2
  while [[ "$1" = --preserve-env=* ]]; do shift; done
  if [ "$1" = git ]; then
    echo "git $2" >&2
    [ "$2" != "$FAIL_COMMAND" ] || return 1
    if [ "$FAIL_COMMAND" = rev-parse-new ] && [ "$2" = rev-parse ] && [ -f "$MARKER" ]; then
      echo git rev-parse-new >&2
      return 1
    fi
    case "$2" in
      show-ref) return "$BRANCH_STATUS" ;;
      rev-parse)
        if [ "$CHANGE" = 1 ]; then
          if [ -f "$MARKER" ]; then echo changed; else touch "$MARKER"; echo old; fi
        else echo "$COMMIT"; fi ;;
    esac
  elif [[ "$1" = *blitz.python-trust.sh ]]; then
    echo "check $2"
    if [ "$2" = "$FAIL_CHECK" ]; then return 1; fi
  elif [[ "$1" = *venv/bin/pip ]]; then
    echo dependencies
    return "$INSTALL_STATUS"
  fi
  return 0
}
'''
            cases = [(branch, failure, change, install, starts, '')
                     for branch, failure, change, install, starts in (
                         (1, '', 0, 0, False), (0, 'pip', 0, 0, False),
                         (0, 'app', 0, 0, False), (0, '', 0, 0, True),
                         (0, '', 1, 1, False), (0, 'app', 1, 0, False),
                         (0, '', 1, 0, True))]
            cases += [(0, '', 0, 0, command == 'start', command)
                      for command in ('stop', 'fetch', 'reset', 'rev-parse', 'start')]
            cases.append((0, '', 1, 0, False, 'rev-parse-new'))
            for branch, failure, change, install_status, starts, command in cases:
                with self.subTest(branch=branch, failure=failure, change=change, command=command):
                    marker = path / 'rev-parse-called'
                    marker.unlink(missing_ok=True)
                    env = dict(os.environ, BRANCH_STATUS=str(branch), FAIL_CHECK=failure,
                               COMMIT='unchanged', INSTALL_STATUS=str(install_status),
                               CHANGE=str(change), MARKER=str(marker), FAIL_COMMAND=command)
                    result = subprocess.run(['bash', '-c', header + policy_prefix(source) + '\n' + block, 'test', 'update-code', 'main'],
                                            env=env, capture_output=True, text=True)
                    self.assertEqual('service start ' in result.stdout, starts, result.stdout + result.stderr)
                    self.assertEqual(result.returncode == 0, starts and not command, result.stdout + result.stderr)
                    self.assertIn('service stop blitzapi blitzapi-celery-worker blitzapi-celery-beat', result.stdout)
                    if command:
                        self.assertIn('service ' + command if command in ('stop', 'start') else 'git ' + command,
                                      result.stdout + result.stderr)
                    if command == 'stop':
                        self.assertNotIn('git ', result.stderr)
                        self.assertNotIn('check ', result.stdout)
                    if starts:
                        self.assertLess(result.stdout.index('check pip'), result.stdout.index('check app'))
                        self.assertLess(result.stdout.index('check app'), result.stdout.index('service start'))
                        self.assertEqual('dependencies' in result.stdout, bool(change))
            # Cover absent service and branch inference without fabricating an
            # active installation or silently defaulting to an arbitrary branch.
            env = dict(os.environ, BRANCH_STATUS='0', FAIL_CHECK='', COMMIT='unchanged',
                       INSTALL_STATUS='0', CHANGE='0', MARKER=str(path / 'inferred'), FAIL_COMMAND='')
            for command in ('', 'rev-parse'):
                env['FAIL_COMMAND'] = command
                result = subprocess.run(['bash', '-c', header.replace('currentBranch=main', 'currentBranch=') +
                                         policy_prefix(source) + '\n' + block, 'test', 'update-code', ''],
                                        env=env, text=True, capture_output=True)
                self.assertEqual(result.returncode, int(bool(command)), result.stdout + result.stderr)
                if not command:
                    self.assertIn('# BRANCH ---> unchanged', result.stdout)
                else:
                    self.assertNotIn('git fetch', result.stderr)
            result = subprocess.run(['bash', '-c', header + policy_prefix(source) + '\n' +
                                     block.replace('printf blitzapi.service', 'true'), 'test', 'update-code', 'main'],
                                    env=env, text=True, capture_output=True)
            self.assertEqual(result.returncode, 1)
            self.assertIn('blitzapi not active', result.stdout)
            self.assertNotIn('service stop', result.stdout)
            self.assertNotIn('check ', result.stdout)

    def test_image_checkout_and_standalone_fail_closed(self):
        source = (ROOT / 'build_sdcard.sh').read_text()
        block = source[source.index('# Refresh through signed APT'):source.index('"${pip_sudo[@]}" python3 -m pip install grpcio')]
        block = block.replace("/usr/bin/python3 - <<", "python3 - <<")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            helper = root / 'home.admin/config.scripts/blitz.python-trust.sh'
            helper.parent.mkdir(parents=True)
            script = root / 'build.sh'
            header = '''
sudo() {
  while [[ "$1" = --preserve-env=* ]]; do shift; done
  if [ "$1" = -H ]; then
    shift
    while [[ "$1" = --preserve-env=* ]]; do shift; done
    set -- -H "$@"
  fi
  case "$*" in
    'apt-get -o APT::Update::Error-Mode=any update') echo apt-index; return "$INDEX_STATUS" ;;
    'apt-get install --only-upgrade -y ca-certificates') echo apt-ca; return "$APT_STATUS" ;;
    'update-ca-certificates --fresh') echo bundle-refresh; return "$REFRESH_STATUS" ;;
    '-H bash '*) echo helper-invoked; return "$HELPER_STATUS" ;;
    *) echo unexpected-command >&2; return 99 ;;
  esac
}
wget() {
  [[ "$*" = '--no-config --https-only --ca-certificate=/etc/ssl/certs/ca-certificates.crt -O '* ]] || return 99
  echo helper-fetched; return "$FETCH_STATUS"
}
python3() { cat >/dev/null; echo bundle-verified; return "$CA_STATUS"; }
mktemp() {
  [ "$TEMP_STATUS" = 0 ] || return 1
  command mktemp "$@"
}
'''
            script.write_text(header + block + '\necho next-download\n')
            for checkout in (True, False):
                if checkout:
                    helper.touch()
                else:
                    helper.unlink(missing_ok=True)
                failures = ('', 'INDEX', 'APT', 'REFRESH', 'CA', 'HELPER')
                if not checkout:
                    failures += ('FETCH', 'TEMP')
                for failure in failures:
                    with self.subTest(checkout=checkout, failure=failure):
                        statuses = {name + '_STATUS': str(int(name == failure))
                                    for name in ('INDEX', 'APT', 'REFRESH', 'CA', 'HELPER', 'FETCH', 'TEMP')}
                        result = subprocess.run(['bash', str(script)], text=True, capture_output=True,
                                                env=dict(os.environ, **statuses, TMPDIR=temp))
                        self.assertEqual(result.returncode == 0, not failure, result.stdout + result.stderr)
                        self.assertEqual('next-download' in result.stdout, not failure, result.stdout + result.stderr)
                        self.assertEqual(list(root.glob('tmp.*')), [], 'standalone helper temporary file leaked')
                        if failure in ('INDEX', 'APT', 'REFRESH', 'CA', 'FETCH', 'TEMP'):
                            self.assertNotIn('helper-invoked', result.stdout)
                        if failure in ('INDEX', 'APT', 'REFRESH', 'CA'):
                            self.assertNotIn('helper-fetched', result.stdout)
                        if not failure:
                            events = ['apt-index', 'apt-ca', 'bundle-refresh', 'bundle-verified']
                            if not checkout:
                                events.append('helper-fetched')
                            events += ['helper-invoked', 'next-download']
                            self.assertEqual(result.stdout.splitlines(), events)

    def test_vendor_provision_ordering(self):
        source = (ROOT / 'home.admin/_provision.update.sh').read_text()
        comments = '# a conversion of config data or app data is needed'
        python_hook = '/home/admin/config.scripts/blitz.python-trust.sh'
        vendor_hook = '/home/admin/config.scripts/blitz.trust.sh update'
        self.assertLess(source.index(comments), source.index(python_hook))
        self.assertLess(source.index(python_hook), source.index('# if old bitcoin.conf exists'))
        # The same regression exercises the real combined source in the merge
        # worktree, or the companion insertion at its exact upstream anchor.
        if vendor_hook not in source:
            anchor = 'echo "prechecks OK"  >> ${logFile}\n'
            source = source.replace(anchor, anchor + '\n' + vendor_hook + ' >> "${logFile}" 2>&1 || exit 1\n')
        self.assertLess(source.index(vendor_hook), source.index(python_hook))
        block = source[source.index('echo "prechecks OK"'):source.index('# if old bitcoin.conf exists')]
        block = block.replace('/home/admin/config.scripts/blitz.trust.sh', 'vendor')
        block = block.replace(python_hook, 'python_trust')
        with tempfile.TemporaryDirectory() as temp:
            log = Path(temp) / 'log'
            header = '''
vendor() { echo vendor; return "$VENDOR_STATUS"; }
python_trust() { echo python; return "$HELPER_STATUS"; }
'''
            for vendor, helper in ((0, 0), (1, 0), (0, 1)):
                result = subprocess.run(['bash', '-c', header + block + '\necho next-hook'],
                                        env=dict(os.environ, logFile=str(log),
                                                 VENDOR_STATUS=str(vendor), HELPER_STATUS=str(helper)),
                                        text=True, capture_output=True)
                events = log.read_text().splitlines()
                self.assertEqual(events, ['prechecks OK', 'vendor'] + ([] if vendor else ['python']))
                self.assertEqual(result.returncode == 0, not (vendor or helper))
                self.assertEqual('next-hook' in result.stdout, not (vendor or helper))
                log.unlink()

    def test_image_and_upgrade_gate(self):
        image = (ROOT / 'build_sdcard.sh').read_text()
        events = ('sudo apt-get -o APT::Update::Error-Mode=any update || exit 1',
                  'sudo apt-get install --only-upgrade -y ca-certificates || exit 1',
                  'sudo update-ca-certificates --fresh || exit 1',
                  "/usr/bin/python3 - <<'PY' || exit 1", 'trust_helper=',
                  'wget --no-config --https-only --ca-certificate=',
                  '"${pip_sudo[@]}" python3 -m pip install grpcio')
        positions = [image.index(event) for event in events]
        self.assertEqual(positions, sorted(positions))
        # No pip package download is allowed before the bootstrap boundary.
        commands = '\n'.join(line.split('#', 1)[0] for line in image[:positions[0]].splitlines())
        self.assertNotRegex(commands, r'\b(?:pip[23]?\s+install|python[23]?\s+-m\s+pip\s+install)\b')
        self.assertLess(image.index('system-pip /usr/bin/python3'), image.index('pip install grpcio'))
        self.assertIn('system-pip /usr/bin/python3 || exit 1', image)
        update = (ROOT / 'home.admin/_provision.update.sh').read_text()
        self.assertIn('system-pip /usr/bin/python3 >> ${logFile} 2>&1 || exit 1', update)


if __name__ == '__main__':
    unittest.main()
