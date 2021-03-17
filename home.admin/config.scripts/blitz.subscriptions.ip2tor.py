#!/usr/bin/python3

import codecs
import json
import math
import os
import sys
import time
from datetime import datetime
from pathlib import Path

import grpc
import requests
import toml

sys.path.append('/home/admin/raspiblitz/home.admin/BlitzPy/blitzpy')
from config import RaspiBlitzConfig
from exceptions import BlitzError

from lndlibs import rpc_pb2 as lnrpc
from lndlibs import rpc_pb2_grpc as rpcstub

#####################
# SCRIPT INFO
#####################

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# manage ip2tor subscriptions for raspiblitz")
    print("# blitz.subscriptions.ip2tor.py create-ssh-dialog servicename toraddress torport")
    print("# blitz.subscriptions.ip2tor.py shop-list shopurl")
    print("# blitz.subscriptions.ip2tor.py shop-order shopurl servicename hostid toraddress:port duration "
          "msatsFirst msatsNext [description]")
    print("# blitz.subscriptions.ip2tor.py subscriptions-list")
    print("# blitz.subscriptions.ip2tor.py subscriptions-renew secondsBeforeSuspend")
    print("# blitz.subscriptions.ip2tor.py subscription-cancel id")
    print("# blitz.subscriptions.ip2tor.py subscription-by-service servicename")
    print("# blitz.subscriptions.ip2tor.py ip-by-tor onionaddress")
    sys.exit(1)

# constants for standard services
SERVICE_LND_REST_API = "LND-REST-API"
SERVICE_LND_GRPC_API = "LND-GRPC-API"
SERVICE_LNBITS = "LNBITS"
SERVICE_BTCPAY = "BTCPAY"
SERVICE_SPHINX = "SPHINX"

#####################
# BASIC SETTINGS
#####################
session = requests.session()
if Path("/mnt/hdd/raspiblitz.conf").is_file():
    cfg = RaspiBlitzConfig()
    cfg.reload()

    if cfg.chain.value == "test":
        is_testnet = True
    else:
        is_testnet = False

    ENV = "PROD"
    DEFAULT_SHOPURL = "fulmo7x6yvgz6zs2b2ptduvzwevxmizhq23klkenslt5drxx2physlqd.onion"
    # DEFAULT_SHOPURL = "ip2tor.fulmo.org"
    LND_IP = "127.0.0.1"
    LND_ADMIN_MACAROON_PATH = "/mnt/hdd/app-data/lnd/data/chain/{0}/{1}net/admin.macaroon".format(cfg.network.value,
                                                                                                  cfg.chain.value)
    LND_TLS_PATH = "/mnt/hdd/app-data/lnd/tls.cert"
    # make sure to make requests thru TOR 127.0.0.1:9050
    session.proxies = {'http': 'socks5h://127.0.0.1:9050', 'https': 'socks5h://127.0.0.1:9050'}
    SUBSCRIPTIONS_FILE = "/mnt/hdd/app-data/subscriptions/subscriptions.toml"
else:
    ENV = "DEV"
    print("# blitz.ip2tor.py (development env)")
    DEFAULT_SHOPURL = "fulmo7x6yvgz6zs2b2ptduvzwevxmizhq23klkenslt5drxx2physlqd.onion"
    # DEFAULT_SHOPURL = "ip2tor.fulmo.org"
    LND_IP = "192.168.178.95"
    LND_ADMIN_MACAROON_PATH = "/Users/rotzoll/Downloads/RaspiBlitzCredentials/admin.macaroon"
    LND_TLS_PATH = "/Users/rotzoll/Downloads/RaspiBlitzCredentials/tls.cert"
    SUBSCRIPTIONS_FILE = "/Users/rotzoll/Downloads/RaspiBlitzCredentials/subscriptions.toml"

    is_testnet = False


#####################
# HELPER FUNCTIONS
#####################

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)


def handleException(e):
    if isinstance(e, BlitzError):
        eprint(e.details)
        eprint(e.org)
        print("error='{0}'".format(e.short))
    else:
        eprint(e)
        print("error='{0}'".format(str(e)))
    sys.exit(1)


def parseDate(datestr):
    return datetime.strptime(datestr, "%Y-%m-%dT%H:%M:%SZ")


def secondsLeft(dateObj):
    return round((dateObj - datetime.utcnow()).total_seconds())


# takes a shopurl from user input and turns it into the format needed
# also makes sure that .onion addresses run just with http not https
def normalizeShopUrl(shopurlUserInput):
    # basic checks and formats
    if len(shopurlUserInput) < 3:
        return ""
    shopurlUserInput = shopurlUserInput.lower()
    shopurlUserInput = shopurlUserInput.replace(" ", "")
    shopurlUserInput = shopurlUserInput.replace("\n", "")
    shopurlUserInput = shopurlUserInput.replace("\r", "")

    # remove protocol from the beginning (if needed)
    if shopurlUserInput.find("://") > 0:
        shopurlUserInput = shopurlUserInput[shopurlUserInput.find("://") + 3:]

    # remove all path after domain 
    if shopurlUserInput.find("/") > 0:
        shopurlUserInput = shopurlUserInput[:shopurlUserInput.find("/")]

    # add correct protocol again
    if not shopurlUserInput.startswith("http://") and not shopurlUserInput.startswith("https://"):
        if shopurlUserInput.endswith(".onion"):
            shopurlUserInput = "http://{0}".format(shopurlUserInput)
        else:
            shopurlUserInput = "https://{0}".format(shopurlUserInput)

    return shopurlUserInput


#####################
# IP2TOR API CALLS
#####################

def apiGetHosts(session, shopurl):
    print("# apiGetHosts")
    hosts = []

    # make HTTP request
    url = "{0}/api/v1/public/hosts/?is_testnet={1}".format(shopurl, int(is_testnet))
    try:
        response = session.get(url)
    except Exception as e:
        raise BlitzError("failed HTTP request", {'url': url}, e)
    if response.status_code != 200:
        raise BlitzError("failed HTTP code", {'status_code': response.status_code})

    # parse & validate data
    try:
        jData = json.loads(response.content)
    except Exception as e:
        raise BlitzError("failed JSON parsing", {'content': response.content}, e)
    if not isinstance(jData, list):
        raise BlitzError("hosts not list", {'content': response.content})
    for idx, hostEntry in enumerate(jData):
        try:
            # ignore if not offering tor bridge
            if not hostEntry['offers_tor_bridges']:
                continue
            # ignore if duration is less than an hour
            if hostEntry['tor_bridge_duration'] < 3600:
                continue
            # add duration per hour value 
            hostEntry['tor_bridge_duration_hours'] = math.floor(hostEntry['tor_bridge_duration'] / 3600)
            # ignore if prices are negative or below one sat (maybe msats later)
            if hostEntry['tor_bridge_price_initial'] < 1000:
                continue
            if hostEntry['tor_bridge_price_extension'] < 1000:
                continue
            # add price in sats
            hostEntry['tor_bridge_price_initial_sats'] = math.ceil(hostEntry['tor_bridge_price_initial'] / 1000)
            hostEntry['tor_bridge_price_extension_sats'] = math.ceil(hostEntry['tor_bridge_price_extension'] / 1000)
            # ignore name is less then 3 chars
            if len(hostEntry['name']) < 3:
                continue
            # ignore id with zero value
            if len(hostEntry['id']) < 1:
                continue
            # shorten names to 20 chars max
            hostEntry['name'] = hostEntry['name'][:20]
        except Exception as e:
            raise BlitzError("failed host entry pasring", hostEntry, e)

        hosts.append(hostEntry)

    print("# found {0} valid torbridge hosts".format(len(hosts)))
    return hosts


def apiPlaceOrderNew(session, shopurl, hostid, toraddressWithPort):
    print("# apiPlaceOrderNew")

    url = "{0}/api/v1/public/order/".format(shopurl)
    postData = {
        'product': "tor_bridge",
        'host_id': hostid,
        'tos_accepted': True,
        'comment': 'RaspiBlitz',
        'target': toraddressWithPort,
        'public_key': ''
    }
    try:
        response = session.post(url, data=postData)
    except Exception as e:
        raise BlitzError("failed HTTP request", {'url': url}, e)
    if response.status_code == 420:
        raise BlitzError("forwarding this address was rejected", {'status_code': response.status_code})
    if response.status_code != 201:
        raise BlitzError("failed HTTP code", {'status_code': response.status_code})

    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['id']) == 0:
            print("error='MISSING ID'")
            return
    except Exception as e:
        raise BlitzError("failed JSON parsing", {'status_code': response.status_code}, e)

    return jData['id']


def apiPlaceOrderExtension(session, shopurl, bridgeid):
    print("# apiPlaceOrderExtension")

    url = "{0}/api/v1/public/tor_bridges/{1}/extend/".format(shopurl, bridgeid)
    try:
        response = session.post(url)
    except Exception as e:
        raise BlitzError("failed HTTP request", {'url': url}, e)
    if response.status_code == 420:
        raise BlitzError("forwarding this address was rejected", {'status_code': response.status_code})
    if response.status_code != 200 and response.status_code != 201:
        raise BlitzError("failed HTTP code", {'status_code': response.status_code})

    # parse & validate data
    print("# parse")
    try:
        jData = json.loads(response.content)
        if len(jData['po_id']) == 0:
            print("error='MISSING ID'")
            return
    except Exception as e:
        raise BlitzError("failed JSON parsing", {'content': response.content}, e)

    return jData['po_id']


def apiGetOrder(session, shopurl, orderid) -> dict:
    print("# apiGetOrder")

    # make HTTP request
    url = "{0}/api/v1/public/pos/{1}/".format(shopurl, orderid)
    try:
        response = session.get(url)
    except Exception as e:
        raise BlitzError("failed HTTP request", {'url': url}, e)
    if response.status_code != 200:
        raise BlitzError("failed HTTP code", {'status_code': response.status_code})

    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['item_details']) == 0:
            raise BlitzError("missing item", {'content': response.content})
        if len(jData['ln_invoices']) > 1:
            raise BlitzError("more than one invoice", {'content': response.content})
    except Exception as e:
        raise BlitzError("failed JSON parsing", {'content': response.content}, e)

    return jData


def apiGetBridgeStatus(session, shopurl, bridgeid):
    print("# apiGetBridgeStatus")

    # make HTTP request
    url = "{0}/api/v1/public/tor_bridges/{1}/".format(shopurl, bridgeid)
    try:
        response = session.get(url)
    except Exception as e:
        raise BlitzError("failed HTTP request", {'url': url}, e)
    if response.status_code != 200:
        raise BlitzError("failed HTTP code", {'status_code': response.status_code})
    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['id']) == 0:
            raise BlitzError("missing id", {'content': response.content})
    except Exception as e:
        raise BlitzError("failed JSON parsing", {'content': response.content}, e)

    return jData


#####################
# LND API CALLS
#####################

def lndDecodeInvoice(lnInvoiceString):
    try:
        # call LND GRPC API
        macaroon = codecs.encode(open(LND_ADMIN_MACAROON_PATH, 'rb').read(), 'hex')
        os.environ['GRPC_SSL_CIPHER_SUITES'] = 'HIGH+ECDSA'
        cert = open(LND_TLS_PATH, 'rb').read()
        ssl_creds = grpc.ssl_channel_credentials(cert)
        channel = grpc.secure_channel("{0}:10009".format(LND_IP), ssl_creds)
        stub = rpcstub.LightningStub(channel)
        request = lnrpc.PayReqString(
            pay_req=lnInvoiceString,
        )
        response = stub.DecodePayReq(request, metadata=[('macaroon', macaroon)])

        # validate results
        if response.num_msat <= 0:
            raise BlitzError("zero invoice not allowed", {'invoice': lnInvoiceString})

    except Exception as e:
        raise BlitzError("failed LND invoice decoding", {'invoice': lnInvoiceString}, e)

    return response


def lndPayInvoice(lnInvoiceString):
    try:
        # call LND GRPC API
        macaroon = codecs.encode(open(LND_ADMIN_MACAROON_PATH, 'rb').read(), 'hex')
        os.environ['GRPC_SSL_CIPHER_SUITES'] = 'HIGH+ECDSA'
        cert = open(LND_TLS_PATH, 'rb').read()
        ssl_creds = grpc.ssl_channel_credentials(cert)
        channel = grpc.secure_channel("{0}:10009".format(LND_IP), ssl_creds)
        stub = rpcstub.LightningStub(channel)
        request = lnrpc.SendRequest(
            payment_request=lnInvoiceString,
        )
        response = stub.SendPaymentSync(request, metadata=[('macaroon', macaroon)])

        # validate results
        if len(response.payment_error) > 0:
            raise BlitzError(response.payment_error, {'invoice': lnInvoiceString})

    except Exception as e:
        raise BlitzError("payment failed", {'invoice': lnInvoiceString}, e)

    return response


#####################
# PROCESS FUNCTIONS
#####################

def shopList(shopUrl):
    print("#### Getting available options from shop ...")
    shopUrl = normalizeShopUrl(shopUrl)
    return apiGetHosts(session, shopUrl)


def shopOrder(shopUrl, hostid, servicename, torTarget, duration, msatsFirst, msatsNext, description=""):
    print("#### Placeing order ...")
    shopUrl = normalizeShopUrl(shopUrl)
    orderid = apiPlaceOrderNew(session, shopUrl, hostid, torTarget)

    print("#### Waiting until invoice is available ...")
    loopCount = 0
    while True:
        time.sleep(2)
        loopCount += 1
        print("# Loop {0}".format(loopCount))
        order = apiGetOrder(session, shopUrl, orderid)
        if order['status'] == "R":
            raise BlitzError("Subscription Rejected", order)
        if len(order['ln_invoices']) > 0 and order['ln_invoices'][0]['payment_request'] is not None:
            break
        if loopCount > 60:
            raise BlitzError("timeout on getting invoice", order)

    # get data from now complete order
    paymentRequestStr = order['ln_invoices'][0]['payment_request']
    bridge_id = order['item_details'][0]['product']['id']
    bridge_ip = order['item_details'][0]['product']['host']['ip']
    bridge_port = order['item_details'][0]['product']['port']

    print("#### Decoding invoice and checking ..)")
    print("# invoice: {0}".format(paymentRequestStr))
    paymentRequestDecoded = lndDecodeInvoice(paymentRequestStr)
    if paymentRequestDecoded is None: sys.exit()
    print("# amount as advertised: {0} milliSats".format(msatsFirst))
    print("# amount in invoice is: {0} milliSats".format(paymentRequestDecoded.num_msat))
    if int(msatsFirst) < int(paymentRequestDecoded.num_msat):
        raise BlitzError("invoice bigger amount than advertised",
                         "advertised({0}) invoice({1})".format(msatsFirst, paymentRequestDecoded.num_msat))

    print("#### Paying invoice ...")
    payedInvoice = lndPayInvoice(paymentRequestStr)
    print('# OK PAYMENT SENT')

    print("#### Waiting until bridge is ready ...")
    loopCount = 0
    while True:
        time.sleep(3)
        loopCount += 1
        print("## Loop {0}".format(loopCount))
        bridge = apiGetBridgeStatus(session, shopUrl, bridge_id)
        if bridge['status'] == "A":
            break
        if bridge['status'] == "R":
            break
        if loopCount > 120:
            raise BlitzError("timeout bridge not getting ready", bridge)

    print("#### Check if port is valid ...")
    try:
        bridge_port = int(bridge['port'])
    except KeyError:
        raise BlitzError("invalid port (key not found)", bridge)
    except ValueError:
        raise BlitzError("invalid port (not a number)", bridge)

    print("#### Check if duration delivered is as advertised ...")
    contract_breached = False
    warning_text = ""
    secondsDelivered = secondsLeft(parseDate(bridge['suspend_after']))
    print("# delivered({0}) promised({1})".format(secondsDelivered, duration))
    if (secondsDelivered + 600) < int(duration):
        contract_breached = True
        warning_text = "delivered duration shorter than advertised"
    if bridge['status'] == "R":
        contract_breached = True
        try:
            warningTXT = "rejected: {0}".format(bridge['message'])
        except Exception as e:
            warningTXT = "rejected: n/a"

    # create subscription data for storage
    subscription = dict()
    subscription['type'] = "ip2tor-v1"
    subscription['id'] = bridge['id']
    subscription['name'] = servicename
    subscription['shop'] = shopUrl
    subscription['active'] = not contract_breached
    subscription['ip'] = bridge_ip
    subscription['port'] = bridge_port
    subscription['duration'] = int(duration)
    subscription['price_initial'] = int(msatsFirst)
    subscription['price_extension'] = int(msatsNext)
    subscription['price_total'] = int(paymentRequestDecoded.num_msat)
    subscription['time_created'] = str(datetime.now().strftime("%Y-%m-%d %H:%M"))
    subscription['time_lastupdate'] = str(datetime.now().strftime("%Y-%m-%d %H:%M"))
    subscription['suspend_after'] = bridge['suspend_after']
    subscription['description'] = str(description)
    subscription['contract_breached'] = contract_breached
    subscription['warning'] = warning_text
    subscription['tor'] = torTarget

    # load, add and store subscriptions
    try:
        os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
        if Path(SUBSCRIPTIONS_FILE).is_file():
            print("# load toml file")
            subscriptions = toml.load(SUBSCRIPTIONS_FILE)
        else:
            print("# new toml file")
            subscriptions = {}
        if "subscriptions_ip2tor" not in subscriptions:
            subscriptions['subscriptions_ip2tor'] = []
        subscriptions['subscriptions_ip2tor'].append(subscription)
        subscriptions['shop_ip2tor'] = shopUrl
        with open(SUBSCRIPTIONS_FILE, 'w') as writer:
            writer.write(toml.dumps(subscriptions))
            writer.close()

    except Exception as e:
        eprint(e)
        raise BlitzError("fail on subscription storage", subscription, e)

    print("# OK - BRIDGE READY: {0}:{1} -> {2}".format(bridge_ip, bridge_port, torTarget))
    return subscription


def subscriptionExtend(shopUrl, bridgeid, durationAdvertised, msatsNext, bridge_suspendafter):
    warningTXT = ""
    contract_breached = False

    print("#### Placing extension order ...")
    shopUrl = normalizeShopUrl(shopUrl)
    orderid = apiPlaceOrderExtension(session, shopUrl, bridgeid)

    print("#### Waiting until invoice is available ...")
    loopCount = 0
    while True:
        time.sleep(2)
        loopCount += 1
        print("## Loop {0}".format(loopCount))
        order = apiGetOrder(session, shopUrl, orderid)
        if len(order['ln_invoices']) > 0 and order['ln_invoices'][0]['payment_request'] is not None:
            break
        if loopCount > 120:
            raise BlitzError("timeout on getting invoice", order)

    paymentRequestStr = order['ln_invoices'][0]['payment_request']

    print("#### Decoding invoice and checking ..)")
    print("# invoice: {0}".format(paymentRequestStr))
    paymentRequestDecoded = lndDecodeInvoice(paymentRequestStr)
    if paymentRequestDecoded is None: sys.exit()
    print("# amount as advertised: {0} milliSats".format(msatsNext))
    print("# amount in invoice is: {0} milliSats".format(paymentRequestDecoded.num_msat))
    if int(msatsNext) < int(paymentRequestDecoded.num_msat):
        raise BlitzError("invoice bigger amount than advertised",
                         "advertised({0}) invoice({1})".format(msatsNext, paymentRequestDecoded.num_msat))

    print("#### Paying invoice ...")
    payedInvoice = lndPayInvoice(paymentRequestStr)

    print("#### Check if bridge was extended ...")
    bridge = None
    loopCount = 0
    while True:
        time.sleep(3)
        loopCount += 1
        print("## Loop {0}".format(loopCount))
        try:
            bridge = apiGetBridgeStatus(session, shopUrl, bridgeid)
            if bridge['status'] == "R":
                contract_breached = True
                try:
                    warningTXT = "rejected: {0}".format(bridge['message'])
                except Exception as e:
                    warningTXT = "rejected: n/a"
                break
            if bridge['suspend_after'] != bridge_suspendafter:
                break
        except Exception as e:
            eprint(e)
            print("# EXCEPTION on apiGetBridgeStatus")
        if loopCount > 240:
            warningTXT = "timeout on last payed extension"
            contract_breached = True
            break

    if bridge and not contract_breached:
        print("#### Check if extension duration is as advertised ...")
        secondsLeftOld = secondsLeft(parseDate(bridge_suspendafter))
        secondsLeftNew = secondsLeft(parseDate(bridge['suspend_after']))
        secondsExtended = secondsLeftNew - secondsLeftOld
        print("# secondsExtended({0}) promised({1})".format(secondsExtended, durationAdvertised))
        if secondsExtended < int(durationAdvertised):
            contract_breached = True
            warningTXT = "delivered duration shorter than advertised"

    # load, update and store subscriptions
    try:
        print("# load toml file")
        os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
        subscriptions = toml.load(SUBSCRIPTIONS_FILE)
        for idx, subscription in enumerate(subscriptions['subscriptions_ip2tor']):
            if subscription['id'] == bridgeid:
                subscription['suspend_after'] = str(bridge['suspend_after'])
                subscription['time_lastupdate'] = str(datetime.now().strftime("%Y-%m-%d %H:%M"))
                subscription['price_total'] += int(paymentRequestDecoded.num_msat)
                subscription['contract_breached'] = contract_breached
                subscription['warning'] = warningTXT
                if contract_breached:
                    subscription['active'] = False
                with open(SUBSCRIPTIONS_FILE, 'w') as writer:
                    writer.write(toml.dumps(subscriptions))
                    writer.close()
                break

    except Exception as e:
        eprint(e)
        raise BlitzError("fail on subscription storage", org=e)

    print("# BRIDGE GOT EXTENDED: {0} -> {1}".format(bridge_suspendafter, bridge['suspend_after']))


def menuMakeSubscription(blitzServiceName, torAddress, torPort):
    # late imports - so that rest of script can run also if dependency is not available
    from dialog import Dialog

    torTarget = "{0}:{1}".format(torAddress, torPort)

    ############################
    # PHASE 1: Enter Shop URL

    # see if user had before entered another shop of preference
    shopurl = DEFAULT_SHOPURL
    try:
        subscriptions = toml.load(SUBSCRIPTIONS_FILE)
        shopurl = subscriptions['shop_ip2tor']
        print("# using last shop url set in subscriptions.toml")
    except Exception as e:
        print("# using default shop url")

    # remove https:// from shop url (to keep it short)
    if shopurl.find("://") > 0:
        shopurl = shopurl[shopurl.find("://") + 3:]

    while True:

        # input shop url
        d = Dialog(dialog="dialog", autowidgetsize=True)
        d.set_background_title("Select IP2TOR Bridge Shop (communication secured thru TOR)")
        code, text = d.inputbox(
            "Enter Address of a IP2TOR Shop (OR JUST USE DEFAULT):",
            height=10, width=72, init=shopurl,
            title="Shop Address")

        # if user canceled
        if code != d.OK:
            sys.exit(0)

        # get host list from shop
        shopurl = text
        os.system('clear')
        try:
            hosts = shopList(shopurl)
        except Exception as e:
            # shopurl not working
            eprint(e)
            time.sleep(3)
            Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
Cannot reach a shop under that address.
Please check domain or cancel dialog.
            ''', title="ERROR")
        else:
            # when shop is empty
            if len(hosts) == 0:
                Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
The shop has no available offers at the moment.
Try again later, enter another address or cancel.
            ''', title="ERROR")
            # ok we got hosts - continue
            else:
                break

    ###############################
    # PHASE 2: SELECT SUBSCRIPTION

    # create menu to select shop
    host = None
    choices = []
    for idx, hostEntry in enumerate(hosts):
        choices.append(
            ("{0}".format(idx),
             "{0} ({1} hours, first: {2} sats, next: {3} sats)".format(
                 hostEntry['name'].ljust(20),
                 hostEntry['tor_bridge_duration_hours'],
                 hostEntry['tor_bridge_price_initial_sats'],
                 hostEntry['tor_bridge_price_extension_sats'])
             )
        )

    while True:

        # show menu with options
        d = Dialog(dialog="dialog", autowidgetsize=True)
        d.set_background_title("IP2TOR Bridge Shop: {0}".format(shopurl))
        code, tag = d.menu(
            "Following TOR bridge hosts are available. Select for details:",
            choices=choices, title="Available Subscriptions")

        # if user cancels
        if code != d.OK:
            sys.exit(0)

        # get data of selected
        seletedIndex = int(tag)
        host = hosts[seletedIndex]

        # optimize content for display
        if len(host['terms_of_service']) == 0: host['terms_of_service'] = "-"
        if len(host['terms_of_service_url']) == 0: host['terms_of_service_url'] = "-"

        # show details of selected
        d = Dialog(dialog="dialog", autowidgetsize=True)
        d.set_background_title("IP2TOR Bridge Offer Details: {0}".format(shopurl))
        text = '''
The subscription would renew every {0} hours.
The first time it would cost: {1} sats
Every next time it would cost: {2} sats

If you AGREE you will subscribe to this service.
You will get a port on the IP {3} that will
forward to your RaspiBlitz TOR address for '{7}':
{4}

You can cancel the subscription anytime under
the "SUBSCRIPTONS" menu on your RaspiBlitz.
There will be no refunds for not used hours.
There is no guarantee for quality of service.

The service has the following additional terms:
{5}

More information on the service you can find under:
{6}
'''.format(
            host['tor_bridge_duration_hours'],
            host['tor_bridge_price_initial_sats'],
            host['tor_bridge_price_extension_sats'],
            host['ip'],
            torTarget,
            host['terms_of_service'],
            host['terms_of_service_url'],
            blitzServiceName
        )

        code = d.msgbox(text, title=host['name'], ok_label="Back", extra_button=True, extra_label="AGREE", width=75,
                        height=30)

        # if user AGREED break loop and continue with selected host
        if code == "extra":
            break

    ############################
    # PHASE 3: Make Subscription

    description = "{0} / {1} / {2}".format(host['name'], host['terms_of_service'], host['terms_of_service_url'])

    try:

        os.system('clear')
        subscription = shopOrder(shopurl, host['id'], blitzServiceName, torTarget, host['tor_bridge_duration'],
                                 host['tor_bridge_price_initial'], host['tor_bridge_price_extension'], description)

    except BlitzError as be:

        exitcode = 0

        try:
            message = be.details['message']
        except KeyError:
            message = ""

        if (be.short == "timeout on waiting for extending bridge" or
                be.short == "fail on subscription storage" or
                be.short == "invalid port" or
                be.short == "timeout bridge not getting ready"):

            # error happened after payment
            exitcode = Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
You DID PAY the initial fee.
But the service was not able to provide service.
Subscription will be ignored.

Error: {0}
Message: {1}
            '''.format(be.short, message), title="Error on Subscription", extra_button=True, extra_label="Details")
        else:

            # error happened before payment
            exitcode = Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
You DID NOT PAY the initial fee.
The service was not able to provide service.
Subscription will be ignored.

Error: {0}
Message: {1}
            '''.format(be.short, message), title="Error on Subscription", extra_button=True, extra_label="Details")

        # show more details (when user used extra button)
        if exitcode == Dialog.EXTRA:
            os.system('clear')
            print('###### ERROR DETAIL FOR DEBUG #######')
            print("")
            print("Error Short:")
            print(be.short)
            print('Shop:')
            print(shopurl)
            print('Bridge:')
            print(str(host))
            print("Error Detail:")
            print(be.details)
            print("")
            input("Press Enter to continue ...")

        sys.exit(1)

    except Exception as e:

        # unknown error happened
        os.system('clear')
        print('###### EXCEPTION DETAIL FOR DEBUG #######')
        print("")
        print('Shop:')
        print(shopurl)
        print('Bridge:')
        print(str(host))
        print("EXCEPTION:")
        print(str(e))
        print("")
        input("Press Enter to continue ...")
        sys.exit(1)

    # if LND REST or LND GRPC service ... add bridge IP to TLS
    if blitzServiceName == SERVICE_LND_REST_API or blitzServiceName == SERVICE_LND_GRPC_API:
        os.system("sudo /home/admin/config.scripts/lnd.tlscert.sh ip-add {0}".format(subscription['ip']))
        os.system("sudo /home/admin/config.scripts/lnd.credentials.sh reset tls")
        os.system("sudo /home/admin/config.scripts/lnd.credentials.sh sync")

    # warn user if not delivered as advertised
    if subscription['contract_breached']:
        Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
The service was payed & delivered, but RaspiBlitz detected:
{0}
You may want to consider to cancel the subscription later.
            '''.format(subscription['warning'], title="Warning"))

    # decide if https:// address
    protocol = ""
    if blitzServiceName == SERVICE_LNBITS:
        protocol = "https://"

    # Give final result feedback to user
    Dialog(dialog="dialog", autowidgetsize=True).msgbox('''
OK your service is ready & your subscription is active.

You payed {0} sats for the first {1} hours.
Next AUTOMATED PAYMENTS will be {2} sats each.

Your service '{3}' should now publicly be reachable under:
{6}{4}:{5}

Please test now if the service is performing as promised.
If not - dont forget to cancel the subscription under:
MAIN MENU > Manage Subscriptions > My Subscriptions
            '''.format(
        host['tor_bridge_price_initial_sats'],
        host['tor_bridge_duration_hours'],
        host['tor_bridge_price_extension_sats'],
        blitzServiceName,
        subscription['ip'],
        subscription['port'],
        protocol),
        title="Subscription Active"
    )


#####################
# COMMANDS
#####################

###############
# CREATE SSH DIALOG
# use for ssh shell menu
###############
def create_ssh_dialog():
    # check parameters
    try:
        if len(sys.argv) <= 4:
            raise BlitzError("incorrect parameters")
    except Exception as e:
        handleException(e)

    servicename = sys.argv[2]
    toraddress = sys.argv[3]
    port = sys.argv[4]

    menuMakeSubscription(servicename, toraddress, port)

    sys.exit()


###############
# SHOP LIST
# call from web interface
###############
def shop_list():
    # check parameters
    try:
        if len(sys.argv) <= 2:
            raise BlitzError("incorrect parameters")
    except Exception as e:
        handleException(e)

    shopurl = sys.argv[2]

    try:
        # get data
        hosts = shopList(shopurl)
        # output is json list of hosts
        print(json.dumps(hosts, indent=2))
    except Exception as e:
        handleException(e)

    sys.exit(0)


##########################
# SHOP ORDER
# call from web interface
##########################
def shop_order():
    # check parameters
    try:
        if len(sys.argv) <= 8:
            raise BlitzError("incorrect parameters")
    except Exception as e:
        handleException(e)

    shopurl = sys.argv[2]
    servicename = sys.argv[3]
    hostid = sys.argv[4]
    toraddress = sys.argv[5]
    duration = sys.argv[6]
    msatsFirst = sys.argv[7]
    msatsNext = sys.argv[8]
    if len(sys.argv) >= 10:
        description = sys.argv[9]
    else:
        description = ""

    # get data
    try:
        subscription = shopOrder(shopurl, hostid, servicename, toraddress, duration, msatsFirst, msatsNext, description)
        # output json ordered bridge
        print(json.dumps(subscription, indent=2))
        sys.exit()
    except Exception as e:
        handleException(e)


#######################
# SUBSCRIPTIONS LIST
# call in intervals from background process
#######################
def subscriptions_list():
    try:

        if Path(SUBSCRIPTIONS_FILE).is_file():
            os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
            subs = toml.load(SUBSCRIPTIONS_FILE)
        else:
            subs = {}
        if "subscriptions_ip2tor" not in subs:
            subs['subscriptions_ip2tor'] = []
        print(json.dumps(subs['subscriptions_ip2tor'], indent=2))

    except Exception as e:
        handleException(e)


#######################
# SUBSCRIPTIONS RENEW
# call in intervals from background process
#######################
def subscriptions_renew():
    print("# RUNNING subscriptions-renew")

    # check parameters
    try:
        secondsBeforeSuspend = int(sys.argv[2])
        if secondsBeforeSuspend < 0:
            secondsBeforeSuspend = 0
    except Exception as e:
        print("# running with secondsBeforeSuspend=0")
        secondsBeforeSuspend = 0

    # check if any active subscriptions are below the secondsBeforeSuspend - if yes extend

    try:

        if not Path(SUBSCRIPTIONS_FILE).is_file():
            print("# no subscriptions")
            sys.exit(0)

        os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
        subscriptions = toml.load(SUBSCRIPTIONS_FILE)
        for idx, subscription in enumerate(subscriptions['subscriptions_ip2tor']):

            try:

                if subscription['active'] and subscription['type'] == "ip2tor-v1":
                    secondsToRun = secondsLeft(parseDate(subscription['suspend_after']))
                    if secondsToRun < secondsBeforeSuspend:
                        print("# RENEW: subscription {0} with {1} seconds to run".format(subscription['id'],
                                                                                         secondsToRun))
                        subscriptionExtend(
                            subscription['shop'],
                            subscription['id'],
                            subscription['duration'],
                            subscription['price_extension'],
                            subscription['suspend_after']
                        )
                    else:
                        print("# GOOD: subscription {0} with {1} "
                              "seconds to run".format(subscription['id'], secondsToRun))

            except BlitzError as be:
                # write error into subscription warning
                subs = toml.load(SUBSCRIPTIONS_FILE)
                for sub in subs['subscriptions_ip2tor']:
                    if sub['id'] == subscription['id']:
                        sub['warning'] = "Exception on Renew: {0}".format(be.short)
                        if be.short == "invoice bigger amount than advertised":
                            sub['contract_breached'] = True
                            sub['active'] = False
                        with open(SUBSCRIPTIONS_FILE, 'w') as writer:
                            writer.write(toml.dumps(subs))
                            writer.close()
                        break
                print("# BLITZERROR on subscriptions-renew of subscription index {0}: {1}".format(idx, be.short))
                print("# {0}".format(be.short))

            except Exception as e:
                print("# EXCEPTION on subscriptions-renew of subscription index {0}".format(idx))
                eprint(e)

    except Exception as e:
        handleException(e)

    # output - not needed only for debug logs
    print("# DONE subscriptions-renew")


#######################
# SUBSCRIPTION CANCEL
# call in intervals from background process
#######################
def subscription_cancel():
    # check parameters
    try:
        if len(sys.argv) <= 2:
            raise BlitzError("incorrect parameters")
    except Exception as e:
        handleException(e)

    subscriptionID = sys.argv[2]

    try:
        os.system("sudo chown admin:admin {0}".format(SUBSCRIPTIONS_FILE))
        subs = toml.load(SUBSCRIPTIONS_FILE)
        newList = []
        for idx, sub in enumerate(subs['subscriptions_ip2tor']):
            if sub['id'] != subscriptionID:
                newList.append(sub)
        subs['subscriptions_ip2tor'] = newList

        # persist change
        with open(SUBSCRIPTIONS_FILE, 'w') as writer:
            writer.write(toml.dumps(subs))
            writer.close()

        print(json.dumps(subs, indent=2))

    except Exception as e:
        handleException(e)


#######################
# GET ADDRESS BY SERVICE NAME
# gets called by other scripts to check if service has a ip2tor bridge address
# output is bash key/value style so that it can be imported with source
#######################
def subscription_by_service():
    # check parameters
    try:
        if len(sys.argv) <= 2:
            raise BlitzError("incorrect parameters")
    except Exception as e:
        handleException(e)

    service_name = sys.argv[2]

    try:
        if os.path.isfile(SUBSCRIPTIONS_FILE):
            subs = toml.load(SUBSCRIPTIONS_FILE)
            for idx, sub in enumerate(subs['subscriptions_ip2tor']):
                if sub['active'] and sub['name'] == service_name:
                    print("type='{0}'".format(sub['type']))
                    print("ip='{0}'".format(sub['ip']))
                    print("port='{0}'".format(sub['port']))
                    print("tor='{0}'".format(sub['tor']))
                    sys.exit(0)

        print("error='not found'")

    except Exception as e:
        handleException(e)
        sys.exit(1)


#######################
# GET IP BY ONION ADDRESS
# gets called by other scripts to check if a onion address as a IP2TOR bridge
# output is bash key/value style so that it can be imported with source
#######################
def ip_by_tor():
    # check parameters
    try:
        if len(sys.argv) <= 2:
            raise BlitzError("incorrect parameters")
    except Exception as e:
        handleException(e)

    onion = sys.argv[2]

    try:
        if os.path.isfile(SUBSCRIPTIONS_FILE):
            subs = toml.load(SUBSCRIPTIONS_FILE)
            for idx, sub in enumerate(subs['subscriptions_ip2tor']):
                if sub['active'] and (sub['tor'] == onion or sub['tor'].split(":")[0] == onion):
                    print("id='{0}'".format(sub['id']))
                    print("type='{0}'".format(sub['type']))
                    print("ip='{0}'".format(sub['ip']))
                    print("port='{0}'".format(sub['port']))
                    print("tor='{0}'".format(sub['tor']))
                    sys.exit(0)

        print("error='not found'")

    except Exception as e:
        handleException(e)
        sys.exit(1)


def main():
    if sys.argv[1] == "create-ssh-dialog":
        create_ssh_dialog()

    elif sys.argv[1] == "shop-list":
        shop_list()

    elif sys.argv[1] == "shop-order":
        shop_order()

    elif sys.argv[1] == "subscriptions-list":
        subscriptions_list()

    elif sys.argv[1] == "subscriptions-renew":
        subscriptions_renew()

    elif sys.argv[1] == "subscription-cancel":
        subscription_cancel()

    elif sys.argv[1] == "subscription-by-service":
        subscription_by_service()

    elif sys.argv[1] == "ip-by-tor":
        ip_by_tor()

    else:
        # unknown command
        print("# unknown command")


if __name__ == '__main__':
    main()
