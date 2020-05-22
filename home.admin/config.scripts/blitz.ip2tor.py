#!/usr/bin/python3

import sys
import locale
import requests
import json
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
        choices=[("(1)", "Test HTTP REQUEST thru TOR PROXY"),
        ("(2)", "Make REST API - JSON request")])
    if code == d.OK:
        if tag == "(1)":
            session = requests.session()
            session.proxies = {'http':  'socks5://127.0.0.1:9050', 'https': 'socks5://127.0.0.1:9050'}
            print("Needs: pip3 install pysocks\n")
            print("Call 'http://httpbin.org/ip' thru TOR proxy:\n")
            print(session.get("http://httpbin.org/ip").text)
            print("Call 'http://httpbin.org/ip' normal:\n")
            print(requests.get("http://httpbin.org/ip").text)
            print("Call 'https://shop.ip2t.org/api/v1/public/hosts/' thru TOR:\n")
            print(session.get("https://shop.ip2t.org/api/v1/public/hosts/").text)
        if tag == "(2)":
            myresp = requests.get('https://shop.ip2t.org/api/v1/public/hosts/')
            jData = json.loads(myresp.content)
            print("The response contains {0} properties".format(len(jData)))
            print("\n")
            for key in jData:
                print (key)
                print("\n")
    else:
        print("Cancel")