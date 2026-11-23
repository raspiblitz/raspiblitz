#!/usr/bin/env python3
"""Local-only faults against disposable stores, including synthetic encrypted keys."""
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import tempfile
import unittest
from unittest.mock import patch
from test_java_trust import fix, HELPER
import test_java_trust as fixtures


@unittest.skipUnless(os.environ.get('JAVA_TRUST_PUBLIC_LISTING'), 'public inventory required')
class SafetyTests(unittest.TestCase):
    certs: dict
    good: str
    store: Path

    @classmethod
    def setUpClass(cls):
        fixtures.RealKeytoolTests.setUpClass.__func__(cls)
    setUp = fixtures.RealKeytoolTests.setUp
    add = fixtures.RealKeytoolTests.add
    listing = fixtures.RealKeytoolTests.listing

    def bad_store(self):
        self.add('bad', self.certs[next(iter(fix.DENIED))])
        self.add('custom', self.good)
        os.chmod(self.store, 0o640)
        return self.store.read_bytes()

    def assert_clean(self):
        self.assertEqual(list(self.store.parent.glob('.*.trust-*')), [])

    @unittest.skipUnless(sys.platform.startswith('linux') and hasattr(os, 'setxattr'),
                         'Linux POSIX ACL/xattr integration required')
    def test_linux_posix_acl_and_user_xattr_are_preserved(self):
        import errno
        import pwd
        import struct
        setxattr = getattr(os, 'setxattr')
        getxattr = getattr(os, 'getxattr')
        listxattr = getattr(os, 'listxattr')
        self.bad_store()
        # Linux UAPI posix_acl.h / posix_acl_xattr.h layout, no ACL tool package.
        undefined = (1 << 32) - 1
        entries = [(0x01, 0x06, undefined),
                   (0x02, 0x04, pwd.getpwnam('nobody').pw_uid),
                   (0x04, 0, undefined), (0x10, 0x04, undefined),
                   (0x20, 0, undefined)]
        acl = struct.pack('<I', 0x0002) + b''.join(struct.pack('<HHI', *e) for e in entries)
        try:
            setxattr(self.store, 'system.posix_acl_access', acl)
            setxattr(self.store, 'user.java_trust_fixture', b'preserve-metadata')
        except OSError as error:
            if error.errno in (errno.ENOTSUP, errno.ENOSYS, errno.EPERM):
                self.skipTest('Filesystem does not permit POSIX ACL fixtures')
            raise
        before = {name: getxattr(self.store, name) for name in listxattr(self.store)}
        metadata = self.store.stat()
        self.assertEqual(before['system.posix_acl_access'], acl)
        fix.remediate(self.store, True)
        self.assertEqual({name: getxattr(self.store, name) for name in listxattr(self.store)}, before)
        after = self.store.stat()
        self.assertEqual((after.st_uid, after.st_gid, after.st_mode),
                         (metadata.st_uid, metadata.st_gid, metadata.st_mode))

    def test_reproduced_real_keytool_alias_replacement_race(self):
        self.bad_store()
        real = fix.keytool
        changed = []

        def racing(stage, *args):
            self.assertNotEqual(stage, self.store)
            if '-delete' in args and not changed:
                # Exact historical boundary: after final listing, before delete.
                real(self.store, '-delete', '-alias', 'bad')
                cert = self.store.parent / 'replacement.pem'
                cert.write_text(self.good)
                real(self.store, '-importcert', '-noprompt', '-alias', 'bad', '-file', str(cert))
                changed.append(self.store.read_bytes())
            return real(stage, *args)

        with patch.object(fix, 'keytool', side_effect=racing):
            with self.assertRaisesRegex(RuntimeError, 'changed during'):
                fix.remediate(self.store, True)
        self.assertEqual(self.store.read_bytes(), changed[0])
        self.assertEqual(self.listing()['bad'], self.listing()['custom'])
        self.assert_clean()

    def test_replaced_inode_same_bytes_is_not_overwritten(self):
        saved = self.bad_store()
        real = fix.keytool
        replaced = []

        def racing(stage, *args):
            if '-delete' in args:
                other = self.store.with_suffix('.replacement')
                other.write_bytes(saved)
                os.replace(other, self.store)
                replaced.append(self.store.stat().st_ino)
            return real(stage, *args)

        with patch.object(fix, 'keytool', side_effect=racing):
            with self.assertRaisesRegex(RuntimeError, 'changed during'):
                fix.remediate(self.store, True)
        self.assertEqual(self.store.stat().st_ino, replaced[0])
        self.assertEqual(self.store.read_bytes(), saved)
        self.assert_clean()

    def test_truncating_keytool_failure_never_truncates_live(self):
        saved = self.bad_store()
        real = fix.keytool

        def truncate(stage, *args):
            if '-delete' in args:
                self.assertNotEqual(stage, self.store)
                stage.write_bytes(b'')
                raise RuntimeError('injected keytool write failure')
            return real(stage, *args)

        with patch.object(fix, 'keytool', side_effect=truncate):
            with self.assertRaisesRegex(RuntimeError, 'injected'):
                fix.remediate(self.store, True)
        self.assertEqual(self.store.read_bytes(), saved)
        self.assert_clean()

    def test_keyboard_interrupt_during_staged_mutation(self):
        saved = self.bad_store()
        real = fix.keytool

        def interrupt(stage, *args):
            if '-delete' in args:
                stage.write_bytes(b'partial write')
                raise KeyboardInterrupt()
            return real(stage, *args)

        with patch.object(fix, 'keytool', side_effect=interrupt):
            with self.assertRaises(KeyboardInterrupt):
                fix.remediate(self.store, True)
        self.assertEqual(self.store.read_bytes(), saved)
        self.assert_clean()

    def test_real_process_sigterm_and_sigkill_before_commit(self):
        saved = self.bad_store()
        for sig in (signal.SIGTERM, signal.SIGKILL):
            with self.subTest(signal=sig):
                marker = self.store.parent / 'ready'
                marker.unlink(missing_ok=True)
                code = '''import importlib.util,sys,time
from pathlib import Path
s=importlib.util.spec_from_file_location('fix',sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
real=m.keytool
marker=Path(sys.argv[3])
def hook(stage,*args):
    if '-delete' in args:
        stage.write_bytes(b'partial')
        marker.write_text('ready')
        time.sleep(30)
    return real(stage,*args)
m.keytool=hook
sys.argv=[sys.argv[1],'update','--keystore',sys.argv[2]]
m.main()
'''
                proc = subprocess.Popen([sys.executable, '-c', code, str(HELPER), str(self.store), str(marker)],
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                try:
                    deadline = time.monotonic() + 15
                    while not marker.exists() and time.monotonic() < deadline and proc.poll() is None:
                        time.sleep(.02)
                    self.assertTrue(marker.exists())
                    proc.send_signal(sig)
                    proc.wait(timeout=10)
                    self.assertNotEqual(proc.returncode, 0)
                    self.assertEqual(self.store.read_bytes(), saved)
                finally:
                    if proc.poll() is None:
                        proc.kill()
                        proc.wait()
                if sig == signal.SIGTERM:
                    self.assert_clean()
                else:
                    work, = list(self.store.parent.glob('.*.trust-*'))
                    self.assertEqual(work.stat().st_mode & 0o777, 0o700)
                    self.assertEqual((work / 'original.jks').stat().st_mode & 0o777, 0o600)

    def test_generated_private_ca_anchor_survives_with_custom_alias(self):
        self.bad_store()
        cert = self.store.parent / 'private-ca.pem'
        key = self.store.parent / 'private-ca.key'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                        '-keyout', str(key), '-out', str(cert), '-days', '1',
                        '-subj', '/CN=Disposable private organization CA',
                        '-addext', 'basicConstraints=critical,CA:TRUE'],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.add('debian:private-organization-with-no-source-file', cert.read_text())
        before = self.listing()
        fix.remediate(self.store, True)
        after = self.listing()
        self.assertEqual(after, {a: e for a, e in before.items() if a != 'bad'})
        self.assertIn('debian:private-organization-with-no-source-file', after)
        saved = self.store.read_bytes()
        fix.remediate(self.store, True)
        self.assertEqual(self.store.read_bytes(), saved)
        self.assert_clean()

    def test_synthetic_private_entry_preserved_byte_for_byte(self):
        self.bad_store()
        os.chmod(self.store, 0o600)
        # Fresh fixture key only. Distinct key password, unknown to remediation.
        fix.keytool(self.store, '-genkeypair', '-alias', 'opaque fixture', '-keyalg', 'EC',
                    '-dname', 'CN=Disposable test key', '-validity', '1', '-storetype', 'JKS',
                    '-keypass', 'synthetic-only-password')
        os.chmod(self.store, 0o600)
        private = fix.opaque_private_entries(self.store.read_bytes())
        before = self.listing()
        self.assertEqual(len(private), 1)
        fix.remediate(self.store, True)
        self.assertEqual(fix.opaque_private_entries(self.store.read_bytes()), private)
        self.assertEqual(self.listing(), {a: e for a, e in before.items() if a != 'bad'})
        self.assertEqual(self.store.stat().st_mode & 0o777, 0o600)
        self.assert_clean()
        # TemporaryDirectory cleanup deletes the fixture encrypted container.

    def test_multiline_control_and_spoofed_metadata_aliases_rejected(self):
        for alias in ('line one\nline two', 'one\ttwo', 'one\rtwo', 'one\x01two',
                      'one\nCreation date: Oct 29, 2026\nEntry type: trustedCertEntry'):
            with self.subTest(alias=repr(alias)):
                self.store.unlink(missing_ok=True)
                self.add(alias, self.good)
                saved = self.store.read_bytes()
                with self.assertRaisesRegex(RuntimeError, 'Control or multiline'):
                    fix.remediate(self.store, True)
                self.assertEqual(self.store.read_bytes(), saved)

    def test_symlink_and_hardlink_are_not_replaced(self):
        saved = self.bad_store()
        alias = self.store.parent / 'link.jks'
        alias.symlink_to(self.store)
        with self.assertRaises(OSError):
            fix.remediate(alias, True)
        self.assertTrue(alias.is_symlink())
        alias.unlink()
        os.link(self.store, alias)
        with self.assertRaisesRegex(RuntimeError, 'non-hardlinked'):
            fix.remediate(self.store, True)
        self.assertEqual(self.store.read_bytes(), saved)

    def test_failed_atomic_replace_leaves_live_unchanged(self):
        saved = self.bad_store()
        with patch.object(fix.os, 'replace', side_effect=OSError('replace failure')):
            with self.assertRaises(OSError):
                fix.remediate(self.store, True)
        self.assertEqual(self.store.read_bytes(), saved)
        self.assert_clean()

    def test_postrename_sync_failure_rolls_back(self):
        saved = self.bad_store()
        real = fix.sync_dir
        calls = []

        def sync(path):
            calls.append(path)
            if len(calls) == 3:
                raise OSError('commit durability fault')
            real(path)

        with patch.object(fix, 'sync_dir', side_effect=sync):
            with self.assertRaises(OSError):
                fix.remediate(self.store, True)
        self.assertEqual(self.store.read_bytes(), saved)
        self.assertEqual(self.store.stat().st_mode & 0o777, 0o640)

    def test_postcommit_changed_live_is_not_rolled_back_over(self):
        saved = self.bad_store()
        real = fix.sync_dir
        calls = []
        changed = []

        def sync(path):
            calls.append(path)
            if len(calls) == 3:
                self.add('external safe anchor', self.good)
                changed.append(self.store.read_bytes())
                raise OSError('commit durability fault after external write')
            real(path)

        with patch.object(fix, 'sync_dir', side_effect=sync):
            with self.assertRaises(OSError):
                fix.remediate(self.store, True)
        self.assertEqual(self.store.read_bytes(), changed[0])
        work, = list(self.store.parent.glob('.*.trust-*'))
        self.assertEqual(work.stat().st_mode & 0o777, 0o700)
        self.assertEqual((work / 'original.jks').read_bytes(), saved)
        self.assertEqual((work / 'original.jks').stat().st_mode & 0o777, 0o600)

    def test_lock_blocks_inventory_until_released(self):
        self.bad_store()
        started = self.store.parent / 'started'
        inventoried = self.store.parent / 'inventoried'
        lock = self.store.with_name('.' + self.store.name + '.trust.lock')
        fd = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
        fix.fcntl.flock(fd, fix.fcntl.LOCK_EX)
        code = """import importlib.util,sys
from pathlib import Path
s=importlib.util.spec_from_file_location('fix',sys.argv[1]); m=importlib.util.module_from_spec(s); s.loader.exec_module(m)
real=m.keytool
marker=Path(sys.argv[4])
def hook(stage,*args):
    marker.touch()
    return real(stage,*args)
m.keytool=hook
Path(sys.argv[3]).touch()
m.remediate(Path(sys.argv[2]),True)
"""
        proc = subprocess.Popen([sys.executable, '-c', code, str(HELPER), str(self.store), str(started), str(inventoried)],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 10
            while not started.exists() and time.monotonic() < deadline and proc.poll() is None:
                time.sleep(.02)
            self.assertTrue(started.exists())
            time.sleep(.2)
            self.assertFalse(inventoried.exists())
            fix.fcntl.flock(fd, fix.fcntl.LOCK_UN)
            output = proc.communicate(timeout=20)
            self.assertEqual(proc.returncode, 0, output)
            self.assertTrue(inventoried.exists())
        finally:
            os.close(fd)
            if proc.poll() is None:
                proc.kill()
                proc.wait()

    def test_two_helper_processes_serialize(self):
        self.bad_store()
        args = [sys.executable, str(HELPER), 'update', '--keystore', str(self.store)]
        procs = [subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE) for _ in range(2)]
        results = [p.communicate(timeout=30) for p in procs]
        self.assertEqual([p.returncode for p in procs], [0, 0], results)
        self.assertEqual(set(self.listing()), {'custom'})
        self.assert_clean()


class LifecycleTests(unittest.TestCase):
    def test_selected_jre_jssecacerts_and_custom_store_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / 'bin').mkdir()
            security = home / 'lib/security'
            security.mkdir(parents=True)
            java = home / 'bin/java'
            java.touch()
            (home / 'bin/keytool').touch()
            (security / 'cacerts').touch()
            real = Path.resolve

            def resolve(path, *args, **kwargs):
                return real(java) if path == Path('/usr/bin/java') else real(path, *args, **kwargs)

            def which(name):
                return str(home / 'bin' / name)

            with patch.object(fix.shutil, 'which', side_effect=which), patch.object(Path, 'resolve', resolve), patch.dict(os.environ, {}, clear=True):
                with self.assertRaisesRegex(RuntimeError, 'does not use Debian'):
                    fix.selected_store()
                # Broken symlinks also shadow cacerts and must not pass.
                (security / 'jssecacerts').symlink_to(home / 'missing')
                with self.assertRaisesRegex(RuntimeError, 'jssecacerts overrides'):
                    fix.selected_store()

    def test_explicit_runtime_overrides_fail_actionably(self):
        for name in ('JAVA_HOME', 'JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS', 'JDK_JAVA_OPTIONS', 'MAVEN_OPTS'):
            with self.subTest(name=name), patch.dict(os.environ, {name: 'custom'}):
                with self.assertRaisesRegex(RuntimeError, 'override requires'):
                    fix.selected_store()

    def test_fints_actual_install_prefix_gate_is_fatal_before_maven(self):
        script = HELPER.with_name('bonus.fints.sh').read_text()
        start = script.index('  # install java & build tool')
        end = script.index('  # make sure mysql', start)
        prefix = script[start:end].replace('/home/admin/config.scripts/blitz.trust.sh', 'gate')
        fixture = 'sudo() { printf "sudo %s\\n" "$*"; }; gate() { echo GATE; return 1; };\n'
        result = subprocess.run(['bash', '-c', fixture + prefix + '\necho MAVEN_REACHED'], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertIn('default-jdk', result.stdout)
        self.assertIn('maven', result.stdout)
        self.assertIn('GATE', result.stdout)
        self.assertNotIn('MAVEN_REACHED', result.stdout)
        self.assertLess(script.index('/home/admin/config.scripts/blitz.trust.sh update'), script.index('/usr/bin/mvn package'))


if __name__ == '__main__':
    unittest.main()
