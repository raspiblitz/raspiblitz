#!/usr/bin/python3

import json
import os
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import requests
import toml

# add blitzpy to path (relative for dev environments)
script_dir = os.path.dirname(os.path.abspath(__file__))
# prioritize local BlitzPy if it exists (for repo testing)
local_blitzpy = os.path.abspath(os.path.join(script_dir, '..', 'BlitzPy'))
if os.path.exists(local_blitzpy):
    sys.path.insert(0, local_blitzpy)

from blitzpy import RaspiBlitzConfig
from blitzpy.exceptions import BlitzError

#####################
# SCRIPT INFO
#####################

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# manage TunnelSats VPN subscriptions for raspiblitz")
    print("# blitz.subscriptions.tunnelsats.py create-ssh-dialog")
    print("# blitz.subscriptions.tunnelsats.py subscriptions-list")
    print("# blitz.subscriptions.tunnelsats.py subscription-cancel <id>")
    sys.exit(1)

#####################
# BASIC SETTINGS
#####################

SUBSCRIPTIONS_FILE = "/mnt/hdd/app-data/subscriptions/subscriptions.toml"

# explicitly set path because some blitzpy versions have wrong default
cfg_path = "/mnt/hdd/app-data/raspiblitz.conf"
if not os.path.exists(cfg_path):
    cfg_path = "/mnt/hdd/raspiblitz.conf"
cfg = RaspiBlitzConfig(abs_path=cfg_path)
cfg.reload()

session = requests.session()

#####################
# HELPER FUNCTIONS
#####################

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def handleException(e):
    if isinstance(e, BlitzError):
        print("error='{0}'".format(e.short))
    else:
        eprint(e)
        print("error='{0}'".format(str(e)))
    sys.exit(1)

def subscriptions_list():
    try:
        if Path(SUBSCRIPTIONS_FILE).is_file():
            os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
            subs = toml.load(SUBSCRIPTIONS_FILE)
        else:
            subs = {}
        if "subscriptions_tunnelsats" not in subs:
            subs['subscriptions_tunnelsats'] = []
        print(json.dumps(subs['subscriptions_tunnelsats'], indent=2))
    except Exception as e:
        handleException(e)

def create_ssh_dialog():
    from dialog import Dialog
    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("TunnelSats Subscription")
    
    # Check if TunnelSats is already active via bonus script
    # This is a placeholder for actual integration logic
    d.msgbox("TunnelSats Subscription Management via Python is coming soon.\n\nPlease use the Services menu for now.", title="Under Construction")

if __name__ == "__main__":
    if sys.argv[1] == "create-ssh-dialog":
        create_ssh_dialog()
    elif sys.argv[1] == "subscriptions-list":
        subscriptions_list()
    else:
        print("Unknown command: {0}".format(sys.argv[1]))
        sys.exit(1)
