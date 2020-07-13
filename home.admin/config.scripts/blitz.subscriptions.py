#!/usr/bin/python3

########################################################
# SSH Dialogs to manage Subscriptions on the RaspiBlitz
########################################################

import sys
import math
import time
import toml
import os
import subprocess

from dialog import Dialog

from blitzpy import RaspiBlitzConfig

# constants for standard services
LND_REST_API = "LND-REST-API"
LND_GRPC_API = "LND-GRPC-API"

# load config 
cfg = RaspiBlitzConfig()
cfg.reload()

# basic values
SUBSCRIPTIONS_FILE="/mnt/hdd/app-data/subscriptions/subscriptions.toml"

####### HELPER FUNCTIONS #########

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def parseDateIP2TORSERVER(datestr):
    return datetime.datetime.strptime(datestr,"%Y-%m-%dT%H:%M:%S.%fZ")

def secondsLeft(dateObj):
    return round((dateObj - datetime.datetime.utcnow()).total_seconds())

####### SSH MENU FUNCTIONS #########

def mySubscriptions():

    # check if any subscriptions are available
    countSubscriptions=0
    try:
        os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
        subs = toml.load(SUBSCRIPTIONS_FILE)
        if 'subscriptions_ip2tor' in subs:
            countSubscriptions += len(subs['subscriptions_ip2tor'])
        if 'subscriptions_letsencrypt' in subs:
            countSubscriptions += len(subs['subscriptions_letsencrypt'])
    except Exception as e: pass
    if countSubscriptions == 0:
        Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
You have no active or inactive subscriptions.
            ''',title="Info")
        return
        
    # load subscriptions and make dialog choices out of it
    choices = []
    lookup = {}
    lookupIndex=0
    subs = toml.load(SUBSCRIPTIONS_FILE)    
        
    # list ip2tor subscriptions
    if 'subscriptions_ip2tor' in subs:
        for sub in subs['subscriptions_ip2tor']:
            # remember subscription under lookupindex
            lookupIndex += 1
            lookup[str(lookupIndex)]=sub
            # add to dialog choices
            if sub['active']:
                activeState="active"
            else:
                activeState="in-active"
            name="IP2TOR Bridge for {0}".format(sub['name'])
            choices.append( ("{0}".format(lookupIndex), "{0} ({1})".format(name.ljust(30), activeState)) )

    # list letsencrypt subscriptions
    if 'subscriptions_letsencrypt' in subs:
        for sub in subs['subscriptions_letsencrypt']:
            # remember subscription under lookupindex
            lookupIndex += 1
            lookup[str(lookupIndex)]=sub
            # add to dialog choices
            if sub['active']:
                activeState="active"
            else:
                activeState="in-active"
            name="LETSENCRYPT {0}".format(sub['id'])
            choices.append( ("{0}".format(lookupIndex), "{0} ({1})".format(name.ljust(30), activeState)) )
    
    # show menu with options
    d = Dialog(dialog="dialog",autowidgetsize=True)
    d.set_background_title("RaspiBlitz Subscriptions")
    code, tag = d.menu(
        "\nYou have the following subscriptions - select for details:",
        choices=choices, cancel_label="Back", width=65, height=15, title="My Subscriptions")
        
    # if user chosses CANCEL
    if code != d.OK: return

    # get data of selected subscrption
    selectedSub = lookup[str(tag)]

    # show details of selected
    d = Dialog(dialog="dialog",autowidgetsize=True)
    d.set_background_title("My Subscriptions")
    if selectedSub['type'] == "letsencrypt-v1":
        if len(selectedSub['warning']) > 0:
            selectedSub['warning'] = "\n{0}".format(selectedSub['warning'])
        text='''
This is a LetsEncrypt subscription using the free DNS service
{dnsservice}

It allows using HTTPS for the domain:
{domain}

The domain is pointing to the IP:
{ip}

The state of the subscription is: {active} {warning}

'''.format( dnsservice=selectedSub['dnsservice_type'],
            domain=selectedSub['id'],
            ip=selectedSub['ip'],
            active= "ACTIVE" if selectedSub['active'] else "NOT ACTIVE",
            warning=selectedSub['warning']
    )

    elif selectedSub['type'] == "ip2tor-v1":
        if len(selectedSub['warning']) > 0:
            selectedSub['warning'] = "\n{0}".format(selectedSub['warning'])
        text='''
This is a IP2TOR subscription bought on {initdate} at
{shop}

It forwards from the public address {publicaddress} to
{toraddress}
for the RaspiBlitz service: {service}

It will renew every {renewhours} hours for {renewsats} sats.
Total payed so far: {totalsats} sats

The state of the subscription is: {active} {warning}

The following additional information is available:
{description}
'''.format( initdate=selectedSub['time_created'],
            shop=selectedSub['shop'],
            publicaddress="{0}:{1}".format(selectedSub['ip'],selectedSub['port']),
            toraddress=selectedSub['tor'],
            renewhours=(round(int(selectedSub['duration'])/3600)),
            renewsats=(round(int(selectedSub['price_extension'])/1000)),
            totalsats=(round(int(selectedSub['price_extension'])/1000)),
            active= "ACTIVE" if selectedSub['active'] else "NOT ACTIVE",
            warning=selectedSub['warning'],
            description=selectedSub['description'],
            service=selectedSub['name']
    )

    if selectedSub['active']:
        extraLable = "CANCEL SUBSCRIPTION"
    else:
        extraLable = "DELETE SUBSCRIPTION"
    code = d.msgbox(text, title="Subscription Detail", ok_label="Back", extra_button=True,  extra_label=extraLable ,width=75, height=30)
        
    # user wants to delete this subscription
    # call the responsible sub script for deletion just in case any subscription needs to do some extra api calls when canceling
    if code == "extra":
        os.system("clear")
        if selectedSub['type'] == "letsencrypt-v1":
            cmd="python /home/admin/config.scripts/blitz.subscriptions.letsencrypt.py subscription-cancel {0}".format(selectedSub['id'])
            print("# running: {0}".format(cmd))    
            os.system(cmd)
            time.sleep(2)
        elif selectedSub['type'] == "ip2tor-v1":
            cmd="python /home/admin/config.scripts/blitz.subscriptions.ip2tor.py subscription-cancel {0}".format(selectedSub['id'])
            print("# running: {0}".format(cmd))    
            os.system(cmd)
            time.sleep(2)
        else:
            print("# FAIL: unknown subscription type")
            time.sleep(3)

    # loop until no more subscriptions or user chooses CANCEL on subscription list
    mySubscriptions()

####### SSH MENU #########

choices = []
choices.append( ("LIST","My Subscriptions") )
choices.append( ("NEW1","+ IP2TOR Bridge (paid)") )
choices.append( ("NEW2","+ LetsEncrypt HTTPS Domain (free)") )

d = Dialog(dialog="dialog",autowidgetsize=True)
d.set_background_title("RaspiBlitz Subscriptions")
code, tag = d.menu(
    "\nCheck existing subscriptions or create new:",
    choices=choices, width=50, height=10, title="Subscription Management")

# if user chosses CANCEL
if code != d.OK:
    sys.exit(0)

####### MANAGE SUBSCRIPTIONS #########

if tag == "LIST":
    mySubscriptions()
    sys.exit(0)

####### NEW LETSENCRYPT HTTPS DOMAIN #########

if tag == "NEW2":

    # run creating a new IP2TOR subscription
    os.system("clear")
    cmd="python /home/admin/config.scripts/blitz.subscriptions.letsencrypt.py create-ssh-dialog"
    print("# running: {0}".format(cmd))
    os.system(cmd)
    sys.exit(0)

####### NEW IP2TOR BRIDGE #########

if tag == "NEW1":

    # check if Blitz is running behind TOR
    cfg.reload()
    if not cfg.run_behind_tor.value:
        Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
The IP2TOR service just makes sense if you run
your RaspiBlitz behind TOR.
        ''',title="Info")
        sys.exit(1)

    # check for which standard services already a active bridge exists
    lnd_rest_api=False
    lnd_grpc_api=False
    try:
        if os.path.isfile(SUBSCRIPTIONS_FILE):
            os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
            subs = toml.load(SUBSCRIPTIONS_FILE)
            for sub in subs['subscriptions_ip2tor']:
                if not sub['active']: next
                if sub['active'] and sub['name'] == LND_REST_API: lnd_rest_api=True
                if sub['active'] and sub['name'] == LND_GRPC_API: lnd_grpc_api=True
    except Exception as e:
        print(e)

    # ask user for which RaspiBlitz service the bridge should be used
    choices = []
    choices.append( ("REST","LND REST API {0}".format("--> ALREADY BRIDGED" if lnd_rest_api else "")) )
    choices.append( ("GRPC","LND gRPC API {0}".format("--> ALREADY BRIDGED" if lnd_grpc_api else "")) )
    choices.append( ("SELF","Create a custom IP2TOR Bridge") )

    d = Dialog(dialog="dialog",autowidgetsize=True)
    d.set_background_title("RaspiBlitz Subscriptions")
    code, tag = d.menu(
        "\nChoose RaspiBlitz Service to create Bridge for:",
        choices=choices, width=60, height=10, title="Select Service")

    # if user chosses CANCEL
    if code != d.OK:
        sys.exit(0)

    servicename=None
    torAddress=None
    torPort=None
    if tag == "REST":
        # get TOR address for REST
        servicename=LND_REST_API
        torAddress = subprocess.run(['sudo', 'cat', '/mnt/hdd/tor/lndrest8080/hostname'], stdout=subprocess.PIPE).stdout.decode('utf-8').strip()
        torPort=8080
    if tag == "GRPC":
        # get TOR address for GRPC
        servicename=LND_GRPC_API
        torAddress = subprocess.run(['sudo', 'cat', '/mnt/hdd/tor/lndrpc10009/hostname'], stdout=subprocess.PIPE).stdout.decode('utf-8').strip()
        torPort=10009
    if tag == "SELF":
        servicename="CUSTOM"
        try:
            # get custom TOR address
            code, text = d.inputbox(
                "Enter TOR Onion-Address:",
                height=10, width=60, init="",
                title="IP2TOR Bridge Target")
            text = text.strip()
            os.system("clear")
            if code != d.OK: sys.exit(0)
            if len(text) == 0: sys.exit(0)
            if text.find('.onion') < 0 or text.find(' ') > 0 :
                print("Not a TOR Onion Address")
                time.sleep(3)
                sys.exit(0)
            torAddress = text
            # get custom TOR port
            code, text = d.inputbox(
                "Enter TOR Port Number:",
                height=10, width=40, init="80",
                title="IP2TOR Bridge Target")
            text = text.strip()
            os.system("clear")
            if code != d.OK: sys.exit(0)
            if len(text) == 0: sys.exit(0)
            torPort = int(text)
        except Exception as e:
            print(e)
            time.sleep(3)
            sys.exit(1)

    # run creating a new IP2TOR subscription
    os.system("clear")
    cmd="python /home/admin/config.scripts/blitz.subscriptions.ip2tor.py create-ssh-dialog {0} {1} {2}".format(servicename,torAddress,torPort)
    print("# running: {0}".format(cmd))
    os.system(cmd)
    sys.exit(0)