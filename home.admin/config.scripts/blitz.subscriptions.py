#!/usr/bin/python3

########################################################
# SSH Dialogs to manage Subscriptions on the RaspiBlitz
########################################################

import sys
import math
import time
import toml

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
You have no active or inactive subscriptions at the moment.
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
        name="IP2TOR brigde for {0}".format(sub['blitz_service'])
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
            active= "active" if selectedSub['active'] else "inactive",
            warning=selectedSub['warning'],
            description=selectedSub['description'],
            service=selectedSub['blitz_service']
    )

    if selectedSub['active']:
        extraLable = "CANCEL"
    else:
        extraLable = "DELETE"
    code = d.msgbox(text, title="Subscription Detail", ok_label="Back", extra_button=True,  extra_label=extraLable ,width=70, height=30)
        
    # user wants to delete this subscription
    if code == "extra":
        if selectedSub['type'] == "ip2tor-v1":
            # TODO: make call to blitz.ip2tor to cancel/delete subscription
            pass
    
    # loop until no more subscriptions or user chooses CANCEL on subscription list
    mySubscriptions()

####### SSH MENU #########

mySubscriptions()