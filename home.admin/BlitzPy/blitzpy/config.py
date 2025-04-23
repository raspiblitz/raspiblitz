# -*- coding: utf-8 -*-
import configparser
import copy
import logging
import os
from configparser import DEFAULTSECT, RawConfigParser

log = logging.getLogger(__name__)

_UNSET = object()


class CustomConfigParser(RawConfigParser):
    def get(self, section, option, *, raw=False, vars=None, fallback=_UNSET):
        val = RawConfigParser.get(self, section, option)
        return val.strip('"').strip("'")


class BaseSetting(object):
    TYPE = str

    def __init__(self, key, aliases=None, default=_UNSET):
        self.key = key
        self.aliases = aliases
        self.default = default

        # hidden attributes for properties
        self._is_set = False
        self._value = None

    @property
    def is_set(self):
        return self._is_set

    @property
    def export(self):
        if self.TYPE == bool:
            if self.value:
                return f"{self.key}='on'"
            else:
                return f"{self.key}='off'"
        elif self.TYPE == int:
            return f"{self.key}={self.value}"
        else:
            return f"{self.key}='{self.value}'"

    @property
    def value(self):
        if self._is_set:
            return self._value
        if self.default is not _UNSET:
            return self.default
        return self.TYPE()

    @value.setter
    def value(self, new_value):
        if not isinstance(new_value, self.TYPE):
            raise ValueError(f'must be of type: {self.TYPE}')
        self._is_set = True
        self._value = new_value

    def __eq__(self, other):
        return self.value == other

    def __ne__(self, other):
        return not self.value == other

    def __repr__(self):
        if not self._is_set:
            return f'<{self.__class__.__name__} [{self.key}]: <not set> Default: {self.default}>'
        return f'<{self.__class__.__name__} [{self.key}]: {self._value} Default: {self.default}>'

    def __str__(self):
        return f'{self.key}: {self.value}'

    def get(self, section):
        """gets the value for this settings from a ConfigParser.section instance"""
        try:
            if self.TYPE == bool:
                self.value = section.getboolean(self.key, fallback=self.default)
            elif self.TYPE == int:
                self.value = section.getint(self.key, fallback=self.default)
            else:
                self.value = section.get(self.key, fallback=self.default)
        except configparser.NoOptionError:
            pass


class BoolSetting(BaseSetting):
    TYPE = bool


class IntSetting(BaseSetting):
    TYPE = int


class StrSetting(BaseSetting):
    pass


class BaseConfig(object):
    def __init__(self, *args, **kwargs):
        self.abs_path = None

        # store raw file content (list of lines)
        self.raw_lines = []

        # initialize Custom Config Parser
        self.parser = CustomConfigParser(delimiters=["="], strict=False)

    @property
    def settings(self):
        return {attr: value for attr, value in self.__dict__.items() if isinstance(value, BaseSetting)}

    @property
    def settings_by_keys(self):
        return {value.key: value for attr, value in self.__dict__.items() if isinstance(value, BaseSetting)}

    @property
    def settings_by_aliases_and_keys(self):
        ret = dict()
        for attr, value in self.__dict__.items():
            if isinstance(value, BaseSetting):
                ret.update({value.key: value})
                if value.aliases:
                    for alias in value.aliases:
                        ret.update({alias: value})

        return ret

    def reload(self):
        """load (or reload) config from file"""
        log.debug("loading config from file: {}".format(self.abs_path))
        with open(self.abs_path) as f:
            raw = f.read()

        self.raw_lines = raw.split('\n')

        self.parser.read_string("[{}]\n".format(DEFAULTSECT) + raw)
        default_s = self.parser[DEFAULTSECT]

        for attr, setting in self.settings.items():
            setting.get(default_s)

    def write(self, path=None):
        if not path:
            path = self.abs_path
        keys_to_process = copy.deepcopy(self.settings_by_aliases_and_keys)
        keys_processed = list()
        export_lines = list()

        for line in self.raw_lines:
            line_key = line.split('=')[0]
            if line_key in keys_to_process:
                setting = self.settings_by_aliases_and_keys[line_key]
                export_lines.append(f'{setting.export}\n'.encode())

                keys_processed.append(line_key)

                keys_to_process.pop(line_key)
                if setting.aliases:
                    for alias in setting.aliases:
                        try:
                            keys_to_process.pop(alias)
                        except KeyError:
                            pass
            else:
                # append unknown row as is
                export_lines.append(f'{line}\n'.encode())

        with open(path, 'wb') as f:
            if export_lines[-1] == b'\n':
                # remove 1 trailing blank line
                export_lines = export_lines[:-1]
            f.writelines(export_lines)

        if keys_processed:
            print("[INFO] Keys processed:\n{}".format(', '.join(keys_processed)))
        else:
            print("[WARN] Keys processed: None")

        if keys_to_process:
            print("[WARN] Keys or Aliases not found:\n{}".format(', '.join(keys_to_process)))
        else:
            print("[INFO] Keys or Aliases not found: None")


class RaspiBlitzConfig(BaseConfig):
    def __init__(self, abs_path="/mnt/hdd/app-data/raspiblitz.conf"):
        super().__init__()
        self.abs_path = abs_path

        # default values for RaspiBlitz Configuration
        self.auto_nat_discovery = BoolSetting('autoNatDiscovery', default=False)
        self.auto_pilot = BoolSetting('autoPilot', default=False)
        self.auto_unlock = BoolSetting('autoUnlock', default=False)
        self.chain = StrSetting('chain', default='main')
        self.dyn_domain = StrSetting('dynDomain')
        self.dyn_update_url = StrSetting('dynUpdateUrl')
        self.hostname = StrSetting('hostname')
        self.invoice_allow_donations = BoolSetting('invoiceAllowDonations', default=False)
        self.invoice_default_amount = IntSetting('invoiceDefaultAmount', default=402)
        self.lcd_rotate = BoolSetting('lcdrotate', default=False)
        self.lnd_address = StrSetting('lndAddress')
        self.lnd_port = StrSetting('lndPort')
        self.network = StrSetting('network', default='bitcoin')
        self.public_ip = StrSetting('publicIP')
        self.rtl_web_interface = BoolSetting('rtlWebinterface', default=False)
        self.run_behind_tor = BoolSetting('runBehindTor', default=False)
        self.ssh_tunnel = StrSetting('sshtunnel')
        self.touchscreen = BoolSetting('touchscreen', default=False)
        self.version = StrSetting('raspiBlitzVersion')
        self.lnbits = BoolSetting('LNBits', aliases=['LNbits', 'lnbits'], default=False)

class RaspiBlitzInfo(BaseConfig):
    def __init__(self, abs_path="/home/admin/raspiblitz.info"):
        super().__init__()
        self.abs_path = abs_path

        # default values for RaspiBlitz Info
        self.base_image = StrSetting('base_image')
        self.chain = StrSetting('chain')
        self.message = StrSetting('message')
        self.network = StrSetting('network')
        self.setup_step = IntSetting('setup_step', default=0)
        self.state = StrSetting('state')
        self.undervoltage_reports = IntSetting('undervoltage_reports', default=0)


def main():
    rb_cfg = RaspiBlitzConfig()
    if os.path.exists(rb_cfg.abs_path):
        rb_cfg.reload()

        print("====================\n= RaspiBlitzConfig =\n====================")
        print("auto_nat_discovery: \t\t{}".format(rb_cfg.auto_nat_discovery))
        print("auto_pilot: \t\t\t{}".format(rb_cfg.auto_pilot))
        print("auto_unlock: \t\t\t{}".format(rb_cfg.auto_unlock))
        print("chain: \t\t\t\t{}".format(rb_cfg.chain))
        print("dynDomain: \t\t\t{}".format(rb_cfg.dyn_domain))
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
