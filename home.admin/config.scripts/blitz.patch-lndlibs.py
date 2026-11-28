"""Retire an unremovable lndlibs bytecode cache during an SSH PATCH update."""

import ctypes
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile


def retire(staged_parent, live_parent):
    if os.geteuid() == 0:
        raise ValueError("run the PATCH cache handoff as admin, not root")
    flags = os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW
    try:
        live_fd = os.open(live_parent, flags)
    except FileNotFoundError:
        return
    try:
        try:
            library_fd = os.open("lndlibs", flags, dir_fd=live_fd)
        except FileNotFoundError:
            return
        try:
            try:
                mode = os.stat("__pycache__", dir_fd=library_fd, follow_symlinks=False).st_mode
            except FileNotFoundError:
                return
            if not stat.S_ISDIR(mode) or os.access("__pycache__", os.W_OK | os.X_OK, dir_fd=library_fd):
                return
        finally:
            os.close(library_fd)

        # Keep retired code outside Python's import paths. Debian's normal
        # /var/tmp policy can expire the private tree without privileged PATCH code.
        quarantine = Path(tempfile.mkdtemp(prefix="raspiblitz-retired-lndlibs-", dir="/var/tmp"))
        source = staged_parent / "lndlibs"
        retired = quarantine / "lndlibs"
        try:
            if os.fstat(live_fd).st_dev != quarantine.stat().st_dev:
                raise ValueError("cannot retire lndlibs: /var/tmp and the live library must share a filesystem")
            if source.is_symlink():
                raise ValueError("expected a real staged lndlibs directory")
            if source.exists():
                shutil.copytree(source, retired, symlinks=True, ignore=shutil.ignore_patterns("__pycache__"))
                # RENAME_EXCHANGE swaps whole directories without a gap for imports.
                libc = ctypes.CDLL(None, use_errno=True)
                if libc.renameat2(-100, os.fsencode(retired), live_fd, b"lndlibs", 2):
                    error = ctypes.get_errno()
                    raise OSError(error, os.strerror(error))
            else:
                # The selected branch no longer ships the library.
                os.rename("lndlibs", retired, src_dir_fd=live_fd)
        except (OSError, ValueError, AttributeError):
            # A failed rename leaves only our own prepared copy here.
            shutil.rmtree(quarantine)
            raise
        print(f"Retired previous lndlibs under {quarantine}", file=sys.stderr)
        print("replaced")
    finally:
        os.close(live_fd)


if __name__ == "__main__":
    try:
        retire(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError, AttributeError) as exc:
        sys.exit(f"PATCH cannot retire Python bytecode: {exc}")
