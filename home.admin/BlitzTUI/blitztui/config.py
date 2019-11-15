# -*- coding: utf-8 -*-

import logging
import os
from configparser import ConfigParser, DEFAULTSECT

log = logging.getLogger(__name__)


class LndConfig(object):
    def __init__(self, abs_path="/mnt/hdd/lnd/lnd.conf"):
        self.abs_path = abs_path

        # default values for LND Configuration
        self.rpc_listen = ""

    @property
    def rpc_listen_host(self):
        return self.rpc_listen.split(":")[0]

    @property
    def rpc_listen_port(self):
        try:
            return int(self.rpc_listen.split(":")[1])
        except (IndexError, TypeError, ValueError):
            return 0

    def reload(self):
        """load config from file"""
        parser = ConfigParser()

        log.debug("loading config from file: {}".format(self.abs_path))
        with open(self.abs_path) as f:
            parser.read_string(f.read())

        app_options = parser["Application Options"]

        self.rpc_listen = get_str_clean(app_options, "rpclisten", self.rpc_listen)


class RaspiBlitzConfig(object):
    def __init__(self, abs_path="/mnt/hdd/raspiblitz.conf"):
        self.abs_path = abs_path

        # default values for RaspiBlitz Configuration
        self.auto_nat_discovery = False
        self.auto_pilot = False
        self.auto_unlock = False
        self.chain = ""
        self.dynDomain = ""
        self.dyn_update_url = ""
        self.hostname = ""
        self.invoice_allow_donations = False
        self.invoice_default_amount = 402
        self.lcd_rotate = False
        self.lnd_address = ""
        self.lnd_port = ""
        self.network = ""
        self.public_ip = ""
        self.rtl_web_interface = False
        self.run_behind_tor = False
        self.ssh_tunnel = ""
        self.touchscreen = False
        self.version = ""

    def reload(self):
        """load config from file"""
        parser = ConfigParser()

        log.debug("loading config from file: {}".format(self.abs_path))
        with open(self.abs_path) as f:
            parser.read_string("[{}]\n".format(DEFAULTSECT) + f.read())

        default_s = parser[DEFAULTSECT]

        self.auto_nat_discovery = default_s.getboolean("autoNatDiscovery", self.auto_nat_discovery)
        self.auto_pilot = default_s.getboolean("autoPilot", self.auto_pilot)
        self.auto_unlock = default_s.getboolean("autoUnlock", self.auto_unlock)
        self.chain = get_str_clean(default_s, "chain", self.chain)
        self.dynDomain = get_str_clean(default_s, "dynDomain", self.dynDomain)
        self.dyn_update_url = get_str_clean(default_s, "dynUpdateUrl", self.dyn_update_url)
        self.hostname = get_str_clean(default_s, "hostname", self.hostname)
        self.invoice_allow_donations = default_s.getboolean("invoiceAllowDonations", self.invoice_allow_donations)
        self.invoice_default_amount = get_int_safe(default_s, "invoiceDefaultAmount", self.invoice_default_amount)
        self.lcd_rotate = default_s.getboolean("lcdrotate", self.lcd_rotate)
        self.lnd_address = get_str_clean(default_s, "lndAddress", self.lnd_address)
        self.lnd_port = get_str_clean(default_s, "lndPort", self.lnd_port)
        self.network = get_str_clean(default_s, "network", self.network)
        self.public_ip = get_str_clean(default_s, "publicIP", self.public_ip)
        self.rtl_web_interface = default_s.getboolean("rtlWebinterface", self.rtl_web_interface)
        self.run_behind_tor = default_s.getboolean("runBehindTor", self.run_behind_tor)
        self.ssh_tunnel = get_str_clean(default_s, "sshtunnel", self.ssh_tunnel)
        self.touchscreen = default_s.getboolean("touchscreen", self.touchscreen)
        self.version = get_str_clean(default_s, "raspiBlitzVersion", self.version)


class RaspiBlitzInfo(object):
    def __init__(self, abs_path="/home/admin/raspiblitz.info"):
        self.abs_path = abs_path

        # default values for RaspiBlitz Info
        self.base_image = ""
        self.chain = ""
        self.message = ""
        self.network = ""
        self.setup_step = 0
        self.state = ""
        self.undervoltage_reports = 0

    def reload(self):
        """load config from file"""
        parser = ConfigParser()

        log.debug("loading config from file: {}".format(self.abs_path))
        with open(self.abs_path) as f:
            parser.read_string("[{}]\n".format(DEFAULTSECT) + f.read())

        default_s = parser[DEFAULTSECT]

        self.base_image = get_str_clean(default_s, "baseimage", self.base_image)
        self.chain = get_str_clean(default_s, "chain", self.chain)
        self.message = get_str_clean(default_s, "message", self.message)
        self.network = get_str_clean(default_s, "network", self.network)
        self.setup_step = get_int_safe(default_s, "setupStep", self.setup_step)
        self.state = get_str_clean(default_s, "state", self.state)
        self.undervoltage_reports = get_int_safe(default_s, "undervoltageReports", self.undervoltage_reports)


def get_int_safe(cp_section, key, default_value):
    """take a ConfigParser section, get key that might be string encoded int and return int"""
    try:
        value = cp_section.getint(key, default_value)
    except ValueError:
        _value = cp_section.get(key)
        value = int(_value.strip("'").strip('"'))  # this will raise an Exception if int() fails!
    return value


def get_str_clean(cp_section, key, default_value):
    """take a ConfigParser section, get key and strip leading and trailing  \' and \" chars"""
    value = cp_section.get(key, default_value)
    if not value:
        return ""

    return value.lstrip('"').lstrip("'").rstrip('"').rstrip("'")


def main():
    lnd_cfg = LndConfig()
    if os.path.exists(lnd_cfg.abs_path):
        lnd_cfg.reload()

        print("=======\n= LND =\n=======")
        print("rpc_list: \t\t{}".format(lnd_cfg.rpc_listen))
        print("rpc_list_host: \t\t{}".format(lnd_cfg.rpc_listen_host))
        print("rpc_list_port: \t\t{}".format(lnd_cfg.rpc_listen_port))
        print("")

    rb_cfg = RaspiBlitzConfig()
    if os.path.exists(rb_cfg.abs_path):
        rb_cfg.reload()

        print("====================\n= RaspiBlitzConfig =\n====================")
        print("auto_nat_discovery: \t\t{}".format(rb_cfg.auto_nat_discovery))
        print("auto_pilot: \t\t\t{}".format(rb_cfg.auto_pilot))
        print("auto_unlock: \t\t\t{}".format(rb_cfg.auto_unlock))
        print("chain: \t\t\t\t{}".format(rb_cfg.chain))
        print("dynDomain: \t\t\t{}".format(rb_cfg.dynDomain))
        print("dyn_update_url: \t\t{}".format(rb_cfg.dyn_update_url))
        print("hostname: \t\t\t{}".format(rb_cfg.hostname))
        print("invoice_allow_donations: \t{}".format(rb_cfg.invoice_allow_donations))
        print("invoice_default_amount: \t{}".format(rb_cfg.invoice_default_amount))
        print("lcd_rotate: \t\t\t{}".format(rb_cfg.lcd_rotate))
        print("lnd_address: \t\t\t{}".format(rb_cfg.lnd_address))
        print("lnd_port: \t\t\t{}".format(rb_cfg.lnd_port))
        print("network: \t\t\t{}".format(rb_cfg.network))
        print("public_ip: \t\t\t{}".format(rb_cfg.public_ip))
        print("rtl_web_interface: \t\t{}".format(rb_cfg.rtl_web_interface))
        print("run_behind_tor: \t\t{}".format(rb_cfg.run_behind_tor))
        print("ssh_tunnel: \t\t\t{}".format(rb_cfg.ssh_tunnel))
        print("touchscreen: \t\t\t{}".format(rb_cfg.touchscreen))
        print("version: \t\t\t{}".format(rb_cfg.version))
        print("")

    rb_info = RaspiBlitzInfo()
    if os.path.exists(rb_info.abs_path):
        rb_info.reload()

        print("==================\n= RaspiBlitzInfo =\n==================")
        print("state: \t\t{}".format(rb_info.state))
        print("")


if __name__ == "__main__":
    main()
