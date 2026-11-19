#!/usr/bin/env python3
"""Branch-aware changed-code coverage gate for the TunnelSats integration (stdlib only).

Reads a coverage.py JSON report (`coverage json -o coverage.json`) generated with
`--branch` and enforces minimum statement and branch coverage across:
  - home.admin/config.scripts/blitz.subscriptions.tunnelsats.py (full file)
  - home.admin/config.scripts/blitz.subscriptions.py (changed lines vs --base-ref)
  - test/tunnelsats/schema_check.py (full file)
"""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys


FULL_TARGETS = (
    "home.admin/config.scripts/blitz.subscriptions.tunnelsats.py",
    "test/tunnelsats/schema_check.py",
)

DIFF_TARGETS = (
    "home.admin/config.scripts/blitz.subscriptions.py",
)

HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@", re.MULTILINE)


def _normalize_path(raw_path, repo_root):
    text = str(raw_path).replace("\\", "/")
    root_prefix = str(repo_root.resolve()).replace("\\", "/").rstrip("/") + "/"
    if text.startswith(root_prefix):
        text = text[len(root_prefix):]
    while text.startswith("./"):
        text = text[2:]
    return text


def _format_line_ranges(lines):
    if not lines:
        return "none"
    ordered = sorted(set(lines))
    ranges = []
    start = prev = ordered[0]
    for num in ordered[1:]:
        if num == prev + 1:
            prev = num
        else:
            ranges.append(f"{start}-{prev}" if start != prev else str(start))
            start = prev = num
    ranges.append(f"{start}-{prev}" if start != prev else str(start))
    return ", ".join(ranges)


def _format_branches(branches):
    if not branches:
        return "none"
    formatted = []
    for src, dst in sorted(branches):
        dst_label = "exit" if dst < 0 else str(dst)
        formatted.append(f"{src}->{dst_label}")
    return ", ".join(formatted)


def _git_changed_lines(repo_root, base_ref, relpath):
    """Return the set of added/modified line numbers in relpath relative to base_ref."""
    merge_base = subprocess.run(
        ["git", "merge-base", base_ref, "HEAD"],
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    diff_base = merge_base.stdout.strip() if merge_base.returncode == 0 else base_ref

    diff_proc = subprocess.run(
        ["git", "diff", "--unified=0", diff_base, "--", relpath],
        cwd=str(repo_root),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if diff_proc.returncode != 0:
        raise RuntimeError(
            f"git diff failed for {relpath} against {diff_base}: {diff_proc.stderr.strip()}"
        )

    changed = set()
    for match in HUNK_RE.finditer(diff_proc.stdout):
        start = int(match.group(1))
        count = int(match.group(2)) if match.group(2) is not None else 1
        if count > 0:
            changed.update(range(start, start + count))
    return changed


def _evaluate_entry(relpath, scope, entry, filter_lines, min_line, min_branch):
    if entry is None:
        return {
            "file": relpath,
            "scope": scope,
            "exec_lines": 0,
            "total_lines": 0,
            "line_pct": 0.0,
            "exec_branches": 0,
            "total_branches": 0,
            "branch_pct": 0.0,
            "missing_lines": [],
            "missing_branches": [],
            "passed": False,
            "error": "missing from coverage JSON",
        }

    raw_exec_lines = set(entry.get("executed_lines", []))
    raw_miss_lines = set(entry.get("missing_lines", []))
    raw_exec_branches = [tuple(b) for b in entry.get("executed_branches", [])]
    raw_miss_branches = [tuple(b) for b in entry.get("missing_branches", [])]

    if filter_lines is not None:
        exec_lines = sorted(raw_exec_lines & filter_lines)
        miss_lines = sorted(raw_miss_lines & filter_lines)
        exec_branches = [b for b in raw_exec_branches if b[0] in filter_lines]
        miss_branches = [b for b in raw_miss_branches if b[0] in filter_lines]
    else:
        exec_lines = sorted(raw_exec_lines)
        miss_lines = sorted(raw_miss_lines)
        exec_branches = raw_exec_branches
        miss_branches = raw_miss_branches

    total_lines = len(exec_lines) + len(miss_lines)
    total_branches = len(exec_branches) + len(miss_branches)
    line_pct = (100.0 * len(exec_lines) / total_lines) if total_lines else 100.0
    branch_pct = (100.0 * len(exec_branches) / total_branches) if total_branches else 100.0
    passed = (line_pct + 1e-9 >= min_line) and (branch_pct + 1e-9 >= min_branch)

    return {
        "file": relpath,
        "scope": scope,
        "exec_lines": len(exec_lines),
        "total_lines": total_lines,
        "line_pct": line_pct,
        "exec_branches": len(exec_branches),
        "total_branches": total_branches,
        "branch_pct": branch_pct,
        "missing_lines": miss_lines,
        "missing_branches": miss_branches,
        "passed": passed,
        "error": None,
    }


def _print_report(results, min_line, min_branch):
    header = (
        f"{'File':<60} {'Scope':<9} {'Lines':>11} {'Line%':>7} "
        f"{'Branches':>11} {'Br%':>7} {'Status':<6}"
    )
    sep = "-" * len(header)
    print(header)
    print(sep)
    for row in results:
        lines_col = f"{row['exec_lines']}/{row['total_lines']}"
        branches_col = f"{row['exec_branches']}/{row['total_branches']}"
        status = "PASS" if row["passed"] else "FAIL"
        print(
            f"{row['file']:<60} {row['scope']:<9} {lines_col:>11} {row['line_pct']:>6.2f}% "
            f"{branches_col:>11} {row['branch_pct']:>6.2f}% {status:<6}"
        )
    print(sep)
    print(f"Thresholds: line >= {min_line:.1f}%, branch >= {min_branch:.1f}%")

    for row in results:
        if row["error"]:
            print(f"\n[FAIL] {row['file']}: {row['error']}")
            continue
        if row["missing_lines"] or row["missing_branches"]:
            marker = "FAIL" if not row["passed"] else "INFO"
            print(f"\n[{marker}] {row['file']} ({row['scope']}):")
            if row["missing_lines"]:
                print(f"  Uncovered lines:    {_format_line_ranges(row['missing_lines'])}")
            if row["missing_branches"]:
                print(f"  Uncovered branches: {_format_branches(row['missing_branches'])}")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description="Verify branch-aware statement and branch coverage for TunnelSats Python code."
    )
    parser.add_argument("--json", required=True, dest="json_path", help="Path to coverage.json report")
    parser.add_argument(
        "--base-ref",
        default="HEAD~1",
        help="Git base ref used to compute changed lines for modified files (default: HEAD~1)",
    )
    parser.add_argument(
        "--min-line",
        type=float,
        default=100.0,
        help="Minimum required statement coverage percentage (default: 100.0)",
    )
    parser.add_argument(
        "--min-branch",
        type=float,
        default=100.0,
        help="Minimum required branch coverage percentage (default: 100.0)",
    )
    parser.add_argument(
        "--repo-root",
        default=str(Path(__file__).resolve().parents[2]),
        help="Repository root directory (default: auto-detected)",
    )
    args = parser.parse_args(argv)

    repo_root = Path(args.repo_root).resolve()
    try:
        with open(args.json_path, encoding="utf-8") as handle:
            report = json.load(handle)
    except (OSError, ValueError) as exc:
        print(f"ERROR: could not read coverage report {args.json_path}: {exc}", file=sys.stderr)
        return 1

    if not report.get("meta", {}).get("branch_coverage"):
        print("ERROR: coverage JSON report was not generated with --branch", file=sys.stderr)
        return 1

    files_by_rel = {
        _normalize_path(path, repo_root): entry
        for path, entry in report.get("files", {}).items()
    }

    results = []
    for relpath in FULL_TARGETS:
        results.append(
            _evaluate_entry(
                relpath,
                "full",
                files_by_rel.get(relpath),
                None,
                args.min_line,
                args.min_branch,
            )
        )

    for relpath in DIFF_TARGETS:
        try:
            changed = _git_changed_lines(repo_root, args.base_ref, relpath)
        except RuntimeError as exc:
            print(f"ERROR: {exc}", file=sys.stderr)
            return 1
        results.append(
            _evaluate_entry(
                relpath,
                "changed",
                files_by_rel.get(relpath),
                changed,
                args.min_line,
                args.min_branch,
            )
        )

    _print_report(results, args.min_line, args.min_branch)
    return 0 if all(row["passed"] for row in results) else 1


if __name__ == "__main__":
    sys.exit(main())
