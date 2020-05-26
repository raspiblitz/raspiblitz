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
        subs = toml.load(SUBSCRIPTIONS_FILE)
        countSubscriptions += len(subs['subscriptions_ip2tor'])
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
    for sub in subs['subscriptions_ip2tor']:
        # remember subscription under lookupindex
        lookupIndex += 1
        lookup[str(lookupIndex)]=sub
        # add to dialog choices
        if sub['active']:
            activeState="active"
        else:
            activeState="in-active"
        name="IP2TOR Bridge for {0}".format(sub['blitz_service'])
        choices.append( ("{0}".format(lookupIndex), "{0} ({1})".format(name.ljust(30), activeState)) )
    
    # show menu with options
    d = Dialog(dialog="dialog",autowidgetsize=True)
    d.set_background_title("RaspiBlitz Subscriptions")
    code, tag = d.menu(
        "\nYou have the following subscriptions - select for details:",
        choices=choices, width=65, height=15, title="My Subscriptions")
        
    # if user chosses CANCEL
    if code != d.OK: return

    # get data of selected subscrption
    selectedSub = lookup[str(tag)]

    # show details of selected
    d = Dialog(dialog="dialog",autowidgetsize=True)
    d.set_background_title("My Subscriptions")
    if selectedSub['type'] == "ip2tor-v1":
        if len(selectedSub['warning']) > 0:
            selectedSub['warning'] = "\n{0}".formart(selectedSub['warning'])
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
            service=selectedSub['blitz_service']
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
        if selectedSub['type'] == "ip2tor-v1":
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
choices.append( ("NEW1","+ new IP2TOR Bridge") )

d = Dialog(dialog="dialog",autowidgetsize=True)
d.set_background_title("RaspiBlitz Subscriptions")
code, tag = d.menu(
    "\nCheck your existing subscriptions or create new:",
    choices=choices, width=40, height=10, title="Subscription Management")

# if user chosses CANCEL
if code != d.OK:
    sys.exit(0)

if tag == "LIST":
    mySubscriptions()
    sys.exit(0)

if tag == "NEW1":
    cmd="python /home/admin/config.scripts/blitz.subscriptions.ip2tor.py blitz.subscriptions.ip2tor.py create-ssh-dialog {0} {1} {2}".format("RTL","s7foqiwcstnxmlesfsjt7nlhwb2o6w44hc7glv474n7sbyckf76wn6id.onion","80")
    print("# running: {0}".format(cmd))
    os.system(cmd)
    sys.exit(0)