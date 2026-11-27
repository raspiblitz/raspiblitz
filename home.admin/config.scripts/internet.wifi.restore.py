"""Install saved NetworkManager keyfiles without inheriting permissions or links."""

import fcntl
import hashlib
import os
import shutil
import stat
import sys
import tempfile
from pathlib import Path


def restore_profiles(source: Path, target: Path) -> None:
    target_fd = os.open(target, os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        fcntl.flock(target_fd, fcntl.LOCK_EX)
        _restore(source, target, target_fd)
    finally:
        os.close(target_fd)


def _restore(source: Path, target: Path, target_fd: int) -> None:
    source_fd = os.open(source, os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        with tempfile.TemporaryDirectory(dir=target) as staging:
            records = []
            manifest = hashlib.sha256()
            for name in sorted(os.listdir(source_fd)):
                if name.startswith("."):
                    continue
                if not stat.S_ISREG(os.stat(name, dir_fd=source_fd, follow_symlinks=False).st_mode):
                    raise ValueError("backup contains a non-regular profile")
                fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK, dir_fd=source_fd)
                with os.fdopen(fd, "rb") as src:
                    if not stat.S_ISREG(os.fstat(src.fileno()).st_mode):
                        raise ValueError("backup contains a non-regular profile")
                    with tempfile.NamedTemporaryFile(dir=staging, delete=False) as out:
                        shutil.copyfileobj(src, out)
                        out.flush()
                        os.fsync(out.fileno())
                    with open(out.name, "rb") as copied:
                        digest = hashlib.sha256()
                        for block in iter(lambda: copied.read(65536), b""):
                            digest.update(block)
                    manifest.update(os.fsencode(name) + b"\0" + digest.digest())
                    records.append((out.name, target / name))
            if not records:
                raise ValueError("backup contains no profiles")
            # An interrupted set must be replayed from the same backup before
            # the next boot can back up a partially restored configuration.
            marker = target / ".raspiblitz-restore-pending"
            expected = manifest.hexdigest()
            if marker.exists():
                if marker.read_text(encoding="ascii") != expected:
                    raise ValueError("different backup already pending")
            else:
                with tempfile.NamedTemporaryFile(dir=staging, mode="w", encoding="ascii", delete=False) as state:
                    state.write(expected)
                    state.flush()
                    os.fsync(state.fileno())
                os.replace(state.name, marker)
                os.fsync(target_fd)
            for staged, destination in records:
                os.replace(staged, destination)
            os.fsync(target_fd)
            marker.unlink()
            os.fsync(target_fd)
    finally:
        os.close(source_fd)


if __name__ == "__main__":
    try:
        restore_profiles(Path(sys.argv[1]), Path("/etc/NetworkManager/system-connections"))
    except (OSError, ValueError):
        sys.exit("Wi-Fi profile restore failed; check backup files and write access.")
