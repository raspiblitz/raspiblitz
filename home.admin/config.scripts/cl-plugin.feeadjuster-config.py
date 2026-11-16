#!/usr/bin/env python3
"""Fee-owned CLN lines only. Run as bitcoin; never persist config snapshots."""
import base64
import hashlib
import json
import os
import re
import sys

TAG = b"# raspiblitz-feeadjuster-disabled: "
OPTION = re.compile(rb"^[ \t]*feeadjuster(?:-[A-Za-z0-9_-]+)?[ \t]*(?:=|\r?$)")


def owned(line):
    return bool(OPTION.match(line) or
                (line.startswith(TAG) and OPTION.match(line[len(TAG):])))


def snapshot(lines):
    # Only fee lines leave this process; unrelated secrets stay in memory.
    rows = []
    other = []
    for line in lines:
        if owned(line):
            rows.append([len(other), base64.b64encode(line).decode("ascii")])
        else:
            other.append(line)
    return {"rows": rows, "other": hashlib.sha256(b"".join(other)).hexdigest()}


def main():
    mode, path = sys.argv[1:]
    # In-place update preserves ownership/mode and follows the existing config
    # symlink. No temporary config/backup containing unrelated secrets is made.
    with open(path, "r+b" if mode != "snapshot" else "rb") as config:
        original = config.read()
        lines = original.splitlines(keepends=True)
        if mode == "snapshot":
            print(base64.b64encode(json.dumps(snapshot(lines)).encode()).decode())
            return
        if mode == "restore":
            saved = json.loads(base64.b64decode(sys.stdin.buffer.read(), validate=True))
            current = snapshot(lines)
            if current["other"] != saved["other"]:
                raise RuntimeError("Unrelated config changed; manual fee rollback required")
            others = [line for line in lines if not owned(line)]
            slots = {}
            for position, value in saved["rows"]:
                slots.setdefault(position, []).append(base64.b64decode(value, validate=True))
            result = []
            for i in range(len(others) + 1):
                result.extend(slots.get(i, []))
                if i < len(others):
                    result.append(others[i])
            updated = b"".join(result)
        elif mode in ("park", "unpark"):
            updated = b"".join(
                TAG + line if mode == "park" and OPTION.match(line) else
                line[len(TAG):] if mode == "unpark" and line.startswith(TAG)
                and OPTION.match(line[len(TAG):]) else line
                for line in lines)
        else:
            raise ValueError("Unknown fee config operation")
        if updated == original:
            return
        try:
            config.seek(0)
            if config.write(updated) != len(updated):
                raise OSError("Short fee config write")
            config.truncate()
            config.flush()
            os.fsync(config.fileno())
            config.seek(0)
            if config.read() != updated:
                raise OSError("Fee config verification failed")
        except Exception:
            # Best effort immediate recovery, then caller retries from its
            # fee-only in-memory snapshot and reports any incomplete rollback.
            config.seek(0)
            if config.write(original) != len(original):
                raise OSError("Short fee config recovery write")
            config.truncate()
            config.flush()
            os.fsync(config.fileno())
            raise


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # Never print config contents (including option values) in diagnostics.
        print("Fee config operation failed: " + type(error).__name__, file=sys.stderr)
        sys.exit(1)
