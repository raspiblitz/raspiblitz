"""Unit tests for home.admin/config.scripts/cl.hsmsecret.py

Run from the test directory (needs: pip install mnemonic==0.19):
  python3 -m unittest -v test_cl_hsmsecret.py
With branch coverage (as in CI):
  python3 -m coverage run --branch --include='*/cl.hsmsecret.py' -m unittest test_cl_hsmsecret.py
  python3 -m coverage report -m --fail-under=100
"""

import errno
import hashlib
import importlib.util
import io
import os
import runpy
import signal
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

HELPER = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                      "..", "home.admin", "config.scripts", "cl.hsmsecret.py")

spec = importlib.util.spec_from_file_location("cl_hsmsecret", HELPER)
assert spec is not None and spec.loader is not None
hs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(hs)

# Official BIP39 test vectors (trezor/python-mnemonic vectors.json).
# The legacy hsm_secret is the first 32 bytes of the 64-byte BIP39 seed.
ABANDON_12 = " ".join(["abandon"] * 11 + ["about"])
ABANDON_24 = " ".join(["abandon"] * 23 + ["art"])
ZOO_24 = " ".join(["zoo"] * 23 + ["vote"])
VECTORS = [
    (ABANDON_12, "TREZOR",
     "c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553"),
    (ABANDON_24, "TREZOR",
     "bda85446c68413707090a52022edd26a1c9462295029f2e60cd7c4f2bbd30971"),
    (ZOO_24, "TREZOR",
     "dd48c104698c30cfe2b6142103248622fb7bb0ff692eebb00089b32d22484e16"),
    # no passphrase: what 'lightning-hsmtool generatehsm' of CLN v25.09.3
    # writes for ABANDON_12 (checked against the real binary in
    # cl.hsmtool.real-cln.bats)
    (ABANDON_12, "",
     "5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc1"),
]
SECRET = bytes.fromhex(VECTORS[0][2])


def run_main(argv, stdin_data):
    if isinstance(stdin_data, str):
        stdin_data = stdin_data.encode("utf-8")
    stdout, stderr = io.StringIO(), io.StringIO()
    with mock.patch.object(sys, "stderr", stderr):
        code = hs.main(argv, stdin=io.BytesIO(stdin_data), stdout=stdout)
    return code, stdout.getvalue(), stderr.getvalue()


class TestDerive(unittest.TestCase):

    def test_known_vectors_byte_for_byte(self):
        for mnemonic, passphrase, expected in VECTORS:
            with self.subTest(words=len(mnemonic.split()), passphrase=passphrase):
                code, out, err = run_main(
                    ["x", "derive"], "%s\n%s\n" % (mnemonic, passphrase))
                self.assertEqual((code, err), (0, ""))
                self.assertEqual(out, expected + "\n")
                self.assertEqual(hs.derive_hsm_secret(
                    mnemonic, passphrase.encode()).hex(), expected)

    def test_passphrase_changes_the_secret(self):
        self.assertNotEqual(hs.derive_hsm_secret(ABANDON_12, b"TREZOR"),
                            hs.derive_hsm_secret(ABANDON_12, b"TREZOR "))

    def test_non_ascii_passphrase_is_hashed_as_raw_bytes(self):
        # libwally (CLN < v25.12) hashes the raw bytes: no NFKD, no locale
        composed, decomposed = "\u00e9".encode(), "e\u0301".encode()
        self.assertNotEqual(hs.derive_hsm_secret(ABANDON_12, composed),
                            hs.derive_hsm_secret(ABANDON_12, decomposed))
        for passphrase in (b"p\xc3\xa4ss word", b"se\xffcret\x80"):
            with self.subTest(passphrase=passphrase):
                code, out, err = run_main(
                    ["x", "derive"], ABANDON_12.encode() + b"\n" + passphrase + b"\n")
                self.assertEqual((code, err), (0, ""))
                expected = hashlib.pbkdf2_hmac(
                    "sha512", ABANDON_12.encode(), b"mnemonic" + passphrase,
                    2048)[:32].hex()
                self.assertEqual(out, expected + "\n")

    def test_non_ascii_mnemonic(self):
        err = self.assert_rejected(
            ABANDON_12.replace("about", "ab\u00f6ut") + "\n\n", "non-ASCII")
        self.assertNotIn("abandon", err)

    def assert_rejected(self, stdin_text, message):
        code, out, err = run_main(["x", "derive"], stdin_text)
        self.assertEqual(code, 1)
        self.assertEqual(out, "")
        self.assertIn(message, err)
        return err

    def test_wrong_word_count(self):
        for count in (1, 11, 13, 23, 25):
            with self.subTest(count=count):
                words = " ".join(["abandon"] * count)
                self.assert_rejected(words + "\n\n", "%d words" % count)

    def test_empty_mnemonic(self):
        self.assert_rejected("\n\n", "invalid mnemonic")

    def test_double_space_is_a_wrong_word_count(self):
        self.assert_rejected(ABANDON_12.replace(" ", "  ", 1) + "\n\n",
                             "separated by single spaces")

    def test_unknown_words_are_reported_by_position_only(self):
        words = ABANDON_12.split(" ")
        words[2], words[7] = "notaword", "bitcoinx"
        err = self.assert_rejected(" ".join(words) + "\n\n",
                                   "number 3, 8 not in the BIP39")
        self.assertNotIn("notaword", err)
        self.assertNotIn("abandon", err)

    def test_uppercase_word_is_unknown(self):
        self.assert_rejected(ABANDON_12.upper() + "\n\n", "not in the BIP39")

    def test_wrong_checksum(self):
        err = self.assert_rejected(" ".join(["abandon"] * 12) + "\n\n",
                                   "wrong BIP39 checksum")
        self.assertNotIn("abandon", err)

    def test_missing_passphrase_line(self):
        self.assert_rejected(ABANDON_12 + "\n", "incomplete input")

    def test_cut_off_input(self):
        self.assert_rejected(ABANDON_12[:20], "incomplete input")
        self.assert_rejected("", "incomplete input")

    def test_mnemonic_package_missing(self):
        with mock.patch.dict(sys.modules, {"mnemonic": None}):
            self.assert_rejected(ABANDON_12 + "\n\n",
                                 "'mnemonic' package is not installed")


class TestParseSecretHex(unittest.TestCase):

    def test_valid(self):
        self.assertEqual(hs.parse_secret_hex(SECRET.hex() + "\n"), SECRET)

    def test_invalid(self):
        for data in ("", "\n", SECRET.hex()[:-2], SECRET.hex() + "00",
                     SECRET.hex().upper(), "zz" + SECRET.hex()[2:],
                     SECRET.hex()[:32] + " " + SECRET.hex()[32:]):
            with self.subTest(data=data):
                with self.assertRaises(hs.HsmSecretError):
                    hs.parse_secret_hex(data)


class TestWrite(unittest.TestCase):

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.dir = self.tmp.name
        self.path = os.path.join(self.dir, "hsm_secret")

    def tearDown(self):
        for name in os.listdir(self.dir):
            if not os.path.islink(os.path.join(self.dir, name)):
                os.chmod(os.path.join(self.dir, name), 0o600)
        self.tmp.cleanup()

    def write(self, stdin_text=SECRET.hex() + "\n", path=None):
        return run_main(["x", "write", path or self.path], stdin_text)

    def assert_no_leftovers(self, expected=()):
        self.assertEqual(sorted(os.listdir(self.dir)), sorted(expected))

    def test_creates_exact_bytes_with_mode_0400(self):
        code, out, err = self.write()
        self.assertEqual((code, out, err), (0, "", ""))
        with open(self.path, "rb") as f:
            self.assertEqual(f.read(), SECRET)
        st = os.stat(self.path)
        self.assertEqual(stat.S_IMODE(st.st_mode), 0o400)
        self.assertEqual(st.st_uid, os.getuid())
        self.assertEqual(st.st_nlink, 1)
        self.assert_no_leftovers(["hsm_secret"])

    def test_mode_does_not_depend_on_umask(self):
        old = os.umask(0o777)
        try:
            self.assertEqual(self.write()[0], 0)
        finally:
            os.umask(old)
        self.assertEqual(stat.S_IMODE(os.stat(self.path).st_mode), 0o400)

    def test_never_overwrites_an_existing_wallet(self):
        with open(self.path, "wb") as f:
            f.write(b"existing wallet")
        code, _, err = self.write()
        self.assertEqual(code, 1)
        self.assertIn("already exists", err)
        with open(self.path, "rb") as f:
            self.assertEqual(f.read(), b"existing wallet")
        self.assert_no_leftovers(["hsm_secret"])

    def test_never_follows_an_existing_symlink(self):
        target = os.path.join(self.dir, "elsewhere")
        os.symlink(target, self.path)
        code, _, err = self.write()
        self.assertEqual(code, 1)
        self.assertIn("already exists", err)
        self.assertFalse(os.path.exists(target))

    def test_existing_file_appearing_during_the_write_is_kept(self):
        # race: another process creates the hsm_secret before the link
        real_link = os.link

        def racing_link(src, dst):
            with open(dst, "wb") as f:
                f.write(b"other wallet")
            real_link(src, dst)

        with mock.patch.object(hs.os, "link", racing_link):
            code, _, err = self.write()
        self.assertEqual(code, 1)
        self.assertIn("File exists", err)
        with open(self.path, "rb") as f:
            self.assertEqual(f.read(), b"other wallet")
        self.assert_no_leftovers(["hsm_secret"])

    def test_invalid_input_creates_nothing(self):
        for data in ("", SECRET.hex()[:40]):
            with self.subTest(data=data):
                code, _, err = self.write(data)
                self.assertEqual(code, 1)
                self.assertIn("64 lowercase hex characters", err)
                self.assert_no_leftovers()

    def test_missing_directory(self):
        code, _, err = self.write(path=os.path.join(self.dir, "no", "hsm_secret"))
        self.assertEqual(code, 1)
        self.assertIn("could not create", err)

    def test_short_writes_are_completed(self):
        real_write = os.write
        with mock.patch.object(hs.os, "write",
                               lambda fd, data: real_write(fd, data[:5])):
            self.assertEqual(self.write()[0], 0)
        with open(self.path, "rb") as f:
            self.assertEqual(f.read(), SECRET)

    def assert_failure_leaves_nothing(self, name, message):
        error = OSError(errno.ENOSPC, os.strerror(errno.ENOSPC))
        with mock.patch.object(hs.os, name, side_effect=error):
            code, _, err = self.write()
        self.assertEqual(code, 1)
        self.assertIn(message, err)
        self.assert_no_leftovers()

    def test_write_error_leaves_no_partial_file(self):
        self.assert_failure_leaves_nothing("write", "could not write")

    def test_fsync_error_leaves_no_file(self):
        self.assert_failure_leaves_nothing("fsync", "could not write")

    def test_fchmod_error_leaves_no_file(self):
        self.assert_failure_leaves_nothing("fchmod", "could not write")

    def test_link_error_leaves_no_file(self):
        self.assert_failure_leaves_nothing("link", "could not write")

    def test_failed_cleanup_of_the_temporary_file_is_ignored(self):
        with mock.patch.object(hs.os, "unlink", side_effect=OSError(errno.EIO, "EIO")):
            self.assertEqual(self.write()[0], 0)
        with open(self.path, "rb") as f:
            self.assertEqual(f.read(), SECRET)

    def test_directory_sync_error(self):
        real_fsync = os.fsync
        calls = []

        def fsync(fd):
            calls.append(fd)
            if len(calls) == 2:
                raise OSError(errno.EIO, os.strerror(errno.EIO))
            real_fsync(fd)

        with mock.patch.object(hs.os, "fsync", fsync):
            code, _, err = self.write()
        self.assertEqual(code, 1)
        self.assertIn("could not sync", err)

    def test_interrupted_process_never_leaves_a_partial_hsm_secret(self):
        # SIGKILL the writer at each step: the hsm_secret is either complete
        # or absent, never partial
        for step in ("write", "fsync", "link"):
            with self.subTest(step=step):
                code = (
                    "import importlib.util, os, signal, sys\n"
                    "spec = importlib.util.spec_from_file_location('h', sys.argv[1])\n"
                    "h = importlib.util.module_from_spec(spec)\n"
                    "spec.loader.exec_module(h)\n"
                    "def die(*a): os.kill(os.getpid(), signal.SIGKILL)\n"
                    "setattr(h.os, sys.argv[3], die)\n"
                    "h.main(['x', 'write', sys.argv[2]])\n")
                proc = subprocess.run(
                    [sys.executable, "-c", code, HELPER, self.path, step],
                    input=SECRET.hex() + "\n", text=True)
                self.assertEqual(proc.returncode, -signal.SIGKILL)
                self.assertFalse(os.path.lexists(self.path))
                for name in os.listdir(self.dir):
                    self.assertTrue(name.startswith(".hsm_secret.tmp."))
                    os.chmod(os.path.join(self.dir, name), 0o600)
                    os.unlink(os.path.join(self.dir, name))


class TestType(unittest.TestCase):
    # the format detection follows CLN detect_hsm_secret_type(); the real
    # files of CLN v25.09.3 and the pinned CLN are checked in
    # cl.hsmtool.real-cln.bats

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.path = os.path.join(self.tmp.name, "hsm_secret")

    def tearDown(self):
        self.tmp.cleanup()

    def put(self, data):
        with open(self.path, "wb") as f:
            f.write(data)

    def run_cmd(self, command):
        return run_main(["x", command, self.path], b"")

    def test_types(self):
        mnemonic = ABANDON_12.encode()
        for data, expected in (
                (b"", "invalid"),
                (b"\x01" * 31, "invalid"),
                (SECRET, "plain"),
                (b"\x01" * 73, "encrypted"),
                (bytes(32) + mnemonic, "mnemonic"),
                (b"\x01" + bytes(31) + mnemonic, "mnemonic-passphrase"),
                (b"\x01" * 33, "mnemonic-passphrase")):
            with self.subTest(expected=expected, length=len(data)):
                self.put(data)
                self.assertEqual(self.run_cmd("type"), (0, expected + "\n", ""))

    def test_type_of_a_missing_file(self):
        code, out, err = self.run_cmd("type")
        self.assertEqual((code, out), (1, ""))
        self.assertIn("could not read", err)


class TestCommandLine(unittest.TestCase):

    def test_usage(self):
        for argv in (["x"], ["x", "derive", "extra"], ["x", "write"],
                     ["x", "type"], ["x", "type", "a", "b"], ["x", "mnemonic", "a"], ["x", "unknown"]):
            with self.subTest(argv=argv):
                code, out, err = run_main(argv, "")
                self.assertEqual((code, out), (2, ""))
                self.assertIn("Usage:", err)

    def test_script_entry_point(self):
        with mock.patch.object(sys, "argv", [HELPER]), \
                mock.patch.object(sys, "stdin", io.TextIOWrapper(io.BytesIO())), \
                mock.patch.object(sys, "stderr", io.StringIO()):
            with self.assertRaises(SystemExit) as cm:
                runpy.run_path(HELPER, run_name="__main__")
        self.assertEqual(cm.exception.code, 2)

    def test_derive_piped_to_write(self):
        # the pipeline used by cl.hsmtool.sh createHsmSecret
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "hsm_secret")
            derive = subprocess.run(
                [sys.executable, HELPER, "derive"],
                input="%s\n%s\n" % (ABANDON_12, "TREZOR"),
                capture_output=True, text=True, check=True)
            subprocess.run([sys.executable, HELPER, "write", path],
                           input=derive.stdout, text=True, check=True)
            with open(path, "rb") as f:
                self.assertEqual(f.read(), SECRET)
            os.chmod(path, 0o600)


if __name__ == "__main__":
    unittest.main()
