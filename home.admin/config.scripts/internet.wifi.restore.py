"""Install saved NetworkManager keyfiles without inheriting permissions or links."""

import os
import shutil
import stat
import sys
import tempfile
from pathlib import Path


def restore_profiles(source: Path, target: Path) -> None:
    source_fd = os.open(source, os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        with tempfile.TemporaryDirectory(dir=target) as staging:
            records = []
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
                    records.append((out.name, target / name))
            if not records:
                raise ValueError("backup contains no profiles")
            for staged, destination in records:
                os.replace(staged, destination)
    finally:
        os.close(source_fd)


if __name__ == "__main__":
    try:
        restore_profiles(Path(sys.argv[1]), Path("/etc/NetworkManager/system-connections"))
    except (OSError, ValueError):
        sys.exit("Wi-Fi profile restore failed; check backup files and write access.")
