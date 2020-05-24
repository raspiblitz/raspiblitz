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

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# manage ip2tor subscriptions for raspiblitz")
    print("# blitz.ip2tor.py menu")
    sys.exit(1)

# basic settings
cfg = RaspiBlitzConfig()
if Path("/mnt/hdd/raspiblitz.conf").is_file():
    print("# blitz.ip2tor.py")
    cfg.reload()
    DEFAULT_SHOPURL="shopdeu2vdhazvmllyfagdcvlpflzdyt5gwftmn4hjj3zw2oyelksaid.onion"
    LND_IP="127.0.0.1"
    LND_ADMIN_MACAROON_PATH="/mnt/hdd/app-data/lnd/data/chain/{0}/{1}net/admin.macaroon".format(cfg.network,cfg.chain)
    LND_TLS_PATH="/mnt/hdd/app-data/lnd/tls.cert"
else:
    print("# blitz.ip2tor.py (development env)")
    cfg.run_behind_tor = False
    DEFAULT_SHOPURL="shop.ip2t.org"
    LND_IP="192.168.178.95"
    LND_ADMIN_MACAROON_PATH="/Users/rotzoll/Downloads/RaspiBlitzCredentials/admin.macaroon"
    LND_TLS_PATH="/Users/rotzoll/Downloads/RaspiBlitzCredentials/tls.cert"

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

def apiGetHosts(session, shopurl):

    print("# apiGetHosts")
    hosts=[]

    # make HTTP request
    try:
        response = session.get("{0}/api/v1/public/hosts/".format(shopurl))
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

        print("({0}) {1} ({2} hours, first: {3} sats, next: {4} sats)".format(idx, hostEntry['name'].ljust(20), hostEntry['tor_bridge_duration_hours'], hostEntry['tor_bridge_price_initial_sats'], hostEntry['tor_bridge_price_extension_sats']))
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


torTarget = "qrmfuxwgyzk5jdjz.onion:80"
shopUrl = normalizeShopUrl(DEFAULT_SHOPURL)
session = requests.session()
if cfg.run_behind_tor:
    session.proxies = {'http':  'socks5://127.0.0.1:9050', 'https': 'socks5://127.0.0.1:9050'}

print("#### GET HOSTS")
hosts = apiGetHosts(session, shopUrl)
if hosts is None: sys.exit()
print(hosts)

print("#### PLACE ORDER")
hostid = hosts[0]['id']
msatsFirst=hosts[0]['tor_bridge_price_initial']
msatsNext=hosts[0]['tor_bridge_price_extension']
duration=hosts[0]['tor_bridge_duration']
orderid = apiPlaceOrderNew(session, shopUrl, hostid, torTarget)
if orderid is None: sys.exit()
print(orderid)

print("#### WAIT UNTIL INVOICE IS AVAILABLE")
while True:
    print("## Loop")
    order = apiGetOrder(session, shopUrl, orderid)
    if order is None: sys.exit()
    print(order)
    if len(order['ln_invoices']) > 0 and order['ln_invoices'][0]['payment_request'] is not None: break
    time.sleep(2)
paymentRequestStr = order['ln_invoices'][0]['payment_request']
bridge_id = order['item_details'][0]['product']['id']
bridge_ip = order['item_details'][0]['product']['host']['ip']
bridge_port = order['item_details'][0]['product']['port']

print("#### DECODE INVOICE")
print(paymentRequestStr)
paymentRequestDecoded = lndDecodeInvoice(paymentRequestStr)
if paymentRequestDecoded is None: sys.exit()

print("#### CHECK INVOICE")
print("# is invoice not more then advertised: {0}".format(msatsFirst))
print("# amount in invoice is: {0}".format(paymentRequestDecoded.num_msat))
if msatsFirst < paymentRequestDecoded.num_msat:
    print("# invoice wants more the advertised -> EXIT")
    sys.exit(1)

print("#### PAY INVOICE")
payedInvoice = lndPayInvoice(paymentRequestStr)
if payedInvoice is None: sys.exit()
print(payedInvoice)

print("#### CHECK IF BRIDGE IS READY")
while True:
    print("## Loop")
    bridge = apiGetBridgeStatus(session, shopUrl, bridge_id)
    if bridge is None: sys.exit()
    print(bridge)
    if bridge['status'] == "A": break
    time.sleep(3)
bridge_id = bridge['id']
bridge_suspendafter = bridge['suspend_after']
bridge_port = bridge['port']

print("#### CHECK IF DURATION DELIVERED AS PROMISED")
contract_broken=False
secondsDelivered=secondsLeft(parseDate(bridge_suspendafter))
print("delivered({0}) promised({1})".format(secondsDelivered, duration))
if (secondsDelivered + 600) < duration:
    print("CONTRACT BROKEN - duration delivered is too small")
    sys.exit()

print("BRIDGE READY: {0}:{1} -> {2}".format(bridge_ip, bridge_port, torTarget))

time.sleep(10)

print("#### PLACE EXTENSION ORDER")
orderid = apiPlaceOrderExtension(session, shopUrl, bridge_id)
if orderid is None: sys.exit()
print(orderid)

print("#### WAIT UNTIL INVOICE IS AVAILABLE")
while True:
    print("## Loop")
    order = apiGetOrder(session, shopUrl, orderid)
    if order is None: sys.exit()
    print(order)
    if len(order['ln_invoices']) > 0 and order['ln_invoices'][0]['payment_request'] is not None: break
    time.sleep(2)
paymentRequestStr = order['ln_invoices'][0]['payment_request']

print("#### DECODE INVOICE")
print(paymentRequestStr)
paymentRequestDecoded = lndDecodeInvoice(paymentRequestStr)
if paymentRequestDecoded is None: sys.exit()

print("#### CHECK INVOICE (EXTENSION)")
print("# is invoice not more then advertised: {0}".format(msatsNext))
print("# amount in invoice is: {0}".format(paymentRequestDecoded.num_msat))
if msatsNext < paymentRequestDecoded.num_msat:
    print("# invoice wants more the advertised -> EXIT")
    sys.exit(1)

print("#### PAY INVOICE")
payedInvoice = lndPayInvoice(paymentRequestStr)
if payedInvoice is None: sys.exit()
print(payedInvoice)

print("#### CHECK IF BRIDGE GOT EXTENDED")
while True:
    print("## Loop")
    bridge = apiGetBridgeStatus(session, shopUrl, bridge_id)
    if bridge is None: sys.exit()
    print(bridge)
    if bridge['suspend_after'] != bridge_suspendafter: break
    time.sleep(3)

print("BRIDGE GOT EXTENDED: {0} -> {1}".format(bridge_suspendafter, bridge['suspend_after']))

print("#### CHECK IF EXTENSION DURATION WAS CORRECT")
secondsLeftOld = secondsLeft(parseDate(bridge_suspendafter))
secondsLeftNew = secondsLeft(parseDate(bridge['suspend_after']))
secondsExtended = secondsLeftNew - secondsLeftOld
print("# secondsExtended({0}) promised({1})".format(secondsExtended, duration))
if secondsExtended < duration:
    print("CONTRACT BROKEN - duration delivered is too small")
    sys.exit()
else:
    print("OK")

if False: '''

###############
# MENU
###############

if sys.argv[1] == "menu":
    from dialog import Dialog
    d = Dialog(dialog="dialog",autowidgetsize=True)
    d.set_background_title("IP2TOR Subscription Service")
    code, tag = d.menu("OK, then you have two options:",
        choices=[("(1)", "Test HTTP REQUEST thru TOR PROXY"),
        ("(2)", "Make REST API - JSON request"),
        ("(3)", "TOML test"),
        ("(4)", "Working with .conf files")])
    if code == d.OK:
        if tag == "(1)":
            print("Needs: pip3 install pysocks\n")
            session = requests.session()
            session.proxies = {'http':  'socks5://127.0.0.1:9050', 'https': 'socks5://127.0.0.1:9050'}
            print("Call 'http://httpbin.org/ip' thru TOR proxy:\n")
            print(session.get("http://httpbin.org/ip").text)
            print("Call 'http://httpbin.org/ip' normal:\n")
            print(requests.get("http://httpbin.org/ip").text)
            print("Call 'https://shop.ip2t.org/api/v1/public/hosts/' thru TOR:\n")
            print(session.get("https://shop.ip2t.org/api/v1/public/hosts/").text)
        if tag == "(2)":

        if tag == "(3)":
            print ("Needs: pip3 install toml")
            import toml
            toml_string = """
            """
        if tag == "(4)":
            with open('/mnt/hdd/raspiblitz.conf', 'r') as myfile:
                data=myfile.read()
            print(data)
            import toml
            parsed_toml = toml.loads(data)
            print(parsed_toml)

    else:
        print("Cancel")
    '''