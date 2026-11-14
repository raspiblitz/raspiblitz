#!/usr/bin/python3
"""Run ONLY in the disposable container: writes /usr/bin and dpkg database."""
import hashlib
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import unittest

ROOT = Path('/work')
SCRIPT = ROOT / 'home.admin/config.scripts/tor.install.sh'
FIXTURE = Path('/fixture')
CASES = Path('/cases')
TRACE_LINES = set()


def command(args, **kw):
    p = subprocess.run(args, text=True, stdout=subprocess.PIPE,
                       stderr=subprocess.STDOUT, **kw)
    if p.returncode:
        raise RuntimeError(f'{args}: {p.stdout}')
    return p.stdout


def package(version, name='tor', arch='all'):
    directory = FIXTURE / ('build-' + version + ('-' + name + '-' + arch if (name, arch) != ('tor', 'all') else ''))
    (directory / 'DEBIAN').mkdir(parents=True)
    (directory / 'usr/bin').mkdir(parents=True)
    (directory / 'DEBIAN/control').write_text(
        f'Package: {name}\nVersion: {version}\nArchitecture: {arch}\n'
        'Maintainer: Test <test@example.invalid>\nDescription: Inert Tor fixture\n')
    binary = directory / 'usr/bin/tor'
    binary.write_text('#!/bin/sh\n[ "$1" = --version ] || exit 99\n'
                      '[ "${FAULT:-}" != empty-version ] || { touch "$CASE/reached"; exit 0; }\n'
                      f'echo "Tor version {version}."\n'
                      '[ "${FAULT:-}" != version-error ] || { touch "$CASE/reached"; exit 1; }\n')
    binary.chmod(0o755)
    target = FIXTURE / f'{name}_{version}_{arch}.deb'
    command(['dpkg-deb', '--build', str(directory), str(target)])


def setup_module():
    assert Path('/.dockerenv').exists(), 'Do not run on a host'
    assert os.geteuid() == 0
    FIXTURE.mkdir()
    CASES.mkdir()
    home = FIXTURE / 'gnupg'
    home.mkdir(mode=0o700)
    os.environ['GNUPGHOME'] = str(home)
    command(['gpg', '--batch', '--passphrase', '', '--quick-generate-key',
             'Isolated fixture <test@example.invalid>', 'rsa2048', 'sign', '0'])
    info = command(['gpg', '--with-colons', '--list-keys'])
    fingerprint = next(x.split(':')[9] for x in info.splitlines() if x.startswith('fpr:'))
    (FIXTURE / 'fingerprint').write_text(fingerprint)
    (FIXTURE / 'key.asc').write_text(command(['gpg', '--armor', '--export', fingerprint]))
    (FIXTURE / 'key.gpg').write_bytes(subprocess.check_output(['gpg', '--export', fingerprint]))
    command(['gpg', '--batch', '--passphrase', '', '--quick-generate-key',
             'Untrusted extra key <extra@example.invalid>', 'ed25519', 'sign', '0'])
    (FIXTURE / 'bundle.asc').write_text(command(['gpg', '--armor', '--export']))
    for version in ('0.4.8.1', '0.4.9.1', '0.4.9.2', '0.4.10.2'):
        package(version)
    package('0.4.8.1', name='not-tor')
    package('0.4.8.1', arch='i386')
    package('0.4.8.1', arch='arm64')
    Path('/home/admin/download').mkdir(parents=True)
    Path('/usr/bin/snowflake-client').touch()
    Path('/usr/bin/snowflake-proxy').touch()
    bindir = FIXTURE / 'bin'
    bindir.mkdir()
    for name in ('sudo', 'lsb_release', 'curl', 'gpg', 'dpkg', 'dpkg-query',
                 'apt', 'debuild', 'systemctl', 'setcap', 'mktemp', 'install', 'tee'):
        (bindir / name).symlink_to(ROOT / 'tests/tor-update/shim.py')
    (ROOT / 'tests/tor-update/shim.py').chmod(0o755)
    Path('/etc/apt/sources.list.d').mkdir(exist_ok=True)
    (FIXTURE / 'bash-env').write_text("PS4='+${BASH_SOURCE}:${LINENO}: '\n")
    print('production_sha256=' + hashlib.sha256(SCRIPT.read_bytes()).hexdigest(), flush=True)


class Update(unittest.TestCase):
    def run_case(self, fault='', source=False, arch='arm64', unit='tor@default', old='0.4.8.1', action='update', latest_only=False, cache='', latest='0.4.9.1'):
        case = CASES / self.id().split('.')[-1]
        case.mkdir()
        repo = case / 'repo'
        repo.mkdir()
        versions = [latest] if latest_only else list(dict.fromkeys([old, latest]))
        for version in versions:
            shutil.copy(FIXTURE / f'tor_{version}_all.deb', repo)
        # dpkg-scanpackages reports warnings on stderr; only package records belong in Packages.
        packages = subprocess.check_output(['dpkg-scanpackages', '--multiversion', '.', '/dev/null'],
                                           cwd=repo, stderr=subprocess.DEVNULL).decode()
        (repo / 'Packages').write_text(packages)
        (repo / 'Release').write_text(command(['apt-ftparchive', 'release', '.'], cwd=repo))
        command(['gpg', '--batch', '--yes', '--local-user', (FIXTURE / 'fingerprint').read_text(), '--clearsign', '--output', str(repo / 'InRelease'), str(repo / 'Release')])
        (case / 'lists/partial').mkdir(parents=True)
        (case / 'archives/partial').mkdir(parents=True)
        (case / 'sources.list').write_text(f'deb [signed-by=/fixture/key.gpg] file:{repo} ./\n')
        (case / 'apt.conf').write_text(
            f'Dir::Etc::sourcelist "{case}/sources.list";\n'
            'Dir::Etc::sourceparts "-";\n'
            f'Dir::State::lists "{case}/lists";\n'
            f'Dir::Cache::archives "{case}/archives";\n'
            'APT::Get::List-Cleanup "0";\n')
        env = dict(os.environ, APT_CONFIG=str(case / 'apt.conf'), CASE=str(case),
                   FAULT=fault, ARCH=arch, UNIT=unit,
                   PATH=str(FIXTURE / 'bin') + ':' + os.environ['PATH'])
        command(['/usr/bin/dpkg', '-i', str(FIXTURE / f'tor_{old}_all.deb')])
        command(['/usr/bin/apt-get', 'update'],
                env=dict(env, PATH='/usr/sbin:/usr/bin:/sbin:/bin'))
        for cached in Path('/var/cache/apt/archives').glob('tor_*.deb'):
            cached.unlink()
        if cache:
            target = Path('/var/cache/apt/archives/tor_cached.deb')
            if cache == 'corrupt':
                target.write_bytes(b'not a deb')
            else:
                shutil.copy(FIXTURE / cache, target)
        (case / 'service').write_text('running')
        legacy = Path('/etc/apt/trusted.gpg.d/torproject.gpg')
        legacy.write_text('legacy-global-key')
        Path('/usr/share/keyrings/torproject.gpg').write_text('previous-keyring')
        with (case / 'trace').open('w') as trace:
            env.update(BASH_XTRACEFD=str(trace.fileno()), BASH_ENV='/fixture/bash-env')
            p = subprocess.run(['bash', '-x', str(SCRIPT), action] + (['source'] if source else []),
                               env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                               pass_fds=(trace.fileno(),))
        (case / 'output').write_text(p.stdout)
        for line in (case / 'trace').read_text().splitlines():
            try:
                if line.lstrip('+').startswith(str(SCRIPT) + ':'):
                    TRACE_LINES.add(int(line.lstrip('+').split(':')[1]))
            except ValueError:
                pass
        events = [json.loads(x) for x in (case / 'events').read_text().splitlines()]
        version = command(['/usr/bin/dpkg-query', '-W', '-f=${Version}', 'tor']).strip()
        expected = 0 if fault in ('', 'key-retry', 'backup-download') else 1
        self.assertEqual(p.returncode, expected, p.stdout)
        if fault:
            self.assertTrue((case / 'reached').exists(), 'fault not reached: ' + p.stdout)
        if expected == 0:
            self.assertEqual(version, max((latest, old), key=lambda v: tuple(map(int, v.split('.')))))
            self.assertEqual((case / 'service').read_text(), 'stopped' if action == 'install' else 'running')
            if not source:
                sources = Path('/etc/apt/sources.list.d/tor.list').read_text()
                self.assertIn(f'arch={arch} signed-by=/usr/share/keyrings/torproject.gpg', sources)
        elif action == 'install':
            self.assertIn('! FAIL:', p.stdout)
        elif fault != 'rollback-failure' and not latest_only:
            self.assertEqual(version, old, p.stdout)
            # Compare actual packaged executable bytes, not only the database.
            self.assertEqual(Path('/usr/bin/tor').read_bytes(),
                             (FIXTURE / f'build-{old}/usr/bin/tor').read_bytes())
            if fault != 'restart-permanent':
                self.assertEqual((case / 'service').read_text(), 'running')
        if fault == 'checksum':
            self.assertIn('Hash Sum mismatch', p.stdout)
        if fault == 'signature':
            self.assertIn('BADSIG', p.stdout)
        if fault == 'rollback-failure':
            self.assertIn('Package rollback failed', p.stdout)
            self.assertEqual(version, '0.4.9.1')
        if fault == 'restart-permanent':
            self.assertIn('Unable to restart the Tor service', p.stdout)
            self.assertEqual((case / 'service').read_text(), 'stopped')
        stages = re.findall(r'Recovery files retained in (\S+)', p.stdout)
        for stage in stages:
            directory = Path(stage)
            self.assertEqual(directory.stat().st_uid, 0)
            self.assertEqual(directory.stat().st_mode & 0o777, 0o700)
            if fault != 'backup-download' and (not latest_only or cache in ('tor_0.4.8.1_all.deb', 'tor_0.4.8.1_arm64.deb')):
                self.assertEqual((directory / 'previous.deb').read_bytes(),
                                 (FIXTURE / f'tor_{old}_all.deb').read_bytes())
        for event in events:
            if event[:2] == ['systemctl', 'stop'] or event[:2] == ['systemctl', 'restart']:
                self.assertEqual(event[2], unit)
        if fault.startswith('key-') and fault != 'key-retry':
            self.assertEqual(Path('/usr/share/keyrings/torproject.gpg').read_text(), 'previous-keyring')
            self.assertEqual(sum(e[:2] == ['curl', '-fsS'] for e in events), 0 if fault == 'key-stage' else 2)
        if not source:
            self.assertEqual(legacy.exists(), fault.startswith('key-') and fault != 'key-retry' or
                             fault in ('keyring-install', 'bundled-key', 'sources-write', 'update-stage', 'missing-package'))
        if latest_only:
            backup = cache in ('tor_0.4.8.1_all.deb', 'tor_0.4.8.1_arm64.deb')
            self.assertEqual('continuing without package rollback' in p.stdout, not backup)
            rollbacks = [e for e in events if e[0] == 'dpkg' and e[-1].endswith('previous.deb')]
            self.assertEqual(bool(rollbacks), backup and expected != 0)
            if expected != 0:
                self.assertEqual(version, old if backup else latest)
                self.assertGreaterEqual(sum(e[:2] == ['systemctl', 'restart'] for e in events),
                                        2 if fault.startswith('restart') else 1)
                self.assertEqual((case / 'service').read_text(),
                                 'stopped' if fault == 'restart-permanent' else 'running')
        return case, events

    def test_latest_only_upgrade(self):
        self.run_case(latest_only=True)

    def test_future_candidate(self):
        self.run_case(latest_only=True, latest='0.4.10.2')

    def test_cache_fallback(self):
        self.run_case('apt-install', latest_only=True, cache='tor_0.4.8.1_all.deb')

    def test_cache_actual_architecture(self):
        self.run_case(latest_only=True, cache='tor_0.4.8.1_arm64.deb')

    def test_no_backup_install_failure(self):
        self.run_case('apt-install', latest_only=True)

    def test_no_backup_restart_failure(self):
        self.run_case('restart', latest_only=True)

    def test_no_backup_permanent_restart_failure(self):
        self.run_case('restart-permanent', latest_only=True)

    def test_install_success(self):
        self.run_case(action='install')

    def test_install_empty_version(self):
        self.run_case('empty-version', action='install')

    def test_install_old_version(self):
        self.run_case('old-version', action='install')

    def test_verified_amd64(self):
        self.run_case(arch='amd64')

    def test_verified_arm64(self):
        self.run_case()

    def test_legacy_unit(self):
        self.run_case(unit='tor')

    def test_existing_version_noop(self):
        self.run_case(old='0.4.9.1')

    def test_newer_version_no_downgrade(self):
        self.run_case(old='0.4.9.2')

    def test_retry_clearnet(self):
        case, events = self.run_case('key-retry')
        curls = [e for e in events if e[0] == 'curl']
        self.assertEqual(len(curls), 2)
        self.assertIn('-x', curls[0])
        self.assertNotIn('-x', curls[1])
        self.assertTrue(any('https://deb.torproject.org/' in x for x in curls[1]))

    def test_source_stop_legacy(self):
        self.run_case('stop', source=True, unit='tor')

    def test_source_missing_download_dir(self):
        shutil.rmtree('/home/admin/download')
        self.run_case(source=True)

    def test_source_success(self):
        self.run_case(source=True)

    def test_source_legacy(self):
        self.run_case(source=True, unit='tor')


def add_case(name, fault, source=False):
    def test(self):
        self.run_case(fault, source=source)
    setattr(Update, 'test_' + name, test)


for fault in ('key-download', 'key-fingerprint', 'key-dearmor', 'signature', 'checksum',
              'download', 'transport-download', 'transport-install', 'apt-install',
              'restart', 'restart-permanent', 'rollback-failure', 'missing-package',
              'backup-download', 'empty-version', 'old-version', 'version-error', 'signal', 'update-stage', 'key-stage',
              'keyring-install', 'key-inspect', 'bundled-key', 'sources-write'):
    add_case('apt_' + fault.replace('-', '_'), fault)
for fault in ('source-download', 'build-tools', 'build-dep', 'build', 'missing-build',
              'stop', 'source-install', 'restart', 'empty-version', 'old-version', 'version-error', 'signature',
              'source-stage', 'source-layout', 'multiple-build'):
    add_case('source_' + fault.replace('-', '_'), fault, True)


for label, cache in [('package', 'not-tor_0.4.8.1_all.deb'),
                     ('version', 'tor_0.4.9.1_all.deb'),
                     ('architecture', 'tor_0.4.8.1_i386.deb'), ('corrupt', 'corrupt')]:
    def invalid_cache(self, cache=cache):
        self.run_case('apt-install', latest_only=True, cache=cache)
    setattr(Update, 'test_invalid_cache_' + label, invalid_cache)


def verify_command_sites():
    """Audit command/condition sites in the changed helpers/update block.

    This is a Bash xtrace site gate, not a claim of shell branch coverage.
    Multiline expansions are attributed to their final expansion line by Bash.
    """
    lines = SCRIPT.read_text().splitlines()
    spans = []
    for start, end in (('add_tor_sources(){', 'configure_default_torrc(){'),
                       ('require_supported_tor_version(){', 'action=$1'),
                       ('if [ "${action}" = "update" ]; then', '# if above')):
        first = next(i for i, line in enumerate(lines) if line.startswith(start))
        last = next(i for i, line in enumerate(lines[first + 1:], first + 1) if line.startswith(end))
        spans.extend(range(first, last))
    pattern = re.compile(r'^(local |[a-z_]+=|for |if |curl |gpg |sudo |rm |echo |return |trap |exit |case |cd |apt |debuild |mkdir |set -- tor_|\[ )')
    required = set()
    nested_start = lines.index("  if ! sudo bash -c '")
    nested_end = next(i for i in range(nested_start, len(lines)) if lines[i].startswith("    exit 1' bash"))
    for i in spans:
        # The embedded root shell has its own line numbers, not SCRIPT lines.
        # Its outcomes are asserted by the signed-repository/cache cases.
        if nested_start < i <= nested_end:
            continue
        line = lines[i].strip()
        if not pattern.match(line):
            continue
        if line.startswith('fingerprint=$('):
            i = next(j for j in range(i + 1, len(lines)) if lines[j].strip().endswith("')"))
        elif line.startswith('echo "deb '):
            i += 1
        required.add(i + 1)
    missing = sorted(required - TRACE_LINES)
    print(f'Changed-path command/condition sites traced: {len(required - set(missing))}/{len(required)}')
    if missing:
        print('Untraced sites: ' + repr([(i, lines[i - 1]) for i in missing]))
    return not missing


if __name__ == '__main__':
    setup_module()
    result = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(Update))
    Path('/work/trace-lines.json').write_text(json.dumps(sorted(TRACE_LINES)))
    print(f'Traced production lines: {len(TRACE_LINES)}; see trace-lines.json')
    print('TRACE_LINES=' + json.dumps(sorted(TRACE_LINES)))
    covered = verify_command_sites()
    raise SystemExit(0 if result.wasSuccessful() and covered else 1)
