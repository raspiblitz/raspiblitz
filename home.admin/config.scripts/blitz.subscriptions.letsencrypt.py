#!/usr/bin/python3

import sys
import locale
import requests
import json
import math
import time
import datetime, time
import codecs, grpc, os
from pathlib import Path
import toml
from blitzpy import RaspiBlitzConfig

####### SCRIPT INFO #########

# - this subscription does not require any payments
# - the recurring part is managed by the lets encrypt ACME script

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# manage letsencrypt HTTPS certificates for raspiblitz")
    print("# blitz.subscriptions.letsencrypt.py create-ssh-dialog")
    print("# blitz.subscriptions.ip2tor.py subscriptions-new dyndns|ip dnsservice id token")
    print("# blitz.subscriptions.ip2tor.py subscriptions-list")
    print("# blitz.subscriptions.ip2tor.py subscription-cancel id")
    print("# blitz.subscriptions.ip2tor.py subscription-detail id")
    sys.exit(1)

####### BASIC SETTINGS #########

SUBSCRIPTIONS_FILE="/mnt/hdd/app-data/subscriptions/subscriptions.toml"

cfg = RaspiBlitzConfig()
cfg.reload()

# todo: make sure that also ACME script uses TOR if activated
session = requests.session()
if cfg.run_behind_tor:
  session.proxies = {'http':  'socks5h://127.0.0.1:9050', 'https': 'socks5h://127.0.0.1:9050'}

####### HELPER CLASSES #########

class BlitzError(Exception):
    def __init__(self, errorShort, errorLong="", errorException=None):
        self.errorShort = str(errorShort)
        self.errorLong = str(errorLong)
        self.errorException = errorException

####### HELPER FUNCTIONS #########

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def handleException(e):
    if isinstance(e, BlitzError):
        eprint(e.errorLong)
        eprint(e.errorException)
        print("error='{0}'".format(e.errorShort))
    else:
        eprint(e)
        print("error='{0}'".format(str(e)))
    sys.exit(1)

def getsubdomain(fulldomainstring):
    return fulldomainstring.split('.')[0]

####### API Calls to DNS Servcies #########

def duckDNSupdate(domain, token, ip):

    print("# duckDNS update IP API call")
    
    # make HTTP request
    try:
        url="https://www.duckdns.org/update?domains={0}&token={1}&ip={2}".format(getsubdomain(domain), token, ip)
        response = session.get(url)
    except Exception as e:
        raise BlitzError("failed HTTP request",url,e)
    if response.status_code != 200:
        raise BlitzError("failed HTTP code",response.status_code,)
    
    return response.content

####### PROCESS FUNCTIONS #########

def subscriptionsNew(ip, dnsservice, id, token):

    # todo: install lets encrypt if first subscription

    # todo: check given IP (is dynDNS, IP of IP2TOR, or just fixed)

    # todo: update DNS

    # create subscription data for storage
    subscription = {}
    subscription['type'] = "letsencrypt-v1"
    subscription['id'] = id
    subscription['active'] = True
    subscription['name'] = "{0} for {1}".format(dnsservice, id)
    subscription['dnsservice_type'] = dnsservice
    subscription['dnsservice_token'] = token
    subscription['ip'] = ip
    subscription['time_created'] = str(datetime.datetime.now().strftime("%Y-%m-%d %H:%M"))
    subscription['warning'] = ""

    # load, add and store subscriptions
    try:
        os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
        if Path(SUBSCRIPTIONS_FILE).is_file():
            print("# load toml file")
            subscriptions = toml.load(SUBSCRIPTIONS_FILE)
        else:
            print("# new toml file")
            subscriptions = {}
        if "subscriptions_letsencrypt" not in subs:
            subscriptions['subscriptions_letsencrypt'] = []
        subscriptions['subscriptions_letsencrypt'].append(subscription)
        with open(SUBSCRIPTIONS_FILE, 'w') as writer:
            writer.write(toml.dumps(subscriptions))
            writer.close()

    except Exception as e:
        eprint(e)
        raise BlitzError("fail on subscription storage",subscription, e)

    print("# OK - BRIDGE READY: {0}:{1} -> {2}".format(bridge_ip, subscription['port'], torTarget))
    return subscription

def subscriptionsCancel(id):

    os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
    subs = toml.load(SUBSCRIPTIONS_FILE)
    newList = []
    for idx, sub in enumerate(subs['subscriptions_letsencrypt']):
        if sub['id'] != subscriptionID:
            newList.append(sub)
    subs['subscriptions_letsencrypt'] = newList

    # persist change
    with open(SUBSCRIPTIONS_FILE, 'w') as writer:
        writer.write(toml.dumps(subs))
        writer.close()

    print(json.dumps(subs, indent=2))

    # todo: deinstall letsencrypt if this was last subscription

def menuMakeSubscription():

    # todo ... copy parts of IP2TOR dialogs

    ############################
    # PHASE 1: Choose DNS service

    ############################
    # PHASE 2: Enter ID & API token for service

    ############################
    # PHASE 3: Choose what kind of IP: dynDNS, IP2TOR, fixedIP

    return False

####### COMMANDS #########

###############
# CREATE SSH DIALOG
# use for ssh shell menu
###############

if sys.argv[1] == "create-ssh-dialog":

    # check parameters
    try:
        if len(sys.argv) <= 4: raise BlitzError("incorrect parameters","")
        servicename = sys.argv[2]
        toraddress = sys.argv[3]
        port = sys.argv[4]
    except Exception as e:
        handleException(e)

    # late imports - so that rest of script can run also if dependency is not available
    from dialog import Dialog
    menuMakeSubscription(servicename, toraddress, port)

    sys.exit()

###############
# SUBSCRIPTIONS NEW
# call from web interface
###############    

if sys.argv[1] == "subscriptions-new":

    # check parameters
    try:
        if len(sys.argv) <= 5: raise BlitzError("incorrect parameters","")
        ip = sys.argv[2]
        dnsservice_type = sys.argv[3]
        dnsservice_id = sys.argv[4]
        dnsservice_token = sys.argv[5]
    except Exception as e:
        handleException(e)

    # get data
    try:
        subscription = subscriptionsNew(ip, dnsservice_type, dnsservice_id, dnsservice_token)
    except Exception as e:
        handleException(e)

    # output json ordered bridge
    print(json.dumps(subscription, indent=2))
    sys.exit()

#######################
# SUBSCRIPTIONS LIST
#######################

if sys.argv[1] == "subscriptions-list":

    try:

        if Path(SUBSCRIPTIONS_FILE).is_file():
            os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
            subs = toml.load(SUBSCRIPTIONS_FILE)
        else:
            subs = {}
        if "subscriptions_letsencrypt" not in subs:
            subs['subscriptions_letsencrypt'] = []
        print(json.dumps(subs['subscriptions_letsencrypt'], indent=2))
    
    except Exception as e:
        handleException(e)

    sys.exit(0)

#######################
# SUBSCRIPTION CANCEL
#######################
if sys.argv[1] == "subscription-cancel":

    # check parameters
    try:
        if len(sys.argv) <= 2: raise BlitzError("incorrect parameters","")
        subscriptionID = sys.argv[2]
    except Exception as e:
        handleException(e)

    try:

        subscriptionsCancel(subscriptionID)

    except Exception as e:
        handleException(e)

    sys.exit(0)

# unkown command
print("# unkown command")
