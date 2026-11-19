#!/usr/bin/env python3
"""Run the unchanged production entrypoint against local RPC processes, in Docker only."""
import json
import os
from pathlib import Path
import shlex
import signal
import socket
import socketserver
import subprocess
import threading
import time
import unittest

ROOT = Path('/src')
MONITOR = ROOT / 'home.admin/config.scripts/bitcoin.monitor.sh'
STATE = Path('/tmp/monitor-test')
GOOD = {'connections': 3, 'localaddresses': [{'address': '127.0.0.1', 'port': 8333}]}
CHAIN = {'headers': 100, 'blocks': 100, 'initialblockdownload': False,
         'verificationprogress': 1}

CLIENT = r'''#!/usr/bin/python3
import json, os, signal, socket, subprocess, sys
from pathlib import Path
if '-version' in sys.argv:
    print('Bitcoin Core RPC client version v28.0.0')
    sys.exit(0)
state = Path('/tmp/monitor-test')
with (state / 'pids').open('a') as f:
    f.write(str(os.getpid()) + '\n')
mode = json.loads((state / 'modes').read_text()).get(sys.argv[-1], {})
if mode.get('stubborn'):
    signal.signal(signal.SIGTERM, signal.SIG_IGN)
    child = subprocess.Popen(['/usr/bin/python3', '-c',
        'import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(60)'])
    with (state / 'pids').open('a') as f:
        f.write(str(child.pid) + '\n')
with socket.create_connection(('127.0.0.1', int((state / 'port').read_text()))) as sock:
    sock.sendall((sys.argv[-1] + '\n').encode())
    response = sock.makefile().read()
result = json.loads(response)
sys.stdout.write(result.get('out', ''))
sys.stderr.write(result.get('err', ''))
sys.exit(result.get('code', 0))
'''


class RPC(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


class Handler(socketserver.StreamRequestHandler):
    def handle(self):
        method = self.rfile.readline().decode().strip()
        modes = json.loads((STATE / 'modes').read_text())
        mode = modes.get(method, {})
        time.sleep(mode.get('delay', 0))
        result = {'out': mode.get('out', json.dumps({
            'getnetworkinfo': GOOD, 'getpeerinfo': [{'network': 'onion'}, {'network': 'i2p'}],
            'getconnectioncount': 3, 'getblockchaininfo': CHAIN,
            'getmempoolinfo': {'size': 7}}[method], indent=2)),
            'code': mode.get('code', 0), 'err': mode.get('err', '')}
        try:
            self.wfile.write(json.dumps(result).encode())
        except (BrokenPipeError, ConnectionResetError):
            pass


class MonitorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if os.environ.get('MONITOR_TEST_CONTAINER') != '1' or not Path('/.dockerenv').exists():
            raise RuntimeError('Disposable test container required; never run fixtures on a node')
        STATE.mkdir()
        Path('/var/cache/raspiblitz').mkdir(parents=True, exist_ok=True)
        Path('/mnt/hdd/bitcoin/blocks').mkdir(parents=True)
        Path('/usr/local/bin/bitcoin-cli').write_text(CLIENT)
        Path('/usr/local/bin/bitcoin-cli').chmod(0o755)
        for name, text in {
            'systemctl': '#!/bin/sh\n[ "$1" = status ] || exit 99\necho "active (running)"\n',
            'ss': '#!/bin/sh\nprintf "peer1\\npeer2\\n"\n',
        }.items():
            path = Path('/usr/local/bin') / name
            path.write_text(text)
            path.chmod(0o755)
        cls.server = RPC(('127.0.0.1', 0), Handler)
        (STATE / 'port').write_text(str(cls.server.server_address[1]))
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        (STATE / 'modes').write_text('{}')
        (STATE / 'pids').write_text('')
        (STATE / 'port').write_text(str(self.server.server_address[1]))

    def tearDown(self):
        try:
            self.assert_no_clients()
        finally:
            # Clean up even when testing a broken revision, without masking the failure.
            for pid in (STATE / 'pids').read_text().splitlines():
                try:
                    os.kill(int(pid), signal.SIGKILL)
                except ProcessLookupError:
                    pass
            for path in Path('/var/cache/raspiblitz').glob('.bitcoind-*'):
                path.unlink()

    def modes(self, **modes):
        (STATE / 'modes').write_text(json.dumps(modes))

    def run_monitor(self, action='status', deadline='0.5', net='mainnet'):
        started = time.monotonic()
        result = subprocess.run(['bash', str(MONITOR), net, action], capture_output=True,
                                text=True, timeout=6,
                                env={**os.environ, 'BITCOIN_MONITOR_RPC_TIMEOUT': deadline})
        elapsed = time.monotonic() - started
        values = {}
        for line in result.stdout.splitlines():
            key, value = line.split('=', 1)
            values[key] = shlex.split(value)[0] if value else ''
        self.assertLess(elapsed, 4, result)
        self.assertEqual(list(Path('/var/cache/raspiblitz').glob('.bitcoind-*')), [])
        return result, values, elapsed

    def assert_degraded(self, short):
        result, values, elapsed = self.run_monitor()
        self.assertEqual(result.returncode, 0, result)
        self.assertEqual(values['btc_running'], '1')
        self.assertEqual(values['btc_ready'], '0')
        self.assertEqual(values['btc_online'], '0')
        self.assertEqual(values['btc_error_short'], short)
        return elapsed

    def assert_no_clients(self):
        # PID 1 in minimal containers may retain killed zombies; these cannot run
        # or retain pipes. Reject every live recorded client/descendant.
        for pid in (STATE / 'pids').read_text().splitlines():
            stat = Path('/proc') / pid / 'stat'
            if stat.exists():
                self.assertEqual(stat.read_text().split()[2], 'Z', f'live RPC process {pid}')

    def test_status_success_all_networks(self):
        for net in ('mainnet', 'testnet', 'signet'):
            with self.subTest(net=net):
                result, values, _ = self.run_monitor(net=net)
                self.assertEqual(result.returncode, 0)
                self.assertEqual(values['btc_running'], '1')
                self.assertEqual(values['btc_ready'], '1')
                self.assertEqual(values['btc_online'], '1')
                self.assertEqual(values['btc_error_short'], '')

    def test_status_zero_connections_is_ready_but_offline(self):
        self.modes(getnetworkinfo={'out': '{"connections":0}'})
        _, values, _ = self.run_monitor()
        self.assertEqual((values['btc_ready'], values['btc_online']), ('1', '0'))

    def test_connection_refused(self):
        # Reserve an unlistened local port: real connect(2) ECONNREFUSED.
        with socket.socket() as closed:
            closed.bind(('127.0.0.1', 0))
            (STATE / 'port').write_text(str(closed.getsockname()[1]))
            result, values, _ = self.run_monitor()
        self.assertEqual(result.returncode, 0)
        self.assertEqual((values['btc_running'], values['btc_ready']), ('1', '0'))
        self.assertIn('Connection refused', values['btc_error_full'])

    def test_timeout_degraded(self):
        self.modes(getnetworkinfo={'delay': 2})
        self.assertGreater(self.assert_degraded('RPC timeout'), 0.45)

    def test_timeout_with_stderr(self):
        # A diagnostic before blocking must not obscure the timeout identity.
        client = Path('/usr/local/bin/bitcoin-cli')
        original = client.read_text()
        client.write_text(original.replace('mode = json.loads',
                          "sys.stderr.write('RPC still waiting\\n'); sys.stderr.flush()\nmode = json.loads"))
        try:
            self.modes(getnetworkinfo={'delay': 2})
            self.assert_degraded('RPC timeout')
        finally:
            client.write_text(original)

    def test_status_invalid_output(self):
        for output in ('', '{bad', '{}', 'null', '[]', '{"connections":"3oops"}',
                       '{"connections":-3}', '{"connections":1.5}',
                       '{"connections":3}\n{"connections":4}'):
            with self.subTest(output=output):
                self.modes(getnetworkinfo={'out': output})
                self.assert_degraded('Invalid RPC response')

    def test_response_inside_deadline(self):
        self.modes(getnetworkinfo={'delay': 0.8})
        result, values, elapsed = self.run_monitor(deadline='1')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(values['btc_ready'], '1')
        self.assertGreater(elapsed, 0.75)

    def test_response_outside_deadline(self):
        self.modes(getnetworkinfo={'delay': 1.2})
        result, values, elapsed = self.run_monitor(deadline='1')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(values['btc_error_short'], 'RPC timeout')
        self.assertEqual(values['btc_running'], '1')
        self.assertLess(elapsed, 1.2)

    def test_network_success(self):
        result, values, _ = self.run_monitor('network')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(values['btc_peers'], '3')
        self.assertEqual(values['btc_peers_onion'], '1')
        self.assertEqual(values['btc_peers_i2p'], '1')
        self.assertEqual(values['btc_address'], '127.0.0.1')

    def test_network_fallback(self):
        for mode in ({'delay': 2}, {'out': ''}, {'out': '{bad'}, {'out': 'null'},
                     {'code': 1, 'out': json.dumps(GOOD)}):
            with self.subTest(mode=mode):
                self.modes(getnetworkinfo=mode)
                result, values, _ = self.run_monitor('network')
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual(values['btc_peers'], '3')
                self.assertEqual(values['btc_address'], '')

    def test_peerinfo_timeout_preserves_count(self):
        self.modes(getpeerinfo={'delay': 2})
        result, values, _ = self.run_monitor('network')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(values['btc_peers'], '3')
        self.assertEqual(values['btc_peers_onion'], '0')

    def test_connection_count_fallback_to_sockets(self):
        for mode in ({'delay': 2}, {'out': ''}, {'out': 'error 42'},
                     {'code': 1, 'out': '9'}):
            with self.subTest(mode=mode):
                self.modes(getnetworkinfo={'out': ''}, getconnectioncount=mode)
                result, values, _ = self.run_monitor('network')
                self.assertEqual(result.returncode, 0)
                self.assertEqual(values['btc_peers'], '2')

    def test_info_success(self):
        for progress in (0, 0.5, 1e-8, 1):
            with self.subTest(progress=progress):
                self.modes(getblockchaininfo={'out': json.dumps(
                    {**CHAIN, 'verificationprogress': progress})})
                result, values, _ = self.run_monitor('info')
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual(result.stderr, '')
                self.assertEqual(values['btc_synced'], '1')

    def test_info_invalid_numeric_fields(self):
        for field in ('headers', 'blocks', 'verificationprogress'):
            invalid = ('-1', '1.5', '2147483648', '9007199254740992',
                       '1e100', '1e999', '-1e999', 'NaN', 'null', '"1"')
            if field == 'verificationprogress':
                invalid += ('1.000001', '-0.000001')
            for value in invalid:
                with self.subTest(field=field, value=value):
                    chain = {**CHAIN, field: 'INVALID_NUMBER'}
                    output = json.dumps(chain).replace('"INVALID_NUMBER"', value)
                    self.modes(getblockchaininfo={'out': output})
                    result, values, _ = self.run_monitor('info')
                    self.assertEqual(result.returncode, 1, result)
                    self.assertEqual(values, {'error': 'no data'})
                    self.assertEqual(result.stderr, '')

    def test_info_integer_boundaries_and_exponents(self):
        for literal, expected in (('0', '0'), ('2147483647', '2147483647'),
                                  ('1e6', '1000000'), ('1.0', '1')):
            with self.subTest(literal=literal):
                output = ('{"headers":' + literal + ',"blocks":' + literal +
                          ',"initialblockdownload":false,"verificationprogress":1}')
                self.modes(getblockchaininfo={'out': output})
                result, values, _ = self.run_monitor('info')
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual(result.stderr, '')
                self.assertEqual(values['btc_blocks_headers'], expected)
                self.assertEqual(values['btc_blocks_verified'], expected)
                self.assertEqual(values['btc_blocks_behind'], '0')
                self.assertEqual(values['btc_synced'], '1')
        # Exercise the widest accepted subtraction in both directions.
        for headers, blocks in ((2147483647, 0), (0, 2147483647)):
            self.modes(getblockchaininfo={'out': json.dumps(
                {**CHAIN, 'headers': headers, 'blocks': blocks})})
            result, values, _ = self.run_monitor('info')
            self.assertEqual(result.returncode, 0, result)
            self.assertEqual(result.stderr, '')
            self.assertEqual(values['btc_blocks_behind'], str(headers - blocks))

    def test_mempool_invalid_sizes(self):
        for value in ('-1', '1.5', '2147483648', '9007199254740992',
                      '1e100', '1e999', '-1e999', 'NaN', 'null', '"1"'):
            with self.subTest(value=value):
                self.modes(getmempoolinfo={'out': '{"size":' + value + '}'})
                result, values, _ = self.run_monitor('mempool')
                self.assertEqual(result.returncode, 1, result)
                self.assertEqual(values, {'error': 'no data'})
                self.assertEqual(result.stderr, '')

    def test_mempool_integer_boundaries_and_exponents(self):
        for literal, expected in (('0', '0'), ('2147483647', '2147483647'),
                                  ('1e6', '1000000'), ('1.0', '1')):
            with self.subTest(literal=literal):
                self.modes(getmempoolinfo={'out': '{"size":' + literal + '}'})
                result, values, _ = self.run_monitor('mempool')
                self.assertEqual(result.returncode, 0, result)
                self.assertEqual(result.stderr, '')
                self.assertEqual(values['btc_mempool_transactions'], expected)

    def test_mempool_success(self):
        result, values, _ = self.run_monitor('mempool')
        self.assertEqual(result.returncode, 0)
        self.assertEqual(values['btc_mempool_transactions'], '7')

    def test_info_mempool_failures(self):
        for action, method in (('info', 'getblockchaininfo'), ('mempool', 'getmempoolinfo')):
            for mode in ({'delay': 2}, {'out': ''}, {'out': '{bad'}, {'out': 'null'},
                         {'code': 1, 'out': json.dumps(CHAIN if action == 'info' else {'size': 7})}):
                with self.subTest(action=action, mode=mode):
                    self.modes(**{method: mode})
                    result, values, _ = self.run_monitor(action)
                    self.assertEqual(result.returncode, 1, result)
                    self.assertEqual(values, {'error': 'no data'})

    def test_repeated_iterations_leave_no_processes(self):
        for i in range(8):
            self.modes(getnetworkinfo={'delay': 2} if i % 2 else {})
            result, values, _ = self.run_monitor()
            self.assertEqual(result.returncode, 0)
            self.assertEqual(values['btc_ready'], '0' if i % 2 else '1')
            self.assert_no_clients()

    def test_timeout_output_clears_stale_sourced_status(self):
        self.modes(getnetworkinfo={'delay': 2})
        result = subprocess.run(
            ['bash', '-c', 'btc_ready=1; btc_online=1; btc_running=0; '
             'source <(bash "$1" mainnet status); '
             '[[ "$btc_ready" = 0 && "$btc_online" = 0 && "$btc_running" = 1 '
             '&& "$btc_error_short" = "RPC timeout" ]]', 'test', str(MONITOR)],
            capture_output=True, text=True, timeout=6,
            env={**os.environ, 'BITCOIN_MONITOR_RPC_TIMEOUT': '0.5'})
        self.assertEqual(result.returncode, 0, result)

    def test_term_resistant_rpc_and_descendant_are_bounded(self):
        self.modes(getnetworkinfo={'delay': 60, 'stubborn': True})
        self.assert_degraded('RPC timeout')
        self.assert_no_clients()


if __name__ == '__main__':
    unittest.main(verbosity=2)
