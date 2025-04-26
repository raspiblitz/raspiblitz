#!/usr/bin/env python3

import argparse
import logging
import os
import signal
import sys
from argparse import RawTextHelpFormatter
from configparser import ConfigParser, DEFAULTSECT
from blitzpy import RaspiBlitzConfig, RaspiBlitzInfo

LND_CONF = "/mnt/hdd/app-data/lnd/lnd.conf"
RB_CONF = "/mnt/hdd/app-data/raspiblitz.conf"

log = logging.getLogger(__name__)


def main():
    # make sure CTRL+C works
    signal.signal(signal.SIGINT, signal.SIG_DFL)

    description = """RaspiBlitz Config Check"""

    parser = argparse.ArgumentParser(description=description, formatter_class=RawTextHelpFormatter)
    parser.add_argument("-V", "--version",
                        help="print version", action="version",
                        version="0.1")

    parser.add_argument("-p", "--print",
                        help="print parsed config", action="store_true")

    parser.add_argument("-q", "--quiet",
                        help="suppress normal output", action="store_true")


    # parse args
    args = parser.parse_args()

    # Raspi Config
    rb_cfg_valid = False

    rb_cfg = RaspiBlitzConfig()
    if os.path.exists(rb_cfg.abs_path):
        try:
            rb_cfg.reload()

            rb_cfg_valid = True
            if not args.quiet:
                print("RaspiBlitz Config: \tOK")
        except Exception as err:
            if not args.quiet:
                print("RaspiBlitz Config: \tERROR")
                log.warning(err)
                print("# Use command to fix: nano /mnt/hdd/app-data/raspiblitz.conf")
                print("# CTRL+o to save / CRTL+x to exit / then reboot")

    else:
        if not args.quiet:
            print("RaspiBlitz Config: \tMISSING")



    # Raspi Info
    rb_info_valid = False

    rb_info = RaspiBlitzInfo()
    if os.path.exists(rb_info.abs_path):
        try:
            rb_info.reload()

            rb_info_valid = True
            if not args.quiet:
                print("RaspiBlitz Info: \tOK")
        except Exception as err:
            if not args.quiet:
                print("RaspiBlitz Info: \tERROR")
                log.warning(err)

    else:
        if not args.quiet:
            print("RaspiBlitz Info: \tMISSING")


    if args.print:
        print("====================\n= RaspiBlitzConfig =\n====================")
        if rb_cfg_valid:
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
        else:
            print("invalid or missing")
            print("")


        print("==================\n= RaspiBlitzInfo =\n==================")
        if rb_info_valid:
            print("state: \t\t{}".format(rb_info.state))
            print("")
        else:
            print("invalid or missing")
            print("")


    if rb_cfg_valid:
        sys.exit(0)
    else:
        sys.exit(1)

if __name__ == "__main__":
    main()

