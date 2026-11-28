"""Publish a complete RaspiBlitz WebUI build on the same filesystem as nginx."""

import ctypes
import os
from html.parser import HTMLParser
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import unquote, urlsplit


class EntryAssets(HTMLParser):
    def __init__(self):
        super().__init__()
        self.references = []

    def handle_starttag(self, tag, attrs):
        attributes = dict(attrs)
        if tag == "script" and attributes.get("src"):
            self.references.append(("script", attributes["src"]))
        if tag == "link" and "stylesheet" in (attributes.get("rel") or "").lower().split():
            self.references.append(("stylesheet", attributes.get("href") or ""))


def validate(bundle):
    parser = EntryAssets()
    parser.feed((bundle / "index.html").read_text(encoding="utf-8"))
    parser.close()
    has_entry = False
    for kind, reference in parser.references:
        url = urlsplit(reference)
        if url.scheme or url.netloc:
            continue
        path = (bundle / unquote(url.path).lstrip("/")).resolve()
        if bundle not in path.parents or not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"missing or invalid local {kind} in index.html")
        has_entry |= kind == "script"
    if not has_entry:
        raise ValueError("index.html has no local application script")


def publish(source, live):
    if source.is_symlink() or live.is_symlink():
        raise ValueError("expected a build directory and a real nginx document root")
    # Keep the copy private until every entry is validated. Creating the staging
    # directory next to the live tree also makes the atomic exchange possible.
    with tempfile.TemporaryDirectory(dir=live.parent, prefix=".webui-") as tmp:
        staged = Path(tmp).resolve() / "bundle"
        shutil.copytree(source, staged, symlinks=True, ignore=shutil.ignore_patterns(".*"))
        for path in staged.rglob("*"):
            if path.is_symlink() or not (path.is_file() or path.is_dir()):
                raise ValueError("unsupported entry in WebUI build")
            path.chmod(0o755 if path.is_dir() else 0o644)
        staged.chmod(0o755)
        validate(staged)
        if not live.exists():
            staged.rename(live)
            return
        if not live.is_dir():
            raise ValueError("nginx document root must be a directory")
        # The legacy updater only replaced public/*; retain operator-owned
        # hidden entries without following links to other locations.
        for entry in live.glob(".*"):
            target = staged / entry.name
            subprocess.run(["cp", "-a", "--", entry, target], check=True)
        old_stat = live.stat()
        os.chown(staged, old_stat.st_uid, old_stat.st_gid)
        shutil.copystat(live, staged)
        # Linux renameat2(RENAME_EXCHANGE) leaves the old directory in the
        # staging area for cleanup. Even a failed swap leaves the live UI intact.
        libc = ctypes.CDLL(None, use_errno=True)
        at_fdcwd, rename_exchange = -100, 2
        if libc.renameat2(at_fdcwd, os.fsencode(staged), at_fdcwd, os.fsencode(live), rename_exchange):
            error = ctypes.get_errno()
            raise OSError(error, os.strerror(error))


if __name__ == "__main__":
    try:
        live = Path(sys.argv[2])
        publish(Path(sys.argv[1]), live)
        if len(sys.argv) == 5:
            # Flush the tree and directory exchange before recording the commit.
            subprocess.run(["sync", "-f", live.parent], check=True)
            marker = Path(sys.argv[3])
            with tempfile.NamedTemporaryFile(mode="w", dir=marker.parent, delete=False) as stamp:
                stamp.write(sys.argv[4] + "\n")
                stamp.flush()
                os.fsync(stamp.fileno())
            try:
                os.replace(stamp.name, marker)
                subprocess.run(["sync", "-f", marker.parent], check=True)
            finally:
                Path(stamp.name).unlink(missing_ok=True)
    except (OSError, ValueError, AttributeError, subprocess.CalledProcessError) as error:
        sys.exit(f"WebUI publication failed: {error}")
