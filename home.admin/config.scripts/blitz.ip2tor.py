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
    print("# blitz.ip2tor.py subscription-cancel [id]")
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
    LND_ADMIN_MACAROON_PATH="/mnt/hdd/app-data/lnd/data/chain/{0}/{1}net/admin.macaroon".format(cfg.network.value,cfg.chain)
    LND_TLS_PATH="/mnt/hdd/app-data/lnd/tls.cert"
    # make sure to make requests thru TOR 127.0.0.1:9050
    session.proxies = {'http':  'socks5h://127.0.0.1:9050', 'https': 'socks5h://127.0.0.1:9050'}
else:
    print("# blitz.ip2tor.py (development env)")
    DEFAULT_SHOPURL="shop.ip2t.org"
    LND_IP="192.168.178.95"
    LND_ADMIN_MACAROON_PATH="/Users/rotzoll/Downloads/RaspiBlitzCredentials/admin.macaroon"
    LND_TLS_PATH="/Users/rotzoll/Downloads/RaspiBlitzCredentials/tls.cert"

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

def parseDate(datestr):
    return datetime.datetime.strptime(datestr,"%Y-%m-%dT%H:%M:%S.%fZ")

def secondsLeft(dateObj):
    return round((dateObj - datetime.datetime.utcnow()).total_seconds())

# takes a shopurl from user input and turns it into the format needed
# also makes sure that .onion addresses run just with http not https
def normalizeShopUrl(shopurlUserInput):

    # basic checks and formats
    if len(shopurlUserInput) < 3: return ""
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
        raise BlitzError("falied HTTP request",url,e)
    if response.status_code != 200:
        raise BlitzError("failed HTTP code",response.status_code,)
    
    # parse & validate data
    try:
        jData = json.loads(response.content)
    except Exception as e:
        raise BlitzError("failed JSON parsing",response.content,e)
    if not isinstance(jData, list):
        raise BlitzError("hosts not list",response.content)
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
            raise BlitzError("failed host entry pasring",str(hostEntry),e)  

        hosts.append(hostEntry)
    
    print("# found {0} valid torbridge hosts".format(len(hosts)))
    return hosts

def apiPlaceOrderNew(session, shopurl, hostid, toraddressWithPort):

    print("# apiPlaceOrderNew")

    try:
        url="{0}/api/v1/public/order/".format(shopurl)
        postData={
            'product': "tor_bridge",
            'host_id': hostid,
            'tos_accepted': True,
            'comment': 'test',
            'target': toraddressWithPort,
            'public_key': ''
        }  
        response = session.post(url, data=postData)
    except Exception as e:
        raise BlitzError("failed HTTP request",url,e)
    if response.status_code != 201:
        raise BlitzError("failed HTTP code",response.status_code)

    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['id']) == 0:
            print("error='MISSING ID'")
            return
    except Exception as e:
        raise BlitzError("failed JSON parsing",response.status_code,e)

    return jData['id']

def apiPlaceOrderExtension(session, shopurl, bridgeid):

    print("# apiPlaceOrderExtension")

    try:
        url="{0}/api/v1/public/tor_bridges/{1}/extend/".format(shopurl, bridgeid)
        response = session.post(url)
    except Exception as e:
        raise BlitzError("failed HTTP request",url,e)
    if response.status_code != 200 and response.status_code != 201:
        raise BlitzError("failed HTTP code",response.status_code)

    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['po_id']) == 0:
            print("error='MISSING ID'")
            return
    except Exception as e:
        raise BlitzError("failed JSON parsing",response.content, e)

    return jData['po_id']


def apiGetOrder(session, shopurl, orderid):

    print("# apiGetOrder")

    # make HTTP request
    try:
        url="{0}/api/v1/public/pos/{1}/".format(shopurl,orderid)
        response = session.get(url)
    except Exception as e:
        raise BlitzError("failed HTTP request",url, e)
    if response.status_code != 200:
        raise BlitzError("failed HTTP code",response.status_code)

    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['item_details']) == 0:
            raise BlitzError("missing item",response.content)
        if len(jData['ln_invoices']) > 1:
            raise BlitzError("more than one invoice",response.content)
    except Exception as e:
        raise BlitzError("failed JSON parsing",response.content, e)

    return jData

def apiGetBridgeStatus(session, shopurl, bridgeid):

    print("# apiGetBridgeStatus")

    # make HTTP request
    try:
        url="{0}/api/v1/public/tor_bridges/{1}/".format(shopurl,bridgeid)
        response = session.get(url)
    except Exception as e:
        raise BlitzError("failed HTTP request",url, e)
    if response.status_code != 200:
        raise BlitzError("failed HTTP code",response.status_code)
    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['id']) == 0:
            raise BlitzError("missing id",response.content)
    except Exception as e:
        raise BlitzError("failed JSON parsing",response.content, e)

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
            raise BlitzError("zero invoice not allowed",lnInvoiceString)

    except Exception as e:
        raise BlitzError("failed LND invoice decoding",lnInvoiceString,e)

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
            raise BlitzError(response.payment_error,lnInvoiceString)

    except Exception as e:
        raise BlitzError("payment failed",lnInvoiceString,e)

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

    print("#### WAIT UNTIL INVOICE IS AVAILABLE")
    loopCount=0
    while True:
        time.sleep(2)
        loopCount+=1
        print("# Loop {0}".format(loopCount))
        order = apiGetOrder(session, shopUrl, orderid)
        if len(order['ln_invoices']) > 0 and order['ln_invoices'][0]['payment_request'] is not None:
            break
        if loopCount > 30:
            raise BlitzError("timeout on getting invoice", order)

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
        raise BlitzError("invoice other amount than advertised", "advertised({0}) invoice({1})".format(msatsFirst, paymentRequestDecoded.num_msat))

    print("#### PAY INVOICE")
    payedInvoice = lndPayInvoice(paymentRequestStr)
    print('# OK PAYMENT SENT')

    print("#### CHECK IF BRIDGE IS READY")
    loopCount=0
    while True:
        time.sleep(3)
        loopCount+=1
        print("## Loop {0}".format(loopCount))
        bridge = apiGetBridgeStatus(session, shopUrl, bridge_id)
        if bridge['status'] == "A":
            break
        if loopCount > 60: 
            raise BlitzError("timeout bridge not getting ready", bridge)
        
    # get data from ready bride
    bridge_suspendafter = bridge['suspend_after']
    bridge_port = bridge['port']

    print("#### CHECK IF DURATION DELIVERED AS PROMISED")
    secondsDelivered=secondsLeft(parseDate(bridge_suspendafter))
    print("# delivered({0}) promised({1})".format(secondsDelivered, duration))
    if (secondsDelivered + 600) < duration:
        bridge['contract_breached'] = True
        bridge['warning'] = "delivered duration shorter than advertised"
    else:
        bridge['contract_breached'] = False

    print("# OK - BRIDGE READY: {0}:{1} -> {2}".format(bridge_ip, bridge_port, torTarget))
    return bridge
    
def subscriptionExtend(shopUrl, bridgeid, durationAdvertised, msatsFirst):    

    print("#### PLACE EXTENSION ORDER")
    shopUrl=normalizeShopUrl(shopUrl)
    orderid = apiPlaceOrderExtension(session, shopUrl, bridgeid)

    print("#### WAIT UNTIL INVOICE IS AVAILABLE")
    loopCount=0
    while True:
        time.sleep(2)
        loopCount+=1
        print("## Loop {0}".format(loopCount))
        order = apiGetOrder(session, shopUrl, orderid)
        if len(order['ln_invoices']) > 0 and order['ln_invoices'][0]['payment_request'] is not None:
            break
        if loopCount > 30:
            raise BlitzError("timeout on getting invoice", order)
        
    
    paymentRequestStr = order['ln_invoices'][0]['payment_request']

    print("#### DECODE INVOICE & CHECK AMOUNT")
    print("# invoice: {0}".format(paymentRequestStr))
    paymentRequestDecoded = lndDecodeInvoice(paymentRequestStr)
    if paymentRequestDecoded is None: sys.exit()
    print("# amount as advertised: {0}".format(msatsNext))
    print("# amount in invoice is: {0}".format(paymentRequestDecoded.num_msat))
    if msatsNext < paymentRequestDecoded.num_msat:
        raise BlitzError("invoice other amount than advertised", "advertised({0}) invoice({1})".format(msatsNext, paymentRequestDecoded.num_msat))

    print("#### PAY INVOICE")
    payedInvoice = lndPayInvoice(paymentRequestStr)

    print("#### CHECK IF BRIDGE GOT EXTENDED")
    loopCount=0
    while True:
        time.sleep(3)
        loopCount+=1
        print("## Loop {0}".format(loopCount))
        bridge = apiGetBridgeStatus(session, shopUrl, bridgeid)
        if bridge['suspend_after'] != bridge_suspendafter:
            break
        if loopCount > 60: 
            raise BlitzError("timeout on waiting for extending bridge", bridge)

    print("#### CHECK IF DURATION DELIVERED AS PROMISED")
    secondsLeftOld = secondsLeft(parseDate(bridge_suspendafter))
    secondsLeftNew = secondsLeft(parseDate(bridge['suspend_after']))
    secondsExtended = secondsLeftNew - secondsLeftOld
    print("# secondsExtended({0}) promised({1})".format(secondsExtended, durationAdvertised))
    if secondsExtended < durationAdvertised:
        bridge['contract_breached'] = True
        bridge['warning'] = "delivered duration shorter than advertised"
    else:
        bridge['contract_breached'] = False
    
    print("# BRIDGE GOT EXTENDED: {0} -> {1}".format(bridge_suspendafter, bridge['suspend_after']))
    return bridge

def menuMakeSubscription(blitzServiceName, torAddress, torPort):

    torTarget = "{0}:{1}".format(torAddress, torPort)

    ############################
    # PHASE 1: Enter Shop URL

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
        try:
            hosts = shopList(shopurl)
        except Exception as e:
            # shopurl not working
            Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
Cannot reach a shop under that address.
Please check domain or cancel dialog.
            ''',title="ERROR")
        else:
            # when shop is empty
            if len(hosts) == 0:
                Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
The shop has no available offers at the moment.
Try again later, enter another address or cancel.
            ''',title="ERROR")
            # ok we got hosts - continue
            else: break

    ###############################
    # PHASE 2: SELECT SUBSCRIPTION

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
        
        # if user cancels
        if code != d.OK: sys.exit(0)

        # get data of selected
        seletedIndex = int(tag)
        host = hosts[seletedIndex]

        # optimize content for display
        if len(host['terms_of_service']) == 0: host['terms_of_service'] = "-"
        if len(host['terms_of_service_url']) == 0: host['terms_of_service_url'] = "-"

        # show details of selected
        d = Dialog(dialog="dialog",autowidgetsize=True)
        d.set_background_title("IP2TOR Bridge Offer Details: {0}".format(shopurl))
        text='''
The subscription will renew every {0} hours.
The first time it will cost: {1} sats
Every next time it will cost: {2} sats

If you AGREE you will subscribe to this service.
You will get a port on the IP {3} that will
forward to your RaspiBlitz TOR address:
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
        host['terms_of_service_url'])

        code = d.msgbox(text, title=host['name'], ok_label="Back", extra_button=True,  extra_label="AGREE" ,width=60, height=30)
        
        # if user AGREED break loop and continue with selected host
        if code == "extra": break

    ############################
    # PHASE 3: Make Subscription

    try:

        #bridge = shopOrder(shopurl, host['id'], torTarget, host['tor_bridge_duration'], host['tor_bridge_price_initial_sats'])
        bridge=[]
        bridge['contract_breached']=True

    except BlitzError as be:

        if  be.errorShort == "timeout on waiting for extending bridge":

            # error happend after payment
            Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
You DID PAY the initial fee.
But the service was not able to provide service.
Subscription will be ignored.
            ''',title="Error on Subscription")
            sys.exit(1)

        else:

            # error happend before payment
            Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
You DID NOT PAY the initial fee.
The service was not able to provide service.
Subscription will be ignored.
Error: {0}
            '''.format(be.errorShort),title="Error on Subscription")
            sys.exit(1)

    except Exception as e:

            # unkown error happend
            Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
Unkown Error happend - please report to developers:
{0}
            '''.format(str(e)),title="Exception on Subscription")
            sys.exit(1)

    # warn user if not delivered as advertised
    if bridge['contract_breached']:
        Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
The service was payed & delivered, but RaspiBlitz detected:
{0}
You may want to consider to cancel the subscription later.
            '''.format(bridge['warning'],title="Warning"))

    # TODO: persist subscription in list

    # Give final result feedback to user
    Dialog(dialog="dialog",autowidgetsize=True).msgbox('''
OK your service is ready & your subscription is active.

You payed {0} sats for the first {1} hours.
Next AUTOMATED PAYMENT will be {2} sats.

Your service '{3}' should now publicly be reachable under:
{4}:{5}

Please test now if the service is performing as promised.
If not - dont forget to cancel the subscription under:
MAIN MENU > SUBSCRIPTIONS > MY SUBSCRIPTIONS
            '''.format(be.errorShort),title="Subscription Active") 


####### COMMANDS #########

###############
# MENU
# use for ssh shell menu
###############

if sys.argv[1] == "menu":

    # late imports - so that rest of script can run also if dependency is not available
    from dialog import Dialog

    menuMakeSubscription("RTL", "s7foqiwcstnxmlesfsjt7nlhwb2o6w44hc7glv474n7sbyckf76wn6id.onion", "80")

    sys.exit()

###############
# SHOP LIST
# call from web interface
###############    

if sys.argv[1] == "shop-list":

    # check parameters
    try:
        shopurl = sys.argv[2]
    except Exception as e:
        handleException(e)

    # get data
    try:
        hosts = shopList(shopurl)
    except Exception as e:
        handleException(e)

    # output is json list of hosts
    json.dumps(hosts, indent=2)
    sys.exit(0)

###############
# SHOP ORDER
# call from web interface
###############    

if sys.argv[1] == "shop-order":

    # check parameters
    try:
        shopurl = sys.argv[2]
        hostid = sys.argv[3]
        toraddress = sys.argv[4]
        duration = sys.argv[5]
        msats = sys.argv[6]
    except Exception as e:
        handleException(e)

    # get data
    try:
        bridge = shopOrder(shopurl, hostid, toraddress, duration, msats)
    except Exception as e:
        handleException(e)

    # TODO: persist subscription

    # output json ordered bridge
    json.dumps(bridge, indent=2)
    sys.exit()

#######################
# SUBSCRIPTIONS LIST
# call in intervalls from background process
#######################

if sys.argv[1] == "subscriptions-list":

    try:
        
        # TODO: JSON output of list with all subscrptions
        print("TODO: implement")
    
    except Exception as e:
        handleException(e)

    sys.exit(0)

#######################
# SUBSCRIPTIONS RENEW
# call in intervalls from background process
#######################

if sys.argv[1] == "subscriptions-renew":

    # check parameters
    try:
        secondsBeforeSuspend = sys.argv[2]
        if secondsBeforeSuspend < 0: secondsBeforeSuspend = 0
    except Exception as e:
        handleException(e)

    # TODO: check if any active subscrpitions are below the secondsBeforeSuspend - if yes extend
    print("TODO: implement")
    sys.exit(1)

    # get date
    try:
        bridge = subscriptionExtend(shopUrl, bridgeid, durationAdvertised, msatsFirst)
    except Exception as e:
        handleException(e)

    # TODO: persist subscription

    # output - not needed only for debug logs
    print("# DONE subscriptions-renew")

#######################
# SUBSCRIPTION CANCEL
# call in intervalls from background process
#######################

if sys.argv[1] == "subscription-cancel":

    try:
        
        # TODO: JSON output of list with all subscrptions
        print("TODO: implement")
    
    except Exception as e:
        handleException(e)

    sys.exit(0)

# unkown command
print("# unkown command")