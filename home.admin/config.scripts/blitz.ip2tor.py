#!/usr/bin/python3

import sys
import locale
import requests
import json
import math

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# manage ip2tor subscriptions for raspiblitz")
    print("# blitz.ip2tor.py menu")
    sys.exit(1)

# basic settings
locale.setlocale(locale.LC_ALL, '')

# TODO: use TOR proxy session
# TODO: check is still works when shopurl is an onion address
def apiGetHosts(shopurl):

    print("# apiGetHosts")
    hosts=[]

    # make HTTP request
    try:
        response = requests.get("https://"+shopurl+"/api/v1/public/hosts/")
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

# TODO: use TOR proxy session
def apiPlaceOrder(shopurl, hostid, toraddressWithPort):

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
        response = requests.post("https://"+shopurl+"/api/v1/public/order/", data=postData)
    except Exception as e:
        print("error='FAILED HTTP REQUEST'")
        return
    if response.status_code != 201:
        print("error='FAILED HTTP CODE ({0})'".format(response.status_code))
        return

    # parse & validate data
    try:
        jData = json.loads(response.content)
    except Exception as e:
        print("error='FAILED JSON PARSING'")
        return

    print(jData)

apiGetHosts("shop.ip2t.org")
#apiPlaceOrder("shop.ip2t.org", "fc747bae-6dbb-498d-89c2-f2445210c8f8", "facebookcorewwwi.onion:80")

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