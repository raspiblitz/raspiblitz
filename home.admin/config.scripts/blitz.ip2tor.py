#!/usr/bin/python3

import sys
import locale
import requests
import json
import math

import codecs, grpc, os
from lndlibs import rpc_pb2 as ln
from lndlibs import rpc_pb2_grpc as lnrpc

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# manage ip2tor subscriptions for raspiblitz")
    print("# blitz.ip2tor.py menu")
    sys.exit(1)

# basic settings
locale.setlocale(locale.LC_ALL, '')
USE_TOR=False
LND_IP="192.168.178.95"
LND_ADMIN_MACAROON_PATH=""

# TODO: check is still works when shopurl is an onion address
def apiGetHosts(session, shopurl):

    print("# apiGetHosts")
    hosts=[]

    # make HTTP request
    try:
        response = session.get("https://{0}/api/v1/public/hosts/".format(shopurl))
    except Exception as e:
        print("error='FAILED HTTP REQUEST'")
        return
    if response.status_code != 200:
        print("error='FAILED HTTP CODE ({0})'".format(response.status_code))
        return
    
    # parse & validate data
    try:
        jData = json.loads(response.content)
    except Exception as e:
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
          print("error='PARSING HOST ENTRY'")
          return    

        print("({0}) {1} ({2} hours, first: {3} sats, next: {4} sats)".format(idx, hostEntry['name'].ljust(20), hostEntry['tor_bridge_duration_hours'], hostEntry['tor_bridge_price_initial_sats'], hostEntry['tor_bridge_price_extension_sats']))
        #print(hostEntry)
        hosts.append(hostEntry)
    
    print("# found {0} valid torbridge hosts".format(len(hosts)))
    return hosts

def apiPlaceOrder(session, shopurl, hostid, toraddressWithPort):

    print("# apiPlaceOrder")

    postData={
        'product': "tor_bridge",
        'host_id': hostid,
        'tos_accepted': True,
        'comment': 'test',
        'target': toraddressWithPort,
        'public_key': ''
    }
    try:
        response = session.post("https://{0}/api/v1/public/order/".format(shopurl), data=postData)
    except Exception as e:
        print("error='FAILED HTTP REQUEST'")
        return
    if response.status_code != 201:
        print("error='FAILED HTTP CODE ({0}) != 201'".format(response.status_code))
        return

    # parse & validate data
    try:
        jData = json.loads(response.content)
        if len(jData['id']) == 0:
            print("error='MISSING ID'")
            return
    except Exception as e:
        print("error='FAILED JSON PARSING'")
        return

    return jData['id']


def apiGetOrder(session, shopurl, orderid):

    print("# apiGetOrder")

    # make HTTP request
    try:
        response = session.get("https://{0}/api/v1/public/pos/{1}/".format(shopurl,orderid))
    except Exception as e:
        print("error='FAILED HTTP REQUEST'")
        return
    if response.status_code != 200:
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
        print("error='FAILED JSON PARSING'")
        return

    return jData

def lndDecodeInvoice(lnInvoiceString):

    macaroon = codecs.encode(open('LND_DIR/data/chain/bitcoin/simnet/admin.macaroon', 'rb').read(), 'hex')
    os.environ['GRPC_SSL_CIPHER_SUITES'] = 'HIGH+ECDSA'
    cert = open('LND_DIR/tls.cert', 'rb').read()
    ssl_creds = grpc.ssl_channel_credentials(cert)
    channel = grpc.secure_channel('192.168.178.95:10009', ssl_creds)
    stub = rpcstub.LightningStub(channel)
    request = lnrpc.PayReqString(
        pay_req=lnInvoiceString,
    )
    response = stub.DecodePayReq(request, metadata=[('macaroon', macaroon)])
    print(response)

lndDecodeInvoice("lnbc300n1p0v37m5pp5xncvgrphrp9p5h52c7luqf2tkzq0v3v6ae3f9q08vrnevux9xwtsdraxgukxwpj8pjnvtfkvsun2tf5x56rgtfcxq6kgtfe89nxywpsxq6rsdfhvgazq5z08gsxxdf3xs6nvdn994jnyd33956rydfk95urjcfh943nwd338q6kydmyxgurqcqzpgxqrrsssp5ka6qqqnmuxu35783m8n8avsafmc4pasnh365pgj20vpj2r735xrq9qy9qsq956lq8l66rrt6nec2s20uwh4dcxwgt3ndqyt2pdc02axpdk3xt4k9pjpev0f9tfff0xe3g9eqp3tvl690a8n6u8dwweqm2azycj0utcpz8pkeu")

session = requests.session()
#session.proxies = {'http':  'socks5://127.0.0.1:9050', 'https': 'socks5://127.0.0.1:9050'}
#apiGetHosts(session, "shop.ip2t.org")
#orderid = apiPlaceOrder(session, "shop.ip2t.org", "fc747bae-6dbb-498d-89c2-f2445210c8f8", "facebookcorewwwi.onion:80")
#apiGetOrder(session, "shop.ip2t.org", orderid)

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