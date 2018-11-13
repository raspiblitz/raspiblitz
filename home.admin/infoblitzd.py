#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import base64
import json
import logging
import logging.config
import logging.config
import os
import re
import socket
import socketserver
import subprocess
import sys
import threading
import time
import urllib.parse
from datetime import timedelta
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler
from optparse import OptionParser

try:  # make sure that (unsupported) Python2 can fail gracefully
    import configparser
    from urllib.request import urlopen
    from urllib.error import HTTPError
except ImportError:
    pass


if sys.version_info < (3, 5, 0):
    print("Python2 not supported! Please run with Python3.5+")
    sys.exit(1)

CTYPE_HTML = "text/html"
CTYPE_JSON = "application/json"
BOARD_NAME = "RaspiBlitz"
BOARD_VERSION = "0.93"
NETWORK_FILE = "/home/admin/.network"
BITCOIN_HOME = "/home/bitcoin"
IF_NAME = "eth0"
TIMEOUT = 10

CRYPTO_CURRENCIES = {
    "bitcoin": {
        "title": "Bitcoin",
        "cli": "bitcoin-cli",
        "daemon": "bitcoind",
        "testnet_dir": "testnet3",
        "mainnet_port": 8333,
        "testnet_port": 18333
    },
    "litecoin": {
        "title": "Litecoin",
        "cli": "litecoin-cli",
        "daemon": "litecoind",
        "testnet_dir": "testnet3",  # ?!
        "mainnet_port": 9333,
        "testnet_port": 19333
    }
}

logger = logging.getLogger()


def setup_logging(default_path='infoblitz_logging.json'):
    """Setup logging configuration"""
    path = default_path
    if os.path.exists(path):
        with open(path, 'rt') as f:
            config = json.load(f)
        logging.config.dictConfig(config)
    else:  # is infoblitz_logging.json does not exist use the following default log setup
        default_config_as_json = """
{
    "version": 1,
    "disable_existing_loggers": false,
    "formatters": {
        "simple": {
            "format": "%(asctime)s (%(threadName)-10s) %(name)s - %(levelname)s - %(message)s"
        },
        "extended": {
            "format": "%(asctime)s (%(threadName)-10s) %(name)s - %(levelname)s - %(module)s:%(lineno)d - %(message)s"
        }

    },

    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "level": "ERROR",
            "formatter": "simple",
            "stream": "ext://sys.stdout"
        },

        "file_handler": {
            "class": "logging.handlers.RotatingFileHandler",
            "level": "DEBUG",
            "formatter": "extended",
            "filename": "infoblitz.log",
            "maxBytes": 10485760,
            "backupCount": 2,
            "encoding": "utf8"
        }
    },

    "loggers": {
        "infoblitz": {
            "level": "INFO",
            "handlers": ["console", "file_handler"],
            "propagate": "no"
        }
    },

    "root": {
        "level": "DEBUG",
        "handlers": ["console", "file_handler"]
    }
}
"""
        config = json.loads(default_config_as_json)
        logging.config.dictConfig(config)


def sigint_handler(signum, frame):
    print('CTRL+C pressed - exiting!')
    sys.exit(0)


def _red(string):
    return "\033[91m{}\033[00m".format(string)


def _green(string):
    return "\033[92m{}\033[00m".format(string)


def _yellow(string):
    return "\033[93m{}\033[00m".format(string)


def _gray(string):
    return "\033[97m{}\033[00m".format(string)


def _cyan(string):
    return "\033[96m{}\033[00m".format(string)


def _purple(string):
    return "\033[95m{}\033[00m".format(string)


def clear():
    # check and make call for specific operating system
    if os.name == 'posix':
        _ = os.system('clear')  # Linux and Mac OS


def get_ipv4_addresses(ifname):
    """get_ipv4_addresses("eth0")"""
    ip_addresses = []
    _res = subprocess.check_output(["ip", "-4", "addr", "show", "dev", "{}".format(ifname), "scope", "global", "up"])
    for line in _res.split(b"\n"):
        match = re.match(b".+inet (.+)/.+", line)
        if match:
            ip_addresses.append(match.groups()[0].decode('utf-8'))
    return ip_addresses


def get_ipv6_addresses(ifname):
    """get_ipv6_addresses("eth0")"""
    ip_addresses = []
    _res = subprocess.check_output(["ip", "-6", "addr", "show", "dev", "{}".format(ifname), "scope", "global", "up"])
    for line in _res.split(b"\n"):
        match = re.match(b".+inet6 (.+)/.+", line)
        if match and b"mngtmpaddr" not in line:
            ip_addresses.append(match.groups()[0].decode('utf-8'))
    return ip_addresses


def port_check(address="127.0.0.1", port=8080, timeout=1.0):
    if not isinstance(port, int):
        return False

    if not 0 < port < 65535:
        return False

    s = socket.socket()
    s.settimeout(timeout)
    is_open = False
    try:
        s.connect((address, port))
        is_open = True
    except Exception as err:
        logger.warning("Something's wrong with {}:{}. Exception is {}".format(address, port, err))
    finally:
        s.close()
    return is_open


def run_user(cmd, shell=True, timeout=None):
    if shell:  # shell is potentially considered a security risk (command injection when taking user input)
        if not isinstance(cmd, str):
            raise ValueError("cmd to execute must be passed in a single string when shell is True")

        if cmd.split(" ")[0] == "sudo":
            timeout = None
    else:
        if not isinstance(cmd, list):
            raise ValueError("cmd to execute must be passed in as list of strings when shell is False")

        if cmd[0] == "sudo":
            timeout = None

    try:
        # subprocess.run requires Python3.5+
        p = subprocess.run(cmd,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                           universal_newlines=True, shell=shell, timeout=timeout)

        if p.returncode:  # non-zero
            result = p.stderr
            success = False
            timed_out = False
        else:
            result = p.stdout
            success = True
            timed_out = False

    except subprocess.TimeoutExpired:
        result = None
        success = False
        timed_out = True

    return result, success, timed_out


class QuietBaseHTTPRequestHandler(BaseHTTPRequestHandler):
    """Quiet http request handler
    Subclasses SimpleHTTPRequestHandler in order to overwrite the log_message
    method, letting us reduce output generated by the handler. Only standard
    messages are overwritten, so errors will still be displayed.
    """

    def __init__(self, request, client_address, server, board=None, board_lock=None):
        super().__init__(request, client_address, server)
        self.board = board
        self.board_lock = board_lock

    def do_GET(self):
        parts = urllib.parse.urlsplit(self.path)

        if parts.path.endswith('/favicon.ico'):
            ctype = 'image/x-icon'
            content = bytes(base64.b64decode(
                "AAABAAEAEBAAAAEAIABoBAAAFgAAACgAAAAQAAAAIAAAAAEAIAAAAAAA"
                "AAQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoJiIKKCYiWgAAAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                "AAAoJiIgKCYiuygmIhgAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAoJiJDKCYi7SgmIlIAAAAAAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoJiJz"
                "KCYi/SgmIqAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                "AAAAAAAAAAAAACgmIgooJiKmKCYi/ygmIuAoJiIOAAAAAAAAAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACgmIh8oJiLPKCYi/ygm"
                "Iv4oJiI/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                "AAAAACgmIkEoJiLrKCYi/ygmIv8oJiKMAAAAAAAAAAAAAAAAAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAACgmInAoJiL8KCYi/ygmIv8oJiL/"
                "KCYiySgmIpwoJiJzKCYiKQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAACgm"
                "IhYoJiJyKCYinCgmIsIoJiL8KCYi/ygmIv8oJiL/KCYinygmIgkAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoJiJTKCYi/ygm"
                "Iv8oJiL5KCYiaAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                "AAAAAAAAAAAoJiIeKCYi7ygmIv8oJiLjKCYiNwAAAAAAAAAAAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAoJiIDKCYixCgmIv8oJiK+"
                "KCYiFQAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                "AAAAAAAAKCYigigmIv8oJiKJKCYiAwAAAAAAAAAAAAAAAAAAAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAKCYiPigmIvAoJiJSAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                "KCYiEigmIrooJiInAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAACgmIlooJiIMAAAAAAAAAAAAAAAA"
                "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA//8AAP/3"
                "AAD/7wAA/88AAP8fAAD+PwAA/D8AAPgfAAD4DwAA/j8AAPx/AAD4/wAA"
                "8f8AAPf/AADv/wAA//8AAA=="
            ))

        elif not parts.path.endswith('/'):
            # redirect browser - doing basically what apache does
            self.send_response(HTTPStatus.MOVED_PERMANENTLY)
            new_parts = (parts[0], parts[1], parts[2] + '/',
                         parts[3], parts[4])
            new_url = urllib.parse.urlunsplit(new_parts)
            self.send_header("Location", new_url)
            self.end_headers()
            return None

        elif parts.path.endswith('/json/'):
            ctype = CTYPE_JSON

            with self.board_lock:
                # dict_content = {"hello": "world",
                #                 "version": self.board.version.val,
                #                 "lnd_external": self.board.lnd_external.val}

                json_content = json.loads(json.dumps(self.board.all_metrics()))
                content = bytes(json.dumps(json_content), "UTF-8")

        else:
            ctype = CTYPE_HTML
            content = bytes("<html><head><title>RaspiBlitz Info Dashboard</title></head>", "UTF-8")
            content += bytes("<body><h1>RaspiBlitz Info Dashboard</h1>", "UTF-8")
            content += bytes("<p>The Dashboard Version is: v{}</p>".format(self.board.version.val), "UTF-8")
            content += bytes("<p>The API Endpoint (JSON) is located here: <a href=\"/json/\">/json/</a></p>", "UTF-8")
            content += bytes("</body></html>", "UTF-8")

        self.send_response(200)
        self.send_header("Content-type", ctype)
        self.send_header("Content-Length", len(content))
        self.end_headers()

        self.wfile.write(content)

    def log_message(self, *args):
        """Overwrite so messages are not logged to STDOUT"""
        pass

    def log_request(self, code='-', size='-'):
        """Log an accepted request.

        This is called by send_response().

        """
        if isinstance(code, HTTPStatus):
            code = code.value
        logger.debug("{} - - [{}] \"{}\" {} {}".format(self.address_string(), self.log_date_time_string(),
                                                       self.requestline, str(code), str(size)))


class ThreadedHTTPServer(object):
    """Runs BaseHTTPServer in a thread
    Lets you start and stop an instance of SimpleHTTPServer.
    """
    def __init__(self, host, port, board=None, board_lock=None, name=None):
        """Prepare thread and socket server
        Creates the socket server that will use the HTTP request handler. Also
        prepares the thread to run the serve_forever method of the socket
        server as a daemon once it is started
        """
        request_handler = QuietBaseHTTPRequestHandler
        request_handler.board = board
        request_handler.board_lock = board_lock

        socketserver.TCPServer.allow_reuse_address = True
        self.server = socketserver.TCPServer((host, port), request_handler)
        self.server_thread = threading.Thread(name=name, target=self.server.serve_forever)
        self.server_thread.daemon = True

    def __enter__(self):
        self.start()
        return self

    def __exit__(self, type, value, traceback):
        self.stop()

    def start(self):
        """Start the HTTP server
        Starts the serve_forever method of Socket running the request handler
        as a daemon thread
        """
        self.server_thread.start()

    def stop(self):
        """Stop the HTTP server
        Stops the server and cleans up the port assigned to the socket
        """
        self.server.shutdown()
        self.server.server_close()


# Benefit of using class instead of function: Can use clean signature instead of kwargs..!
class DashboardPrinter(threading.Thread):
    def __init__(self, group=None, target=None, name="DB_Printer",
                 board=None, board_lock=None, interval=None,
                 daemon=True, args=(), kwargs=None, ):
        super().__init__(group, target, name, daemon=daemon, args=args, kwargs=kwargs)
        self.board = board
        self.board_lock = board_lock
        self.interval = interval

    def run(self):
        while True:

            start = time.time()
            with self.board_lock:
                end = time.time()
                logger.info("Getting print lock took: {:.3f} seconds".format(end - start))

                clear()
                self.board.display()

            time.sleep(self.interval)


class DashboardUpdater(threading.Thread):
    def __init__(self, group=None, target=None, name="DB_Updater",
                 board=None, board_lock=None, interval=None,
                 daemon=True, args=(), kwargs=None, ):
        super().__init__(group, target, name, daemon=daemon, args=args, kwargs=kwargs)
        self.board = board
        self.board_lock = board_lock
        self.interval = interval

    def run(self):
        while True:
            logger.debug("Updating Dashboard")
            total_start = time.time()

            start = time.time()
            with self.board_lock:
                end = time.time()
                logger.debug("Getting update1 lock took: {:.3f} seconds".format(end - start))

                self.board.update_load()
                self.board.update_uptime()
                self.board.update_cpu_temp()
                self.board.update_memory()
                self.board.update_storage()
                self.board.update_ip_network_data()
            time.sleep(0.05)

            start = time.time()
            with self.board_lock:
                end = time.time()
                logger.debug("Getting update2 lock took: {:.3f} seconds".format(end - start))

                self.board.update_network()

                self.board.update_bitcoin_dir()
                self.board.read_bitcoin_config()

                self.board.update_chain()
            time.sleep(0.05)

            start = time.time()
            with self.board_lock:
                end = time.time()
                logger.debug("Getting update3 lock took: {:.3f} seconds".format(end - start))

                self.board.update_bitcoin_binaries()
                self.board.check_bitcoind_is_running()
                self.board.update_bitcoin_daemon_version()
                self.board.update_bitcoin_data()
            time.sleep(0.05)

            start = time.time()
            with self.board_lock:
                end = time.time()
                logger.debug("Getting update4 lock took: {:.3f} seconds".format(end - start))

                self.board.update_lnd_dirs()
                self.board.read_lnd_config()
                self.board.check_lnd_is_running()
                self.board.update_lnd_wallet_is_locked()
                self.board.update_lnd_alias()
                self.board.update_lnd_data()
            time.sleep(0.05)

            start = time.time()
            with self.board_lock:
                end = time.time()
                logger.debug("Getting update5 lock took: {:.3f} seconds".format(end - start))

                self.board.update_public_ip()
                self.board.update_bitcoin_public_port()
                self.board.check_public_ip_lnd_port()
                self.board.check_public_ip_bitcoin_port()
            time.sleep(0.05)

            total_end = time.time()
            logger.info("Dashboard Value Update took: {:.3f} seconds".format(total_end - total_start))

            time.sleep(self.interval)


class Metric(object):
    STYLES = ["default", "red", "green", "yellow", "gray", "cyan"]

    def __init__(self, val=None, txt=None, prefix=None, suffix=None, style="default", allow_empty=False):
        self.val = val  # "raw" value of Metric
        self._txt = txt  # text of "raw" value intended for printing to console (e.g. Memory in MiB instead of Bytes)
        self.prefix = prefix
        self.suffix = suffix

        if style not in self.STYLES:
            raise ValueError("unknown style!")
        self.style = style

        self.allow_empty = allow_empty  # when this is False (default) "prefix + n/a + suffix" will be printed

    @property
    def txt(self):
        if self._txt:
            return self._txt
        elif self._txt == "":
            return ""
        else:
            if self.val:
                return "{}".format(self.val)
            else:
                return None

    @txt.setter
    def txt(self, value):
        self._txt = value

    def __repr__(self):
        if self.val:
            return "<{0}: {1}>".format(self.__class__.__name__, self.val)
        return "<{0}: n/a>".format(self.__class__.__name__)

    def __str__(self):
        return self.apply_style(string=self.to_txt(), style=self.style)

    def apply_style(self, string, style=None):
        if not style:
            style = "default"
        if "n/a" in string:
            return _purple(string)
        elif string:
            if style == "red":
                return _red(string)
            elif style == "green":
                return _green(string)
            elif style == "yellow":
                return _yellow(string)
            elif style == "gray":
                return _gray(string)
            elif style == "cyan":
                return _cyan(string)
            else:
                return string
        else:
            if self.allow_empty:
                return ""
            else:
                return _purple(string)

    def to_dct(self):
        dct = dict()
        # copy dict except for _txt and allow_empty
        for k, v in self.__dict__.items():
            if k in ["_txt", "allow_empty"]:
                continue
            dct.update({k: v})
        # add txt representation
        dct.update({"txt": self.to_txt()})
        return dct

    def to_txt(self):
        if self.prefix is None:
            prefix = ""
        else:
            prefix = self.prefix

        if self.suffix is None:
            suffix = ""
        else:
            suffix = self.suffix

        if self.txt:
            return "{0}{1}{2}".format(prefix, self.txt, suffix)
        else:
            if self.allow_empty:
                return ""
            else:
                return "{0}n/a{1}".format(prefix, suffix)


class Dashboard(object):
    def __init__(self, currency, interface=IF_NAME, timeout=TIMEOUT):
        self.currency = CRYPTO_CURRENCIES[currency]

        # Attributes that are used internally but not displayed directly
        #
        self.interface = interface
        self.timeout = timeout

        self.ipv4_addresses = list()
        self.lpv6_addresses = list()

        self.bitcoin_dir = None
        self.lnd_dir = None
        self.lnd_macaroon_dir = None

        self.bitcoin_config = None
        self.lnd_config = None

        self.bitcoin_daemon = None
        self.bitcoin_cli = None

        self.bitcoin_local_adresses = list()

        self.lnd_is_running = False
        self.lnd_is_syned = False
        self.lnd_wallet_is_locked = True

        # Dashboard Metrics (all values that are displayed somewhere) - in use
        #
        self.name = Metric()
        self.version = Metric()

        # System data
        self.load_one = Metric()
        self.load_five = Metric()
        self.load_fifteen = Metric()
        self.cpu_temp = Metric(suffix="°C")
        self.memory_total = Metric(suffix="M", style="green")
        self.memory_avail = Metric(suffix="M", style="green")

        # Storage
        self.sd_total_abs = Metric(suffix="G", style="green")
        self.sd_free_abs = Metric(suffix="G", style="green")
        self.sd_free = Metric(suffix="%", style="green")
        self.hdd_total_abs = Metric(suffix="G", style="green")
        self.hdd_free_abs = Metric(suffix="G", style="green")
        self.hdd_free = Metric(suffix="%", style="green")

        # IP Network/Traffic Info
        self.local_ip = Metric(style="green")
        self.network_tx = Metric()
        self.network_rx = Metric()

        self.public_ip = Metric(style="green")
        self.public_bitcoin_port = Metric(style="green")
        self.public_bitcoin_port_status = Metric(allow_empty=True)

        # Bitcoin / Chain Info
        self.network = Metric(style="default")
        self.chain = Metric("main", suffix="net", style="green")

        self.bitcoin_cli_version = Metric(style="green")
        self.bitcoin_version = Metric(style="green")
        self.bitcoin_is_running = False
        self.bitcoin_log_msgs = None

        self.sync_behind = Metric()
        self.sync_percentage = Metric(suffix="%", style="green")
        self.sync_status = Metric()

        # self.last_block = Metric()
        self.block_height = Metric()
        self.btc_line2 = Metric()
        self.mempool = Metric()

        # Tor (The Onion Router)
        self.tor_active = Metric(allow_empty=True)
        self.onion_addr = Metric()

        self.lnd_alias = Metric(style="green")
        self.lnd_version = Metric(style="green")
        self.lnd_lncli_version = Metric(style="green")
        self.lnd_base_msg = Metric(allow_empty=True)
        self.lnd_channel_msg = Metric(allow_empty=True)
        self.lnd_channel_balance = Metric()
        self.lnd_channels_online = Metric()
        self.lnd_channels_total = Metric()
        self.lnd_external = Metric(style="yellow")
        self.public_ip_lnd_port_status = Metric(allow_empty=True)

        self.lnd_wallet_balance = Metric()
        self.lnd_wallet_lock_status = Metric()

        # Dashboard Metrics (all values that are displayed somewhere) - currently not in use
        #
        self.uptime = Metric()

        self.bitcoin_ipv4_reachable = Metric()
        self.bitcoin_ipv4_limited = Metric()
        self.bitcoin_ipv6_reachable = Metric()
        self.bitcoin_ipv6_limited = Metric()
        self.bitcoin_onion_reachable = Metric()
        self.bitcoin_onion_limited = Metric()

    def __repr__(self):
        return "<{0}: Version: {1}>".format(self.__class__.__name__, self.version)

    def all_metrics(self):
        """Introspection: return list of all attributes that are Metric instances"""
        return [{m: getattr(self, m).to_dct()} for m in [a for a in dir(self)] if isinstance(getattr(self, m), Metric)]

    def update_load(self):
        one, five, fifteen = os.getloadavg()

        _cpu_count = os.cpu_count()
        self.load_one.val = one
        self.load_one.txt = "{:.2f}".format(self.load_one.val)
        self.load_five.val = five
        self.load_five.txt = "{:.2f}".format(self.load_five.val)
        self.load_fifteen.val = fifteen
        self.load_fifteen.txt = "{:.2f}".format(self.load_fifteen.val)

        if float(self.load_one.val) < _cpu_count * 0.5:
            self.load_one.style = "green"
        elif float(self.load_one.val) < _cpu_count:
            self.load_one.style = "yellow"
        else:
            self.load_one.style = "red"

        if float(self.load_five.val) < _cpu_count * 0.5:
            self.load_five.style = "green"
        elif float(self.load_five.val) < _cpu_count:
            self.load_five.style = "yellow"
        else:
            self.load_five.style = "red"

        if float(self.load_fifteen.val) < _cpu_count * 0.5:
            self.load_fifteen.style = "green"
        elif float(self.load_fifteen.val) < _cpu_count:
            self.load_fifteen.style = "yellow"
        else:
            self.load_fifteen.style = "red"

    def update_uptime(self):
        if not os.path.exists("/proc/uptime"):
            return

        with open("/proc/uptime", "r") as f:
            _uptime_seconds = float(f.readline().split()[0])

        self.uptime.val = int(timedelta(seconds=_uptime_seconds).total_seconds())
        self.uptime.txt = "{}".format(self.uptime.val)

    def update_cpu_temp(self):
        if not os.path.exists("/sys/class/thermal/thermal_zone0/temp"):
            return

        with open("/sys/class/thermal/thermal_zone0/temp", "r") as f:
            content = int(f.readline().split("\n")[0])
        self.cpu_temp.val = content / 1000.0
        self.cpu_temp.txt = "{:.0f}".format(self.cpu_temp.val)

        if self.cpu_temp.val > 80.0:
            self.cpu_temp.style = "red"

    def update_memory(self):
        if not os.path.exists("/proc/meminfo"):
            return

        with open("/proc/meminfo", "r") as f:
            content = f.readlines()
        _meminfo = dict((i.split()[0].rstrip(':'), int(i.split()[1])) for i in content)

        self.memory_total.val = _meminfo['MemTotal']  # e.g. 949440
        self.memory_total.txt = "{:.0f}".format(self.memory_total.val / 1024)

        self.memory_avail.val = _meminfo['MemAvailable']  # e.g. 457424
        self.memory_avail.txt = "{:.0f}".format(self.memory_avail.val / 1024)

        if self.memory_avail.val < 100000:
            self.memory_total.style = "yellow"
            self.memory_avail.style = "yellow"

    def update_storage(self):
        """use statvfs interface to get free/used disk space

        statvfs.f_frsize * statvfs.f_blocks  # Size of filesystem in bytes
        statvfs.f_frsize * statvfs.f_bfree   # Actual number of free bytes
        statvfs.f_frsize * statvfs.f_bavail  # Number of free bytes that ordinary users are allowed to use
        """
        if not os.path.exists("/"):
            return

        statvfs_sd = os.statvfs('/')
        _sd_total_abs = statvfs_sd.f_frsize * statvfs_sd.f_blocks
        _sd_free_abs = statvfs_sd.f_frsize * statvfs_sd.f_bavail
        _sd_free = _sd_free_abs / _sd_total_abs * 100

        if not os.path.exists("/mnt/hdd"):
            return

        statvfs_hdd = os.statvfs("/mnt/hdd")
        _hdd_total_abs = statvfs_hdd.f_frsize * statvfs_hdd.f_blocks
        # _hdd_free_abs = statvfs_hdd.f_frsize * statvfs_hdd.f_bfree
        _hdd_free_abs = statvfs_hdd.f_frsize * statvfs_hdd.f_bavail
        _hdd_free = _hdd_free_abs / _hdd_total_abs * 100

        self.sd_total_abs.val = _sd_total_abs / 1024.0 / 1024.0 / 1024.0
        self.sd_total_abs.txt = "{:.0f}".format(self.sd_total_abs.val)

        self.sd_free_abs.val = _sd_free_abs / 1024.0 / 1024.0 / 1024.0
        self.sd_free_abs.txt = "{:.0f}".format(self.sd_free_abs.val)

        self.sd_free.val = _sd_free
        self.sd_free.txt = "{:.0f}".format(self.sd_free.val)

        self.hdd_total_abs.val = _hdd_total_abs / 1024.0 / 1024.0 / 1024.0
        self.hdd_total_abs.txt = "{:.0f}".format(self.hdd_total_abs.val)

        self.hdd_free_abs.val = _hdd_free_abs / 1024.0 / 1024.0 / 1024.0
        self.hdd_free_abs.txt = "{:.0f}".format(self.hdd_free_abs.val)

        self.hdd_free.val = _hdd_free
        self.hdd_free.txt = "{:.0f}".format(self.hdd_free.val)

        if self.hdd_free.val < 20:
            self.hdd_free.style = "yellow"
        elif self.hdd_free.val < 10:
            self.hdd_free.style = "red"

    def update_ip_network_data(self):
        self.ipv4_addresses = get_ipv4_addresses(self.interface)
        self.ipv6_addresses = get_ipv6_addresses(self.interface)
        self.local_ip.val = self.ipv4_addresses[0]

        if not os.path.exists("/sys/class/net/{0}/statistics/rx_bytes".format(self.interface)):
            return

        with open("/sys/class/net/{0}/statistics/rx_bytes".format(self.interface), 'r') as f:
            _rx_bytes = float(f.readline().split()[0])

        if not os.path.exists("/sys/class/net/{0}/statistics/tx_bytes".format(self.interface)):
            return

        with open("/sys/class/net/{0}/statistics/tx_bytes".format(self.interface), 'r') as f:
            _tx_bytes = float(f.readline().split()[0])

        if _tx_bytes / 1024.0 / 1024.0 / 1024.0 / 1024.0 > 1:
            _tx_suffix = "TiB"
            _tx_bytes_val = _tx_bytes / 1024.0 / 1024.0 / 1024.0 / 1024.0
        elif _tx_bytes / 1024.0 / 1024.0 / 1024.0 > 1:
            _tx_suffix = "GiB"
            _tx_bytes_val = _tx_bytes / 1024.0 / 1024.0 / 1024.0
        elif _tx_bytes / 1024.0 / 1024.0 > 1:
            _tx_suffix = "MiB"
            _tx_bytes_val = _tx_bytes / 1024.0 / 1024.0
        elif _tx_bytes / 1024.0 > 1:
            _tx_suffix = "KiB"
            _tx_bytes_val = _tx_bytes / 1024.0
        else:
            _tx_suffix = "Byte"
            _tx_bytes_val = _tx_bytes

        if _rx_bytes / 1024.0 / 1024.0 / 1024.0 / 1024.0 > 1:
            _rx_suffix = "TiB"
            _rx_bytes_val = _rx_bytes / 1024.0 / 1024.0 / 1024.0 / 1024.0
        elif _rx_bytes / 1024.0 / 1024.0 / 1024.0 > 1:
            _rx_suffix = "GiB"
            _rx_bytes_val = _rx_bytes / 1024.0 / 1024.0 / 1024.0
        elif _rx_bytes / 1024.0 / 1024.0 > 1:
            _rx_suffix = "MiB"
            _rx_bytes_val = _rx_bytes / 1024.0 / 1024.0
        elif _rx_bytes / 1024.0 > 1:
            _rx_suffix = "KiB"
            _rx_bytes_val = _rx_bytes / 1024.0
        else:
            _rx_suffix = "Byte"
            _rx_bytes_val = _rx_bytes

        self.network_rx = Metric(_rx_bytes_val, txt="{:.1f}".format(_rx_bytes_val), suffix=_rx_suffix)
        self.network_tx = Metric(_tx_bytes_val, txt="{:.1f}".format(_tx_bytes_val), suffix=_tx_suffix)

    def update_network(self):
        # load network (bitcoin, litecoin, ..?!)
        with open(NETWORK_FILE) as f:
            content = f.readline().split("\n")[0]
        if content not in list(CRYPTO_CURRENCIES.keys()):
            raise ValueError("unexpected value in {}: {}".format(NETWORK_FILE, content))
        self.network.val = content

        if not self.network.val == self.currency["title"].lower():
            raise ValueError("Crypto Currency in {} does not match selection!".format(NETWORK_FILE))

    def update_bitcoin_dir(self):
        self.bitcoin_dir = "{0}/.{1}".format(BITCOIN_HOME, self.network.val)

    def read_bitcoin_config(self):
        _bitcoin_conf = "{0}/{1}.conf".format(self.bitcoin_dir, self.network.val)
        if not os.path.exists(_bitcoin_conf):
            logger.warning("{} config not found: {}".format(self.currency["title"], _bitcoin_conf))
            return

        # need to do a little "hack" here as ConfigParser expects sections which bitcoin.conf does not have
        with open(_bitcoin_conf, 'r') as f:
            _config_string = '[DEFAULT]\n' + f.read()

        config = configparser.ConfigParser(strict=False)
        config.read_string(_config_string)
        self.bitcoin_config = config  # access with self.bitcoin_config["DEFAULT"]...

    def update_chain(self):
        # get chain (mainnet or testnet)
        try:
            if self.bitcoin_config["DEFAULT"]["testnet"] == "1":
                self.chain.val = "test"
        except KeyError:
            pass  # this is expected - if testnet is not present then mainnet is active
        except TypeError as err:  # catch if None, expected index/key not present
            logger.warning("Error: {}".format(err))

    def update_bitcoin_binaries(self):
        cmds = "which {}d".format(self.network.val)
        _bitcoind, success, timed_out = run_user(cmds, timeout=self.timeout)
        if success:
            try:
                self.bitcoin_daemon = _bitcoind.split("\n")[0]
            except IndexError as err:
                logger.warning("Error: {}".format(err))
        else:
            raise Exception("could not find network chain daemin tool: {}d".format(self.network.val))

        cmds = "which {}-cli".format(self.network.val)
        _bitcoin_cli, success, timed_out = run_user(cmds, timeout=self.timeout)
        if success:
            try:
                self.bitcoin_cli = _bitcoin_cli.split("\n")[0]
            except IndexError as err:
                logger.warning("Error: {}".format(err))
        else:
            raise Exception("could not find network chain cli tool: {}-cli".format(self.network.val))

    def check_bitcoind_is_running(self):
        # check if bitcoind is running
        cmds = "ps aux | grep -e \"{}.*-daemon\" | grep -v grep | wc -l".format(self.currency['daemon'])
        _bitcoind_running, success, timed_out = run_user(cmds, timeout=self.timeout)
        if success:
            try:
                if _bitcoind_running.split("\n")[0] == "0":
                    self.bitcoin_is_running = False
                    logger.warning("{} is not running".format(self.currency['daemon']))
                    return True
                else:
                    self.bitcoin_is_running = True
                    return True
            except IndexError as err:
                logger.warning("Error: {}".format(err))

        return False

    def update_bitcoind_log(self):
        # check bitcoind log
        if self.chain.val == "test":
            cmds = "sudo -u bitcoin tail -n 20 {}/{}/debug.log".format(self.bitcoin_dir, self.currency["testnet_dir"])
        else:
            cmds = "sudo -u bitcoin tail -n 20 {}/debug.log".format(self.bitcoin_dir)
        _bitcoind_log, success, timed_out = run_user(cmds, timeout=self.timeout)
        if success:
            try:
                self.bitcoin_log_msgs = [_bitcoind_log.split("\n")[-3], _bitcoind_log.split("\n")[-2]]
            except IndexError as err:
                logger.warning("Error: {}".format(err))

    def update_bitcoin_daemon_version(self):
        # get bitcoin version from daemon (bitcoind -version)
        cmds = "{} -datadir={} -version".format(self.bitcoin_cli, self.bitcoin_dir)
        _version_info, success, timed_out = run_user(cmds, timeout=self.timeout)
        if success:
            self.bitcoin_version.val = re.match("^.* v(.*$)", _version_info).groups()[0]
            self.bitcoin_version.prefix = "v"

    def update_bitcoin_data(self):
        self.sync_status.val = None
        self.sync_status.txt = None
        self.sync_status.style = "default"
        self.sync_percentage.val = None
        self.sync_percentage.txt = None
        self.sync_percentage.style = "green"

        # block count/height
        cmds = "{} -datadir={} getblockcount".format(self.bitcoin_cli, self.bitcoin_dir)
        _block_count, success, timed_out = run_user(cmds, timeout=self.timeout)
        if success:
            # reset self.bitcoin_log_msgs - which might have been set by update_bitcoind_log()
            self.bitcoin_log_msgs = None
            try:
                self.block_height.val = int(_block_count.split("\n")[0])
                self.block_height.txt = "{}".format(self.block_height.val)
            except IndexError as err:
                logger.warning("Error: {}".format(err))

        else:  # unable to run getblockcount.. maybe bitcoind is processing a long running job (e.g. txindex) TODO
            # try:
            #     last_line = _block_count.split("\n")[-2]
            # except AttributeError:
            #     pass

            self.update_bitcoind_log()

        # get blockchain (sync) status/percentage
        cmds = "{} -datadir={} getblockchaininfo".format(self.bitcoin_cli, self.bitcoin_dir)
        _chain_info, success, timed_out = run_user(cmds, timeout=self.timeout)
        if success:
            try:
                _block_verified = json.loads(_chain_info)["blocks"]
                _block_diff = int(self.block_height.val) - int(_block_verified)

                _progress = json.loads(_chain_info)["verificationprogress"]

                self.sync_percentage.val = _progress
                self.sync_percentage.txt = "{:.2f}".format(self.sync_percentage.val * 100)
                if _block_diff == 0:  # fully synced
                    self.sync_status.val = _block_diff
                    self.sync_status.txt = "OK"
                    self.sync_status.style = "green"
                    self.sync_behind = " "
                elif _block_diff == 1:  # fully synced
                    self.sync_status.val = _block_diff
                    self.sync_status.txt = "OK"
                    self.sync_status.style = "green"
                    self.sync_behind = "-1 block"
                elif _block_diff <= 10:
                    self.sync_status.val = _block_diff
                    self.sync_status.txt = "catchup"
                    self.sync_status.style = "red"
                    self.sync_percentage.style = "red"
                    self.sync_behind = "-{} blocks".format(_block_diff)
                else:
                    self.sync_status.val = _block_diff
                    self.sync_status.txt = "progress"
                    self.sync_status.style = "red"
                    self.sync_percentage.style = "red"
                    self.sync_behind = "-{} blocks".format(_block_diff)

            except (KeyError, TypeError) as err:  # catch if result is None or expected key not present
                logger.warning("Error: {}".format(err))
        else:
            logger.debug("Error: getblockchaininfo")

        # mempool info
        cmds = "{} -datadir={} getmempoolinfo".format(self.bitcoin_cli, self.bitcoin_dir)
        _mempool_info, success, timed_out = run_user(cmds, timeout=self.timeout)
        if success:
            try:
                self.mempool.val = json.loads(_mempool_info)["size"]
            except (KeyError, TypeError) as err:  # catch if None, expected index/key not present
                logger.warning("Error: {}".format(err))

        # bitcoin network connectivity info
        cmds = "{} -datadir={} getnetworkinfo".format(self.bitcoin_cli, self.bitcoin_dir)
        _network_info, success, timed_out = run_user(cmds, timeout=self.timeout)
        if success:
            try:
                for nw in json.loads(_network_info)["networks"]:
                    if nw["name"] == "ipv4":
                        if nw["reachable"]:
                            self.bitcoin_ipv4_reachable.val = True
                            self.bitcoin_ipv4_reachable.txt = "True"
                            self.bitcoin_ipv4_reachable.style = "green"
                        else:
                            self.bitcoin_ipv4_reachable.val = False
                            self.bitcoin_ipv4_reachable.txt = "False"
                            self.bitcoin_ipv4_reachable.style = "red"
                        if nw["limited"]:
                            self.bitcoin_ipv4_limited.val = True
                            self.bitcoin_ipv4_limited.txt = "True"
                            self.bitcoin_ipv4_limited.style = "green"
                        else:
                            self.bitcoin_ipv4_limited.val = False
                            self.bitcoin_ipv4_limited.txt = "False"
                            self.bitcoin_ipv4_limited.style = "red"

                    if nw["name"] == "ipv6":
                        if nw["reachable"]:
                            self.bitcoin_ipv6_reachable.val = True
                            self.bitcoin_ipv6_reachable.txt = "True"
                            self.bitcoin_ipv6_reachable.style = "green"
                        else:
                            self.bitcoin_ipv6_reachable.val = False
                            self.bitcoin_ipv6_reachable.txt = "False"
                            self.bitcoin_ipv6_reachable.style = "red"

                        if nw["limited"]:
                            self.bitcoin_ipv6_limited.val = True
                            self.bitcoin_ipv6_limited.txt = "True"
                            self.bitcoin_ipv6_limited.style = "green"
                        else:
                            self.bitcoin_ipv6_limited.val = False
                            self.bitcoin_ipv6_limited.txt = "False"
                            self.bitcoin_ipv6_limited.style = "red"

                    if nw["name"] == "onion":
                        if nw["reachable"]:
                            self.bitcoin_onion_reachable.val = True
                            self.bitcoin_onion_reachable.txt = "True"
                            self.bitcoin_onion_reachable.style = "green"
                        else:
                            self.bitcoin_onion_reachable.val = False
                            self.bitcoin_onion_reachable.txt = "False"
                            self.bitcoin_onion_reachable.style = "red"

                        if nw["limited"]:
                            self.bitcoin_onion_limited.val = True
                            self.bitcoin_onion_limited.txt = "True"
                            self.bitcoin_onion_limited.style = "green"
                        else:
                            self.bitcoin_onion_limited.val = False
                            self.bitcoin_onion_limited.txt = "False"
                            self.bitcoin_onion_limited.style = "red"

            except (KeyError, TypeError) as err:  # catch if None, expected index/key not present
                logger.warning("Error: {}".format(err))

            self.bitcoin_local_adresses = list()
            try:
                for la in json.loads(_network_info)["localaddresses"]:
                    if ":" in la["address"]:
                        if la["address"] in self.ipv6_addresses:
                            self.bitcoin_local_adresses.append("[{}]:{}".format(la["address"], la["port"]))
                    elif ".onion" in la["address"]:
                        self.bitcoin_local_adresses.append("{}:{}".format(la["address"], la["port"]))

                        if self.bitcoin_onion_reachable:
                            self.tor_active = Metric("+ Tor")
                        else:
                            self.tor_active = Metric("+ Tor?")
                    else:
                        self.bitcoin_local_adresses.append("{}:{}".format(la["address"], la["port"]))

            except (KeyError, TypeError) as err:  # catch if None, expected index/key not present
                logger.warning("Error: {}".format(err))

    def update_lnd_dirs(self):
        # set datadir - requires network and chain to be set/checked
        self.lnd_dir = "/home/bitcoin/.lnd"
        self.lnd_macaroon_dir = "/home/bitcoin/.lnd/data/chain/{0}/{1}net".format(self.network.val, self.chain.val)

    def read_lnd_config(self):
        _lnd_conf = "{}/lnd.conf".format(self.lnd_dir)
        if not os.path.exists(_lnd_conf):
            return

        config = configparser.ConfigParser(strict=False)
        config.read(_lnd_conf)
        self.lnd_config = config

    def check_lnd_is_running(self):
        # check if lnd is running
        cmds = "ps aux | grep -e \"bin\/lnd\" | grep -v grep | wc -l"
        _lnd_running, success, timed_out = run_user(cmds, timeout=self.timeout)
        if success:
            try:
                if _lnd_running.split("\n")[0] == "0":
                    self.lnd_is_running = False
                    # print("WARN: LND not running!")
                else:
                    self.lnd_is_running = True
                    return True
            except IndexError as err:
                logger.warning("Error: {}".format(err))

        return False

    def update_lnd_wallet_is_locked(self):
        # LN Wallet Lock Status
        cmds = "sudo tail -n 1 /mnt/hdd/lnd/logs/{0}/{1}net/lnd.log".format(self.network.val, self.chain.val)
        _ln_lock_status_log, success, timed_out = run_user(cmds)
        if success:
            if re.match(".*unlock.*", _ln_lock_status_log):
                self.lnd_wallet_lock_status = Metric("\U0001F512", style="red")
                self.lnd_wallet_lock_status.val = True
                self.lnd_wallet_is_locked = True
            else:
                self.lnd_wallet_lock_status = Metric("\U0001F513", style="green")
                self.lnd_wallet_lock_status.val = False
                self.lnd_wallet_is_locked = False
                return False

        return True

    # def _update_lncli_version(self):
    #     # get lnd client version client
    #     cmds = "/usr/local/bin/lncli --version"
    #     _ln_client_version, success, timed_out = run_user(cmds, timeout=self.timeout)
    #     if success:
    #         try:
    #             line = _ln_client_version.split("\n")[0]
    #             self.lnd_lncli_version.raw = line.split(" ")[2]
    #             self.lnd_lncli_version = self.lnd_lncli_version.raw
    #         except IndexError as err:
    #             logger.warning("Error: {}".format(err))

    def update_lnd_alias(self):
        try:
            self.lnd_alias.val = self.lnd_config["Application Options"]["alias"]
        except (KeyError, TypeError) as err:  # catch if None, expected index/key not present
            logger.warning("Error: {}".format(err))

    def update_lnd_data(self):
        # reset any data that might be changed in this method
        self.lnd_base_msg.val = None
        self.lnd_base_msg.txt = None
        self.lnd_base_msg.style = "default"
        self.lnd_version.val = None
        self.lnd_version.txt = None
        self.lnd_version.style = "green"
        self.lnd_external.val = None
        self.lnd_external.txt = None
        self.lnd_external.style = "yellow"
        self.lnd_channel_msg.val = None
        self.lnd_channel_msg.txt = None
        self.lnd_channel_msg.style = "default"
        self.lnd_wallet_balance.val = None
        self.lnd_wallet_balance.txt = None
        self.lnd_wallet_balance.style = "default"
        self.lnd_channel_balance.val = None
        self.lnd_channel_balance.txt = None
        self.lnd_channel_balance.style = "default"
        self.lnd_channels_online.val = None
        self.lnd_channels_online.txt = None
        self.lnd_channels_online.style = "default"
        self.lnd_channels_total.val = None
        self.lnd_channels_total.txt = None
        self.lnd_channels_total.style = "default"
        self.lnd_is_syned = False

        # If LND is not running exit
        if not self.lnd_is_running:
            return

        # If LN wallet is locked exit
        if self.lnd_wallet_is_locked:
            self.lnd_base_msg.val = "\U0001F512Locked"
            self.lnd_base_msg.style = "red"
            return

        cmds = ("sudo -u bitcoin /usr/local/bin/lncli --macaroonpath={}/readonly.macaroon "
                "--tlscertpath={}/tls.cert getinfo 2>/dev/null".format(self.lnd_macaroon_dir, self.lnd_dir))
        _ln_get_info, success, timed_out = run_user(cmds)
        if success:
            if not _ln_get_info:
                self.lnd_base_msg.val = "Not Started/Ready Yet"
                self.lnd_base_msg.style = "red"

            else:
                try:
                    self.lnd_version.val = json.loads(_ln_get_info)["version"].split(" ")[0]
                except (IndexError, KeyError, TypeError) as err:  # catch if None, expected index/key not present
                    logger.warning("Error: {}".format(err))

                try:
                    self.lnd_external.val = json.loads(_ln_get_info)["uris"][0]
                except (IndexError, KeyError, TypeError) as err:  # catch if None, expected index/key not present
                    logger.warning("Error: {}".format(err))

                try:
                    if not json.loads(_ln_get_info)["synced_to_chain"]:
                        self.lnd_is_syned = False
                    else:
                        self.lnd_is_syned = True
                except (KeyError, TypeError) as err:  # catch if None, expected index/key not present
                    logger.warning("Error: {}".format(err))

        if self.lnd_is_syned:
            # synched_to_chain is True
            cmds = ("sudo -u bitcoin /usr/local/bin/lncli "
                    "--macaroonpath={}/readonly.macaroon --tlscertpath={}/tls.cert "
                    "walletbalance 2>/dev/null".format(self.lnd_macaroon_dir, self.lnd_dir))
            _ln_wallet_balance, success, timed_out = run_user(cmds)
            if success:
                try:
                    self.lnd_wallet_balance.val = int(json.loads(_ln_wallet_balance)["confirmed_balance"])
                    self.lnd_wallet_balance.txt = "{}".format(self.lnd_wallet_balance.val)
                    self.lnd_wallet_balance.style = "yellow"
                except (KeyError, TypeError) as err:  # catch if None, expected index/key not present
                    logger.warning("Error: {}".format(err))
                    self.lnd_wallet_balance.val = None
                    self.lnd_wallet_balance.txt = None

            cmds = ("sudo -u bitcoin /usr/local/bin/lncli "
                    "--macaroonpath={}/readonly.macaroon --tlscertpath={}/tls.cert "
                    "channelbalance 2>/dev/null".format(self.lnd_macaroon_dir, self.lnd_dir))
            _ln_channel_balance, success, timed_out = run_user(cmds)
            if success:
                try:
                    self.lnd_channel_balance.val = int(json.loads(_ln_channel_balance)["balance"])
                    self.lnd_channel_balance.txt = "{}".format(self.lnd_channel_balance.val)
                    self.lnd_channel_balance.style = "yellow"
                except (KeyError, TypeError) as err:  # catch if None, expected index/key not present
                    logger.warning("Error: {}".format(err))
                    self.lnd_channel_balance.val = None
                    self.lnd_channel_balance.txt = None

                try:
                    self.lnd_channels_online.val = int(json.loads(_ln_get_info)["num_active_channels"])
                    self.lnd_channels_online.txt = "{}".format(self.lnd_channels_online.val)
                except (KeyError, TypeError) as err:  # catch if None, expected index/key not present
                    logger.warning("Error: {}".format(err))
                    self.lnd_channels_online.val = None
                    self.lnd_channels_online.txt = None
                except json.decoder.JSONDecodeError as err:  # catch if LND is unable to respond
                    logger.warning("Error: {}".format(err))
                    self.lnd_channels_online.val = None
                    self.lnd_channels_online.txt = None

            cmds = ("sudo -u bitcoin /usr/local/bin/lncli "
                    "--macaroonpath={}/readonly.macaroon --tlscertpath={}/tls.cert "
                    "listchannels 2>/dev/null".format(self.lnd_macaroon_dir, self.lnd_dir))
            _ln_list_channels, success, timed_out = run_user(cmds)
            if success:
                try:
                    self.lnd_channels_total.val = len(json.loads(_ln_list_channels)["channels"])
                except (KeyError, TypeError) as err:  # catch if None, expected index/key not present
                    logger.warning("Error: {}".format(err))

        else:  # LND is not synched
            # is Bitcoind running?!
            if not self.bitcoin_is_running:
                self.lnd_base_msg.val = "{} not running or not ready".format(self.currency['daemon'])
                self.lnd_base_msg.vale = self.lnd_base_msg.val
                self.lnd_base_msg.style = "red"
                return

            self.lnd_base_msg.val = "Waiting for chain sync"
            self.lnd_base_msg.txt = self.lnd_base_msg.val
            self.lnd_base_msg.style = "red"

            cmds = ("sudo -u bitcoin tail -n 10000 "
                    "/mnt/hdd/lnd/logs/{}/{}net/lnd.log".format(self.network.val, self.chain.val))
            _ln_item, success, timed_out = run_user(cmds)
            if not success:
                self.lnd_channel_msg.val = "?!"
                self.lnd_channel_msg.style = "red"

            else:
                _last_match = ""
                for line in _ln_item.split("\n"):
                    obj = re.match(".*\(height=(\d+).*", line)
                    if obj:
                        _last_match = obj.groups()[0]
                    else:
                        obj = re.match(".*Caught up to height (\d+)$", line)
                        if obj:
                            _last_match = obj.groups()[0]

                try:
                    _last_match = int(_last_match)
                except ValueError:
                    _last_match = 0

                if self.block_height.val:
                    if int(_last_match) > 0:
                        self.lnd_channel_msg.val = int(_last_match)
                        self.lnd_channel_msg.txt = "-> scanning {}/{}".format(_last_match, self.block_height)
                        self.lnd_channel_msg.style = "red"
                    else:
                        self.lnd_channel_msg.val = int(_last_match)
                        self.lnd_channel_msg.txt = "-> scanning ??/{}".format(self.block_height)
                        self.lnd_channel_msg.style = "red"

    def update_public_ip(self):
        try:
            f = urlopen('http://v4.ipv6-test.com/api/myip.php')
            self.public_ip.val = f.read(100).decode('utf-8')
        except Exception as err:
            logger.warning("_update_public_ip failed: {}".format(err))

    def update_bitcoin_public_port(self):
        try:
            _public_bitcoin_port = self.bitcoin_config["DEFAULT"]["port"]
        except KeyError:
            if self.chain.val == "test":
                _public_bitcoin_port = self.currency["testnet_port"]

            else:
                _public_bitcoin_port = self.currency["mainnet_port"]

        self.public_bitcoin_port.val = _public_bitcoin_port

    def check_public_ip_bitcoin_port(self):
        if port_check(self.public_ip.val, self.public_bitcoin_port.val, timeout=2.0):
            self.public_bitcoin_port_status.val = True
            self.public_bitcoin_port_status.txt = ""
            self.public_ip.style = "green"
            self.public_bitcoin_port.style = "green"
        else:
            self.public_bitcoin_port_status.val = False
            self.public_bitcoin_port_status.txt = "not reachable"
            self.public_bitcoin_port_status.style = "red"
            self.public_ip.style = "red"
            self.public_bitcoin_port.style = "red"

    def check_public_ip_lnd_port(self):
        if not self.lnd_external.val:
            return

        try:
            _public_lnd_port = int(self.lnd_external.val.split(":")[1])

            if _public_lnd_port:
                if port_check(self.public_ip.val, _public_lnd_port, timeout=2.0):
                    self.public_ip_lnd_port_status.val = True
                    self.public_ip_lnd_port_status.txt = ""
                else:
                    self.public_ip_lnd_port_status.val = False
                    self.public_ip_lnd_port_status.txt = "not reachable"
                    self.public_ip_lnd_port_status.style = "red"
        except IndexError as err:
            logger.warning("Error: {}".format(err))

    def update(self):
        """update Metrics directly or call helper methods"""
        pass

        # self.update_load()
        # self.update_uptime()
        # self.update_cpu_temp()
        # self.update_memory()
        # self.update_storage()
        # self.update_ip_network_data()

        # self.update_network()
        #
        # self.update_bitcoin_dir()
        # self.read_bitcoin_config()
        #
        # self.update_chain()
        #
        # self.update_bitcoin_binaries()
        # self.check_bitcoind_is_running()
        # self.update_bitcoin_daemon_version()
        # self.update_bitcoin_data()

        # self.update_lnd_dirs()
        # self.read_lnd_config()
        # self.check_lnd_is_running()
        # self.update_lnd_wallet_is_locked()
        # self.update_lnd_alias()
        # self.update_lnd_data()
        #
        # self.update_public_ip()
        # self.update_bitcoin_public_port()
        # self.check_public_ip_lnd_port()
        # self.check_public_ip_bitcoin_port()

    def display(self):
        logo0 = _yellow("               ")
        logo1 = _yellow("        ,/     ")
        logo2 = _yellow("      ,'/      ")
        logo3 = _yellow("    ,' /       ")
        logo4 = _yellow("  ,'  /_____,  ")
        logo5 = _yellow(" .'____    ,'  ")
        logo6 = _yellow("      /  ,'    ")
        logo7 = _yellow("     / ,'      ")
        logo8 = _yellow("    /,'        ")
        logo9 = _yellow("   /'          ")

        if self.lnd_is_running:
            if self.lnd_wallet_is_locked:
                lnd_info = Metric("Running", style="yellow")
            else:
                lnd_info = self.lnd_version
        else:
            lnd_info = Metric("Not Running", style="red")

        line9 = "LND {}".format(lnd_info)
        if self.lnd_base_msg.val and self.lnd_channel_msg.val:
            line9 = "{} {}\n               {}".format(line9, self.lnd_base_msg, self.lnd_channel_msg)
        elif self.lnd_base_msg.val:
            line9 = "{} {}".format(line9, self.lnd_base_msg)
        elif self.lnd_channel_msg.val:
            line9 = "{} {}".format(line9, self.lnd_channel_msg)

        if not (self.lnd_channels_online.val and self.lnd_channels_total.val):
            pass
        else:
            if self.lnd_channels_online.val <= self.lnd_channels_total.val:
                self.lnd_channels_online.style = "yellow"
                self.lnd_channels_total.style = "yellow"
            elif self.lnd_channels_online.val == self.lnd_channels_total.val:
                self.lnd_channels_online.style = "green"
                self.lnd_channels_total.style = "green"
            else:
                self.lnd_channels_online.style = "red"
                self.lnd_channels_total.style = "red"

        lines = [
            logo0,
            logo0 + "{} {}  {}".format(self.name, self.version, self.lnd_alias),
            logo0 + "{} {} {}".format(self.network, "Fullnode + Lightning Network", self.tor_active),
            logo1 + _yellow("-------------------------------------------"),
            logo2 + "{} {}, {}, {}  {} {}".format("load average:", self.load_one, self.load_five, self.load_fifteen,
                                                  "CPU:", self.cpu_temp),
            logo3 + "{} {} / {} {} {} ({})".format("Free Mem:", self.memory_avail, self.memory_total,
                                                   "Free HDD:", self.hdd_free_abs, self.hdd_free),
            logo4 + "{}{} ▼{} ▲{}".format("ssh admin@", self.local_ip, self.network_rx, self.network_tx),
            logo5,
            logo6 + "{} {} {} {} {} ({})".format(self.network, self.bitcoin_version, self.chain,
                                                 "Sync", self.sync_status, self.sync_percentage),
            logo7 + "{} {}:{} {}".format("Public", self.public_ip, self.public_bitcoin_port,
                                         self.public_bitcoin_port_status),
            logo8 + "{} {} {}".format("", "", ""),
            logo9 + line9,
            logo0 + "Wallet {} sat  {}/{} Chan {} sat".format(self.lnd_wallet_balance,
                                                              self.lnd_channels_online, self.lnd_channels_total,
                                                              self.lnd_channel_balance),
            logo0,
            "{} {}".format(self.lnd_external, self.public_ip_lnd_port_status)
        ]

        if self.bitcoin_log_msgs:
            lines.append(_yellow("Last lines of: ") + _red("bitcoin/debug.log"))
            for msg in self.bitcoin_log_msgs:
                if len(msg) <= 60:
                    lines.append(msg)
                else:
                    lines.append(msg[0:57] + "...")

        if len(self.bitcoin_local_adresses) == 1:
            lines.append("\nAdditional Public Address (e.g. IPv6)")
            lines.append("* {}".format(self.bitcoin_local_adresses[0]))
        elif len(self.bitcoin_local_adresses) >= 1:
            lines.append("\nAdditional Public Addresses (e.g. IPv6) only showing first")
            lines.append("* {}".format(self.bitcoin_local_adresses[0]))

        for line in lines:
            print(line)

    # def update_and_display(self):
    #     self.update()
    #     clear()
    #     self.display()


def main():
    setup_logging()

    usage = "usage: %prog [Options]"
    parser = OptionParser(usage=usage, version="%prog {}".format(BOARD_VERSION))

    parser.add_option("-H", "--host", dest="host", type="string", default="localhost",
                      help="Host to listen on (default localhost)")
    parser.add_option("-P", "--port", dest="port", type="int", default="8000",
                      help="Port to listen on (default 8000)")

    parser.add_option("-c", "--crypto-currency", dest="crypto_currency", type="string", default="bitcoin",
                      help="Currency/Network to report on (default bitcoin)")
    parser.add_option("-t", "--timeout", dest="timeout", type="int", default=TIMEOUT,
                      help="how long to wait for data to be collected (default {} sec)".format(TIMEOUT))
    parser.add_option("-r", "--refresh", dest="refresh", type="int", default=5,
                      help="interval to refresh data when looping (default 5 sec)")
    parser.add_option("--interface", dest="interface", type="string", default=IF_NAME,
                      help="network interface to report on (default {})".format(IF_NAME))

    options, args = parser.parse_args()

    crypto_currency = options.crypto_currency.lower()
    if crypto_currency not in list(CRYPTO_CURRENCIES.keys()):
        raise ValueError("Unexpected Crypto Currency given: {}".format(options.crypto_currency))

    logger.info("Starting infoBlitz...")

    board = Dashboard(crypto_currency)
    board.timeout = 120
    board.interface = options.interface
    board.name = Metric(BOARD_NAME, style="yellow")
    board.version = Metric(BOARD_VERSION, style="yellow")

    # use a threading.Lock() to ensure access to the same data from different threads
    board_lock = threading.Lock()

    dashboard_updater_thread = DashboardUpdater(board=board, board_lock=board_lock, interval=options.refresh)
    dashboard_printer_thread = DashboardPrinter(board=board, board_lock=board_lock, interval=options.refresh + 10)
    web_server_thread = ThreadedHTTPServer(options.host, options.port, board, board_lock, name="Web_Server")

    logger.info("Starting Dashboard Updater")
    dashboard_updater_thread.start()
    logger.info("Starting Dashboard Printer")
    dashboard_printer_thread.start()
    logger.info("Starting Web Server: http://{}:{}".format(options.host, options.port))
    web_server_thread.start()

    # for info/debug only
    logger.debug("Threads: [{}]".format("; ".join([t.getName() for t in threading.enumerate()])))

    try:
        while True:  # run in loop that can be interrupted with CTRL+c
            time.sleep(0.2)  # ToDO check.. not quite sure..
    except KeyboardInterrupt:
        logger.debug("Stopping server loop")
        web_server_thread.stop()
        sys.exit(0)


if __name__ == "__main__":
    main()
