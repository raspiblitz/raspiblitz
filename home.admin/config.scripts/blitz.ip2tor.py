#!/usr/bin/python3

import sys
import locale
from dialog import Dialog

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("manage ip2tor subscriptions for raspiblitz")
    print("blitz.ip2tor.py menu")
    sys.exit(1)

# basic settings
locale.setlocale(locale.LC_ALL, '')

###############
# MENU
###############

if sys.argv[1] == "menu":

    d = Dialog(dialog="dialog",autowidgetsize=True)
    d.set_background_title("IP2TOR Subscription Service")
    code, tag = d.menu("OK, then you have two options:",
        choices=[("(1)", "Leave this fascinating example"),
        ("(2)", "Leave this fascinating example")])
    if code == d.OK:
        print("OK --> ")
        print(tag)
    else:
        print("Cancel")
  
