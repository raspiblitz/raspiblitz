"""Regression tests for the local JoinMarket wallet migration."""

import importlib.util
import io
import os
import stat
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "home.admin/config.scripts/joinmarket.wallet.py"
spec = importlib.util.spec_from_file_location("joinmarket_wallet", SCRIPT)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class WalletMigrationTests(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.data = Path(directory.name)
        self.core = self.data / "bitcoin/bitcoin.conf"
        self.core.parent.mkdir()
        self.core.write_text("main.wallet=wallet.dat\n")
        self.legacy = self.data / "bitcoin/wallets/wallet.dat/wallet.dat"
        self.legacy.parent.mkdir(parents=True)
        self.legacy.write_bytes(b"old-core-wallet")
        self.config = self.data / ".joinmarket/joinmarket.cfg"
        self.config.parent.mkdir()
        self.config.write_text("[BLOCKCHAIN]\nrpc_host = localhost\nrpc_wallet_file = wallet.dat\n")
        self.wallets = self.config.parent / "wallets"
        self.wallets.mkdir()
        for name in ("first.jmdat", "second.jmdat"):
            (self.wallets / name).write_bytes(name.encode())
        patcher = patch.multiple(migration, DATA=self.data, CORE_CONF=self.core, JM_CONF=self.config)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.backups = self.data / "backup/joinmarket"

    def test_remote_and_pre_30_keep_legacy_selection(self):
        migration.backup("29.5")
        self.config.write_text("[BLOCKCHAIN]\nrpc_host = example.invalid\nrpc_wallet_file = wallet.dat\n")
        migration.backup("32.1")
        self.assertFalse(self.backups.exists())
        self.assertIn("rpc_wallet_file = wallet.dat", self.config.read_text())

    def test_core_daemon_version(self):
        with patch.object(migration.subprocess, "run") as version:
            version.return_value.stdout = "Bitcoin Core daemon version v32.1.0\n"
            self.assertTrue(migration.modern_core())
            version.return_value.stdout = "Bitcoin Core daemon version v29.2.0\n"
            self.assertFalse(migration.modern_core())

    def test_empty_rpc_port_and_cookie_follow_existing_settings(self):
        self.config.write_text(
            "[BLOCKCHAIN]\nrpc_host = localhost\nnetwork = signet\nrpc_port =\n"
            "rpc_cookie_file = /tmp/example-cookie\n"
        )
        with patch.object(migration.subprocess, "run") as command:
            cookie = type("Result", (), {"returncode": 0, "stdout": "__cookie__:fixture\n"})()
            status = type("Result", (), {"returncode": 0, "stdout": '{"version":320100}'})()
            command.side_effect = [cookie, status]
            self.assertEqual(migration.rpc("getnetworkinfo"), {"version": 320100})
        self.assertIn("-rpcport=38332", command.call_args.args[0])
        self.assertIn("-stdinrpcpass", command.call_args.args[0])
        self.assertIn("-conf=/dev/null", command.call_args.args[0])
        self.assertEqual(command.call_args.args[0][:3], ["runuser", "-u", "joinmarket"])
        self.assertNotIn("fixture", " ".join(command.call_args.args[0]))
        self.assertEqual(command.call_args.kwargs["input"], "fixture\n")

    def test_missing_joinmarket_credentials_do_not_fall_back_to_core_credentials(self):
        with patch.object(migration.subprocess, "run") as command:
            with self.assertRaisesRegex(ValueError, "Configure the JoinMarket RPC password"):
                migration.rpc("getnetworkinfo")
        command.assert_not_called()

    def test_legacy_wallet_on_another_loopback_instance_requires_its_own_backup(self):
        self.config.write_text("[BLOCKCHAIN]\nrpc_port = 18332\nrpc_wallet_file = wallet.dat\n")
        with self.assertRaisesRegex(ValueError, "on its own Core instance"):
            migration.backup("32.1")
        self.assertFalse(self.backups.exists())

    def test_missing_legacy_core_wallet_prevents_migration(self):
        self.legacy.unlink()
        with self.assertRaisesRegex(ValueError, "wallet.dat is missing"):
            migration.backup("32.1")
        self.assertFalse(self.backups.exists())

    def test_loaded_watch_only_descriptor_named_wallet_dat_stays_selected(self):
        old_config = self.config.read_bytes()
        with patch.object(migration, "modern_core", return_value=True), patch.object(
            migration, "rpc", side_effect=[
                {"version": 320100}, [migration.LEGACY_WALLET],
                {"descriptors": True, "private_keys_enabled": False},
            ],
        ) as rpc:
            migration.prepare()
        self.assertEqual(rpc.call_count, 3)
        self.assertFalse(self.backups.exists())
        self.assertEqual(self.config.read_bytes(), old_config)

    @unittest.skipUnless(os.geteuid() == 0, "requires the production admin-only backup permissions")
    def test_explicit_backup_preserves_the_newest_pre_upgrade_core_config(self):
        with redirect_stdout(io.StringIO()):
            migration.backup("32.1")
            self.core.write_text("main.wallet=wallet.dat\n# updated before next attempt\n")
            (self.wallets / "second.jmdat").unlink()
            migration.backup("32.1")
        copies = list(self.backups.iterdir())
        self.assertEqual(len(copies), 2)
        current, = [copy for copy in copies if (copy / "bitcoin/bitcoin.conf").read_bytes() == self.core.read_bytes()]
        self.assertFalse((current / ".joinmarket/wallets/second.jmdat").exists())

    @unittest.skipUnless(os.geteuid() == 0, "requires the production admin-only backup permissions")
    def test_backup_copies_all_wallets_and_reuses_the_pre_restart_snapshot(self):
        old_config = self.core.read_bytes()
        with redirect_stdout(io.StringIO()) as log:
            migration.backup("32.1")
            self.core.write_text("# Core no longer autoloads the old wallet\n")
            migration.backup_legacy_wallet(core_already_started=True)
        backup, = self.backups.iterdir()
        self.assertIn(str(backup), log.getvalue())
        for source in (*self.wallets.iterdir(), self.legacy, self.config):
            self.assertEqual((backup / source.relative_to(self.data)).read_bytes(), source.read_bytes())
        self.assertEqual((backup / self.core.relative_to(self.data)).read_bytes(), old_config)
        self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(self.backups.parent.stat().st_mode), 0o755)

    def test_incomplete_backup_prevents_migration(self):
        old_config = self.config.read_bytes()
        (self.wallets / ".first.jmdat.lock").write_text("123")
        with patch.object(migration, "modern_core", return_value=True), patch.object(
            migration, "rpc", side_effect=[{"version": 320100}, []]
        ) as rpc:
            with self.assertRaisesRegex(ValueError, "Close open JoinMarket wallets"):
                migration.prepare()
        self.assertEqual(rpc.call_count, 2)
        self.assertEqual(self.config.read_bytes(), old_config)
        self.assertFalse(self.backups.exists())

    def test_select_descriptor_only_updates_blockchain_section(self):
        self.config.write_text("[OTHER]\nrpc_wallet_file = custom\n\n[BLOCKCHAIN]\nrpc_host = localhost\n")
        migration.select_descriptor()
        self.assertIn("[OTHER]\nrpc_wallet_file = custom", self.config.read_text())
        self.assertEqual(migration.local_wallet(), migration.DESCRIPTOR_WALLET)

    @unittest.skipUnless(os.geteuid() == 0, "requires the production admin-only backup permissions")
    def test_rejected_wallet_does_not_change_the_configuration(self):
        old_config = self.config.read_bytes()
        with redirect_stdout(io.StringIO()), patch.object(migration, "modern_core", return_value=True), patch.object(
            migration, "rpc", side_effect=[
                {"version": 320100}, [migration.DESCRIPTOR_WALLET],
                {"descriptors": True, "private_keys_enabled": True},
            ],
        ):
            with self.assertRaisesRegex(ValueError, "watch-only descriptor wallet"):
                migration.prepare()
        self.assertEqual(self.config.read_bytes(), old_config)
        backup, = self.backups.iterdir()
        self.assertEqual((backup / self.config.relative_to(self.data)).read_bytes(), old_config)


if __name__ == "__main__":
    unittest.main()
