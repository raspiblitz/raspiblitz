#!/usr/bin/python3
"""Comprehensive line and branch coverage tests for payment, claim, settle, and pay-node paths
in blitz.subscriptions.tunnelsats.py (lines 1660-3190).
"""

import argparse
import datetime
import hashlib
import io
import json
import os
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
    ENVELOPE,
    ModuleTestCase,
    NOW,
    fixture,
    fixture_json,
    make_bolt11,
    mod,
    schema_check,
)

PREIMAGE_A = "aa" * 32
HASH_A = hashlib.sha256(bytes.fromhex(PREIMAGE_A)).hexdigest()
PREIMAGE_B = "bb" * 32
HASH_B = hashlib.sha256(bytes.fromhex(PREIMAGE_B)).hexdigest()


def _valid_claim_doc(pub=ALICE_PUB):
    doc = fixture_json("api", "claim_client_held.json")
    doc["peer"]["publicKey"] = pub
    return doc


def _save_pending(deps, **fields):
    doc = mod.empty_pending()
    doc.update(fields)
    mod.save_pending(deps, doc)
    return doc


def _make_order(payment_hash=HASH_A, order_id="ord-cov-1", state="awaiting_payment",
                server_id="eu-de", months=1, impl="lnd", amount_sats=25000,
                priv=ALICE_PRIV, pub=ALICE_PUB, expiry_offset=3600, extra=None):
    inv_hash = payment_hash if mod.HEX64_RE.fullmatch(str(payment_hash or "")) else HASH_A
    inv = make_bolt11("lnbc%du" % (amount_sats // 100), payment_hash=inv_hash, expiry=3600)
    rec = {
        "order_id": order_id,
        "payment_hash": payment_hash,
        "invoice": inv,
        "amount_sats": amount_sats,
        "server_id": server_id,
        "months": months,
        "impl": impl,
        "private_key": priv,
        "public_key": pub,
        "created_at": mod.iso(NOW),
        "invoice_expires_at": mod.iso(NOW + datetime.timedelta(seconds=expiry_offset)),
        "retained_until": mod.iso(NOW + datetime.timedelta(seconds=mod.PENDING_TTL_SECONDS)),
        "state": state,
        "node_payment": {"state": "none", "result": None},
    }
    if extra:
        rec.update(extra)
    return rec


def _make_renewal(payment_hash=HASH_A, renewal_id="ren-cov-1", state="awaiting_payment",
                  server_id="de2", months=1, amount_sats=25000, pub=ALICE_PUB,
                  old_expiry="2026-12-01T00:00:00Z", expiry_offset=3600, extra=None):
    inv_hash = payment_hash if mod.HEX64_RE.fullmatch(str(payment_hash or "")) else HASH_A
    inv = make_bolt11("lnbc%du" % (amount_sats // 100), payment_hash=inv_hash, expiry=3600)
    rec = {
        "renewal_id": renewal_id,
        "payment_hash": payment_hash,
        "invoice": inv,
        "amount_sats": amount_sats,
        "server_id": server_id,
        "months": months,
        "old_expiry": old_expiry,
        "new_expiry": "2026-12-31T00:00:00Z",
        "public_key": pub,
        "created_at": mod.iso(NOW),
        "invoice_expires_at": mod.iso(NOW + datetime.timedelta(seconds=expiry_offset)),
        "retained_until": mod.iso(NOW + datetime.timedelta(seconds=mod.PENDING_TTL_SECONDS)),
        "state": state,
        "node_payment": {"state": "none", "result": None},
    }
    if extra:
        rec.update(extra)
    return rec


def _make_reset(payment_hash=HASH_A, reset_id="rst-cov-1", state="awaiting_payment",
                server_id="de2", amount_sats=10000, pub=ALICE_PUB,
                old_resets=0, old_used_gb=95.0, expiry_offset=3600, extra=None):
    inv_hash = payment_hash if mod.HEX64_RE.fullmatch(str(payment_hash or "")) else HASH_A
    inv = make_bolt11("lnbc%du" % (amount_sats // 100), payment_hash=inv_hash, expiry=3600)
    rec = {
        "reset_id": reset_id,
        "payment_hash": payment_hash,
        "invoice": inv,
        "amount_sats": amount_sats,
        "server_id": server_id,
        "public_key": pub,
        "created_at": mod.iso(NOW),
        "invoice_expires_at": mod.iso(NOW + datetime.timedelta(seconds=expiry_offset)),
        "retained_until": mod.iso(NOW + datetime.timedelta(seconds=mod.PENDING_TTL_SECONDS)),
        "state": state,
        "old_resets": old_resets,
        "old_used_gb": old_used_gb,
        "node_payment": {"state": "none", "result": None},
    }
    if extra:
        rec.update(extra)
    return rec


class TestApiRequestAndPolling(ModuleTestCase):
    def test_api_json_request_errors_and_503_retry(self):
        # Transport error -> E_API_UNAVAILABLE
        self.fake.http_responses = [OSError("connection refused")]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._api_json_request(self.deps, mod.API_SERVERS_URL)
        self.assertEqual(("E_API_UNAVAILABLE", mod.EXIT_API_UNAVAILABLE), (ctx.exception.code, ctx.exception.exit_code))

        # Oversized body -> E_API_INVALID
        self.fake.http_responses = [(200, {}, b"x" * (mod.API_MAX_BYTES + 1))]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._api_json_request(self.deps, mod.API_SERVERS_URL)
        self.assertEqual(("E_API_INVALID", mod.EXIT_INVALID_API), (ctx.exception.code, ctx.exception.exit_code))

        # 503 with numeric retry-after > 60 is capped to 60 and retried once
        self.fake.sleeps.clear()
        self.fake.http_responses = [
            (503, {"retry-after": "120"}, b"{}"),
            (200, {}, b'{"ok": true}'),
        ]
        status, _hdrs, doc, code = mod._api_json_request(self.deps, mod.API_SERVERS_URL)
        self.assertEqual((200, {"ok": True}, None, [60]), (status, doc, code, self.fake.sleeps))

        # 503 with non-numeric retry-after sleeps 30; second 503 breaks and returns error code
        self.fake.sleeps.clear()
        self.fake.http_responses = [
            (503, {"retry-after": "later"}, b""),
            (503, {}, b'{"error": "ERR_DOWN"}'),
        ]
        status, _hdrs, doc, code = mod._api_json_request(self.deps, mod.API_SERVERS_URL)
        self.assertEqual((503, {"error": "ERR_DOWN"}, "ERR_DOWN", [30]),
                         (status, doc, code, self.fake.sleeps))

        # Empty body on 204 returns doc=None
        self.fake.http_responses = [(204, {}, b"")]
        status, _hdrs, doc, code = mod._api_json_request(self.deps, mod.API_SERVERS_URL)
        self.assertEqual((204, None, None), (status, doc, code))

    def test_poll_order_status_all_branches(self):
        # Invalid payment_hash
        self.assertEqual("invalid", mod.poll_order_status(self.deps, None)[0])
        self.assertEqual("invalid", mod.poll_order_status(self.deps, "short")[0])

        # Transport exception -> failed
        self.fake.http_responses = [RuntimeError("net down")]
        self.assertEqual("failed", mod.poll_order_status(self.deps, HASH_A)[0])

        # Oversized response -> invalid
        self.fake.http_responses = [(200, {}, b"a" * (mod.API_MAX_BYTES + 1))]
        self.assertEqual("invalid", mod.poll_order_status(self.deps, HASH_A)[0])

        # 202 and processing
        self.fake.http_responses = [(202, {}, b'{"status": "pending"}')]
        self.assertEqual(("ok", "processing"), mod.poll_order_status(self.deps, HASH_A)[:2])
        self.fake.http_responses = [(200, {}, b'{"status": "processing"}')]
        self.assertEqual(("ok", "processing"), mod.poll_order_status(self.deps, HASH_A)[:2])

        # Pending synonyms
        for raw_st in ("pending", "awaiting_payment", "unpaid"):
            self.fake.http_responses = [(200, {}, json.dumps({"status": raw_st}).encode())]
            self.assertEqual(("ok", "pending"), mod.poll_order_status(self.deps, HASH_A)[:2])

        # Terminal statuses
        for raw_st in ("paid", "claimed", "expired"):
            self.fake.http_responses = [(200, {}, json.dumps({"status": raw_st}).encode())]
            self.assertEqual(("ok", raw_st), mod.poll_order_status(self.deps, HASH_A)[:2])

        # Unexpected status string
        self.fake.http_responses = [(200, {}, b'{"status": "weird"}')]
        self.assertEqual("invalid", mod.poll_order_status(self.deps, HASH_A)[0])

        # 404 -> not_found
        self.fake.http_responses = [(404, {}, b"{}")]
        self.assertEqual("not_found", mod.poll_order_status(self.deps, HASH_A)[0])

        # 429 with numeric and non-numeric retry-after
        self.fake.http_responses = [(429, {"retry-after": "15"}, b"{}")]
        out, _st, _doc, det = mod.poll_order_status(self.deps, HASH_A)
        self.assertEqual(("failed", "rate limited, retry in 15 s"), (out, det))
        self.fake.http_responses = [(429, {"retry-after": "abc"}, b"{}")]
        out, _st, _doc, det = mod.poll_order_status(self.deps, HASH_A)
        self.assertEqual(("failed", "rate limited, retry in 60 s"), (out, det))

        # 500+ -> failed
        self.fake.http_responses = [(502, {}, b"bad gateway")]
        self.assertEqual("failed", mod.poll_order_status(self.deps, HASH_A)[0])

        # Other 4xx or 200 non-dict -> invalid
        self.fake.http_responses = [(400, {}, b"{}")]
        self.assertEqual("invalid", mod.poll_order_status(self.deps, HASH_A)[0])
        self.fake.http_responses = [(200, {}, b"[]")]
        self.assertEqual("invalid", mod.poll_order_status(self.deps, HASH_A)[0])

    def test_poll_reset_status_all_branches(self):
        # Invalid payment_hash
        self.assertEqual("invalid", mod.poll_reset_status(self.deps, 123)[0])
        self.assertEqual("invalid", mod.poll_reset_status(self.deps, "not-hex")[0])

        # Transport exception -> failed
        self.fake.http_responses = [OSError("boom")]
        self.assertEqual("failed", mod.poll_reset_status(self.deps, HASH_A)[0])

        # Oversized response -> invalid
        self.fake.http_responses = [(200, {}, b"b" * (mod.API_MAX_BYTES + 1))]
        self.assertEqual("invalid", mod.poll_reset_status(self.deps, HASH_A)[0])

        # Wrong subscription type
        self.fake.http_responses = [(200, {}, b'{"type": "subscription", "status": "paid"}')]
        self.assertEqual("invalid", mod.poll_reset_status(self.deps, HASH_A)[0])

        # Valid type and omitted type across statuses
        self.fake.http_responses = [(202, {}, b'{"type": "bandwidth_reset", "status": "pending"}')]
        self.assertEqual(("ok", "processing"), mod.poll_reset_status(self.deps, HASH_A)[:2])
        self.fake.http_responses = [(200, {}, b'{"status": "unpaid"}')]
        self.assertEqual(("ok", "pending"), mod.poll_reset_status(self.deps, HASH_A)[:2])
        for raw_st in ("paid", "claimed", "expired", "failed"):
            self.fake.http_responses = [(200, {}, json.dumps({"type": "bandwidth_reset", "status": raw_st}).encode())]
            self.assertEqual(("ok", raw_st), mod.poll_reset_status(self.deps, HASH_A)[:2])

        # Unexpected status string
        self.fake.http_responses = [(200, {}, b'{"type": "bandwidth_reset", "status": "mystery"}')]
        self.assertEqual("invalid", mod.poll_reset_status(self.deps, HASH_A)[0])

        # 404, 429, 500+, 400
        self.fake.http_responses = [(404, {}, b"{}")]
        self.assertEqual("not_found", mod.poll_reset_status(self.deps, HASH_A)[0])
        self.fake.http_responses = [(429, {"retry-after": "25"}, b"{}")]
        res_429_num = mod.poll_reset_status(self.deps, HASH_A)
        self.assertEqual(("failed", "rate limited, retry in 25 s"), (res_429_num[0], res_429_num[3]))
        self.fake.http_responses = [(429, {"retry-after": "none"}, b"{}")]
        res_429 = mod.poll_reset_status(self.deps, HASH_A)
        self.assertEqual(("failed", "rate limited, retry in 60 s"), (res_429[0], res_429[3]))
        self.fake.http_responses = [(500, {}, b"err")]
        self.assertEqual("failed", mod.poll_reset_status(self.deps, HASH_A)[0])
        self.fake.http_responses = [(400, {}, b"{}")]
        self.assertEqual("invalid", mod.poll_reset_status(self.deps, HASH_A)[0])


class TestAssembleClaimedConfigAndQr(ModuleTestCase):
    def test_assemble_claimed_config_success_variants_and_all_rejections(self):
        # Success with list allowedIPs, empty presharedKey, valid mtu, date-only subscriptionEnd
        doc = _valid_claim_doc()
        doc["peer"]["presharedKey"] = ""
        doc["server"]["allowedIPs"] = ["0.0.0.0/0", "::/0"]
        doc["server"]["mtu"] = 1420
        doc["subscriptionEnd"] = "2027-03-15"
        cfg = mod.assemble_claimed_config(doc, ALICE_PRIV, ALICE_PUB)
        self.assertIsNone(cfg["preshared_key"])
        self.assertEqual(1420, cfg["mtu"])
        self.assertEqual(["0.0.0.0/0", "::/0"], cfg["allowed_ips"])
        self.assertEqual("2027-03-15T00:00:00Z", cfg["valid_until"])

        # Direct argument failures
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.assemble_claimed_config(["not-a-dict"], ALICE_PRIV, ALICE_PUB)
        self.assertEqual("E_CLAIM_INVALID", ctx.exception.code)

        with self.assertRaises(mod.ModuleError) as ctx:
            mod.assemble_claimed_config(_valid_claim_doc(), "bad-key", ALICE_PUB)
        self.assertEqual("E_CLAIM_INVALID", ctx.exception.code)

        with self.assertRaises(mod.ModuleError) as ctx:
            mod.assemble_claimed_config(_valid_claim_doc(), ALICE_PRIV, BOB_PUB)
        self.assertEqual("E_CLAIM_INVALID", ctx.exception.code)

        # Document field rejections
        base = _valid_claim_doc()
        cases = [
            dict(base, peer="not-a-dict"),
            dict(base, server="not-a-dict"),
            dict(base, peer=dict(base["peer"], address="not-an-ip")),
            dict(base, peer=dict(base["peer"], presharedKey="not-a-key")),
            dict(base, server=dict(base["server"], publicKey="bad-key")),
            dict(base, server=dict(base["server"], publicKey=ALICE_PUB)),
            dict(base, server=dict(base["server"], endpoint="de2.tunnelsats.com")),
            dict(base, server=dict(base["server"], endpoint=12345)),
            dict(base, server=dict(base["server"], allowedIPs=12345)),
            dict(base, server=dict(base["server"], allowedIPs=[123])),
            dict(base, server=dict(base["server"], persistentKeepalive=True)),
            dict(base, server=dict(base["server"], persistentKeepalive=-1)),
            dict(base, server=dict(base["server"], mtu=True)),
            dict(base, server=dict(base["server"], mtu=1000)),
            dict(base, server=dict(base["server"], mtu=1600)),
            dict(base, subscriptionEnd=""),
            dict(base, subscriptionEnd=None),
        ]
        for bad_doc in cases:
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.assemble_claimed_config(bad_doc, ALICE_PRIV, ALICE_PUB)
            self.assertEqual("E_CLAIM_INVALID", ctx.exception.code)

        # Assembled config exceeding MAX_CONFIG_BYTES causes parse_wg_config to fail -> E_CLAIM_INVALID
        huge_allowed = ["0.0.0.0/0"] + ["10.%d.%d.0/24" % (i // 256, i % 256) for i in range(1300)]
        oversized_doc = dict(base, server=dict(base["server"], allowedIPs=huge_allowed))
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.assemble_claimed_config(oversized_doc, ALICE_PRIV, ALICE_PUB)
        self.assertEqual("E_CLAIM_INVALID", ctx.exception.code)
        self.assertIn("assembled config failed validation", ctx.exception.message)

    def test_show_qr_branches(self):
        # Empty / non-str invoice does nothing
        mod.show_qr(self.deps, "")
        mod.show_qr(self.deps, None)
        self.assertEqual([], self.fake.calls)

        # Success prints ANSI QR to stderr and sends to blitz.display.sh
        stderr_buf = io.StringIO()
        with mock.patch.object(sys, "stderr", stderr_buf):
            mod.show_qr(self.deps, "lnbc250u1test")
        self.assertIn("FAKE_ANSI_QR", stderr_buf.getvalue())
        self.assertIn([mod.BLITZ_DISPLAY, "qr", "LNBC250U1TEST"], self.fake.calls)

        # qrencode failure skips stderr output but still invokes blitz.display.sh
        self.fake.calls.clear()
        self.fake.qrencode_rc = 1
        stderr_buf2 = io.StringIO()
        with mock.patch.object(sys, "stderr", stderr_buf2):
            mod.show_qr(self.deps, "lnbc250u1fail")
        self.assertEqual("", stderr_buf2.getvalue())
        self.assertIn([mod.BLITZ_DISPLAY, "qr", "LNBC250U1FAIL"], self.fake.calls)


class TestBuyRenewTopupInvoiceCoverage(ModuleTestCase):
    def test_derive_server_id(self):
        self.assertEqual("eu-de", mod._derive_server_id({"server_domain": "eu-de"}))
        self.assertEqual("de2", mod._derive_server_id({"endpoint_host": "de2.tunnelsats.com"}))
        self.assertEqual("", mod._derive_server_id({}))

    def test_cmd_buy_validation_retention_eviction_qr_and_node_pay(self):
        # Direct validation branches (--months, --pay)
        for bad_kwargs in (
            {"server": "eu-de", "months": 2, "pay": "none", "yes": False, "json": True},
            {"server": "eu-de", "months": 1, "pay": "invalid", "yes": False, "json": True},
        ):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.cmd_buy(self.deps, argparse.Namespace(**bad_kwargs), mod.Result("buy"))
            self.assertEqual("E_USAGE", ctx.exception.code)

        # Not eligible -> E_NOT_ELIGIBLE
        self.fake.conf_set("runBehindTor", "off")
        doc = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")
        self.assertEqual((3, "E_NOT_ELIGIBLE"), (doc["exit_code"], doc["error"]))
        self.fake.conf_set("runBehindTor", "on")

        # Existing protected order -> E_ORDER_PENDING
        _save_pending(self.deps, order=_make_order(state="paid"), retained_orders=[])
        doc = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")
        self.assertEqual((14, "E_ORDER_PENDING"), (doc["exit_code"], doc["error"]))

        # Reuse existing order with --pay qr and json=False calls show_qr
        _save_pending(self.deps, order=_make_order(state="awaiting_payment"), retained_orders=[])
        stderr_buf = io.StringIO()
        res = mod.Result("buy")
        with mock.patch.object(sys, "stderr", stderr_buf):
            mod.cmd_buy(self.deps, argparse.Namespace(server="eu-de", months=1, pay="qr", yes=False, json=False, impl=None), res)
        self.assertTrue(res.fields["reused"])
        self.assertIn("FAKE_ANSI_QR", stderr_buf.getvalue())

        # Supersede order without valid payment_hash (skips poll) AND evict retained_orders > MAX_RETAINED_ORDERS
        # Case A: evicted item has private_key -> shred_first=True
        retained_with_key = [
            _make_order(order_id="old-%d" % i, state="superseded", priv=ALICE_PRIV)
            for i in range(mod.MAX_RETAINED_ORDERS)
        ]
        cur_no_hash = _make_order(order_id="cur-no-hash", payment_hash="bad-hash", server_id="us-east")
        _save_pending(self.deps, order=cur_no_hash, retained_orders=retained_with_key)
        inv_new = make_bolt11("lnbc250u", payment_hash=HASH_B, expiry=3600)
        self.fake.http_responses = [(200, {}, json.dumps({
            "orderId": "ord-after-evict", "paymentHash": HASH_B, "invoice": inv_new, "amountSats": 25000,
        }).encode())]
        stderr_buf2 = io.StringIO()
        res_qr = mod.Result("buy")
        with mock.patch.object(sys, "stderr", stderr_buf2):
            mod.cmd_buy(self.deps, argparse.Namespace(server="eu-de", months=1, pay="qr", yes=False, json=False, impl=None), res_qr)
        self.assertEqual("ord-after-evict", res_qr.fields["order_id"])
        self.assertEqual(mod.MAX_RETAINED_ORDERS, len(mod.load_pending(self.deps)["retained_orders"]))
        self.assertIn("FAKE_ANSI_QR", stderr_buf2.getvalue())

        # Case B: evicted item has NO private_key -> shred_first stays False
        retained_no_key = [
            _make_order(order_id="nokey-%d" % i, state="superseded", priv=None)
            for i in range(mod.MAX_RETAINED_ORDERS)
        ]
        _save_pending(self.deps, order=cur_no_hash, retained_orders=retained_no_key)
        self.fake.http_responses = [(200, {}, json.dumps({
            "orderId": "ord-evict-nokey", "paymentHash": HASH_B, "invoice": inv_new, "amountSats": 25000,
        }).encode())]
        doc = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")
        self.assertEqual(0, doc["exit_code"])

        # Case C: all MAX_RETAINED_ORDERS retained items are protected -> keep_count == 0
        retained_prot = [
            _make_order(order_id="prot-%d" % i, state="paid", priv=ALICE_PRIV)
            for i in range(mod.MAX_RETAINED_ORDERS)
        ]
        _save_pending(self.deps, order=cur_no_hash, retained_orders=retained_prot)
        self.fake.http_responses = [(200, {}, json.dumps({
            "orderId": "ord-evict-prot", "paymentHash": HASH_B, "invoice": inv_new, "amountSats": 25000,
        }).encode())]
        doc = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")
        self.assertEqual(0, doc["exit_code"])
        self.assertEqual(mod.MAX_RETAINED_ORDERS, len(mod.load_pending(self.deps)["retained_orders"]))

        # API error branches in cmd_buy
        _save_pending(self.deps, order=None, retained_orders=[])
        api_error_cases = [
            ((429, {}, b"{}"), "E_RATE_LIMITED"),
            ((502, {}, b"err"), "E_API_UNAVAILABLE"),
            ((400, {}, b"{}"), "E_API_INVALID"),
            ((200, {}, b"[]"), "E_API_INVALID"),
            ((200, {}, json.dumps({"orderId": "ord-1", "paymentHash": "bad", "invoice": inv_new, "amountSats": 25000}).encode()), "E_API_INVALID"),
            ((200, {}, json.dumps({"orderId": "bad id!", "paymentHash": HASH_B, "invoice": inv_new, "amountSats": 25000}).encode()), "E_API_INVALID"),
            ((200, {}, json.dumps({"orderId": "ord-1", "paymentHash": HASH_B, "invoice": inv_new, "amountSats": True}).encode()), "E_INVOICE_MISMATCH"),
            ((200, {}, json.dumps({"orderId": "ord-1", "paymentHash": HASH_B, "invoice": inv_new, "amountSats": 0}).encode()), "E_INVOICE_MISMATCH"),
        ]
        for resp, expected_code in api_error_cases:
            self.fake.http_responses = [resp]
            doc = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")
            self.assertEqual(expected_code, doc["error"], resp)

        # --pay node --yes invokes _pay_pending_item_via_node
        self.record()
        self.fake.lnd_listpayments = (0, {"payments": []})
        self.fake.lnd_payinvoice = (0, {
            "status": "SUCCEEDED", "payment_preimage": PREIMAGE_B, "payment_hash": HASH_B, "fee_sat": "5",
        })
        self.fake.http_responses = [
            (200, {}, json.dumps({"orderId": "ord-node", "paymentHash": HASH_B, "invoice": inv_new, "amountSats": 25000}).encode()),
            (200, {}, json.dumps({"status": "pending"}).encode()),
            (202, {}, json.dumps({"status": "processing"}).encode()),
        ]
        doc = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "node", "--yes")
        self.assertEqual(mod.EXIT_PENDING, doc["exit_code"])

    def test_cmd_renew_all_branches(self):
        # Direct usage validation
        for bad_kwargs in (
            {"months": 2, "pay": "none", "yes": False, "json": True},
            {"months": 1, "pay": "invalid", "yes": False, "json": True},
            {"months": 1, "pay": "node", "yes": False, "json": True},
        ):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.cmd_renew(self.deps, argparse.Namespace(**bad_kwargs), mod.Result("renew"))
            self.assertIn(ctx.exception.code, ("E_USAGE", "E_CONFIRMATION_REQUIRED"))

        # Invalid server_id in stored state -> E_STORED_CONFIG
        st = self.store()
        st["api"]["data"]["server_domain"] = "INVALID_HOST!"
        mod.save_state(self.deps, st)
        doc = self.run_verb("renew", "--months", "1", "--pay", "none")
        self.assertEqual((1, "E_STORED_CONFIG"), (doc["exit_code"], doc["error"]))

        # Restore valid state with date-only old_expiry
        st = self.store()
        st["api"]["data"]["expiry"] = "2026-12-01"
        mod.save_state(self.deps, st)

        # Existing protected renewal -> E_RENEWAL_PENDING
        _save_pending(self.deps, renewal=_make_renewal(state="paid"))
        doc = self.run_verb("renew", "--months", "1", "--pay", "none")
        self.assertEqual((14, "E_RENEWAL_PENDING"), (doc["exit_code"], doc["error"]))

        # Reuse with --pay qr and json=False calls show_qr
        _save_pending(self.deps, renewal=_make_renewal(state="awaiting_payment"))
        stderr_buf = io.StringIO()
        res = mod.Result("renew")
        with mock.patch.object(sys, "stderr", stderr_buf):
            mod.cmd_renew(self.deps, argparse.Namespace(months=1, pay="qr", yes=False, json=False, impl=None), res)
        self.assertTrue(res.fields["reused"])
        self.assertIn("FAKE_ANSI_QR", stderr_buf.getvalue())

        # Non-reusable renewal with invalid payment_hash skips poll -> creates new with date-only old_expiry fallback
        inv_b = make_bolt11("lnbc600u", payment_hash=HASH_B, expiry=3600)
        _save_pending(self.deps, renewal=_make_renewal(months=1, payment_hash="bad-hash"))
        self.fake.http_responses = [(200, {}, json.dumps({
            "renewalId": "ren-new", "paymentHash": HASH_B, "invoice": inv_b,
        }).encode())]
        stderr_buf2 = io.StringIO()
        res2 = mod.Result("renew")
        with mock.patch.object(sys, "stderr", stderr_buf2):
            mod.cmd_renew(self.deps, argparse.Namespace(months=3, pay="qr", yes=False, json=False, impl=None), res2)
        self.assertEqual("ren-new", res2.fields["renewal_id"])
        self.assertIn("FAKE_ANSI_QR", stderr_buf2.getvalue())

        # Non-reusable renewal with valid payment_hash whose poll returns pending proceeds to create with explicit newExpiry
        inv_a = make_bolt11("lnbc250u", payment_hash=HASH_A, expiry=3600)
        self.fake.http_responses = [
            (200, {}, json.dumps({"status": "pending"}).encode()),
            (200, {}, json.dumps({
                "renewalId": "ren-exp", "paymentHash": HASH_A, "invoice": inv_a,
                "newExpiry": "2027-06-01T00:00:00Z",
            }).encode()),
        ]
        doc = self.run_verb("renew", "--months", "1", "--pay", "none")
        self.assertEqual((0, "2027-06-01T00:00:00Z"), (doc["exit_code"], doc["new_expiry"]))

        # API error branches in cmd_renew
        _save_pending(self.deps, renewal=None)
        for resp, expected_code in (
            ((404, {}, b'{"error": "ERR_RESOURCE_NOT_FOUND"}'), "E_UNKNOWN_KEY"),
            ((403, {}, b'{"error": "ERR_MIGRATION_REQUIRED"}'), "E_MIGRATION_REQUIRED"),
            ((429, {}, b"{}"), "E_RATE_LIMITED"),
            ((500, {}, b"err"), "E_API_UNAVAILABLE"),
            ((400, {}, b"{}"), "E_API_INVALID"),
            ((200, {}, b"[]"), "E_API_INVALID"),
            ((200, {}, json.dumps({"renewalId": "ren-1", "paymentHash": "bad", "invoice": inv_a}).encode()), "E_API_INVALID"),
            ((200, {}, json.dumps({"renewalId": "bad id!", "paymentHash": HASH_A, "invoice": inv_a}).encode()), "E_API_INVALID"),
        ):
            self.fake.http_responses = [resp]
            doc = self.run_verb("renew", "--months", "1", "--pay", "none")
            self.assertEqual(expected_code, doc["error"], resp)

        # --pay node --yes invokes _pay_pending_item_via_node
        self.fake.lnd_listpayments = (0, {"payments": []})
        self.fake.lnd_payinvoice = (0, {
            "status": "SUCCEEDED", "payment_preimage": PREIMAGE_A, "payment_hash": HASH_A, "fee_sat": "3",
        })
        self.fake.http_responses = [
            (200, {}, json.dumps({"renewalId": "ren-node", "paymentHash": HASH_A, "invoice": inv_a}).encode()),
            (200, {}, json.dumps({"status": "pending"}).encode()),
            (500, {}, b"api down during settle"),
        ]
        doc = self.run_verb("renew", "--months", "1", "--pay", "node", "--yes")
        self.assertEqual(mod.EXIT_PENDING, doc["exit_code"])

    def test_cmd_topup_all_branches(self):
        # Direct usage validation
        for bad_kwargs, code in (
            ({"pay": "invalid", "yes": False, "json": True}, "E_USAGE"),
            ({"pay": "node", "yes": False, "json": True}, "E_CONFIRMATION_REQUIRED"),
        ):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.cmd_topup(self.deps, argparse.Namespace(**bad_kwargs), mod.Result("topup"))
            self.assertEqual(code, ctx.exception.code)

        # Invalid server_id in state -> E_STORED_CONFIG
        st = self.store()
        st["api"]["data"]["server_domain"] = "BAD HOST!"
        mod.save_state(self.deps, st)
        doc = self.run_verb("topup", "--pay", "none")
        self.assertEqual((1, "E_STORED_CONFIG"), (doc["exit_code"], doc["error"]))

        self.store()
        # Existing protected reset -> E_ORDER_PENDING
        _save_pending(self.deps, reset=_make_reset(state="paid"))
        doc = self.run_verb("topup", "--pay", "none")
        self.assertEqual((14, "E_ORDER_PENDING"), (doc["exit_code"], doc["error"]))

        # Reuse with invalid payment_hash skips poll and shows QR when json=False
        _save_pending(self.deps, reset=_make_reset(payment_hash="not-hex"))
        stderr_buf = io.StringIO()
        res = mod.Result("topup")
        with mock.patch.object(sys, "stderr", stderr_buf):
            mod.cmd_topup(self.deps, argparse.Namespace(pay="qr", yes=False, json=False, impl=None), res)
        self.assertTrue(res.fields["reused"])
        self.assertIn("FAKE_ANSI_QR", stderr_buf.getvalue())

        # Reuse poll returns failed -> marks needs_support + E_RESET_FAILED
        _save_pending(self.deps, reset=_make_reset(payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, json.dumps({"type": "bandwidth_reset", "status": "failed"}).encode())]
        doc = self.run_verb("topup", "--pay", "none")
        self.assertEqual((12, "E_RESET_FAILED"), (doc["exit_code"], doc["error"]))
        self.assertEqual("needs_support", mod.load_pending(self.deps)["reset"]["state"])

        # Non-reusable (different pubkey) with valid payment_hash whose poll returns paid -> E_ORDER_PENDING
        _save_pending(self.deps, reset=_make_reset(payment_hash=HASH_A, pub=BOB_PUB))
        self.fake.http_responses = [(200, {}, json.dumps({"type": "bandwidth_reset", "status": "paid"}).encode())]
        doc = self.run_verb("topup", "--pay", "none")
        self.assertEqual((14, "E_ORDER_PENDING"), (doc["exit_code"], doc["error"]))

        # Non-reusable (different pubkey) with valid payment_hash whose poll returns pending -> creates new
        inv_b = make_bolt11("lnbc100u", payment_hash=HASH_B, expiry=3600)
        _save_pending(self.deps, reset=_make_reset(payment_hash=HASH_A, pub=BOB_PUB))
        self.fake.http_responses = [
            (200, {}, json.dumps({"type": "bandwidth_reset", "status": "pending"}).encode()),
            (200, {}, json.dumps({
                "resetId": "rst-new", "paymentHash": HASH_B, "invoice": inv_b, "amountSats": 10000,
                "expiresAt": mod.iso(NOW + datetime.timedelta(seconds=1800)),
            }).encode()),
        ]
        stderr_buf2 = io.StringIO()
        res2 = mod.Result("topup")
        with mock.patch.object(sys, "stderr", stderr_buf2):
            mod.cmd_topup(self.deps, argparse.Namespace(pay="qr", yes=False, json=False, impl=None), res2)
        self.assertEqual("rst-new", res2.fields["reset_id"])
        self.assertIn("FAKE_ANSI_QR", stderr_buf2.getvalue())

        # Non-reusable (different pubkey) with invalid payment_hash skips poll -> creates new
        _save_pending(self.deps, reset=_make_reset(payment_hash="bad", pub=BOB_PUB))
        self.fake.http_responses = [(200, {}, json.dumps({
            "resetId": "rst-new2", "paymentHash": HASH_B, "invoice": inv_b, "amountSats": 10000,
        }).encode())]
        doc = self.run_verb("topup", "--pay", "none")
        self.assertEqual((0, "rst-new2"), (doc["exit_code"], doc["reset_id"]))

        # API error branches in cmd_topup
        _save_pending(self.deps, reset=None)
        for resp, expected_code in (
            ((404, {}, b'{"error": "ERR_RESOURCE_NOT_FOUND"}'), "E_UNKNOWN_KEY"),
            ((403, {}, b'{"error": "ERR_MIGRATION_REQUIRED"}'), "E_MIGRATION_REQUIRED"),
            ((429, {}, b'{"message": "max resets per month reached"}'), "E_RESET_LIMIT"),
            ((429, {}, b'{"message": "slow down"}'), "E_RATE_LIMITED"),
            ((503, {}, b"down"), "E_API_UNAVAILABLE"),
            ((400, {}, b"{}"), "E_API_INVALID"),
            ((200, {}, b"[]"), "E_API_INVALID"),
            ((200, {}, json.dumps({"resetId": "rst-1", "paymentHash": "bad", "invoice": inv_b, "amountSats": 10000}).encode()), "E_API_INVALID"),
            ((200, {}, json.dumps({"resetId": "bad id!", "paymentHash": HASH_B, "invoice": inv_b, "amountSats": 10000}).encode()), "E_API_INVALID"),
            ((200, {}, json.dumps({"resetId": "rst-1", "paymentHash": HASH_B, "invoice": inv_b, "amountSats": False}).encode()), "E_INVOICE_MISMATCH"),
            ((200, {}, json.dumps({"resetId": "rst-1", "paymentHash": HASH_B, "invoice": inv_b, "amountSats": -10}).encode()), "E_INVOICE_MISMATCH"),
        ):
            self.fake.http_responses = [resp, resp] if resp[0] == 503 else [resp]
            doc = self.run_verb("topup", "--pay", "none")
            self.assertEqual(expected_code, doc["error"], resp)

    def test_cmd_invoice_all_branches(self):
        # Invalid kind
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.cmd_invoice(self.deps, argparse.Namespace(kind="bogus", qr_png=None, json=True), mod.Result("invoice"))
        self.assertEqual("E_USAGE", ctx.exception.code)

        # Valid pending order
        _save_pending(self.deps, order=_make_order(state="awaiting_payment"))

        # Without --qr-png and json=True
        doc = self.run_verb("invoice", "--kind", "order")
        self.assertEqual((0, None), (doc["exit_code"], doc["qr_png"]))

        # Without --qr-png and json=False -> calls show_qr
        stderr_buf = io.StringIO()
        res = mod.Result("invoice")
        with mock.patch.object(sys, "stderr", stderr_buf):
            mod.cmd_invoice(self.deps, argparse.Namespace(kind="order", qr_png=None, json=False), res)
        self.assertIn("FAKE_ANSI_QR", stderr_buf.getvalue())

        # Invalid --qr-png (whitespace, NUL byte, symlink)
        symlink_path = os.path.join(self.root, "link.png")
        os.symlink("/tmp/nowhere", symlink_path)
        for bad_path in ("   ", "/tmp/bad\x00.png", symlink_path):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.cmd_invoice(self.deps, argparse.Namespace(kind="order", qr_png=bad_path, json=True), mod.Result("invoice"))
            self.assertEqual("E_USAGE", ctx.exception.code)

        # qrencode failure -> E_QR_FAILED
        self.fake.qrencode_rc = 1
        out_png = os.path.join(self.root, "fail.png")
        doc = self.run_verb("invoice", "--kind", "order", "--qr-png", out_png)
        self.assertEqual((1, "E_QR_FAILED"), (doc["exit_code"], doc["error"]))


class TestClaimAndSettleCoverage(ModuleTestCase):
    def test_can_unattended_restart_all_branches(self):
        # Inactive unit -> True regardless of autoUnlock
        self.fake.units["lnd.service"]["ActiveState"] = "inactive"
        self.assertTrue(mod.can_unattended_restart(self.deps, "lnd"))

        # Active LND: autoUnlock on vs off
        self.fake.units["lnd.service"]["ActiveState"] = "active"
        self.fake.conf_set("autoUnlock", "off")
        self.assertFalse(mod.can_unattended_restart(self.deps, "lnd"))
        self.fake.conf_set("autoUnlock", "on")
        self.assertTrue(mod.can_unattended_restart(self.deps, "lnd"))

        # Active CLN: clEncryptedHSM off vs on+clAutoUnlock off vs on+on
        self.fake.units["lightningd.service"]["ActiveState"] = "active"
        self.fake.conf_set("clEncryptedHSM", "off")
        self.assertTrue(mod.can_unattended_restart(self.deps, "cl"))
        self.fake.conf_set("clEncryptedHSM", "on")
        self.fake.conf_set("clAutoUnlock", "off")
        self.assertFalse(mod.can_unattended_restart(self.deps, "cl"))
        self.fake.conf_set("clAutoUnlock", "on")
        self.assertTrue(mod.can_unattended_restart(self.deps, "cl"))

    def test_claim_and_store_order_error_and_storage_branches(self):
        # 1. Transport error: foreground=True raises, foreground=False returns retryable
        order = _make_order(state="paid")
        pending = {"order": order, "retained_orders": []}
        self.fake.http_responses = [OSError("timeout")]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._claim_and_store_order(self.deps, pending, order, mod.Result("settle"), foreground=True)
        self.assertEqual("E_API_UNAVAILABLE", ctx.exception.code)

        self.fake.http_responses = [OSError("timeout")]
        out = mod._claim_and_store_order(self.deps, pending, order, mod.Result("settle"), foreground=False)
        self.assertEqual((False, "claiming", True), (out["done"], out["state"], out["retryable"]))

        # 2. Invalid API error (oversized response) -> marks needs_support and raises
        self.fake.http_responses = [(200, {}, b"x" * (mod.API_MAX_BYTES + 1))]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._claim_and_store_order(self.deps, pending, order, mod.Result("settle"), foreground=True)
        self.assertEqual(("E_API_INVALID", "needs_support"), (ctx.exception.code, order["state"]))

        # 3. 500/429 during claim: foreground=True raises, foreground=False returns retryable
        order["state"] = "paid"
        self.fake.http_responses = [(429, {}, b"{}")]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._claim_and_store_order(self.deps, pending, order, mod.Result("settle"), foreground=True)
        self.assertEqual("E_API_UNAVAILABLE", ctx.exception.code)

        self.fake.http_responses = [(500, {}, b"err")]
        out = mod._claim_and_store_order(self.deps, pending, order, mod.Result("settle"), foreground=False)
        self.assertEqual((False, "claiming", True), (out["done"], out["state"], out["retryable"]))

        # 4. 400 / non-dict -> marks needs_support + E_CLAIM_INVALID
        self.fake.http_responses = [(400, {}, b"{}")]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._claim_and_store_order(self.deps, pending, order, mod.Result("settle"), foreground=True)
        self.assertEqual(("E_CLAIM_INVALID", "needs_support"), (ctx.exception.code, order["state"]))

        # 5. assemble_claimed_config failure -> marks needs_support + E_CLAIM_INVALID
        order["state"] = "paid"
        bad_claim = _valid_claim_doc(pub=BOB_PUB)
        self.fake.http_responses = [(200, {}, json.dumps(bad_claim).encode())]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._claim_and_store_order(self.deps, pending, order, mod.Result("settle"), foreground=True)
        self.assertEqual(("E_CLAIM_INVALID", "needs_support"), (ctx.exception.code, order["state"]))

        # 6. Another subscription already configured -> recovered-<order_id>.conf
        # Test both is_retained=False and is_retained=True, plus api_status failure -> outcome="skipped"
        st = self.store()
        st["public_key"] = BOB_PUB
        mod.save_state(self.deps, st)

        ord_main = _make_order(order_id="ord-rec-1", state="paid")
        pending_main = {"order": ord_main, "retained_orders": []}
        self.fake.http_responses = [
            (200, {}, json.dumps(_valid_claim_doc()).encode()),
            (500, {}, b"status down"),
        ]
        out_rec1 = mod._claim_and_store_order(self.deps, pending_main, ord_main, mod.Result("settle"),
                                              foreground=True, is_retained=False)
        self.assertEqual("recovered", out_rec1["state"])
        self.assertIsNone(pending_main["order"])
        self.assertTrue(os.path.isfile(self.path(out_rec1["recovered_file"])))

        ord_ret = _make_order(order_id="ord-rec-2", state="paid")
        pending_ret = {"order": None, "retained_orders": [ord_ret]}
        self.fake.http_responses = [
            (200, {}, json.dumps(_valid_claim_doc()).encode()),
            (200, {}, fixture("api", "status_enabled.json").encode()),
        ]
        out_rec2 = mod._claim_and_store_order(self.deps, pending_ret, ord_ret, mod.Result("settle"),
                                              foreground=True, is_retained=True)
        self.assertEqual("recovered", out_rec2["state"])
        self.assertEqual([], pending_ret["retained_orders"])

        # 7. Background + cannot unattended restart -> claimed_awaiting_unlock (is_retained=False and True)
        os.remove(self.path(mod.STATE_FILE))
        self.fake.units["lnd.service"]["ActiveState"] = "active"
        self.fake.conf_set("autoUnlock", "off")

        ord_bg1 = _make_order(order_id="ord-bg-1", state="paid")
        pend_bg1 = {"order": ord_bg1, "retained_orders": []}
        self.fake.http_responses = [
            (200, {}, json.dumps(_valid_claim_doc()).encode()),
            (200, {}, fixture("api", "status_enabled.json").encode()),
        ]
        out_bg1 = mod._claim_and_store_order(self.deps, pend_bg1, ord_bg1, mod.Result("settle"),
                                             foreground=False, is_retained=False)
        self.assertEqual("claimed_awaiting_unlock", out_bg1["state"])
        self.assertIsNone(pend_bg1["order"])

        os.remove(self.path(mod.STATE_FILE))
        ord_bg2 = _make_order(order_id="ord-bg-2", state="paid")
        pend_bg2 = {"order": None, "retained_orders": [ord_bg2]}
        self.fake.http_responses = [
            (200, {}, json.dumps(_valid_claim_doc()).encode()),
            (200, {}, fixture("api", "status_enabled.json").encode()),
        ]
        out_bg2 = mod._claim_and_store_order(self.deps, pend_bg2, ord_bg2, mod.Result("settle"),
                                             foreground=False, is_retained=True)
        self.assertEqual("claimed_awaiting_unlock", out_bg2["state"])
        self.assertEqual([], pend_bg2["retained_orders"])

        # 8. Normal activation with is_retained=True and tick_timer_needed=False -> turns tick-timer off
        os.remove(self.path(mod.STATE_FILE))
        self.fake.calls.clear()
        ord_act = _make_order(order_id="ord-act-ret", state="paid")
        pend_act = {"order": None, "retained_orders": [ord_act]}
        self.fake.http_responses = [
            (200, {}, json.dumps(_valid_claim_doc()).encode()),
            (200, {}, fixture("api", "status_enabled.json").encode()),
        ]
        with mock.patch.object(mod, "tick_timer_needed", return_value=False):
            out_act = mod._claim_and_store_order(self.deps, pend_act, ord_act, mod.Result("settle"),
                                                 foreground=True, is_retained=True)
        self.assertEqual("active", out_act["state"])
        self.assertEqual([], pend_act["retained_orders"])
        self.assertIn([mod.ITS, "tick-timer", "off"], self.fake.calls)

    def test_settle_once_inner_orders_and_retained_branches(self):
        # Empty pending: foreground=True raises E_NO_PENDING, foreground=False returns none
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual("E_NO_PENDING", ctx.exception.code)
        out, impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=False)
        self.assertEqual(({"done": False, "kind": None, "state": "none"}, None), (out, impl))

        # Active order in needs_support: foreground=True raises, foreground=False returns dict
        _save_pending(self.deps, order=_make_order(state="needs_support",
                                                   extra={"error_code": "E_CLAIM_CONFLICT", "error_detail": "dup"}))
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual("E_CLAIM_CONFLICT", ctx.exception.code)
        out, impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=False)
        self.assertEqual(("needs_support", None), (out["state"], impl))

        # Active order awaiting_payment poll returns expired -> marks expired_unpaid
        _save_pending(self.deps, order=_make_order(state="awaiting_payment"))
        self.fake.http_responses = [(200, {}, b'{"status": "expired"}')]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual(("expired_unpaid", False), (out["state"], out["done"]))
        self.assertEqual("expired_unpaid", mod.load_pending(self.deps)["order"]["state"])

        # Active order already paid with notify_event + claim failure in background (foreground=False)
        events = []
        _save_pending(self.deps, order=_make_order(state="paid"))
        self.fake.http_responses = [(409, {}, b"{}")]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=False,
                                            notify_event=lambda ev, ph: events.append((ev, ph)))
        self.assertEqual([("payment_received", HASH_A)], events)
        self.assertEqual("needs_support", out["state"])

        # Retained orders: skip needs_support, poll unpaid -> stays unpaid
        _save_pending(self.deps, order=None, retained_orders=[
            _make_order(order_id="ret-sup", state="needs_support"),
            _make_order(order_id="ret-wait", state="superseded", payment_hash=HASH_A),
        ])
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual(("order", False), (out["kind"], out["done"]))

        # Retained order poll returns paid -> notify_event + claim active sets finish_impl
        events.clear()
        _save_pending(self.deps, order=None, retained_orders=[
            _make_order(order_id="ret-paid", state="superseded", payment_hash=HASH_A),
        ])
        self.fake.http_responses = [
            (200, {}, b'{"status": "paid"}'),
            (200, {}, json.dumps(_valid_claim_doc()).encode()),
            (200, {}, fixture("api", "status_enabled.json").encode()),
        ]
        out, finish_impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True,
                                                  notify_event=lambda ev, ph: events.append((ev, ph)))
        self.assertEqual(("active", "lnd", [("payment_received", HASH_A)]), (out["state"], finish_impl, events))

        # Retained order already paid (skips poll), no notify_event, claim returns 202 (state != active)
        _save_pending(self.deps, order=None, retained_orders=[
            _make_order(order_id="ret-202", state="paid", payment_hash=HASH_A),
        ])
        self.fake.http_responses = [(202, {}, b'{"status": "processing"}')]
        out, finish_impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual(("claiming", None), (out["state"], finish_impl))

        # Retained order claim ModuleError: foreground=True raises, foreground=False returns needs_support
        _save_pending(self.deps, order=None, retained_orders=[
            _make_order(order_id="ret-409", state="paid", payment_hash=HASH_A),
        ])
        self.fake.http_responses = [(409, {}, b"{}")]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual("E_CLAIM_CONFLICT", ctx.exception.code)

        _save_pending(self.deps, order=None, retained_orders=[
            _make_order(order_id="ret-409-bg", state="paid", payment_hash=HASH_A),
        ])
        self.fake.http_responses = [(409, {}, b"{}")]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=False)
        self.assertEqual(("needs_support", False), (out["state"], out["done"]))

    def test_settle_once_inner_renewal_and_reset_branches(self):
        # --- Renewal branches ---
        # 1. awaiting_payment poll returns expired -> marks expired_unpaid
        _save_pending(self.deps, renewal=_make_renewal(state="awaiting_payment"))
        self.fake.http_responses = [(200, {}, b'{"status": "expired"}')]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual(("renewal", "expired_unpaid"), (out["kind"], out["state"]))

        # 2. awaiting_payment poll returns pending -> stays awaiting_payment
        _save_pending(self.deps, renewal=_make_renewal(state="awaiting_payment"))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual(("renewal", "awaiting_payment"), (out["kind"], out["state"]))

        # 3. awaiting_payment poll returns paid with notify_event, api_status not confirmed -> done=False
        events = []
        _save_pending(self.deps, renewal=_make_renewal(state="awaiting_payment"))
        self.fake.http_responses = [
            (200, {}, b'{"status": "paid"}'),
            (500, {}, b"status error"),
        ]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True,
                                            notify_event=lambda ev, ph: events.append((ev, ph)))
        self.assertEqual((False, "paid", [("payment_received", HASH_A)]), (out["done"], out["state"], events))

        # 4. Already paid renewal with notify_event, date-only old_expiry, notify_state dict, NO stored conf file
        events.clear()
        st = self.store()
        st["notify_state"] = {"expiry_cycle": "2026-12-01", "events": {"expiry_soon": "x", "expired": "y"}}
        mod.save_state(self.deps, st)
        os.remove(self.path(mod.CONF_FILE))
        _save_pending(self.deps, renewal=_make_renewal(state="paid", old_expiry="2026-11-01"))
        status_doc = fixture_json("api", "status_enabled.json")
        status_doc["expiry"] = "2027-01-15T00:00:00Z"
        self.fake.http_responses = [(200, {}, json.dumps(status_doc).encode())]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True,
                                            notify_event=lambda ev, ph: events.append((ev, ph)))
        self.assertEqual((True, "confirmed", [("payment_received", HASH_A)]), (out["done"], out["state"], events))
        st_after = mod.load_state(self.deps)
        self.assertEqual({}, st_after["notify_state"]["events"])

        # --- Bandwidth reset branches ---
        # 5. needs_support: foreground=True raises, foreground=False returns dict
        _save_pending(self.deps, reset=_make_reset(state="needs_support",
                                                   extra={"error_code": "E_RESET_FAILED", "error_detail": "oops"}))
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual("E_RESET_FAILED", ctx.exception.code)
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=False)
        self.assertEqual(("reset", "needs_support"), (out["kind"], out["state"]))

        # 6. awaiting_payment poll returns failed: foreground=True raises, foreground=False returns dict
        _save_pending(self.deps, reset=_make_reset(state="awaiting_payment"))
        self.fake.http_responses = [(200, {}, b'{"type": "bandwidth_reset", "status": "failed"}')]
        with self.assertRaises(mod.ModuleError) as ctx:
            mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual("E_RESET_FAILED", ctx.exception.code)

        _save_pending(self.deps, reset=_make_reset(state="awaiting_payment"))
        self.fake.http_responses = [(200, {}, b'{"type": "bandwidth_reset", "status": "failed"}')]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=False)
        self.assertEqual(("reset", "needs_support"), (out["kind"], out["state"]))

        # 7. awaiting_payment poll returns expired -> marks expired_unpaid
        _save_pending(self.deps, reset=_make_reset(state="awaiting_payment"))
        self.fake.http_responses = [(200, {}, b'{"type": "bandwidth_reset", "status": "expired"}')]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual(("reset", "expired_unpaid"), (out["kind"], out["state"]))

        # 8. awaiting_payment poll returns pending -> stays awaiting_payment
        _save_pending(self.deps, reset=_make_reset(state="awaiting_payment"))
        self.fake.http_responses = [(200, {}, b'{"type": "bandwidth_reset", "status": "pending"}')]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True)
        self.assertEqual(("reset", "awaiting_payment"), (out["kind"], out["state"]))

        # 9. awaiting_payment poll returns paid with notify_event + api_status fails -> done=False
        events.clear()
        _save_pending(self.deps, reset=_make_reset(state="awaiting_payment"))
        self.fake.http_responses = [
            (200, {}, b'{"type": "bandwidth_reset", "status": "paid"}'),
            (500, {}, b"status down"),
        ]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=True,
                                            notify_event=lambda ev, ph: events.append((ev, ph)))
        self.assertEqual((False, "paid", [("payment_received", HASH_A)]), (out["done"], out["state"], events))

        # 10. already paid reset with notify_event + poll returns failed in background (foreground=False)
        events.clear()
        _save_pending(self.deps, reset=_make_reset(state="paid"))
        self.fake.http_responses = [(200, {}, b'{"type": "bandwidth_reset", "status": "failed"}')]
        out, _impl = mod._settle_once_inner(self.deps, mod.Result("settle"), foreground=False,
                                            notify_event=lambda ev, ph: events.append((ev, ph)))
        self.assertEqual(("needs_support", [("payment_received", HASH_A)]), (out["state"], events))


class TestPayNodeAndHelpersCoverage(ModuleTestCase):
    def test_parse_last_json_parse_msat_verify_preimage_and_error_mappers(self):
        # _parse_last_json
        self.assertIsNone(mod._parse_last_json(None))
        self.assertIsNone(mod._parse_last_json("   "))
        self.assertIsNone(mod._parse_last_json("no json here"))
        self.assertEqual({"a": 1}, mod._parse_last_json('{"a": 1}'))
        self.assertEqual({"b": 2}, mod._parse_last_json('prefix {broken} {"a": 1}\nnoise {"b": 2} trailing'))

        # _parse_msat
        self.assertEqual(0, mod._parse_msat(0))
        self.assertEqual(5000, mod._parse_msat(5000))
        self.assertIsNone(mod._parse_msat(True))
        self.assertIsNone(mod._parse_msat(-1))
        self.assertEqual(1234, mod._parse_msat("1234msat"))
        self.assertEqual(1234, mod._parse_msat("1234"))
        self.assertIsNone(mod._parse_msat("badmsat"))
        self.assertIsNone(mod._parse_msat(None))

        # _verify_preimage
        self.assertFalse(mod._verify_preimage(None, HASH_A))
        self.assertFalse(mod._verify_preimage("not-hex", HASH_A))
        self.assertTrue(mod._verify_preimage(PREIMAGE_A, HASH_A))
        self.assertFalse(mod._verify_preimage(PREIMAGE_B, HASH_A))

        # _map_lnd_pay_error
        self.assertEqual("E_PAY_NO_ROUTE", mod._map_lnd_pay_error({"failure_reason": "FAILURE_REASON_NO_ROUTE"}, "", ""))
        self.assertEqual("E_PAY_INSUFFICIENT_BALANCE", mod._map_lnd_pay_error({}, "", "insufficient balance"))
        self.assertEqual("E_PAY_TIMEOUT", mod._map_lnd_pay_error({"failure_reason": "FAILURE_REASON_TIMEOUT"}, "", ""))
        self.assertEqual("E_PAY_INCORRECT_DETAILS", mod._map_lnd_pay_error({"failure_reason": "FAILURE_REASON_INCORRECT_PAYMENT_DETAILS"}, "", ""))
        self.assertEqual("E_PAY_EXPIRED", mod._map_lnd_pay_error({}, "invoice expired", ""))
        self.assertEqual("E_PAY_ERROR", mod._map_lnd_pay_error(None, "something else", ""))

        # _map_cln_pay_error
        self.assertEqual("E_PAY_INSUFFICIENT_BALANCE", mod._map_cln_pay_error({"message": "Could not afford"}, "", ""))
        self.assertEqual("E_PAY_NO_ROUTE", mod._map_cln_pay_error({"code": 205}, "", ""))
        self.assertEqual("E_PAY_EXPIRED", mod._map_cln_pay_error({"code": 207}, "", ""))
        self.assertEqual("E_PAY_EXPIRED", mod._map_cln_pay_error({}, "", "invoice expired"))
        self.assertEqual("E_PAY_NO_ROUTE", mod._map_cln_pay_error({"code": 210, "message": "failed to find route"}, "", ""))
        self.assertEqual("E_PAY_TIMEOUT", mod._map_cln_pay_error({"code": 210, "message": "gave up"}, "", ""))
        self.assertEqual("E_PAY_TIMEOUT", mod._map_cln_pay_error({}, "timed out", ""))
        self.assertEqual("E_PAY_INCORRECT_DETAILS", mod._map_cln_pay_error({"message": "unknown payment details"}, "", ""))
        self.assertEqual("E_PAY_ERROR", mod._map_cln_pay_error(None, "unknown failure", ""))

    def test_cmd_pay_node_and_state_preflight_guards(self):
        # cmd_pay_node invalid --kind
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.cmd_pay_node(self.deps, argparse.Namespace(yes=True, kind="bogus", impl=None), mod.Result("pay-node"))
        self.assertEqual("E_USAGE", ctx.exception.code)

        # Auto-select fallback (second loop) picks non-awaiting_payment item -> E_ALREADY_PAID
        _save_pending(self.deps, order=None, renewal=_make_renewal(state="paid"))
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((14, "E_ALREADY_PAID"), (doc["exit_code"], doc["error"]))

        # needs_support item -> raises item error_code
        _save_pending(self.deps, order=_make_order(state="needs_support",
                                                   extra={"error_code": "E_CLAIM_CONFLICT", "error_detail": "dup"}))
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((12, "E_CLAIM_CONFLICT"), (doc["exit_code"], doc["error"]))

        # node_payment already paying/uncertain -> E_PAY_IN_FLIGHT
        _save_pending(self.deps, order=_make_order(state="awaiting_payment",
                                                   extra={"node_payment": {"state": "uncertain", "result": "uncertain"}}))
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_IN_FLIGHT"), (doc["exit_code"], doc["error"]))

        # Expired invoice -> marks expired_unpaid + E_INVOICE_EXPIRED
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", expiry_offset=-60))
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((14, "E_INVOICE_EXPIRED"), (doc["exit_code"], doc["error"]))
        self.assertEqual("expired_unpaid", mod.load_pending(self.deps)["order"]["state"])

        # No active Lightning impl -> E_PAY_NODE_LOCKED
        self.fake.conf_set("lightning", "none")
        self.fake.conf_set("lnd", "off")
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", impl=None))
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_NODE_LOCKED"), (doc["exit_code"], doc["error"]))
        self.fake.conf_set("lightning", "lnd")
        self.fake.conf_set("lnd", "on")

        # Preflight 1: API reports paid, expired, and reset failed
        _save_pending(self.deps, order=_make_order(state="awaiting_payment"))
        self.fake.http_responses = [(200, {}, b'{"status": "paid"}')]
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((14, "E_ALREADY_PAID"), (doc["exit_code"], doc["error"]))

        _save_pending(self.deps, order=_make_order(state="awaiting_payment"))
        self.fake.http_responses = [(200, {}, b'{"status": "expired"}')]
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((14, "E_INVOICE_EXPIRED"), (doc["exit_code"], doc["error"]))

        _save_pending(self.deps, reset=_make_reset(state="awaiting_payment"))
        self.fake.http_responses = [(200, {}, b'{"type": "bandwidth_reset", "status": "failed"}')]
        doc = self.run_verb("pay-node", "--kind", "reset", "--yes")
        self.assertEqual((12, "E_RESET_FAILED"), (doc["exit_code"], doc["error"]))

    def test_lnd_pay_node_preflight_and_fallback_recovery_branches(self):
        # Preflight 2: non-dict entry, wrong hash, matching FAILED ignored, matching IN_FLIGHT -> E_PAY_IN_FLIGHT
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.lnd_listpayments = (0, {"payments": [
            "bad-entry",
            {"payment_hash": HASH_B, "status": "SUCCEEDED"},
            {"payment_hash": HASH_A, "status": "FAILED"},
            {"payment_hash": HASH_A, "status": "IN_FLIGHT"},
        ]})
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_IN_FLIGHT"), (doc["exit_code"], doc["error"]))

        # Preflight 3: decodepayreq fails -> E_PAY_NODE_LOCKED
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.lnd_listpayments = (0, {"payments": []})
        self.fake.lnd_decodepayreq = (1, "", "locked")
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_NODE_LOCKED"), (doc["exit_code"], doc["error"]))

        # Preflight 3: decodepayreq non-integer num_satoshis -> E_INVOICE_MISMATCH
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.lnd_decodepayreq = (0, {"payment_hash": HASH_A, "num_satoshis": "not-an-int"})
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((12, "E_INVOICE_MISMATCH"), (doc["exit_code"], doc["error"]))
        self.fake.lnd_decodepayreq = None

        # Execute LND: bad fee_sat in pay_doc, fallback listpayments recovers FAILED with failure_reason (on dict without one)
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.lnd_listpayments = [
            (0, {"payments": []}),
            (0, {"payments": [
                {"payment_hash": HASH_A, "status": "FAILED", "failure_reason": "FAILURE_REASON_NO_ROUTE", "fee_sat": "bad"},
                {"payment_hash": HASH_B, "status": "SUCCEEDED"},
            ]}),
        ]
        self.fake.lnd_payinvoice = (1, {"status": "IN_FLIGHT", "fee_sat": "bad"}, "")
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_NO_ROUTE"), (doc["exit_code"], doc["error"]))

        # Execute LND: pay_doc is None (non-JSON output), fallback listpayments sets pay_doc from failure_reason with valid fee_sat
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.lnd_listpayments = [
            (0, {"payments": []}),
            (0, {"payments": [
                {"payment_hash": HASH_A, "status": "FAILED", "failure_reason": "FAILURE_REASON_TIMEOUT", "fee_sat": "7"},
            ]}),
        ]
        self.fake.lnd_payinvoice = (1, "non-json output", "")
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_TIMEOUT"), (doc["exit_code"], doc["error"]))

        # Execute LND: pay_doc already has failure_reason, fallback listpayments has failure_reason + fee_sat=None
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.lnd_listpayments = [
            (0, {"payments": []}),
            (0, {"payments": [
                {"payment_hash": HASH_A, "status": "FAILED", "failure_reason": "FAILURE_REASON_NO_ROUTE"},
            ]}),
        ]
        self.fake.lnd_payinvoice = (1, {"status": "FAILED", "failure_reason": "FAILURE_REASON_INSUFFICIENT_BALANCE"}, "")
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_INSUFFICIENT_BALANCE"), (doc["exit_code"], doc["error"]))

        # Execute LND: fallback listpayments returns rc != 0 and payinvoice rc == 124 -> E_PAY_TIMEOUT (uncertain)
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.lnd_listpayments = [
            (0, {"payments": []}),
            (1, "", "rpc failed"),
        ]
        self.fake.lnd_payinvoice = (124, "", "timeout")
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_TIMEOUT"), (doc["exit_code"], doc["error"]))
        self.assertEqual("uncertain", mod.load_pending(self.deps)["order"]["node_payment"]["state"])

        # Execute LND: fallback listpayments has matching hash with UNKNOWN status (ignored)
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.lnd_listpayments = [
            (0, {"payments": []}),
            (0, {"payments": [{"payment_hash": HASH_A, "status": "UNKNOWN"}]}),
        ]
        self.fake.lnd_payinvoice = (1, "non-json", "generic error")
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_ERROR"), (doc["exit_code"], doc["error"]))

        # Execute LND: fallback listpayments recovers IN_FLIGHT (no failure_reason -> branch 3045->3050)
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.lnd_listpayments = [
            (0, {"payments": []}),
            (0, {"payments": [{"payment_hash": HASH_A, "status": "IN_FLIGHT"}]}),
        ]
        self.fake.lnd_payinvoice = (1, "non-json", "still running")
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_TIMEOUT"), (doc["exit_code"], doc["error"]))
        self.assertEqual("uncertain", mod.load_pending(self.deps)["order"]["node_payment"]["state"])

        # Execute LND: SUCCEEDED with bad preimage -> E_PAY_ERROR
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.lnd_listpayments = (0, {"payments": []})
        self.fake.lnd_payinvoice = (0, {"status": "SUCCEEDED", "payment_preimage": PREIMAGE_B}, "")
        doc = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_ERROR"), (doc["exit_code"], doc["error"]))

    def test_cln_pay_node_preflight_and_fallback_recovery_branches(self):
        self.fake.conf_set("lightning", "cl")
        self.fake.conf_set("cl", "on")

        # Preflight 2: listpays fails -> E_PAY_NODE_LOCKED
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A, impl="cl"))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.cln_listpays = (1, "", "daemon down")
        doc = self.run_verb("pay-node", "--impl", "cl", "--yes")
        self.assertEqual((10, "E_PAY_NODE_LOCKED"), (doc["exit_code"], doc["error"]))

        # Preflight 2: non-dict, mismatched hash, failed ignored, complete -> E_ALREADY_PAID
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A, impl="cl"))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.cln_listpays = (0, {"pays": [
            "bad-entry",
            {"payment_hash": HASH_B, "status": "complete"},
            {"payment_hash": HASH_A, "status": "failed"},
            {"payment_hash": HASH_A, "status": "complete"},
        ]})
        doc = self.run_verb("pay-node", "--impl", "cl", "--yes")
        self.assertEqual((14, "E_ALREADY_PAID"), (doc["exit_code"], doc["error"]))

        # Preflight 2: pending -> E_PAY_IN_FLIGHT
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A, impl="cl"))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.cln_listpays = (0, {"pays": [{"payment_hash": HASH_A, "status": "pending"}]})
        doc = self.run_verb("pay-node", "--impl", "cl", "--yes")
        self.assertEqual((10, "E_PAY_IN_FLIGHT"), (doc["exit_code"], doc["error"]))

        # Preflight 3: decode fails -> E_PAY_NODE_LOCKED
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A, impl="cl"))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.cln_listpays = (0, {"pays": []})
        self.fake.cln_decode = (1, "", "rpc error")
        doc = self.run_verb("pay-node", "--impl", "cl", "--yes")
        self.assertEqual((10, "E_PAY_NODE_LOCKED"), (doc["exit_code"], doc["error"]))

        # Preflight 3: decode mismatch -> E_INVOICE_MISMATCH
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A, impl="cl"))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.cln_decode = (0, {"payment_hash": HASH_B, "amount_msat": "25000000msat"})
        doc = self.run_verb("pay-node", "--impl", "cl", "--yes")
        self.assertEqual((12, "E_INVOICE_MISMATCH"), (doc["exit_code"], doc["error"]))
        self.fake.cln_decode = None

        # Execute CLN: non-JSON output, fallback listpays fails, rc == 124 -> E_PAY_TIMEOUT
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A, impl="cl"))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.cln_listpays = [(0, {"pays": []}), (1, "", "err")]
        self.fake.cln_pay = (124, "not-json", "still-not-json")
        doc = self.run_verb("pay-node", "--impl", "cl", "--yes")
        self.assertEqual((10, "E_PAY_TIMEOUT"), (doc["exit_code"], doc["error"]))

        # Execute CLN: fallback listpays skips non-dict and failed, finds pending -> E_PAY_TIMEOUT
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A, impl="cl"))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.cln_listpays = [
            (0, {"pays": []}),
            (0, {"pays": [{"status": "pending"}, {"status": "failed"}, "not-dict"]}),
        ]
        self.fake.cln_pay = (1, "", "timeout")
        doc = self.run_verb("pay-node", "--impl", "cl", "--yes")
        self.assertEqual((10, "E_PAY_TIMEOUT"), (doc["exit_code"], doc["error"]))

        # Execute CLN: fallback listpays recovers complete with bad preimage -> E_PAY_ERROR
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A, impl="cl"))
        self.fake.http_responses = [(200, {}, b'{"status": "pending"}')]
        self.fake.cln_listpays = [
            (0, {"pays": []}),
            (0, {"pays": [{"status": "complete", "preimage": PREIMAGE_B}]}),
        ]
        self.fake.cln_pay = (1, "", "")
        doc = self.run_verb("pay-node", "--impl", "cl", "--yes")
        self.assertEqual((10, "E_PAY_ERROR"), (doc["exit_code"], doc["error"]))

        # Execute CLN: fallback listpays recovers complete with valid preimage -> settles (pending on 202)
        _save_pending(self.deps, order=_make_order(state="awaiting_payment", payment_hash=HASH_A, impl="cl"))
        self.fake.http_responses = [
            (200, {}, b'{"status": "pending"}'),
            (202, {}, b'{"status": "processing"}'),
        ]
        self.fake.cln_listpays = [
            (0, {"pays": []}),
            (0, {"pays": [{"status": "complete", "preimage": PREIMAGE_A}]}),
        ]
        self.fake.cln_pay = (1, "", "")
        doc = self.run_verb("pay-node", "--impl", "cl", "--yes")
        self.assertEqual(mod.EXIT_PENDING, doc["exit_code"])


class TestLegacyConfigCoverage(ModuleTestCase):
    def test_read_legacy_config_errors_and_success(self):
        # Missing or invalid path -> E_CONFIG_NOT_FOUND
        for tool in ({}, {"config": {}}, {"config": {"path": "/tmp/evil.conf"}}):
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.read_legacy_config(self.deps, tool)
            self.assertEqual("E_CONFIG_NOT_FOUND", ctx.exception.code)

        # Valid path but file missing on disk -> OSError -> E_CONFIG_NOT_FOUND
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.read_legacy_config(self.deps, {"config": {"path": "/etc/wireguard/tunnelsatsv2.conf"}})
        self.assertEqual("E_CONFIG_NOT_FOUND", ctx.exception.code)

        # Existing valid legacy config -> parsed successfully
        self.write("etc/wireguard/tunnelsatsv2.conf", fixture("import", "website.conf"))
        cfg = mod.read_legacy_config(self.deps, {"config": {"path": "/etc/wireguard/tunnelsatsv2.conf"}})
        self.assertEqual(ALICE_PUB, cfg["public_key"])


if __name__ == "__main__":
    unittest.main()
