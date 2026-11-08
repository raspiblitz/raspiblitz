#!/usr/bin/env python3
"""Syntax-check every changed program; ratchet full-file ShellCheck diagnostics.

Legacy scripts already have warnings. Compare diagnostic code/message/source text
against the immutable pre-PR base, not line numbers, so moving a warning cannot
hide a new one. No files or ShellCheck codes are excluded.
"""
from collections import Counter
import json
import os
from pathlib import Path
import subprocess
import tempfile

BASE = os.environ.get('TRUST_TEST_BASE', 'c421693d')

def git(*args):
    return subprocess.check_output(['git', *args], text=True)


def diagnostics(path, text):
    result = subprocess.run(['shellcheck', '--format=json', str(path)], capture_output=True, text=True)
    if result.returncode not in (0, 1):
        raise RuntimeError(result.stderr)
    lines = text.splitlines()
    return Counter((d['code'], d['level'], d['message'],
                    '\n'.join(lines[d['line'] - 1:d['endLine']]))
                   for d in json.loads(result.stdout))


def main():
    names = set(git('diff', '--name-only', BASE, '--').splitlines())
    names.update(git('ls-files', '--others', '--exclude-standard').splitlines())
    checked = 0
    for name in sorted(names):
        path = Path(name)
        if not path.is_file():
            continue
        if path.suffix in ('.sh', '.bats'):
            syntax = ['bats', '--count'] if path.suffix == '.bats' else ['bash', '-n']
            subprocess.run([*syntax, str(path)], check=True)
            text = path.read_text()
            current = diagnostics(path, text)
            old = subprocess.run(['git', 'show', f'{BASE}:{name}'], capture_output=True, text=True)
            # Scratch file stays alongside the source so .shellcheckrc discovery
            # and relative source handling are identical for base and candidate.
            with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', dir=path.parent) as f:
                f.write(old.stdout)
                f.flush()
                previous = diagnostics(Path(f.name), old.stdout) if old.returncode == 0 else Counter()
            new = current - previous
            for diagnostic, count in new.items():
                print(name, count, diagnostic, flush=True)
            if new:
                raise AssertionError(f'{name}: new ShellCheck diagnostics')
            print(f'PASS bash syntax and full ShellCheck: {name} ({sum(current.values())} existing diagnostics)')
            checked += 1
        elif path.suffix == '.py':
            compile(path.read_bytes(), str(path), 'exec')
            print(f'PASS Python syntax: {name}')
        elif path.suffix == '.js':
            subprocess.run(['node', '--check', name], check=True)
            print(f'PASS Node syntax: {name}')
    assert checked >= 7, f'Unexpectedly narrow shell inventory: {checked}'
    subprocess.run(['git', 'diff', '--check'], check=True)
    print(f'PASS static checks over ALL {checked} changed shell paths; no new ShellCheck diagnostics')


if __name__ == '__main__':
    main()
