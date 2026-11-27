"""Run with python3 test/lnd-wallet-startup.py on a RaspiBlitz Python install."""
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

scripts = Path(__file__).resolve().parents[1] / "home.admin/config.scripts"
sys.path.insert(0, str(scripts))
spec = importlib.util.spec_from_file_location("wallet", scripts / "lnd.initwallet.py")
wallet = importlib.util.module_from_spec(spec)
with patch.object(sys, "argv", ["wallet", "new", "testnet", "test-only"]):
    spec.loader.exec_module(wallet)


class FirstStart(unittest.TestCase):
    def setUp(self):
        self.args = patch.object(sys, "argv", ["wallet", "new", "testnet", "test-only"])
        self.args.start()
        self.addCleanup(self.args.stop)

    def test_waits_before_creating_wallet_once(self):
        with patch.object(Path, "read_bytes", side_effect=[FileNotFoundError(), b"", b"cert"]), \
             patch.object(wallet.time, "sleep") as sleep, \
             patch.object(wallet.grpc, "ssl_channel_credentials") as credentials, \
             patch.object(wallet.grpc, "secure_channel") as channel, \
             patch.object(wallet.grpc, "channel_ready_future") as ready, \
             patch.object(wallet, "new") as create:
            wallet.main()
            self.assertEqual(sleep.call_count, 2)
            credentials.assert_called_once_with(b"cert")
            ready.assert_called_once_with(channel.return_value)
            ready.return_value.result.assert_called_once()
            create.assert_called_once()

    def test_timeout_before_generating_any_seed(self):
        for certificate, stage in [(None, "TLS certificate"), (b"cert", "wallet RPC")]:
            with self.subTest(stage=stage), \
                 patch.object(Path, "read_bytes", return_value=certificate), \
                 patch.object(wallet.time, "monotonic", side_effect=[0, 61]), \
                 patch.object(wallet.grpc, "secure_channel"), \
                 patch.object(wallet.grpc, "channel_ready_future") as ready, \
                 patch.object(wallet, "new") as create, \
                 contextlib.redirect_stdout(io.StringIO()) as stdout, \
                 contextlib.redirect_stderr(io.StringIO()), self.assertRaises(SystemExit) as failure:
                ready.return_value.result.side_effect = wallet.grpc.FutureTimeoutError()
                wallet.main()
            self.assertEqual(failure.exception.code, 1)
            self.assertIn(stage, stdout.getvalue())
            self.assertNotIn("seedwords", stdout.getvalue())
            create.assert_not_called()


if __name__ == "__main__":
    unittest.main()
