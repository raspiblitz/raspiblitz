#!/usr/bin/env python3
"""Remove only Debian's two October 2026 incident anchors from Java cacerts.

Uses keytool's public-certificate listing, never exports or decrypts private keys.
Non-default store passwords require separately reviewed administrator remediation.
"""
import argparse
import hashlib
import fcntl
import shutil
import signal
import stat
import struct
import tempfile
import unicodedata
import os
from pathlib import Path
import re
import ssl
import subprocess
import sys

DENIED = {
    "86a1ecba089c4a8d3bbe2734c612ba341d813e043cf9e8a862cd5c57a36bbe6b",
    "d7a7a0fb5d7e2731d771e9484ebcdef71d5f0c3e0a2948782bc83ee0ea699ef4",
}
PEM = re.compile(r"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", re.S)


def keytool(store, *args):
    result = subprocess.run([
        "keytool", "-J-Duser.language=en", "-J-Duser.country=US",
        *args, "-keystore", str(store), "-storepass", "changeit",
    ], capture_output=True, text=True, env={**os.environ, "LC_ALL": "C.UTF-8"})
    if result.returncode:
        raise RuntimeError("keytool failed; check store permissions, password, and JRE")
    return result.stdout


def inventory(text):
    count = re.search(r"Your keystore contains (\d+) entr(?:y|ies)", text)
    if not count:
        raise RuntimeError("Cannot validate keytool entry count")
    entries = {}
    for block in re.split(r"(?m)^Alias name: ", text)[1:]:
        alias, _, details = block.partition("\n")
        if (not re.match(r"^Creation date: [^\n]+\n", details)
                or any(unicodedata.category(c).startswith("C") or c in "\u2028\u2029" for c in alias)):
            raise RuntimeError("Control or multiline alias; manual review required")
        kind = re.search(r"(?m)^Entry type: (\S+)\s*$", details)
        certs = PEM.findall(details)
        if not alias or alias.startswith("-") or alias in entries or not kind or not certs:
            raise RuntimeError("Ambiguous keytool entry; refusing modification")
        if kind[1] not in {"trustedCertEntry", "PrivateKeyEntry"}:
            raise RuntimeError("Unsupported keystore entry type")
        if kind[1] == "trustedCertEntry" and len(certs) != 1:
            raise RuntimeError("Ambiguous trusted certificate entry")
        hashes = tuple(hashlib.sha256(ssl.PEM_cert_to_DER_cert(c)).hexdigest() for c in certs)
        entries[alias] = (kind[1], hashes)
    if len(entries) != int(count[1]):
        raise RuntimeError("Keystore inventory count mismatch")
    return entries


def mutate_stage(store, update=False):
    before = inventory(keytool(store, "-list", "-rfc"))
    targets = []
    for alias, (kind, hashes) in before.items():
        if DENIED.intersection(hashes):
            if kind != "trustedCertEntry":
                raise RuntimeError("Incident certificate in a private-key entry; manual review required")
            targets.append(alias)
    if targets and not update:
        raise RuntimeError(f"Java store still trusts {len(targets)} incident anchor entries")
    for alias in targets:
        # Refuse a changed inventory instead of deleting a concurrently replaced entry.
        current = inventory(keytool(store, "-list", "-rfc"))
        expected = {k: v for k, v in before.items() if k not in targets[:targets.index(alias)]}
        if current != expected:
            raise RuntimeError("Keystore changed during remediation; stop concurrent maintenance")
        keytool(store, "-delete", "-alias", alias)
    after = inventory(keytool(store, "-list", "-rfc"))
    expected = {k: v for k, v in before.items() if k not in targets}
    if after != expected:
        raise RuntimeError("Java postcondition failed: unrelated public entries changed")
    return len(targets), len(after)


def opaque_private_entries(data):
    """Compare encrypted JKS entry records, without decrypting/exporting keys.

    Deliberately fail closed on other container formats. Debian cacerts is JKS.
    Modified UTF-8 alias bytes are opaque here; keytool validates public aliases.
    """
    pos = 0

    def take(n):
        nonlocal pos
        if n < 0 or pos + n > len(data) - 20:
            raise RuntimeError("Malformed JKS container")
        result = data[pos:pos + n]
        pos += n
        return result

    def number():
        return struct.unpack(">I", take(4))[0]

    def utf():
        return take(struct.unpack(">H", take(2))[0])

    if number() != 0xFEEDFEED:
        raise RuntimeError("Only Debian JKS stores supported; review custom store format manually")
    version = number()
    if version not in (1, 2):
        raise RuntimeError("Unsupported JKS version")
    private = {}
    for _ in range(number()):
        start = pos
        tag = number()
        alias = utf()
        try:
            name = alias.replace(b'\xc0\x80', b'\0').decode('utf-8', 'surrogatepass')
        except UnicodeError as exc:
            raise RuntimeError("Unsupported JKS alias encoding") from exc
        if not name or any(unicodedata.category(c).startswith('C') or c in '\u2028\u2029' for c in name):
            raise RuntimeError("Control or multiline alias; manual review required")
        take(8)  # timestamp
        if tag == 1:
            take(number())  # opaque encrypted key, never decrypted
            count = number()
        elif tag == 2:
            count = 1
        else:
            raise RuntimeError("Unsupported JKS entry")
        for _ in range(count):
            if version == 2:
                utf()
            take(number())
        if tag == 1:
            if alias in private:
                raise RuntimeError("Duplicate private entry")
            private[alias] = data[start:pos]
    if pos != len(data) - 20:
        raise RuntimeError("Malformed JKS trailing data")
    return private


def snapshot(store):
    with open(store, "rb", opener=lambda p, f: os.open(p, f | os.O_NOFOLLOW)) as src:
        st = os.fstat(src.fileno())
        if not stat.S_ISREG(st.st_mode) or st.st_nlink != 1:
            raise RuntimeError("Require a regular, non-hardlinked JKS file")
        data = src.read()
        end = os.fstat(src.fileno())
    identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns,
                          s.st_ctime_ns, s.st_mode, s.st_uid, s.st_gid)
    if identity(st) != identity(end):
        raise RuntimeError("Keystore changed during snapshot")
    return identity(st), data, st


def attributes(path):
    # Linux POSIX ACLs are xattrs too. Refuse silent copystat omissions.
    if not hasattr(os, 'listxattr') or not hasattr(os, 'getxattr'):
        if sys.platform.startswith('linux'):
            raise RuntimeError("Python lacks Linux extended-permission support")
        return {}  # Local non-Linux fixture tests cover POSIX mode/owner only.
    return {name: os.getxattr(path, name, follow_symlinks=False)
            for name in os.listxattr(path, follow_symlinks=False)}


def sync_dir(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def remediate(store, update=False):
    # Canonical parent, but never follow a final-component symlink. In particular,
    # do not replace a JRE's cacerts symlink: caller must select its canonical target.
    store = store.parent.resolve(strict=True) / store.name
    parent = store.parent.stat()
    if parent.st_uid not in (0, os.geteuid()) or parent.st_mode & 0o022:
        raise RuntimeError("Keystore directory must be owner-controlled, not group/world writable")
    lock = store.with_name('.' + store.name + '.trust.lock')
    fd = os.open(lock, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, 'rb') as guard:
        st = os.fstat(guard.fileno())
        if (not stat.S_ISREG(st.st_mode) or st.st_nlink != 1
                or st.st_uid != os.geteuid() or stat.S_IMODE(st.st_mode) != 0o600):
            raise RuntimeError("Unsafe helper lock")
        fcntl.flock(guard, fcntl.LOCK_EX)
        original, data, metadata = snapshot(store)
        private = opaque_private_entries(data)
        original_attributes = attributes(store)
        work = Path(tempfile.mkdtemp(prefix='.' + store.name + '.trust-', dir=store.parent))
        backup = work / 'original.jks'
        stage = work / 'staged.jks'
        keep = False
        committed_inode = None
        commit_attempted = False
        try:
            for path in (backup, stage):
                with open(path, 'xb') as out:
                    os.chmod(path, 0o600)
                    out.write(data)
                    out.flush()
                    os.fsync(out.fileno())
            removed, preserved = mutate_stage(stage, update)
            staged_data = stage.read_bytes()
            if opaque_private_entries(staged_data) != private:
                raise RuntimeError("Opaque private entries changed; refusing commit")
            if removed:
                # Preserve all metadata supported by this filesystem, fail on error.
                os.chown(stage, metadata.st_uid, metadata.st_gid)
                shutil.copystat(store, stage, follow_symlinks=False)
                if attributes(stage) != original_attributes:
                    raise RuntimeError("Cannot preserve keystore extended permissions/attributes")
                with open(stage, 'rb') as staged:
                    os.fsync(staged.fileno())
                sync_dir(work)
                sync_dir(store.parent)
                current, current_data, _ = snapshot(store)
                if current != original or current_data != data:
                    raise RuntimeError("Keystore changed during remediation; live file untouched")
                # flock serializes helper writers, not arbitrary privileged writers.
                # No POSIX compare-and-rename primitive exists: external maintainers
                # MUST quiesce from snapshot through this atomic replacement.
                committed_identity, _, _ = snapshot(stage)
                commit_attempted = True
                os.replace(stage, store)
                # rename changes ctime on some filesystems; retain inode and bytes
                committed_inode = committed_identity[:2]
                try:
                    sync_dir(store.parent)
                except OSError:
                    # Roll back only our own unchanged committed inode/content.
                    committed, live_data, _ = snapshot(store)
                    if committed[:2] == committed_inode and live_data == staged_data:
                        rollback = work / 'rollback.jks'
                        with open(rollback, 'xb') as out:
                            os.chmod(rollback, 0o600)
                            out.write(data)
                            out.flush()
                            os.chown(rollback, metadata.st_uid, metadata.st_gid)
                            shutil.copystat(store, rollback, follow_symlinks=False)
                            if attributes(rollback) != original_attributes:
                                raise RuntimeError("Rollback metadata mismatch; protected original retained")
                            os.fsync(out.fileno())
                        os.replace(rollback, store)
                        sync_dir(store.parent)
                    raise
            current, current_data, _ = snapshot(store)
            if removed:
                if current[:2] != committed_inode or current_data != staged_data:
                    raise RuntimeError("Committed keystore changed; protected backup retained")
            elif current != original or current_data != data:
                raise RuntimeError("Keystore changed during remediation; live file untouched")
        except BaseException:
            # Precommit errors need no rollback. After a failed commit durability
            # operation retain the protected original for administrator recovery.
            if commit_attempted and not stage.exists():
                keep = True
                print(f"Protected recovery directory retained: {work}", file=sys.stderr)
            raise
        finally:
            if not keep:
                shutil.rmtree(work)
        print(f"Java incident anchors absent; {removed} removed, {preserved} entries preserved.")


def selected_store():
    for name in ('JAVA_TOOL_OPTIONS', '_JAVA_OPTIONS', 'JDK_JAVA_OPTIONS',
                 'JAVA_OPTS', 'MAVEN_OPTS', 'JAVA_HOME', 'JRE_HOME', 'JAVACMD',
                 'MAVEN_ARGS', 'MAVEN_CONFIG', 'M2_HOME', 'MAVEN_PROJECTBASEDIR',
                 'MAVEN_BASEDIR'):
        if os.environ.get(name):
            raise RuntimeError(f"Explicit {name} override requires separate Java trust review")
    java = shutil.which('java')
    if not java:
        raise RuntimeError("No selected Java executable; repair Debian JRE installation")
    executable = Path(java).resolve(strict=True)
    if executable != Path('/usr/bin/java').resolve(strict=True):
        raise RuntimeError("PATH selects a non-default Java; repair alternatives or review override")
    home = executable.parent.parent
    tool = shutil.which('keytool')
    if not tool or Path(tool).resolve(strict=True).parent.parent != home:
        raise RuntimeError("Selected java and keytool differ; repair Debian alternatives")
    security = home / 'lib/security'
    if (security / 'jssecacerts').exists() or (security / 'jssecacerts').is_symlink():
        raise RuntimeError("jssecacerts overrides cacerts; review/remove override before Java use")
    selected = (security / 'cacerts').resolve(strict=True)
    if selected != Path('/etc/ssl/certs/java/cacerts'):
        raise RuntimeError("Selected JRE does not use Debian cacerts; review custom Java trust")
    return selected


def interrupted(signum, frame):
    raise RuntimeError("Java trust remediation interrupted")


def main():
    signal.signal(signal.SIGTERM, interrupted)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=("check", "update"))
    parser.add_argument("--keystore", type=Path, help="Explicit isolated JKS file; bypasses selected-JRE gate")
    args = parser.parse_args()
    store = args.keystore if args.keystore is not None else selected_store()
    if not store.is_file():
        raise RuntimeError("Java cacerts missing; repair the vendor package first")
    remediate(store, args.mode == "update")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, ValueError) as exc:
        print(f"FAIL - {exc}", file=sys.stderr)
        sys.exit(1)
