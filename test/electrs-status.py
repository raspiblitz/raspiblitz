#!/usr/bin/env python3
"""Run the production status command with a loopback Electrum peer and a synthetic Core tip."""
import json
import os
from pathlib import Path
import socketserver
import subprocess
import sys
import tempfile
import threading

SCRIPT = Path(sys.argv[1]) if len(sys.argv) > 1 else (
    Path(__file__).resolve().parents[1] / "home.admin/config.scripts/bonus.electrs.sh"
)
HEADER = "00" * 80
HASH = "ab" * 32


class Peer(socketserver.StreamRequestHandler):
    def handle(self):
        request = json.loads(self.rfile.readline())
        assert request["method"] == "blockchain.headers.subscribe"
        self.wfile.write((json.dumps(self.server.reply) + "\n").encode())


with tempfile.TemporaryDirectory() as temp, socketserver.TCPServer(("127.0.0.1", 0), Peer) as server:
    root = Path(temp)
    # Route only these expected commands into the fixture. No real sudo is invoked.
    (root / "sudo").write_text("""#!/bin/bash
case "$*" in
  "systemctl status electrs --no-page") echo "$SERVICE" ;;
  "-u bitcoin /usr/local/bin/bitcoin-cli "*getblockchaininfo) echo "$CHAIN" ;;
  "-u bitcoin /usr/local/bin/bitcoin-cli "*"getblockheader "*" false") echo "$CORE_HEADER" ;;
  "-u electrs test -f /mnt/hdd/app-storage/electrs/initial-sync.verified") test -f "$FIXTURE/verified" ;;
  "-u electrs touch -- /mnt/hdd/app-storage/electrs/initial-sync.verified") touch "$FIXTURE/verified" ;;
  *) exit 93 ;;
esac
""")
    (root / "nc").write_text("""#!/bin/sh
[ "$*" = '-w 2 -q 1 127.0.0.1 50001' ] || exit 2
exec python3 -c 'import socket,os,sys
with socket.create_connection(("127.0.0.1",int(os.environ["PORT"])),2) as s:
 s.sendall(sys.stdin.buffer.readline())
 print(s.makefile().readline(),end="")'
""")
    for command in ("nc", "sudo"):
        (root / command).chmod(0o755)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        cases = [
            ("partial", 50, False, 100, HEADER, 50, False),
            ("core-ibd", 100, True, 100, HEADER, 99, False),
            ("more-headers", 100, False, 102, HEADER, 99, False),
            ("other-chain", 100, False, 100, "11" * 80, 99, False),
            ("invalid-height", "bad", False, 100, HEADER, 0, False),
            ("rpc-error", None, False, 100, HEADER, 0, False),
            ("ahead", 101, False, 100, HEADER, 99, False),
            ("tip", 100, False, 100, HEADER, 100, True),
            ("later-block", 99, False, 100, HEADER, 99, True),
        ]
        env = dict(os.environ, FIXTURE=temp, PORT=str(server.server_address[1]),
                   PATH=temp + ":" + os.environ["PATH"], SERVICE="active (running)")
        for name, height, ibd, headers, data, progress, complete in cases:
            server.reply = ({"id": 1, "error": {"code": -1}} if height is None else
                            {"id": 1, "result": {"height": height, "hex": data}})
            env.update(CHAIN=json.dumps(dict(blocks=100, headers=headers, bestblockhash=HASH,
                                             initialblockdownload=ibd)), CORE_HEADER=HEADER)
            run = subprocess.run(["bash", str(SCRIPT), "status-sync"], env=env,
                                 capture_output=True, text=True, timeout=12, check=True)
            assert f"blockheightPercent='{progress}'" in run.stdout, (name, run.stdout)
            assert f"initialSynced={int(complete)}" in run.stdout, (name, run.stdout)
            assert (root / "verified").exists() == complete, name
            print(name, "ok")
        env["SERVICE"] = "inactive"
        result = subprocess.check_output(["bash", str(SCRIPT), "status-sync"], env=env, text=True)
        assert "initialSynced=0" in result and "electrumResponding=0" in result
        print("stopped ok")
    finally:
        server.shutdown()
        thread.join()
