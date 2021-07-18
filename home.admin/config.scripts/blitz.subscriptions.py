#!/usr/bin/python3

########################################################
# SSH Dialogs to manage Subscriptions on the RaspiBlitz
########################################################

import os
import subprocess
import sys
import time
from datetime import datetime

import toml
sys.path.append('/home/admin/raspiblitz/home.admin/BlitzPy/blitzpy')
from config import RaspiBlitzConfig
from dialog import Dialog

# constants for standard services
SERVICE_LND_REST_API = "LND-REST-API"
SERVICE_LND_GRPC_API = "LND-GRPC-API"
SERVICE_LNBITS = "LNBITS"
SERVICE_BTCPAY = "BTCPAY"
SERVICE_SPHINX = "SPHINX"

# load config
cfg = RaspiBlitzConfig()
cfg.reload()

# basic values
SUBSCRIPTIONS_FILE = "/mnt/hdd/app-data/subscriptions/subscriptions.toml"

exec(open('/home/admin/_tor.commands.sh').read())


#######################
# HELPER FUNCTIONS
#######################

# ToDo(frennkie) these are not being used!

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def parse_date_ip2tor(date_str):
    return datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S.%fZ")


def seconds_left(date_obj):
    return round((date_obj - datetime.utcnow()).total_seconds())


#######################
# SSH MENU FUNCTIONS
#######################

def my_subscriptions():
    # check if any subscriptions are available
    count_subscriptions = 0
    try:
        os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
        subs = toml.load(SUBSCRIPTIONS_FILE)
        if 'subscriptions_ip2tor' in subs:
            count_subscriptions += len(subs['subscriptions_ip2tor'])
        if 'subscriptions_letsencrypt' in subs:
            count_subscriptions += len(subs['subscriptions_letsencrypt'])
    except Exception as e:
        print(f"warning: {e}")

    if count_subscriptions == 0:
        Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
You have no active or inactive subscriptions.
            ''', title="Info")
        return

    # load subscriptions and make dialog choices out of it
    choices = []
    lookup = {}
    lookup_index = 0
    subs = toml.load(SUBSCRIPTIONS_FILE)

    # list ip2tor subscriptions
    if 'subscriptions_ip2tor' in subs:
        for sub in subs['subscriptions_ip2tor']:
            # remember subscription under lookupindex
            lookup_index += 1
            lookup[str(lookup_index)] = sub
            # add to dialog choices
            if sub['active']:
                active_state = "active"
            else:
                active_state = "in-active"
            name = "IP2TOR Bridge (P:{1}) for {0}".format(sub['name'], sub['port'])
            choices.append(("{0}".format(lookup_index), "{0} ({1})".format(name.ljust(30), active_state)))

    # list letsencrypt subscriptions
    if 'subscriptions_letsencrypt' in subs:
        for sub in subs['subscriptions_letsencrypt']:
            # remember subscription under lookupindex
            lookup_index += 1
            lookup[str(lookup_index)] = sub
            # add to dialog choices
            if sub['active']:
                active_state = "active"
            else:
                active_state = "in-active"
            name = "LETSENCRYPT {0}".format(sub['id'])
            choices.append(("{0}".format(lookup_index), "{0} ({1})".format(name.ljust(30), active_state)))

    # show menu with options
    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("RaspiBlitz Subscriptions")
    code, tag = d.menu(
        "\nYou have the following subscriptions - select for details:",
        choices=choices, cancel_label="Back", width=65, height=15, title="My Subscriptions")

    # if user chosses CANCEL
    if code != d.OK:
        return

    # get data of selected subscription
    selected_sub = lookup[str(tag)]

    # show details of selected
    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("My Subscriptions")
    if selected_sub['type'] == "letsencrypt-v1":
        if len(selected_sub['warning']) > 0:
            selected_sub['warning'] = "\n{0}".format(selected_sub['warning'])
        text = '''
This is a LetsEncrypt subscription using the free DNS service
{dnsservice}

It allows using HTTPS for the domain:
{domain}

The domain is pointing to the IP:
{ip}

The state of the subscription is: {active} {warning}

The following additional information is available:
{description}

'''.format(dnsservice=selected_sub['dnsservice_type'],
           domain=selected_sub['id'],
           ip=selected_sub['ip'],
           active="ACTIVE" if selected_sub['active'] else "NOT ACTIVE",
           warning=selected_sub['warning'],
           description=selected_sub['description']
           )

    elif selected_sub['type'] == "ip2tor-v1":
        if len(selected_sub['warning']) > 0:
            selected_sub['warning'] = "\n{0}".format(selected_sub['warning'])
        text = '''
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
'''.format(initdate=selected_sub['time_created'],
           shop=selected_sub['shop'],
           publicaddress="{0}:{1}".format(selected_sub['ip'], selected_sub['port']),
           toraddress=selected_sub['tor'],
           renewhours=(round(int(selected_sub['duration']) / 3600)),
           renewsats=(round(int(selected_sub['price_extension']) / 1000)),
           totalsats=(round(int(selected_sub['price_total']) / 1000)),
           active="ACTIVE" if selected_sub['active'] else "NOT ACTIVE",
           warning=selected_sub['warning'],
           description=selected_sub['description'],
           service=selected_sub['name']
           )
    else:
        text = "no text?! FIXME"

    if selected_sub['active']:
        extra_label = "CANCEL SUBSCRIPTION"
    else:
        extra_label = "DELETE SUBSCRIPTION"
    code = d.msgbox(text, title="Subscription Detail", ok_label="Back", extra_button=True, extra_label=extra_label,
                    width=75, height=30)

    # user wants to delete this subscription
    # call the responsible sub script for deletion just in case any subscription needs to do some extra
    # api calls when canceling
    if code == "extra":
        os.system("clear")
        if selected_sub['type'] == "letsencrypt-v1":
            cmd = "python /home/admin/config.scripts/blitz.subscriptions.letsencrypt.py subscription-cancel {0}".format(
                selected_sub['id'])
            print("# running: {0}".format(cmd))
            os.system(cmd)
            time.sleep(2)
        elif selected_sub['type'] == "ip2tor-v1":
            cmd = "python /home/admin/config.scripts/blitz.subscriptions.ip2tor.py subscription-cancel {0}".format(
                selected_sub['id'])
            print("# running: {0}".format(cmd))
            os.system(cmd)
            time.sleep(2)
        else:
            print("# FAIL: unknown subscription type")
            time.sleep(3)

    # trigger restart of relevant services so they can pickup new environment
    print("# restarting Sphinx Relay to pickup new public url (please wait) ...")
    os.system("sudo systemctl restart sphinxrelay 2>/dev/null")
    time.sleep(8)

    # loop until no more subscriptions or user chooses CANCEL on subscription list
    my_subscriptions()


def main():
    #######################
    # SSH MENU
    #######################

    choices = list()
    choices.append(("LIST", "My Subscriptions"))
    choices.append(("NEW1", "+ IP2TOR Bridge (paid)"))
    choices.append(("NEW2", "+ LetsEncrypt HTTPS Domain (free)"))

    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("RaspiBlitz Subscriptions")
    code, tag = d.menu(
        "\nCheck existing subscriptions or create new:",
        choices=choices, width=50, height=10, title="Subscription Management")

    # if user chosses CANCEL
    if code != d.OK:
        sys.exit(0)

    #######################
    # MANAGE SUBSCRIPTIONS
    #######################

    if tag == "LIST":
        my_subscriptions()
        sys.exit(0)

    ###############################
    # NEW LETSENCRYPT HTTPS DOMAIN
    ###############################

    if tag == "NEW2":
        # run creating a new IP2TOR subscription
        os.system("clear")
        cmd = "python /home/admin/config.scripts/blitz.subscriptions.letsencrypt.py create-ssh-dialog"
        print("# running: {0}".format(cmd))
        os.system(cmd)
        sys.exit(0)

    ###############################
    # NEW IP2TOR BRIDGE
    ###############################

    if tag == "NEW1":

        # check if Blitz is running behind Tor
        cfg.reload()
        if not cfg.run_behind_tor.value:
            Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
    The IP2TOR service just makes sense if you run
    your RaspiBlitz behind Tor.
            ''', title="Info")
            sys.exit(1)

        os.system("clear")
        print("please wait ..")

        # check for which standard services already a active bridge exists
        lnd_rest_api = False
        lnd_grpc_api = False
        lnbits = False
        btcpay = False
        sphinx = False
        try:
            if os.path.isfile(SUBSCRIPTIONS_FILE):
                os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
                subs = toml.load(SUBSCRIPTIONS_FILE)
                for sub in subs['subscriptions_ip2tor']:
                    if not sub['active']:
                        continue
                    if sub['active'] and sub['name'] == SERVICE_LND_REST_API:
                        lnd_rest_api = True
                    if sub['active'] and sub['name'] == SERVICE_LND_GRPC_API:
                        lnd_grpc_api = True
                    if sub['active'] and sub['name'] == SERVICE_LNBITS:
                        lnbits = True
                    if sub['active'] and sub['name'] == SERVICE_BTCPAY:
                        btcpay = True
                    if sub['active'] and sub['name'] == SERVICE_SPHINX:
                        sphinx = True
        except Exception as e:
            print(e)

        # check if BTCPayServer is installed
        btc_pay_server = False
        status_data = subprocess.run(['/home/admin/config.scripts/bonus.btcpayserver.sh', 'status'],
                                     stdout=subprocess.PIPE).stdout.decode('utf-8').strip()
        if status_data.find("installed=1") > -1:
            btc_pay_server = True

        # check if Sphinx-Relay is installed
        sphinx_relay = False
        status_data = subprocess.run(['/home/admin/config.scripts/bonus.sphinxrelay.sh', 'status'],
                                     stdout=subprocess.PIPE).stdout.decode('utf-8').strip()
        if status_data.find("installed=1") > -1:
            sphinx_relay = True

        # ask user for which RaspiBlitz service the bridge should be used
        choices = list()
        choices.append(("REST", "LND REST API {0}".format("--> ALREADY BRIDGED" if lnd_rest_api else "")))
        choices.append(("GRPC", "LND gRPC API {0}".format("--> ALREADY BRIDGED" if lnd_grpc_api else "")))
        if cfg.lnbits:
            choices.append(("LNBITS", "LNbits Webinterface {0}".format("--> ALREADY BRIDGED" if lnbits else "")))
        if btc_pay_server:
            choices.append(("BTCPAY", "BTCPay Server Webinterface {0}".format("--> ALREADY BRIDGED" if btcpay else "")))
        if sphinx_relay:
            choices.append(("SPHINX", "Sphinx Relay  {0}".format("--> ALREADY BRIDGED" if sphinx else "")))
        choices.append(("SELF", "Create a custom IP2TOR Bridge"))

        d = Dialog(dialog="dialog", autowidgetsize=True)
        d.set_background_title("RaspiBlitz Subscriptions")
        code, tag = d.menu(
            "\nChoose RaspiBlitz Service to create Bridge for:",
            choices=choices, width=60, height=10, title="Select Service")

        # if user chosses CANCEL
        if code != d.OK:
            sys.exit(0)

        service_name = None
        tor_address = None
        tor_port = None
        if tag == "REST":
            # get Tor address for REST
            service_name = SERVICE_LND_REST_API
            tor_address = subprocess.run(['sudo', 'cat', '${SERVICES_DATA_DIR}/lndrest8080/hostname'],
                                         stdout=subprocess.PIPE).stdout.decode('utf-8').strip()
            tor_port = 8080
        if tag == "GRPC":
            # get Tor address for GRPC
            service_name = SERVICE_LND_GRPC_API
            tor_address = subprocess.run(['sudo', 'cat', '${SERVICES_DATA_DIR}/lndrpc10009/hostname'],
                                         stdout=subprocess.PIPE).stdout.decode('utf-8').strip()
            tor_port = 10009
        if tag == "LNBITS":
            # get Tor address for LNBits
            service_name = SERVICE_LNBITS
            tor_address = subprocess.run(['sudo', 'cat', '${SERVICES_DATA_DIR}/lnbits/hostname'],
                                         stdout=subprocess.PIPE).stdout.decode('utf-8').strip()
            tor_port = 443
        if tag == "BTCPAY":
            # get Tor address for BTCPAY
            service_name = SERVICE_BTCPAY
            tor_address = subprocess.run(['sudo', 'cat', '${SERVICES_DATA_DIR}/btcpay/hostname'],
                                         stdout=subprocess.PIPE).stdout.decode('utf-8').strip()
            tor_port = 443
        if tag == "SPHINX":
            # get Tor address for SPHINX
            service_name = SERVICE_SPHINX
            tor_address = subprocess.run(['sudo', 'cat', '${SERVICES_DATA_DIR}/sphinxrelay/hostname'],
                                         stdout=subprocess.PIPE).stdout.decode('utf-8').strip()
            tor_port = 443
        if tag == "SELF":
            service_name = "CUSTOM"
            try:
                # get custom Tor address
                code, text = d.inputbox(
                    "Enter Tor Onion-Address:",
                    height=10, width=60, init="",
                    title="IP2TOR Bridge Target")
                text = text.strip()
                os.system("clear")
                if code != d.OK:
                    sys.exit(0)
                if len(text) == 0:
                    sys.exit(0)
                if text.find('.onion') < 0 or text.find(' ') > 0:
                    print("Not a Tor Onion Address")
                    time.sleep(3)
                    sys.exit(0)
                tor_address = text
                # get custom Tor port
                code, text = d.inputbox(
                    "Enter Tor Port Number:",
                    height=10, width=40, init="80",
                    title="IP2TOR Bridge Target")
                text = text.strip()
                os.system("clear")
                if code != d.OK:
                    sys.exit(0)
                if len(text) == 0:
                    sys.exit(0)
                tor_port = int(text)
            except Exception as e:
                print(e)
                time.sleep(3)
                sys.exit(1)

        # run creating a new IP2TOR subscription
        os.system("clear")
        cmd = "python /home/admin/config.scripts/blitz.subscriptions.ip2tor.py create-ssh-dialog {0} {1} {2}".format(
            service_name, tor_address, tor_port)
        print("# running: {0}".format(cmd))
        os.system(cmd)

        # action after possibly new created bride
        if service_name == SERVICE_SPHINX:
            print("# restarting Sphinx Relay to pickup new public url (please wait) ...")
            os.system("sudo systemctl restart sphinxrelay")
            time.sleep(8)

        sys.exit(0)

if __name__ == '__main__':
    main()
