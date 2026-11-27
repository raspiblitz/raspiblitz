#!/usr/bin/env python3
"""Publish a private, stable copy of a submitted setup record for provisioning."""

import grp
import os
import stat
import sys
import tempfile
from pathlib import Path


def freeze(source: Path, destination: Path) -> None:
    fd = os.open(source, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    with os.fdopen(fd, "rb") as submitted:
        attrs = os.fstat(fd)
        admin_group = grp.getgrnam("admin").gr_gid
        if not stat.S_ISREG(attrs.st_mode) or attrs.st_gid != admin_group or attrs.st_mode & 0o007:
            raise ValueError("unexpected setup record permissions")
        # Read one bounded request. A record contains settings and seed text, never an uploaded file.
        data = submitted.read(65537)
        if not data or len(data) > 65536:
            raise ValueError("unexpected setup record size")
    with tempfile.NamedTemporaryFile(dir=destination.parent, delete=False) as out:
        try:
            out.write(data)
            out.flush()
            os.fchown(out.fileno(), 0, admin_group)
            os.fchmod(out.fileno(), 0o640)
            os.replace(out.name, destination)
        finally:
            Path(out.name).unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        freeze(Path(sys.argv[1]), Path(sys.argv[2]))
    except (OSError, ValueError, KeyError):
        sys.exit("Unable to accept the submitted setup record.")
