#!/usr/bin/env python3
"""Integration tests for the TunnelSats hooks in home.admin/config.scripts/blitz.subscriptions.py.

Runs with the Python standard library only by stubbing RaspiBlitz runtime modules
(toml, dialog, blitzpy, config) in sys.modules while loading the real script via importlib.
"""

from contextlib import redirect_stdout
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest import mock


SCRIPT_PATH = (
    Path(__file__).resolve().parents[2]
    / "home.admin"
    / "config.scripts"
    / "blitz.subscriptions.py"
)


class _StubRaspiBlitzConfig:
    def __init__(self):
        self.reloaded = 0

    def reload(self):
        self.reloaded += 1


class _FakeDialog:
    OK = "ok"
    CANCEL = "cancel"
    EXTRA = "extra"

    menu_responses = []
    msgbox_responses = []
    menu_calls = []
    msgbox_calls = []
    background_titles = []

    def __init__(self, dialog="dialog", autowidgetsize=True):
        self.dialog = dialog
        self.autowidgetsize = autowidgetsize

    @classmethod
    def reset(cls, menu_responses=None, msgbox_responses=None):
        cls.menu_responses = list(menu_responses or [])
        cls.msgbox_responses = list(msgbox_responses or [])
        cls.menu_calls = []
        cls.msgbox_calls = []
        cls.background_titles = []

    def set_background_title(self, title):
        self.__class__.background_titles.append(title)

    def menu(self, text, choices=None, **kwargs):
        self.__class__.menu_calls.append({
            "text": text,
            "choices": list(choices or []),
            "kwargs": dict(kwargs),
        })
        if self.__class__.menu_responses:
            return self.__class__.menu_responses.pop(0)
        return (self.CANCEL, "")

    def msgbox(self, text, **kwargs):
        self.__class__.msgbox_calls.append({
            "text": text,
            "kwargs": dict(kwargs),
        })
        if self.__class__.msgbox_responses:
            return self.__class__.msgbox_responses.pop(0)
        return self.OK


def _load_subscriptions_module():
    toml_stub = types.ModuleType("toml")
    toml_stub.load = mock.MagicMock(side_effect=FileNotFoundError("subscriptions.toml"))

    dialog_stub = types.ModuleType("dialog")
    dialog_stub.Dialog = _FakeDialog

    blitzpy_stub = types.ModuleType("blitzpy")
    config_stub = types.ModuleType("config")
    config_stub.RaspiBlitzConfig = _StubRaspiBlitzConfig
    blitzpy_stub.config = config_stub

    saved_path = list(sys.path)
    stubs = {
        "toml": toml_stub,
        "dialog": dialog_stub,
        "blitzpy": blitzpy_stub,
        "config": config_stub,
    }
    try:
        with mock.patch.dict(sys.modules, stubs):
            spec = importlib.util.spec_from_file_location("blitz_subscriptions_under_test", SCRIPT_PATH)
            assert spec is not None and spec.loader is not None
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            return module
    finally:
        sys.path[:] = saved_path


class SubscriptionsIntegrationBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.mod = _load_subscriptions_module()

    def setUp(self):
        _FakeDialog.reset()
        self.mod.Dialog = _FakeDialog
        self.mod.toml.load = mock.MagicMock(side_effect=FileNotFoundError("subscriptions.toml"))
        self.tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmpdir.cleanup)

    def _write_conf(self, content):
        conf_path = Path(self.tmpdir.name) / "raspiblitz.conf"
        conf_path.write_text(content, encoding="utf-8")
        return str(conf_path)


class TestTunnelsatsList(SubscriptionsIntegrationBase):
    def test_filters_only_tunnelsats_v1_dicts(self):
        payload = {
            "subscriptions": [
                {"type": "tunnelsats-v1", "name": "de2.tunnelsats.com:24556", "active": True},
                {"type": "ip2tor-v1", "name": "other", "active": True},
                {"name": "missing-type"},
                "not-a-dict",
                42,
                None,
            ]
        }
        proc = subprocess.CompletedProcess(args=[], returncode=0, stdout=json.dumps(payload).encode("utf-8"))
        with mock.patch.object(self.mod.subprocess, "run", return_value=proc) as run_mock:
            result = self.mod.tunnelsats_list()

        self.assertEqual(
            result,
            [{"type": "tunnelsats-v1", "name": "de2.tunnelsats.com:24556", "active": True}],
        )
        run_mock.assert_called_once_with(
            ["sudo", self.mod.TUNNELSATS_MODULE, "subscriptions-list", "--json"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=20,
        )

    def test_empty_and_missing_subscriptions_key(self):
        for body in ({"subscriptions": []}, {}):
            proc = subprocess.CompletedProcess(args=[], returncode=0, stdout=json.dumps(body).encode("utf-8"))
            with mock.patch.object(self.mod.subprocess, "run", return_value=proc):
                self.assertEqual(self.mod.tunnelsats_list(), [])

    def test_returns_empty_list_on_subprocess_or_json_error(self):
        with mock.patch.object(self.mod.subprocess, "run", side_effect=OSError("no sudo")):
            self.assertEqual(self.mod.tunnelsats_list(), [])

        timeout_err = subprocess.TimeoutExpired(cmd=["sudo"], timeout=20)
        with mock.patch.object(self.mod.subprocess, "run", side_effect=timeout_err):
            self.assertEqual(self.mod.tunnelsats_list(), [])

        bad_json = subprocess.CompletedProcess(args=[], returncode=0, stdout=b"not json")
        with mock.patch.object(self.mod.subprocess, "run", return_value=bad_json):
            self.assertEqual(self.mod.tunnelsats_list(), [])

        wrong_shape = subprocess.CompletedProcess(args=[], returncode=0, stdout=b"[]")
        with mock.patch.object(self.mod.subprocess, "run", return_value=wrong_shape):
            self.assertEqual(self.mod.tunnelsats_list(), [])


class TestBlitzConfValue(SubscriptionsIntegrationBase):
    def test_parses_unquoted_single_and_double_quoted_values(self):
        conf = self._write_conf(
            "# raspiblitz.conf\n"
            "chain=main\n"
            "lightning='lnd'\n"
            'network="bitcoin"\n'
            "tunnelsats='off'\n"
            'tunnelsats="on"\n'
        )
        with mock.patch.object(self.mod, "BLITZ_CONF_FILE", conf):
            self.assertEqual(self.mod.blitz_conf_value("chain"), "main")
            self.assertEqual(self.mod.blitz_conf_value("lightning"), "lnd")
            self.assertEqual(self.mod.blitz_conf_value("network"), "bitcoin")
            self.assertEqual(self.mod.blitz_conf_value("tunnelsats"), "on")
            self.assertEqual(self.mod.blitz_conf_value("nonexistent"), "")

    def test_empty_file_and_missing_file(self):
        empty_conf = self._write_conf("")
        with mock.patch.object(self.mod, "BLITZ_CONF_FILE", empty_conf):
            self.assertEqual(self.mod.blitz_conf_value("chain"), "")

        missing_conf = str(Path(self.tmpdir.name) / "does-not-exist.conf")
        with mock.patch.object(self.mod, "BLITZ_CONF_FILE", missing_conf):
            self.assertEqual(self.mod.blitz_conf_value("chain"), "")


class TestTunnelsatsDetailText(SubscriptionsIntegrationBase):
    def test_formats_full_status_document(self):
        doc = {
            "server_domain": "de2.tunnelsats.com",
            "vpn_port": 24556,
            "expiry": "2026-12-01T00:00:00Z",
            "tunnelsats": "on",
            "guard": {"decision": "hybrid", "reason": "ok"},
            "last_check": {"verdict": "pass"},
        }
        proc = subprocess.CompletedProcess(args=[], returncode=0, stdout=json.dumps(doc).encode("utf-8"))
        with mock.patch.object(self.mod.subprocess, "run", return_value=proc) as run_mock:
            text = self.mod.tunnelsats_detail_text()

        run_mock.assert_called_once_with(
            ["sudo", self.mod.TUNNELSATS_MODULE, "status", "--cached", "--json"],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=20,
        )
        self.assertIn("Server:        de2.tunnelsats.com (VPN port 24556)", text)
        self.assertIn("Expires:       2026-12-01T00:00:00Z", text)
        self.assertIn("TunnelSats:    on", text)
        self.assertIn("Start guard:   hybrid (ok)", text)
        self.assertIn("Last check:    pass", text)
        self.assertIn("Use MANAGE for STATUS, CHECK, REPAIR, REMOVE and ABOUT.", text)

    def test_handles_missing_expiry_guard_and_last_check(self):
        doc = {
            "server_domain": "us1.tunnelsats.com",
            "vpn_port": 24557,
            "expiry": None,
            "tunnelsats": "off",
            "guard": None,
            "last_check": None,
        }
        proc = subprocess.CompletedProcess(args=[], returncode=0, stdout=json.dumps(doc).encode("utf-8"))
        with mock.patch.object(self.mod.subprocess, "run", return_value=proc):
            text = self.mod.tunnelsats_detail_text()

        self.assertIn("Expires:       unknown", text)
        self.assertIn("Start guard:   None (None)", text)
        self.assertIn("Last check:    none", text)

    def test_returns_fallback_text_on_subprocess_or_json_error(self):
        with mock.patch.object(self.mod.subprocess, "run", side_effect=OSError("exec failed")):
            self.assertEqual(
                self.mod.tunnelsats_detail_text(),
                "\nThe TunnelSats status could not be read.\n",
            )

        bad_json = subprocess.CompletedProcess(args=[], returncode=0, stdout=b"{bad")
        with mock.patch.object(self.mod.subprocess, "run", return_value=bad_json):
            self.assertEqual(
                self.mod.tunnelsats_detail_text(),
                "\nThe TunnelSats status could not be read.\n",
            )


class TestMySubscriptions(SubscriptionsIntegrationBase):
    def test_zero_subscriptions_shows_info_msgbox(self):
        buf = io.StringIO()
        with (
            mock.patch.object(self.mod.os, "system"),
            mock.patch.object(self.mod, "tunnelsats_list", return_value=[]),
            redirect_stdout(buf),
        ):
            self.mod.my_subscriptions()

        self.assertEqual(len(_FakeDialog.menu_calls), 0)
        self.assertEqual(len(_FakeDialog.msgbox_calls), 1)
        self.assertIn("You have no active or inactive subscriptions.", _FakeDialog.msgbox_calls[0]["text"])
        self.assertEqual(_FakeDialog.msgbox_calls[0]["kwargs"].get("title"), "Info")

    def test_tunnelsats_only_without_toml_lists_active_and_inactive_and_opens_manage(self):
        ts_items = [
            {"type": "tunnelsats-v1", "name": "de2.tunnelsats.com:24556", "active": True},
            {"type": "tunnelsats-v1", "name": "us1.tunnelsats.com:24557", "active": False},
        ]
        _FakeDialog.reset(
            menu_responses=[(_FakeDialog.OK, "1"), (_FakeDialog.CANCEL, "")],
            msgbox_responses=[_FakeDialog.EXTRA],
        )
        buf = io.StringIO()
        with (
            mock.patch.object(self.mod.os, "system") as os_system,
            mock.patch.object(self.mod, "tunnelsats_list", return_value=ts_items),
            mock.patch.object(self.mod, "tunnelsats_detail_text", return_value="DETAIL-TEXT") as detail_mock,
            mock.patch.object(self.mod.subprocess, "run") as run_mock,
            redirect_stdout(buf),
        ):
            self.mod.my_subscriptions()

        self.assertEqual(len(_FakeDialog.menu_calls), 2)
        choices = _FakeDialog.menu_calls[0]["choices"]
        self.assertEqual(len(choices), 2)
        self.assertIn("TUNNELSATS de2.tunnelsats.com:24556", choices[0][1])
        self.assertIn("(active)", choices[0][1])
        self.assertIn("TUNNELSATS us1.tunnelsats.com:24557", choices[1][1])
        self.assertIn("(in-active)", choices[1][1])

        detail_mock.assert_called_once_with()
        self.assertEqual(len(_FakeDialog.msgbox_calls), 1)
        self.assertEqual(_FakeDialog.msgbox_calls[0]["text"], "DETAIL-TEXT")
        self.assertEqual(_FakeDialog.msgbox_calls[0]["kwargs"].get("extra_label"), "MANAGE")
        run_mock.assert_called_once_with(["sudo", self.mod.TUNNELSATS_MODULE, "menu"])
        os_system.assert_any_call("clear")

    def test_tunnelsats_detail_back_does_not_launch_menu(self):
        ts_items = [{"type": "tunnelsats-v1", "name": "de2.tunnelsats.com:24556", "active": True}]
        _FakeDialog.reset(
            menu_responses=[(_FakeDialog.OK, "1"), (_FakeDialog.CANCEL, "")],
            msgbox_responses=[_FakeDialog.OK],
        )
        buf = io.StringIO()
        with (
            mock.patch.object(self.mod.os, "system"),
            mock.patch.object(self.mod, "tunnelsats_list", return_value=ts_items),
            mock.patch.object(self.mod, "tunnelsats_detail_text", return_value="DETAIL-TEXT"),
            mock.patch.object(self.mod.subprocess, "run") as run_mock,
            redirect_stdout(buf),
        ):
            self.mod.my_subscriptions()

        run_mock.assert_not_called()

    def test_non_tunnelsats_active_inactive_and_unknown_type_branches(self):
        subs_doc = {
            "subscriptions_letsencrypt": [
                {
                    "type": "letsencrypt-v1",
                    "id": "active.example.org",
                    "active": True,
                    "warning": "",
                    "dnsservice_type": "duckdns",
                    "ip": "1.2.3.4",
                    "description": "active cert",
                },
                {
                    "type": "letsencrypt-v1",
                    "id": "inactive.example.org",
                    "active": False,
                    "warning": "",
                    "dnsservice_type": "duckdns",
                    "ip": "1.2.3.4",
                    "description": "inactive cert",
                },
                {
                    "type": "unknown-v1",
                    "id": "mystery",
                    "active": False,
                },
            ]
        }
        self.mod.toml.load = mock.MagicMock(return_value=subs_doc)
        _FakeDialog.reset(
            menu_responses=[
                (_FakeDialog.OK, "1"),
                (_FakeDialog.OK, "2"),
                (_FakeDialog.OK, "3"),
                (_FakeDialog.CANCEL, ""),
            ],
            msgbox_responses=[_FakeDialog.OK, _FakeDialog.OK, _FakeDialog.EXTRA],
        )
        buf = io.StringIO()
        with (
            mock.patch.object(self.mod.os, "system"),
            mock.patch.object(self.mod.time, "sleep"),
            mock.patch.object(self.mod, "tunnelsats_list", return_value=[]),
            mock.patch.object(self.mod.subprocess, "run") as run_mock,
            redirect_stdout(buf),
        ):
            self.mod.my_subscriptions()

        self.assertEqual(len(_FakeDialog.msgbox_calls), 3)
        self.assertEqual(_FakeDialog.msgbox_calls[0]["kwargs"].get("extra_label"), "CANCEL SUBSCRIPTION")
        self.assertEqual(_FakeDialog.msgbox_calls[1]["kwargs"].get("extra_label"), "DELETE SUBSCRIPTION")
        self.assertEqual(_FakeDialog.msgbox_calls[2]["text"], "no text?! FIXME")
        self.assertEqual(_FakeDialog.msgbox_calls[2]["kwargs"].get("extra_label"), "DELETE SUBSCRIPTION")
        self.assertIn("# FAIL: unknown subscription type", buf.getvalue())
        run_mock.assert_not_called()


class TestMainMenu(SubscriptionsIntegrationBase):
    def test_mainnet_lnd_without_subscription_shows_plus_paid_label(self):
        conf = self._write_conf("chain=main\nlightning=lnd\n")
        _FakeDialog.reset(menu_responses=[(_FakeDialog.CANCEL, "")])
        with (
            mock.patch.object(self.mod, "BLITZ_CONF_FILE", conf),
            mock.patch.object(self.mod, "tunnelsats_list", return_value=[]),
            self.assertRaises(SystemExit) as ctx,
        ):
            self.mod.main()

        self.assertEqual(ctx.exception.code, 0)
        self.assertIn(("TUNNELSATS", "+ TunnelSats VPN (paid)"), _FakeDialog.menu_calls[0]["choices"])

    def test_mainnet_cl_with_subscription_shows_plain_label(self):
        conf = self._write_conf("chain='main'\nlightning=\"cl\"\n")
        ts_items = [{"type": "tunnelsats-v1", "name": "de2.tunnelsats.com:24556", "active": True}]
        _FakeDialog.reset(menu_responses=[(_FakeDialog.CANCEL, "")])
        with (
            mock.patch.object(self.mod, "BLITZ_CONF_FILE", conf),
            mock.patch.object(self.mod, "tunnelsats_list", return_value=ts_items),
            self.assertRaises(SystemExit) as ctx,
        ):
            self.mod.main()

        self.assertEqual(ctx.exception.code, 0)
        self.assertIn(("TUNNELSATS", "TunnelSats VPN"), _FakeDialog.menu_calls[0]["choices"])

    def test_omits_tunnelsats_when_chain_not_main_or_lightning_unsupported(self):
        for content in ("chain=test\nlightning=lnd\n", "chain=main\nlightning=none\n", ""):
            _FakeDialog.reset(menu_responses=[(_FakeDialog.CANCEL, "")])
            conf = self._write_conf(content)
            with (
                mock.patch.object(self.mod, "BLITZ_CONF_FILE", conf),
                mock.patch.object(self.mod, "tunnelsats_list") as ts_list,
                self.assertRaises(SystemExit) as ctx,
            ):
                self.mod.main()

            self.assertEqual(ctx.exception.code, 0)
            tags = [tag for tag, _ in _FakeDialog.menu_calls[0]["choices"]]
            self.assertNotIn("TUNNELSATS", tags)
            ts_list.assert_not_called()

    def test_selecting_tunnelsats_clears_runs_module_and_exits_zero(self):
        conf = self._write_conf("chain=main\nlightning=lnd\n")
        _FakeDialog.reset(menu_responses=[(_FakeDialog.OK, "TUNNELSATS")])
        with (
            mock.patch.object(self.mod, "BLITZ_CONF_FILE", conf),
            mock.patch.object(self.mod, "tunnelsats_list", return_value=[]),
            mock.patch.object(self.mod.os, "system") as os_system,
            mock.patch.object(self.mod.subprocess, "run") as run_mock,
            self.assertRaises(SystemExit) as ctx,
        ):
            self.mod.main()

        self.assertEqual(ctx.exception.code, 0)
        os_system.assert_called_once_with("clear")
        run_mock.assert_called_once_with(["sudo", self.mod.TUNNELSATS_MODULE, "menu"])

    def test_selecting_non_tunnelsats_tag_does_not_invoke_tunnelsats(self):
        conf = self._write_conf("chain=main\nlightning=lnd\n")
        _FakeDialog.reset(menu_responses=[(_FakeDialog.OK, "OTHER")])
        with (
            mock.patch.object(self.mod, "BLITZ_CONF_FILE", conf),
            mock.patch.object(self.mod, "tunnelsats_list", return_value=[]),
            mock.patch.object(self.mod.os, "system") as os_system,
            mock.patch.object(self.mod.subprocess, "run") as run_mock,
        ):
            self.mod.main()

        os_system.assert_not_called()
        run_mock.assert_not_called()


if __name__ == "__main__":
    unittest.main()
