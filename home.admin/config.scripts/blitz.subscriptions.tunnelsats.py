#!/usr/bin/python3
"""TunnelSats VPN subscription for RaspiBlitz (SSH menu > SUBSCRIBE > TunnelSats).

TunnelSats routes the node's Lightning clearnet traffic through a WireGuard VPN; Tor stays on for
onion peers. The dataplane is TunnelSats' own tunnelsats.sh in managed mode, driven through
internet.tunnelsats.sh (pinned and verified tool, start guard, restore block). This module keeps
the subscription (a WireGuard config rebuilt from validated fields, plus state) and orchestrates
import, adoption, checks, repair and removal.

Verbs (all with --json; every verb except --help needs root, the state is root 0600):
  menu | servers | buy --server ID --months N --pay node|qr|copy|none [--yes] [--impl lnd|cl]
  renew --months N --pay node|qr|copy|none [--yes] | topup --pay node|qr|copy|none [--yes]
  invoice [--kind order|renewal|reset] [--qr-png PATH] | pending | settle [--wait S]
  pay-node [--kind order|renewal|reset] [--impl lnd|cl] --yes | export --out FILE
  import --file FILE [--impl lnd|cl] [--dry-run] [--yes] | adopt [--yes] [--upgrade]
  status [--refresh|--cached] [--raw-api] | check | detect | repair [--impl lnd|cl] --yes
  uninstall --yes [--purge] | subscriptions-list | tick [--now ISO --no-persist] [--status-file FILE --no-persist]

Key custody: the private key exists only in tunnelsats.conf (root 0600) and in the config
tunnelsats.sh derives from it. It never appears in argv, environment variables, logs, JSON output,
raspiblitz.conf or notifications; the public key is derived in-process (RFC 7748 X25519).
"""

import argparse
import base64
import datetime
import fcntl
import hashlib
import http.client
import ipaddress
import json
import math
import os
import pwd
import re
import secrets
import signal
import ssl
import subprocess
import sys
import time
import urllib.parse

MODULE_VERSION = "0.2.0"
CONTRACT = 1

# Exit codes (module column of the contract)
EXIT_OK = 0
EXIT_OPERATIONAL = 1
EXIT_USAGE = 2
EXIT_NOT_CONFIGURED = 3
EXIT_UNSAFE = 4
EXIT_DEGRADED = 5
EXIT_PAY_FAILED = 10
EXIT_PENDING = 11
EXIT_INVALID_API = 12
EXIT_API_UNAVAILABLE = 13
EXIT_REFUSED = 14

# Production paths (relative to Deps.root in tests)
APPDATA = "/mnt/hdd/app-data"
STATE_DIR = APPDATA + "/tunnelsats"
CONF_FILE = STATE_DIR + "/tunnelsats.conf"
STATE_FILE = STATE_DIR + "/state.json"
PENDING_FILE = STATE_DIR + "/pending.json"
LAST_RESTORE_FILE = STATE_DIR + "/last-restore.json"
RB_CONF = APPDATA + "/raspiblitz.conf"
CUSTOM_INSTALLS = APPDATA + "/custom-installs.sh"
RUN_DIR = "/run/tunnelsats"
# uninstall --managed of the pinned tool (and a failed install's rollback) removes RUN_DIR: the lock
# lives next to it, in a root 0700 directory of its own
LOCK_DIR = "/run/tunnelsats-rb"
LOCK_FILE = LOCK_DIR + "/module.lock"
SERVERS_CACHE_FILE = LOCK_DIR + "/servers-cache.json"
STOPPED_UNITS = RUN_DIR + "/stopped-units"
ITS = "/home/admin/config.scripts/internet.tunnelsats.sh"
BLITZ_CONF = "/home/admin/config.scripts/blitz.conf.sh"
BLITZ_DISPLAY = "/home/admin/config.scripts/blitz.display.sh"
NOTIFY = "/home/admin/config.scripts/blitz.notify.sh"
LND_ASSET = "/home/admin/assets/lnd.service"
CL_INSTALL_SERVICE = "/home/admin/config.scripts/cl.install-service.sh"
LND_UNLOCK = "/home/admin/config.scripts/lnd.unlock.sh"
CL_HSMTOOL = "/home/admin/config.scripts/cl.hsmtool.sh"
LNCLI = ["sudo", "-u", "bitcoin", "/usr/local/bin/lncli", "-n=mainnet", "--rpcserver", "localhost:10009"]
CLNCLI = ["sudo", "-u", "bitcoin", "/usr/local/bin/lightning-cli", "--conf=/home/bitcoin/.lightning/config"]
UNIT_DIR = "/etc/systemd/system"
LEGACY_CONF_RE = re.compile(r"/etc/wireguard/[A-Za-z0-9_.-]{1,64}\.conf")

API_BASE_URL = "https://tunnelsats.com/api/public/v1"
API_SERVERS_URL = API_BASE_URL + "/servers"
API_SUBSCRIPTION_URL = API_BASE_URL + "/subscription"
API_CREATE_URL = API_BASE_URL + "/subscription/create"
API_RENEW_URL = API_BASE_URL + "/subscription/renew"
API_RESET_URL = API_BASE_URL + "/subscription/bandwidth-reset"
API_CLAIM_URL = API_BASE_URL + "/subscription/claim"
API_STATUS_URL = API_BASE_URL + "/subscription/status"
API_CONNECT_TIMEOUT = 15
API_READ_TIMEOUT = 30
API_MAX_BYTES = 65536
API_CACHE_SECONDS = 6 * 3600
SERVERS_CACHE_SECONDS = 60
PENDING_TTL_SECONDS = 24 * 3600
INVOICE_DEFAULT_TTL_SECONDS = 3600
MAX_RETAINED_ORDERS = 5
MAX_RENEW_SATS = 200000
DURATIONS = (1, 3, 6, 12)
PAY_MODES = ("node", "qr", "copy", "none")

OFFLINE_SERVERS = (
    {"id": "us-east", "country": "USA", "city": "Ashburn", "flag": "🇺🇸", "status": "online"},
    {"id": "us-west", "country": "USA", "city": "Hillsboro", "flag": "🇺🇸", "status": "online"},
    {"id": "eu-de", "country": "Germany", "city": "Nuremberg", "flag": "🇩🇪", "status": "online"},
    {"id": "asia-sg", "country": "Singapore", "city": "Singapore", "flag": "🇸🇬", "status": "online"},
    {"id": "sa-br", "country": "Brazil", "city": "Sao Paulo", "flag": "🇧🇷", "status": "online"},
    {"id": "oc-au", "country": "Australia", "city": "Sydney", "flag": "🇦🇺", "status": "online"},
    {"id": "eu-ch", "country": "Switzerland", "city": "Geneva", "flag": "🇨🇭", "status": "online"},
)
SERVER_STATUSES = ("online", "degraded", "offline", "active", "full", "maintenance", "disabled")
ONLINE_SERVER_STATUSES = ("online", "active")
SELECTABLE_SERVER_STATUSES = ("online", "degraded", "active")

# Timeouts (s) for internet.tunnelsats.sh, each above the script's own worst case, so the script
# ends by itself and cleans up; run_command stops the whole process group only as a last resort.
ITS_TIMEOUT = {
    "fetch": 300,            # its_fetch_online: TS_RB_FETCH_BUDGET (240) for all network steps
    "detect": 420,           # a fetch when no copy is stored, then the tool's detect (120, +10 kill)
    "install": 960,          # the tool's install --managed (900, +10 kill)
    "adopt": 960,            # the tool's adopt --managed (900, +10 kill)
    "uninstall": 660,        # the tool's uninstall --managed (600, +10 kill)
    "verify": 150,           # the tool's verify with probes (120, +10 kill)
    "verify_no_probe": 60,   # the tool's verify --no-probe (35, +10 kill)
    "status": 60,            # one verify --no-probe (TS_RB_VERIFY_TIMEOUT 30, +5 kill)
    "guard_dry_run": 120,    # one verify (30, +5 kill), no handshake wait in --dry-run
}

IMPLS = ("lnd", "cl")
UNITS = {"lnd": "lnd.service", "cl": "lightningd.service"}
IMPL_OF_UNIT = {unit: impl for impl, unit in UNITS.items()}
OTHER_IMPL = {"lnd": "cl", "cl": "lnd"}
BASES = {"lnd": "lnd", "cl": "lightningd"}
VARS = {"lnd": "TUNNELSATS_LND_ARGS", "cl": "TUNNELSATS_CLN_ARGS"}
RESTARTABLE = ("emergency_block", "verify_timeout", "verify_unsafe", "verify_failed", "verify_invalid",
               "verify_inconsistent", "not_installed", "tool_missing", "unit_mismatch", "announce_unconfirmed")
RESTART_MESSAGE = ("TunnelSats: the tunnel is ready again. Restart Lightning to resume clearnet connections "
                   "(SSH menu > SUBSCRIBE > TunnelSats).")
# announce_cleanup of the tool's uninstall --managed (contract 1, additive since tunnelsats PR 230): its
# own step that takes the former VPN address out of LND's node announcement
TOOL_ANNOUNCE_RESULTS = ("removed", "none", "lnd_not_ready", "failed", "skipped")
# unit file states in which no boot starts a unit (read back after systemctl disable)
BOOT_OFF = ("disabled", "masked", "masked-runtime")
# an IPv4 address with a port, as the tool's announcement warnings name them
ADDRESS_RE = re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}:\d{1,5}\b")
# REPAIR and IMPORT check the node only once the Lightning unit the tool or the module (re)started
# has left "activating" (LND until it is ready, Type=notify; verify reports such a start as
# degraded): at most LN_START_WAIT seconds, read every LN_START_STEP seconds
LN_START_WAIT = 90
LN_START_STEP = 3
# When the final check of IMPORT, ADOPT --upgrade or REPAIR finds wg_handshake ("no handshake yet")
# as the only failing check, it waits briefly for the handshake the probe or Lightning traffic
# initiated: at most HANDSHAKE_WAIT seconds, read every HANDSHAKE_STEP seconds
HANDSHAKE_WAIT = 15
HANDSHAKE_STEP = 3
# the drop-in with which install --managed puts the managed unit into the slice, as detect reports it
# (artifact managed_ln_dropin)
DROPIN_RE = re.compile(r"/etc/systemd/system/([A-Za-z0-9_.@-]+\.service)\.d/tunnelsats-managed\.conf")

# Validators, always applied with fullmatch: with match, a "$" would also accept a final newline
KEY_RE = re.compile(r"[A-Za-z0-9+/]{42}[AEIMQUYcgkosw048]=")
HOST_RE = re.compile(r"([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+tunnelsats\.com")
SERVER_ID_RE = re.compile(r"[a-z0-9-]{2,32}")
HEX64_RE = re.compile(r"[0-9a-f]{64}")
ORDER_ID_RE = re.compile(r"[A-Za-z0-9_.-]{1,64}")
BOLT11_AMOUNT_RE = re.compile(r"lnbc(?:(\d+)([munp])?)?1[0-9a-z]{7,}", re.IGNORECASE)
_BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"
_BECH32_CHARSET_MAP = {c: i for i, c in enumerate(_BECH32_CHARSET)}
ISO_RE = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?(Z|[+-]\d{2}:\d{2})")
SECTION_RE = re.compile(r"\[([A-Za-z]+)\]")
KV_RE = re.compile(r"([A-Za-z][A-Za-z0-9]*)\s*=\s*(.*)")
PORT_COMMENT_RE = re.compile(r"#\s*(?:Port Forwarding\s*:|VPNPort\s*=)\s*(\S+)\s*", re.IGNORECASE)
VALID_UNTIL_RE = re.compile(r"#\s*Valid Until\s*:\s*(\S+)\s*", re.IGNORECASE)
MYPUBKEY_RE = re.compile(r"#\s*myPubKey\s*:\s*(\S+)\s*", re.IGNORECASE)
DROPPED_KEYS = ("dns", "postup", "postdown", "preup", "predown", "table", "fwmark", "saveconfig", "listenport")
MAX_CONFIG_BYTES = 16384

LND_FLAG_RE = re.compile(r"--(tor\.skip-proxy-for-clearnet-targets(=.*)?|externalhosts=.*)")
CLN_FLAG_RE = re.compile(r"--(bind-addr=0\.0\.0\.0:9735|always-use-proxy=false|announce-addr-discovered=false|announce-addr=(?!.*\.onion).*)")


class ModuleError(Exception):
    """An error with a stable code; the message never holds key material or config values."""

    def __init__(self, code, cls, message, exit_code):
        super().__init__(message)
        self.code = code
        self.cls = cls
        self.message = message
        self.exit_code = exit_code


# ------------------------------------------------------------------------------------------
# Effects (injectable)
# ------------------------------------------------------------------------------------------

def stop_group(proc, grace=10):
    """Stops the process group of proc (started with start_new_session): SIGTERM, so the scripts'
    EXIT and TERM traps can remove their temp files, SIGKILL after grace seconds. Reaps proc."""
    for sig, wait in ((signal.SIGTERM, grace), (signal.SIGKILL, 5)):
        try:
            os.killpg(proc.pid, sig)
        except ProcessLookupError:
            pass
        try:
            proc.communicate(timeout=wait)
            return
        except subprocess.TimeoutExpired:
            continue
    proc.kill()
    proc.communicate()


def run_command(argv, timeout=60, interactive=False):
    """Runs argv (a list, never through a shell). Returns (rc, stdout, stderr); a timeout is rc 124.
    The command runs in its own process group, so a timeout stops it with all its children."""
    if interactive:
        return subprocess.run(argv, timeout=timeout, check=False).returncode, "", ""
    try:
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True)
    except OSError as exc:
        return 127, "", str(exc)
    try:
        out, err = proc.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        stop_group(proc)
        return 124, "", "timeout"
    except BaseException:
        stop_group(proc)
        raise
    return proc.returncode, out.decode("utf-8", "replace"), err.decode("utf-8", "replace")


def http_post_json(url, payload=None):
    """GET (payload is None) or POST JSON over TLS (certificate verification on, no proxy).
    Returns (status, headers, body). 15 s to connect, 30 s per read, at most API_MAX_BYTES of body.
    Raises OSError on failure."""
    parts = urllib.parse.urlsplit(url)
    method = "GET" if payload is None else "POST"
    body = None if payload is None else json.dumps(payload).encode()
    req_headers = {"Accept": "application/json", "User-Agent": "TunnelSats-RaspiBlitz/" + MODULE_VERSION}
    if body is not None:
        req_headers["Content-Type"] = "application/json"
    conn = http.client.HTTPSConnection(parts.hostname, parts.port or 443, timeout=API_CONNECT_TIMEOUT,
                                       context=ssl.create_default_context())
    try:
        conn.connect()
        conn.sock.settimeout(API_READ_TIMEOUT)
        conn.request(method, parts.path, body=body, headers=req_headers)
        resp = conn.getresponse()
        raw = resp.read(API_MAX_BYTES + 1)
        headers = {k.lower(): v for k, v in resp.getheaders()}
        return resp.status, headers, raw
    except (http.client.HTTPException, ssl.SSLError) as exc:
        raise OSError(str(exc)) from None
    finally:
        conn.close()


class Deps:
    """External effects: filesystem root, HTTP, commands, clock, sleep, privilege."""

    def __init__(self, root="/", http=None, run=None, clock=None, sleep=None, is_root=None, log=None):
        self.root = root
        self.http = http or http_post_json
        self.run = run or run_command
        self.clock = clock or (lambda: datetime.datetime.now(datetime.timezone.utc))
        self.sleep = sleep or time.sleep
        self.is_root = is_root or (lambda: os.geteuid() == 0)
        self.log = log or (lambda msg: print(msg, file=sys.stderr))

    def path(self, p):
        return os.path.join(self.root, p.lstrip("/"))


# ------------------------------------------------------------------------------------------
# Small helpers
# ------------------------------------------------------------------------------------------

def now_iso(deps):
    return deps.clock().strftime("%Y-%m-%dT%H:%M:%SZ")


def parse_iso(value):
    """Returns an aware datetime for an ISO-8601 string, or None."""
    if not isinstance(value, str) or not ISO_RE.fullmatch(value):
        return None
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    frac = re.search(r"\.(\d+)", text)
    if frac and len(frac.group(1)) > 6:
        text = text.replace(frac.group(0), "." + frac.group(1)[:6])
    try:
        return datetime.datetime.fromisoformat(text)
    except ValueError:
        return None


def valid_host(host):
    return isinstance(host, str) and len(host) <= 253 and HOST_RE.fullmatch(host) is not None


def valid_port(port):
    return isinstance(port, int) and not isinstance(port, bool) and 1 <= port <= 65535


def is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and value >= 0


def is_count(value):
    return isinstance(value, int) and not isinstance(value, bool) and value >= 0


def parse_one_json(text):
    """The single JSON object in text, or None."""
    try:
        decoder = json.JSONDecoder()
        doc, end = decoder.raw_decode(text.strip())
        if text.strip()[end:].strip() or not isinstance(doc, dict):
            return None
        return doc
    except (ValueError, AttributeError):
        return None


def read_rb_conf(deps):
    """raspiblitz.conf as a dict (KEY=v, KEY='v', KEY="v"; last wins); parsed, never sourced."""
    values = {}
    try:
        with open(deps.path(RB_CONF), encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return values
    for line in lines:
        match = re.fullmatch(r"\s*([A-Za-z_][A-Za-z0-9_]*)=(.*)", line.rstrip("\r"))
        if not match:
            continue
        value = match.group(2)
        if value.startswith("'"):
            value = value[1:].split("'", 1)[0]
        elif value.startswith('"'):
            value = value[1:].split('"', 1)[0]
        else:
            value = value.split()[0] if value.split() else ""
        values[match.group(1)] = value
    return values


def ensure_dir(path, mode):
    if not os.path.isdir(path):
        os.makedirs(path, mode=mode, exist_ok=True)
    os.chmod(path, mode)


def write_private(path, data, mode=0o600):
    """Writes bytes atomically: O_CREAT|O_EXCL temp file (mode 0600), fsync, rename, fsync of the
    directory, read back."""
    directory = os.path.dirname(path)
    fd = None
    tmp = None
    for _ in range(20):
        tmp = os.path.join(directory, ".%s.%s" % (os.path.basename(path), secrets.token_hex(6)))
        try:
            fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
            break
        except FileExistsError:
            continue
    if fd is None:
        raise ModuleError("E_WRITE_FAILED", "operational", "no temp file in %s" % directory, EXIT_OPERATIONAL)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
        dir_fd = os.open(directory, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
    except OSError:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise ModuleError("E_WRITE_FAILED", "operational", "%s could not be written" % path, EXIT_OPERATIONAL) from None
    with open(path, "rb") as handle:
        if handle.read() != data:
            raise ModuleError("E_WRITE_FAILED", "operational", "%s did not read back" % path, EXIT_OPERATIONAL)


def shred(path):
    """Overwrites a file with random bytes before deleting it (best effort on journaling media)."""
    try:
        size = os.path.getsize(path)
        with open(path, "r+b") as handle:
            handle.write(secrets.token_bytes(max(size, 1)))
            handle.flush()
            os.fsync(handle.fileno())
        os.unlink(path)
    except FileNotFoundError:
        pass


# ------------------------------------------------------------------------------------------
# X25519 (RFC 7748): the public key, derived in-process
# ------------------------------------------------------------------------------------------

_P = 2 ** 255 - 19
_A24 = 121665


def x25519(scalar, u_coord):
    """X25519(k, u) of RFC 7748 section 5 on 32-byte strings."""
    k = bytearray(scalar)
    k[0] &= 248
    k[31] &= 127
    k[31] |= 64
    k_int = int.from_bytes(k, "little")
    u = bytearray(u_coord)
    u[31] &= 127
    x_1 = int.from_bytes(u, "little") % _P
    x_2, z_2, x_3, z_3, swap = 1, 0, x_1, 1, 0
    for t in reversed(range(255)):
        k_t = (k_int >> t) & 1
        swap ^= k_t
        if swap:
            x_2, x_3, z_2, z_3 = x_3, x_2, z_3, z_2
        swap = k_t
        a = (x_2 + z_2) % _P
        aa = a * a % _P
        b = (x_2 - z_2) % _P
        bb = b * b % _P
        e = (aa - bb) % _P
        c = (x_3 + z_3) % _P
        d = (x_3 - z_3) % _P
        da = d * a % _P
        cb = c * b % _P
        x_3 = (da + cb) * (da + cb) % _P
        z_3 = x_1 * (da - cb) * (da - cb) % _P
        x_2 = aa * bb % _P
        z_2 = e * (aa + _A24 * e) % _P
    if swap:
        x_2, x_3, z_2, z_3 = x_3, x_2, z_3, z_2
    return (x_2 * pow(z_2, _P - 2, _P) % _P).to_bytes(32, "little")


def public_key_of(private_b64):
    """The WireGuard public key (base64) of a base64 private key."""
    raw = base64.b64decode(private_b64, validate=True)
    if len(raw) != 32:
        raise ModuleError("E_CONFIG_INVALID", "usage", "PrivateKey is not a 32-byte key", EXIT_USAGE)
    return base64.b64encode(x25519(raw, (9).to_bytes(32, "little"))).decode()


def generate_wg_keypair():
    """Generates an RFC 7748 X25519 WireGuard keypair in-process. Returns (private_b64, public_b64)."""
    raw = bytearray(secrets.token_bytes(32))
    raw[0] &= 248
    raw[31] &= 127
    raw[31] |= 64
    private_b64 = base64.b64encode(bytes(raw)).decode()
    return private_b64, public_key_of(private_b64)


# ------------------------------------------------------------------------------------------
# BOLT11 Bech32 decoder and amount/payment-hash verifier
# ------------------------------------------------------------------------------------------

def _bech32_polymod(values):
    gen = (0x3B6A57B2, 0x26508E6D, 0x1EA119FA, 0x3D4233DD, 0x2A1462B3)
    chk = 1
    for v in values:
        b = chk >> 25
        chk = ((chk & 0x1FFFFFF) << 5) ^ v
        for i in range(5):
            if (b >> i) & 1:
                chk ^= gen[i]
    return chk


def _bech32_hrp_expand(hrp):
    return [ord(x) >> 5 for x in hrp] + [0] + [ord(x) & 31 for x in hrp]


def _bech32_verify_checksum(hrp, data):
    return _bech32_polymod(_bech32_hrp_expand(hrp) + data) == 1


def bolt11_amount_sats(invoice):
    """Amount in whole satoshis from a mainnet BOLT11 HRP, or None when omitted, sub-satoshi, or invalid."""
    if not isinstance(invoice, str):
        return None
    match = BOLT11_AMOUNT_RE.fullmatch(invoice.strip())
    if not match or not match.group(1):
        return None
    value = int(match.group(1))
    unit = (match.group(2) or "").lower()
    msat_per_unit = {"": 100_000_000_000, "m": 100_000_000, "u": 100_000, "n": 100, "p": 0.1}.get(unit)
    if msat_per_unit is None:
        return None
    msats = round(value * msat_per_unit)
    if msats <= 0 or msats % 1000 != 0:
        return None
    return msats // 1000


def decode_bolt11(bolt11):
    """Decodes and validates a mainnet BOLT11 invoice in pure Python. Returns a dict with
    amount_sats, payment_hash, timestamp, and expiry_seconds, or raises ModuleError(E_INVOICE_MISMATCH)."""
    if not isinstance(bolt11, str) or not bolt11.strip() or len(bolt11.strip()) > 4000:
        raise ModuleError("E_INVOICE_MISMATCH", "invalid_response", "invoice is missing or invalid", EXIT_INVALID_API)
    raw_s = bolt11.strip()
    if raw_s != raw_s.lower() and raw_s != raw_s.upper():
        raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                          "invoice mixes upper and lower case", EXIT_INVALID_API)
    inv = raw_s.lower()
    amount_sats = bolt11_amount_sats(inv)
    if amount_sats is None or amount_sats <= 0:
        raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                          "invoice does not carry a positive whole-satoshi amount", EXIT_INVALID_API)
    sep = inv.rfind("1")
    if sep < 4:
        raise ModuleError("E_INVOICE_MISMATCH", "invalid_response", "invoice has no Bech32 separator", EXIT_INVALID_API)
    hrp = inv[:sep]
    data_part = inv[sep + 1:]
    if len(data_part) < 117:
        raise ModuleError("E_INVOICE_MISMATCH", "invalid_response", "invoice data section is too short", EXIT_INVALID_API)
    try:
        words = [_BECH32_CHARSET_MAP[c] for c in data_part]
    except KeyError:
        raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                          "invoice contains invalid Bech32 characters", EXIT_INVALID_API) from None
    if not _bech32_verify_checksum(hrp, words):
        raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                          "invoice Bech32 checksum failed", EXIT_INVALID_API)
    timestamp = 0
    for w in words[:7]:
        timestamp = (timestamp << 5) | w
    tagged = words[7:len(words) - 110]
    idx = 0
    embedded_hash = None
    expiry_seconds = INVOICE_DEFAULT_TTL_SECONDS
    seen_expiry = False
    while idx + 3 <= len(tagged):
        tag_type = tagged[idx]
        data_len = (tagged[idx + 1] << 5) | tagged[idx + 2]
        idx += 3
        if idx + data_len > len(tagged):
            raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                              "invoice has a truncated tagged field", EXIT_INVALID_API)
        field_words = tagged[idx:idx + data_len]
        idx += data_len
        if tag_type == 1 and data_len == 52 and embedded_hash is None:
            acc = 0
            for w in field_words:
                acc = (acc << 5) | w
            embedded_hash = (acc >> 4).to_bytes(32, "big").hex()
        elif tag_type == 6 and not seen_expiry and data_len > 0:
            seen_expiry = True
            exp_val = 0
            for w in field_words:
                exp_val = (exp_val << 5) | w
            if exp_val > 0:
                expiry_seconds = exp_val
    if embedded_hash is None:
        raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                          "invoice has no payment hash ('p' tag)", EXIT_INVALID_API)
    return {"amount_sats": amount_sats, "payment_hash": embedded_hash,
            "timestamp": timestamp, "expiry_seconds": expiry_seconds}


def verify_bolt11_invoice(bolt11, expected_payment_hash, expected_sats=None, max_sats=MAX_RENEW_SATS):
    """Verifies a BOLT11 invoice against expected_payment_hash and either expected_sats (exact match)
    or max_sats (ceiling when the API omits amountSats). Returns the decoded dict."""
    if not isinstance(expected_payment_hash, str) or not HEX64_RE.fullmatch(expected_payment_hash.lower()):
        raise ModuleError("E_API_INVALID", "invalid_response", "paymentHash is not 64 hex characters", EXIT_INVALID_API)
    decoded = decode_bolt11(bolt11)
    if decoded["payment_hash"] != expected_payment_hash.lower():
        raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                          "invoice payment hash does not match paymentHash", EXIT_INVALID_API)
    if expected_sats is not None:
        if isinstance(expected_sats, bool) or not isinstance(expected_sats, int) or expected_sats <= 0:
            raise ModuleError("E_API_INVALID", "invalid_response", "amountSats is not a positive integer",
                              EXIT_INVALID_API)
        if decoded["amount_sats"] != expected_sats:
            raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                              "invoice amount (%d sats) does not match amountSats (%d sats)"
                              % (decoded["amount_sats"], expected_sats), EXIT_INVALID_API)
    elif decoded["amount_sats"] > max_sats:
        raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                          "invoice amount (%d sats) exceeds ceiling (%d sats)"
                          % (decoded["amount_sats"], max_sats), EXIT_INVALID_API)
    return decoded


# ------------------------------------------------------------------------------------------
# WireGuard config: parser, validator, canonical rebuild (the claim trust boundary for files)
# ------------------------------------------------------------------------------------------

def _invalid(code, message):
    return ModuleError(code, "usage", message, EXIT_USAGE)


def parse_wg_config(data):
    """Validates a website or exported WireGuard config (bytes) and returns a dict of the validated
    fields plus warnings. Errors name keys and line numbers, never values."""
    if not isinstance(data, (bytes, bytearray)) or len(data) > MAX_CONFIG_BYTES:
        raise _invalid("E_CONFIG_INVALID", "the config is larger than 16 KiB")
    if b"\x00" in data:
        raise _invalid("E_CONFIG_INVALID", "the config holds NUL bytes")
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError:
        raise _invalid("E_CONFIG_INVALID", "the config is not UTF-8") from None
    warnings = []
    sections = {}
    current = None
    port = None
    valid_until = None
    mypubkey = None
    for number, raw in enumerate(text.split("\n"), start=1):
        line = raw[:-1] if raw.endswith("\r") else raw
        if any(ord(ch) < 32 and ch != "\t" for ch in line) or "\x7f" in line:
            raise _invalid("E_CONFIG_INVALID", "line %d holds a control character" % number)
        line = line.strip()
        if not line:
            continue
        if line.startswith("#"):
            for regex, label in ((PORT_COMMENT_RE, "port"), (VALID_UNTIL_RE, "valid"), (MYPUBKEY_RE, "pub")):
                match = regex.fullmatch(line)
                if not match:
                    continue
                value = match.group(1)
                if label == "port":
                    if port is not None:
                        raise _invalid("E_CONFIG_INVALID", "line %d: a second port comment" % number)
                    if not re.fullmatch(r"[1-9][0-9]{0,4}", value) or int(value) > 65535:
                        raise _invalid("E_CONFIG_NO_PORT", "line %d: the port comment is not a port number" % number)
                    port = int(value)
                elif label == "valid":
                    if valid_until is not None:
                        raise _invalid("E_CONFIG_INVALID", "line %d: a second Valid Until comment" % number)
                    if parse_iso(value) is None:
                        warnings.append("line %d: Valid Until is not an ISO-8601 time and was dropped" % number)
                    else:
                        valid_until = value
                else:
                    if mypubkey is not None:
                        raise _invalid("E_CONFIG_INVALID", "line %d: a second myPubKey comment" % number)
                    mypubkey = value
                break
            continue
        section = SECTION_RE.fullmatch(line)
        if section:
            name = section.group(1).lower()
            if name not in ("interface", "peer"):
                raise _invalid("E_CONFIG_INVALID", "line %d: unknown section" % number)
            if name in sections:
                raise _invalid("E_CONFIG_INVALID", "line %d: a second [%s] section" % (number, section.group(1)))
            sections[name] = {}
            current = name
            continue
        if "#" in line:
            line = line.split("#", 1)[0].rstrip()
        match = KV_RE.fullmatch(line)
        if not match or current is None:
            raise _invalid("E_CONFIG_INVALID", "line %d is not a key = value line inside a section" % number)
        key = match.group(1).lower()
        if key in sections[current]:
            raise _invalid("E_CONFIG_INVALID", "line %d: duplicate key %s" % (number, match.group(1)))
        sections[current][key] = (number, match.group(2).strip(), match.group(1))
    if "interface" not in sections or "peer" not in sections:
        raise _invalid("E_CONFIG_INVALID", "the config needs exactly one [Interface] and one [Peer] section")
    if port is None:
        raise _invalid("E_CONFIG_NO_PORT", "the config has no '# Port Forwarding:' comment (the VPN port)")
    known = {"interface": ("privatekey", "address", "mtu"),
             "peer": ("publickey", "presharedkey", "endpoint", "allowedips", "persistentkeepalive")}
    for name, entries in sections.items():
        for key, (number, _value, label) in sorted(entries.items(), key=lambda item: item[1][0]):
            if key not in known[name]:
                reason = "is not used by managed mode" if key in DROPPED_KEYS else "is unknown"
                warnings.append("line %d: %s %s and was dropped" % (number, label, reason))
    iface, peer = sections["interface"], sections["peer"]

    def required(entries, key, label):
        if key not in entries:
            raise _invalid("E_CONFIG_INVALID", "%s is missing" % label)
        return entries[key]

    number, private_key, _ = required(iface, "privatekey", "PrivateKey")
    if not KEY_RE.fullmatch(private_key):
        raise _invalid("E_CONFIG_INVALID", "line %d: PrivateKey is not a WireGuard key" % number)
    number, address_text, _ = required(iface, "address", "Address")
    addresses = []
    for part in [p.strip() for p in address_text.split(",") if p.strip()]:
        try:
            interface = ipaddress.ip_interface(part)
        except ValueError:
            raise _invalid("E_CONFIG_INVALID", "line %d: Address holds an invalid entry" % number) from None
        if interface.version == 6:
            warnings.append("line %d: an IPv6 Address entry was dropped (the server tunnels IPv4 only)" % number)
            continue
        if interface.ip not in ipaddress.ip_network("10.0.0.0/8"):
            raise _invalid("E_CONFIG_INVALID", "line %d: Address must be inside 10.0.0.0/8" % number)
        if interface.network.prefixlen != 32:
            # TunnelSats issues one /32; a wider prefix would add an on-link route on the tunnel
            raise _invalid("E_CONFIG_INVALID", "line %d: Address must be a single /32 address" % number)
        addresses.append(str(interface))
    if not addresses:
        raise _invalid("E_CONFIG_INVALID", "line %d: Address has no IPv4 entry" % number)
    mtu = None
    if "mtu" in iface:
        number, value, _ = iface["mtu"]
        if not re.fullmatch(r"[0-9]{4}", value) or not 1280 <= int(value) <= 1500:
            raise _invalid("E_CONFIG_INVALID", "line %d: MTU must be 1280-1500" % number)
        mtu = int(value)
    number, peer_key, _ = required(peer, "publickey", "PublicKey")
    if not KEY_RE.fullmatch(peer_key):
        raise _invalid("E_CONFIG_INVALID", "line %d: PublicKey is not a WireGuard key" % number)
    psk = None
    if "presharedkey" in peer:
        number, psk, _ = peer["presharedkey"]
        if not KEY_RE.fullmatch(psk):
            raise _invalid("E_CONFIG_INVALID", "line %d: PresharedKey is not a WireGuard key" % number)
    number, endpoint, _ = required(peer, "endpoint", "Endpoint")
    match = re.fullmatch(r"(.+):([0-9]{1,5})", endpoint)
    if not match:
        raise _invalid("E_CONFIG_INVALID", "line %d: Endpoint is not host:port" % number)
    host = match.group(1).lower()
    endpoint_port = int(match.group(2))
    if host.startswith("[") or re.fullmatch(r"[0-9.]+", host):
        raise ModuleError("E_ENDPOINT_NOT_ALLOWED", "refused",
                          "line %d: Endpoint must be a *.tunnelsats.com host name, not an IP address" % number,
                          EXIT_USAGE)
    if not valid_host(host):
        raise ModuleError("E_ENDPOINT_NOT_ALLOWED", "refused",
                          "line %d: Endpoint host is not a *.tunnelsats.com name" % number, EXIT_USAGE)
    if not 1 <= endpoint_port <= 65535:
        raise _invalid("E_CONFIG_INVALID", "line %d: Endpoint port must be 1-65535" % number)
    number, allowed_text, _ = required(peer, "allowedips", "AllowedIPs")
    networks = []
    for part in [p.strip() for p in allowed_text.split(",") if p.strip()]:
        try:
            networks.append(str(ipaddress.ip_network(part, strict=False)))
        except ValueError:
            raise _invalid("E_CONFIG_INVALID", "line %d: AllowedIPs holds an invalid entry" % number) from None
    if "0.0.0.0/0" not in networks:
        raise _invalid("E_CONFIG_INVALID", "line %d: AllowedIPs must contain 0.0.0.0/0" % number)
    keepalive = None
    if "persistentkeepalive" in peer:
        number, value, _ = peer["persistentkeepalive"]
        if not re.fullmatch(r"[0-9]{1,5}", value) or int(value) > 65535:
            raise _invalid("E_CONFIG_INVALID", "line %d: PersistentKeepalive must be 0-65535" % number)
        keepalive = int(value)
    public_key = public_key_of(private_key)
    matches = None
    if mypubkey is not None:
        matches = mypubkey == public_key
        if not matches:
            warnings.append("the myPubKey comment differs from the key derived from PrivateKey (the derived one is used)")
    return {"private_key": private_key, "addresses": addresses, "mtu": mtu, "peer_public_key": peer_key,
            "preshared_key": psk, "endpoint_host": host, "endpoint_port": endpoint_port,
            "allowed_ips": networks, "keepalive": keepalive, "vpn_port": port, "valid_until": valid_until,
            "public_key": public_key, "public_key_matches": matches, "warnings": warnings}


def render_wg_config(cfg):
    """The canonical config from validated fields only: fixed order, LF. The metadata comments stay
    before [Interface], where tunnelsats.sh reads '# Port Forwarding:'."""
    lines = ["# TunnelSats WireGuard config (rebuilt by RaspiBlitz from validated fields)",
             "# Port Forwarding: %d" % cfg["vpn_port"]]
    if cfg.get("valid_until"):
        lines.append("# Valid Until: %s" % cfg["valid_until"])
    lines += ["# myPubKey: %s" % cfg["public_key"], "[Interface]", "PrivateKey = %s" % cfg["private_key"],
              "Address = %s" % ", ".join(cfg["addresses"])]
    if cfg.get("mtu"):
        lines.append("MTU = %d" % cfg["mtu"])
    lines += ["[Peer]", "PublicKey = %s" % cfg["peer_public_key"]]
    if cfg.get("preshared_key"):
        lines.append("PresharedKey = %s" % cfg["preshared_key"])
    lines += ["Endpoint = %s:%d" % (cfg["endpoint_host"], cfg["endpoint_port"]),
              "AllowedIPs = %s" % ", ".join(cfg["allowed_ips"])]
    if cfg.get("keepalive") is not None:
        lines.append("PersistentKeepalive = %d" % cfg["keepalive"])
    return ("\n".join(lines) + "\n").encode()


# ------------------------------------------------------------------------------------------
# Public API: POST /subscription/status
# ------------------------------------------------------------------------------------------

def _api_error_code(raw):
    doc = parse_one_json(raw.decode("utf-8", "replace")) if raw else None
    code = doc.get("error") if doc else None
    return code if isinstance(code, str) and re.fullmatch(r"ERR_[A-Z0-9_]{1,40}", code) else None


def validate_status(doc):
    """The validated fields of a 200 response, renamed for the module, or None."""
    if not isinstance(doc, dict):
        return None
    expiry = doc.get("expiry")
    synced = doc.get("last_synced_at")
    vpn_port = doc.get("vpn_port")
    if parse_iso(expiry) is None or not (synced is None or parse_iso(synced) is not None):
        return None
    if not is_number(doc.get("bandwidth_used_gb")) or not is_number(doc.get("bandwidth_limit_gb")):
        return None
    if not is_count(doc.get("bandwidth_resets_this_month")) or not is_count(doc.get("max_resets_per_month")):
        return None
    if doc.get("status") not in ("enabled", "disabled") or not valid_host(doc.get("server_domain")):
        return None
    if not (vpn_port is None or valid_port(vpn_port)):
        return None
    return {"expiry": expiry, "bandwidth_used_gb": doc["bandwidth_used_gb"],
            "bandwidth_limit_gb": doc["bandwidth_limit_gb"], "resets_this_month": doc["bandwidth_resets_this_month"],
            "max_resets_per_month": doc["max_resets_per_month"], "peer_status": doc["status"],
            "server_domain": doc["server_domain"], "vpn_port": vpn_port, "last_synced_at": synced}


def api_status(deps, public_key):
    """Asks the API for the subscription of a public key. Returns (outcome, data, detail): outcome is
    confirmed, unknown_key (404, definitive), failed (network, timeout, 5xx, 429), invalid
    (validation failed) or migration (the key must be migrated on the website first). Response
    bodies are never logged."""
    for attempt in (1, 2):
        try:
            status, headers, raw = deps.http(API_STATUS_URL, {"wgPublicKey": public_key})
        except Exception:  # network, TLS, timeout: never the body
            return "failed", None, "the TunnelSats API could not be reached"
        if len(raw) > API_MAX_BYTES:
            return "invalid", None, "the response is larger than 64 KB"
        if status == 503 and attempt == 1:
            retry = headers.get("retry-after", "30")
            deps.sleep(min(int(retry), 60) if str(retry).isdigit() else 30)
            continue
        break
    code = _api_error_code(raw) if status != 200 else None
    if status == 200:
        data = validate_status(parse_one_json(raw.decode("utf-8", "replace")))
        if data is None:
            return "invalid", None, "the status response failed validation"
        return "confirmed", data, ""
    if status == 404 and code == "ERR_RESOURCE_NOT_FOUND":
        return "unknown_key", None, "TunnelSats knows no subscription for this key"
    if status == 403 and code == "ERR_MIGRATION_REQUIRED":
        return "migration", None, "this subscription has to be migrated on tunnelsats.com first"
    if status == 429:
        retry = headers.get("retry-after", "60")
        return "failed", None, "rate limited, retry in %s s" % (retry if str(retry).isdigit() else "60")
    if status >= 500 or status == 404:
        return "failed", None, "the TunnelSats API is unavailable (HTTP %d)" % status
    return "invalid", None, "unexpected API answer (HTTP %d)" % status


# ------------------------------------------------------------------------------------------
# Local state
# ------------------------------------------------------------------------------------------

def load_state(deps):
    try:
        with open(deps.path(STATE_FILE), encoding="utf-8") as handle:
            doc = json.load(handle)
        return doc if isinstance(doc, dict) and doc.get("schema") == "raspiblitz.tunnelsats.state/1" else None
    except (OSError, ValueError):
        return None


def save_state(deps, state):
    ensure_dir(deps.path(STATE_DIR), 0o700)
    write_private(deps.path(STATE_FILE), (json.dumps(state, indent=1, sort_keys=True) + "\n").encode())


def load_stored_config(deps):
    try:
        with open(deps.path(CONF_FILE), "rb") as handle:
            return parse_wg_config(handle.read())
    except OSError:
        return None


def empty_pending():
    return {"schema": "raspiblitz.tunnelsats.pending/1", "order": None, "renewal": None, "reset": None,
            "retained_orders": [], "recovered_configs": []}


def load_pending(deps):
    try:
        with open(deps.path(PENDING_FILE), encoding="utf-8") as handle:
            doc = json.load(handle)
        if not isinstance(doc, dict) or doc.get("schema") != "raspiblitz.tunnelsats.pending/1":
            return empty_pending()
        base = empty_pending()
        for key in ("order", "renewal", "reset"):
            if isinstance(doc.get(key), dict):
                base[key] = doc[key]
        if isinstance(doc.get("retained_orders"), list):
            base["retained_orders"] = [x for x in doc["retained_orders"] if isinstance(x, dict)]
        if isinstance(doc.get("recovered_configs"), list):
            base["recovered_configs"] = [x for x in doc["recovered_configs"] if isinstance(x, dict)]
        return base
    except (OSError, ValueError):
        return empty_pending()


def save_pending(deps, doc, shred_first=False):
    ensure_dir(deps.path(STATE_DIR), 0o700)
    if shred_first:
        shred(deps.path(PENDING_FILE))
    write_private(deps.path(PENDING_FILE), (json.dumps(doc, indent=1, sort_keys=True) + "\n").encode())


def _item_protected_from_prune(item):
    """True if item is paid, claiming, needs_support, or has an in-flight/uncertain node payment."""
    if not isinstance(item, dict):
        return False
    if item.get("state") in ("paid", "claiming", "needs_support"):
        return True
    np_state = (item.get("node_payment") or {}).get("state") if isinstance(item.get("node_payment"), dict) else None
    return np_state in ("paying", "uncertain", "succeeded")


def prune_pending(deps, doc=None, now=None, persist=True):
    """Refreshes expired awaiting_payment items to expired_unpaid and prunes unpaid items past
    retained_until. Never prunes paid, claiming, needs_support, or uncertain node payments.
    Shreds pending.json before rewriting when an order private key is dropped."""
    now = now or deps.clock()
    doc = load_pending(deps) if doc is None else doc
    changed = False
    dropped_key = False

    def refresh_and_keep(item):
        nonlocal changed, dropped_key
        if not isinstance(item, dict):
            return None
        exp = parse_iso(item.get("invoice_expires_at"))
        if item.get("state") == "awaiting_payment" and not _item_protected_from_prune(item) and exp and now >= exp:
            item["state"] = "expired_unpaid"
            changed = True
        ret = parse_iso(item.get("retained_until"))
        if not _item_protected_from_prune(item) and item.get("state") in ("awaiting_payment", "expired_unpaid") \
                and ret and now >= ret:
            if item.get("private_key"):
                dropped_key = True
            changed = True
            return None
        return item

    for key in ("order", "renewal", "reset"):
        if doc.get(key) is not None:
            doc[key] = refresh_and_keep(doc[key])
    kept_retained = []
    for item in doc.get("retained_orders") or []:
        updated = refresh_and_keep(item)
        if updated is not None:
            kept_retained.append(updated)
    if len(kept_retained) > MAX_RETAINED_ORDERS:
        # Keep protected orders first, then newest by created_at
        protected = [x for x in kept_retained if _item_protected_from_prune(x)]
        unprotected = [x for x in kept_retained if not _item_protected_from_prune(x)]
        keep_count = max(0, MAX_RETAINED_ORDERS - len(protected))
        dropped = unprotected[:max(0, len(unprotected) - keep_count)]
        if any(x.get("private_key") for x in dropped):
            dropped_key = True
        kept_retained = protected + (unprotected[-keep_count:] if keep_count else [])
        changed = True
    doc["retained_orders"] = kept_retained
    if changed and persist and os.path.exists(deps.path(PENDING_FILE)):
        save_pending(deps, doc, shred_first=dropped_key)
    return doc


def redact_pending_item(item):
    """Returns a copy of a pending item without private_key or full invoice."""
    if not isinstance(item, dict):
        return None
    out = {k: v for k, v in item.items() if k not in ("private_key", "invoice")}
    if "private_key" in item:
        out["has_private_key"] = bool(item.get("private_key"))
    return out


def tick_timer_needed(deps):
    """True when tunnelsats is on, a subscription is stored, or pending.json holds an active item."""
    if read_rb_conf(deps).get("tunnelsats") == "on" or load_state(deps) is not None:
        return True
    pending = load_pending(deps)
    return bool(pending.get("order") or pending.get("renewal") or pending.get("reset")
                or pending.get("retained_orders"))


class Lock:
    """flock on /run/tunnelsats-rb/module.lock: state-changing verbs run one at a time. Not below
    /run/tunnelsats: uninstall --managed removes that directory while REMOVE or REPAIR holds the lock,
    and a lock file created again there would let a second verb in."""

    def __init__(self, deps, wait):
        self.deps = deps
        self.wait = wait
        self.fd = None

    def __enter__(self):
        lock_dir = self.deps.path(LOCK_DIR)
        os.makedirs(lock_dir, mode=0o700, exist_ok=True)
        os.chmod(lock_dir, 0o700)
        self.fd = os.open(self.deps.path(LOCK_FILE), os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
        deadline = time.monotonic() + self.wait
        while True:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                return self
            except OSError:
                if time.monotonic() >= deadline:
                    os.close(self.fd)
                    raise ModuleError("E_BUSY", "operational", "another TunnelSats action is running",
                                      EXIT_OPERATIONAL) from None
                time.sleep(0.5)

    def __exit__(self, *exc):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        os.close(self.fd)


# ------------------------------------------------------------------------------------------
# System calls (all as argument lists)
# ------------------------------------------------------------------------------------------

def its(deps, args, timeout=120):
    """internet.tunnelsats.sh <args...>; returns (rc, document or None)."""
    rc, out, _err = deps.run([ITS] + list(args), timeout=timeout)
    return rc, parse_one_json(out)


def blitz_conf_set(deps, key, value):
    rc, _out, _err = deps.run([BLITZ_CONF, "set", key, value], timeout=30)
    if rc != 0:
        raise ModuleError("E_CONF_WRITE", "operational", "raspiblitz.conf: %s could not be set" % key, EXIT_OPERATIONAL)


def unit_props(deps, unit, *props):
    argv = ["systemctl", "show"]
    for prop in props:
        argv += ["-p", prop]
    rc, out, _err = deps.run(argv + [unit], timeout=30)
    values = {prop: "" for prop in props}
    if rc == 0:
        for line in out.splitlines():
            key, _sep, value = line.partition("=")
            if key in values:
                values[key] = value
    return values


def systemctl(deps, *args):
    rc, _out, _err = deps.run(["systemctl"] + list(args), timeout=120)
    return rc == 0


def select_impl(conf, requested=None):
    """The implementation TunnelSats tunnels: LND when it runs (also next to CLN), else CLN.
    Returns (impl or None, reason or None); --impl cl next to LND is refused."""
    lnd_on = conf.get("lightning") == "lnd" or conf.get("lnd") in ("on", "1")
    cl_on = conf.get("lightning") == "cl" or conf.get("cl") in ("on", "1")
    if requested == "cl" and lnd_on:
        raise ModuleError("E_PORT_CONFLICT", "refused",
                          "LND is on and owns port 9735: TunnelSats tunnels LND on this node", EXIT_REFUSED)
    if requested == "lnd":
        return ("lnd", None) if lnd_on else (None, "lnd_not_active")
    if requested == "cl":
        return ("cl", None) if cl_on else (None, "cl_not_active")
    if lnd_on:
        return "lnd", None
    if cl_on:
        return "cl", None
    return None, "no_lightning"


# ------------------------------------------------------------------------------------------
# Output
# ------------------------------------------------------------------------------------------

class Result:
    def __init__(self, command):
        self.command = command
        self.fields = {}
        self.errors = []
        self.exit_code = EXIT_OK

    def error(self, code, cls, message, exit_code=None):
        self.errors.append({"code": code, "class": cls, "message": message})
        self.fields.setdefault("error", code)
        if exit_code is not None:
            self.exit_code = exit_code

    def document(self):
        doc = {"contract": CONTRACT, "command": self.command, "module_version": MODULE_VERSION,
               "ok": self.exit_code == EXIT_OK, "exit_code": self.exit_code, "errors": self.errors}
        doc.update(self.fields)
        return doc


def emit(result, as_json, out=None):
    out = out or sys.stdout
    doc = result.document()
    if as_json:
        out.write(json.dumps(doc, sort_keys=True) + "\n")
        return
    for key in sorted(doc):
        if key in ("contract", "module_version"):
            continue
        out.write("%s: %s\n" % (key, json.dumps(doc[key], sort_keys=True)))


# ------------------------------------------------------------------------------------------
# detect
# ------------------------------------------------------------------------------------------

def detect(deps, requested=None):
    """Eligibility (design 6.4). Returns the detect fields; read-only."""
    conf = read_rb_conf(deps)
    reasons = []
    impl, why = select_impl(conf, requested)
    if why:
        reasons.append(why)
    if conf.get("chain", "main") != "main":
        reasons.append("chain_not_main")
    if conf.get("runBehindTor") != "on":
        reasons.append("tor_required")
    if conf.get("lndPort") not in (None, "", "9735"):
        reasons.append("lnd_port")
    if impl:
        rc, audit = its(deps, ["audit", impl, "--json"], timeout=30)
        if audit is None:
            reasons.append("config_check_failed")
        elif audit.get("status") == "unrepairable":
            reasons.append("config_unrepairable:%s" % audit.get("reason"))
        elif audit.get("eligible") is False:
            reasons.append("not_eligible:%s" % audit.get("not_eligible_reason"))
    rc, tool = its(deps, ["detect", "--json"], timeout=ITS_TIMEOUT["detect"])
    kind = None
    artifacts = []
    capabilities = {}
    if tool is None or rc != 0:
        reasons.append("tool_detect_failed")
    else:
        install = tool.get("install") if isinstance(tool.get("install"), dict) else {}
        kind = install.get("kind")
        artifacts = [{"id": a.get("id"), "location": a.get("location")} for a in install.get("artifacts") or []
                     if isinstance(a, dict) and a.get("status") == "present"]
        caps = tool.get("capabilities") if isinstance(tool.get("capabilities"), dict) else {}
        capabilities = {
            "wireguard_tools": (caps.get("wireguard_tools") or {}).get("status"),
            "nft": (caps.get("nft") or {}).get("status"),
            "systemd": (caps.get("systemd") or {}).get("status"),
            "cgroup_v2": (caps.get("cgroup_v2") or {}).get("status"),
        }
        if capabilities["systemd"] != "present":
            reasons.append("systemd_missing")
        if capabilities["cgroup_v2"] != "mounted":
            reasons.append("cgroup_v2_missing")
        if kind in ("legacy_v2", "legacy_v3_pre_204", "legacy_v3_post_204"):
            reasons.append("legacy_install")
        elif kind not in ("none", "managed"):
            reasons.append("unknown_install")
    configured = load_state(deps) is not None
    return {"eligible": not reasons, "impl": impl, "reasons": reasons, "capabilities": capabilities,
            "existing_install": {"kind": kind, "artifacts": artifacts}, "installed": kind == "managed",
            "artifacts": [a["id"] for a in artifacts], "configured": configured,
            "adopt_available": kind in ("legacy_v2", "legacy_v3_pre_204", "legacy_v3_post_204", "unknown")}


def cmd_detect(deps, args, result):
    result.fields.update(detect(deps))
    if not result.fields["eligible"] and not result.fields["configured"]:
        result.exit_code = EXIT_NOT_CONFIGURED


# ------------------------------------------------------------------------------------------
# servers
# ------------------------------------------------------------------------------------------

def _validate_server_items(items):
    if not isinstance(items, list) or not items:
        return None
    servers = []
    seen = set()
    for entry in items:
        if not isinstance(entry, dict):
            return None
        sid = entry.get("id")
        country = entry.get("country")
        city = entry.get("city")
        flag = entry.get("flag") or ""
        status = entry.get("status") or "online"
        if not isinstance(sid, str) or not SERVER_ID_RE.fullmatch(sid) or sid in seen:
            return None
        if not isinstance(country, str) or not country.strip() or len(country) > 64 \
                or any(ord(c) < 32 or ord(c) == 127 for c in country):
            return None
        if not isinstance(city, str) or not city.strip() or len(city) > 64 \
                or any(ord(c) < 32 or ord(c) == 127 for c in city):
            return None
        if not isinstance(flag, str) or len(flag) > 16 \
                or any(ord(c) < 32 or ord(c) == 127 for c in flag):
            return None
        if status not in SERVER_STATUSES:
            return None
        seen.add(sid)
        servers.append({"id": sid, "country": country.strip(), "city": city.strip(),
                        "flag": flag.strip(), "status": status})
    return servers


def _validate_servers_payload(raw):
    if not raw or len(raw) > API_MAX_BYTES:
        return None
    try:
        parsed = json.loads(raw.decode("utf-8", "replace"))
    except ValueError:
        return None
    items = parsed.get("servers") if isinstance(parsed, dict) else parsed
    return _validate_server_items(items)


def _load_servers_cache(deps):
    try:
        with open(deps.path(SERVERS_CACHE_FILE), encoding="utf-8") as handle:
            doc = json.load(handle)
        if not isinstance(doc, dict):
            return None, None
        servers = _validate_server_items(doc.get("servers"))
        if not servers:
            return None, None
        return servers, parse_iso(doc.get("fetched_at"))
    except (OSError, ValueError):
        return None, None


def fetch_servers(deps):
    """Returns (servers, stale, offline_list) with a 60 s cache in /run/tunnelsats-rb/servers-cache.json."""
    cached, fetched_at = _load_servers_cache(deps)
    if cached and fetched_at and 0 <= (deps.clock() - fetched_at).total_seconds() <= SERVERS_CACHE_SECONDS:
        return cached, False, False
    try:
        status, _headers, raw = deps.http(API_SERVERS_URL, None)
    except Exception:
        status, raw = 0, b""
    servers = _validate_servers_payload(raw) if status == 200 else None
    if servers:
        try:
            ensure_dir(deps.path(LOCK_DIR), 0o700)
            write_private(deps.path(SERVERS_CACHE_FILE),
                          (json.dumps({"fetched_at": now_iso(deps), "servers": servers}, sort_keys=True) + "\n").encode())
        except ModuleError:
            pass
        return servers, False, False
    if cached:
        return cached, True, False
    return [dict(s) for s in OFFLINE_SERVERS], True, True


def cmd_servers(deps, args, result):
    servers, stale, offline_list = fetch_servers(deps)
    result.fields.update({"servers": servers, "stale": stale, "offline_list": offline_list})


# ------------------------------------------------------------------------------------------
# Activation (shared by IMPORT and REPAIR)
# ------------------------------------------------------------------------------------------

def guard_line(impl):
    """The start guard line of a mainnet Lightning unit (the templates write the same text): it runs
    the guard, or, without an executable internet.tunnelsats.sh, writes the empty value (never a
    deleted file, so a stray raspiblitz.conf value cannot pass) and lets Lightning start Tor-only."""
    return ("ExecStartPre=+/bin/sh -c 'if [ -x {its} ]; then exec {its} guard {impl} mainnet; fi; "
            "echo tunnelsats-guard: internet.tunnelsats.sh is missing, Lightning starts Tor-only >&2; "
            "mkdir -p /run/tunnelsats && echo {var}= > /run/tunnelsats/hybrid-{base}.env'").format(
                its=ITS, impl=impl, var=VARS[impl], base=BASES[impl])


def unit_template_ok(deps, impl):
    """The Lightning unit file carries the guard template lines and needs no daemon-reload."""
    unit = UNITS[impl]
    props = unit_props(deps, unit, "FragmentPath", "NeedDaemonReload")
    path = props["FragmentPath"]
    if not path or props["NeedDaemonReload"] != "no":
        return False
    try:
        with open(deps.path(path), encoding="utf-8", errors="replace") as handle:
            lines = [line.rstrip("\r") for line in handle.read().split("\n")]
    except OSError:
        return False
    var = VARS[impl]
    if "Environment=%s=" % var not in lines:
        return False
    if "EnvironmentFile=-/run/tunnelsats/hybrid-%s.env" % BASES[impl] not in lines:
        return False
    if guard_line(impl) not in lines:
        return False
    starts = [line for line in lines if line.startswith("ExecStart=")]
    if impl == "lnd":
        return bool(starts) and starts[0].endswith(" $" + var)
    return bool(starts) and starts[0].endswith(" $$%s'" % var)


def regenerate_unit(deps, impl):
    """Rewrites a guard-less unit with RaspiBlitz's own writers (no restart for LND)."""
    if impl == "lnd":
        rc, _o, _e = deps.run(["install", "-m", "0644", LND_ASSET, UNIT_DIR + "/lnd.service"], timeout=30)
        ok = rc == 0 and systemctl(deps, "daemon-reload")
    else:
        rc, _o, _e = deps.run([CL_INSTALL_SERVICE, "mainnet"], timeout=300)
        ok = rc == 0
    if not ok or not unit_template_ok(deps, impl):
        raise ModuleError("E_UNIT_TEMPLATE", "operational",
                          "the Lightning unit could not be rewritten with the start guard lines", EXIT_OPERATIONAL)


def map_tool_exit(rc):
    if rc == 6:
        return EXIT_NOT_CONFIGURED
    if rc == 7:
        return EXIT_REFUSED
    return EXIT_OPERATIONAL


def tool_error(doc, fallback):
    errors = (doc or {}).get("errors") or []
    code = errors[0].get("code") if errors and isinstance(errors[0], dict) else None
    return code if isinstance(code, str) and re.fullmatch(r"E_[A-Z0-9_]{1,40}", code) else fallback


def activate(deps, impl, result, stored_writer=None, tool_verb="install"):
    """Design 6.3: preflight without changes, store, unit, flags, install/adopt, block, timer, check."""
    activation = {"fetch": None, "unit_regenerated": False, tool_verb: None, "ln_restarted": None,
                  "restore_block": None, "tick_timer": None}
    result.fields["activation"] = activation
    rc, doc = its(deps, ["fetch", "--json"], timeout=ITS_TIMEOUT["fetch"])
    activation["fetch"] = "ok" if rc == 0 else tool_error(doc, "E_DOWNLOAD_FAILED")
    if rc != 0:
        raise ModuleError(activation["fetch"], "operational",
                          "the pinned tunnelsats.sh could not be fetched and verified", EXIT_OPERATIONAL)
    rc, doc = its(deps, ["block-insert", "--check", "--json"], timeout=30)
    if rc != 0:
        raise ModuleError(tool_error(doc, "E_BLOCK_CHECK"), "operational",
                          "custom-installs.sh cannot take the restore block (fix it first)", EXIT_OPERATIONAL)
    template_ok = unit_template_ok(deps, impl)
    if stored_writer:
        stored_writer()
    if tool_verb == "install" and not template_ok:
        regenerate_unit(deps, impl)
        activation["unit_regenerated"] = True
    blitz_conf_set(deps, "tunnelsatsImpl", impl)
    blitz_conf_set(deps, "tunnelsats", "on")
    rc, doc = its(deps, [tool_verb, "--impl", impl, "--json"], timeout=ITS_TIMEOUT[tool_verb])
    if rc != 0 and tool_verb == "adopt" and doc and doc.get("adopted"):
        # E_PARTIAL: the managed dataplane is installed and armed, only the Lightning unit or the
        # verifier timer did not start; finish as managed and let the final check report it
        result.fields["warnings"] = list(result.fields.get("warnings") or []) + [tool_error(doc, "E_PARTIAL")]
        rc = 0
    if rc != 0:
        fallback = "E_ADOPT_FAILED" if tool_verb == "adopt" else "E_INSTALL_FAILED"
        activation[tool_verb] = tool_error(doc, fallback)
        if tool_verb == "adopt":
            # adopt stops Lightning before it removes the legacy setup. Unless the unit still runs (adopt
            # refused before any change), the legacy clearnet settings may be left without a tunnel:
            # keep tunnelsats on, so the start guard keeps Lightning Tor-only, and repair them at rest
            _rc, audit = its(deps, ["audit", impl, "--repair", "--json"], timeout=30)
            if tool_error(audit, "") != "E_UNIT_ACTIVE":
                raise ModuleError(activation[tool_verb], "operational",
                                  "the legacy setup could not be replaced; Lightning stays stopped, and TunnelSats "
                                  "stays on so its next start is Tor-only (fix the cause, then run ADOPT --upgrade "
                                  "again)", map_tool_exit(rc))
            blitz_conf_set(deps, "tunnelsats", "off")
            raise ModuleError(activation[tool_verb], "operational",
                              "adopt refused before any change; the legacy setup keeps running (fix the cause, "
                              "then run ADOPT --upgrade again)", map_tool_exit(rc))
        blitz_conf_set(deps, "tunnelsats", "off")
        raise ModuleError(activation[tool_verb], "operational",
                          "the managed dataplane could not be installed; Lightning stays Tor-only "
                          "(the stored config stays for REPAIR)", map_tool_exit(rc))
    activation[tool_verb] = "ok"
    activation["ln_restarted"] = bool(doc.get("ln_restarted")) if doc else None
    if tool_verb == "adopt":
        for key in ("legacy_kind", "legacy_removed", "legacy_remaining", "unit_edits", "unit_reverted"):
            if doc and key in doc:
                activation[key] = doc[key]
        if not activation["ln_restarted"]:
            its(deps, ["audit", impl, "--repair", "--json"], timeout=30)
        if not unit_template_ok(deps, impl):
            regenerate_unit(deps, impl)
            activation["unit_regenerated"] = True
            if doc and (doc.get("ln_restarted") or doc.get("ln_was_active")):
                systemctl(deps, "restart", UNITS[impl])
                activation["ln_restarted"] = True
    rc, block_doc = its(deps, ["block-insert", "--json"], timeout=30)
    activation["restore_block"] = "present" if rc == 0 else "failed"
    rc, out, _err = deps.run([ITS, "tick-timer", "on"], timeout=60)
    activation["tick_timer"] = "active" if rc == 0 else "failed"
    wait_for_handshake(deps)
    return doc


def wait_for_handshake(deps, seconds=60, step=5):
    """Waits up to 60 s for the first handshake of the tunnel (verify --no-probe)."""
    waited = 0
    while True:
        rc, doc = its(deps, ["verify", "--no-probe", "--json"], timeout=ITS_TIMEOUT["verify_no_probe"])
        checks = (doc or {}).get("checks") or []
        if any(isinstance(c, dict) and c.get("id") == "wg_handshake" and c.get("result") == "pass" for c in checks):
            return True
        if waited >= seconds:
            return False
        deps.sleep(step)
        waited += step


def wait_until_started(deps, unit, limit=LN_START_WAIT, step=LN_START_STEP):
    """REPAIR and IMPORT, before their final check, after the tool or the module (re)started unit:
    waits while it is "activating" (LND until it is ready, Type=notify), at most limit seconds,
    because verify reports a start in progress as degraded. Returns the record for the result:
    unit, state (read last; "auto-restart" for a unit that keeps failing), waited_s and outcome:
    "active", "not_running" (it was not starting), "failed" (it stopped while starting, or it waits
    in auto-restart after a failed start) or "timeout" (still starting at the limit)."""
    started, waited = deps.clock(), 0
    state = unit_props(deps, unit, "ActiveState")["ActiveState"]
    starting = state == "activating"
    while state == "activating" and waited < limit and (deps.clock() - started).total_seconds() < limit:
        deps.sleep(step)
        waited += step
        state = unit_props(deps, unit, "ActiveState")["ActiveState"]
    if state == "active":
        outcome = "active"
    elif state == "activating":
        # Restart=always (RestartSec=60): "activating" with SubState auto-restart is the pause after
        # a start that failed, not a start in progress; one read, only when the wait ends here
        if unit_props(deps, unit, "SubState")["SubState"] == "auto-restart":
            outcome, state = "failed", "auto-restart"
        else:
            outcome = "timeout"
    else:
        outcome = "failed" if starting else "not_running"
    return {"unit": unit, "state": state or "unknown", "waited_s": waited, "outcome": outcome}


def start_wait_detail(wait):
    """Why the final check saw a start that did not finish, or None."""
    if not wait:
        return None
    if wait["outcome"] == "timeout":
        hint = " (LND stays starting until its wallet is unlocked)" if wait["unit"] == UNITS["lnd"] else ""
        return ("%s was still starting after %d s, so this check ran while it starts%s: run CHECK again once it "
                "runs" % (wait["unit"], wait["waited_s"], hint))
    if wait["outcome"] == "failed":
        return ("%s stopped while starting (%s): see journalctl -u %s, then REPAIR"
                % (wait["unit"], wait["state"], wait["unit"]))
    return None


def with_start_wait(checked, wait):
    """The check result with a start that did not finish as a failed degraded check (ln_start), so
    the verdict is never protected for it."""
    detail = start_wait_detail(wait)
    if detail:
        checked["checks"].append({"id": "ln_start", "class": "degraded", "result": "fail", "detail": detail})
        checked["reasons"].append("ln_start")
        if checked["verdict"] == "protected":
            checked["verdict"] = "degraded"
    return checked


def only_no_handshake_yet(checked):
    """True when the only failing check in checked is wg_handshake with 'no handshake yet'."""
    failed = [c for c in checked.get("checks") or [] if c.get("result") == "fail"]
    return (len(failed) == 1 and failed[0].get("id") == "wg_handshake"
            and "no handshake yet" in str(failed[0].get("detail") or "").lower())


def check_after_activation(deps, wait=None, limit=HANDSHAKE_WAIT, step=HANDSHAKE_STEP):
    """The final check after an activation or reinstall (IMPORT, ADOPT --upgrade, REPAIR): when the
    only failing check is wg_handshake ("no handshake yet"), waits briefly (at most limit seconds,
    every step seconds) and runs the check again so the first handshake initiated by the probe or
    Lightning traffic is seen without turning any other check into protected."""
    checked = with_start_wait(run_check(deps), wait)
    started, waited = deps.clock(), 0
    while only_no_handshake_yet(checked) and waited < limit and (deps.clock() - started).total_seconds() < limit:
        deps.sleep(step)
        waited += step
        checked = with_start_wait(run_check(deps), wait)
    return checked


# ------------------------------------------------------------------------------------------
# import
# ------------------------------------------------------------------------------------------

def sync_fields(outcome, data, cfg):
    return {"sync": {"outcome": outcome}, "server_domain": (data or {}).get("server_domain") or cfg["endpoint_host"],
            "expiry": (data or {}).get("expiry") or cfg.get("valid_until")}


def store_subscription(deps, cfg, mode, impl, outcome, data, extra=None):
    """Writes tunnelsats.conf (0600) and state.json (0600)."""
    ensure_dir(deps.path(STATE_DIR), 0o700)
    write_private(deps.path(CONF_FILE), render_wg_config(cfg))
    state = load_state(deps) or {}
    state.update({
        "schema": "raspiblitz.tunnelsats.state/1", "mode": mode, "impl": impl, "public_key": cfg["public_key"],
        "endpoint_host": cfg["endpoint_host"], "vpn_port": cfg["vpn_port"],
        "server_domain": (data or {}).get("server_domain") or cfg["endpoint_host"],
        "valid_until": cfg.get("valid_until"), "imported_at": state.get("imported_at") or now_iso(deps),
        "api": {"outcome": outcome, "checked_at": now_iso(deps), "data": data,
                "confirmed_at": now_iso(deps) if outcome == "confirmed" else None},
        "notified_invocation_id": state.get("notified_invocation_id"), "notify": state.get("notify") or {},
    })
    if extra:
        state.update(extra)
    save_state(deps, state)
    return state


def confirm_with_api(deps, cfg, yes, result):
    outcome, data, detail = api_status(deps, cfg["public_key"])
    result.fields.update(sync_fields(outcome, data, cfg))
    if outcome == "unknown_key":
        raise ModuleError("E_UNKNOWN_KEY", "refused", detail + "; nothing was stored", EXIT_REFUSED)
    if outcome == "migration":
        raise ModuleError("E_MIGRATION_REQUIRED", "refused", detail, EXIT_REFUSED)
    if outcome == "invalid":
        raise ModuleError("E_API_INVALID", "invalid_response", detail, EXIT_INVALID_API)
    if outcome == "failed" and not yes:
        raise ModuleError("E_API_UNAVAILABLE", "retryable",
                          detail + "; confirm to continue without the API (--yes)", EXIT_API_UNAVAILABLE)
    return outcome, data


def read_import_file(path):
    real = path
    try:
        if not os.path.isfile(real) or os.path.islink(real):
            raise OSError
        if os.path.getsize(real) > MAX_CONFIG_BYTES:
            raise _invalid("E_CONFIG_INVALID", "the config is larger than 16 KiB")
        with open(real, "rb") as handle:
            return handle.read(MAX_CONFIG_BYTES + 1)
    except OSError:
        raise _invalid("E_FILE", "the config file cannot be read (a regular file is needed)") from None


def cmd_import(deps, args, result):
    data = read_import_file(args.file)
    cfg = parse_wg_config(data)
    result.fields.update({"valid": True, "warnings": cfg["warnings"], "public_key": cfg["public_key"],
                          "public_key_matches": cfg["public_key_matches"],
                          "endpoint": {"host": cfg["endpoint_host"]}, "vpn_port": cfg["vpn_port"],
                          "ln_start_wait": None})
    state = load_state(deps)
    if state and state.get("public_key") != cfg["public_key"]:
        raise ModuleError("E_ALREADY_CONFIGURED", "refused",
                          "another subscription is stored on this node: REMOVE it first", EXIT_REFUSED)
    if state and state.get("mode") == "adopted_legacy":
        raise ModuleError("E_UPGRADE_UNAVAILABLE", "refused",
                          "this subscription runs on the adopted standard install: run adopt --upgrade --yes",
                          EXIT_REFUSED)
    found = detect(deps, args.impl)
    result.fields["detect"] = {"eligible": found["eligible"], "reasons": found["reasons"]}
    if found["reasons"]:
        raise ModuleError("E_NOT_ELIGIBLE", "not_eligible", "not eligible: %s" % ", ".join(found["reasons"]),
                          EXIT_NOT_CONFIGURED)
    impl = found["impl"]
    outcome, api_data = confirm_with_api(deps, cfg, args.yes, result)
    if args.dry_run:
        result.fields["dry_run"] = True
        return
    if state:
        # The same key again (for example a re-downloaded config): store it and repair
        with Lock(deps, wait=30):
            store_subscription(deps, cfg, "managed", impl, outcome, api_data)
        cmd_repair(deps, argparse.Namespace(yes=True, impl=impl, json=args.json), result)
        return
    with Lock(deps, wait=30):
        activate(deps, impl, result,
                 stored_writer=lambda: store_subscription(deps, cfg, "managed", impl, outcome, api_data))
    # the tool's install restarted a running unit: the check waits until that start is done
    finish_with_check(deps, result, wait_until_started(deps, UNITS[impl]))


def cmd_export(deps, args, result):
    out_path = str(getattr(args, "out", "") or "").strip()
    if not out_path or "\x00" in out_path:
        raise ModuleError("E_USAGE", "usage", "invalid --out path", EXIT_USAGE)
    if deps.root != "/" and out_path.startswith(deps.root):
        target_path = out_path
    elif out_path.startswith("/"):
        target_path = deps.path(out_path)
    else:
        target_path = os.path.abspath(out_path)
    if os.path.islink(target_path):
        raise ModuleError("E_USAGE", "usage", "--out path must not be a symlink", EXIT_USAGE)
    parent = os.path.dirname(target_path)
    if not parent or not os.path.isdir(parent) or os.path.islink(parent):
        raise ModuleError("E_USAGE", "usage", "parent directory of --out does not exist", EXIT_USAGE)
    cfg = load_stored_config(deps)
    state = load_state(deps)
    if cfg is None:
        raise ModuleError("E_NOT_CONFIGURED", "not_configured",
                          "no stored WireGuard config to export", EXIT_NOT_CONFIGURED)
    write_private(target_path, render_wg_config(cfg), mode=0o600)
    owner_name = "admin"
    if deps.root == "/":
        try:
            pw = pwd.getpwnam("admin")
            os.chown(target_path, pw.pw_uid, pw.pw_gid)
        except (KeyError, OSError):
            pass
    os.chmod(target_path, 0o600)
    result.fields.update({
        "exported": True,
        "file": out_path,
        "mode": "0600",
        "owner": owner_name,
        "public_key": cfg["public_key"],
        "server_domain": (state or {}).get("server_domain") or cfg["endpoint_host"],
        "vpn_port": cfg["vpn_port"],
    })



def finish_with_check(deps, result, wait=None):
    result.fields["ln_start_wait"] = wait
    checked = check_after_activation(deps, wait)
    result.fields["verdict"] = checked["verdict"]
    result.fields["guard"] = checked["guard"]
    result.fields["check"] = {"reasons": checked["reasons"], "restart_needed": checked["restart_needed"]}
    if start_wait_detail(wait):
        result.fields["warnings"] = list(result.fields.get("warnings") or []) + [start_wait_detail(wait)]
    result.exit_code = verdict_exit(checked["verdict"])


def verdict_exit(verdict):
    return {"protected": EXIT_OK, "degraded": EXIT_DEGRADED, "unsafe": EXIT_UNSAFE}.get(verdict, EXIT_NOT_CONFIGURED)


# ------------------------------------------------------------------------------------------
# buy, renew, invoice, pending, claim trust boundary, and settle
# ------------------------------------------------------------------------------------------

def iso(dt):
    return dt.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _api_json_request(deps, url, payload=None):
    """Performs a GET (payload=None) or POST JSON request to the TunnelSats API with one 503 retry.
    Returns (status, headers, doc, error_code) or raises ModuleError on transport/size failure."""
    for attempt in (1, 2):
        try:
            status, headers, raw = deps.http(url, payload)
        except Exception:
            raise ModuleError("E_API_UNAVAILABLE", "retryable",
                              "the TunnelSats API could not be reached", EXIT_API_UNAVAILABLE) from None
        if len(raw) > API_MAX_BYTES:
            raise ModuleError("E_API_INVALID", "invalid_response",
                              "the response is larger than 64 KB", EXIT_INVALID_API)
        if status == 503 and attempt == 1:
            retry = headers.get("retry-after", "30")
            deps.sleep(min(int(retry), 60) if str(retry).isdigit() else 30)
            continue
        break
    doc = parse_one_json(raw.decode("utf-8", "replace")) if raw else None
    code = _api_error_code(raw) if status not in (200, 201) else None
    return status, headers, doc, code


def poll_order_status(deps, payment_hash):
    """Polls GET /api/public/v1/subscription/{paymentHash}. Returns (outcome, status_str, doc, detail)
    where outcome is 'ok', 'not_found', 'failed', or 'invalid'. HTTP 202 (status 'processing') means
    the payment is confirmed and the API is still provisioning or renewing: status_str 'processing'."""
    if not isinstance(payment_hash, str) or not HEX64_RE.fullmatch(payment_hash.lower()):
        return "invalid", None, None, "invalid paymentHash"
    try:
        status, headers, doc, _code = _api_json_request(deps, "%s/%s" % (API_SUBSCRIPTION_URL, payment_hash.lower()), None)
    except ModuleError as exc:
        if exc.exit_code == EXIT_API_UNAVAILABLE:
            return "failed", None, None, exc.message
        return "invalid", None, None, exc.message
    if status in (200, 202) and isinstance(doc, dict):
        raw_st = str(doc.get("status") or "").strip().lower()
        if status == 202 or raw_st == "processing":
            return "ok", "processing", doc, ""
        if raw_st in ("pending", "awaiting_payment", "unpaid"):
            return "ok", "pending", doc, ""
        if raw_st in ("paid", "claimed", "expired"):
            return "ok", raw_st, doc, ""
        return "invalid", None, None, "unexpected order status value"
    if status == 404:
        return "not_found", None, None, "order not found"
    if status == 429:
        retry = headers.get("retry-after", "60")
        return "failed", None, None, "rate limited, retry in %s s" % (retry if str(retry).isdigit() else "60")
    if status >= 500:
        return "failed", None, None, "the TunnelSats API is unavailable (HTTP %d)" % status
    return "invalid", None, None, "unexpected API answer (HTTP %d)" % status


def poll_reset_status(deps, payment_hash):
    """Polls GET /api/public/v1/subscription/{paymentHash} for a bandwidth_reset invoice.
    Returns (outcome, status_str, doc, detail) where outcome is 'ok', 'not_found', 'failed', or 'invalid'."""
    if not isinstance(payment_hash, str) or not HEX64_RE.fullmatch(payment_hash.lower()):
        return "invalid", None, None, "invalid paymentHash"
    try:
        status, headers, doc, _code = _api_json_request(deps, "%s/%s" % (API_SUBSCRIPTION_URL, payment_hash.lower()), None)
    except ModuleError as exc:
        if exc.exit_code == EXIT_API_UNAVAILABLE:
            return "failed", None, None, exc.message
        return "invalid", None, None, exc.message
    if status in (200, 202) and isinstance(doc, dict):
        doc_type = doc.get("type")
        if doc_type is not None and str(doc_type).strip().lower() != "bandwidth_reset":
            return "invalid", None, None, "unexpected subscription type for bandwidth reset"
        raw_st = str(doc.get("status") or "").strip().lower()
        if status == 202 or raw_st == "processing":
            return "ok", "processing", doc, ""
        if raw_st in ("pending", "awaiting_payment", "unpaid"):
            return "ok", "pending", doc, ""
        if raw_st in ("paid", "claimed", "expired", "failed"):
            return "ok", raw_st, doc, ""
        return "invalid", None, None, "unexpected reset status value"
    if status == 404:
        return "not_found", None, None, "reset not found"
    if status == 429:
        retry = headers.get("retry-after", "60")
        return "failed", None, None, "rate limited, retry in %s s" % (retry if str(retry).isdigit() else "60")
    if status >= 500:
        return "failed", None, None, "the TunnelSats API is unavailable (HTTP %d)" % status
    return "invalid", None, None, "unexpected API answer (HTTP %d)" % status


def assemble_claimed_config(claim_doc, private_key, expected_public_key):
    """Concept 4.4 Claim Trust Boundary: validates individual fields of a /subscription/claim response,
    never reads fullConfig/config/peer.privateKey, verifies peer.publicKey matches the locally derived
    public key, and builds and re-parses the canonical WireGuard config. Raises ModuleError(E_CLAIM_INVALID).
    The body of a client-held key order (API docs, ClaimResult): server {endpoint, publicKey, allowedIPs},
    peer {address, publicKey, presharedKey}, vpnPort, subscriptionEnd."""
    def bad(msg):
        return ModuleError("E_CLAIM_INVALID", "invalid_response", msg, EXIT_INVALID_API)

    if not isinstance(claim_doc, dict):
        raise bad("claim response is not a JSON object")
    if not isinstance(private_key, str) or not KEY_RE.fullmatch(private_key):
        raise bad("local private key is missing or invalid")
    derived_pub = public_key_of(private_key)
    if derived_pub != expected_public_key:
        raise bad("local public key does not match the derived public key")
    peer = claim_doc.get("peer")
    server = claim_doc.get("server")
    if not isinstance(peer, dict) or not isinstance(server, dict):
        raise bad("claim response is missing peer or server object")
    if peer.get("publicKey") != derived_pub:
        raise bad("claim peer.publicKey does not match local public key")
    peer_ip_raw = peer.get("address")
    if not isinstance(peer_ip_raw, str) or not peer_ip_raw.strip():
        raise bad("claim peer.address is missing")
    peer_ip_str = peer_ip_raw.strip() if "/" in peer_ip_raw.strip() else peer_ip_raw.strip() + "/32"
    try:
        iface = ipaddress.IPv4Interface(peer_ip_str)
    except ValueError:
        raise bad("claim peer.address is not a valid IPv4 address") from None
    if iface.network.prefixlen != 32 or iface.ip not in ipaddress.IPv4Network("10.0.0.0/8"):
        raise bad("claim peer.address must be a /32 address inside 10.0.0.0/8")
    psk = peer.get("presharedKey")
    if psk is not None and psk != "":
        if not isinstance(psk, str) or not KEY_RE.fullmatch(psk.strip()):
            raise bad("claim peer.presharedKey is not a valid WireGuard key")
        psk = psk.strip()
    else:
        psk = None
    vpn_port = claim_doc.get("vpnPort")
    if not valid_port(vpn_port):
        raise bad("claim vpnPort is missing or outside 1..65535")
    server_pub = server.get("publicKey")
    if not isinstance(server_pub, str) or not KEY_RE.fullmatch(server_pub.strip()):
        raise bad("claim server.publicKey is not a valid WireGuard key")
    server_pub = server_pub.strip()
    if server_pub == derived_pub:
        raise bad("claim server.publicKey equals the peer public key")
    endpoint_raw = server.get("endpoint")
    if not isinstance(endpoint_raw, str) or ":" not in endpoint_raw:
        raise bad("claim server.endpoint is missing or invalid")
    host, _sep, port_str = endpoint_raw.strip().rpartition(":")
    host = host.lower()
    if not valid_host(host) or not re.fullmatch(r"[0-9]{1,5}", port_str) or not valid_port(int(port_str)):
        raise bad("claim server.endpoint must be a *.tunnelsats.com host and valid port")
    endpoint_port = int(port_str)
    allowed_raw = server.get("allowedIPs", "0.0.0.0/0")
    if isinstance(allowed_raw, str):
        allowed_parts = [p.strip() for p in allowed_raw.split(",") if p.strip()]
    elif isinstance(allowed_raw, list) and all(isinstance(p, str) for p in allowed_raw):
        allowed_parts = [p.strip() for p in allowed_raw if p.strip()]
    else:
        raise bad("claim server.allowedIPs is invalid")
    allowed_ips = []
    for entry in allowed_parts:
        try:
            # the rule of IMPORT (parse_wg_config): IPv4 and IPv6 networks, 0.0.0.0/0 required below
            allowed_ips.append(str(ipaddress.ip_network(entry, strict=False)))
        except ValueError:
            raise bad("claim server.allowedIPs holds an invalid network") from None
    if "0.0.0.0/0" not in allowed_ips:
        raise bad("claim server.allowedIPs must contain 0.0.0.0/0")
    keepalive = server.get("persistentKeepalive", 25)
    if isinstance(keepalive, bool) or not isinstance(keepalive, int) or not (0 <= keepalive <= 65535):
        raise bad("claim server.persistentKeepalive is invalid")
    mtu = server.get("mtu")
    if mtu is not None:
        if isinstance(mtu, bool) or not isinstance(mtu, int) or not (1280 <= mtu <= 1500):
            raise bad("claim server.mtu must be 1280-1500")
    sub_end = claim_doc.get("subscriptionEnd")
    if not isinstance(sub_end, str) or not sub_end.strip():
        raise bad("claim subscriptionEnd is missing")
    sub_end_str = sub_end.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", sub_end_str):
        sub_end_str = sub_end_str + "T00:00:00Z"
    sub_dt = parse_iso(sub_end_str)
    if sub_dt is None:
        raise bad("claim subscriptionEnd is not a valid ISO-8601 date/timestamp")
    valid_until = iso(sub_dt)
    cfg = {
        "private_key": private_key,
        "addresses": [str(iface)],
        "mtu": mtu,
        "peer_public_key": server_pub,
        "preshared_key": psk,
        "endpoint_host": host,
        "endpoint_port": endpoint_port,
        "allowed_ips": allowed_ips,
        "keepalive": keepalive,
        "vpn_port": vpn_port,
        "valid_until": valid_until,
        "public_key": derived_pub,
        "public_key_matches": True,
        "warnings": [],
    }
    try:
        return parse_wg_config(render_wg_config(cfg))
    except ModuleError as exc:
        raise bad("assembled config failed validation: %s" % exc.message) from None


def show_qr(deps, invoice):
    """Displays an uppercased BOLT11 QR code on the terminal and LCD when available."""
    if not isinstance(invoice, str) or not invoice.strip():
        return
    upper = invoice.strip().upper()
    rc, out, _err = deps.run(["qrencode", "-t", "ANSIUTF8", "-m", "2", upper], timeout=15)
    if rc == 0 and out:
        sys.stderr.write(out + "\n")
    deps.run([BLITZ_DISPLAY, "qr", upper], timeout=15)


def hide_qr(deps):
    deps.run([BLITZ_DISPLAY, "hide"], timeout=15)


def _buy_fields(order, reused=False):
    return {
        "state": order["state"],
        "reused": reused,
        "order_id": order["order_id"],
        "payment_hash": order["payment_hash"],
        "server_id": order["server_id"],
        "months": order["months"],
        "duration": order["months"],
        "amount_sats": order["amount_sats"],
        "amount_check": {
            "match": True,
            "invoice_sats": order["amount_sats"],
            "api_sats": order["amount_sats"],
        },
        "public_key": order["public_key"],
        "created_at": order["created_at"],
        "invoice_expires_at": order["invoice_expires_at"],
        "retained_until": order["retained_until"],
        "node_payment": dict(order.get("node_payment") or {"state": "none", "result": None}),
    }


def cmd_buy(deps, args, result):
    if not isinstance(args.server, str) or not SERVER_ID_RE.fullmatch(args.server):
        raise ModuleError("E_USAGE", "usage", "invalid --server id", EXIT_USAGE)
    if args.months not in DURATIONS:
        raise ModuleError("E_USAGE", "usage", "--months must be 1, 3, 6, or 12", EXIT_USAGE)
    if args.pay not in PAY_MODES:
        raise ModuleError("E_USAGE", "usage", "--pay must be node, qr, copy, or none", EXIT_USAGE)
    if args.pay == "node" and not getattr(args, "yes", False):
        raise ModuleError("E_CONFIRMATION_REQUIRED", "usage",
                          "--pay node requires --yes (or create the invoice first and run pay-node --yes)", EXIT_USAGE)
    if load_state(deps) is not None:
        raise ModuleError("E_ALREADY_CONFIGURED", "refused",
                          "a subscription is already stored on this node: use renew or remove it first", EXIT_REFUSED)
    found = detect(deps, getattr(args, "impl", None))
    result.fields["detect"] = {"eligible": found["eligible"], "reasons": found["reasons"]}
    if found["reasons"]:
        raise ModuleError("E_NOT_ELIGIBLE", "not_eligible", "not eligible: %s" % ", ".join(found["reasons"]),
                          EXIT_NOT_CONFIGURED)
    impl = found["impl"]
    with Lock(deps, wait=30):
        pending = prune_pending(deps)
        cur = pending.get("order")
        shred_first = False
        reused = False
        if isinstance(cur, dict):
            if _item_protected_from_prune(cur):
                raise ModuleError("E_ORDER_PENDING", "refused",
                                  "an existing order is already paid or awaiting claim/support: run settle first",
                                  EXIT_REFUSED)
            exp = parse_iso(cur.get("invoice_expires_at"))
            if (cur.get("state") == "awaiting_payment" and cur.get("server_id") == args.server
                    and cur.get("months") == args.months and exp and deps.clock() < exp):
                deps.run([ITS, "tick-timer", "on"], timeout=60)
                result.fields.update(_buy_fields(cur, reused=True))
                if args.pay == "qr" and not args.json:
                    show_qr(deps, cur.get("invoice"))
                reused = True
            else:
                if HEX64_RE.fullmatch(str(cur.get("payment_hash") or "")):
                    p_out, p_status, _p_doc, _p_det = poll_order_status(deps, cur["payment_hash"])
                    if p_out == "ok" and p_status in ("paid", "claimed", "processing"):
                        cur["state"] = "paid"
                        save_pending(deps, pending)
                        raise ModuleError("E_ORDER_PENDING", "refused",
                                          "the existing order has been paid: run settle to claim and activate it",
                                          EXIT_REFUSED)
                sup = dict(cur, state="superseded" if cur.get("state") == "awaiting_payment" else cur.get("state"))
                retained = list(pending.get("retained_orders") or []) + [sup]
                if len(retained) > MAX_RETAINED_ORDERS:
                    protected = [x for x in retained if _item_protected_from_prune(x)]
                    unprotected = [x for x in retained if not _item_protected_from_prune(x)]
                    keep_count = max(0, MAX_RETAINED_ORDERS - len(protected))
                    evicted = unprotected[:max(0, len(unprotected) - keep_count)]
                    if any(x.get("private_key") for x in evicted):
                        shred_first = True
                    retained = protected + (unprotected[-keep_count:] if keep_count else [])
                pending["retained_orders"] = retained
                pending["order"] = None
        if not reused:
            priv_key, pub_key = generate_wg_keypair()
            status, _headers, doc, _code = _api_json_request(
                deps, API_CREATE_URL, {"serverId": args.server, "duration": args.months, "wgPublicKey": pub_key}
            )
            if status == 429:
                raise ModuleError("E_RATE_LIMITED", "retryable", "rate limited by the TunnelSats API", EXIT_API_UNAVAILABLE)
            if status >= 500:
                raise ModuleError("E_API_UNAVAILABLE", "retryable",
                                  "the TunnelSats API is unavailable (HTTP %d)" % status, EXIT_API_UNAVAILABLE)
            if status not in (200, 201) or not isinstance(doc, dict):
                raise ModuleError("E_API_INVALID", "invalid_response",
                                  "unexpected create response (HTTP %d)" % status, EXIT_INVALID_API)
            payment_hash = str(doc.get("paymentHash") or "").strip().lower()
            if not HEX64_RE.fullmatch(payment_hash):
                raise ModuleError("E_API_INVALID", "invalid_response",
                                  "create response is missing a 64-hex paymentHash", EXIT_INVALID_API)
            raw_order_id = doc.get("orderId") if doc.get("orderId") is not None else doc.get("id")
            order_id = str(raw_order_id).strip() if raw_order_id is not None else payment_hash[:16]
            if not ORDER_ID_RE.fullmatch(order_id):
                raise ModuleError("E_API_INVALID", "invalid_response",
                                  "create response has an invalid orderId", EXIT_INVALID_API)
            invoice = doc.get("invoice") if doc.get("invoice") is not None else doc.get("paymentRequest")
            api_sats = doc.get("amountSats")
            if isinstance(api_sats, bool) or not isinstance(api_sats, int) or api_sats <= 0:
                raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                                  "create response is missing a positive integer amountSats", EXIT_INVALID_API)
            decoded = verify_bolt11_invoice(invoice, payment_hash, expected_sats=api_sats)
            now = deps.clock()
            created_at = iso(now)
            exp_dt = now + datetime.timedelta(seconds=decoded["expiry_seconds"])
            ret_dt = now + datetime.timedelta(seconds=PENDING_TTL_SECONDS)
            order_record = {
                "order_id": order_id,
                "payment_hash": payment_hash,
                "invoice": invoice.strip(),
                "amount_sats": decoded["amount_sats"],
                "server_id": args.server,
                "months": args.months,
                "impl": impl,
                "private_key": priv_key,
                "public_key": pub_key,
                "created_at": created_at,
                "invoice_expires_at": iso(exp_dt),
                "retained_until": iso(ret_dt),
                "state": "awaiting_payment",
                "node_payment": {"state": "none", "result": None},
            }
            pending["order"] = order_record
            save_pending(deps, pending, shred_first=shred_first)
            deps.run([ITS, "tick-timer", "on"], timeout=60)
            result.fields.update(_buy_fields(order_record, reused=False))
            if args.pay == "qr" and not args.json:
                show_qr(deps, order_record["invoice"])
    if args.pay == "node":
        _pay_pending_item_via_node(deps, "order", impl, result)


def _renew_fields(renewal, reused=False):
    return {
        "state": renewal["state"],
        "reused": reused,
        "renewal_id": renewal["renewal_id"],
        "payment_hash": renewal["payment_hash"],
        "server_id": renewal["server_id"],
        "months": renewal["months"],
        "duration": renewal["months"],
        "amount_sats": renewal["amount_sats"],
        "old_expiry": renewal.get("old_expiry"),
        "new_expiry": renewal.get("new_expiry"),
        "public_key": renewal["public_key"],
        "created_at": renewal["created_at"],
        "invoice_expires_at": renewal["invoice_expires_at"],
        "retained_until": renewal["retained_until"],
        "node_payment": dict(renewal.get("node_payment") or {"state": "none", "result": None}),
    }


def _derive_server_id(state):
    dom = (((state.get("api") or {}).get("data") or {}).get("server_domain")
           or state.get("server_domain") or state.get("endpoint_host") or "")
    dom = str(dom).strip().lower()
    if dom.endswith(".tunnelsats.com"):
        dom = dom[:-len(".tunnelsats.com")]
    return dom


def cmd_renew(deps, args, result):
    if args.months not in DURATIONS:
        raise ModuleError("E_USAGE", "usage", "--months must be 1, 3, 6, or 12", EXIT_USAGE)
    if args.pay not in PAY_MODES:
        raise ModuleError("E_USAGE", "usage", "--pay must be node, qr, copy, or none", EXIT_USAGE)
    if args.pay == "node" and not getattr(args, "yes", False):
        raise ModuleError("E_CONFIRMATION_REQUIRED", "usage",
                          "--pay node requires --yes (or create the invoice first and run pay-node --yes)", EXIT_USAGE)
    state = load_state(deps)
    if state is None or not state.get("public_key"):
        raise ModuleError("E_NOT_CONFIGURED", "not_configured",
                          "no TunnelSats subscription is stored on this node", EXIT_NOT_CONFIGURED)
    server_id = _derive_server_id(state)
    if not SERVER_ID_RE.fullmatch(server_id):
        raise ModuleError("E_STORED_CONFIG", "operational",
                          "stored server domain is missing or invalid", EXIT_OPERATIONAL)
    old_expiry = ((state.get("api") or {}).get("data") or {}).get("expiry") or state.get("valid_until")
    with Lock(deps, wait=30):
        pending = prune_pending(deps)
        cur = pending.get("renewal")
        reused = False
        if isinstance(cur, dict):
            if _item_protected_from_prune(cur):
                raise ModuleError("E_RENEWAL_PENDING", "refused",
                                  "an existing renewal is already paid or awaiting confirmation: run settle first",
                                  EXIT_REFUSED)
            exp = parse_iso(cur.get("invoice_expires_at"))
            if (cur.get("state") == "awaiting_payment" and cur.get("months") == args.months
                    and cur.get("public_key") == state["public_key"] and exp and deps.clock() < exp):
                deps.run([ITS, "tick-timer", "on"], timeout=60)
                result.fields.update(_renew_fields(cur, reused=True))
                if args.pay == "qr" and not args.json:
                    show_qr(deps, cur.get("invoice"))
                reused = True
            elif HEX64_RE.fullmatch(str(cur.get("payment_hash") or "")):
                p_out, p_status, _p_doc, _p_det = poll_order_status(deps, cur["payment_hash"])
                if p_out == "ok" and p_status in ("paid", "claimed", "processing"):
                    cur["state"] = "paid"
                    save_pending(deps, pending)
                    raise ModuleError("E_RENEWAL_PENDING", "refused",
                                      "the existing renewal has been paid: run settle first",
                                      EXIT_REFUSED)
        if not reused:
            status, _headers, doc, code = _api_json_request(
                deps, API_RENEW_URL,
                {"serverId": server_id, "duration": args.months, "wgPublicKey": state["public_key"]},
            )
            if status == 404 and code == "ERR_RESOURCE_NOT_FOUND":
                raise ModuleError("E_UNKNOWN_KEY", "refused",
                                  "TunnelSats knows no subscription for this key", EXIT_REFUSED)
            if status == 403 and code == "ERR_MIGRATION_REQUIRED":
                raise ModuleError("E_MIGRATION_REQUIRED", "refused",
                                  "this subscription has to be migrated on tunnelsats.com first", EXIT_REFUSED)
            if status == 429:
                raise ModuleError("E_RATE_LIMITED", "retryable", "rate limited by the TunnelSats API", EXIT_API_UNAVAILABLE)
            if status >= 500:
                raise ModuleError("E_API_UNAVAILABLE", "retryable",
                                  "the TunnelSats API is unavailable (HTTP %d)" % status, EXIT_API_UNAVAILABLE)
            if status not in (200, 201) or not isinstance(doc, dict):
                raise ModuleError("E_API_INVALID", "invalid_response",
                                  "unexpected renew response (HTTP %d)" % status, EXIT_INVALID_API)
            payment_hash = str(doc.get("paymentHash") or "").strip().lower()
            if not HEX64_RE.fullmatch(payment_hash):
                raise ModuleError("E_API_INVALID", "invalid_response",
                                  "renew response is missing a 64-hex paymentHash", EXIT_INVALID_API)
            raw_id = doc.get("renewalId") if doc.get("renewalId") is not None else doc.get("orderId")
            renewal_id = str(raw_id).strip() if raw_id is not None else payment_hash[:16]
            if not ORDER_ID_RE.fullmatch(renewal_id):
                raise ModuleError("E_API_INVALID", "invalid_response",
                                  "renew response has an invalid renewalId", EXIT_INVALID_API)
            invoice = doc.get("invoice") if doc.get("invoice") is not None else doc.get("paymentRequest")
            api_sats = doc.get("amountSats")
            decoded = verify_bolt11_invoice(invoice, payment_hash, expected_sats=api_sats, max_sats=MAX_RENEW_SATS)
            now = deps.clock()
            new_expiry = doc.get("newExpiry") or doc.get("subscriptionEnd")
            if not (isinstance(new_expiry, str) and parse_iso(new_expiry) is not None):
                base_dt = parse_iso(old_expiry)
                if base_dt is None and isinstance(old_expiry, str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", old_expiry):
                    base_dt = parse_iso(old_expiry + "T00:00:00Z")
                base_dt = max(base_dt, now) if base_dt is not None else now
                new_expiry = iso(base_dt + datetime.timedelta(days=30 * args.months))
            exp_dt = now + datetime.timedelta(seconds=decoded["expiry_seconds"])
            ret_dt = now + datetime.timedelta(seconds=PENDING_TTL_SECONDS)
            renewal_record = {
                "renewal_id": renewal_id,
                "payment_hash": payment_hash,
                "invoice": invoice.strip(),
                "amount_sats": decoded["amount_sats"],
                "server_id": server_id,
                "months": args.months,
                "old_expiry": old_expiry,
                "new_expiry": new_expiry,
                "public_key": state["public_key"],
                "created_at": iso(now),
                "invoice_expires_at": iso(exp_dt),
                "retained_until": iso(ret_dt),
                "state": "awaiting_payment",
                "node_payment": {"state": "none", "result": None},
            }
            pending["renewal"] = renewal_record
            save_pending(deps, pending)
            deps.run([ITS, "tick-timer", "on"], timeout=60)
            result.fields.update(_renew_fields(renewal_record, reused=False))
            if args.pay == "qr" and not args.json:
                show_qr(deps, renewal_record["invoice"])
    if args.pay == "node":
        _pay_pending_item_via_node(deps, "renewal", getattr(args, "impl", None), result)


def _reset_fields(reset, reused=False):
    return {
        "state": reset["state"],
        "reused": reused,
        "reset_id": reset["reset_id"],
        "payment_hash": reset["payment_hash"],
        "server_id": reset["server_id"],
        "amount_sats": reset["amount_sats"],
        "amount_check": {
            "match": True,
            "invoice_sats": reset["amount_sats"],
            "api_sats": reset["amount_sats"],
        },
        "public_key": reset["public_key"],
        "created_at": reset["created_at"],
        "invoice_expires_at": reset["invoice_expires_at"],
        "retained_until": reset["retained_until"],
        "old_resets": reset.get("old_resets"),
        "old_used_gb": reset.get("old_used_gb"),
        "node_payment": dict(reset.get("node_payment") or {"state": "none", "result": None}),
    }


def cmd_topup(deps, args, result):
    if args.pay not in PAY_MODES:
        raise ModuleError("E_USAGE", "usage", "--pay must be node, qr, copy, or none", EXIT_USAGE)
    if args.pay == "node" and not getattr(args, "yes", False):
        raise ModuleError("E_CONFIRMATION_REQUIRED", "usage",
                          "--pay node requires --yes (or create the invoice first and run pay-node --yes)", EXIT_USAGE)
    state = load_state(deps)
    if state is None or not state.get("public_key"):
        raise ModuleError("E_NOT_CONFIGURED", "not_configured",
                          "no TunnelSats subscription is stored on this node", EXIT_NOT_CONFIGURED)
    server_id = _derive_server_id(state)
    if not SERVER_ID_RE.fullmatch(server_id):
        raise ModuleError("E_STORED_CONFIG", "operational",
                          "stored server domain is missing or invalid", EXIT_OPERATIONAL)
    api_data = ((state.get("api") or {}).get("data") or {})
    old_resets = api_data.get("resets_this_month")
    old_used_gb = api_data.get("bandwidth_used_gb")
    with Lock(deps, wait=30):
        pending = prune_pending(deps)
        cur = pending.get("reset")
        reused = False
        if isinstance(cur, dict):
            if _item_protected_from_prune(cur):
                raise ModuleError("E_ORDER_PENDING", "refused",
                                  "an existing bandwidth reset is already paid or awaiting confirmation: run settle first",
                                  EXIT_REFUSED)
            exp = parse_iso(cur.get("invoice_expires_at"))
            if (cur.get("state") == "awaiting_payment" and cur.get("public_key") == state["public_key"]
                    and exp and deps.clock() < exp):
                if HEX64_RE.fullmatch(str(cur.get("payment_hash") or "")):
                    p_out, p_status, _p_doc, _p_det = poll_reset_status(deps, cur["payment_hash"])
                    if p_out == "ok" and p_status in ("paid", "claimed", "processing"):
                        cur["state"] = "paid"
                        save_pending(deps, pending)
                        raise ModuleError("E_ORDER_PENDING", "refused",
                                          "the existing bandwidth reset has been paid: run settle first",
                                          EXIT_REFUSED)
                    if p_out == "ok" and p_status == "failed":
                        cur["state"] = "needs_support"
                        cur["error_code"] = "E_RESET_FAILED"
                        cur["error_detail"] = "bandwidth reset failed on server after payment"
                        save_pending(deps, pending)
                        raise ModuleError("E_RESET_FAILED", "invalid_response", cur["error_detail"], EXIT_INVALID_API)
                deps.run([ITS, "tick-timer", "on"], timeout=60)
                result.fields.update(_reset_fields(cur, reused=True))
                if args.pay == "qr" and not args.json:
                    show_qr(deps, cur.get("invoice"))
                reused = True
            elif HEX64_RE.fullmatch(str(cur.get("payment_hash") or "")):
                p_out, p_status, _p_doc, _p_det = poll_reset_status(deps, cur["payment_hash"])
                if p_out == "ok" and p_status in ("paid", "claimed", "processing"):
                    cur["state"] = "paid"
                    save_pending(deps, pending)
                    raise ModuleError("E_ORDER_PENDING", "refused",
                                      "the existing bandwidth reset has been paid: run settle first",
                                      EXIT_REFUSED)
        if not reused:
            status, _headers, doc, code = _api_json_request(
                deps, API_RESET_URL, {"wgPublicKey": state["public_key"], "serverId": server_id}
            )
            if status == 404 and code == "ERR_RESOURCE_NOT_FOUND":
                raise ModuleError("E_UNKNOWN_KEY", "refused",
                                  "TunnelSats knows no subscription for this key", EXIT_REFUSED)
            if status == 403 and code == "ERR_MIGRATION_REQUIRED":
                raise ModuleError("E_MIGRATION_REQUIRED", "refused",
                                  "this subscription has to be migrated on tunnelsats.com first", EXIT_REFUSED)
            if status == 429:
                err_msg = str((doc or {}).get("message") or (doc or {}).get("error") or "")
                if code == "ERR_RESET_LIMIT_REACHED" or re.search(r"\bresets per month reached\b", err_msg, re.IGNORECASE):
                    raise ModuleError("E_RESET_LIMIT", "refused",
                                      "monthly bandwidth reset limit reached", EXIT_REFUSED)
                raise ModuleError("E_RATE_LIMITED", "retryable", "rate limited by the TunnelSats API", EXIT_API_UNAVAILABLE)
            if status >= 500:
                raise ModuleError("E_API_UNAVAILABLE", "retryable",
                                  "the TunnelSats API is unavailable (HTTP %d)" % status, EXIT_API_UNAVAILABLE)
            if status not in (200, 201) or not isinstance(doc, dict):
                raise ModuleError("E_API_INVALID", "invalid_response",
                                  "unexpected bandwidth-reset response (HTTP %d)" % status, EXIT_INVALID_API)
            payment_hash = str(doc.get("paymentHash") or "").strip().lower()
            if not HEX64_RE.fullmatch(payment_hash):
                raise ModuleError("E_API_INVALID", "invalid_response",
                                  "bandwidth-reset response is missing a 64-hex paymentHash", EXIT_INVALID_API)
            raw_id = doc.get("resetId") if doc.get("resetId") is not None else doc.get("orderId")
            reset_id = str(raw_id).strip() if raw_id is not None else payment_hash[:16]
            if not ORDER_ID_RE.fullmatch(reset_id):
                raise ModuleError("E_API_INVALID", "invalid_response",
                                  "bandwidth-reset response has an invalid resetId", EXIT_INVALID_API)
            invoice = doc.get("invoice") if doc.get("invoice") is not None else doc.get("paymentRequest")
            api_sats = doc.get("amountSats")
            if isinstance(api_sats, bool) or not isinstance(api_sats, int) or api_sats <= 0:
                raise ModuleError("E_INVOICE_MISMATCH", "invalid_response",
                                  "bandwidth-reset response is missing a positive integer amountSats", EXIT_INVALID_API)
            decoded = verify_bolt11_invoice(invoice, payment_hash, expected_sats=api_sats)
            now = deps.clock()
            api_exp = parse_iso(doc.get("expiresAt"))
            exp_dt = api_exp if (api_exp is not None and api_exp > now) else (now + datetime.timedelta(seconds=decoded["expiry_seconds"]))
            ret_dt = now + datetime.timedelta(seconds=PENDING_TTL_SECONDS)
            reset_record = {
                "reset_id": reset_id,
                "payment_hash": payment_hash,
                "invoice": invoice.strip(),
                "amount_sats": decoded["amount_sats"],
                "server_id": server_id,
                "public_key": state["public_key"],
                "created_at": iso(now),
                "invoice_expires_at": iso(exp_dt),
                "retained_until": iso(ret_dt),
                "state": "awaiting_payment",
                "old_resets": old_resets,
                "old_used_gb": old_used_gb,
                "node_payment": {"state": "none", "result": None},
            }
            pending["reset"] = reset_record
            save_pending(deps, pending)
            deps.run([ITS, "tick-timer", "on"], timeout=60)
            result.fields.update(_reset_fields(reset_record, reused=False))
            if args.pay == "qr" and not args.json:
                show_qr(deps, reset_record["invoice"])
    if args.pay == "node":
        _pay_pending_item_via_node(deps, "reset", getattr(args, "impl", None), result)


def cmd_invoice(deps, args, result):
    if args.kind not in ("order", "renewal", "reset"):
        raise ModuleError("E_USAGE", "usage", "--kind must be order, renewal, or reset", EXIT_USAGE)
    with Lock(deps, wait=30):
        pending = prune_pending(deps)
        item = pending.get(args.kind)
        if not isinstance(item, dict) or not item.get("invoice"):
            raise ModuleError("E_NO_PENDING", "not_configured",
                              "no pending %s found" % args.kind, EXIT_NOT_CONFIGURED)
        if item.get("state") == "expired_unpaid":
            raise ModuleError("E_INVOICE_EXPIRED", "refused",
                              "the %s invoice has expired" % args.kind, EXIT_REFUSED)
        qr_png = None
        if getattr(args, "qr_png", None):
            out_path = str(args.qr_png).strip()
            if not out_path or "\x00" in out_path or os.path.islink(out_path):
                raise ModuleError("E_USAGE", "usage", "invalid --qr-png path", EXIT_USAGE)
            rc, _out, _err = deps.run(
                ["qrencode", "-o", out_path, "-s", "6", "-m", "2", item["invoice"].upper()],
                timeout=15,
            )
            if rc != 0:
                raise ModuleError("E_QR_FAILED", "operational",
                                  "qrencode could not write %s" % out_path, EXIT_OPERATIONAL)
            qr_png = out_path
        result.fields.update({
            "kind": args.kind,
            "state": item.get("state"),
            "payment_hash": item.get("payment_hash"),
            "invoice": item["invoice"],
            "amount_sats": item.get("amount_sats"),
            "invoice_expires_at": item.get("invoice_expires_at"),
            "qr_png": qr_png,
        })
        if not args.json and not qr_png:
            show_qr(deps, item["invoice"])


def cmd_pending(deps, args, result):
    with Lock(deps, wait=30):
        pending = prune_pending(deps)
    result.fields.update({
        "order": redact_pending_item(pending.get("order")),
        "renewal": redact_pending_item(pending.get("renewal")),
        "reset": redact_pending_item(pending.get("reset")),
        "retained_orders": [redact_pending_item(x) for x in (pending.get("retained_orders") or [])],
        "recovered_configs": list(pending.get("recovered_configs") or []),
    })


def can_unattended_restart(deps, impl):
    """True when Lightning can be restarted unattended (auto-unlock enabled, or the unit is not running)."""
    conf = read_rb_conf(deps)
    unit = UNITS.get(impl, "lnd.service")
    active = unit_props(deps, unit, "ActiveState")["ActiveState"]
    if active in ("inactive", "failed", ""):
        return True
    if impl == "lnd":
        return conf.get("autoUnlock") == "on"
    return conf.get("clEncryptedHSM") != "on" or conf.get("clAutoUnlock") == "on"


def _claim_and_store_order(deps, pending, order, result, foreground=True, notify_event=None, is_retained=False):
    """Claims a paid order, validates the config via assemble_claimed_config, and either activates it
    or stores it as recovered / activation_pending."""
    order["state"] = "claiming"
    save_pending(deps, pending)
    try:
        status, _headers, doc, _code = _api_json_request(
            deps, API_CLAIM_URL, {"paymentHash": order["payment_hash"], "wgPublicKey": order["public_key"]}
        )
    except ModuleError as exc:
        if exc.exit_code == EXIT_API_UNAVAILABLE:
            if foreground:
                raise
            return {"done": False, "kind": "order", "state": "claiming",
                    "payment_hash": order["payment_hash"], "retryable": True}
        order["state"] = "needs_support"
        order["error_code"] = exc.code
        order["error_detail"] = exc.message
        save_pending(deps, pending)
        raise
    if status == 409:
        order["state"] = "needs_support"
        order["error_code"] = "E_CLAIM_CONFLICT"
        order["error_detail"] = "claim conflict (HTTP 409): public key or order was already claimed"
        save_pending(deps, pending)
        raise ModuleError("E_CLAIM_CONFLICT", "invalid_response", order["error_detail"], EXIT_INVALID_API)
    if status in (202, 402) or (isinstance(doc, dict) and str(doc.get("status") or "").strip().lower() == "processing"):
        # 202: paid, the API still provisions the tunnel; 402: the API does not see the payment yet.
        # Both ask the client to retry the claim, so the order stays in claiming for the next pass.
        return {"done": False, "kind": "order", "state": "claiming",
                "payment_hash": order["payment_hash"], "retryable": True}
    if status >= 500 or status == 429:
        if foreground:
            raise ModuleError("E_API_UNAVAILABLE", "retryable",
                              "the TunnelSats API is unavailable during claim (HTTP %d)" % status, EXIT_API_UNAVAILABLE)
        return {"done": False, "kind": "order", "state": "claiming",
                "payment_hash": order["payment_hash"], "retryable": True}
    if status not in (200, 201) or not isinstance(doc, dict):
        order["state"] = "needs_support"
        order["error_code"] = "E_CLAIM_INVALID"
        order["error_detail"] = "unexpected claim response (HTTP %d)" % status
        save_pending(deps, pending)
        raise ModuleError("E_CLAIM_INVALID", "invalid_response", order["error_detail"], EXIT_INVALID_API)
    try:
        cfg = assemble_claimed_config(doc, order["private_key"], order["public_key"])
    except ModuleError as exc:
        order["state"] = "needs_support"
        order["error_code"] = exc.code
        order["error_detail"] = exc.message
        save_pending(deps, pending)
        raise
    outcome, api_data, _detail = api_status(deps, cfg["public_key"])
    if outcome != "confirmed":
        outcome, api_data = "skipped", None
    cur_state = load_state(deps)
    if cur_state is not None and cur_state.get("public_key") != cfg["public_key"]:
        # Another subscription is already configured: save recovered-<order_id>.conf (0600)
        rec_name = "recovered-%s.conf" % re.sub(r"[^A-Za-z0-9_.-]", "_", str(order.get("order_id") or "order"))
        rec_path = "%s/%s" % (STATE_DIR, rec_name)
        ensure_dir(deps.path(STATE_DIR), 0o700)
        write_private(deps.path(rec_path), render_wg_config(cfg))
        pending.setdefault("recovered_configs", []).append({
            "order_id": order.get("order_id"),
            "payment_hash": order.get("payment_hash"),
            "public_key": cfg["public_key"],
            "file": rec_path,
            "recovered_at": now_iso(deps),
        })
        if is_retained:
            pending["retained_orders"] = [x for x in (pending.get("retained_orders") or []) if x is not order]
        else:
            pending["order"] = None
        save_pending(deps, pending, shred_first=True)
        return {"done": True, "kind": "order", "state": "recovered", "order_id": order.get("order_id"),
                "payment_hash": order.get("payment_hash"), "public_key": cfg["public_key"], "recovered_file": rec_path}
    impl = order.get("impl") if order.get("impl") in IMPLS else select_impl(read_rb_conf(deps))[0]
    if not foreground and not can_unattended_restart(deps, impl):
        store_subscription(deps, cfg, "managed", impl, outcome, api_data, {"activation_pending": True})
        if is_retained:
            pending["retained_orders"] = [x for x in (pending.get("retained_orders") or []) if x is not order]
        else:
            pending["order"] = None
        save_pending(deps, pending, shred_first=True)
        return {"done": True, "kind": "order", "state": "claimed_awaiting_unlock",
                "order_id": order.get("order_id"), "payment_hash": order.get("payment_hash"),
                "public_key": cfg["public_key"], "server_domain": cfg["endpoint_host"],
                "expiry": (api_data or {}).get("expiry") or cfg.get("valid_until")}
    activate(deps, impl, result,
             stored_writer=lambda: store_subscription(deps, cfg, "managed", impl, outcome, api_data,
                                                      {"activation_pending": False}))
    if is_retained:
        pending["retained_orders"] = [x for x in (pending.get("retained_orders") or []) if x is not order]
    else:
        pending["order"] = None
    save_pending(deps, pending, shred_first=True)
    if not tick_timer_needed(deps):
        deps.run([ITS, "tick-timer", "off"], timeout=60)
    return {"done": True, "kind": "order", "state": "active", "impl": impl,
            "order_id": order.get("order_id"), "payment_hash": order.get("payment_hash"),
            "public_key": cfg["public_key"],
            "server_domain": (api_data or {}).get("server_domain") or cfg["endpoint_host"],
            "expiry": (api_data or {}).get("expiry") or cfg.get("valid_until")}


def _settle_once_inner(deps, result, foreground=True, notify_event=None):
    finish_impl = None
    outcome_dict = None
    pending = prune_pending(deps)
    order = pending.get("order")
    renewal = pending.get("renewal")
    reset = pending.get("reset")
    retained = pending.get("retained_orders") or []
    if not order and not renewal and not reset and not retained:
        if foreground:
            raise ModuleError("E_NO_PENDING", "not_configured",
                              "no pending order, renewal, or reset to settle", EXIT_NOT_CONFIGURED)
        return {"done": False, "kind": None, "state": "none"}, None

    # 1. Active order
    if isinstance(order, dict):
        if order.get("state") == "needs_support":
            if foreground:
                raise ModuleError(order.get("error_code") or "E_CLAIM_INVALID", "invalid_response",
                                  order.get("error_detail") or "order requires support", EXIT_INVALID_API)
            return {"done": False, "kind": "order", "state": "needs_support",
                    "payment_hash": order.get("payment_hash")}, None
        if order.get("state") in ("awaiting_payment", "expired_unpaid"):
            p_out, p_status, _p_doc, _p_det = poll_order_status(deps, order.get("payment_hash"))
            if p_out == "ok" and p_status in ("paid", "claimed", "processing"):
                order["state"] = "paid"
                save_pending(deps, pending)
                if notify_event and not order.get("payment_notified"):
                    order["payment_notified"] = True
                    save_pending(deps, pending)
                    notify_event("payment_received", order.get("payment_hash"))
            elif p_out == "ok" and p_status == "expired" and not _item_protected_from_prune(order):
                order["state"] = "expired_unpaid"
                save_pending(deps, pending)
        if order.get("state") in ("paid", "claiming"):
            if notify_event and not order.get("payment_notified"):
                order["payment_notified"] = True
                save_pending(deps, pending)
                notify_event("payment_received", order.get("payment_hash"))
            try:
                outcome_dict = _claim_and_store_order(
                    deps, pending, order, result, foreground=foreground,
                    notify_event=notify_event, is_retained=False,
                )
                if outcome_dict.get("state") == "active":
                    finish_impl = outcome_dict.get("impl")
            except ModuleError:
                if foreground:
                    raise
                outcome_dict = {"done": False, "kind": "order", "state": order.get("state", "needs_support"),
                                "payment_hash": order.get("payment_hash")}

    # 2. Retained superseded orders
    if outcome_dict is None:
        for ret_order in list(retained):
            if not isinstance(ret_order, dict) or ret_order.get("state") == "needs_support":
                continue
            if ret_order.get("state") in ("awaiting_payment", "superseded", "expired_unpaid"):
                p_out, p_status, _p_doc, _p_det = poll_order_status(deps, ret_order.get("payment_hash"))
                if p_out == "ok" and p_status in ("paid", "claimed", "processing"):
                    ret_order["state"] = "paid"
                    save_pending(deps, pending)
            if ret_order.get("state") in ("paid", "claiming"):
                if notify_event and not ret_order.get("payment_notified"):
                    ret_order["payment_notified"] = True
                    save_pending(deps, pending)
                    notify_event("payment_received", ret_order.get("payment_hash"))
                try:
                    outcome_dict = _claim_and_store_order(
                        deps, pending, ret_order, result, foreground=foreground,
                        notify_event=notify_event, is_retained=True,
                    )
                    if outcome_dict.get("state") == "active":
                        finish_impl = outcome_dict.get("impl")
                except ModuleError:
                    if foreground:
                        raise
                    outcome_dict = {"done": False, "kind": "order", "state": ret_order.get("state", "needs_support"),
                                    "payment_hash": ret_order.get("payment_hash")}
                break

    # 3. Renewal
    if outcome_dict is None and isinstance(renewal, dict):
        if renewal.get("state") in ("awaiting_payment", "expired_unpaid"):
            p_out, p_status, _p_doc, _p_det = poll_order_status(deps, renewal.get("payment_hash"))
            if p_out == "ok" and p_status in ("paid", "claimed", "processing"):
                renewal["state"] = "paid"
                save_pending(deps, pending)
                if notify_event and not renewal.get("payment_notified"):
                    renewal["payment_notified"] = True
                    save_pending(deps, pending)
                    notify_event("payment_received", renewal.get("payment_hash"))
            elif p_out == "ok" and p_status == "expired" and not _item_protected_from_prune(renewal):
                renewal["state"] = "expired_unpaid"
                save_pending(deps, pending)
        if renewal.get("state") == "paid":
            if notify_event and not renewal.get("payment_notified"):
                renewal["payment_notified"] = True
                save_pending(deps, pending)
                notify_event("payment_received", renewal.get("payment_hash"))
            s_out, s_data, _s_det = api_status(deps, renewal.get("public_key"))
            old_dt = parse_iso(renewal.get("old_expiry"))
            if old_dt is None and isinstance(renewal.get("old_expiry"), str) and re.fullmatch(r"\d{4}-\d{2}-\d{2}", renewal["old_expiry"]):
                old_dt = parse_iso(renewal["old_expiry"] + "T00:00:00Z")
            new_dt = parse_iso((s_data or {}).get("expiry")) if s_out == "confirmed" else None
            if s_out == "confirmed" and new_dt is not None and (old_dt is None or new_dt > old_dt):
                state = load_state(deps) or {}
                state["valid_until"] = s_data["expiry"]
                state["api"] = {"outcome": "confirmed", "checked_at": now_iso(deps),
                                "data": s_data, "confirmed_at": now_iso(deps)}
                if isinstance(state.get("notify_state"), dict):
                    state["notify_state"]["expiry_cycle"] = s_data["expiry"]
                    for ev in ("expiry_soon", "expired"):
                        (state["notify_state"].get("events") or {}).pop(ev, None)
                save_state(deps, state)
                cfg = load_stored_config(deps)
                if cfg is not None:
                    cfg["valid_until"] = s_data["expiry"]
                    write_private(deps.path(CONF_FILE), render_wg_config(cfg))
                pending["renewal"] = None
                save_pending(deps, pending)
                outcome_dict = {
                    "done": True, "kind": "renewal", "state": "confirmed",
                    "renewal_id": renewal.get("renewal_id"), "payment_hash": renewal.get("payment_hash"),
                    "old_expiry": renewal.get("old_expiry"), "new_expiry": s_data["expiry"],
                    "expiry": s_data["expiry"],
                }
            else:
                outcome_dict = {
                    "done": False, "kind": "renewal", "state": "paid",
                    "renewal_id": renewal.get("renewal_id"), "payment_hash": renewal.get("payment_hash"),
                }

    # 4. Bandwidth reset
    if outcome_dict is None and isinstance(reset, dict):
        if reset.get("state") == "needs_support":
            if foreground:
                raise ModuleError(reset.get("error_code") or "E_RESET_FAILED", "invalid_response",
                                  reset.get("error_detail") or "bandwidth reset requires support", EXIT_INVALID_API)
            return {"done": False, "kind": "reset", "state": "needs_support",
                    "payment_hash": reset.get("payment_hash")}, None
        polled_reset = False
        p_out, p_status = None, None
        if reset.get("state") in ("awaiting_payment", "expired_unpaid"):
            polled_reset = True
            p_out, p_status, _p_doc, _p_det = poll_reset_status(deps, reset.get("payment_hash"))
            if p_out == "ok" and p_status in ("paid", "claimed", "processing"):
                reset["state"] = "paid"
                save_pending(deps, pending)
                if notify_event and not reset.get("payment_notified"):
                    reset["payment_notified"] = True
                    save_pending(deps, pending)
                    notify_event("payment_received", reset.get("payment_hash"))
            elif p_out == "ok" and p_status == "failed":
                reset["state"] = "needs_support"
                reset["error_code"] = "E_RESET_FAILED"
                reset["error_detail"] = "bandwidth reset failed on server after payment"
                save_pending(deps, pending)
                if foreground:
                    raise ModuleError("E_RESET_FAILED", "invalid_response", reset["error_detail"], EXIT_INVALID_API)
                return {"done": False, "kind": "reset", "state": "needs_support",
                        "payment_hash": reset.get("payment_hash")}, None
            elif p_out == "ok" and p_status == "expired" and not _item_protected_from_prune(reset):
                reset["state"] = "expired_unpaid"
                save_pending(deps, pending)
        if reset.get("state") == "paid":
            if notify_event and not reset.get("payment_notified"):
                reset["payment_notified"] = True
                save_pending(deps, pending)
                notify_event("payment_received", reset.get("payment_hash"))
            if not polled_reset:
                p_out, p_status, _p_doc, _p_det = poll_reset_status(deps, reset.get("payment_hash"))
                if p_out == "ok" and p_status == "failed":
                    reset["state"] = "needs_support"
                    reset["error_code"] = "E_RESET_FAILED"
                    reset["error_detail"] = "bandwidth reset failed on server after payment"
                    save_pending(deps, pending)
                    if foreground:
                        raise ModuleError("E_RESET_FAILED", "invalid_response", reset["error_detail"], EXIT_INVALID_API)
                    return {"done": False, "kind": "reset", "state": "needs_support",
                            "payment_hash": reset.get("payment_hash")}, None
            if p_out == "ok" and p_status == "processing":
                outcome_dict = {
                    "done": False, "kind": "reset", "state": "paid",
                    "reset_id": reset.get("reset_id"), "payment_hash": reset.get("payment_hash"),
                }
            else:
                s_out, s_data, _s_det = api_status(deps, reset.get("public_key"))
                old_resets = reset.get("old_resets")
                old_used = reset.get("old_used_gb")
                new_resets = (s_data or {}).get("resets_this_month") if s_out == "confirmed" else None
                new_used = (s_data or {}).get("bandwidth_used_gb") if s_out == "confirmed" else None
                reset_applied = (
                    s_out == "confirmed"
                    and (
                        p_status in ("paid", "claimed")
                        or (is_count(old_resets) and is_count(new_resets) and new_resets > old_resets)
                        or (is_number(old_used) and is_number(new_used) and new_used < old_used)
                    )
                )
                if reset_applied:
                    state = load_state(deps) or {}
                    state["valid_until"] = s_data["expiry"]
                    state["api"] = {"outcome": "confirmed", "checked_at": now_iso(deps),
                                    "data": s_data, "confirmed_at": now_iso(deps)}
                    if isinstance(state.get("notify_state"), dict):
                        state["notify_state"]["bandwidth_cycle"] = "%s:%s" % (
                            s_data.get("expiry") or state.get("valid_until") or "",
                            s_data.get("resets_this_month", 0),
                        )
                        for ev in ("bandwidth_high", "bandwidth_exhausted"):
                            (state["notify_state"].get("events") or {}).pop(ev, None)
                    save_state(deps, state)
                    pending["reset"] = None
                    save_pending(deps, pending)
                    outcome_dict = {
                        "done": True, "kind": "reset", "state": "confirmed",
                        "reset_id": reset.get("reset_id"), "payment_hash": reset.get("payment_hash"),
                        "bandwidth_used_gb": s_data.get("bandwidth_used_gb"),
                        "bandwidth_limit_gb": s_data.get("bandwidth_limit_gb"),
                        "resets_this_month": s_data.get("resets_this_month"),
                        "max_resets_per_month": s_data.get("max_resets_per_month"),
                        "peer_status": s_data.get("peer_status"),
                    }
                else:
                    outcome_dict = {
                        "done": False, "kind": "reset", "state": "paid",
                        "reset_id": reset.get("reset_id"), "payment_hash": reset.get("payment_hash"),
                    }

    if outcome_dict is None:
        active_item = order or renewal or reset or (retained[0] if retained else {})
        kind = "order" if (order or retained) else ("renewal" if renewal else "reset")
        outcome_dict = {
            "done": False, "kind": kind, "state": active_item.get("state", "awaiting_payment"),
            "payment_hash": active_item.get("payment_hash"),
        }
    return outcome_dict, finish_impl


def settle_once(deps, result, foreground=True, notify_event=None, use_lock=True):
    """Runs one settlement pass. Returns a dict with 'done' (bool), 'kind', 'state', and item metadata."""
    if use_lock:
        with Lock(deps, wait=30):
            outcome_dict, finish_impl = _settle_once_inner(deps, result, foreground=foreground, notify_event=notify_event)
    else:
        outcome_dict, finish_impl = _settle_once_inner(deps, result, foreground=foreground, notify_event=notify_event)
    if finish_impl is not None:
        finish_with_check(deps, result, wait_until_started(deps, UNITS[finish_impl]))
        outcome_dict["verdict"] = result.fields.get("verdict")
        if notify_event and result.fields.get("verdict") == "protected":
            notify_event("activation_done", outcome_dict.get("payment_hash"))
    return outcome_dict


def cmd_settle(deps, args, result):
    wait_seconds = max(0, int(getattr(args, "wait", 0) or 0))
    waited = 0
    while True:
        outcome = settle_once(deps, result, foreground=True)
        result.fields.update({k: v for k, v in outcome.items() if k != "done"})
        if outcome.get("done"):
            if outcome.get("state") == "confirmed":
                result.exit_code = EXIT_OK
            hide_qr(deps)
            return
        if waited >= wait_seconds:
            result.exit_code = EXIT_PENDING
            return
        step = min(5, wait_seconds - waited)
        deps.sleep(step)
        waited += step


# ------------------------------------------------------------------------------------------
# pay-node (LND and Core Lightning invoice payment with preflight and 1% fee cap)
# ------------------------------------------------------------------------------------------

def _parse_last_json(text):
    """Returns the last JSON object in text (e.g. from lncli payinvoice --json), or None."""
    if not isinstance(text, str) or not text.strip():
        return None
    one = parse_one_json(text)
    if one is not None:
        return one
    decoder = json.JSONDecoder()
    last_doc = None
    pos = 0
    while True:
        idx = text.find("{", pos)
        if idx < 0:
            break
        try:
            doc, end = decoder.raw_decode(text, idx)
            if isinstance(doc, dict):
                last_doc = doc
                pos = max(idx + 1, end)
                continue
        except ValueError:
            pass
        pos = idx + 1
    return last_doc


def _parse_msat(value):
    """Parses a Core Lightning msat value (integer or '<N>msat' string) into an int, or None."""
    if isinstance(value, int) and not isinstance(value, bool) and value >= 0:
        return value
    if isinstance(value, str):
        raw = value.strip().lower()
        if raw.endswith("msat"):
            raw = raw[:-4]
        if raw.isdigit():
            return int(raw)
    return None


def _verify_preimage(preimage_hex, expected_payment_hash):
    """True when preimage_hex is 64 hex chars whose SHA-256 equals expected_payment_hash."""
    if not isinstance(preimage_hex, str) or not HEX64_RE.fullmatch(preimage_hex.strip().lower()):
        return False
    digest = hashlib.sha256(bytes.fromhex(preimage_hex.strip().lower())).hexdigest()
    return digest == expected_payment_hash.lower()


def _map_lnd_pay_error(doc, stdout_text, stderr_text):
    combined = " ".join([
        str((doc or {}).get("failure_reason") or ""),
        str((doc or {}).get("payment_error") or ""),
        str(stdout_text or ""),
        str(stderr_text or ""),
    ]).lower()
    if any(k in combined for k in ("failure_reason_no_route", "no_route", "no route", "unable to find a path")):
        return "E_PAY_NO_ROUTE"
    if any(k in combined for k in ("failure_reason_insufficient_balance", "insufficient_balance",
                                   "insufficient local balance", "insufficient balance", "channel balance")):
        return "E_PAY_INSUFFICIENT_BALANCE"
    if any(k in combined for k in ("failure_reason_timeout", "timeout", "timed out")):
        return "E_PAY_TIMEOUT"
    if any(k in combined for k in ("failure_reason_incorrect_payment_details", "incorrect_payment_details",
                                   "unknown_payment_hash")):
        return "E_PAY_INCORRECT_DETAILS"
    if "expired" in combined:
        return "E_PAY_EXPIRED"
    return "E_PAY_ERROR"


def _map_cln_pay_error(doc, stdout_text, stderr_text):
    code = doc.get("code") if isinstance(doc, dict) else None
    combined = " ".join([
        str((doc or {}).get("message") or ""),
        str(stdout_text or ""),
        str(stderr_text or ""),
    ]).lower()
    if any(k in combined for k in ("insufficient", "not enough funds", "unaffordable", "could not afford",
                                   "cannot afford")):
        return "E_PAY_INSUFFICIENT_BALANCE"
    if code in (205, 206) or any(k in combined for k in ("no route", "route not found", "failed to find route")):
        return "E_PAY_NO_ROUTE"
    if code == 207 or "expired" in combined:
        return "E_PAY_EXPIRED"
    if code == 210:
        return "E_PAY_NO_ROUTE" if "route" in combined else "E_PAY_TIMEOUT"
    if any(k in combined for k in ("timeout", "timed out")):
        return "E_PAY_TIMEOUT"
    if any(k in combined for k in ("incorrect", "unknown payment details")):
        return "E_PAY_INCORRECT_DETAILS"
    return "E_PAY_ERROR"


def _pay_pending_item_via_node(deps, kind_arg, impl_arg, result):
    """Pays the selected pending invoice via LND or Core Lightning with 3-step preflight and 1% fee cap,
    then settles the item."""
    with Lock(deps, wait=30):
        pending = prune_pending(deps)
        if kind_arg in ("order", "renewal", "reset"):
            kind = kind_arg
            item = pending.get(kind)
        else:
            kind, item = None, None
            for k in ("order", "renewal", "reset"):
                cand = pending.get(k)
                if isinstance(cand, dict) and cand.get("state") == "awaiting_payment":
                    kind, item = k, cand
                    break
            if item is None:
                for k in ("order", "renewal", "reset"):
                    cand = pending.get(k)
                    if isinstance(cand, dict):
                        kind, item = k, cand
                        break
        if not isinstance(item, dict) or not item.get("invoice"):
            raise ModuleError("E_NO_PENDING", "not_configured",
                              "no pending %s invoice to pay" % (kind_arg or "subscription"), EXIT_NOT_CONFIGURED)
        result.fields["kind"] = kind
        result.fields["payment_hash"] = item.get("payment_hash")
        if item.get("state") in ("paid", "claiming"):
            raise ModuleError("E_ALREADY_PAID", "refused",
                              "this %s invoice is already marked paid: run settle" % kind, EXIT_REFUSED)
        if item.get("state") == "needs_support":
            raise ModuleError(item.get("error_code") or "E_CLAIM_INVALID", "invalid_response",
                              item.get("error_detail") or "%s requires support" % kind, EXIT_INVALID_API)
        np = item.get("node_payment") or {}
        if np.get("state") in ("paying", "uncertain"):
            raise ModuleError("E_PAY_IN_FLIGHT", "pay_failed",
                              "a node payment for this %s is already in flight or uncertain: run settle first" % kind,
                              EXIT_PAY_FAILED)
        exp_dt = parse_iso(item.get("invoice_expires_at"))
        if item.get("state") == "expired_unpaid" or (exp_dt is not None and deps.clock() >= exp_dt):
            item["state"] = "expired_unpaid"
            save_pending(deps, pending)
            raise ModuleError("E_INVOICE_EXPIRED", "refused", "the %s invoice has expired" % kind, EXIT_REFUSED)
        invoice = str(item.get("invoice") or "").strip()
        payment_hash = str(item.get("payment_hash") or "").strip().lower()
        decoded = verify_bolt11_invoice(invoice, payment_hash, expected_sats=item.get("amount_sats"),
                                        max_sats=MAX_RENEW_SATS)
        amount_sats = decoded["amount_sats"]
        fee_limit_sats = max(int(math.ceil(amount_sats * 0.01)), 10)
        fee_limit_msat = fee_limit_sats * 1000
        state = load_state(deps)
        conf = read_rb_conf(deps)
        impl = (impl_arg or item.get("impl") or (state or {}).get("impl")
                or conf.get("tunnelsatsImpl") or select_impl(conf)[0])
        if impl not in IMPLS:
            raise ModuleError("E_PAY_NODE_LOCKED", "pay_failed",
                              "no active Lightning implementation (lnd or cl) available for node payment",
                              EXIT_PAY_FAILED)

        def fail_node_pay(code, msg, exit_code=EXIT_PAY_FAILED, cls="pay_failed", np_state="failed", np_result="failed"):
            item["node_payment"] = {
                "state": np_state,
                "result": np_result,
                "impl": impl,
                "error_code": code,
                "fee_limit_sats": fee_limit_sats,
                "attempted_at": now_iso(deps),
            }
            save_pending(deps, pending)
            result.fields.update({
                "kind": kind,
                "state": item.get("state"),
                "payment_hash": payment_hash,
                "amount_sats": amount_sats,
                "fee_limit_sats": fee_limit_sats,
                "node_payment": dict(item["node_payment"]),
            })
            raise ModuleError(code, cls, msg, exit_code)

        # Preflight 1: Live API poll before paying (never pay twice)
        if kind == "reset":
            p_out, p_status, _p_doc, _p_det = poll_reset_status(deps, payment_hash)
        else:
            p_out, p_status, _p_doc, _p_det = poll_order_status(deps, payment_hash)
        if p_out == "ok" and p_status in ("paid", "claimed", "processing"):
            item["state"] = "paid"
            save_pending(deps, pending)
            raise ModuleError("E_ALREADY_PAID", "refused",
                              "the TunnelSats API reports this %s invoice is already paid" % kind, EXIT_REFUSED)
        if p_out == "ok" and p_status == "expired":
            item["state"] = "expired_unpaid"
            save_pending(deps, pending)
            raise ModuleError("E_INVOICE_EXPIRED", "refused",
                              "the TunnelSats API reports this %s invoice has expired" % kind, EXIT_REFUSED)
        if p_out == "ok" and p_status == "failed":
            item["state"] = "needs_support"
            item["error_code"] = "E_RESET_FAILED" if kind == "reset" else "E_CLAIM_INVALID"
            item["error_detail"] = "%s failed on server" % kind
            save_pending(deps, pending)
            raise ModuleError(item["error_code"], "invalid_response", item["error_detail"], EXIT_INVALID_API)

        # Preflight 2: Node payment history check (listpayments / listpays)
        if impl == "lnd":
            rc, out, _err = deps.run(LNCLI + ["listpayments", "--include_incomplete"], timeout=30)
            lp_doc = parse_one_json(out) if rc == 0 else None
            if rc != 0 or not isinstance(lp_doc, dict):
                fail_node_pay("E_PAY_NODE_LOCKED", "LND did not answer listpayments (wallet locked or unavailable)")
            for p in lp_doc.get("payments") or []:
                if not isinstance(p, dict) or str(p.get("payment_hash") or "").strip().lower() != payment_hash:
                    continue
                p_st = str(p.get("status") or "").upper()
                if p_st == "SUCCEEDED":
                    item["state"] = "paid"
                    item["node_payment"] = {
                        "state": "succeeded", "result": "succeeded", "impl": impl,
                        "fee_limit_sats": fee_limit_sats, "paid_at": now_iso(deps),
                    }
                    save_pending(deps, pending)
                    raise ModuleError("E_ALREADY_PAID", "refused", "LND already paid this invoice", EXIT_REFUSED)
                if p_st in ("IN_FLIGHT", "INITIATED"):
                    fail_node_pay("E_PAY_IN_FLIGHT",
                                  "LND reports a payment for this invoice is already in flight",
                                  np_state="uncertain", np_result="uncertain")
        else:
            rc, out, _err = deps.run(CLNCLI + ["listpays", "bolt11=" + invoice], timeout=30)
            lp_doc = parse_one_json(out) if rc == 0 else None
            if rc != 0 or not isinstance(lp_doc, dict):
                fail_node_pay("E_PAY_NODE_LOCKED", "Core Lightning did not answer listpays (daemon unavailable)")
            for p in lp_doc.get("pays") or []:
                if not isinstance(p, dict):
                    continue
                p_hash = str(p.get("payment_hash") or "").strip().lower()
                if p_hash and p_hash != payment_hash:
                    continue
                p_st = str(p.get("status") or "").lower()
                if p_st == "complete":
                    item["state"] = "paid"
                    item["node_payment"] = {
                        "state": "succeeded", "result": "succeeded", "impl": impl,
                        "fee_limit_sats": fee_limit_sats, "paid_at": now_iso(deps),
                    }
                    save_pending(deps, pending)
                    raise ModuleError("E_ALREADY_PAID", "refused",
                                      "Core Lightning already paid this invoice", EXIT_REFUSED)
                if p_st == "pending":
                    fail_node_pay("E_PAY_IN_FLIGHT",
                                  "Core Lightning reports a payment for this invoice is still pending",
                                  np_state="uncertain", np_result="uncertain")

        # Preflight 3: Node decode cross-check (decodepayreq / decode)
        if impl == "lnd":
            rc, out, _err = deps.run(LNCLI + ["decodepayreq", invoice], timeout=30)
            dec_doc = parse_one_json(out) if rc == 0 else None
            if rc != 0 or not isinstance(dec_doc, dict):
                fail_node_pay("E_PAY_NODE_LOCKED", "LND did not answer decodepayreq (wallet locked or unavailable)")
            node_hash = str(dec_doc.get("payment_hash") or "").strip().lower()
            try:
                node_sats = int(dec_doc.get("num_satoshis"))
            except (TypeError, ValueError):
                node_sats = -1
            if node_hash != payment_hash or node_sats != amount_sats or node_sats <= 0 or node_sats > MAX_RENEW_SATS:
                fail_node_pay("E_INVOICE_MISMATCH",
                              "LND decodepayreq fields do not match the verified invoice",
                              exit_code=EXIT_INVALID_API, cls="invalid_response")
        else:
            rc, out, _err = deps.run(CLNCLI + ["decode", invoice], timeout=30)
            dec_doc = parse_one_json(out) if rc == 0 else None
            if rc != 0 or not isinstance(dec_doc, dict):
                fail_node_pay("E_PAY_NODE_LOCKED", "Core Lightning did not answer decode (daemon unavailable)")
            node_hash = str(dec_doc.get("payment_hash") or "").strip().lower()
            node_msat = _parse_msat(dec_doc.get("amount_msat"))
            if (node_hash != payment_hash or node_msat != amount_sats * 1000
                    or node_msat <= 0 or node_msat > MAX_RENEW_SATS * 1000):
                fail_node_pay("E_INVOICE_MISMATCH",
                              "Core Lightning decode fields do not match the verified invoice",
                              exit_code=EXIT_INVALID_API, cls="invalid_response")

        # Execute payment
        item["node_payment"] = {
            "state": "paying",
            "result": "in_flight",
            "impl": impl,
            "fee_limit_sats": fee_limit_sats,
            "attempted_at": now_iso(deps),
        }
        save_pending(deps, pending)

        fee_sats = None
        if impl == "lnd":
            rc, out, err = deps.run(
                LNCLI + ["payinvoice", "--force", "--json", "--timeout", "60s",
                         "--fee_limit", str(fee_limit_sats), "--pay_req", invoice],
                timeout=75,
            )
            pay_doc = _parse_last_json(out)
            status_str = str((pay_doc or {}).get("status") or "").upper()
            preimage = str((pay_doc or {}).get("payment_preimage") or "").strip().lower()
            if isinstance(pay_doc, dict):
                try:
                    raw_fee = pay_doc.get("fee_sat") if pay_doc.get("fee_sat") is not None else pay_doc.get("fee")
                    if raw_fee is not None:
                        fee_sats = int(raw_fee)
                except (TypeError, ValueError):
                    fee_sats = None
            if rc != 0 or status_str not in ("SUCCEEDED", "FAILED"):
                l_rc, l_out, _l_err = deps.run(LNCLI + ["listpayments", "--include_incomplete"], timeout=30)
                l_doc = parse_one_json(l_out) if l_rc == 0 else None
                if isinstance(l_doc, dict):
                    for p in reversed(l_doc.get("payments") or []):
                        if isinstance(p, dict) and str(p.get("payment_hash") or "").strip().lower() == payment_hash:
                            p_st = str(p.get("status") or "").upper()
                            if p_st in ("SUCCEEDED", "FAILED", "IN_FLIGHT", "INITIATED"):
                                status_str = p_st
                                preimage = str(p.get("payment_preimage") or preimage).strip().lower()
                                if p.get("failure_reason"):
                                    if isinstance(pay_doc, dict) and not pay_doc.get("failure_reason"):
                                        pay_doc["failure_reason"] = p.get("failure_reason")
                                    elif pay_doc is None:
                                        pay_doc = {"failure_reason": p.get("failure_reason")}
                                try:
                                    raw_fee = p.get("fee_sat") if p.get("fee_sat") is not None else p.get("fee")
                                    if raw_fee is not None:
                                        fee_sats = int(raw_fee)
                                except (TypeError, ValueError):
                                    pass
                            break
            if status_str == "SUCCEEDED":
                if not _verify_preimage(preimage, payment_hash):
                    fail_node_pay("E_PAY_ERROR", "LND reported SUCCEEDED without a matching payment preimage")
            elif status_str in ("IN_FLIGHT", "INITIATED") or rc == 124:
                fail_node_pay("E_PAY_TIMEOUT",
                              "LND payment timed out or remains in flight; check status with settle",
                              np_state="uncertain", np_result="uncertain")
            else:
                err_code = _map_lnd_pay_error(pay_doc, out, err)
                fail_node_pay(err_code, "LND payment failed (%s)" % err_code)
        else:
            rc, out, err = deps.run(
                CLNCLI + ["-k", "pay", "bolt11=" + invoice,
                          "maxfee=%dmsat" % fee_limit_msat, "retry_for=60"],
                timeout=75,
            )
            pay_doc = _parse_last_json(out) or _parse_last_json(err)
            status_str = str((pay_doc or {}).get("status") or "").lower()
            preimage = str((pay_doc or {}).get("payment_preimage") or "").strip().lower()
            if isinstance(pay_doc, dict):
                sent_m = _parse_msat(pay_doc.get("amount_sent_msat"))
                amt_m = _parse_msat(pay_doc.get("amount_msat"))
                if sent_m is not None and amt_m is not None and sent_m >= amt_m:
                    fee_sats = (sent_m - amt_m) // 1000
            if rc != 0 or status_str != "complete":
                l_rc, l_out, _l_err = deps.run(CLNCLI + ["listpays", "bolt11=" + invoice], timeout=30)
                l_doc = parse_one_json(l_out) if l_rc == 0 else None
                if isinstance(l_doc, dict):
                    for p in reversed(l_doc.get("pays") or []):
                        if isinstance(p, dict):
                            p_st = str(p.get("status") or "").lower()
                            if p_st == "complete":
                                status_str = "complete"
                                preimage = str(p.get("preimage") or p.get("payment_preimage") or preimage).strip().lower()
                                break
                            if p_st == "pending":
                                status_str = "pending"
                                break
            if status_str == "complete":
                if not _verify_preimage(preimage, payment_hash):
                    fail_node_pay("E_PAY_ERROR",
                                  "Core Lightning reported complete without a matching payment preimage")
            elif status_str == "pending" or rc == 124:
                fail_node_pay("E_PAY_TIMEOUT",
                              "Core Lightning payment timed out or remains pending; check status with settle",
                              np_state="uncertain", np_result="uncertain")
            else:
                err_code = _map_cln_pay_error(pay_doc, out, err)
                fail_node_pay(err_code, "Core Lightning payment failed (%s)" % err_code)

        item["state"] = "paid"
        item["node_payment"] = {
            "state": "succeeded",
            "result": "succeeded",
            "impl": impl,
            "fee_limit_sats": fee_limit_sats,
            "fee_sats": fee_sats,
            "preimage_verified": True,
            "paid_at": now_iso(deps),
        }
        save_pending(deps, pending)
        node_payment_snapshot = dict(item["node_payment"])
        result.fields.update({
            "kind": kind,
            "state": "paid",
            "payment_hash": payment_hash,
            "amount_sats": amount_sats,
            "fee_limit_sats": fee_limit_sats,
            "node_payment": node_payment_snapshot,
        })

    outcome = settle_once(deps, result, foreground=True, use_lock=True)
    result.fields.update({k: v for k, v in outcome.items() if k != "done"})
    result.fields["amount_sats"] = amount_sats
    result.fields["fee_limit_sats"] = fee_limit_sats
    result.fields["node_payment"] = node_payment_snapshot
    if outcome.get("done"):
        if outcome.get("state") == "confirmed":
            result.exit_code = EXIT_OK
        hide_qr(deps)
    else:
        result.exit_code = EXIT_PENDING


def cmd_pay_node(deps, args, result):
    if not getattr(args, "yes", False):
        raise ModuleError("E_CONFIRMATION_REQUIRED", "usage",
                          "pay-node requires --yes", EXIT_USAGE)
    if getattr(args, "kind", None) not in (None, "order", "renewal", "reset"):
        raise ModuleError("E_USAGE", "usage", "--kind must be order, renewal, or reset", EXIT_USAGE)
    _pay_pending_item_via_node(deps, getattr(args, "kind", None), getattr(args, "impl", None), result)


# ------------------------------------------------------------------------------------------
# adopt (step 1: take over the subscription of a standard install; step 2: --upgrade to managed)
# ------------------------------------------------------------------------------------------

def custom_installs_lines(deps):
    """Lines outside the TunnelSats block that mention tunnelsats, wireguard or wg-quick (shown,
    never edited)."""
    try:
        with open(deps.path(CUSTOM_INSTALLS), encoding="utf-8", errors="replace") as handle:
            lines = handle.read().splitlines()
    except OSError:
        return []
    found = []
    inside = False
    for number, line in enumerate(lines, start=1):
        bare = line.rstrip("\r")
        if bare.startswith("# >>> TunnelSats block"):
            inside = True
            continue
        if bare == "# <<< TunnelSats block <<<":
            inside = False
            continue
        if not inside and re.search(r"tunnelsats|wireguard|wg-quick", bare, re.IGNORECASE):
            found.append({"line": number, "text": bare[:200]})
    return found


def read_legacy_config(deps, tool):
    path = (tool.get("config") or {}).get("path")
    if not isinstance(path, str) or not LEGACY_CONF_RE.fullmatch(path):
        raise ModuleError("E_CONFIG_NOT_FOUND", "operational", "the legacy WireGuard config was not found",
                          EXIT_OPERATIONAL)
    try:
        with open(deps.path(path), "rb") as handle:
            data = handle.read(MAX_CONFIG_BYTES + 1)
    except OSError:
        raise ModuleError("E_CONFIG_NOT_FOUND", "operational", "the legacy WireGuard config cannot be read",
                          EXIT_OPERATIONAL) from None
    return parse_wg_config(data)


def cmd_adopt(deps, args, result):
    if args.upgrade and not args.yes:
        raise ModuleError("E_CONFIRMATION_REQUIRED", "usage",
                          "ADOPT --upgrade needs --yes (it replaces the legacy setup and restarts Lightning)",
                          EXIT_USAGE)
    result.fields.update({"adopted": False, "upgraded": False, "upgrade_available": True})
    rc, tool = its(deps, ["detect", "--json"], timeout=ITS_TIMEOUT["detect"])
    if tool is None or rc != 0:
        raise ModuleError("E_DETECT_FAILED", "operational", "the TunnelSats install could not be detected",
                          EXIT_OPERATIONAL)
    kind = (tool.get("install") or {}).get("kind")
    if kind == "none":
        raise ModuleError("E_NOTHING_TO_ADOPT", "not_configured", "no TunnelSats install found", EXIT_NOT_CONFIGURED)
    if kind == "managed":
        raise ModuleError("E_ALREADY_MANAGED", "refused", "TunnelSats already runs in managed mode", EXIT_REFUSED)
    state = load_state(deps)
    if args.upgrade and state and state.get("mode") == "adopted_legacy":
        cfg = load_stored_config(deps)
        if cfg is None or cfg["public_key"] != state.get("public_key"):
            raise ModuleError("E_STORED_CONFIG", "operational",
                              "the stored config is missing or invalid: run ADOPT again", EXIT_OPERATIONAL)
        api = state.get("api") or {}
        outcome, data_api = api.get("outcome") or "skipped", api.get("data")
        result.fields.update(sync_fields(outcome, data_api, cfg))
    else:
        cfg = read_legacy_config(deps, tool)
        if state and state.get("public_key") != cfg["public_key"]:
            raise ModuleError("E_ALREADY_CONFIGURED", "refused",
                              "another subscription is stored on this node: REMOVE it first", EXIT_REFUSED)
        outcome, data_api = confirm_with_api(deps, cfg, args.yes, result)
    result.fields.update({"public_key": cfg["public_key"], "legacy_kind": kind, "warnings": list(cfg["warnings"])})
    conf = read_rb_conf(deps)
    impl, _why = select_impl(conf)
    if not args.upgrade:
        with Lock(deps, wait=30):
            store_subscription(deps, cfg, "adopted_legacy", impl, outcome, data_api, {"legacy_kind": kind})
        result.fields["adopted"] = True
        result.fields["custom_installs_lines"] = custom_installs_lines(deps)
        return
    result.fields["ln_start_wait"] = None
    found = detect(deps)
    reasons = [r for r in found["reasons"] if r not in ("legacy_install", "unknown_install")]
    result.fields["detect"] = {"eligible": not reasons, "reasons": reasons}
    if reasons:
        raise ModuleError("E_NOT_ELIGIBLE", "not_eligible", "not eligible: %s" % ", ".join(reasons),
                          EXIT_NOT_CONFIGURED)
    impl = found["impl"]
    with Lock(deps, wait=30):
        # Store as adopted_legacy first so if adopt --managed fails, the subscription stays stored
        store_subscription(deps, cfg, "adopted_legacy", impl, outcome, data_api, {"legacy_kind": kind})
        activate(deps, impl, result, tool_verb="adopt")
        store_subscription(deps, cfg, "managed", impl, outcome, data_api, {"legacy_kind": kind})
    result.fields.update({"adopted": True, "upgraded": True, "upgrade_available": False,
                          "custom_installs_lines": custom_installs_lines(deps)})
    finish_with_check(deps, result, wait_until_started(deps, UNITS[impl]))


# ------------------------------------------------------------------------------------------
# status
# ------------------------------------------------------------------------------------------

def wg_local(deps):
    """Handshake age and transfer of the tunnel (no key material)."""
    info = {"handshake_age_s": None, "rx_bytes": None, "tx_bytes": None}
    rc, out, _err = deps.run(["wg", "show", "tunnelsatsv2", "latest-handshakes"], timeout=10)
    if rc == 0 and out.split():
        fields = out.split()
        if len(fields) >= 2 and fields[1].isdigit() and int(fields[1]) > 0:
            info["handshake_age_s"] = max(0, int(deps.clock().timestamp()) - int(fields[1]))
    rc, out, _err = deps.run(["wg", "show", "tunnelsatsv2", "transfer"], timeout=10)
    if rc == 0 and len(out.split()) >= 3:
        fields = out.split()
        if fields[1].isdigit() and fields[2].isdigit():
            info["rx_bytes"], info["tx_bytes"] = int(fields[1]), int(fields[2])
    return info


def read_guard_record(deps, base):
    try:
        with open(deps.path("%s/guard-%s.json" % (RUN_DIR, base)), encoding="utf-8") as handle:
            doc = json.load(handle)
        return doc if isinstance(doc, dict) and doc.get("schema") == "raspiblitz.tunnelsats.guard/1" else None
    except (OSError, ValueError):
        return None


def cmd_status(deps, args, result):
    state = load_state(deps)
    conf = read_rb_conf(deps)
    if state is None:
        result.fields.update({"configured": False, "tunnelsats": conf.get("tunnelsats", "off")})
        result.exit_code = EXIT_NOT_CONFIGURED
        return
    api = state.get("api") or {}
    outcome = "skipped"
    checked = parse_iso(api.get("checked_at"))
    stale = checked is None or (deps.clock() - checked).total_seconds() > API_CACHE_SECONDS
    if args.refresh or (stale and not args.cached):
        outcome, data, detail = api_status(deps, state["public_key"])
        api["outcome"] = outcome
        api["checked_at"] = now_iso(deps)
        if outcome == "confirmed":
            api["data"] = data
            api["confirmed_at"] = now_iso(deps)
        elif detail:
            result.fields["sync_detail"] = detail
        state["api"] = api
        try:
            with Lock(deps, wait=0):
                save_state(deps, state)
        except ModuleError:
            pass
        if outcome == "invalid":
            result.error("E_API_INVALID", "invalid_response", "the status response failed validation", EXIT_INVALID_API)
    data = api.get("data") or {}
    impl = state.get("impl") or conf.get("tunnelsatsImpl")
    record = read_guard_record(deps, BASES.get(impl, "lnd")) if impl in BASES else None
    live_port = data.get("vpn_port")
    fields = {
        "configured": True, "mode": state.get("mode"), "tunnelsats": conf.get("tunnelsats", "off"), "impl": impl,
        "public_key": state.get("public_key"), "endpoint": {"host": state.get("endpoint_host")},
        "vpn_port": state.get("vpn_port"), "server_domain": data.get("server_domain") or state.get("server_domain"),
        "expiry": data.get("expiry") or state.get("valid_until"), "bandwidth_used_gb": data.get("bandwidth_used_gb"),
        "bandwidth_limit_gb": data.get("bandwidth_limit_gb"), "resets_this_month": data.get("resets_this_month"),
        "max_resets_per_month": data.get("max_resets_per_month"), "peer_status": data.get("peer_status"),
        "sync": {"outcome": outcome, "last_outcome": api.get("outcome"), "confirmed_at": api.get("confirmed_at")},
        "tunnel": wg_local(deps), "last_check": state.get("last_check"),
        "guard": {k: (record or {}).get(k) for k in ("decision", "reason", "decided_at")},
        "notify_state": state.get("notify_state"),
    }
    if getattr(args, "raw_api", False):
        raw_api = {
            "expiry": data.get("expiry") or state.get("valid_until"),
            "bandwidth_used_gb": data.get("bandwidth_used_gb"),
            "bandwidth_limit_gb": data.get("bandwidth_limit_gb"),
            "bandwidth_resets_this_month": data.get("resets_this_month"),
            "max_resets_per_month": data.get("max_resets_per_month"),
            "status": data.get("peer_status"),
            "server_domain": data.get("server_domain") or state.get("server_domain"),
            "vpn_port": data.get("vpn_port") if data.get("vpn_port") is not None else state.get("vpn_port"),
            "last_synced_at": data.get("last_synced_at"),
        }
        fields["raw_api"] = raw_api
        fields["status"] = raw_api["status"]
        fields["bandwidth_resets_this_month"] = raw_api["bandwidth_resets_this_month"]
        fields["last_synced_at"] = raw_api["last_synced_at"]
    if live_port is not None and live_port != state.get("vpn_port"):
        fields["port_changed"] = True
        fields["action"] = "server port changed: REPAIR (restarts Lightning)"
    result.fields.update(fields)


# ------------------------------------------------------------------------------------------
# check
# ------------------------------------------------------------------------------------------

def daemon_cmdline(deps, unit):
    """The command line of the Lightning daemon of unit (lnd, or lightningd below CLN's sh)."""
    props = unit_props(deps, unit, "MainPID", "ActiveState", "InvocationID", "ControlGroup")
    pid = props["MainPID"]
    if not pid.isdigit() or pid == "0":
        return None, props

    def cmdline(p):
        try:
            with open(deps.path("/proc/%s/cmdline" % p), "rb") as handle:
                return [a.decode("utf-8", "replace") for a in handle.read().split(b"\0") if a]
        except OSError:
            return None

    args = cmdline(pid)
    if args and os.path.basename(args[0]) in ("sh", "bash", "dash"):
        try:
            entries = os.listdir(deps.path("/proc"))
        except OSError:
            entries = []
        for entry in entries:
            if not entry.isdigit():
                continue
            try:
                with open(deps.path("/proc/%s/stat" % entry), encoding="utf-8", errors="replace") as handle:
                    stat = handle.read()
            except OSError:
                continue
            fields = stat.rsplit(")", 1)[-1].split()
            if len(fields) > 1 and fields[1] == pid:
                child = cmdline(entry)
                if child and os.path.basename(child[0]) == "lightningd":
                    return child, props
    return args, props


def has_flags(impl, args):
    regex = LND_FLAG_RE if impl == "lnd" else CLN_FLAG_RE
    return any(regex.fullmatch(a) for a in (args or []))


def lightning_info(deps, impl):
    if impl == "lnd":
        argv = LNCLI + ["getinfo"]
    else:
        argv = CLNCLI + ["getinfo"]
    rc, out, _err = deps.run(argv, timeout=30)
    return parse_one_json(out) if rc == 0 else None


def public_ipv4(value):
    """value if it is a dotted public IPv4 address, else None."""
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{1,3}(\.[0-9]{1,3}){3}", value):
        return None
    try:
        address = ipaddress.IPv4Address(value)
    except ValueError:
        return None
    return value if address.is_global and not address.is_multicast else None


def announce_check(impl, info, record, state, live_ipv4=None):
    """VPN address announced, onion present, no other clearnet address. LND resolves externalhosts
    itself and announces the resolved IPv4, so its uris carry <ipv4>:<vpn_port>: the endpoint's
    address at the start (guard record) and now (live_ipv4, endpoint.ipv4 of this CHECK's verify)
    both count as the VPN address. CLN announces the address of the guard record."""
    if info is None:
        return "degraded", "fail", "Lightning did not answer getinfo (locked or not running)", None
    if impl == "lnd":
        addrs = [u.split("@", 1)[1] for u in info.get("uris") or [] if isinstance(u, str) and "@" in u]
    else:
        addrs = ["%s:%s" % (a.get("address"), a.get("port")) for a in info.get("address") or [] if isinstance(a, dict)]
    onion = any(".onion" in a for a in addrs)
    clear = [a for a in addrs if ".onion" not in a]
    host, port = state.get("endpoint_host"), state.get("vpn_port")
    announce = (record or {}).get("announce") or {}
    expected = {"%s:%s" % (host, port)}
    for ipv4 in (public_ipv4(announce.get("ipv4")), public_ipv4(live_ipv4) if impl == "lnd" else None):
        if ipv4:
            expected.add("%s:%s" % (ipv4, port))
    foreign = [a for a in clear if a not in expected]
    if foreign:
        return "unsafe", "fail", "another clearnet address is announced", onion
    if not onion:
        return "degraded", "fail", "no onion address announced", onion
    unconfirmed = (record or {}).get("reason") == "announce_unconfirmed"
    if (record or {}).get("decision") == "hybrid" and not clear and not unconfirmed:
        return "degraded", "fail", "the VPN address is not announced yet", onion
    return "degraded", "pass", "onion%s announced" % (" and VPN address" if clear else ""), onion


def run_check(deps):
    """CHECK (design 6.5): the tool's verify with probes plus the RaspiBlitz checks."""
    state = load_state(deps) or {}
    conf = read_rb_conf(deps)
    checks = []

    def add(cid, cls, res, detail):
        checks.append({"id": cid, "class": cls, "result": res, "detail": detail})

    if not state:
        rc, verify = its(deps, ["verify", "--no-probe", "--json"], timeout=ITS_TIMEOUT["verify_no_probe"])
        if rc == 9:
            add("legacy_lifecycle", "unsafe", "fail", "legacy setup: the kill switch depends on the tunnel being up "
                "(ADOPT takes over the subscription)")
            return {"verdict": "unsafe", "reasons": ["legacy_lifecycle"], "checks": checks, "clearnet_blocked": None,
                    "guard": {}, "restart_needed": False}
        return {"verdict": "not_configured", "reasons": ["not_configured"], "checks": [], "clearnet_blocked": None,
                "guard": {}, "restart_needed": False}
    if state.get("mode") != "adopted_legacy" and conf.get("tunnelsats") != "on":
        add("tunnelsats_flag", "degraded", "fail", "TunnelSats is not active on this node: REPAIR activates it again")
        return {"verdict": "not_configured", "reasons": ["tunnelsats_flag"], "checks": checks,
                "clearnet_blocked": None, "guard": {}, "restart_needed": False}
    if state.get("mode") == "adopted_legacy":
        add("legacy_lifecycle", "unsafe", "fail", "legacy setup: the kill switch depends on the tunnel being up "
            "(UPGRADE to managed mode in the menu, or run adopt --upgrade --yes)")
        return {"verdict": "unsafe", "reasons": ["legacy_lifecycle"], "checks": checks, "clearnet_blocked": None,
                "guard": {}, "restart_needed": False}
    impl = state.get("impl") or conf.get("tunnelsatsImpl")
    unit, base = UNITS.get(impl, "lnd.service"), BASES.get(impl, "lnd")
    rc, verify = its(deps, ["verify", "--json"], timeout=ITS_TIMEOUT["verify"])
    clearnet_blocked = None
    if verify is None:
        add("verify", "unsafe", "fail", "tunnelsats verify did not answer")
    else:
        clearnet_blocked = verify.get("clearnet_blocked")
        for c in verify.get("checks") or []:
            if isinstance(c, dict) and isinstance(c.get("id"), str):
                cls = c.get("class") if c.get("class") in ("unsafe", "degraded") else "unsafe"
                add(c["id"], cls, c.get("result") if c.get("result") in ("pass", "fail", "skip") else "fail",
                    str(c.get("detail", ""))[:300])
        if rc == 3:
            add("verify", "degraded", "fail", "the managed dataplane is not installed, Lightning runs Tor-only: REPAIR")
        elif rc not in (0, 4, 5):
            add("verify", "unsafe", "fail", "tunnelsats verify: %s (exit %s)" % (tool_error(verify, "E_VERIFY"), rc))
    rc, audit = its(deps, ["audit", impl, "--json"], timeout=30)
    if audit and audit.get("status") == "clean":
        add("ln_at_rest", "unsafe", "pass", "no clearnet setting at rest")
    else:
        add("ln_at_rest", "unsafe", "fail", "clearnet settings at rest: %s" % ",".join((audit or {}).get("keys") or ["?"]))
    record = read_guard_record(deps, base)
    args, props = daemon_cmdline(deps, unit)
    flags = has_flags(impl, args)
    decision = (record or {}).get("decision")
    if props["ActiveState"] != "active" or args is None:
        add("ln_runtime_flags", "degraded", "fail", "Lightning is not running")
    elif flags and (decision != "hybrid" or record.get("invocation_id") != props["InvocationID"]):
        add("ln_runtime_flags", "unsafe", "fail", "clearnet flags run without a hybrid decision of the start guard")
    elif record is None or record.get("invocation_id") != props["InvocationID"]:
        add("ln_runtime_flags", "degraded", "fail", "no start guard decision for this start (unit without the guard lines: REPAIR)")
    elif decision == "hybrid" and not flags:
        add("ln_runtime_flags", "degraded", "fail", "the start guard decided hybrid but the daemon runs without the flags")
    elif decision != "hybrid":
        add("ln_runtime_flags", "degraded", "fail", "Lightning started Tor-only (%s)" % record.get("reason"))
    else:
        add("ln_runtime_flags", "unsafe", "pass", "hybrid flags for this start, decided by the start guard")
    restart_needed = False
    if record and props["ActiveState"] == "active" and record.get("invocation_id") == props["InvocationID"] and \
            record.get("reason") in RESTARTABLE and decision in ("tor-only", "hybrid"):
        rc, dry = its(deps, ["guard", impl, "mainnet", "--dry-run", "--json"], timeout=ITS_TIMEOUT["guard_dry_run"])
        if dry and dry.get("decision") == "hybrid" and (impl == "lnd" or dry.get("reason") == "ok"):
            restart_needed = True
    if restart_needed:
        add("restart_needed", "degraded", "fail", "Restart Lightning to resume clearnet connections" if impl == "lnd"
            else "Restart Lightning to announce the clearnet address")
    else:
        add("restart_needed", "degraded", "pass", "no restart needed")
    info = lightning_info(deps, impl) if props["ActiveState"] == "active" else None
    endpoint = (verify or {}).get("endpoint")
    live_ipv4 = endpoint.get("ipv4") if isinstance(endpoint, dict) else None
    cls, res, detail, onion = announce_check(impl, info, record, state, live_ipv4)
    add("announce", cls, res, detail)
    if impl == "cl":
        bindings = ["%s:%s" % (b.get("address"), b.get("port")) for b in (info or {}).get("binding") or []
                    if isinstance(b, dict)]
        need = {"127.0.0.1:9736"} | ({"0.0.0.0:9735"} if decision == "hybrid" else set())
        add("cln_bindings", "degraded", "pass" if info and need <= set(bindings) else "fail",
            "bindings %s" % ",".join(bindings) if info else "Lightning did not answer getinfo")
    other = "cl" if impl == "lnd" else "lnd"
    rc, other_audit = its(deps, ["audit", other, "--json"], timeout=30)
    other_record = read_guard_record(deps, BASES[other])
    if other_audit and other_audit.get("reason") == "config_missing":
        add("other_impl", "unsafe", "pass", "%s is not installed" % other)
    elif other_audit and other_audit.get("status") == "clean" and (other_record or {}).get("decision") != "hybrid":
        add("other_impl", "unsafe", "pass", "%s Tor-only at rest and without flags" % other)
    else:
        add("other_impl", "unsafe", "fail", "%s has clearnet settings at rest or flags" % other)
    tor_ok = conf.get("runBehindTor") == "on" and onion is not False
    add("tor", "unsafe", "pass" if tor_ok else "fail", "Tor on" if tor_ok else "Tor is off or no onion address")
    rc, block = its(deps, ["block-status", "--json"], timeout=30)
    if block and block.get("state") == "present":
        add("restore_block", "degraded", "pass", "restore block present in custom-installs.sh")
    else:
        add("restore_block", "degraded", "fail", "TunnelSats is not restored automatically after an SD-card update")
    rc, its_state = its(deps, ["status", "--json"], timeout=ITS_TIMEOUT["status"])
    tool_hash = (its_state or {}).get("tool_hash")
    if tool_hash == "current":
        add("tool_pin", "degraded", "pass", "tunnelsats.sh is the pinned version")
    elif tool_hash == "accepted_older":
        add("tool_pin", "degraded", "fail", "update available: REPAIR")
    else:
        add("tool_pin", "degraded", "fail", "the installed tunnelsats tool is missing or not a pinned version: REPAIR")
    if (its_state or {}).get("dev_override") == "yes":
        add("dev_override", "degraded", "fail", "DEV OVERRIDE active for this boot")
    stopped = False
    try:
        with open(deps.path(STOPPED_UNITS), encoding="utf-8") as handle:
            stopped = any(line.split()[:1] == [unit] for line in handle if line.strip())
    except OSError:
        pass
    add("verifier_stopped", "degraded", "fail" if stopped else "pass",
        "the TunnelSats verifier stopped Lightning because no protection holds; REPAIR" if stopped
        else "Lightning not stopped by the verifier")
    last = None
    try:
        with open(deps.path(LAST_RESTORE_FILE), encoding="utf-8") as handle:
            last = json.load(handle)
    except (OSError, ValueError):
        pass
    if last and last.get("result") not in ("ok", None) and not (verify or {}).get("managed"):
        add("last_restore", "degraded", "fail", "the last restore after an SD-card update failed (%s): REPAIR"
            % last.get("error"))
    else:
        add("last_restore", "degraded", "pass", "last restore %s" % ((last or {}).get("result") or "none"))
    data = (state.get("api") or {}).get("data") or {}
    if data.get("vpn_port") is not None and data.get("vpn_port") != state.get("vpn_port"):
        add("vpn_port", "degraded", "fail", "server port changed: REPAIR (restarts Lightning)")
    failed = [c for c in checks if c["result"] == "fail"]
    if any(c["class"] == "unsafe" for c in failed):
        verdict = "unsafe"
    elif failed:
        verdict = "degraded"
    else:
        verdict = "protected"
    return {"verdict": verdict, "reasons": [c["id"] for c in failed], "checks": checks,
            "clearnet_blocked": clearnet_blocked,
            "guard": {k: (record or {}).get(k) for k in ("decision", "reason", "decided_at")},
            "restart_needed": restart_needed}


def cmd_check(deps, args, result):
    checked = run_check(deps)
    result.fields.update(checked)
    result.exit_code = verdict_exit(checked["verdict"])
    state = load_state(deps)
    if state:
        state["last_check"] = {"verdict": checked["verdict"], "at": now_iso(deps)}
        try:
            with Lock(deps, wait=0):
                save_state(deps, state)
        except ModuleError:
            pass


# ------------------------------------------------------------------------------------------
# uninstall (REMOVE)
# ------------------------------------------------------------------------------------------

def tool_uninstall(deps, unit, own_disable=False):
    """uninstall --managed of the pinned tool, for REMOVE and REPAIR. Returns its document, with
    "remaining" the list of what is left and "tool_errors" the codes of the tool's errors, and a note
    for the result or None. If the document does not arrive (no list "remaining": a timeout, a crash,
    no single JSON document, or a failure such as E_LN_STOP before the removal), the outcome is read
    back instead of assumed: detect for the dataplane, systemd for unit before and after. A lost
    report never turns a done removal into a failed one, and never a failed one into a done one.
    own_disable (REMOVE, which disables the unit itself when its config is not Tor-only at rest):
    a report whose only error is E_LN_DISABLE, the tool removed the dataplane but could not disable
    the unit, counts as a complete removal."""
    before = unit_props(deps, unit, "ActiveState", "UnitFileState") if unit else {}
    rc, doc = its(deps, ["uninstall", "--json"], timeout=ITS_TIMEOUT["uninstall"])
    doc = doc if isinstance(doc, dict) else {}
    codes = [e["code"] for e in doc.get("errors") or [] if isinstance(e, dict) and isinstance(e.get("code"), str)
             and re.fullmatch(r"E_[A-Z0-9_]{1,40}", e["code"])][:10]
    if isinstance(doc.get("remaining"), list):
        done = rc == 0 or (own_disable and codes == ["E_LN_DISABLE"])
        return dict(doc, remaining=doc["remaining"] or ([] if done else ["managed dataplane"]), tool_errors=codes), None
    _rc, found = its(deps, ["detect", "--json"], timeout=ITS_TIMEOUT["detect"])
    kind = ((found or {}).get("install") or {}).get("kind")
    removed = isinstance(kind, str) and kind not in ("managed", "unknown")
    after = unit_props(deps, unit, "ActiveState", "UnitFileState") if unit else {}
    read = {"unit": unit, "remaining": [] if removed else ["managed dataplane"],
            "ln_was_active": before.get("ActiveState") not in (None, "", "inactive", "failed"),
            "ln_disabled": (before.get("UnitFileState") in ("enabled", "enabled-runtime")
                            and after.get("UnitFileState") == "disabled"),
            "ln_started": after.get("ActiveState") == "active", "node_config": "unknown", "tool_errors": codes}
    if removed:
        seen = "the dataplane is removed"
    elif isinstance(kind, str):
        seen = "the dataplane is still there"
    else:
        seen = "detect did not answer, so the removal counts as incomplete"
    code = tool_error(doc, "E_TOOL_OUTPUT")
    if code == "E_TOOL_OUTPUT":
        note = "the report of the TunnelSats uninstall did not arrive (E_TOOL_OUTPUT); read back from the system: %s" % seen
    else:
        note = "the TunnelSats uninstall stopped with %s; read back from the system: %s" % (code, seen)
    return read, note


def announce_candidates(deps, state, record):
    """The VPN addresses (<ipv4>:<port>) LND may announce. LND resolves externalhosts itself and
    announces the IPv4 it got: the endpoint's IPv4 at the last start (guard record, read before
    uninstall removes /run/tunnelsats) and now, with the port of the guard record and of the
    stored subscription."""
    announce = (record or {}).get("announce") or {}
    ipv4s = {public_ipv4(announce.get("ipv4"))}
    host = (state or {}).get("endpoint_host")
    if valid_host(host):
        rc, out, _err = deps.run(["getent", "ahostsv4", host], timeout=10)
        if rc == 0:
            ipv4s.update(public_ipv4(line.split()[0]) for line in out.splitlines() if line.split())
    ports = {port for port in (announce.get("port"), (state or {}).get("vpn_port")) if valid_port(port)}
    return sorted("%s:%d" % (ipv4, port) for ipv4 in ipv4s if ipv4 for port in ports)


def announce_command(addresses):
    return " ".join(LNCLI + ["peers", "updatenodeannouncement"] +
                    [arg for address in addresses for arg in ("--address_remove", address)])


def tool_announce_notes(outcome, warnings, candidates):
    """The tool's announcement warnings REMOVE shows with its own notes: only when the tool's step did
    check LND (removed, none, failed), and only those naming an address outside REMOVE's candidates,
    such as another IPv4 with the forwarded port. REMOVE's own step covers its candidates."""
    if outcome not in ("removed", "none", "failed"):
        return []
    return [w for w in warnings if set(ADDRESS_RE.findall(w)) - set(candidates)]


def announce_cleanup(deps, unit, state, record, wait=120, step=5, candidates=None):
    """REMOVE, LND only. LND saves the addresses it announces and announces them again at every
    start when its config sets no externalip, so after REMOVE it would go on announcing the VPN
    address. This takes exactly the VPN address (announce_candidates, or candidates when given) out
    of LND's node announcement once LND answers, never the onion address or any other one. Returns
    the outcome (removed, none, lnd_not_ready, failed; skipped for CLN) and notes for the result."""
    if unit != UNITS["lnd"]:
        return "skipped", []
    candidates = announce_candidates(deps, state, record) if candidates is None else candidates
    if not candidates:
        return "none", []
    info = None
    if unit_props(deps, unit, "ActiveState")["ActiveState"] in ("active", "activating", "reloading"):
        started, waited = deps.clock(), 0
        info = lightning_info(deps, "lnd")
        while info is None and waited < wait and (deps.clock() - started).total_seconds() < wait:
            deps.sleep(step)
            waited += step
            info = lightning_info(deps, "lnd")
    if info is None:
        return "lnd_not_ready", ["LND did not answer (stopped, locked or still starting). Once it runs, take the "
                                 "VPN address out of its node announcement, which LND keeps from its last start: %s"
                                 % announce_command(candidates)]
    announced = {u.split("@", 1)[1] for u in info.get("uris") or [] if isinstance(u, str) and "@" in u}
    stale = [address for address in candidates if address in announced]
    if not stale:
        return "none", []
    failed = []
    for address in stale:
        rc, _out, _err = deps.run(LNCLI + ["peers", "updatenodeannouncement", "--address_remove", address], timeout=30)
        if rc != 0:
            failed.append(address)
    if failed:
        return "failed", ["LND still announces the VPN address %s; run: %s"
                          % (", ".join(failed), announce_command(failed))]
    return "removed", []


def zero_artifacts(deps, impl, conf_flag_off_expected=True, keep_tick_timer=False):
    """What is left after REMOVE (design 6.6 step 10)."""
    leftovers = []
    warnings = []
    rc, tool = its(deps, ["detect", "--json"], timeout=ITS_TIMEOUT["detect"])
    kind = ((tool or {}).get("install") or {}).get("kind")
    if kind != "none":
        leftovers.append("tunnelsats install (%s)" % kind)
    try:
        envs = [e for e in os.listdir(deps.path(RUN_DIR)) if e.startswith("hybrid-")]
    except OSError:
        envs = []
    leftovers += ["%s/%s" % (RUN_DIR, e) for e in envs]
    rc, block = its(deps, ["block-status", "--json"], timeout=30)
    if (block or {}).get("state") != "absent":
        warnings.append("restore block %s in custom-installs.sh (inert while TunnelSats is off)"
                        % (block or {}).get("state"))
    if read_rb_conf(deps).get("tunnelsats") == "on":
        leftovers.append("tunnelsats=on in raspiblitz.conf")
    rc, out, _err = deps.run([ITS, "tick-timer", "status"], timeout=30)
    if not keep_tick_timer and out.strip() != "absent":
        leftovers.append("tunnelsats-tick.timer")
    if impl:
        args, props = daemon_cmdline(deps, UNITS[impl])
        if props["ControlGroup"] and not props["ControlGroup"].startswith("/system.slice/"):
            leftovers.append("%s runs in %s" % (UNITS[impl], props["ControlGroup"]))
        if has_flags(impl, args):
            leftovers.append("clearnet flags on the command line of %s" % UNITS[impl])
    return leftovers, warnings


def purge(deps):
    shred(deps.path(CONF_FILE))
    shred(deps.path(PENDING_FILE))
    state_dir = deps.path(STATE_DIR)
    if os.path.isdir(state_dir):
        for entry in os.listdir(state_dir):
            if entry.startswith("recovered-") and entry.endswith(".conf"):
                shred(os.path.join(state_dir, entry))
    for name in (STATE_FILE, LAST_RESTORE_FILE):
        try:
            os.unlink(deps.path(name))
        except FileNotFoundError:
            pass
    for sub in ("dist", "backup"):
        directory = deps.path(STATE_DIR + "/" + sub)
        if os.path.isdir(directory):
            for entry in os.listdir(directory):
                os.unlink(os.path.join(directory, entry))
            os.rmdir(directory)
    try:
        os.rmdir(deps.path(STATE_DIR))
    except OSError:
        pass


def at_rest_audit(deps, impl, repair):
    """The at-rest audit of implementation impl after the dataplane is gone: --repair (toward
    Tor-only, one backup) if asked, read-only while the unit runs or if not asked. The document, or
    None if the audit did not answer (timeout, error)."""
    doc = None
    if repair:
        rc, doc = its(deps, ["audit", impl, "--repair", "--json"], timeout=60)
    if not repair or (doc or {}).get("status") == "not_checked":
        rc, doc = its(deps, ["audit", impl, "--json"], timeout=30)
    return doc if isinstance(doc, dict) and isinstance(doc.get("status"), str) else None


def at_rest_ok(doc, installed_only=False):
    """Tor-only at rest per audit document doc; installed_only: a missing config counts as fine."""
    if doc is None:
        return False
    if installed_only and doc.get("reason") == "config_missing":
        return True
    return doc.get("status") in ("clean", "repaired")


def at_rest_action(impl, doc, unit, then):
    """action_required of REMOVE and REPAIR for one implementation, in the form tunnelsats.sh uninstall uses:
    the exact lines to remove (<file>:<line>:<setting>) and the command to run afterwards."""
    lines = [line for line in (doc or {}).get("lines") or [] if isinstance(line, str)][:50]
    if doc is None:
        detail = "%s: the at-rest check did not answer; check the config of %s for TunnelSats clearnet " \
                 "settings (LND: externalhosts, externalip, tor.skip-proxy-for-clearnet-targets; CLN: " \
                 "bind-addr=0.0.0.0:9735, a clearnet addr or announce-addr, always-use-proxy=false)" % (impl, unit)
    else:
        keys = ",".join(k for k in doc.get("keys") or [] if isinstance(k, str)) or "none"
        detail = "%s: %s (settings: %s)" % (impl, doc.get("reason") or doc.get("status"), keys)
        if "always-use-proxy" in (doc.get("keys") or []):
            detail += "; CLN needs always-use-proxy=true"
    return {"reason": "node_config_clearnet" if lines else "node_config_unknown", "detail": detail,
            "lines": lines, "then": then}


def keep_pending_removal(deps, unit, doc, reason=None, tunnel=None):
    """Records in state.json that a refused or unfinished REMOVE left unit stopped (and disabled,
    per uninstall document doc): the menu then offers REMOVE again instead of START, and the next
    REMOVE enables and starts the unit once the removal is complete and its config is Tor-only at rest.
    reason: what REMOVE could not do to the unit (stop_failed, disable_failed); tunnel: where the
    tunnel stood then (in_place, removed, partly_removed). Both for the menu."""
    if not unit or not (doc.get("ln_disabled") or (doc.get("ln_was_active") and not doc.get("ln_started"))):
        return
    state = load_state(deps)
    if state is None:
        return
    state["remove_pending"] = {"unit": unit, "ln_was_active": bool(doc.get("ln_was_active")),
                               "ln_disabled": bool(doc.get("ln_disabled")), "at": now_iso(deps)}
    if reason:
        state["remove_pending"].update({"reason": reason, "tunnel": tunnel or "in_place"})
    save_state(deps, state)


def pending_removal(deps, state):
    """The unit a refused REMOVE left stopped, as an uninstall-like document, while that unit still
    does not run (someone may have started it by hand since); else None."""
    pending = (state or {}).get("remove_pending")
    if not isinstance(pending, dict) or pending.get("unit") not in UNITS.values():
        return None
    if unit_props(deps, pending["unit"], "ActiveState")["ActiveState"] not in ("inactive", "failed", ""):
        return None
    return {"unit": pending["unit"], "ln_was_active": bool(pending.get("ln_was_active")),
            "ln_disabled": bool(pending.get("ln_disabled")), "ln_started": False}


def clear_pending_removal(deps):
    state = load_state(deps)
    if state is not None and "remove_pending" in state:
        del state["remove_pending"]
        save_state(deps, state)


def managed_unit(deps):
    """The Lightning unit of the managed install, as verify --no-probe names it (dataplane_healthy
    reads it the same way), or None when verify does not name one."""
    _rc, doc = its(deps, ["verify", "--no-probe", "--json"], timeout=ITS_TIMEOUT["verify_no_probe"])
    unit = (doc or {}).get("unit")
    return unit if unit in UNITS.values() else None


def dropin_unit(found):
    """The Lightning unit of the managed install as the detect document found names it: the one unit
    whose drop-in from install --managed is present (artifact managed_ln_dropin). None when there is
    no such drop-in, more than one, or one for a unit RaspiBlitz does not tunnel."""
    units = set()
    for art in ((found or {}).get("install") or {}).get("artifacts") or []:
        if isinstance(art, dict) and art.get("id") == "managed_ln_dropin" and art.get("status") == "present":
            match = DROPIN_RE.fullmatch(str(art.get("location") or ""))
            units.add(match.group(1) if match else None)
    return units.pop() if len(units) == 1 and units <= set(UNITS.values()) else None


def stop_unless_tor_only(deps, unit, managed=None):
    """REMOVE, before uninstall --managed. Since tunnelsats PR 227 the tool starts the unit it stopped
    again itself when its own check of the node config finds no TunnelSats clearnet settings. That
    check is narrower than the at-rest audit (for LND it leaves out externalip, an empty externalhosts
    and tor.active, for CLN a missing always-use-proxy=true), with TunnelSats off the start guard
    repairs nothing at that start, and the audit repairs only a stopped unit. A running unit of the
    managed install whose config the audit does not find Tor-only at rest, or cannot check, is
    therefore stopped here while the dataplane still holds, recorded as remove_pending before the
    stop, and disabled. The tool then neither stops nor starts it, and this REMOVE repairs the config
    and enables and starts the unit after its own audit, or keeps it stopped and disabled, as after a
    refused REMOVE. managed: the managed unit as detect names it (dropin_unit), used as it is, also
    when state.impl names another, stopped unit; without it, verify --no-probe is asked once a stop is
    due, and a unit it names as not the managed one is never touched. Returns (record or None,
    outcome): "skipped", "stopped", or, when the tool must not run, "stop_failed" (the record has the
    state read back in "state") or "disable_failed" (still enabled: without the dataplane the next
    boot would start it with that config)."""
    unit = managed or unit
    impl = IMPL_OF_UNIT.get(unit) if unit else None
    if impl is None:
        return None, "skipped"
    props = unit_props(deps, unit, "ActiveState", "UnitFileState")
    if props["ActiveState"] in ("inactive", "failed") or at_rest_ok(at_rest_audit(deps, impl, repair=False)):
        return None, "skipped"
    found = None if managed else managed_unit(deps)
    if found and found != unit:
        # state.impl does not name the managed install: only its unit is stopped, never another one
        unit, impl = found, IMPL_OF_UNIT[found]
        props = unit_props(deps, unit, "ActiveState", "UnitFileState")
        if props["ActiveState"] in ("inactive", "failed") or at_rest_ok(at_rest_audit(deps, impl, repair=False)):
            return None, "skipped"
    record = {"unit": unit, "ln_was_active": True, "ln_disabled": False, "ln_started": False}
    keep_pending_removal(deps, unit, record)
    systemctl(deps, "stop", unit)
    record["state"] = unit_props(deps, unit, "ActiveState")["ActiveState"] or "unknown"
    if record["state"] not in ("inactive", "failed"):
        keep_pending_removal(deps, unit, record, reason="stop_failed", tunnel="in_place")
        return record, "stop_failed"
    if props["UnitFileState"] not in BOOT_OFF:
        # recorded before the disable: a REMOVE that ends here leaves the next one to enable it again
        record["ln_disabled"] = True
        keep_pending_removal(deps, unit, record)
        systemctl(deps, "disable", unit)
        if unit_props(deps, unit, "UnitFileState")["UnitFileState"] not in BOOT_OFF:
            record["ln_disabled"] = False
            keep_pending_removal(deps, unit, record, reason="disable_failed", tunnel="in_place")
            return record, "disable_failed"
    return record, "stopped"


def keep_off(deps, unit):
    """REMOVE, after the tool, when the config of unit is not Tor-only at rest: with TunnelSats off the
    start guard repairs nothing, and the tunnel is gone or partly gone, so nothing may run or start
    the unit with that config, now or at the next boot. Stops it if it runs and disables it unless no
    boot starts it, each read back from systemd (never taken from the tool's report). Returns
    (stopped_now, disabled_now, problem, state): problem None, "stop_failed" or "disable_failed",
    state the ActiveState read back."""
    props = unit_props(deps, unit, "ActiveState", "UnitFileState")
    state = props["ActiveState"] or "unknown"
    stopped_now = disabled_now = False
    if state not in ("inactive", "failed"):
        systemctl(deps, "stop", unit)
        state = unit_props(deps, unit, "ActiveState")["ActiveState"] or "unknown"
        if state not in ("inactive", "failed"):
            return False, False, "stop_failed", state
        stopped_now = True
    if props["UnitFileState"] not in BOOT_OFF:
        systemctl(deps, "disable", unit)
        if unit_props(deps, unit, "UnitFileState")["UnitFileState"] not in BOOT_OFF:
            return stopped_now, False, "disable_failed", state
        disabled_now = True
    return stopped_now, disabled_now, None, state


def keep_off_error(result, problem, unit, state, prefix=""):
    """E_LN_STOP or E_LN_DISABLE when keep_off could not stop or disable unit, with the command to run."""
    if problem == "stop_failed":
        result.error("E_LN_STOP", "operational",
                     "%s%s did not stop (state: %s): it runs with a config that is not Tor-only at rest, and "
                     "TunnelSats is off. Stop it with: sudo systemctl stop %s, then remove the listed TunnelSats "
                     "settings and choose REMOVE again" % (prefix, unit, state, unit), EXIT_OPERATIONAL)
    else:
        result.error("E_LN_DISABLE", "operational",
                     "%s%s is stopped but could not be disabled: with TunnelSats off, the next boot would start it "
                     "with a config that is not Tor-only at rest. Run: sudo systemctl disable %s, then remove the "
                     "listed TunnelSats settings and choose REMOVE again" % (prefix, unit, unit), EXIT_OPERATIONAL)


def cmd_uninstall(deps, args, result):
    if not args.yes:
        raise ModuleError("E_CONFIRMATION_REQUIRED", "usage", "REMOVE needs --yes", EXIT_USAGE)
    state = load_state(deps)
    conf = read_rb_conf(deps)
    result.fields.update({"removed": False, "remaining": [], "ln_was_active": False, "ln_started": False,
                          "ln_reenabled": False, "ln_stopped_first": False, "node_config": None, "block": None,
                          "purged": False, "artifacts": [], "announce_cleanup": None, "tool_announce_cleanup": None,
                          "tool_warnings": [], "tool_errors": []})
    if state and state.get("mode") == "adopted_legacy":
        with Lock(deps, wait=30):
            purge(deps)
        result.fields.update({"removed": True, "purged": True, "forgotten": True})
        return
    rc, tool = its(deps, ["detect", "--json"], timeout=ITS_TIMEOUT["detect"])
    managed = ((tool or {}).get("install") or {}).get("kind") == "managed"
    if not state and conf.get("tunnelsats") != "on" and not managed:
        raise ModuleError("E_NOT_CONFIGURED", "not_configured", "TunnelSats is not set up on this node",
                          EXIT_NOT_CONFIGURED)
    impl = (state or {}).get("impl") or conf.get("tunnelsatsImpl")
    impl = impl if impl in IMPLS else select_impl(conf)[0]
    with Lock(deps, wait=30):
        # the address LND announced at its last start, read before uninstall removes /run/tunnelsats
        record = read_guard_record(deps, BASES["lnd"])
        blitz_conf_set(deps, "tunnelsats", "off")
        try:
            for entry in os.listdir(deps.path(RUN_DIR)):
                if entry.startswith("hybrid-") and entry.endswith(".env"):
                    os.unlink(deps.path("%s/%s" % (RUN_DIR, entry)))
        except FileNotFoundError:
            pass
        rc, block = its(deps, ["block-remove", "--json"], timeout=30)
        result.fields["block"] = (block or {}).get("state") if rc == 0 else "error:%s" % tool_error(block, "E_BLOCK")
        pending_doc = load_pending(deps)
        keep_tick = not args.purge and bool(
            pending_doc.get("order") or pending_doc.get("renewal") or pending_doc.get("reset")
            or pending_doc.get("retained_orders")
        )
        if not keep_tick:
            deps.run([ITS, "tick-timer", "off"], timeout=60)
        unit = UNITS.get(impl)
        doc = {}
        notes = []
        result.fields["warnings"] = notes
        if managed:
            # the unit of the managed install: detect names its drop-in (no extra call), which also
            # holds when state.impl names the other implementation; else the stored implementation's
            dropin = dropin_unit(tool)
            unit = dropin or unit
            # an earlier REMOVE that did not finish may have stopped the unit (read while it is stopped)
            pending = pending_removal(deps, state)
            if pending is None:
                pending, outcome = stop_unless_tor_only(deps, unit, managed=dropin)
                result.fields["ln_stopped_first"] = outcome in ("stopped", "disable_failed")
                unit = pending["unit"] if pending else unit
                if outcome in ("stop_failed", "disable_failed"):
                    # the tool would start the unit again with that config, or the next boot would start
                    # it without the tunnel: the tool does not run, the dataplane and kill switch stay
                    result.fields.update({"remaining": ["managed dataplane"], "ln_was_active": True})
                    if outcome == "stop_failed":
                        result.error("E_LN_STOP", "operational",
                                     "%s did not stop (state: %s), so the TunnelSats uninstall did not run: it would "
                                     "start %s again with a config that is not Tor-only at rest. The tunnel and its "
                                     "kill switch stay in place; run REMOVE again" % (unit, pending["state"], unit),
                                     EXIT_OPERATIONAL)
                    else:
                        result.error("E_LN_DISABLE", "operational",
                                     "%s could not be disabled, so the TunnelSats uninstall did not run: without the "
                                     "tunnel, the next boot would start it with a config that is not Tor-only at "
                                     "rest. %s stays stopped, and the tunnel and its kill switch stay in place; run "
                                     "REMOVE again" % (unit, unit), EXIT_OPERATIONAL)
                    return
            doc, note = tool_uninstall(deps, unit, own_disable=True)
            if note:
                notes.append(note)
            unit = doc.get("unit") if doc.get("unit") in UNITS.values() else unit
            if pending and pending["unit"] == unit:
                doc = dict(doc, ln_was_active=bool(doc.get("ln_was_active")) or pending["ln_was_active"],
                           ln_disabled=bool(doc.get("ln_disabled")) or pending["ln_disabled"])
            result.fields.update({"remaining": doc["remaining"], "ln_was_active": bool(doc.get("ln_was_active")),
                                  "ln_started": bool(doc.get("ln_started")), "node_config": doc.get("node_config"),
                                  "tool_errors": doc.get("tool_errors") or []})
            # the tool's own step for LND's node announcement, for the record: REMOVE checks the
            # announcement again itself below, and only that step decides what REMOVE reports and warns
            if doc.get("announce_cleanup") in TOOL_ANNOUNCE_RESULTS:
                result.fields["tool_announce_cleanup"] = doc["announce_cleanup"]
            result.fields["tool_warnings"] = [w for w in doc.get("warnings") or [] if isinstance(w, str)][:10]
        else:
            # a REMOVE refused earlier (config not Tor-only at rest) kept this unit stopped: this run
            # audits it again and enables and starts it only if the config is Tor-only now
            pending = pending_removal(deps, state)
            if pending:
                doc = pending
                unit = pending["unit"]
                result.fields["ln_was_active"] = pending["ln_was_active"]
        # uninstall --managed starts the unit again itself when it finds the node config clean (since
        # tunnelsats PR 227 also with the start guard's variable in ExecStart: the env file this REMOVE
        # deleted counts like an empty one). It leaves the unit stopped, and disabled, when the config
        # holds TunnelSats settings or cannot be checked, and it never starts a unit that was not running
        # when it began, such as one an earlier REMOVE left stopped (remove_pending) or one this REMOVE
        # stopped first (stop_unless_tor_only). Then, and when the report was lost, only this REMOVE's
        # own audit of exactly that unit's implementation may enable and start it; the other one is
        # checked too. When that audit does not find the config Tor-only at rest, REMOVE itself makes
        # sure the unit neither runs nor starts at the next boot (keep_off), whatever the tool reported.
        unit_impl = IMPL_OF_UNIT.get(unit) if unit else None
        main_ok = other_ok = True
        main_doc = other_doc = None
        if unit_impl:
            main_doc = at_rest_audit(deps, unit_impl, repair=True)
            other_doc = at_rest_audit(deps, OTHER_IMPL[unit_impl], repair=False)
            result.fields["at_rest"] = (main_doc or {}).get("status")
            result.fields["other_impl_at_rest"] = (other_doc or {}).get("status")
            main_ok = at_rest_ok(main_doc)
            other_ok = at_rest_ok(other_doc, installed_only=True)
        complete = not result.fields["remaining"]
        tool_errors = result.fields["tool_errors"]
        problem = state_now = None
        if unit and not main_ok and (managed or pending) and "E_LN_STOP" not in tool_errors:
            # TunnelSats is off and the tunnel is gone or partly gone, so no start guard repairs this
            # config: nothing may run or start the unit with it, now or at the next boot. Read back from
            # systemd, so a failed disable by the tool (E_LN_DISABLE) or a lost report is covered too
            stopped_now, disabled_now, problem, state_now = keep_off(deps, unit)
            if stopped_now:
                doc = dict(doc, ln_was_active=True, ln_started=False)
                result.fields.update({"ln_was_active": True, "ln_started": False})
            if disabled_now:
                doc = dict(doc, ln_disabled=True)
        if complete and main_ok and doc.get("ln_disabled") and unit:
            result.fields["ln_reenabled"] = systemctl(deps, "enable", unit)
        if complete and main_ok and doc.get("ln_was_active") and not doc.get("ln_started") and unit:
            result.fields["ln_started"] = systemctl(deps, "start", unit)
        if not complete:
            if "E_LN_STOP" in tool_errors:
                # the tool removed nothing: the unit did not stop, the tunnel and its kill switch stay
                state_now = (unit_props(deps, unit, "ActiveState")["ActiveState"] if unit else "") or "unknown"
                keep_pending_removal(deps, unit, dict(doc, ln_was_active=True, ln_started=False), reason="stop_failed",
                                     tunnel="in_place")
                result.error("E_LN_STOP", "operational",
                             "%s did not stop (state: %s), so the TunnelSats uninstall removed nothing. The tunnel "
                             "and its kill switch stay in place; run REMOVE again" % (unit, state_now), EXIT_OPERATIONAL)
                return
            # the next REMOVE finds the unit stopped by this one in remove_pending and starts it again
            keep_pending_removal(deps, unit, dict(doc, ln_started=False) if problem else doc, reason=problem,
                                 tunnel="partly_removed")
            left = "removal incomplete: %s; " % ", ".join(result.fields["remaining"])
            if problem:
                keep_off_error(result, problem, unit, state_now, left)
            else:
                state_now = (unit_props(deps, unit, "ActiveState")["ActiveState"] if unit else "") or "unknown"
                running = bool(unit) and state_now not in ("inactive", "failed")
                result.error("E_REMOVE_INCOMPLETE", "operational", "%s%s, run REMOVE again" % (
                    left, "%s is %s" % (unit, state_now) if running else "Lightning stays stopped"), EXIT_OPERATIONAL)
            return
        other_action = None
        if not other_ok:
            # the other implementation's config is read-only for TunnelSats and never started by it
            other_unit = UNITS[OTHER_IMPL[unit_impl]]
            other_action = at_rest_action(OTHER_IMPL[unit_impl], other_doc, other_unit, None)
        if not main_ok:
            then = None
            if problem:
                messages = []
            elif doc.get("ln_disabled"):
                then = "systemctl enable --now %s" % unit
                messages = ["%s stays stopped and disabled: its config is not Tor-only at rest" % unit]
            elif doc.get("ln_was_active") and not doc.get("ln_started"):
                then = "systemctl start %s" % unit
                messages = ["%s stays stopped: its config is not Tor-only at rest" % unit]
            else:
                messages = ["the config of %s is not Tor-only at rest" % unit]
            actions = [at_rest_action(unit_impl, main_doc, unit, then)]
            if other_action:
                actions.append(other_action)
                messages.append("the config of %s is not Tor-only at rest" % other_unit)
            result.fields["action_required"] = {
                "reason": "node_config_clearnet" if any(a["lines"] for a in actions) else "node_config_unknown",
                "detail": "; ".join(a["detail"] for a in actions),
                "lines": [line for a in actions for line in a["lines"]],
                "then": then}
            keep_pending_removal(deps, unit, dict(doc, ln_started=False) if problem else doc, reason=problem,
                                 tunnel="removed")
            if problem:
                keep_off_error(result, problem, unit, state_now, "; ".join(messages + [""]))
            else:
                result.error("E_AT_REST_UNREPAIRABLE", "operational",
                             "%s. Remove the listed TunnelSats settings%s" % (
                                 "; ".join(messages), ", then run: sudo %s" % then if then else ""), EXIT_OPERATIONAL)
            return
        candidates = announce_candidates(deps, state, record) if unit == UNITS["lnd"] else []
        cleanup, cleanup_notes = announce_cleanup(deps, unit, state, record, candidates=candidates)
        result.fields["announce_cleanup"] = cleanup
        leftovers, warnings = zero_artifacts(deps, impl, keep_tick_timer=keep_tick)
        if other_action:
            result.fields["other_impl_lines"] = other_action["lines"]
            warnings.insert(0, "%s was left as it is: its config is not Tor-only at rest (%s). TunnelSats never "
                               "starts it; %s before you start it" % (
                                   other_unit, other_action["detail"],
                                   "remove these settings: %s" % "; ".join(other_action["lines"])
                                   if other_action["lines"] else "check its config"))
        result.fields["artifacts"] = leftovers
        result.fields["warnings"] = notes + warnings + cleanup_notes + tool_announce_notes(
            result.fields["tool_announce_cleanup"], result.fields["tool_warnings"], candidates)
        if leftovers:
            result.error("E_ARTIFACTS_LEFT", "operational", "left behind: %s" % "; ".join(leftovers), EXIT_OPERATIONAL)
            return
        result.fields["removed"] = True
        if args.purge:
            purge(deps)
            result.fields["purged"] = True
        else:
            clear_pending_removal(deps)


# ------------------------------------------------------------------------------------------
# repair
# ------------------------------------------------------------------------------------------

def dataplane_healthy(deps, impl):
    rc, doc = its(deps, ["verify", "--no-probe", "--json"], timeout=ITS_TIMEOUT["verify_no_probe"])
    if rc not in (0, 5) or not doc:
        return False
    if doc.get("install_state") != "installed" or doc.get("unit") != UNITS[impl] or doc.get("emergency_block"):
        return False
    return not any(isinstance(c, dict) and c.get("class") == "unsafe" and c.get("result") == "fail"
                   for c in doc.get("checks") or [])


def cmd_repair(deps, args, result):
    if not args.yes:
        raise ModuleError("E_CONFIRMATION_REQUIRED", "usage", "REPAIR needs --yes (it may restart Lightning)",
                          EXIT_USAGE)
    state = load_state(deps)
    if state is None:
        raise ModuleError("E_NOT_CONFIGURED", "not_configured", "no stored subscription: IMPORT first",
                          EXIT_NOT_CONFIGURED)
    if state.get("mode") == "adopted_legacy":
        raise ModuleError("E_UPGRADE_UNAVAILABLE", "refused",
                          "the adopted standard install is not in managed mode yet: run adopt --upgrade --yes",
                          EXIT_REFUSED)
    cfg = load_stored_config(deps)
    if cfg is None or cfg["public_key"] != state.get("public_key"):
        raise ModuleError("E_STORED_CONFIG", "operational", "the stored config is missing or invalid: IMPORT again",
                          EXIT_OPERATIONAL)
    conf = read_rb_conf(deps)
    if conf.get("runBehindTor") != "on":
        # the start guard would block every mainnet start (tor_off); a refusal keeps Lightning running
        raise ModuleError("E_TOR_REQUIRED", "refused",
                          "TunnelSats needs Tor: switch Tor on first (SSH menu > SETTINGS), then REPAIR",
                          EXIT_REFUSED)
    impl, why = select_impl(conf, args.impl)
    if impl is None:
        raise ModuleError("E_NOT_ELIGIBLE", "not_eligible", "no Lightning implementation to tunnel (%s)" % why,
                          EXIT_NOT_CONFIGURED)
    actions = []
    result.fields.update({"actions": actions, "ln_start_wait": None})
    with Lock(deps, wait=30):
        rc, tool = its(deps, ["detect", "--json"], timeout=ITS_TIMEOUT["detect"])
        managed = ((tool or {}).get("install") or {}).get("kind") == "managed"
        rc, its_state = its(deps, ["status", "--json"], timeout=ITS_TIMEOUT["status"])
        current_tool = (its_state or {}).get("tool_hash") == "current"
        unit = UNITS[impl]
        was_active = unit_props(deps, unit, "ActiveState")["ActiveState"] == "active"
        if managed and (not current_tool or state.get("impl") != impl or not dataplane_healthy(deps, impl)):
            # the unit of the old install: the one of the stored implementation
            doc, note = tool_uninstall(deps, UNITS[state["impl"]] if state.get("impl") in IMPLS else unit)
            actions.append("uninstall")
            if note:
                result.fields["warnings"] = [note]
            if doc["remaining"]:
                raise ModuleError("E_REMOVE_INCOMPLETE", "operational",
                                  "the old dataplane could not be removed; Lightning stays stopped", EXIT_OPERATIONAL)
            if doc.get("ln_disabled") and doc.get("unit") in UNITS.values():
                # as in REMOVE: undo uninstall's disable only after a Tor-only at-rest audit of that
                # unit (if the activation below fails, TunnelSats is off and the guard repairs nothing)
                audit = at_rest_audit(deps, IMPL_OF_UNIT[doc["unit"]], repair=True)
                if not at_rest_ok(audit):
                    then = "systemctl enable --now %s" % doc["unit"]
                    result.fields["action_required"] = at_rest_action(IMPL_OF_UNIT[doc["unit"]], audit, doc["unit"], then)
                    raise ModuleError("E_AT_REST_UNREPAIRABLE", "operational",
                                      "%s stays stopped and disabled: its config is not Tor-only at rest. Remove the "
                                      "listed TunnelSats settings, then run: sudo %s, and REPAIR again"
                                      % (doc["unit"], then), EXIT_OPERATIONAL)
                systemctl(deps, "enable", doc["unit"])
                actions.append("reenable")
            was_active = was_active or bool(doc.get("ln_was_active"))
            managed = False
        if not managed:
            state["impl"] = impl
            state["activation_pending"] = False
            activate(deps, impl, result, stored_writer=lambda: save_state(deps, state))
            actions.append("install")
            if was_active and unit_props(deps, unit, "ActiveState")["ActiveState"] != "active":
                systemctl(deps, "start", unit)
                actions.append("start")
        else:
            rc, out, _err = deps.run([ITS, "fetch", "--json"], timeout=ITS_TIMEOUT["fetch"])
            if not unit_template_ok(deps, impl):
                regenerate_unit(deps, impl)
                actions.append("unit_regenerated")
            blitz_conf_set(deps, "tunnelsatsImpl", impl)
            blitz_conf_set(deps, "tunnelsats", "on")
            rc, block = its(deps, ["block-insert", "--json"], timeout=30)
            actions.append("block" if rc == 0 else "block_failed")
            deps.run([ITS, "tick-timer", "on"], timeout=60)
            actions.append("tick_timer")
    # the reinstall restarted a running unit (the tool's install, or the start above): the check
    # waits until that start is done; the path without a restart makes no wait
    wait = wait_until_started(deps, unit) if "install" in actions else None
    result.fields["ln_start_wait"] = wait
    checked = check_after_activation(deps, wait) if "install" in actions else with_start_wait(run_check(deps), wait)
    result.fields.update(checked)
    if start_wait_detail(wait):
        result.fields["warnings"] = list(result.fields.get("warnings") or []) + [start_wait_detail(wait)]
    result.exit_code = verdict_exit(checked["verdict"])


# ------------------------------------------------------------------------------------------
# subscriptions-list, tick
# ------------------------------------------------------------------------------------------

def cmd_subscriptions_list(deps, args, result):
    state = load_state(deps)
    items = []
    if state and state.get("public_key"):
        conf = read_rb_conf(deps)
        data = (state.get("api") or {}).get("data") or {}
        expiry = parse_iso(data.get("expiry") or state.get("valid_until") or "")
        warning = ""
        if expiry and expiry < deps.clock():
            warning = "expired"
        elif data.get("peer_status") == "disabled":
            warning = "peer disabled (bandwidth or subscription)"
        elif (state.get("last_check") or {}).get("verdict") not in (None, "protected"):
            warning = "check: %s" % state["last_check"]["verdict"]
        server = data.get("server_domain") or state.get("server_domain") or state.get("endpoint_host")
        items.append({
            "type": "tunnelsats-v1",
            "id": hashlib.sha256(state["public_key"].encode()).hexdigest()[:8],
            "name": server, "active": conf.get("tunnelsats") == "on" or state.get("mode") == "adopted_legacy",
            "warning": warning,
            "description": "WireGuard VPN for Lightning clearnet via %s%s" % (
                server, ", expires %s" % expiry.strftime("%Y-%m-%d") if expiry else ""),
            "time_created": state.get("imported_at"),
        })
    result.fields["subscriptions"] = items


NOTIFY_MESSAGES = {
    "payment_received": "TunnelSats: payment received. Claiming and activating your subscription.",
    "activation_done": "TunnelSats: tunnel active. Clearnet connections now route through TunnelSats.",
    "expiry_soon": "TunnelSats: subscription expires soon (within 72 hours). Renew in the SSH menu > SUBSCRIBE > TunnelSats.",
    "expired": "TunnelSats: subscription expired. Renew in the SSH menu > SUBSCRIBE > TunnelSats.",
    "bandwidth_high": "TunnelSats: monthly bandwidth high (80% or more used). Check status in the SSH menu.",
    "bandwidth_exhausted": "TunnelSats: monthly bandwidth exhausted or peer disabled. Top up or renew in the SSH menu.",
    "verdict_degraded": "TunnelSats: connection status is DEGRADED (clearnet traffic is blocked by the kill switch while the tunnel recovers).",
    "verdict_unsafe": "TunnelSats: connection status is UNSAFE. Run CHECK or REPAIR in the SSH menu > SUBSCRIBE > TunnelSats.",
    "all_clear": "TunnelSats: connection status is protected again.",
    "restart_needed": RESTART_MESSAGE,
}


def empty_notify_state():
    return {
        "expiry_cycle": None,
        "bandwidth_cycle": None,
        "last_verdict": "protected",
        "verdict_seq": 0,
        "verdict_warning_handed_off": False,
        "daily": {"date": None, "count": 0},
        "events": {},
        "last_event": None,
        "outcome": None,
    }


def _ensure_notify_state(state):
    raw = (state or {}).get("notify_state")
    base = empty_notify_state()
    if isinstance(raw, dict):
        for k in ("expiry_cycle", "bandwidth_cycle", "last_verdict", "verdict_seq",
                  "verdict_warning_handed_off", "last_event", "outcome"):
            if k in raw:
                base[k] = raw[k]
        if isinstance(raw.get("daily"), dict):
            base["daily"] = {"date": raw["daily"].get("date"), "count": int(raw["daily"].get("count") or 0)}
        if isinstance(raw.get("events"), dict):
            base["events"] = {k: dict(v) for k, v in raw["events"].items() if isinstance(v, dict)}
    return base


def send_event_notification(deps, conf, nstate, event, cycle_key, now_dt=None):
    """Sends a deduplicated event notification via blitz.notify.sh send."""
    now_dt = now_dt or deps.clock()
    events = nstate.setdefault("events", {})
    record = events.get(event)
    if not isinstance(record, dict) or record.get("cycle") != cycle_key:
        record = {"cycle": cycle_key, "attempts": 0, "outcome": None}
    if record.get("outcome") in ("handed_off", "skipped_disabled", "dropped", "capped"):
        return None
    is_verdict_event = event in ("verdict_degraded", "verdict_unsafe", "all_clear")
    today = now_dt.strftime("%Y-%m-%d")
    daily = nstate.setdefault("daily", {"date": today, "count": 0})
    if daily.get("date") != today:
        daily["date"] = today
        daily["count"] = 0
    if is_verdict_event and int(daily.get("count") or 0) >= 10:
        record["outcome"] = "capped"
    elif conf.get("notify") != "on":
        record["outcome"] = "skipped_disabled"
    else:
        record["attempts"] += 1
        if is_verdict_event:
            daily["count"] = int(daily.get("count") or 0) + 1
        rc, _out, _err = deps.run([NOTIFY, "send", NOTIFY_MESSAGES[event]], timeout=60)
        if rc == 0:
            record["outcome"] = "handed_off"
        else:
            record["outcome"] = "failed" if record["attempts"] < 3 else "dropped"
    record["updated_at"] = iso(now_dt)
    events[event] = record
    nstate["last_event"] = event
    nstate["outcome"] = record["outcome"]
    deps.log("notify event=%s outcome=%s attempt=%d" % (event, record["outcome"], record["attempts"]))
    return {"event": event, "outcome": record["outcome"], "attempt": record["attempts"]}


def notify(deps, conf, state, invocation):
    """The restart notice, once per Lightning start (invocation). Returns the notification entry."""
    record = state.get("notify") or {}
    if record.get("invocation_id") != invocation:
        record = {"invocation_id": invocation, "attempts": 0, "outcome": None}
    if record.get("outcome") in ("handed_off", "skipped_disabled", "dropped"):
        return None
    if conf.get("notify") != "on":
        record["outcome"] = "skipped_disabled"
    else:
        record["attempts"] += 1
        rc, _out, _err = deps.run([NOTIFY, "send", RESTART_MESSAGE], timeout=60)
        if rc == 0:
            record["outcome"] = "handed_off"
        else:
            record["outcome"] = "failed" if record["attempts"] < 3 else "dropped"
    state["notify"] = record
    if record["outcome"] != "failed":
        state["notified_invocation_id"] = invocation
    deps.log("notify event=restart_needed outcome=%s attempt=%d" % (record["outcome"], record["attempts"]))
    return {"event": "restart_needed", "outcome": record["outcome"], "attempt": record["attempts"]}


def _tick_live_verdict(deps, impl, props):
    """Evaluates the live kernel verdict via verify --no-probe --json."""
    rc, verify = its(deps, ["verify", "--no-probe", "--json"], timeout=ITS_TIMEOUT["verify_no_probe"])
    if verify is None:
        return "unsafe"
    if rc == 0 or verify.get("verdict") == "protected":
        return "protected"
    if rc == 4 or verify.get("verdict") == "unsafe":
        return "unsafe"
    checks = [c for c in (verify.get("checks") or []) if isinstance(c, dict)]
    failed = []
    for c in checks:
        if c.get("result") != "fail":
            continue
        if (c.get("id") == "ln_membership" and props.get("ActiveState") == "active"
                and "is activating" in str(c.get("detail") or "")):
            continue
        failed.append(c)
    if not failed and rc == 5:
        return "protected"
    if any(c.get("class") == "unsafe" for c in failed):
        return "unsafe"
    return "degraded" if rc in (3, 5) or verify.get("verdict") == "degraded" else "unsafe"


def _load_status_file(deps, path):
    try:
        with open(deps.path(path), "rb") as handle:
            raw = handle.read(API_MAX_BYTES + 1)
    except OSError:
        raise ModuleError("E_API_INVALID", "invalid_response", "cannot read --status-file", EXIT_INVALID_API) from None
    if not raw or len(raw) > API_MAX_BYTES:
        raise ModuleError("E_API_INVALID", "invalid_response", "--status-file is empty or too large", EXIT_INVALID_API)
    try:
        doc = json.loads(raw.decode("utf-8", "replace"))
    except ValueError:
        raise ModuleError("E_API_INVALID", "invalid_response", "--status-file is not valid JSON", EXIT_INVALID_API) from None
    validated = validate_status(doc)
    if validated is None and isinstance(doc, dict) and isinstance(doc.get("raw_api"), dict):
        validated = validate_status(doc["raw_api"])
    if validated is None:
        raise ModuleError("E_API_INVALID", "invalid_response", "--status-file failed status validation", EXIT_INVALID_API)
    return validated


def cmd_tick(deps, args, result):
    now_arg = getattr(args, "now", None)
    status_file_arg = getattr(args, "status_file", None)
    no_persist = bool(getattr(args, "no_persist", False))
    if (now_arg is not None or status_file_arg is not None) and not no_persist:
        raise ModuleError("E_USAGE", "usage", "--now and --status-file require --no-persist", EXIT_USAGE)
    is_test_hook = bool(now_arg is not None or status_file_arg is not None or no_persist)
    now_dt = deps.clock()
    if now_arg is not None:
        now_dt = parse_iso(now_arg)
        if now_dt is None:
            raise ModuleError("E_USAGE", "usage", "--now must be an ISO-8601 UTC timestamp", EXIT_USAGE)
        deps.log("tick test_hook now=%s no_persist=true" % now_arg)
    override_api_data = None
    if status_file_arg is not None:
        override_api_data = _load_status_file(deps, status_file_arg)
        deps.log("tick test_hook status_file=%s no_persist=true" % status_file_arg)

    result.fields.update({"restart_needed": False, "notifications": [], "test_hook": True if is_test_hook else None})
    try:
        lock = Lock(deps, wait=0).__enter__()
    except ModuleError:
        result.fields["skipped"] = "another TunnelSats action is running"
        return
    try:
        conf = read_rb_conf(deps)
        state = load_state(deps)
        nstate = _ensure_notify_state(state)
        state_dirty = False

        if not is_test_hook:
            pending = load_pending(deps)
            if pending.get("order") or pending.get("renewal") or pending.get("reset") or pending.get("retained_orders"):
                def on_settle_notify(ev, cycle_key):
                    nonlocal state_dirty
                    entry = send_event_notification(deps, conf, nstate, ev, cycle_key, now_dt=now_dt)
                    if entry:
                        result.fields["notifications"].append(entry)
                        state_dirty = True
                        cur_st = load_state(deps)
                        if cur_st is not None:
                            cur_st["notify_state"] = dict(nstate)
                            save_state(deps, cur_st)

                settle_res = settle_once(deps, result, foreground=False, notify_event=on_settle_notify, use_lock=False)
                result.fields["settle"] = {k: v for k, v in settle_res.items() if k != "done"}
                conf = read_rb_conf(deps)
                state = load_state(deps)
                if state is not None and state_dirty:
                    state["notify_state"] = dict(nstate)
                    save_state(deps, state)

        if conf.get("tunnelsats") != "on" or not state:
            return
        impl = state.get("impl") or conf.get("tunnelsatsImpl")
        if impl not in IMPLS:
            return

        # 6-hour status sync when not in a synthetic test hook
        if not is_test_hook and override_api_data is None and state.get("public_key"):
            api = state.get("api") or {}
            checked_dt = parse_iso(api.get("checked_at"))
            if checked_dt is None or (now_dt - checked_dt).total_seconds() > API_CACHE_SECONDS:
                s_out, s_data, _s_det = api_status(deps, state["public_key"])
                api["outcome"] = s_out
                api["checked_at"] = iso(now_dt)
                if s_out == "confirmed":
                    api["data"] = s_data
                    api["confirmed_at"] = iso(now_dt)
                    state["valid_until"] = s_data["expiry"]
                state["api"] = api
                state_dirty = True

        # Expiry and bandwidth notifications
        api_data = override_api_data if override_api_data is not None else ((state.get("api") or {}).get("data") or {})
        expiry_str = api_data.get("expiry") or state.get("valid_until")
        expiry_dt = parse_iso(expiry_str)
        if expiry_str and nstate.get("expiry_cycle") != expiry_str:
            nstate["expiry_cycle"] = expiry_str
            nstate["events"].pop("expiry_soon", None)
            nstate["events"].pop("expired", None)
            state_dirty = True
        if expiry_dt is not None:
            rem_s = (expiry_dt - now_dt).total_seconds()
            if rem_s <= 0:
                entry = send_event_notification(deps, conf, nstate, "expired", expiry_str, now_dt=now_dt)
                if entry:
                    result.fields["notifications"].append(entry)
                    state_dirty = True
            elif rem_s <= 72 * 3600:
                entry = send_event_notification(deps, conf, nstate, "expiry_soon", expiry_str, now_dt=now_dt)
                if entry:
                    result.fields["notifications"].append(entry)
                    state_dirty = True

        if api_data:
            used = api_data.get("bandwidth_used_gb")
            limit = api_data.get("bandwidth_limit_gb")
            peer_status = api_data.get("peer_status")
            bw_cycle = "%s:%s" % (expiry_str or "", api_data.get("resets_this_month", 0))
            if nstate.get("bandwidth_cycle") != bw_cycle:
                nstate["bandwidth_cycle"] = bw_cycle
                nstate["events"].pop("bandwidth_high", None)
                nstate["events"].pop("bandwidth_exhausted", None)
                state_dirty = True
            if peer_status == "disabled" or (is_number(used) and is_number(limit) and limit > 0 and used >= limit):
                entry = send_event_notification(deps, conf, nstate, "bandwidth_exhausted", bw_cycle, now_dt=now_dt)
                if entry:
                    result.fields["notifications"].append(entry)
                    state_dirty = True
            elif is_number(used) and is_number(limit) and limit > 0 and (used / float(limit)) >= 0.80:
                entry = send_event_notification(deps, conf, nstate, "bandwidth_high", bw_cycle, now_dt=now_dt)
                if entry:
                    result.fields["notifications"].append(entry)
                    state_dirty = True
            elif is_number(used) and is_number(limit) and limit > 0 and (used / float(limit)) < 0.80 and peer_status == "enabled":
                if "bandwidth_high" in nstate["events"] or "bandwidth_exhausted" in nstate["events"]:
                    nstate["events"].pop("bandwidth_high", None)
                    nstate["events"].pop("bandwidth_exhausted", None)
                    state_dirty = True

        if not is_test_hook:
            props = unit_props(deps, UNITS[impl], "ActiveState", "InvocationID")
            record = read_guard_record(deps, BASES[impl])
            if (props["ActiveState"] == "active" and record and props["InvocationID"]
                    and record.get("invocation_id") == props["InvocationID"]
                    and record.get("decision") in ("tor-only", "hybrid")
                    and record.get("reason") in RESTARTABLE):
                rc, dry = its(deps, ["guard", impl, "mainnet", "--dry-run", "--json"], timeout=ITS_TIMEOUT["guard_dry_run"])
                if dry and dry.get("decision") == "hybrid" and (impl != "cl" or dry.get("reason") == "ok"):
                    result.fields["restart_needed"] = True
                    entry = notify(deps, conf, state, props["InvocationID"])
                    if entry:
                        result.fields["notifications"].append(entry)
                        state_dirty = True

            if not result.fields["restart_needed"]:
                live_verdict = _tick_live_verdict(deps, impl, props)
                prev_verdict = nstate.get("last_verdict") or "protected"
                if live_verdict in ("degraded", "unsafe"):
                    ev_name = "verdict_%s" % live_verdict
                    if prev_verdict != live_verdict:
                        nstate["verdict_seq"] = int(nstate.get("verdict_seq") or 0) + 1
                        nstate["last_verdict"] = live_verdict
                        state_dirty = True
                    v_cycle = "v:%d:%s" % (int(nstate.get("verdict_seq") or 1), live_verdict)
                    entry = send_event_notification(deps, conf, nstate, ev_name, v_cycle, now_dt=now_dt)
                    if entry:
                        result.fields["notifications"].append(entry)
                        if entry["outcome"] == "handed_off":
                            nstate["verdict_warning_handed_off"] = True
                        state_dirty = True
                elif live_verdict == "protected":
                    if prev_verdict != "protected":
                        nstate["verdict_seq"] = int(nstate.get("verdict_seq") or 0) + 1
                        nstate["last_verdict"] = "protected"
                        state_dirty = True
                    if nstate.get("verdict_warning_handed_off"):
                        v_cycle = "clear:%d" % int(nstate.get("verdict_seq") or 1)
                        entry = send_event_notification(deps, conf, nstate, "all_clear", v_cycle, now_dt=now_dt)
                        if entry:
                            result.fields["notifications"].append(entry)
                            if entry["outcome"] in ("handed_off", "skipped_disabled", "dropped", "capped"):
                                nstate["verdict_warning_handed_off"] = False
                            state_dirty = True

        if state_dirty and not no_persist:
            state["notify_state"] = nstate
            save_state(deps, state)
    finally:
        lock.__exit__(None, None, None)


# ------------------------------------------------------------------------------------------
# menu (TUI)
# ------------------------------------------------------------------------------------------

ABOUT_TEXT = """TunnelSats (https://tunnelsats.com) routes this node's Lightning clearnet
traffic through a WireGuard VPN. Peers see the VPN server's address, never
your home IP.

- Your node becomes reachable on clearnet via the VPN server and connects to
  clearnet peers through the tunnel. Tor stays on for onion peers.
- If the tunnel is down or the subscription ended, clearnet Lightning traffic
  is blocked. Onion peers keep working.
- TunnelSats sees your home IP (as the VPN client) and your WireGuard public
  key. Your private key never leaves this node.

Official links & resources (https://tunnelsats.com):
- Guide:   https://tunnelsats.com/guide   (Setup & hybrid mode guides)
- Status:  https://tunnelsats.com/status  (Live server health & latency)
- FAQ:     https://tunnelsats.com/faq     (Pricing, bandwidth & Q&A)
- Support: https://tunnelsats.com/support (Nostr, Telegram & help)
- API:     https://api.tunnelsats.com     (Public API & L402/x402 docs)

Buy a subscription in the menu (BUY) or at https://tunnelsats.com (IMPORT)."""

VERDICT_TEXT = {"protected": "Protected", "degraded": "Clearnet paused, Tor peers keep working",
                "unsafe": "Action needed", "not_configured": "Not set up"}


def check_text(checked):
    lines = [VERDICT_TEXT.get(checked["verdict"], checked["verdict"]), ""]
    for c in checked["checks"]:
        if c["result"] == "fail":
            lines.append("- %s: %s" % (c["id"], c["detail"]))
    if checked["verdict"] == "protected":
        lines.append("Every check passed.")
    return "\n".join(lines)


def menu_run(deps, verb_args):
    """Runs a verb in-process and returns its document."""
    result = Result(verb_args[0])
    try:
        args = build_parser().parse_args(verb_args)
        HANDLERS[verb_args[0]](deps, args, result)
    except (ModuleError, _UsageError) as exc:
        code = getattr(exc, "code", "E_USAGE")
        result.error(code, getattr(exc, "cls", "usage"), str(exc), getattr(exc, "exit_code", EXIT_USAGE))
    return result.document()


def menu_choices(deps, state, conf, found=None):
    """The menu entries (tag, text) and a notice shown above them, or None. START and RESTART only
    while TunnelSats is on: the start guard then audits the config at rest before Lightning runs.
    With TunnelSats off (after REMOVE) nothing would, so this menu never starts Lightning then;
    after a refused REMOVE it shows what keeps Lightning stopped and offers REMOVE again."""
    pending_store = load_pending(deps)
    if state is None:
        choices = [("BUY", "Buy a new TunnelSats subscription"),
                   ("IMPORT", "Import a WireGuard config (bought on tunnelsats.com)")]
        if pending_store.get("order") or pending_store.get("retained_orders"):
            choices.insert(1, ("RESUME", "Resume pending subscription order"))
        if (found or {}).get("adopt_available"):
            choices.append(("ADOPT", "Take over the existing TunnelSats setup"))
        choices.append(("ABOUT", "How it works, privacy trade-offs & links"))
        return choices, None
    active_ts = conf.get("tunnelsats") == "on"
    impl = state.get("impl") or conf.get("tunnelsatsImpl") or "lnd"
    pending = state.get("remove_pending")
    notice = None
    remove = ("REMOVE", "Remove TunnelSats from this node")
    has_remove_pending = not active_ts and isinstance(pending, dict) and pending.get("unit") in UNITS.values()
    if has_remove_pending:
        notice = pending_removal_text(deps, pending)
        remove = ("REMOVE", "Remove again: check the config, then start Lightning")
    choices = [("STATUS", "Subscription and tunnel status"), ("CHECK", "Connection check")]
    if not has_remove_pending:
        choices.extend([
            ("RENEW", "Extend the current subscription"),
            ("TOPUP", "Reset monthly bandwidth usage"),
            ("BACKUP", "Export WireGuard config (.conf) backup"),
        ])
        if pending_store.get("renewal") or pending_store.get("reset"):
            choices.append(("RESUME", "Resume pending renewal or bandwidth reset"))
        if state.get("activation_pending"):
            choices.append(("ACTIVATE", "Finish activating claimed subscription"))
    if state.get("mode") == "adopted_legacy":
        choices.append(("UPGRADE", "Upgrade the adopted setup to managed mode"))
    choices.extend([("REPAIR", "Re-apply TunnelSats (also: update the pinned tool)"), remove])
    if active_ts and state.get("mode") != "adopted_legacy" and impl in UNITS:
        if unit_props(deps, UNITS[impl], "ActiveState")["ActiveState"] != "active":
            choices.append(("START", "Start Lightning"))
        else:
            record = read_guard_record(deps, BASES[impl])
            if record and record.get("reason") in RESTARTABLE:
                choices.append(("RESTART", "Restart Lightning to resume clearnet"))
    choices.append(("ABOUT", "How it works, privacy trade-offs & links"))
    return choices, notice


def pending_removal_text(deps, pending):
    """The notice after a REMOVE that did not finish: the live state of the unit it recorded (never the
    record alone, which is written before the stop), where the tunnel stands (in place when REMOVE
    stopped before the tool; removed, or partly removed, when REMOVE could not stop or disable the
    unit afterwards, with the command to run), and a fresh read-only audit of the unit's config."""
    unit = pending["unit"]
    props = unit_props(deps, unit, "ActiveState", "UnitFileState")
    running = props["ActiveState"] not in ("inactive", "failed")
    boot = props["UnitFileState"] not in BOOT_OFF
    stopped = "stopped and disabled" if not boot else "stopped"
    reason, tunnel = pending.get("reason"), pending.get("tunnel") or "in_place"
    what = "did not stop" if reason == "stop_failed" else "could not be disabled"
    command = None
    if reason in ("stop_failed", "disable_failed") and tunnel != "in_place":
        now = ("%s still runs (%s)" % (unit, props["ActiveState"] or "state unknown") if running
               else "%s is stopped but still enabled" % unit if boot else "%s is %s" % (unit, stopped))
        text = "REMOVE did not finish: the tunnel is %s, and %s %s; %s" % (
            "already removed" if tunnel == "removed" else "partly removed", unit, what, now)
        command = ("systemctl disable --now %s" if running and boot else "systemctl stop %s" if running
                   else "systemctl disable %s" if boot else None)
    elif reason in ("stop_failed", "disable_failed"):
        now = "%s still runs (%s)" % (unit, props["ActiveState"] or "state unknown") if running \
            else "%s is %s" % (unit, stopped)
        text = "REMOVE did not finish: %s %s, so the tunnel and its kill switch stay in place; %s" % (unit, what, now)
    elif running:
        text = "REMOVE did not finish: %s still runs (%s)" % (unit, props["ActiveState"] or "state unknown")
    else:
        text = "REMOVE left %s %s" % (unit, stopped)
    then = "it checks the config first" if running else "it checks the config, then starts %s" % unit
    rc, audit = its(deps, ["audit", IMPL_OF_UNIT[unit], "--json"], timeout=30)
    if audit and audit.get("status") == "clean":
        # Tor-only now: running or starting without the tunnel is fine, so no stop or disable command
        return text + ". Its config is Tor-only now: choose REMOVE again to finish; %s." % (
            "it enables and starts %s" % unit if not running else "it checks the config first")
    if command:
        text += ". Run now: sudo %s, so that it neither runs nor starts without the tunnel. Its" % (command % unit)
    else:
        text += ": its"
    text += " config is not Tor-only at rest"
    lines = [line for line in (audit or {}).get("lines") or [] if isinstance(line, str)][:8]
    if lines:
        text += ". Remove these lines:\n" + "\n".join("  %s" % line for line in lines)
    elif audit is None:
        text += " (the check did not answer)"
    else:
        text += " (%s)" % (audit.get("reason") or audit.get("status"))
    return text + "\nThen choose REMOVE again: %s." % then


def menu_server_choices(servers):
    """Builds (server_id, label) choices for the TUI BUY dialog from a servers list.
    Includes online and degraded servers; marks degraded servers in the label and excludes offline ones."""
    choices = []
    for s in servers or ():
        if not isinstance(s, dict):
            continue
        status = s.get("status")
        if status not in SELECTABLE_SERVER_STATUSES:
            continue
        sid = s.get("id")
        country = (s.get("country") or "").strip()
        city = (s.get("city") or "").strip()
        flag = (s.get("flag") or "").strip()
        if not sid or not country or not city:
            continue
        label = "%s %s - %s" % (flag, country, city) if flag else "%s - %s" % (country, city)
        if status not in ONLINE_SERVER_STATUSES:
            label += " [%s]" % status
        choices.append((sid, label))
    return choices


def menu_start(deps, restart=False):
    """START and RESTART of the menu, only while TunnelSats is on (see menu_choices). Returns the
    implementation it started, or None if TunnelSats is off."""
    conf = read_rb_conf(deps)
    if conf.get("tunnelsats") != "on":
        return None
    impl = (load_state(deps) or {}).get("impl") or conf.get("tunnelsatsImpl") or "lnd"
    if impl not in UNITS:
        return None
    systemctl(deps, "restart" if restart else "start", UNITS[impl])
    return impl


def cmd_menu(deps, args, result):  # pragma: no cover - interactive
    from dialog import Dialog  # imported only here
    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("TunnelSats VPN")
    found = None
    duration_choices = [("1", "1 month"), ("3", "3 months"), ("6", "6 months"), ("12", "12 months")]
    pay_choices = [
        ("QR", "Show QR code and BOLT11 invoice (external wallet)"),
        ("NODE", "Pay from this RaspiBlitz node (1% routing fee cap)"),
    ]

    def handle_invoice_payment(kind, title):
        inv_doc = menu_run(deps, ["invoice", "--kind", kind])
        if not inv_doc.get("invoice"):
            d.msgbox(result_text(inv_doc), title=title, width=78, height=20)
            return
        amt = int(inv_doc.get("amount_sats") or 0)
        fee_cap = max(int(math.ceil(amt * 0.01)), 10)
        code_p, pay_tag = d.menu(
            "Invoice amount: %d sats\nChoose how to pay:" % amt,
            choices=pay_choices, width=70, height=12, title=title,
        )
        if code_p != d.OK:
            return
        if pay_tag == "NODE":
            if d.yesno("Pay %d sats from this node (max routing fee %d sats)?" % (amt, fee_cap),
                       width=64, height=10, title=title) == d.OK:
                os.system("clear")
                print("# TunnelSats: paying %d sats via local node ..." % amt)
                pay_doc = menu_run(deps, ["pay-node", "--kind", kind, "--yes"])
                if pay_doc["ok"]:
                    d.msgbox(result_text(pay_doc), title=title, width=78, height=20)
                    return
                if d.yesno(result_text(pay_doc) + "\n\nShow QR code to pay with an external wallet instead?",
                           width=78, height=18, title=title) != d.OK:
                    return
        os.system("clear")
        show_qr(deps, inv_doc["invoice"])
        print("\nBOLT11: %s\n" % inv_doc["invoice"])
        print("# Waiting for payment (up to 5 minutes; background timer also settles automatically) ...")
        settle_doc = menu_run(deps, ["settle", "--wait", "300"])
        hide_qr(deps)
        d.msgbox(result_text(settle_doc), title=title, width=78, height=20)

    while True:
        state = load_state(deps)
        conf = read_rb_conf(deps)
        if state is None and found is None:
            os.system("clear")
            print("# TunnelSats: checking this node ...")
            found = detect(deps)
        choices, notice = menu_choices(deps, state, conf, found)
        text = "\nTunnelSats VPN for Lightning clearnet:"
        if notice:
            text = "\n%s\n%s" % (notice, text)
        code, tag = d.menu(text, choices=choices, width=78 if notice else 70, height=28 if notice else 18,
                           title="TunnelSats", cancel_label="Back")
        if code != d.OK:
            return
        if tag == "ABOUT":
            d.msgbox(ABOUT_TEXT, title="About TunnelSats", width=80, height=26)
        elif tag == "BUY":
            srv_doc = menu_run(deps, ["servers"])
            srv_list = srv_doc.get("servers") or []
            srv_choices = menu_server_choices(srv_list)
            if not srv_choices:
                d.msgbox("No active TunnelSats servers available right now.", title="BUY", width=60, height=8)
                continue
            code, server_id = d.menu("Choose a VPN server location:", choices=srv_choices,
                                     width=70, height=16, title="BUY")
            if code != d.OK:
                continue
            selected_srv = next((s for s in srv_list if isinstance(s, dict) and s.get("id") == server_id), None)
            if selected_srv and selected_srv.get("status") not in ONLINE_SERVER_STATUSES:
                if d.yesno("Server %s (%s - %s) currently has status '%s'.\n\nContinue anyway?"
                           % (server_id, selected_srv.get("country", ""), selected_srv.get("city", ""),
                              selected_srv.get("status", "unknown")),
                           width=64, height=10, title="BUY") != d.OK:
                    continue
            code, months = d.menu("Choose subscription duration:", choices=duration_choices,
                                  width=60, height=12, title="BUY")
            if code != d.OK:
                continue
            os.system("clear")
            print("# TunnelSats: creating subscription invoice ...")
            doc = menu_run(deps, ["buy", "--server", server_id, "--months", months, "--pay", "none"])
            if not doc["ok"]:
                d.msgbox(result_text(doc), title="BUY", width=78, height=20)
                continue
            handle_invoice_payment("order", "BUY")
        elif tag == "RENEW":
            code, months = d.menu("Choose renewal duration:", choices=duration_choices,
                                  width=60, height=12, title="RENEW")
            if code != d.OK:
                continue
            os.system("clear")
            print("# TunnelSats: creating renewal invoice ...")
            doc = menu_run(deps, ["renew", "--months", months, "--pay", "none"])
            if not doc["ok"]:
                d.msgbox(result_text(doc), title="RENEW", width=78, height=20)
                continue
            handle_invoice_payment("renewal", "RENEW")
        elif tag == "TOPUP":
            os.system("clear")
            print("# TunnelSats: creating bandwidth reset invoice ...")
            doc = menu_run(deps, ["topup", "--pay", "none"])
            if not doc["ok"]:
                d.msgbox(result_text(doc), title="TOPUP", width=78, height=20)
                continue
            handle_invoice_payment("reset", "TOPUP")
        elif tag == "BACKUP":
            code, out_path = d.inputbox("Path to write the WireGuard config backup (0600 admin):",
                                        init="/home/admin/tunnelsats-backup.conf",
                                        width=70, height=10, title="BACKUP")
            if code != d.OK or not out_path.strip():
                continue
            doc = menu_run(deps, ["export", "--out", out_path.strip()])
            d.msgbox(result_text(doc), title="BACKUP", width=78, height=20)
        elif tag == "RESUME":
            pending_store = load_pending(deps)
            if pending_store.get("order") or pending_store.get("retained_orders"):
                kind = "order"
            elif pending_store.get("renewal"):
                kind = "renewal"
            else:
                kind = "reset"
            handle_invoice_payment(kind, "RESUME")
        elif tag == "ACTIVATE":
            os.system("clear")
            print("# TunnelSats: activating claimed subscription ...")
            doc = menu_run(deps, ["repair", "--yes"])
            d.msgbox(result_text(doc), title="ACTIVATE", width=78, height=20)
        elif tag == "IMPORT":
            code, path = d.inputbox("Path of the WireGuard config file to import:", init="/home/admin/tunnelsats.conf",
                                    width=70, height=10, title="IMPORT")
            if code != d.OK or not path.strip():
                continue
            if d.yesno(ABOUT_TEXT + "\n\nImport and activate now?", width=80, height=28, title="IMPORT") != d.OK:
                continue
            os.system("clear")
            print("# TunnelSats: importing, this can take a few minutes ...")
            doc = menu_run(deps, ["import", "--file", path.strip()])
            if doc["errors"] and doc["errors"][0]["code"] == "E_API_UNAVAILABLE" and d.yesno(
                    "The TunnelSats API could not be reached to confirm the subscription.\n\n"
                    "Continue without the confirmation?", width=70, height=10) == d.OK:
                doc = menu_run(deps, ["import", "--file", path.strip(), "--yes"])
            d.msgbox(result_text(doc), title="IMPORT", width=78, height=20)
        elif tag == "ADOPT":
            if d.yesno("Take over the subscription of the existing TunnelSats setup?\n\nNothing on the system "
                       "changes; STATUS works afterwards.", width=70, height=10) != d.OK:
                continue
            doc = menu_run(deps, ["adopt"])
            d.msgbox(result_text(doc), title="ADOPT", width=78, height=20)
        elif tag == "UPGRADE":
            if d.yesno("UPGRADE converts the adopted setup to managed mode (start guard, kill switch, "
                       "restore after updates) and may restart Lightning. Continue?",
                       width=70, height=10, title="UPGRADE") != d.OK:
                continue
            os.system("clear")
            print("# TunnelSats: upgrading to managed mode, this can take a few minutes ...")
            doc = menu_run(deps, ["adopt", "--upgrade", "--yes"])
            d.msgbox(result_text(doc), title="UPGRADE", width=78, height=20)
        elif tag == "STATUS":
            doc = menu_run(deps, ["status", "--refresh"])
            d.msgbox(status_text(doc), title="STATUS", width=78, height=22)
        elif tag == "CHECK":
            os.system("clear")
            print("# TunnelSats: running the connection check ...")
            d.msgbox(check_text(run_check(deps)), title="CHECK", width=78, height=22)
        elif tag == "REPAIR":
            if d.yesno("REPAIR re-applies TunnelSats and may restart Lightning. Continue?", width=60, height=8) != d.OK:
                continue
            os.system("clear")
            doc = menu_run(deps, ["repair", "--yes"])
            d.msgbox(result_text(doc), title="REPAIR", width=78, height=20)
        elif tag == "REMOVE":
            code = d.yesno("Lightning restarts in Tor-only mode and the tunnel and kill switch are removed.\n"
                           "Your subscription keeps running at TunnelSats until it expires.\n\n"
                           "Keep the stored config to re-install later?", yes_label="Keep", no_label="Delete",
                           extra_button=True, extra_label="Cancel", width=76, height=12, title="REMOVE")
            if code == d.EXTRA or code == d.ESC:
                continue
            os.system("clear")
            print("# TunnelSats: removing (Lightning stops while the kill switch goes away) ...")
            doc = menu_run(deps, ["uninstall", "--yes"] + ([] if code == d.OK else ["--purge"]))
            d.msgbox(result_text(doc), title="REMOVE", width=78, height=20)
        elif tag in ("START", "RESTART"):
            os.system("clear")
            impl = menu_start(deps, restart=tag == "RESTART")
            if impl is None:
                d.msgbox("TunnelSats is off: this menu starts Lightning only while TunnelSats is on.",
                         title=tag, width=70, height=8)
            elif impl == "lnd" and conf.get("autoUnlock") != "on":
                deps.run([LND_UNLOCK, "chain-unlock", "mainnet"], timeout=600, interactive=True)
            elif impl == "cl" and conf.get("clEncryptedHSM") == "on" and conf.get("clAutoUnlock") != "on":
                deps.run([CL_HSMTOOL, "unlock", "mainnet"], timeout=600, interactive=True)


def result_text(doc):
    action = doc.get("action_required") or {}
    if doc["errors"]:
        lines = ["%s\n\n%s" % (doc["errors"][0]["code"], doc["errors"][0]["message"])]
        if action.get("lines"):
            lines += ["", "Lines to remove:"] + ["  %s" % line for line in action["lines"][:8]]
        if action.get("then"):
            lines += ["", "Then run: sudo %s" % action["then"]]
            if doc.get("command") == "uninstall":
                lines.append("Or choose REMOVE again: it checks the config first, then starts Lightning.")
        return "\n".join(lines)
    lines = ["Done."]
    if "verdict" in doc:
        lines.append("Connection check: %s" % VERDICT_TEXT.get(doc["verdict"], doc["verdict"]))
    if doc.get("warnings"):
        lines += ["", "Notes:"] + ["- %s" % w for w in doc["warnings"][:6]]
    if doc.get("custom_installs_lines"):
        lines += ["", "Lines in custom-installs.sh to review by hand:"]
        lines += ["  %d: %s" % (entry["line"], entry["text"]) for entry in doc["custom_installs_lines"][:8]]
    return "\n".join(lines)


def status_text(doc):
    if not doc.get("configured"):
        return "No TunnelSats subscription is set up on this node."
    tunnel = doc.get("tunnel") or {}
    lines = ["Server:      %s (VPN port %s)" % (doc.get("server_domain"), doc.get("vpn_port")),
             "Expires:     %s" % (doc.get("expiry") or "unknown"),
             "Bandwidth:   %s of %s GB, resets used %s of %s" % (
                 doc.get("bandwidth_used_gb"), doc.get("bandwidth_limit_gb"), doc.get("resets_this_month"),
                 doc.get("max_resets_per_month")),
             "Peer:        %s" % (doc.get("peer_status") or "unknown"),
             "API sync:    %s" % (doc.get("sync") or {}).get("outcome"),
             "Handshake:   %s" % ("%s s ago" % tunnel["handshake_age_s"] if tunnel.get("handshake_age_s") is not None
                                  else "none"),
             "Guard:       %s (%s)" % ((doc.get("guard") or {}).get("decision"), (doc.get("guard") or {}).get("reason")),
             "Public key:  %s" % doc.get("public_key")]
    if doc.get("action"):
        lines += ["", doc["action"]]
    return "\n".join(lines)


# ------------------------------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------------------------------

HANDLERS = {"menu": cmd_menu, "servers": cmd_servers, "buy": cmd_buy, "renew": cmd_renew,
            "topup": cmd_topup, "invoice": cmd_invoice, "pending": cmd_pending, "settle": cmd_settle,
            "pay-node": cmd_pay_node, "export": cmd_export, "import": cmd_import, "adopt": cmd_adopt,
            "status": cmd_status, "check": cmd_check, "detect": cmd_detect, "repair": cmd_repair,
            "uninstall": cmd_uninstall, "subscriptions-list": cmd_subscriptions_list, "tick": cmd_tick}


class _UsageError(Exception):
    pass


class _Parser(argparse.ArgumentParser):
    """Raises on a usage error instead of exiting, so every run prints one document."""

    def error(self, message):
        raise _UsageError(message)


def build_parser():
    parser = _Parser(prog="blitz.subscriptions.tunnelsats.py", description=__doc__.split("\n")[0])
    sub = parser.add_subparsers(dest="verb", required=True)

    def verb(name):
        p = sub.add_parser(name)
        p.add_argument("--json", action="store_true")
        return p

    verb("menu")
    verb("servers")
    p = verb("buy")
    p.add_argument("--server", required=True)
    p.add_argument("--months", type=int, choices=DURATIONS, required=True)
    p.add_argument("--pay", choices=PAY_MODES, default="none")
    p.add_argument("--impl", choices=IMPLS)
    p.add_argument("--yes", action="store_true")
    p = verb("renew")
    p.add_argument("--months", type=int, choices=DURATIONS, required=True)
    p.add_argument("--pay", choices=PAY_MODES, default="none")
    p.add_argument("--impl", choices=IMPLS)
    p.add_argument("--yes", action="store_true")
    p = verb("topup")
    p.add_argument("--pay", choices=PAY_MODES, default="none")
    p.add_argument("--impl", choices=IMPLS)
    p.add_argument("--yes", action="store_true")
    p = verb("invoice")
    p.add_argument("--kind", choices=("order", "renewal", "reset"), default="order")
    p.add_argument("--qr-png")
    verb("pending")
    p = verb("settle")
    p.add_argument("--wait", type=int, default=0)
    p = verb("pay-node")
    p.add_argument("--kind", choices=("order", "renewal", "reset"))
    p.add_argument("--impl", choices=IMPLS)
    p.add_argument("--yes", action="store_true")
    p = verb("export")
    p.add_argument("--out", required=True)
    p = verb("import")
    p.add_argument("--file", required=True)
    p.add_argument("--impl", choices=IMPLS)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--yes", action="store_true")
    p = verb("adopt")
    p.add_argument("--yes", action="store_true")
    p.add_argument("--upgrade", action="store_true")
    p = verb("status")
    group = p.add_mutually_exclusive_group()
    group.add_argument("--refresh", action="store_true")
    group.add_argument("--cached", action="store_true")
    p.add_argument("--raw-api", action="store_true")
    verb("check")
    verb("detect")
    p = verb("repair")
    p.add_argument("--impl", choices=IMPLS)
    p.add_argument("--yes", action="store_true")
    p = verb("uninstall")
    p.add_argument("--yes", action="store_true")
    p.add_argument("--purge", action="store_true")
    verb("subscriptions-list")
    p = verb("tick")
    p.add_argument("--now")
    p.add_argument("--status-file")
    p.add_argument("--no-persist", action="store_true")
    return parser


def main(argv=None, deps=None, out=None):
    argv = sys.argv[1:] if argv is None else argv
    deps = deps or Deps()
    as_json = "--json" in argv or "--raw-api" in argv
    verb = next((a for a in argv if not a.startswith("-")), "")
    result = Result(verb or "usage")
    if argv in (["-h"], ["--help"]):
        build_parser().print_help()
        return EXIT_OK
    try:
        args = build_parser().parse_args(argv)
        if not deps.is_root():
            raise ModuleError("E_NOT_ROOT", "usage", "run as root (sudo)", EXIT_USAGE)
        os.umask(0o077)
        HANDLERS[args.verb](deps, args, result)
    except _UsageError as exc:
        result.error("E_USAGE", "usage", str(exc), EXIT_USAGE)
    except ModuleError as exc:
        result.error(exc.code, exc.cls, exc.message, exc.exit_code)
    except Exception as exc:  # an unexpected failure still gives one document, without details
        deps.log("unexpected %s" % type(exc).__name__)
        result.error("E_INTERNAL", "operational", "unexpected %s" % type(exc).__name__, EXIT_OPERATIONAL)
    if verb == "menu" and not as_json:
        return EXIT_OK
    emit(result, as_json, out)
    return result.exit_code


if __name__ == "__main__":
    sys.exit(main())
