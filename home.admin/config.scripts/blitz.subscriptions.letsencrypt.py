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
from blitzpy import RaspiBlitzConfig,BlitzError

#####################
# SCRIPT INFO
#####################

# - this subscription does not require any payments
# - the recurring part is managed by the lets encrypt ACME script

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# manage letsencrypt HTTPS certificates for raspiblitz")
    print("# blitz.subscriptions.letsencrypt.py create-ssh-dialog")
    print("# blitz.subscriptions.letsencrypt.py subscriptions-list")
    print("# blitz.subscriptions.letsencrypt.py subscription-new <dyndns|ip> <duckdns> <id> <token> [ip|tor|ip&tor]")
    print("# blitz.subscriptions.letsencrypt.py subscription-detail <id>")
    print("# blitz.subscriptions.letsencrypt.py subscription-cancel <id>")
    print("# blitz.subscriptions.letsencrypt.py domain-by-ip <ip>")
    sys.exit(1)

# constants for standard services
SERVICE_LND_REST_API = "LND-REST-API"
SERVICE_LND_GRPC_API = "LND-GRPC-API"
SERVICE_LNBITS = "LNBITS"
SERVICE_BTCPAY = "BTCPAY"

#####################
# BASIC SETTINGS
#####################

SUBSCRIPTIONS_FILE = "/mnt/hdd/app-data/subscriptions/subscriptions.toml"

cfg = RaspiBlitzConfig()
cfg.reload()

# todo: make sure that also ACME script uses TOR if activated
session = requests.session()
if cfg.run_behind_tor.value:
    session.proxies = {'http': 'socks5h://127.0.0.1:9050', 'https': 'socks5h://127.0.0.1:9050'}


#####################
# HELPER CLASSES
#####################

# ToDo(frennkie) replace this with updated BlitzError from blitzpy
class BlitzError(Exception):
    def __init__(self, errorShort, errorLong="", errorException=None):
        self.errorShort = str(errorShort)
        self.errorLong = str(errorLong)
        self.errorException = errorException


#####################
# HELPER FUNCTIONS
#####################

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

############################
# API Calls to DNS Services
############################

def duckdns_update(domain, token, ip):
    print("# duckDNS update IP API call for {0}".format(domain))

    # make HTTP request
    url = "https://www.duckdns.org/update?domains={0}&token={1}&ip={2}".format(domain.split('.')[0], token, ip)
    print("# calling URL: {0}".format(url))
    try:
        response = session.get(url)
        if response.status_code != 200:
            raise BlitzError("failed HTTP code", str(response.status_code))
        print("# response-code: {0}".format(response.status_code))
    except Exception as e:
        raise BlitzError("failed HTTP request", url, e)

    return response.content

def dynu_update(domain, token, ip):

    print("# dynu update IP API call for {0}".format(domain))

    # split token to oAuth username and password
    try:
        print("Splitting oAuth user & pass:")
        username = token.split(":")[0]
        password = token.split(":")[1]
        print(username)
        print(password)
    except Exception as e:
        raise BlitzError("failed to split token", token, e)

    # get API token from oAuth data
    url="https://api.dynu.com/v2/oauth2/token"
    headers = {'accept': 'application/json'}
    print("# calling URL: {0}".format(url))
    try:
        response = session.get(url, headers=headers, auth=(username, password))
        if response.status_code != 200:
            raise BlitzError("failed HTTP request", url + str(response.status_code))
        print("# response-code: {0}".format(response.status_code))
    except Exception as e:
        raise BlitzError("failed HTTP request", url, e)
    
    # parse data
    apitoken=""
    try:
        print(response.content)
        data = json.loads(response.content)
        apitoken = data["access_token"];
    except Exception as e:
        raise BlitzError("failed parsing data", response.content, e)
    if len(apitoken) == 0:
        raise BlitzError("access_token not found", response.content)

    # get id for domain
    url = "https://api.dynu.com/v2/dns"
    headers = {'accept': 'application/json', 'API-Key': apitoken}
    print("# calling URL: {0}".format(url))
    try:
        response = session.get(url, headers=headers)
        if response.status_code != 200:
            raise BlitzError("failed HTTP request", url + str(response.status_code))
        print("# response-code: {0}".format(response.status_code))
    except Exception as e:
        raise BlitzError("failed HTTP request", url, e)

    # parse data
    id_for_domain=""
    try:
        print(response.content)
        data = json.loads(response.content)
        for entry in data["domains"]:   
            print(entry)
            if entry['name'] is domain:
                id_for_domain = entry["id"]
                break
    except Exception as e:
        raise BlitzError("failed parsing data", response.content, e)
    if len(id_for_domain) == 0:
        raise BlitzError("domain not found", response.content)

    # update ip address
    url = "https://api.dynu.com/v2/dns/{1}".format(id_for_domain)
    headers = {'accept': 'application/json', 'API-Key': apitoken}
    data = {"name": domain, "ipv4Address": ip, "ttl": 90 }
    print("# calling URL: {0}".format(url))
    print("# post data: {0}".format(data))
    try:
        response = session.post(url, headers=headers, data=data)
        if response.status_code != 200:
            raise BlitzError("failed HTTP request", url + str(response.status_code))
        print("# response-code: {0}".format(response.status_code))
    except Exception as e:
        raise BlitzError("failed HTTP request", url, e)

    return response.content    

#####################
# PROCESS FUNCTIONS
#####################

def subscriptions_new(ip, dnsservice, domain, token, target):
    # domain needs to be the full domain name
    if domain.find(".") == -1:
        raise BlitzError("not a fully qualified domain name", domain)

    # check if domain already exists
    if len(get_subscription(domain)) > 0:
        raise BlitzError("domain already exists", domain)

    # make sure lets encrypt client is installed
    os.system("/home/admin/config.scripts/bonus.letsencrypt.sh on")

    # dyndns
    real_ip = ip
    if ip == "dyndns":
        update_url = ""
        if dnsservice == "duckdns":
            update_url = "https://www.duckdns.org/update?domains={0}&token={1}".format(domain, token, ip)
        subprocess.run(['/home/admin/config.scripts/internet.dyndomain.sh', 'on', domain, update_url],
                       stdout=subprocess.PIPE).stdout.decode('utf-8').strip()
        real_ip = cfg.public_ip
        if dnsservice == "dynu":
            Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
Sorry .. dynu.com cannot be used for updating dyndns yet with RaspiBlitz.
        ''', title="Not implemented yet.")
            sys.exit(0)

    # update DNS with actual IP
    if dnsservice == "duckdns":
        print("# dnsservice=duckdns --> update {0}".format(domain))
        duckdns_update(domain, token, real_ip)
    if dnsservice == "dynu":
        print("# dnsservice=dynu --> update {0}".format(domain))
        dynu_update(domain, token, real_ip)

    # create subscription data for storage
    subscription = dict()
    subscription['type'] = "letsencrypt-v1"
    subscription['id'] = domain
    subscription['active'] = True
    subscription['name'] = "{0} for {1}".format(dnsservice, domain)
    subscription['dnsservice_type'] = dnsservice
    subscription['dnsservice_token'] = token
    subscription['ip'] = ip
    subscription['target'] = target
    subscription['description'] = "For {0}".format(target)
    subscription['time_created'] = str(datetime.now().strftime("%Y-%m-%d %H:%M"))
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
        if "subscriptions_letsencrypt" not in subscriptions:
            subscriptions['subscriptions_letsencrypt'] = []
        subscriptions['subscriptions_letsencrypt'].append(subscription)
        with open(SUBSCRIPTIONS_FILE, 'w') as writer:
            writer.write(toml.dumps(subscriptions))
            writer.close()

    except Exception as e:
        eprint(e)
        raise BlitzError("fail on subscription storage", str(subscription), e)

    # run the ACME script
    print("# Running letsencrypt ACME script ...")
    acme_result = subprocess.Popen(
        ["/home/admin/config.scripts/bonus.letsencrypt.sh", "issue-cert", dnsservice, domain, token, target],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf8')
    out, err = acme_result.communicate()
    eprint(str(out))
    eprint(str(err))
    if out.find("error=") > -1:
        time.sleep(6)
        raise BlitzError("letsancrypt acme failed", out)

    print("# OK - LETSENCRYPT DOMAIN IS READY")
    return subscription


def subscriptions_cancel(s_id):
    os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
    subs = toml.load(SUBSCRIPTIONS_FILE)
    new_list = []
    removed_cert = None
    for idx, sub in enumerate(subs['subscriptions_letsencrypt']):
        if sub['id'] != s_id:
            new_list.append(sub)
        else:
            removed_cert = sub
    subs['subscriptions_letsencrypt'] = new_list

    # run the ACME script to remove cert
    if removed_cert:
        acme_result = subprocess.Popen(
            ["/home/admin/config.scripts/bonus.letsencrypt.sh", "remove-cert", removed_cert['id'],
             removed_cert['target']], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf8')
        out, err = acme_result.communicate()
        if out.find("error=") > -1:
            time.sleep(6)
            raise BlitzError("letsencrypt acme failed", out)

    # persist change
    with open(SUBSCRIPTIONS_FILE, 'w') as writer:
        writer.write(toml.dumps(subs))
        writer.close()

    print(json.dumps(subs, indent=2))

    # todo: deinstall letsencrypt if this was last subscription


def get_subscription(subscription_id):
    try:

        if Path(SUBSCRIPTIONS_FILE).is_file():
            os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
            subs = toml.load(SUBSCRIPTIONS_FILE)
        else:
            return []
        if "subscriptions_letsencrypt" not in subs:
            return []
        for idx, sub in enumerate(subs['subscriptions_letsencrypt']):
            if sub['id'] == subscription_id:
                return sub
        return []

    except Exception as e:
        return []


def get_domain_by_ip(ip):
    # does subscriptin file exists
    if Path(SUBSCRIPTIONS_FILE).is_file():
        os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
        subs = toml.load(SUBSCRIPTIONS_FILE)
    else:
        raise BlitzError("no match")
    # section with letsencrypt subs exists
    if "subscriptions_letsencrypt" not in subs:
        raise BlitzError("no match")
    # go thru subscription and check of a match
    for idx, sub in enumerate(subs['subscriptions_letsencrypt']):
        # if IP is a direct match
        if sub['ip'] == ip:
            return sub['id']
        # if IP is a dynamicIP - check with the publicIP from the config
        if sub['ip'] == "dyndns":
            if cfg.public_ip == ip:
                return sub['id']
    raise BlitzError("no match")


def menu_make_subscription():
    # late imports - so that rest of script can run also if dependency is not available
    from dialog import Dialog

    # todo ... copy parts of IP2TOR dialogs

    ############################
    # PHASE 1: Choose DNS service

    # ask user for which RaspiBlitz service the bridge should be used
    choices = []
    choices.append(("DUCKDNS", "Use duckdns.org"))
    choices.append(("DYNU", "Use dynu.com"))

    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("LetsEncrypt Subscription")
    code, tag = d.menu(
        "\nChoose a free DNS service to work with:",
        choices=choices, width=60, height=10, title="Select Service")

    # if user chosses CANCEL
    if code != d.OK:
        sys.exit(0)

    # get the fixed dnsservice string
    dnsservice = tag.lower()

    ############################
    # PHASE 2: Enter ID & API token for service

    if dnsservice == "duckdns":

        # show basic info on duck dns
        Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
If you havent already go to https://duckdns.org
- consider using the TOR browser
- create an account or login
- make sure you have a subdomain added
        ''', title="DuckDNS Account needed")

        # enter the subdomain
        code, text = d.inputbox(
            "Enter your duckDNS subdomain:",
            height=10, width=40, init="",
            title="DuckDNS Domain")
        subdomain = text.strip()
        subdomain = subdomain.split(' ')[0]
        subdomain = subdomain.split('.')[0]
        domain = "{0}.duckdns.org".format(subdomain)
        os.system("clear")

        # check for valid input
        if len(subdomain) == 0:
            Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
This looks not like a valid subdomain.
        ''', title="Unvalid Input")
            sys.exit(0)

        # enter the token
        code, text = d.inputbox(
            "Enter the duckDNS token of your account:",
            height=10, width=50, init="",
            title="DuckDNS Token")
        token = text.strip()
        token = token.split(' ')[0]

        # check for valid input
        try:
            token.index("-")
        except Exception as e:
            token = ""
        if len(token) < 20:
            Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
This looks not like a valid token.
        ''', title="Invalid Input")
            sys.exit(0)

    if dnsservice == "dynu":

        # show basic info on duck dns
        Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
If you havent already go to https://dynu.com
- consider using the TOR browser
- create an account or login
- DDNS Services -> create new
        ''', title="dynu.com Account needed")
        
        # enter the subdomain
        code, text = d.inputbox(
            "Enter the complete DDNS name:",
            height=10, width=40, init="",
            title="dynu.com DDNS Domain")
        domain = text.strip()
        if len(domain) < 6:
            Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
This looks not like a valid DDNS.
        ''', title="Invalid Input")
            sys.exit(0)
        os.system("clear")

        # show basic info on duck dns
        Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
Continue in your dynu.com account: 
- open 'Control Panel' > 'API Credentials'
- see listed 'OAuth2' ClientID & Secret
- click glasses icon to view values
        ''', title="dynu.com API Key needed")

        # enter the CLIENTID
        code, text = d.inputbox(
            "Enter the OAuth2 CLIENTID:",
            height=10, width=50, init="",
            title="dynu.com OAuth2 ClientID")
        clientid = text.strip()
        clientid = clientid.split(' ')[0]
        if len(clientid) < 20 or len(clientid.split('-'))<2: 
            Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
This looks not like valid ClientID.
        ''', title="Invalid Input")
            sys.exit(0)

        # enter the SECRET
        code, text = d.inputbox(
            "Enter the OAuth2 SECRET:",
            height=10, width=50, init="",
            title="dynu.com OAuth2 SECRET")
        secret = text.strip()
        secret = secret.split(' ')[0]
        if len(secret) < 10:
            Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
This looks not like valid.
        ''', title="Invalid Input")
            sys.exit(0)

        token = "{}:{}".format(clientid, secret)

    else:
        os.system("clear")
        print("Not supported yet: {0}".format(dnsservice))
        time.sleep(4)
        sys.exit(0)

        ############################
    # PHASE 3: Choose what kind of IP: dynDNS, IP2TOR, fixedIP

    # ask user for which RaspiBlitz service the bridge should be used
    choices = list()
    choices.append(("IP2TOR", "HTTPS for a IP2TOR Bridge"))
    choices.append(("DYNDNS", "HTTPS for {0} DynamicIP DNS".format(dnsservice.upper())))
    choices.append(("STATIC", "HTTPS for a static IP"))

    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("LetsEncrypt Subscription")
    code, tag = d.menu(
        "\nChoose the kind of IP you want to use:",
        choices=choices, width=60, height=10, title="Select Service")

    # if user chooses CANCEL
    os.system("clear")
    if code != d.OK:
        sys.exit(0)

    # default target are the nginx ip ports
    target = "ip"
    ip = ""

    if tag == "IP2TOR":

        # get all active IP2TOR subscriptions (just in case)
        ip2tor_subs = []
        if Path(SUBSCRIPTIONS_FILE).is_file():
            os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
            subs = toml.load(SUBSCRIPTIONS_FILE)
            for idx, sub in enumerate(subs['subscriptions_ip2tor']):
                if sub['active']:
                    ip2tor_subs.append(sub)

        # when user has no IP2TOR subs yet
        if len(ip2tor_subs) == 0:
            Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
You have no active IP2TOR subscriptions.
Create one first and try again.
        ''', title="No IP2TOR available")
            sys.exit(0)

            # let user select a IP2TOR subscription
        choices = []
        for idx, sub in enumerate(ip2tor_subs):
            choices.append(("{0}".format(idx), "IP2TOR {0} {1}:{2}".format(sub['name'], sub['ip'], sub['port'])))

        d = Dialog(dialog="dialog", autowidgetsize=True)
        d.set_background_title("LetsEncrypt Subscription")
        code, tag = d.menu(
            "\nChoose the IP2TOR subscription:",
            choices=choices, width=60, height=10, title="Select")

        # if user chosses CANCEL
        if code != d.OK:
            sys.exit(0)

        # get the slected IP2TOR bridge
        ip2tor_select = ip2tor_subs[int(tag)]
        ip = ip2tor_select["ip"]
        target = "tor"

    elif tag == "DYNDNS":

        # the subscriptioNew method will handle acrivating the dnydns part
        ip = "dyndns"

    elif tag == "STATIC":

        # enter the static IP
        code, text = d.inputbox(
            "Enter the static public IP of this RaspiBlitz:",
            height=10, width=40, init="",
            title="Static IP")
        ip = text.strip()
        ip = ip.split(' ')[0]

        # check for valid input
        try:
            ip.index(".")
        except Exception as e:
            ip = ""
        if len(ip) == 0:
            Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
This looks not like a valid IP.
        ''', title="Invalid Input")
            sys.exit(0)

    # create the letsencrypt subscription
    try:
        os.system("clear")
        subscription = subscriptions_new(ip, dnsservice, domain, token, target)

        # success dialog
        Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
OK your LetsEncrypt subscription is now ready.
Go to SUBSCRIBE > LIST to see details.
Use the correct port on {0}
to reach the service you wanted.
            '''.format(domain), title="OK LetsEncrypt Created")

    except Exception as e:

        # unknown error happened
        Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
Unknown Error happened - please report to developers:
{0}
            '''.format(str(e)), title="Exception on Subscription")
        sys.exit(1)


##################
# COMMANDS
##################

###############
# CREATE SSH DIALOG
# use for ssh shell menu
###############
def create_ssh_dialog():
    menu_make_subscription()


##########################
# SUBSCRIPTIONS NEW
# call from web interface
##########################
def subscription_new():
    # check parameters
    try:
        if len(sys.argv) <= 5:
            raise BlitzError("incorrect parameters", "")
    except Exception as e:
        handleException(e)

    ip = sys.argv[2]
    dnsservice_type = sys.argv[3]
    dnsservice_id = sys.argv[4]
    dnsservice_token = sys.argv[5]
    if len(sys.argv) <= 6:
        target = "ip&tor"
    else:
        target = sys.argv[6]

    # create the subscription
    try:
        subscription = subscriptions_new(ip, dnsservice_type, dnsservice_id, dnsservice_token, target)

        # output json ordered bridge
        print(json.dumps(subscription, indent=2))
        sys.exit()

    except Exception as e:
        handleException(e)


#######################
# SUBSCRIPTIONS LIST
#######################
def subscriptions_list():
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


#######################
# SUBSCRIPTION DETAIL
#######################

def subscription_detail():
    # check parameters
    try:
        if len(sys.argv) <= 2:
            raise BlitzError("incorrect parameters", "")
    except Exception as e:
        handleException(e)

    subscription_id = sys.argv[2]
    httpsTestport = ""
    if len(sys.argv) > 3:
        httpsTestport = sys.argv[3]
    try:
        sub = get_subscription(subscription_id)

        # use unix 'getent' to resolve DNS to IP
        dns_result = subprocess.Popen(
        ["getent", "hosts", subscription_id],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, encoding='utf8')
        out, err = dns_result.communicate()
        sub['dns_response'] = "unknown"
        if subscription_id in out:        
            sub['dns_response'] = out.split(" ")[0]
            if sub['dns_response']!=sub['ip'] and len(sub['warning'])==0:
                sub['warning'] = "Domain resolves not to target IP yet."

        # when https testport is set - check if you we get a https response
        sub['https_response'] = -1
        if len(httpsTestport) > 0:
            url = "https://{0}:{1}".format(subscription_id, httpsTestport)
            try:
                response = session.get(url)
                sub['https_response'] = response.status_code
            except Exception as e:
                sub['https_response'] = 0
            if sub['https_response']!=200 and len(sub['warning'])==0:
                sub['warning'] = "Not able to get HTTPS response."
                
        print(json.dumps(sub, indent=2))

    except Exception as e:
        handleException(e)


#######################
# DOMAIN BY IP
# to check if an ip has a domain mapping
#######################
def domain_by_ip():
    # check parameters
    try:
        if len(sys.argv) <= 2:
            raise BlitzError("incorrect parameters", "")

    except Exception as e:
        handleException(e)

    ip = sys.argv[2]
    try:

        domain = get_domain_by_ip(ip)
        print("domain='{0}'".format(domain))

    except Exception as e:
        handleException(e)


#######################
# SUBSCRIPTION CANCEL
#######################
def subscription_cancel():
    # check parameters
    try:
        if len(sys.argv) <= 2:
            raise BlitzError("incorrect parameters", "")
    except Exception as e:
        handleException(e)

    subscription_id = sys.argv[2]
    try:
        subscriptions_cancel(subscription_id)
    except Exception as e:
        handleException(e)


def main():
    if sys.argv[1] == "create-ssh-dialog":
        create_ssh_dialog()

    elif sys.argv[1] == "domain-by-ip":
        domain_by_ip()

    elif sys.argv[1] == "subscriptions-list":
        subscriptions_list()

    elif sys.argv[1] == "subscription-cancel":
        subscription_cancel()

    elif sys.argv[1] == "subscription-detail":
        subscription_detail()

    elif sys.argv[1] == "subscription-new":
        subscription_new()

    else:
        # unknown command
        print("# unknown command")


if __name__ == '__main__':
    main()
