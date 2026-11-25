#!/usr/bin/python3
"""Recording/fault-injection boundaries; APT, dpkg and GPG remain real tools."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

name = Path(sys.argv[0]).name
args = sys.argv[1:]
root = Path(os.environ['CASE'])
mode = os.environ.get('FAULT', '')
with (root / 'events').open('a') as out:
    out.write(json.dumps([name, *args]) + '\n')


def real(tool, argv):
    return subprocess.run(['/usr/bin/' + tool, *argv],
                          env=dict(os.environ, PATH='/usr/sbin:/usr/bin:/sbin:/bin')).returncode


def fail(tag):
    (root / 'reached').write_text(tag)
    sys.exit(1)


if name == 'sudo':
    os.execvp(args[0], args)
elif name == 'mktemp':
    target = ' '.join(args)
    if ((mode == 'update-stage' and '/var/tmp/tor-update.' in target) or
            (mode == 'source-stage' and '/tor-source.' in target) or
            (mode == 'key-stage' and args == ['-d'])):
        fail(mode)
    sys.exit(real(name, args))
elif name == 'install':
    if mode == 'keyring-install' and args[-1] == '/usr/share/keyrings/torproject.gpg':
        fail(mode)
    sys.exit(real(name, args))
elif name == 'tee':
    if mode == 'sources-write' and args[-1] == '/etc/apt/sources.list.d/tor.list':
        fail(mode)
    sys.exit(real(name, args))
elif name == 'setcap':
    sys.exit(0)
elif name == 'lsb_release':
    print('jammy')
elif name == 'curl':
    onion = '-x' in args
    if mode == 'key-download' or (onion and mode == 'key-retry'):
        fail('key-download')
    key = '/fixture/key.asc'
    if mode == 'bundled-key':
        key = '/fixture/bundle.asc'
        (root / 'reached').write_text(mode)
    if '-o' in args:
        shutil.copy(key, args[args.index('-o') + 1])
    else:
        sys.stdout.write(Path(key).read_text())
elif name == 'gpg':
    if '--show-keys' in args:
        if mode == 'key-inspect':
            fail(mode)
        result = subprocess.run(['/usr/bin/gpg', *args], capture_output=True)
        # Only the external identity is mocked: a disposable test key cannot
        # have the production Tor key fingerprint. Parsing/dearmor are real.
        text = result.stdout.decode()
        fingerprint = Path('/fixture/fingerprint').read_text()
        identity = 'A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89'
        if mode == 'key-fingerprint':
            (root / 'reached').write_text(mode)
            # A matching short prefix must not authenticate a different key.
            identity = 'A3C4' + '0' * 36
        def human(value):
            groups = [value[i:i + 4] for i in range(0, 40, 4)]
            return ' '.join(groups[:5]) + '  ' + ' '.join(groups[5:])
        text = text.replace(fingerprint, identity).replace(human(fingerprint), human(identity))
        print(text, end='')
        sys.exit(result.returncode)
    if mode == 'key-dearmor':
        fail(mode)
    sys.exit(real('gpg', args))
elif name == 'dpkg-query':
    if mode == 'missing-package':
        fail(mode)
    sys.exit(real(name, args))
elif name == 'dpkg':
    if args == ['--print-architecture']:
        print(os.environ['ARCH'])
    elif '-i' in args and mode == 'rollback-failure' and args[-1].endswith('previous.deb'):
        fail(mode)
    elif '-i' in args and mode == 'source-install' and not args[-1].endswith('previous.deb'):
        real(name, args)
        fail(mode)
    else:
        sys.exit(real(name, args))
elif name == 'apt':
    if args[0] == 'download' and mode == 'backup-download':
        fail(mode)
    if 'update' in args:
        if mode == 'signature':
            p = root / 'repo/InRelease'
            p.write_text(p.read_text().replace('Date:', 'Fake:'))
            (root / 'reached').write_text(mode)
        sys.exit(real('apt-get', ['-o', 'APT::Update::Error-Mode=any', *args]))
    if args[0] == 'source':
        if mode == 'source-download':
            fail(mode)
        if mode == 'source-layout':
            (root / 'reached').write_text(mode)
        else:
            Path('tor-0.4.9.1').mkdir()
        sys.exit(0)
    if args[0] == 'build-dep' or 'build-essential' in args:
        if mode in ('build-dep', 'build-tools') and ((args[0] == 'build-dep') == (mode == 'build-dep')):
            fail(mode)
        sys.exit(0)
    if 'install' in args and 'tor' not in args:
        if mode == 'transport-download' and '--download-only' in args:
            fail(mode)
        if mode == 'transport-install' and '--download-only' not in args:
            fail(mode)
        sys.exit(0)
    if '--download-only' in args:
        package = root / 'repo/tor_0.4.9.1_all.deb'
        if mode == 'checksum':
            package.write_bytes(package.read_bytes() + b'tampered')
            (root / 'reached').write_text(mode)
        if mode == 'download':
            package.unlink()
            (root / 'reached').write_text(mode)
    result = real('apt-get', args)
    if 'install' in args and '--download-only' not in args and mode == 'signal':
        import signal
        (root / 'reached').write_text(mode)
        os.kill(os.getppid(), signal.SIGTERM)
        sys.exit(1)
    if 'install' in args and '--download-only' not in args and mode == 'old-version':
        real('dpkg', ['-i', '/fixture/tor_0.4.8.1_all.deb'])
        (root / 'reached').write_text(mode)
    if 'install' in args and '--download-only' not in args and mode in ('apt-install', 'rollback-failure'):
        (root / 'service').write_text('stopped')
        fail(mode)
    sys.exit(result)
elif name == 'debuild':
    if mode == 'build':
        fail(mode)
    if mode != 'missing-build':
        version = '0.4.8.1' if mode == 'old-version' else '0.4.9.1'
        shutil.copy(f'/fixture/tor_{version}_all.deb', f'../tor_{version}_all.deb')
        if mode == 'multiple-build':
            shutil.copy('/fixture/tor_0.4.8.1_all.deb', '../tor_0.4.8.1_all.deb')
            (root / 'reached').write_text(mode)
        if mode == 'old-version':
            (root / 'reached').write_text(mode)
    else:
        (root / 'reached').write_text(mode)
elif name == 'systemctl':
    if args[0] == 'cat':
        sys.exit(0 if os.environ['UNIT'] == 'tor@default' else 1)
    if args[0] == 'disable':
        (root / 'service').write_text('stopped')
    if args[0] == 'stop':
        (root / 'service').write_text('stopped')
        if mode == 'stop':
            fail(mode)
    if args[0] == 'restart':
        marker = root / 'restart-failed'
        if mode in ('restart', 'restart-permanent') and (not marker.exists() or mode == 'restart-permanent'):
            (root / 'service').write_text('stopped')
            marker.touch()
            fail(mode)
        (root / 'service').write_text('running')
else:
    raise RuntimeError('unexpected shim: ' + name)
