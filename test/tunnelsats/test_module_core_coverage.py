#!/usr/bin/python3
"""Comprehensive line and branch coverage tests for core regions (lines 1-1659 and 3191-5161)
of blitz.subscriptions.tunnelsats.py.
"""

import argparse
import base64
import http.client
import io
import json
import os
import signal
import ssl
import subprocess
import sys
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
if HERE not in sys.path:
    sys.path.insert(0, HERE)

from test_module import (  # noqa: E402
    ALICE_PRIV,
    ALICE_PUB,
    BOB_PUB,
    NOW,
    ModuleTestCase,
    fixture,
    fixture_json,
    mod,
)


def _make_custom_bolt11(hrp, tagged_words, timestamp=None):
    """Builds a valid-checksum BOLT11 string with caller-supplied tagged words."""
    ts = int(NOW.timestamp()) if timestamp is None else int(timestamp)
    data = [(ts >> (5 * (6 - i))) & 31 for i in range(7)]
    data += list(tagged_words)
    data += [(i * 7 + 3) & 31 for i in range(104)]
    values = mod._bech32_hrp_expand(hrp.lower()) + data + [0, 0, 0, 0, 0, 0]
    polymod = mod._bech32_polymod(values) ^ 1
    checksum = [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]
    return hrp + "1" + "".join(mod._BECH32_CHARSET[d] for d in data + checksum)


def _payment_hash_tag(hex64):
    h_int = int(hex64, 16) << 4
    p_words = [(h_int >> (5 * (51 - i))) & 31 for i in range(52)]
    return [1, (52 >> 5) & 31, 52 & 31] + p_words


def _cln_unit_text(valid=True):
    lines = [
        "[Unit]",
        "Description=Core Lightning",
        "[Service]",
        "Environment=TUNNELSATS_CLN_ARGS=",
        "EnvironmentFile=-/run/tunnelsats/hybrid-lightningd.env",
        mod.guard_line("cl"),
        "ExecStart=/bin/sh -c '/usr/local/bin/lightningd --conf=/home/bitcoin/.lightning/config $$TUNNELSATS_CLN_ARGS'"
        if valid else "ExecStart=/usr/local/bin/lightningd",
    ]
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------------------------------------
# Region 1 (lines 1-1659): effects, helpers, BOLT11, WG parser, pending, detect, servers,
# activation, import, export
# ------------------------------------------------------------------------------------------

class TestEffectsAndHelpersCoverage(ModuleTestCase):
    def test_stop_group_process_lookup_error(self):
        proc = mock.MagicMock()
        proc.pid = 99999
        proc.communicate.return_value = (b"", b"")
        with mock.patch.object(mod.os, "killpg", side_effect=ProcessLookupError):
            mod.stop_group(proc, grace=1)
        proc.communicate.assert_called_once_with(timeout=1)
        proc.kill.assert_not_called()

    def test_stop_group_timeouts_fall_back_to_kill(self):
        proc = mock.MagicMock()
        proc.pid = 99998
        proc.communicate.side_effect = [
            subprocess.TimeoutExpired(["x"], 1),
            subprocess.TimeoutExpired(["x"], 5),
            (b"", b""),
        ]
        with mock.patch.object(mod.os, "killpg") as killpg:
            mod.stop_group(proc, grace=1)
        self.assertEqual(
            [mock.call(99998, signal.SIGTERM), mock.call(99998, signal.SIGKILL)],
            killpg.call_args_list,
        )
        proc.kill.assert_called_once_with()
        self.assertEqual(3, proc.communicate.call_count)

    def test_run_command_interactive(self):
        with mock.patch.object(mod.subprocess, "run", return_value=mock.Mock(returncode=7)) as srun:
            rc, out, err = mod.run_command(["echo", "hi"], timeout=12, interactive=True)
        self.assertEqual((7, "", ""), (rc, out, err))
        srun.assert_called_once_with(["echo", "hi"], timeout=12, check=False)

    def test_run_command_base_exception_stops_group_and_reraises(self):
        fake_proc = mock.MagicMock()
        fake_proc.communicate.side_effect = KeyboardInterrupt("ctrl-c")
        with mock.patch.object(mod.subprocess, "Popen", return_value=fake_proc), \
             mock.patch.object(mod, "stop_group") as sg:
            with self.assertRaises(KeyboardInterrupt):
                mod.run_command(["sleep", "5"], timeout=5)
        sg.assert_called_once_with(fake_proc)

    def test_http_post_json_get_post_and_errors(self):
        def make_conn(status=200, headers=None, body=b'{"ok":true}'):
            conn = mock.MagicMock()
            conn.sock = mock.MagicMock()
            resp = mock.MagicMock()
            resp.status = status
            resp.read.return_value = body
            resp.getheaders.return_value = headers or [("Content-Type", "application/json")]
            conn.getresponse.return_value = resp
            return conn

        # GET (payload=None)
        conn_get = make_conn(200, [("X-Test", "1")], b"[]")
        with mock.patch.object(mod.http.client, "HTTPSConnection", return_value=conn_get) as hcls, \
             mock.patch.object(mod.ssl, "create_default_context", return_value="CTX"):
            st, hdrs, raw = mod.http_post_json("https://tunnelsats.com/api/public/v1/servers", None)
        self.assertEqual((200, {"x-test": "1"}, b"[]"), (st, hdrs, raw))
        hcls.assert_called_once_with("tunnelsats.com", 443, timeout=mod.API_CONNECT_TIMEOUT, context="CTX")
        conn_get.sock.settimeout.assert_called_once_with(mod.API_READ_TIMEOUT)
        req_headers = conn_get.request.call_args[1]["headers"]
        self.assertNotIn("Content-Type", req_headers)
        conn_get.close.assert_called_once()

        # POST (payload dict)
        conn_post = make_conn(201, [("Retry-After", "5")], b'{"ok":true}')
        with mock.patch.object(mod.http.client, "HTTPSConnection", return_value=conn_post), \
             mock.patch.object(mod.ssl, "create_default_context", return_value="CTX"):
            st, hdrs, raw = mod.http_post_json("https://tunnelsats.com:8443/api/public/v1/subscription/status", {"k": "v"})
        self.assertEqual(201, st)
        self.assertEqual({"retry-after": "5"}, hdrs)
        self.assertEqual("application/json", conn_post.request.call_args[1]["headers"]["Content-Type"])
        conn_post.close.assert_called_once()

        # HTTPException -> OSError
        conn_err = make_conn()
        conn_err.connect.side_effect = http.client.HTTPException("bad http")
        with mock.patch.object(mod.http.client, "HTTPSConnection", return_value=conn_err), \
             mock.patch.object(mod.ssl, "create_default_context", return_value="CTX"):
            with self.assertRaises(OSError):
                mod.http_post_json("https://tunnelsats.com/api/public/v1/servers", None)
        conn_err.close.assert_called_once()

        # SSLError -> OSError
        conn_ssl = make_conn()
        conn_ssl.connect.side_effect = ssl.SSLError("cert failed")
        with mock.patch.object(mod.http.client, "HTTPSConnection", return_value=conn_ssl), \
             mock.patch.object(mod.ssl, "create_default_context", return_value="CTX"):
            with self.assertRaises(OSError):
                mod.http_post_json("https://tunnelsats.com/api/public/v1/servers", None)
        conn_ssl.close.assert_called_once()

    def test_parse_iso_nanoseconds_and_invalid_calendar_date(self):
        dt = mod.parse_iso("2026-10-14T12:00:00.123456789Z")
        self.assertIsNotNone(dt)
        self.assertEqual(123456, dt.microsecond)
        # Matches ISO_RE but Feb 30 fails datetime.fromisoformat
        self.assertIsNone(mod.parse_iso("2026-02-30T12:00:00Z"))

    def test_read_rb_conf_missing_comments_and_quotes(self):
        os.unlink(self.path(mod.RB_CONF))
        self.assertEqual({}, mod.read_rb_conf(self.deps))

        self.write(
            "mnt/hdd/app-data/raspiblitz.conf",
            "# comment line\n\nlightning='lnd'\nnodeName=\"my node\"\nemptyVal=\nplain=on trailing\n",
        )
        conf = mod.read_rb_conf(self.deps)
        self.assertEqual("lnd", conf["lightning"])
        self.assertEqual("my node", conf["nodeName"])
        self.assertEqual("", conf["emptyVal"])
        self.assertEqual("on", conf["plain"])

    def test_write_private_edge_cases(self):
        target = self.path("mnt/hdd/app-data/test-priv.bin")

        # FileExistsError once, then succeeds
        real_open = os.open
        attempts = {"n": 0}

        def flaky_open(path, flags, mode=0o777):
            if os.path.basename(path).startswith(".test-priv.bin.") and attempts["n"] == 0:
                attempts["n"] += 1
                raise FileExistsError("collision")
            return real_open(path, flags, mode)

        with mock.patch.object(mod.os, "open", side_effect=flaky_open):
            mod.write_private(target, b"hello")
        self.assertEqual(b"hello", self.read_bytes("mnt/hdd/app-data/test-priv.bin"))

        # Exhaust all 20 FileExistsError retries
        with mock.patch.object(mod.os, "open", side_effect=FileExistsError("always")):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.write_private(target, b"hello")
        self.assertEqual("E_WRITE_FAILED", ctx.exception.code)

        # os.replace raises OSError -> temp file unlinked cleanly
        with mock.patch.object(mod.os, "replace", side_effect=OSError("disk full")):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.write_private(target, b"hello2")
        self.assertEqual("E_WRITE_FAILED", ctx.exception.code)

        # os.replace raises OSError AND os.unlink raises OSError
        with mock.patch.object(mod.os, "replace", side_effect=OSError("disk full")), \
             mock.patch.object(mod.os, "unlink", side_effect=OSError("unlink failed")):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.write_private(target, b"hello3")
        self.assertEqual("E_WRITE_FAILED", ctx.exception.code)

        # Read-back mismatch raises E_WRITE_FAILED
        real_builtin_open = open

        def wrong_readback(path, mode="r", *a, **kw):
            if path == target and mode == "rb":
                return io.BytesIO(b"corrupted")
            return real_builtin_open(path, mode, *a, **kw)

        with mock.patch("builtins.open", side_effect=wrong_readback):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.write_private(target, b"expected")
        self.assertEqual("E_WRITE_FAILED", ctx.exception.code)
        self.assertIn("did not read back", ctx.exception.message)

    def test_public_key_of_invalid_length(self):
        short_b64 = base64.b64encode(b"too-short").decode()
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.public_key_of(short_b64)
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

    def test_bolt11_amount_decode_and_verify_edge_cases(self):
        # Non-string input to bolt11_amount_sats
        self.assertIsNone(mod.bolt11_amount_sats(12345))

        # decode_bolt11: non-string, empty, > 4000 chars
        for bad in (None, "", "   ", "lnbc1" + "q" * 4005):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.decode_bolt11(bad)
            self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)

        # Data section shorter than 117 chars but passes BOLT11_AMOUNT_RE
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.decode_bolt11("lnbc2500u1qqqqqqqqqq")
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        self.assertIn("too short", ctx.exception.message)

        # Invalid Bech32 character ('b' is not in Bech32 charset, though in [0-9a-z])
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.decode_bolt11("lnbc2500u1" + "b" * 120)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        self.assertIn("invalid Bech32", ctx.exception.message)

        # Truncated tagged field (valid checksum, data_len exceeds remaining tagged words)
        trunc_inv = _make_custom_bolt11("lnbc2500u", [13, 1, 0, 0, 0])  # tag 13, len=32, only 2 words follow
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.decode_bolt11(trunc_inv)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        self.assertIn("truncated", ctx.exception.message)

        # Unknown tag (tag 13 description) AND expiry tag with value 0 (keeps default TTL)
        ph = "c" * 64
        tagged = [13, 0, 2, 1, 2] + [6, 0, 1, 0] + _payment_hash_tag(ph)
        inv = _make_custom_bolt11("lnbc2500u", tagged)
        dec = mod.decode_bolt11(inv)
        self.assertEqual(ph, dec["payment_hash"])
        self.assertEqual(mod.INVOICE_DEFAULT_TTL_SECONDS, dec["expiry_seconds"])

        # verify_bolt11_invoice: invalid expected_payment_hash and invalid expected_sats
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.verify_bolt11_invoice(inv, "not-a-hex64")
        self.assertEqual("E_API_INVALID", ctx.exception.code)

        for bad_sats in (True, 0, -5, "250000"):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.verify_bolt11_invoice(inv, ph, expected_sats=bad_sats)
            self.assertEqual("E_API_INVALID", ctx.exception.code)


class TestWgConfigAndPendingCoverage(ModuleTestCase):
    def _base_conf(self):
        return fixture("import", "website.conf")

    def test_parse_wg_config_and_render_edge_cases(self):
        base = self._base_conf()

        # Duplicate port comment
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(("# Port Forwarding: 24556\n" + base).encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # Duplicate Valid Until comment
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(("# Valid Until: 2026-12-01T00:00:00Z\n" + base).encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # Invalid Valid Until -> warning and dropped
        bad_valid = "\n".join(
            "# Valid Until: not-a-date" if line.startswith("# Valid Until:") else line
            for line in base.splitlines()
        ) + "\n"
        cfg = mod.parse_wg_config(bad_valid.encode())
        self.assertIsNone(cfg["valid_until"])
        self.assertTrue(any("Valid Until" in w for w in cfg["warnings"]))

        # Duplicate myPubKey comment
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(("# myPubKey: %s\n" % ALICE_PUB + base).encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # Inline # comment on key=value line + valid MTU + render_wg_config with MTU
        with_mtu = base.replace("Address = 10.9.0.42/32", "Address = 10.9.0.42/32 # inline comment\nMTU = 1420")
        cfg_mtu = mod.parse_wg_config(with_mtu.encode())
        self.assertEqual(1420, cfg_mtu["mtu"])
        rendered = mod.render_wg_config(cfg_mtu)
        self.assertIn(b"MTU = 1420\n", rendered)

        # Invalid MTU
        bad_mtu = base.replace("Address = 10.9.0.42/32", "Address = 10.9.0.42/32\nMTU = 1200")
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(bad_mtu.encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # Missing [Peer] section
        no_peer = base.split("[Peer]")[0]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(no_peer.encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # Invalid Address entry
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(base.replace("10.9.0.42/32", "not-an-ip").encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # Invalid Peer PublicKey
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(base.replace(BOB_PUB, "badkey").encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # Invalid PresharedKey
        bad_psk = base.replace("[Peer]\n", "[Peer]\nPresharedKey = invalid!\n")
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(bad_psk.encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # Endpoint missing :port
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(base.replace("de2.tunnelsats.com:51820", "de2.tunnelsats.com").encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # Endpoint port out of range
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(base.replace("de2.tunnelsats.com:51820", "de2.tunnelsats.com:70000").encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # Invalid AllowedIPs entry
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(base.replace("0.0.0.0/0, ::/0", "not-a-network").encode())
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

    def test_pending_load_prune_redact_and_tick_timer_needed(self):
        # Wrong schema in pending.json
        self.write("mnt/hdd/app-data/tunnelsats/pending.json", json.dumps({"schema": "wrong/1"}))
        self.assertEqual(mod.empty_pending(), mod.load_pending(self.deps))

        # Valid schema with non-list retained_orders and recovered_configs
        self.write(
            "mnt/hdd/app-data/tunnelsats/pending.json",
            json.dumps({
                "schema": "raspiblitz.tunnelsats.pending/1",
                "order": None,
                "retained_orders": "bad",
                "recovered_configs": None,
            }),
        )
        loaded = mod.load_pending(self.deps)
        self.assertEqual([], loaded["retained_orders"])
        self.assertEqual([], loaded["recovered_configs"])

        # _item_protected_from_prune on non-dict
        self.assertFalse(mod._item_protected_from_prune("not-a-dict"))

        # prune_pending with non-dict item, unpaid item without private_key, pruned retained item,
        # and > MAX_RETAINED_ORDERS both with and without private_key
        past = "2026-10-13T00:00:00Z"
        future = "2026-10-20T00:00:00Z"
        doc = mod.empty_pending()
        doc["order"] = "not-a-dict"
        doc["renewal"] = {"state": "awaiting_payment", "invoice_expires_at": past, "retained_until": past}
        doc["retained_orders"] = [
            {"id": "expired-one", "state": "expired_unpaid", "retained_until": past},
            {"id": "keep-protected", "state": "paid", "retained_until": future},
        ] + [
            {"id": "u%d" % i, "state": "awaiting_payment", "retained_until": future, "private_key": ALICE_PRIV}
            for i in range(6)
        ]
        mod.save_pending(self.deps, doc)
        pruned = mod.prune_pending(self.deps, now=NOW)
        self.assertIsNone(pruned["order"])
        self.assertIsNone(pruned["renewal"])
        self.assertEqual(mod.MAX_RETAINED_ORDERS, len(pruned["retained_orders"]))
        self.assertEqual("keep-protected", pruned["retained_orders"][0]["id"])

        # Over MAX_RETAINED_ORDERS when dropped items have NO private_key, plus non-dict items
        doc2 = mod.empty_pending()
        doc2["order"] = "not-a-dict"
        doc2["retained_orders"] = ["bad-entry"] + [
            {"id": "nk%d" % i, "state": "awaiting_payment", "retained_until": future}
            for i in range(mod.MAX_RETAINED_ORDERS + 2)
        ]
        pruned2 = mod.prune_pending(self.deps, doc=doc2, now=NOW, persist=False)
        self.assertIsNone(pruned2["order"])
        self.assertEqual(mod.MAX_RETAINED_ORDERS, len(pruned2["retained_orders"]))

        # redact_pending_item without private_key key
        self.assertEqual({"id": "x"}, mod.redact_pending_item({"id": "x", "invoice": "lnbc1..."}))

        # tick_timer_needed when tunnelsats=off and state=None
        self.assertTrue(mod.tick_timer_needed(self.deps))  # retained_orders present
        mod.save_pending(self.deps, mod.empty_pending())
        self.assertFalse(mod.tick_timer_needed(self.deps))

    def test_lock_waits_and_retries_before_acquiring(self):
        real_flock = mod.fcntl.flock
        calls = {"n": 0}

        def flaky_flock(fd, op):
            if (op & mod.fcntl.LOCK_EX) and calls["n"] == 0:
                calls["n"] += 1
                raise BlockingIOError("busy")
            return real_flock(fd, op)

        with mock.patch.object(mod.fcntl, "flock", side_effect=flaky_flock), \
             mock.patch.object(mod.time, "sleep") as sleep_mock:
            with mod.Lock(self.deps, wait=5):
                pass
        sleep_mock.assert_called_once_with(0.5)


class TestSystemDetectServersActivationCoverage(ModuleTestCase):
    def test_blitz_conf_set_failure_and_unit_props_edge_cases(self):
        orig_run = self.fake.run

        def fail_conf(argv, timeout=60, interactive=False):
            if argv[0] == mod.BLITZ_CONF:
                return 1, "", "write failed"
            if argv[0] == "systemctl" and argv[1] == "show":
                if argv[-1] == "bad.service":
                    return 1, "", "err"
                return 0, "ExtraKey=ignored\nActiveState=active\n", ""
            return orig_run(argv, timeout=timeout, interactive=interactive)

        self.deps.run = fail_conf
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.blitz_conf_set(self.deps, "tunnelsats", "on")
        self.assertEqual("E_CONF_WRITE", ctx.exception.code)

        self.assertEqual({"ActiveState": ""}, mod.unit_props(self.deps, "bad.service", "ActiveState"))
        self.assertEqual({"ActiveState": "active"}, mod.unit_props(self.deps, "lnd.service", "ActiveState"))

    def test_select_impl_all_branches(self):
        self.assertEqual(("cl", None), mod.select_impl({"cl": "on"}, requested="cl"))
        self.assertEqual((None, "cl_not_active"), mod.select_impl({}, requested="cl"))
        self.assertEqual(("cl", None), mod.select_impl({"cl": "on"}))
        self.assertEqual((None, "no_lightning"), mod.select_impl({}))

    def test_result_error_without_exit_code_and_emit_plain_text(self):
        res = mod.Result("status")
        res.error("E_NOTE", "usage", "just a note")
        self.assertEqual(mod.EXIT_OK, res.exit_code)
        buf = io.StringIO()
        mod.emit(res, as_json=False, out=buf)
        text = buf.getvalue()
        self.assertIn("command: \"status\"\n", text)
        self.assertNotIn("contract:", text)
        self.assertNotIn("module_version:", text)

    def test_detect_ineligibility_branches(self):
        # No lightning, testnet, tool detect fails
        self.write("mnt/hdd/app-data/raspiblitz.conf", "chain=testnet\nrunBehindTor=on\n")
        self.fake.its["detect"] = (1, "")
        found = mod.detect(self.deps)
        self.assertIn("no_lightning", found["reasons"])
        self.assertIn("chain_not_main", found["reasons"])
        self.assertIn("tool_detect_failed", found["reasons"])

        # LND active, audit returns None, capabilities missing systemd/cgroup_v2, unknown install kind
        self.write("mnt/hdd/app-data/raspiblitz.conf", "lightning=lnd\nlnd=on\nchain=main\nrunBehindTor=on\n")
        self.fake.its["audit lnd"] = (1, "not-json")
        tool_doc = fixture_json("tool", "detect_none.json")
        tool_doc["capabilities"]["systemd"]["status"] = "absent"
        tool_doc["capabilities"]["cgroup_v2"]["status"] = "not_mounted"
        tool_doc["install"]["kind"] = "mystery_kind"
        self.fake.its["detect"] = (0, tool_doc)
        found2 = mod.detect(self.deps)
        self.assertIn("config_check_failed", found2["reasons"])
        self.assertIn("systemd_missing", found2["reasons"])
        self.assertIn("cgroup_v2_missing", found2["reasons"])
        self.assertIn("unknown_install", found2["reasons"])

        # Audit returns unrepairable
        self.fake.its["audit lnd"] = (1, {"status": "unrepairable", "reason": "syntax", "eligible": True, "keys": []})
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_none.json"))
        found3 = mod.detect(self.deps)
        self.assertIn("config_unrepairable:syntax", found3["reasons"])

    def test_servers_validation_cache_and_write_error(self):
        self.assertIsNone(mod._validate_server_items([]))
        self.assertIsNone(mod._validate_server_items("not-a-list"))
        self.assertIsNone(mod._validate_server_items(["not-a-dict"]))
        self.assertIsNone(mod._validate_servers_payload(b""))
        self.assertIsNone(mod._validate_servers_payload(b"x" * (mod.API_MAX_BYTES + 1)))
        self.assertIsNone(mod._validate_servers_payload(b"{broken json"))

        # Cache file holds a JSON list instead of dict
        self.write("run/tunnelsats-rb/servers-cache.json", "[]")
        self.assertEqual((None, None), mod._load_servers_cache(self.deps))

        # fetch_servers succeeds even if cache write_private raises ModuleError
        self.fake.http_responses = [(200, {}, fixture("api", "servers.json", mode="rb"))]
        with mock.patch.object(mod, "write_private", side_effect=mod.ModuleError("E_WRITE_FAILED", "operational", "ro", 1)):
            servers, stale, offline = mod.fetch_servers(self.deps)
        self.assertTrue(len(servers) > 0)
        self.assertFalse(stale)
        self.assertFalse(offline)

    def test_unit_template_ok_and_regenerate_unit(self):
        # NeedDaemonReload != "no"
        self.fake.units["lnd.service"]["NeedDaemonReload"] = "yes"
        self.assertFalse(mod.unit_template_ok(self.deps, "lnd"))
        self.fake.units["lnd.service"]["NeedDaemonReload"] = "no"

        # Missing unit file -> OSError -> False
        os.unlink(self.path("etc/systemd/system/lnd.service"))
        self.assertFalse(mod.unit_template_ok(self.deps, "lnd"))

        # Missing EnvironmentFile line
        self.write("etc/systemd/system/lnd.service", "[Service]\nEnvironment=TUNNELSATS_LND_ARGS=\nExecStart=/usr/local/bin/lnd $TUNNELSATS_LND_ARGS\n")
        self.assertFalse(mod.unit_template_ok(self.deps, "lnd"))

        # Has Environment + EnvironmentFile but missing guard_line
        self.write(
            "etc/systemd/system/lnd.service",
            "[Service]\nEnvironment=TUNNELSATS_LND_ARGS=\nEnvironmentFile=-/run/tunnelsats/hybrid-lnd.env\nExecStart=/usr/local/bin/lnd $TUNNELSATS_LND_ARGS\n",
        )
        self.assertFalse(mod.unit_template_ok(self.deps, "lnd"))

        # CLN unit valid and invalid + regenerate_unit("cl")
        self.write("etc/systemd/system/lightningd.service", _cln_unit_text(valid=True))
        self.assertTrue(mod.unit_template_ok(self.deps, "cl"))
        mod.regenerate_unit(self.deps, "cl")

        self.write("etc/systemd/system/lightningd.service", _cln_unit_text(valid=False))
        self.assertFalse(mod.unit_template_ok(self.deps, "cl"))
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.regenerate_unit(self.deps, "cl")
        self.assertEqual("E_UNIT_TEMPLATE", ctx.exception.code)

    def test_activate_error_and_adopt_paths_and_wait_for_handshake(self):
        # fetch fails
        self.fake.its["fetch"] = (1, {"errors": [{"code": "E_HASH_MISMATCH"}]})
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.activate(self.deps, "lnd", mod.Result("import"))
        self.assertEqual("E_HASH_MISMATCH", ctx.exception.code)

        # block-insert --check fails
        self.fake.its["fetch"] = (0, {"ok": True})
        self.fake.its["block-insert --check"] = (1, {"errors": [{"code": "E_BLOCK_SYNTAX"}]})
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.activate(self.deps, "lnd", mod.Result("import"))
        self.assertEqual("E_BLOCK_SYNTAX", ctx.exception.code)

        # adopt with legacy fields + unit_template_ok False -> regenerates unit;
        # Case A: ln_was_active True -> restarts unit
        self.fake.its["block-insert --check"] = (0, {"state": "absent"})
        self.write("etc/systemd/system/lnd.service", "[Service]\nExecStart=/usr/local/bin/lnd\n")
        adopt_doc = dict(
            fixture_json("tool", "install_ok.json"),
            adopted=True,
            legacy_kind="legacy_v3_post_204",
            ln_restarted=False,
            ln_was_active=True,
        )
        self.fake.its["adopt"] = (0, adopt_doc)
        res = mod.Result("adopt")
        mod.activate(self.deps, "lnd", res, tool_verb="adopt")
        self.assertEqual("legacy_v3_post_204", res.fields["activation"]["legacy_kind"])
        self.assertTrue(res.fields["activation"]["unit_regenerated"])
        self.assertTrue(res.fields["activation"]["ln_restarted"])
        self.assertTrue(self.fake.calls_of("systemctl", "restart", "lnd.service"))

        # Case B: adopt with unit_template_ok False AND ln_restarted=False, ln_was_active=False -> no restart
        self.fake.calls.clear()
        self.write("etc/systemd/system/lnd.service", "[Service]\nExecStart=/usr/local/bin/lnd\n")
        adopt_doc2 = dict(
            fixture_json("tool", "install_ok.json"),
            adopted=True,
            ln_restarted=False,
            ln_was_active=False,
        )
        self.fake.its["adopt"] = (0, adopt_doc2)
        res2 = mod.Result("adopt")
        mod.activate(self.deps, "lnd", res2, tool_verb="adopt")
        self.assertTrue(res2.fields["activation"]["unit_regenerated"])
        self.assertFalse(self.fake.calls_of("systemctl", "restart", "lnd.service"))

        # wait_for_handshake timeout path (sleeps, retries, returns False)
        self.fake.its["verify --no-probe"] = (5, fixture_json("verify", "activating_no_handshake.json"))
        self.fake.sleeps.clear()
        self.assertFalse(mod.wait_for_handshake(self.deps, seconds=5, step=5))
        self.assertEqual([5], self.fake.sleeps)

    def test_with_start_wait_confirm_with_api_import_and_export(self):
        # with_start_wait downgrades protected -> degraded
        checked = {"verdict": "protected", "checks": [], "reasons": []}
        wait = {"unit": "lnd.service", "state": "activating", "waited_s": 90, "outcome": "timeout"}
        out = mod.with_start_wait(checked, wait)
        self.assertEqual("degraded", out["verdict"])
        self.assertIn("ln_start", out["reasons"])

        # confirm_with_api: migration and invalid outcomes
        cfg = mod.parse_wg_config(fixture("import", "website.conf", mode="rb"))
        self.fake.http_responses = [(403, {}, fixture("api", "error_migration.json", mode="rb"))]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.confirm_with_api(self.deps, cfg, False, mod.Result("import"))
        self.assertEqual("E_MIGRATION_REQUIRED", ctx.exception.code)

        self.fake.http_responses = [(200, {}, b'{"bad":true}')]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.confirm_with_api(self.deps, cfg, False, mod.Result("import"))
        self.assertEqual("E_API_INVALID", ctx.exception.code)

        # read_import_file: file larger than MAX_CONFIG_BYTES
        big = self.write("big.conf", "A" * (mod.MAX_CONFIG_BYTES + 10))
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.read_import_file(big)
        self.assertEqual("E_CONFIG_INVALID", ctx.exception.code)

        # cmd_import when adopted_legacy with same pubkey -> E_UPGRADE_UNAVAILABLE
        self.store(mode="adopted_legacy")
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual("E_UPGRADE_UNAVAILABLE", doc["errors"][0]["code"])

        # cmd_import re-importing same pubkey in managed mode -> delegates to cmd_repair
        self.store(mode="managed")
        self.activate_conf()
        self.record()
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))
        self.fake.http_responses = [(200, {}, fixture("api", "status_enabled.json", mode="rb"))]
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertTrue(doc["ok"])
        self.assertIn("actions", doc)

        # cmd_export: empty/NUL path -> E_USAGE
        res = mod.Result("export")
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.cmd_export(self.deps, argparse.Namespace(out=""), res)
        self.assertEqual("E_USAGE", ctx.exception.code)
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.cmd_export(self.deps, argparse.Namespace(out="/tmp/a\x00b"), res)
        self.assertEqual("E_USAGE", ctx.exception.code)

        # cmd_export: absolute path not prefixed with deps.root -> uses deps.path()
        os.makedirs(self.path("home/admin"), exist_ok=True)
        doc = self.run_verb("export", "--out", "/home/admin/exported.conf")
        self.assertTrue(doc["ok"])
        self.assertTrue(os.path.isfile(self.path("home/admin/exported.conf")))

        # cmd_export: relative path -> os.path.abspath()
        old_cwd = os.getcwd()
        try:
            os.chdir(self.root)
            doc = self.run_verb("export", "--out", "rel-exported.conf")
            self.assertTrue(doc["ok"])
            self.assertTrue(os.path.isfile(os.path.join(self.root, "rel-exported.conf")))
        finally:
            os.chdir(old_cwd)

        # cmd_export when deps.root == "/" -> calls pwd.getpwnam("admin") and os.chown (success + error)
        root_out = os.path.join(self.root, "root-export.conf")
        fake_root_deps = mod.Deps(root="/", http=self.fake.http, run=self.fake.run, clock=lambda: NOW,
                                  sleep=self.fake.sleep, is_root=lambda: True, log=self.logs.append)
        fake_pw = mock.Mock(pw_uid=1000, pw_gid=1000)
        with mock.patch.object(mod, "load_stored_config", return_value=cfg), \
             mock.patch.object(mod, "load_state", return_value={"server_domain": "de2.tunnelsats.com"}), \
             mock.patch.object(mod.pwd, "getpwnam", return_value=fake_pw), \
             mock.patch.object(mod.os, "chown") as chown_mock:
            res_ok = mod.Result("export")
            mod.cmd_export(fake_root_deps, argparse.Namespace(out=root_out), res_ok)
        chown_mock.assert_called_once_with(root_out, 1000, 1000)
        self.assertTrue(res_ok.fields["exported"])

        with mock.patch.object(mod, "load_stored_config", return_value=cfg), \
             mock.patch.object(mod, "load_state", return_value=None), \
             mock.patch.object(mod.pwd, "getpwnam", side_effect=KeyError("no admin")):
            res_no_admin = mod.Result("export")
            mod.cmd_export(fake_root_deps, argparse.Namespace(out=root_out), res_no_admin)
        self.assertTrue(res_no_admin.fields["exported"])


# ------------------------------------------------------------------------------------------
# Region 2 (lines 3191-5161): adopt, status, check, uninstall, repair, subscriptions-list,
# tick, menu helpers, main
# ------------------------------------------------------------------------------------------

class TestAdoptStatusCheckCoverage(ModuleTestCase):
    def test_cmd_adopt_error_branches(self):
        # detect fails -> E_DETECT_FAILED
        self.fake.its["detect"] = (1, "")
        doc = self.run_verb("adopt")
        self.assertEqual("E_DETECT_FAILED", doc["errors"][0]["code"])

        # adopt --upgrade --yes when stored config is missing -> E_STORED_CONFIG
        self.store(mode="adopted_legacy")
        os.unlink(self.path(mod.CONF_FILE))
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_legacy.json"))
        doc = self.run_verb("adopt", "--upgrade", "--yes")
        self.assertEqual("E_STORED_CONFIG", doc["errors"][0]["code"])

        # adopt when another subscription is stored with different public_key -> E_ALREADY_CONFIGURED
        self.store(mode="managed")
        st = mod.load_state(self.deps)
        st["public_key"] = BOB_PUB
        mod.save_state(self.deps, st)
        self.write("etc/wireguard/tunnelsatsv2.conf", fixture("import", "website.conf"))
        doc = self.run_verb("adopt")
        self.assertEqual("E_ALREADY_CONFIGURED", doc["errors"][0]["code"])

        # adopt --upgrade --yes when detect has non-legacy reasons (e.g. Tor off) -> E_NOT_ELIGIBLE
        self.store(mode="adopted_legacy")
        self.fake.conf_set("runBehindTor", "off")
        doc = self.run_verb("adopt", "--upgrade", "--yes")
        self.assertEqual("E_NOT_ELIGIBLE", doc["errors"][0]["code"])

    def test_wg_local_and_cmd_status_edge_cases(self):
        # wg_local: rc != 0 / empty / zero handshake / non-digit transfer
        orig_run = self.fake.run

        def wg_fail(argv, timeout=60, interactive=False):
            if argv[0] == "wg":
                return 1, "", "err"
            return orig_run(argv, timeout=timeout, interactive=interactive)

        self.deps.run = wg_fail
        self.assertEqual({"handshake_age_s": None, "rx_bytes": None, "tx_bytes": None}, mod.wg_local(self.deps))

        self.deps.run = orig_run
        self.fake.wg["latest-handshakes"] = "%s\t0\n" % BOB_PUB
        self.fake.wg["transfer"] = "%s\tabc\tdef\n" % BOB_PUB
        self.assertEqual({"handshake_age_s": None, "rx_bytes": None, "tx_bytes": None}, mod.wg_local(self.deps))

        # cmd_status --refresh: non-confirmed with empty detail AND busy Lock caught cleanly
        self.store()
        with mock.patch.object(mod, "api_status", return_value=("failed", None, "")), \
             mock.patch.object(mod.Lock, "__enter__", side_effect=mod.ModuleError("E_BUSY", "operational", "busy", 1)):
            doc = self.run_verb("status", "--refresh")
        self.assertTrue(doc["ok"])
        self.assertNotIn("sync_detail", doc)

    def test_daemon_cmdline_edge_cases(self):
        # /proc/<pid>/cmdline missing -> None
        os.unlink(self.path("proc/4242/cmdline"))
        args, props = mod.daemon_cmdline(self.deps, "lnd.service")
        self.assertIsNone(args)
        self.assertEqual("4242", props["MainPID"])

        # MainPID is /bin/sh: test listdir OSError
        self.cmdline(4242, ["/bin/sh", "-c", "lightningd"])
        with mock.patch.object(mod.os, "listdir", side_effect=OSError("no proc")):
            args, _props = mod.daemon_cmdline(self.deps, "lnd.service")
        self.assertEqual(["/bin/sh", "-c", "lightningd"], args)

        # /proc has non-digit entry, missing stat entry, non-child pid, and non-lightningd child -> falls through
        os.makedirs(self.path("proc/self"), exist_ok=True)
        os.makedirs(self.path("proc/5001"), exist_ok=True)  # no stat file
        self.cmdline(5002, ["/usr/bin/other"], ppid=1)  # ppid != 4242
        self.cmdline(5003, ["/bin/sleep", "10"], ppid=4242)  # child, not lightningd
        args, _props = mod.daemon_cmdline(self.deps, "lnd.service")
        self.assertEqual(["/bin/sh", "-c", "lightningd"], args)

    def test_public_ipv4_announce_check_run_check_and_cmd_check(self):
        # public_ipv4: invalid octet -> ValueError -> None
        self.assertIsNone(mod.public_ipv4("999.999.999.999"))

        # announce_check: no onion address announced
        state = {"endpoint_host": "de2.tunnelsats.com", "vpn_port": 24556}
        rec = {"decision": "hybrid", "reason": "ok", "announce": {"ipv4": "1.2.3.4", "port": 24556}}
        info = {"uris": ["0280a@1.2.3.4:24556"]}
        self.assertEqual(
            ("degraded", "fail", "no onion address announced", False),
            mod.announce_check("lnd", info, rec, state),
        )

        # run_check with no state and verify --no-probe rc != 9 -> not_configured
        checked_nc = mod.run_check(self.deps)
        self.assertEqual("not_configured", checked_nc["verdict"])

        # run_check full failure coverage
        self.store()
        self.activate_conf()
        self.record()
        # 1) verify is None, audit is not clean, daemon running without flags (decision=hybrid),
        #    other_impl clean (not config_missing), block absent, tool_hash missing, dev_override=yes,
        #    stopped-units present, last-restore failed, vpn_port changed
        self.fake.its["verify"] = (1, "not-json")
        self.fake.its["audit lnd"] = (0, {"status": "dirty", "keys": ["externalhosts"]})
        self.cmdline(4242, ["/usr/local/bin/lnd", "--configfile=/mnt/hdd/app-data/lnd/lnd.conf"])
        self.fake.its["audit cl"] = (0, {"status": "clean", "keys": []})
        self.fake.its["block-status"] = (0, {"state": "absent"})
        self.fake.its["status"] = (0, {"tool_hash": "missing", "dev_override": "yes"})
        self.write("run/tunnelsats/stopped-units", "lnd.service 2026-10-14T11:00:00Z\n")
        self.write("mnt/hdd/app-data/tunnelsats/last-restore.json", json.dumps({"result": "failed", "error": "E_NET"}))
        st = mod.load_state(self.deps)
        st["api"]["data"]["vpn_port"] = 29999
        mod.save_state(self.deps, st)

        checked = mod.run_check(self.deps)
        by_id = {c["id"]: c for c in checked["checks"]}
        self.assertEqual("fail", by_id["verify"]["result"])
        self.assertEqual("fail", by_id["ln_at_rest"]["result"])
        self.assertEqual("fail", by_id["ln_runtime_flags"]["result"])
        self.assertEqual("pass", by_id["other_impl"]["result"])
        self.assertEqual("fail", by_id["restore_block"]["result"])
        self.assertEqual("fail", by_id["tool_pin"]["result"])
        self.assertEqual("fail", by_id["dev_override"]["result"])
        self.assertEqual("fail", by_id["verifier_stopped"]["result"])
        self.assertEqual("fail", by_id["last_restore"]["result"])
        self.assertEqual("fail", by_id["vpn_port"]["result"])

        # 2) verify returns unexpected rc=2 with malformed check entry + other_impl dirty
        vdoc = fixture_json("verify", "protected.json")
        vdoc["checks"] = list(vdoc["checks"]) + ["not-a-dict", {"id": 123}]
        self.fake.its["verify"] = (2, vdoc)
        self.fake.its["audit cl"] = (0, {"status": "dirty", "keys": ["announce-addr"]})
        checked2 = mod.run_check(self.deps)
        by_id2 = {c["id"]: c for c in checked2["checks"]}
        self.assertEqual("fail", by_id2["verify"]["result"])
        self.assertEqual("fail", by_id2["other_impl"]["result"])

        # cmd_check when Lock raises E_BUSY -> caught cleanly
        with mock.patch.object(mod.Lock, "__enter__", side_effect=mod.ModuleError("E_BUSY", "operational", "busy", 1)):
            doc = self.run_verb("check")
        self.assertIn("verdict", doc)


class TestUninstallAndRepairCoverage(ModuleTestCase):
    def test_tool_uninstall_lost_report_and_detect_failed(self):
        self.fake.its["uninstall"] = (1, "")
        self.fake.its["detect"] = (1, "")
        read, note = mod.tool_uninstall(self.deps, "lnd.service")
        self.assertEqual(["managed dataplane"], read["remaining"])
        self.assertIn("detect did not answer", note)

    def test_announce_candidates_invalid_host_and_zero_artifacts_all_leftovers(self):
        self.assertEqual([], mod.announce_candidates(self.deps, {"endpoint_host": "evil.example", "vpn_port": 24556}, None))

        # zero_artifacts with every leftover + warning
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))
        self.fake.its["block-status"] = (0, {"state": "present"})
        self.activate_conf()
        self.fake.its["tick-timer status"] = (0, "active")
        leftovers, warnings = mod.zero_artifacts(self.deps, "lnd", keep_tick_timer=False)
        self.assertTrue(any("tunnelsats install" in x for x in leftovers))
        self.assertTrue(any("tunnelsats=on" in x for x in leftovers))
        self.assertTrue(any("tunnelsats-tick.timer" in x for x in leftovers))
        self.assertTrue(any("/tunnelsats.slice/" in x for x in leftovers))
        self.assertTrue(any("clearnet flags" in x for x in leftovers))
        self.assertTrue(any("restore block" in w for w in warnings))

        # zero_artifacts with impl=None
        leftovers_none, _ = mod.zero_artifacts(self.deps, None)
        self.assertTrue(len(leftovers_none) > 0)

    def test_purge_missing_dir_and_full_tree(self):
        # STATE_DIR absent
        mod.purge(self.deps)

        # STATE_DIR with recovered-*.conf, dist/*, backup/*, and an extra stray file causing rmdir OSError
        self.store()
        self.write("mnt/hdd/app-data/tunnelsats/recovered-01.conf", "secret")
        self.write("mnt/hdd/app-data/tunnelsats/keep-me.txt", "extra")
        self.write("mnt/hdd/app-data/tunnelsats/dist/tunnelsats.sh", "script")
        self.write("mnt/hdd/app-data/tunnelsats/backup/lnd.conf.bak", "bak")
        mod.purge(self.deps)
        self.assertFalse(os.path.exists(self.path("mnt/hdd/app-data/tunnelsats/recovered-01.conf")))
        self.assertFalse(os.path.exists(self.path("mnt/hdd/app-data/tunnelsats/dist")))
        self.assertFalse(os.path.exists(self.path("mnt/hdd/app-data/tunnelsats/backup")))
        self.assertTrue(os.path.exists(self.path("mnt/hdd/app-data/tunnelsats/keep-me.txt")))

    def test_at_rest_action_cln_and_keep_pending_removal_no_state(self):
        act = mod.at_rest_action("cl", {"status": "unrepairable", "keys": ["always-use-proxy"]}, "lightningd.service", None)
        self.assertIn("always-use-proxy=true", act["detail"])

        # keep_pending_removal returns silently when state is None
        mod.keep_pending_removal(self.deps, "lnd.service", {"ln_was_active": True, "ln_started": False})
        self.assertIsNone(mod.load_state(self.deps))

    def test_stop_unless_tor_only_branches(self):
        # unit=None -> skipped
        self.assertEqual((None, "skipped"), mod.stop_unless_tor_only(self.deps, None))

        # managed=None, state unit is lnd (active + dirty), managed_unit returns lightningd (active + dirty + disabled)
        self.store()
        self.fake.its["audit lnd"] = (0, {"status": "dirty", "keys": ["externalhosts"]})
        self.fake.its["audit cl"] = (0, {"status": "dirty", "keys": ["announce-addr"]})
        vdoc = fixture_json("verify", "cln_protected.json")
        self.fake.its["verify --no-probe"] = (0, vdoc)
        self.fake.units["lightningd.service"]["ActiveState"] = "active"
        self.fake.units["lightningd.service"]["UnitFileState"] = "disabled"
        rec, outcome = mod.stop_unless_tor_only(self.deps, "lnd.service", managed=None)
        self.assertEqual("stopped", outcome)
        self.assertEqual("lightningd.service", rec["unit"])
        self.assertFalse(rec["ln_disabled"])

    def test_cmd_uninstall_branches(self):
        # 1) keep_tick True (pending order exists, not --purge) -> tick-timer off is NOT called;
        #    also unit_impl is None (no lightning active, no impl in state/conf, tunnelsats=on)
        self.write("mnt/hdd/app-data/raspiblitz.conf", "tunnelsats=on\nrunBehindTor=on\n")
        pdoc = mod.empty_pending()
        pdoc["order"] = {"id": "o1", "state": "awaiting_payment"}
        mod.save_pending(self.deps, pdoc)
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_none.json"))
        self.fake.its["block-status"] = (0, {"state": "absent"})
        doc = self.run_verb("uninstall", "--yes")
        self.assertTrue(doc["ok"])
        self.assertFalse(self.fake.calls_of(mod.ITS, "tick-timer", "off"))

        # 2) not complete (remaining non-empty) AND keep_off returns stop_failed -> keep_off_error (E_LN_STOP)
        self.write("mnt/hdd/app-data/raspiblitz.conf", "lightning=lnd\nlnd=on\nchain=main\nrunBehindTor=on\n")
        self.store()
        self.activate_conf()
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))
        self.fake.its["audit lnd"] = (0, {"status": "clean", "keys": []})
        # uninstall leaves remaining AND unit active, then post-uninstall audit --repair is unrepairable,
        # and systemctl stop lnd.service is a noop so keep_off returns stop_failed!
        inc = dict(fixture_json("tool", "uninstall_incomplete.json"), ln_started=True, ln_was_active=True)
        self.fake.its["uninstall"] = (1, inc)
        self.fake.its["audit lnd --repair"] = (1, {"status": "unrepairable", "reason": "syntax", "keys": ["externalhosts"]})
        self.fake.systemctl_noop.add(("stop", "lnd.service"))
        doc2 = self.run_verb("uninstall", "--yes")
        self.assertEqual("E_LN_STOP", doc2["errors"][0]["code"])
        self.fake.systemctl_noop.clear()

        # 3) complete, not main_ok, not problem, not ln_disabled, ln_was_active=True & ln_started=False
        #    -> then = "systemctl start lnd.service"
        self.store()
        self.activate_conf()
        self.fake.units["lnd.service"]["ActiveState"] = "active"
        self.fake.units["lnd.service"]["UnitFileState"] = "disabled"
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))
        self.fake.its["audit lnd"] = (0, {"status": "clean", "keys": []})
        un_doc = dict(fixture_json("tool", "uninstall_disabled.json"), ln_disabled=False, ln_was_active=True, ln_started=False)
        self.fake.its["uninstall"] = (0, un_doc)
        self.fake.its["audit lnd --repair"] = (1, {"status": "unrepairable", "reason": "dirty", "keys": ["externalhosts"], "lines": ["lnd.conf:1:externalhosts"]})
        doc3 = self.run_verb("uninstall", "--yes")
        self.assertEqual("E_AT_REST_UNREPAIRABLE", doc3["errors"][0]["code"])
        self.assertEqual("systemctl start lnd.service", doc3["action_required"]["then"])

        # 4) leftovers present after clean uninstall -> E_ARTIFACTS_LEFT
        self.store()
        self.activate_conf()
        self.fake.its["audit lnd --repair"] = (0, {"status": "clean", "keys": []})
        self.fake.its["uninstall"] = (0, fixture_json("tool", "uninstall_clean.json"))
        # detect still reports managed in zero_artifacts
        self.fake.its["detect"] = [
            (0, fixture_json("tool", "detect_managed.json")),
            (0, fixture_json("tool", "detect_managed.json")),
        ]
        self.fake.its["block-status"] = (0, {"state": "absent"})
        doc4 = self.run_verb("uninstall", "--yes")
        self.assertEqual("E_ARTIFACTS_LEFT", doc4["errors"][0]["code"])

    def test_dataplane_healthy_and_cmd_repair_branches(self):
        # dataplane_healthy False paths
        self.fake.its["verify --no-probe"] = (4, fixture_json("verify", "unsafe_fail_rc5.json"))
        self.assertFalse(mod.dataplane_healthy(self.deps, "lnd"))

        v_em = fixture_json("verify", "activating_emergency_block.json")
        self.fake.its["verify --no-probe"] = (5, v_em)
        self.assertFalse(mod.dataplane_healthy(self.deps, "lnd"))

        # cmd_repair without --yes -> E_CONFIRMATION_REQUIRED
        doc = self.run_verb("repair")
        self.assertEqual("E_CONFIRMATION_REQUIRED", doc["errors"][0]["code"])

        # cmd_repair with missing stored config -> E_STORED_CONFIG
        self.store()
        os.unlink(self.path(mod.CONF_FILE))
        doc = self.run_verb("repair", "--yes")
        self.assertEqual("E_STORED_CONFIG", doc["errors"][0]["code"])

        # cmd_repair with no lightning active -> E_NOT_ELIGIBLE
        self.store()
        self.write("mnt/hdd/app-data/raspiblitz.conf", "chain=main\nrunBehindTor=on\n")
        doc = self.run_verb("repair", "--yes")
        self.assertEqual("E_NOT_ELIGIBLE", doc["errors"][0]["code"])

        # cmd_repair when managed + unhealthy + uninstall returns ln_disabled=False -> reinstalls without reenable
        self.write("mnt/hdd/app-data/raspiblitz.conf", "lightning=lnd\nlnd=on\nchain=main\nrunBehindTor=on\n")
        self.store()
        self.activate_conf()
        self.record()
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))
        self.fake.its["status"] = (0, {"tool_hash": "accepted_older", "dev_override": "no"})
        self.fake.its["uninstall"] = (0, fixture_json("tool", "uninstall_clean.json"))
        self.fake.its["verify --no-probe"] = (5, fixture_json("verify", "activating_tunnel_up.json"))
        doc = self.run_verb("repair", "--yes")
        self.assertIn("uninstall", doc["actions"])
        self.assertNotIn("reenable", doc["actions"])
        self.assertIn("install", doc["actions"])

        # cmd_repair when managed + healthy + unit_template_ok is False -> regenerates unit in place
        self.fake.its["status"] = (0, {"tool_hash": "current", "dev_override": "no"})
        self.fake.its["verify --no-probe"] = (0, fixture_json("verify", "protected.json"))
        self.write("etc/systemd/system/lnd.service", "[Service]\nExecStart=/usr/local/bin/lnd\n")
        doc2 = self.run_verb("repair", "--yes")
        self.assertTrue(doc2["ok"])
        self.assertIn("unit_regenerated", doc2["actions"])
        self.assertNotIn("install", doc2["actions"])


class TestSubscriptionsTickMenuMainCoverage(ModuleTestCase):
    def test_cmd_subscriptions_list_expired_and_peer_disabled(self):
        # Expired
        self.store()
        st = mod.load_state(self.deps)
        st["api"]["data"]["expiry"] = "2026-10-01T00:00:00Z"
        mod.save_state(self.deps, st)
        doc = self.run_verb("subscriptions-list")
        self.assertEqual("expired", doc["subscriptions"][0]["warning"])

        # Future expiry + peer_status disabled
        st["api"]["data"]["expiry"] = "2026-12-01T00:00:00Z"
        st["api"]["data"]["peer_status"] = "disabled"
        mod.save_state(self.deps, st)
        doc2 = self.run_verb("subscriptions-list")
        self.assertEqual("peer disabled (bandwidth or subscription)", doc2["subscriptions"][0]["warning"])

    def test_notify_state_send_event_verdict_and_load_status_file(self):
        # _ensure_notify_state partial raw dict without daily/events
        ns = mod._ensure_notify_state({"notify_state": {"last_verdict": "degraded"}})
        self.assertEqual("degraded", ns["last_verdict"])
        self.assertEqual({"date": None, "count": 0}, ns["daily"])
        self.assertEqual({}, ns["events"])

        # send_event_notification daily cap (>= 10) for verdict event
        ns["daily"] = {"date": "2026-10-14", "count": 10}
        entry = mod.send_event_notification(self.deps, {"notify": "on"}, ns, "verdict_degraded", "v:1:degraded", now_dt=NOW)
        self.assertEqual("capped", entry["outcome"])

        # _tick_live_verdict: verify is None -> unsafe
        self.fake.its["verify --no-probe"] = (1, "not-json")
        self.assertEqual("unsafe", mod._tick_live_verdict(self.deps, "lnd", {"ActiveState": "active"}))

        # _tick_live_verdict: rc=5 with unsafe failing check -> unsafe
        self.fake.its["verify --no-probe"] = (5, {
            "verdict": "degraded",
            "checks": [{"id": "killswitch", "class": "unsafe", "result": "fail", "detail": "down"}],
        })
        self.assertEqual("unsafe", mod._tick_live_verdict(self.deps, "lnd", {"ActiveState": "active"}))

        # _load_status_file: missing, empty, too large, invalid JSON, raw_api wrapper, invalid schema
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._load_status_file(self.deps, "/no-such-file.json")
        self.assertEqual("E_API_INVALID", ctx.exception.code)

        self.write("empty.json", "")
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._load_status_file(self.deps, "/empty.json")
        self.assertEqual("E_API_INVALID", ctx.exception.code)

        self.write("bad.json", "{not-json")
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._load_status_file(self.deps, "/bad.json")
        self.assertEqual("E_API_INVALID", ctx.exception.code)

        valid_status = fixture_json("api", "status_enabled.json")
        self.write("wrapped.json", json.dumps({"raw_api": valid_status}))
        loaded = mod._load_status_file(self.deps, "/wrapped.json")
        self.assertEqual("enabled", loaded["peer_status"])

        self.write("invalid_status.json", json.dumps({"foo": "bar"}))
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._load_status_file(self.deps, "/invalid_status.json")
        self.assertEqual("E_API_INVALID", ctx.exception.code)

    def test_cmd_tick_branches(self):
        # Invalid --now -> E_USAGE
        doc = self.run_verb("tick", "--now", "not-a-time", "--no-persist")
        self.assertEqual("E_USAGE", doc["errors"][0]["code"])

        # Busy lock -> skipped
        with mock.patch.object(mod.Lock, "__enter__", side_effect=mod.ModuleError("E_BUSY", "operational", "busy", 1)):
            doc = self.run_verb("tick")
        self.assertTrue(doc["ok"])
        self.assertIn("skipped", doc)

        # Pending order with on_settle_notify returning None (already notified) AND state None (not dirty)
        pdoc = mod.empty_pending()
        pdoc["order"] = {"id": "o1", "state": "awaiting_payment"}
        mod.save_pending(self.deps, pdoc)

        def fake_settle_once(deps, result, foreground=False, notify_event=None, use_lock=True):
            # Trigger twice: first hands off, second returns None (dedup branch)
            notify_event("payment_received", "o1")
            notify_event("payment_received", "o1")
            return {"done": False, "settled": False}

        with mock.patch.object(mod, "settle_once", side_effect=fake_settle_once):
            doc = self.run_verb("tick")
        self.assertTrue(doc["ok"])
        mod.save_pending(self.deps, mod.empty_pending())

        # Invalid impl in state & conf -> early return
        self.store(impl="bogus")
        self.fake.conf_set("tunnelsats", "on")
        self.fake.conf_set("tunnelsatsImpl", "bogus")
        doc = self.run_verb("tick")
        self.assertTrue(doc["ok"])

        # 6-hour sync fails (s_out != confirmed), expiry_dt is None, api_data is empty
        self.store(impl="lnd")
        self.activate_conf()
        st = mod.load_state(self.deps)
        st["valid_until"] = None
        st["api"] = {"outcome": "skipped", "checked_at": "2026-10-14T00:00:00Z", "data": None}
        mod.save_state(self.deps, st)
        self.fake.http_responses = [(500, {}, b"err")]
        self.fake.its["verify --no-probe"] = (0, fixture_json("verify", "protected.json"))
        doc = self.run_verb("tick")
        self.assertTrue(doc["ok"])

        # Expiry & bandwidth deduplication (entry is None on second run) + limit == 0 + bandwidth drop recovery
        self.fake.conf_set("notify", "on")
        st = mod.load_state(self.deps)
        st["api"] = {
            "outcome": "confirmed",
            "checked_at": "2026-10-14T11:30:00Z",
            "data": {
                "expiry": "2026-10-10T00:00:00Z",
                "bandwidth_used_gb": 100.0,
                "bandwidth_limit_gb": 100.0,
                "resets_this_month": 0,
                "max_resets_per_month": 2,
                "peer_status": "enabled",
                "server_domain": "de2.tunnelsats.com",
                "vpn_port": 24556,
                "last_synced_at": "2026-10-14T11:30:00Z",
            },
        }
        mod.save_state(self.deps, st)
        # First tick fires expired + bandwidth_exhausted
        doc_first = self.run_verb("tick")
        self.assertEqual(2, len(doc_first["notifications"]))
        # Second tick deduplicates both (entry is None branches for expired and bandwidth_exhausted)
        doc_second = self.run_verb("tick")
        self.assertEqual([], doc_second["notifications"])

        # Expiry soon + bandwidth_high, then deduplicated on second tick
        st = mod.load_state(self.deps)
        st["api"]["data"]["expiry"] = "2026-10-15T12:00:00Z"
        st["api"]["data"]["bandwidth_used_gb"] = 85.0
        mod.save_state(self.deps, st)
        doc_hi1 = self.run_verb("tick")
        self.assertEqual(2, len(doc_hi1["notifications"]))
        doc_hi2 = self.run_verb("tick")
        self.assertEqual([], doc_hi2["notifications"])

        # Bandwidth drops below 80% with peer_status == enabled -> clears bandwidth_high/exhausted events
        st = mod.load_state(self.deps)
        st["api"]["data"]["bandwidth_used_gb"] = 10.0
        mod.save_state(self.deps, st)
        self.run_verb("tick")
        st_after = mod.load_state(self.deps)
        self.assertNotIn("bandwidth_high", st_after["notify_state"]["events"])

        # limit == 0 (elif condition False -> [4561, 4567])
        st_after["api"]["data"]["bandwidth_limit_gb"] = 0
        mod.save_state(self.deps, st_after)
        self.run_verb("tick")

        # all_clear: first attempt fails (keeps verdict_warning_handed_off=True -> [4608, 4610]),
        # then succeeds, then when verdict_warning_handed_off manually re-set for same cycle -> entry is None ([4606, 4612])
        st = mod.load_state(self.deps)
        st["notify_state"]["last_verdict"] = "degraded"
        st["notify_state"]["verdict_seq"] = 1
        st["notify_state"]["verdict_warning_handed_off"] = True
        mod.save_state(self.deps, st)
        self.fake.notify_rc = 1
        doc_ac_fail = self.run_verb("tick")
        self.assertEqual("failed", doc_ac_fail["notifications"][0]["outcome"])
        self.assertTrue(mod.load_state(self.deps)["notify_state"]["verdict_warning_handed_off"])

        self.fake.notify_rc = 0
        doc_ac_ok = self.run_verb("tick")
        self.assertEqual("handed_off", doc_ac_ok["notifications"][0]["outcome"])
        self.assertFalse(mod.load_state(self.deps)["notify_state"]["verdict_warning_handed_off"])

        # Same clear cycle with verdict_warning_handed_off=True -> send_event_notification returns None
        st = mod.load_state(self.deps)
        st["notify_state"]["verdict_warning_handed_off"] = True
        mod.save_state(self.deps, st)
        doc_ac_dup = self.run_verb("tick")
        self.assertEqual([], doc_ac_dup["notifications"])

    def test_menu_helpers_result_text_status_text_and_main(self):
        # check_text: protected (no fails) and degraded (mix of pass and fail)
        txt_ok = mod.check_text({"verdict": "protected", "checks": [{"id": "a", "result": "pass", "detail": "ok"}]})
        self.assertIn("Every check passed.", txt_ok)
        txt_deg = mod.check_text({
            "verdict": "degraded",
            "checks": [
                {"id": "a", "result": "pass", "detail": "ok"},
                {"id": "b", "result": "fail", "detail": "broken"},
            ],
        })
        self.assertIn("- b: broken", txt_deg)
        self.assertNotIn("Every check passed.", txt_deg)

        # menu_run: ok verb, ModuleError, and _UsageError
        self.fake.http_responses = [(200, {}, fixture("api", "servers.json", mode="rb"))]
        self.assertTrue(mod.menu_run(self.deps, ["servers"])["ok"])
        err_mod = mod.menu_run(self.deps, ["repair"])
        self.assertEqual("E_CONFIRMATION_REQUIRED", err_mod["errors"][0]["code"])
        err_use = mod.menu_run(self.deps, ["not-a-verb"])
        self.assertEqual("E_USAGE", err_use["errors"][0]["code"])

        # menu_choices: active TS + active unit + guard record reason="ok" (not restartable)
        self.store()
        self.activate_conf()
        self.record(reason="ok")
        choices, notice = mod.menu_choices(self.deps, mod.load_state(self.deps), mod.read_rb_conf(self.deps))
        tags = [t for t, _ in choices]
        self.assertNotIn("RESTART", tags)
        self.assertIsNone(notice)

        # pending_removal_text: reason=None with running=True + audit None + audit without lines
        self.fake.its["audit lnd"] = (1, "not-json")
        t1 = mod.pending_removal_text(self.deps, {"unit": "lnd.service"})
        self.assertIn("still runs", t1)
        self.assertIn("the check did not answer", t1)

        self.fake.its["audit lnd"] = (1, {"status": "unrepairable", "reason": "config_missing"})
        t2 = mod.pending_removal_text(self.deps, {"unit": "lnd.service"})
        self.assertIn("(config_missing)", t2)

        # menu_server_choices: non-dict item and incomplete dict item
        sc = mod.menu_server_choices([
            "not-a-dict",
            {"id": "", "country": "DE", "city": "Berlin", "status": "online"},
            {"id": "eu-de", "country": "Germany", "city": "Nuremberg", "status": "online"},
        ])
        self.assertEqual([("eu-de", "Germany - Nuremberg")], sc)

        # menu_start: invalid impl in state -> None
        self.store(impl="invalid")
        self.fake.conf_set("tunnelsats", "on")
        self.assertIsNone(mod.menu_start(self.deps))

        # result_text: error with action_required (then only / lines only / non-uninstall then),
        # and ok with custom_installs_lines
        rt1 = mod.result_text({
            "command": "repair",
            "errors": [{"code": "E_X", "message": "failed"}],
            "action_required": {"then": "systemctl start lnd.service"},
        })
        self.assertIn("Then run: sudo systemctl start lnd.service", rt1)
        self.assertNotIn("REMOVE again", rt1)

        rt2 = mod.result_text({
            "command": "repair",
            "errors": [{"code": "E_X", "message": "failed"}],
            "action_required": {"lines": ["lnd.conf:1:externalhosts"]},
        })
        self.assertIn("Lines to remove:", rt2)
        self.assertNotIn("Then run:", rt2)

        rt3 = mod.result_text({
            "command": "adopt",
            "errors": [],
            "custom_installs_lines": [{"line": 7, "text": "tunnelsats.sh"}],
        })
        self.assertIn("7: tunnelsats.sh", rt3)

        # status_text: unconfigured, configured without action, configured with action
        self.assertIn("No TunnelSats", mod.status_text({"configured": False}))
        st_no_act = mod.status_text({"configured": True, "server_domain": "de2.tunnelsats.com", "vpn_port": 24556})
        self.assertIn("Handshake:   none", st_no_act)
        st_act = mod.status_text({
            "configured": True,
            "server_domain": "de2.tunnelsats.com",
            "vpn_port": 24556,
            "tunnel": {"handshake_age_s": 12},
            "action": "server port changed: REPAIR",
        })
        self.assertIn("12 s ago", st_act)
        self.assertIn("server port changed: REPAIR", st_act)

        # main: --help returns EXIT_OK
        with mock.patch("sys.stdout", new_callable=io.StringIO):
            self.assertEqual(mod.EXIT_OK, mod.main(["--help"], deps=self.deps))

        # main: menu without --json returns EXIT_OK without emit
        buf = io.StringIO()
        with mock.patch.dict(mod.HANDLERS, {"menu": lambda d, a, r: None}):
            rc = mod.main(["menu"], deps=self.deps, out=buf)
        self.assertEqual(mod.EXIT_OK, rc)
        self.assertEqual("", buf.getvalue())


if __name__ == "__main__":
    unittest.main()
