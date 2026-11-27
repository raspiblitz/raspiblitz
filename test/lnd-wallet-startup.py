"""Run with python3 test/lnd-wallet-startup.py on a RaspiBlitz Python install."""
import contextlib
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

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

    def test_reloads_certificate_when_it_changes_during_startup(self):
        first, second = Mock(), Mock()
        first.result.side_effect = wallet.grpc.FutureTimeoutError()
        with patch.object(Path, "read_bytes", side_effect=[b"incomplete", b"published"]), \
             patch.object(wallet.grpc, "ssl_channel_credentials") as credentials, \
             patch.object(wallet.grpc, "secure_channel") as channel, \
             patch.object(wallet.grpc, "channel_ready_future", side_effect=[first, second]), \
             patch.object(wallet, "new") as create:
            wallet.main()
            self.assertEqual([call.args[0] for call in credentials.call_args_list], [b"incomplete", b"published"])
            channel.return_value.close.assert_called_once()
            create.assert_called_once()

    def test_timeout_before_generating_any_seed(self):
        for certificate, stage in [(None, "TLS certificate"), (b"cert", "wallet RPC")]:
            with self.subTest(stage=stage), \
                 patch.object(Path, "read_bytes", return_value=certificate, side_effect=FileNotFoundError() if certificate is None else None), \
                 patch.object(wallet.time, "monotonic", side_effect=iter([0, 60, 60])), \
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

    def test_seed_is_durable_before_init_and_survives_uncertain_result(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory, "seedwords-testnet.pending")
            stub = Mock()
            stub.GenSeed.return_value.cipher_seed_mnemonic = ["test"] * 24
            def interrupt(_request):
                self.assertEqual(path.stat().st_mode & 0o777, 0o600)
                self.assertIn("24:test", path.read_text())
                raise ConnectionError()
            stub.InitWallet.side_effect = interrupt
            with self.assertRaises(SystemExit), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                wallet.new(stub, "test-only", recovery_path=path)
            self.assertTrue(path.is_file())
            before = path.read_bytes()
            with self.assertRaises(SystemExit), contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
                wallet.new(stub, "test-only", recovery_path=path)
            stub.InitWallet.assert_called_once()
            self.assertEqual(path.read_bytes(), before)


if __name__ == "__main__":
    unittest.main()
