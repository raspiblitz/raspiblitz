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

from blitzpy import RaspiBlitzConfig

from lndlibs import rpc_pb2 as lnrpc
from lndlibs import rpc_pb2_grpc as rpcstub

####### SCRIPT INFO #########

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# manage ip2tor subscriptions for raspiblitz")
    print("# blitz.ip2tor.py menu")
    print("# blitz.ip2tor.py shop-list [shopurl]")
    print("# blitz.ip2tor.py shop-order [shopurl] [hostid] [toraddress:port] [duration] [msats]")
    print("# blitz.ip2tor.py subscriptions-list")
    print("# blitz.ip2tor.py subscriptions-renew [secondsBeforeSuspend]")
    sys.exit(1)

####### BASIC SETTINGS #########

cfg = RaspiBlitzConfig()
session = requests.session()
if Path("/mnt/hdd/raspiblitz.conf").is_file():
    print("# blitz.ip2tor.py")
    cfg.reload()
    #DEFAULT_SHOPURL="shopdeu2vdhazvmllyfagdcvlpflzdyt5gwftmn4hjj3zw2oyelksaid.onion"
    DEFAULT_SHOPURL="shop.ip2t.org"
    LND_IP="127.0.0.1"
    LND_ADMIN_MACAROON_PATH="/mnt/hdd/app-data/lnd/data/chain/{0}/{1}net/admin.macaroon".format(cfg.network,cfg.chain)
    LND_TLS_PATH="/mnt/hdd/app-data/lnd/tls.cert"
    # make sure to make requests thru TOR 127.0.0.1:9050
    session.proxies = {'http':  'socks5h://127.0.0.1:9050', 'https': 'socks5h://127.0.0.1:9050'}
else:
    print("# blitz.ip2tor.py (development env)")
    DEFAULT_SHOPURL="shop.ip2t.org"
    LND_IP="192.168.178.95"
    LND_ADMIN_MACAROON_PATH="/Users/rotzoll/Downloads/RaspiBlitzCredentials/admin.macaroon"
    LND_TLS_PATH="/Users/rotzoll/Downloads/RaspiBlitzCredentials/tls.cert"

####### HELPER FUNCTIONS #########

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def parseDate(datestr):
    return datetime.datetime.strptime(datestr,"%Y-%m-%dT%H:%M:%S.%fZ")

def secondsLeft(dateObj):
    return round((dateObj - datetime.datetime.utcnow()).total_seconds())

# takes a shopurl from user input and turns it into the format needed
# also makes sure that .onion addresses run just with http not https
def normalizeShopUrl(shopurlUserInput):

    # basic checks and formats
    if len(shopurlUserInput) < 3: return
    shopurlUserInput = shopurlUserInput.lower()
    shopurlUserInput = shopurlUserInput.replace(" ", "")
    shopurlUserInput = shopurlUserInput.replace("\n", "")
    shopurlUserInput = shopurlUserInput.replace("\r", "")

    # remove protocol from the beginning (if needed)
    if shopurlUserInput.find("://") > 0:
        shopurlUserInput = shopurlUserInput[shopurlUserInput.find("://")+3:]

    # remove all path after domain 
    if shopurlUserInput.find("/") > 0:
        shopurlUserInput = shopurlUserInput[:shopurlUserInput.find("/")]

    # add correct protocol again
    if ( not shopurlUserInput.startswith("http://") and not shopurlUserInput.startswith("https://") ):
        if shopurlUserInput.endswith(".onion"):
            shopurlUserInput = "http://{0}".format(shopurlUserInput)
        else:
            shopurlUserInput = "https://{0}".format(shopurlUserInput)

    return shopurlUserInput

####### IP2TOR API CALLS #########

def apiGetHosts(session, shopurl):

    print("# apiGetHosts")
    hosts=[]

    # make HTTP request
    try:
        url="{0}/api/v1/public/hosts/".format(shopurl)
        response = session.get(url)
    except Exception as e:
        eprint(url)
        eprint(e)
        print("error='FAILED HTTP REQUEST'")
        return
    if response.status_code != 200:
        eprint(url)
        eprint(response.content)
        print("error='FAILED HTTP CODE ({0})'".format(response.status_code))
        return
    
    # parse & validate data
    try:
        jData = json.loads(response.content)
    except Exception as e:
        eprint(e)
        print("error='FAILED JSON PARSING'")
        return
    if not isinstance(jData, list):
        print("error='NOT A JSON LIST'")
        return    
    for idx, hostEntry in enumerate(jData):
        try:
            # ignore if not offering tor bridge
            if not hostEntry['offers_tor_bridges']: continue
            # ignore if duration is less than an hour
            if hostEntry['tor_bridge_duration'] < 3600: continue
            # add duration per hour value 
            hostEntry['tor_bridge_duration_hours'] = math.floor(hostEntry['tor_bridge_duration']/3600)
            # ignore if prices are negative or below one sat (maybe msats later)
            if hostEntry['tor_bridge_price_initial'] < 1000: continue
            if hostEntry['tor_bridge_price_extension'] < 1000: continue
            # add price in sats
            hostEntry['tor_bridge_price_initial_sats'] = math.ceil(hostEntry['tor_bridge_price_initial']/1000)
            hostEntry['tor_bridge_price_extension_sats'] = math.ceil(hostEntry['tor_bridge_price_extension']/1000)
            # ignore name is less then 3 chars
            if len(hostEntry['name']) < 3: continue
            # ignore id with zero value
            if len(hostEntry['id']) < 1: continue
            # shorten names to 20 chars max
            hostEntry['name'] = hostEntry['name'][:20]
        except Exception as e:
            eprint(e)
            print("error='PARSING HOST ENTRY'")
            return    

        hosts.append(hostEntry)
    
    print("# found {0} valid torbridge hosts".format(len(hosts)))
    return hosts

def apiPlaceOrderNew(session, shopurl, hostid, toraddressWithPort):

    print("# apiPlaceOrderNew")

    try:
        postData={
            'product': "tor_bridge",
            'host_id': hostid,
            'tos_accepted': True,
            'comment': 'test',
            'target': toraddressWithPort,
            'public_key': ''
        }  
        response = session.post("{0}/api/v1/public/order/".format(shopurl), data=postData)
    except Exception as e:
        eprint(e)
        print("error='FAILED HTTP REQUEST'")
        return
    if response.status_code != 201:
        eprint(response.content)
        print("error='FAILED HTTP CODE ({0}) != 201'".format(response.status_code))
        return

    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['id']) == 0:
            print("error='MISSING ID'")
            return
    except Exception as e:
        eprint(e)
        print("error='FAILED JSON PARSING'")
        return

    return jData['id']

def apiPlaceOrderExtension(session, shopurl, bridgeid):

    print("# apiPlaceOrderExtension")

    try:
        url="{0}/api/v1/public/tor_bridges/{1}/extend/".format(shopurl, bridgeid)
        response = session.post(url)
    except Exception as e:
        eprint(url)
        eprint(e)
        print("error='FAILED HTTP REQUEST'")
        return
    if response.status_code != 200 and response.status_code != 201:
        eprint(response.content)
        print("error='FAILED HTTP CODE ({0}) != 201'".format(response.status_code))
        return

    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['po_id']) == 0:
            print("error='MISSING ID'")
            return
    except Exception as e:
        eprint(e)
        print("error='FAILED JSON PARSING'")
        return

    return jData['po_id']


def apiGetOrder(session, shopurl, orderid):

    print("# apiGetOrder")

    # make HTTP request
    try:
        response = session.get("{0}/api/v1/public/pos/{1}/".format(shopurl,orderid))
    except Exception as e:
        eprint(e)
        print("error='FAILED HTTP REQUEST'")
        return
    if response.status_code != 200:
        eprint(response.content)
        print("error='FAILED HTTP CODE ({0})'".format(response.status_code))
        return
    
    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['item_details']) == 0:
            print("error='MISSING ITEM'")
            return
        if len(jData['ln_invoices']) > 1:
            print("error='MORE THEN ONE INVOICE'")
            return
    except Exception as e:
        eprint(e)
        print("error='FAILED JSON PARSING'")
        return

    return jData

def apiGetBridgeStatus(session, shopurl, bridgeid):

    print("# apiGetBridgeStatus")

    # make HTTP request
    try:
        response = session.get("{0}/api/v1/public/tor_bridges/{1}/".format(shopurl,bridgeid))
    except Exception as e:
        eprint(e)
        print("error='FAILED HTTP REQUEST'")
        return
    if response.status_code != 200:
        eprint(response.content)
        print("error='FAILED HTTP CODE ({0})'".format(response.status_code))
        return
    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['id']) == 0:
            print("error='ID IS MISSING'")
            return
    except Exception as e:
        eprint(e)
        print("error='FAILED JSON PARSING'")
        return

    return jData

####### LND API CALLS #########

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
            print("error='ZERO INVOICES NOT ALLOWED'")
            return  

    except Exception as e:
        eprint(e)
        print("error='FAILED LND INVOICE DECODING'")
        return

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
            print("error='PAYMENT FAILED'")
            print("error_detail='{}'".format(response.payment_error))
            return  

    except Exception as e:
       print("error='FAILED LND INVOICE PAYMENT'")
       return

    return response

####### PROCESS FUNCTIONS #########

def shopList(shopUrl):

    print("#### GET HOSTS")
    shopUrl=normalizeShopUrl(shopUrl)
    return apiGetHosts(session, shopUrl)

def shopOrder(shopurl, hostid, toraddress, duration, msatsFirst):

    print("#### PLACE ORDER")
    shopUrl=normalizeShopUrl(shopUrl)
    orderid = apiPlaceOrderNew(session, shopUrl, hostid, torTarget)
    if orderid is None: sys.exit()

    print("#### WAIT UNTIL INVOICE IS AVAILABLE")
    loopCount=0
    while True:
        loopCount+=1
        print("# Loop {0}".format(loopCount))
        order = apiGetOrder(session, shopUrl, orderid)
        if order is None: sys.exit()
        if len(order['ln_invoices']) > 0 and order['ln_invoices'][0]['payment_request'] is not None: break
        if loopCount > 30: 
            eprint("# server is not able to deliver a invoice within timeout")
            print("error='timeout on getting invoice'")
            sys.exit()
        time.sleep(2)

    # get data from now complete order
    paymentRequestStr = order['ln_invoices'][0]['payment_request']
    bridge_id = order['item_details'][0]['product']['id']
    bridge_ip = order['item_details'][0]['product']['host']['ip']
    bridge_port = order['item_details'][0]['product']['port']

    print("#### DECODE INVOICE & CHECK)")
    print("# invoice: {0}".format(paymentRequestStr))
    paymentRequestDecoded = lndDecodeInvoice(paymentRequestStr)
    if paymentRequestDecoded is None: sys.exit()
    print("# amount as advertised: {0}".format(msatsFirst))
    print("# amount in invoice is: {0}".format(paymentRequestDecoded.num_msat))
    if msatsFirst < paymentRequestDecoded.num_msat:
        eprint("# invoice wants more the advertised before -> EXIT")
        print("error='invoice other amount than advertised'")
        sys.exit(1)

    print("#### PAY INVOICE")
    payedInvoice = lndPayInvoice(paymentRequestStr)
    if payedInvoice is None: sys.exit()
    print('# OK PAYMENT SENT')

    print("#### CHECK IF BRIDGE IS READY")
    loopCount=0
    while True:
        loopCount+=1
        print("## Loop {0}".format(loopCount))
        bridge = apiGetBridgeStatus(session, shopUrl, bridge_id)
        if bridge is None: sys.exit()
        if bridge['status'] == "A": break
        if loopCount > 60: 
            eprint("# timeout bridge not getting ready")
            print("error='timeout on waiting for active bridge'")
            sys.exit()
        time.sleep(3)

    # get data from ready bride
    bridge_suspendafter = bridge['suspend_after']
    bridge_port = bridge['port']

    print("#### CHECK IF DURATION DELIVERED AS PROMISED")
    secondsDelivered=secondsLeft(parseDate(bridge_suspendafter))
    print("# delivered({0}) promised({1})".format(secondsDelivered, duration))
    if (secondsDelivered + 600) < duration:
        print("warning='delivered duration shorter than advertised'")

    print("# OK - BRIDGE READY: {0}:{1} -> {2}".format(bridge_ip, bridge_port, torTarget))

def subscriptionExtend(shopUrl, bridgeid, duration, msatsFirst):    

    print("#### PLACE EXTENSION ORDER")
    shopUrl=normalizeShopUrl(shopUrl)
    orderid = apiPlaceOrderExtension(session, shopUrl, bridgeid)
    if orderid is None: sys.exit()

    print("#### WAIT UNTIL INVOICE IS AVAILABLE")
    loopCount=0
    while True:
        loopCount+=1
        print("## Loop {0}".format(loopCount))
        order = apiGetOrder(session, shopUrl, orderid)
        if order is None: sys.exit()
        if len(order['ln_invoices']) > 0 and order['ln_invoices'][0]['payment_request'] is not None: break
        if loopCount > 30: 
            eprint("# server is not able to deliver a invoice within timeout")
            print("error='timeout on getting invoice'")
            sys.exit()
        time.sleep(2)
    
    paymentRequestStr = order['ln_invoices'][0]['payment_request']

    print("#### DECODE INVOICE & CHECK AMOUNT")
    print("# invoice: {0}".format(paymentRequestStr))
    paymentRequestDecoded = lndDecodeInvoice(paymentRequestStr)
    if paymentRequestDecoded is None: sys.exit()
    print("# amount as advertised: {0}".format(msatsNext))
    print("# amount in invoice is: {0}".format(paymentRequestDecoded.num_msat))
    if msatsNext < paymentRequestDecoded.num_msat:
        eprint("# invoice wants more the advertised before -> EXIT")
        print("error='invoice other amount than advertised'")
        sys.exit(1)

    print("#### PAY INVOICE")
    payedInvoice = lndPayInvoice(paymentRequestStr)
    if payedInvoice is None: sys.exit()

    print("#### CHECK IF BRIDGE GOT EXTENDED")
    loopCount=0
    while True:
        loopCount+=1
        print("## Loop {0}".format(loopCount))
        bridge = apiGetBridgeStatus(session, shopUrl, bridgeid)
        if bridge['suspend_after'] != bridge_suspendafter: break
        if loopCount > 60: 
            eprint("# timeout bridge not getting ready")
            print("error='timeout on waiting for extending bridge'")
            sys.exit()
        time.sleep(3)

    print("#### CHECK IF DURATION DELIVERED AS PROMISED")
    secondsLeftOld = secondsLeft(parseDate(bridge_suspendafter))
    secondsLeftNew = secondsLeft(parseDate(bridge['suspend_after']))
    secondsExtended = secondsLeftNew - secondsLeftOld
    print("# secondsExtended({0}) promised({1})".format(secondsExtended, duration))
    if secondsExtended < duration:
        print("warning='delivered duration shorter than advertised'")
    
    print("# BRIDGE GOT EXTENDED: {0} -> {1}".format(bridge_suspendafter, bridge['suspend_after']))

####### COMMANDS #########

###############
# MENU
# use for ssh shell menu
###############

if sys.argv[1] == "menu":

    # late imports - so that rest of script can run also if dependency is not available
    from dialog import Dialog

    shopurl = DEFAULT_SHOPURL
    while True:

        # input shop url
        d = Dialog(dialog="dialog",autowidgetsize=True)
        d.set_background_title("Select IP2TOR Bridge Shop (communication secured thru TOR)")
        code, text = d.inputbox(
            "Enter Address of a IP2TOR Shop (PRESS ENTER FOR DEFAULT):",
            height=10, width=60, init=shopurl,
            title="Shop Address")

        # if user canceled
        if code != d.OK: sys.exit(0)

        # get host list from shop
        shopurl = text
        os.system('clear')
        hosts = shopList(shopurl)
        if hosts is None:
            # shopurl not working
            Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
Cannot reach a shop under that address.
Please check domain or cancel dialog.
            ''',title="ERROR")
        elif len(hosts) == 0:
            # shopurl not working
            Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
The shop has no available offers at the moment.
Try again later, enter another address or cancel.
            ''',title="ERROR")
        else:
            # ok we got hosts - continue
            break

    # TODO: User entry of shopurl - loop until working or cancel
    
    # create menu to select shop - TODO: also while loop list & detail until cancel or subscription
    host=None
    choices = []
    for idx, hostEntry in enumerate(hosts):
        choices.append( ("{0}".format(idx), "{0} ({1} hours, first: {2} sats, next: {3} sats)".format(hostEntry['name'].ljust(20), hostEntry['tor_bridge_duration_hours'], hostEntry['tor_bridge_price_initial_sats'], hostEntry['tor_bridge_price_extension_sats'])) )
    
    while True:

        # show menu with options
        d = Dialog(dialog="dialog",autowidgetsize=True)
        d.set_background_title("IP2TOR Bridge Shop: {0}".format(shopurl))
        code, tag = d.menu(
            "Following TOR bridge hosts are available. Select for details:",
            choices=choices, title="Available Subscriptions")
        if code != d.OK:
            host=None
            break

        # get data of selected
        seletedIndex = int(tag)
        host = hosts[seletedIndex]
        #hostid = hosts[seletedIndex]['id']
        #msatsFirst=hosts[seletedIndex]['tor_bridge_price_initial']
        #msatsNext=hosts[seletedIndex]['tor_bridge_price_extension']
        #duration=hosts[seletedIndex]['tor_bridge_duration']

        # optimize content for display
        if len(host['terms_of_service']) == 0: host['terms_of_service'] = "-"
        if len(host['terms_of_service_url']) == 0: host['terms_of_service_url'] = "-"

        # show details of selected
        d = Dialog(dialog="dialog",autowidgetsize=True)
        d.set_background_title("IP2TOR Bridge Offer Details: {0}".format(shopurl))
        text='''
Name: {0}

If you AGREE you will subscribe to this service.
You will get a port on the IP {1} that will
forward to your RaspiBlitz TOR address:
{2}

The subscription will renew every {3} hours.
The first time it will cost: {4} sats
Every next time it will cost: {5} sats

You can cancel the subscription anytime under
the "SUBSCRIPTONS" menu on your RaspiBlitz.
There will be no refunds for not used hours.
There is no guarantee for quality of service.

The service has the following additional terms:
{6}

More information on the service you can find under:
{7}
'''.format(
        host['name'],
        host['ip'],
        "secrdrop5wyphb5x.onion:80",
        host['tor_bridge_duration_hours'],
        host['tor_bridge_price_initial_sats'],
        host['tor_bridge_price_extension_sats'],
        host['terms_of_service'],
        host['terms_of_service_url'])

        d.scrollbox(text, width=60)

    # if user has canceled
    if host is None:
        print("cancel")
        sys.exit(0)

    # TODO: try to subscribe to host
    print(hostid)

    sys.exit()

###############
# SHOP LIST
# call from web interface
###############    

if sys.argv[1] == "shop-list":

    # check parameters
    try:
        shopurl = sys.argv[2]
        if len(shopurl) == 0:
            print("error='invalid parameter'")
            sys.exit(1)
    except Exception as e:
        print("error='invalid parameters'")
        sys.exit(1)

    # get data
    hosts = shopList(shopurl)
    if hosts is None: sys.exit(1)

    # output is json list of hosts
    print(hosts)
    sys.exit(0)

###############
# SHOP ORDER
# call from web interface
###############    

if sys.argv[1] == "shop-order":

    shopurl = sys.argv[2]
    hostid = sys.argv[3]
    toraddress = sys.argv[4]
    duration = sys.argv[5]
    msats = sys.argv[6]

    # TODO: basic data input check

    shopOrder(shopurl, hostid, toraddress, duration, msats)

    # TODO: print out result data

    sys.exit()

#######################
# SUBSCRIPTIONS RENEW
# call in intervalls from background process
#######################

if sys.argv[1] == "subscriptions-renew":

    # secondsBeforeSuspend
    secondsBeforeSuspend = sys.argv[2]
    if secondsBeforeSuspend < 0:
        print("error='invalid parameter'")
        sys.exit()

    # TODO: check if any active subscrpitions are below the secondsBeforeSuspend - if yes extend
    # subscriptionExtend(shopurl, hostid, toraddress, duration, msatsFirst)

# unkown command
print("error='unkown command'")
sys.exit()