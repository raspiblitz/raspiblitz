#!/usr/bin/python3
"""Create a Core Lightning hsm_secret from BIP39 seed words.

The hsm_secret is written in the legacy plain format: the first 32 bytes of
the BIP39 seed (PBKDF2-HMAC-SHA512 of the mnemonic, salt "mnemonic" +
passphrase, 2048 rounds). This is byte-for-byte what
'lightning-hsmtool generatehsm' wrote before Core Lightning v25.12.

CLN >= v25.12 'generatehsm' writes a new mnemonic format instead. Its
on-chain wallet keys are derived from the full 64-byte seed, so the same seed
words give a different on-chain wallet than a RaspiBlitz wallet created
before, and 'lightning-hsmtool encrypt' rejects the new format.
CLN >= v25.12 still loads the legacy plain format.

Usage:
  cl.hsmsecret.py derive
      stdin: line 1 = mnemonic (space separated), line 2 = passphrase (may be
      empty, hashed as raw bytes like libwally)
      stdout: the 32-byte hsm_secret as 64 hex characters
  cl.hsmsecret.py write <path/to/hsm_secret>
      stdin: the 64 hex characters from 'derive'
      Creates the file with mode 0400. Never overwrites an existing file and
      never leaves a partially written hsm_secret behind.

Secrets are passed on stdin only, never as arguments (visible in 'ps').
'derive' needs the python-mnemonic package, 'write' only the standard library.
"""

import hashlib
import os
import sys

VALID_WORD_COUNTS = (12, 15, 18, 21, 24)
SECRET_LEN = 32
HEX_DIGITS = "0123456789abcdef"


class HsmSecretError(Exception):
    pass


def check_mnemonic(mnemonic):
    """Raise HsmSecretError unless mnemonic is a valid english BIP39 mnemonic.

    The error messages never contain the seed words.
    """
    words = mnemonic.split(" ")
    if len(words) not in VALID_WORD_COUNTS:
        raise HsmSecretError(
            "invalid mnemonic: %d words, expected 12, 15, 18, 21 or 24 words "
            "separated by single spaces" % len(words))
    try:
        from mnemonic import Mnemonic
    except ImportError:
        raise HsmSecretError("the python 'mnemonic' package is not installed")
    mnemo = Mnemonic("english")
    unknown = [str(i + 1) for i, word in enumerate(words)
               if word not in mnemo.wordlist]
    if unknown:
        raise HsmSecretError(
            "invalid mnemonic: word(s) number %s not in the BIP39 english "
            "wordlist" % ", ".join(unknown))
    if not mnemo.check(mnemonic):
        raise HsmSecretError("invalid mnemonic: wrong BIP39 checksum")


def derive_hsm_secret(mnemonic, passphrase):
    """Return the legacy 32-byte hsm_secret for a checked mnemonic (str) and
    passphrase (raw bytes).

    Same as libwally bip39_mnemonic_to_seed() as used by CLN < v25.12: the
    passphrase bytes are hashed as given, without unicode normalization and
    independent of the locale.
    """
    seed = hashlib.pbkdf2_hmac("sha512", mnemonic.encode("ascii"),
                               b"mnemonic" + passphrase, 2048)
    return seed[:SECRET_LEN]


def read_line(stream):
    """Read one line of raw bytes from a binary stream, without the newline."""
    line = stream.readline()
    if not line.endswith(b"\n"):
        # EOF before the end of the line: the input was cut off
        raise HsmSecretError("incomplete input on stdin")
    return line[:-1]


def derive(stdin, stdout):
    mnemonic = read_line(stdin)
    passphrase = read_line(stdin)
    try:
        mnemonic = mnemonic.decode("ascii")
    except UnicodeDecodeError:
        raise HsmSecretError("invalid mnemonic: not in the BIP39 english "
                             "wordlist (non-ASCII characters)")
    check_mnemonic(mnemonic)
    stdout.write(derive_hsm_secret(mnemonic, passphrase).hex() + "\n")


def parse_secret_hex(data):
    data = data.strip()
    if len(data) != 2 * SECRET_LEN or any(c not in HEX_DIGITS for c in data):
        raise HsmSecretError(
            "expected the %d-byte hsm_secret as %d lowercase hex characters "
            "on stdin" % (SECRET_LEN, 2 * SECRET_LEN))
    return bytes.fromhex(data)


def write_hsm_secret(path, secret):
    """Create path containing secret with mode 0400, all or nothing.

    The secret is written and fsynced to a temporary file in the same
    directory first, then hard linked to path: link() fails if path exists
    and path never has partial content. A crash can leave the temporary file
    (mode 0400, next to the hsm_secret) but never a partial hsm_secret.
    """
    if os.path.lexists(path):
        raise HsmSecretError("%s already exists - not overwriting" % path)
    directory = os.path.dirname(os.path.abspath(path))
    tmp = os.path.join(directory, ".%s.tmp.%d"
                       % (os.path.basename(path), os.getpid()))
    try:
        fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o400)
    except OSError as e:
        raise HsmSecretError("could not create %s: %s" % (tmp, e.strerror))
    try:
        try:
            # set the mode explicitly, independent of the umask
            os.fchmod(fd, 0o400)
            view = memoryview(secret)
            while view:
                view = view[os.write(fd, view):]
            os.fsync(fd)
        finally:
            os.close(fd)
        os.link(tmp, path)
    except OSError as e:
        raise HsmSecretError("could not write %s: %s" % (path, e.strerror))
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    # persist the new directory entry
    try:
        dirfd = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(dirfd)
        finally:
            os.close(dirfd)
    except OSError as e:
        raise HsmSecretError("could not sync %s: %s" % (directory, e.strerror))


def main(argv, stdin=None, stdout=sys.stdout):
    """stdin is a binary stream (default: sys.stdin.buffer)."""
    if stdin is None:
        stdin = sys.stdin.buffer
    try:
        if len(argv) == 2 and argv[1] == "derive":
            derive(stdin, stdout)
        elif len(argv) == 3 and argv[1] == "write":
            write_hsm_secret(
                argv[2], parse_secret_hex(stdin.read().decode("ascii", "replace")))
        else:
            sys.stderr.write(__doc__ or "")
            return 2
    except HsmSecretError as e:
        sys.stderr.write("# ERROR cl.hsmsecret.py: %s\n" % e)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
