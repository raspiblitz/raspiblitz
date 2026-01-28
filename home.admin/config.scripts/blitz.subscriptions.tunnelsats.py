import json
import os
import subprocess
import sys
import time
import re
from datetime import datetime
from pathlib import Path

import requests
import toml

# add blitzpy to path (relative for dev environments)
script_dir = os.path.dirname(os.path.abspath(__file__))
# prioritize local BlitzPy if it exists (for repo testing)
local_blitzpy = os.path.abspath(os.path.join(script_dir, '..', 'BlitzPy'))
if os.path.exists(local_blitzpy):
    sys.path.insert(0, local_blitzpy)

from blitzpy import RaspiBlitzConfig
from blitzpy.exceptions import BlitzError

#####################
# SCRIPT INFO
#####################

# display config script info
if len(sys.argv) <= 1 or sys.argv[1] == "-h" or sys.argv[1] == "help":
    print("# manage TunnelSats VPN subscriptions for raspiblitz")
    print("# blitz.subscriptions.tunnelsats.py create-ssh-dialog")
    print("# blitz.subscriptions.tunnelsats.py subscriptions-list")
    print("# blitz.subscriptions.tunnelsats.py subscription-cancel <id>")
    sys.exit(1)

#####################
# BASIC SETTINGS
#####################

SUBSCRIPTIONS_FILE = "/mnt/hdd/app-data/subscriptions/subscriptions.toml"

# explicitly set path because some blitzpy versions have wrong default
cfg_path = "/mnt/hdd/app-data/raspiblitz.conf"
if not os.path.exists(cfg_path):
    cfg_path = "/mnt/hdd/raspiblitz.conf"
cfg = RaspiBlitzConfig(abs_path=cfg_path)
cfg.reload()

session = requests.session()

#####################
# HELPER FUNCTIONS
#####################

def eprint(*args, **kwargs):
    print(*args, file=sys.stderr, **kwargs)

def handleException(e):
    if isinstance(e, BlitzError):
        print("error='{0}'".format(e.short))
    else:
        eprint(e)
        print("error='{0}'".format(str(e)))
    sys.exit(1)

def get_local_pubkey(server_id=None):
    # Find config file
    conf_dir = Path("/mnt/hdd/app-data/tunnelsats")
    if server_id:
        conf_file = conf_dir / f"tunnelsats_{server_id}.conf"
    else:
        # Get first one available
        conf_files = list(conf_dir.glob("tunnelsats_*.conf"))
        if not conf_files:
            return None
        conf_file = conf_files[0]

    if not conf_file.is_file():
        return None
    
    # Extract PrivateKey
    with open(conf_file, "r") as f:
        content = f.read()
    
    match = re.search(r"^PrivateKey\s*=\s*(.*)$", content, re.MULTILINE)
    if not match:
        return None
    
    priv_key = match.group(1).strip()
    
    # Derive PubKey using wg tool
    try:
        proc = subprocess.run(["wg", "pubkey"], input=priv_key.encode(), capture_output=True, check=True)
        return proc.stdout.decode().strip()
    except:
        return None

def check_status(pubkey):
    try:
        payload = {"wgPublicKey": pubkey}
        headers = get_api_headers()
        # NOTE: Using the same endpoint pattern as the bash script
        response = session.post(f"{API_BASE}/subscription/status", headers=headers, json=payload)
        if response.status_code != 200:
            return None
        return response.json()
    except:
        return None

def subscriptions_list():
    try:
        if Path(SUBSCRIPTIONS_FILE).is_file():
            os.system(f"sudo chown admin:admin {SUBSCRIPTIONS_FILE}")
            subs = toml.load(SUBSCRIPTIONS_FILE)
        else:
            subs = {}
        
        tunnelsats_subs = subs.get("subscriptions_tunnelsats", [])
        
        # Add live status to each sub if possible
        for sub in tunnelsats_subs:
            server_id = sub.get("server_id")
            pubkey = get_local_pubkey(server_id)
            if pubkey:
                status_data = check_status(pubkey)
                if status_data:
                    sub["live_status"] = status_data.get("status", "unknown")
                    sub["expiry"] = status_data.get("expiry", "unknown")
                else:
                    sub["live_status"] = "offline/expired?"
            else:
                sub["live_status"] = "config missing"

        print(json.dumps(tunnelsats_subs, indent=2))
    except Exception as e:
        handleException(e)

def subscriptions_cancel(s_id):
    print(f"# subscription_cancel({s_id})")
    
    # 1. Load subscriptions
    os.system(f"sudo chown admin:admin {SUBSCRIPTIONS_FILE}")
    if not Path(SUBSCRIPTIONS_FILE).is_file():
        return
        
    subs = toml.load(SUBSCRIPTIONS_FILE)
    if "subscriptions_tunnelsats" not in subs:
        return

    # 2. Find and remove
    new_list = []
    removed_sub = None
    for sub in subs["subscriptions_tunnelsats"]:
        if sub["id"] != s_id:
            new_list.append(sub)
        else:
            removed_sub = sub
    
    subs["subscriptions_tunnelsats"] = new_list
    
    # 3. Handle technical side-effects (Optional but recommended)
    if removed_sub:
        server_id = removed_sub.get("server_id")
        conf_file = Path(f"/mnt/hdd/app-data/tunnelsats/tunnelsats_{server_id}.conf")
        if conf_file.is_file():
            print(f"# archiving config: {conf_file}")
            # Instead of deleting, we might want to archive it
            os.system(f"mv {conf_file} {conf_file}.bak")

    # 4. Persist
    with open(SUBSCRIPTIONS_FILE, "w") as f:
        f.write(toml.dumps(subs))
    
    print(json.dumps(subs, indent=2))

def save_config_and_persist(config_json, server_id):
    conf_dir = Path("/mnt/hdd/app-data/tunnelsats")
    conf_dir.mkdir(parents=True, exist_ok=True)
    conf_file = conf_dir / f"tunnelsats_{server_id}.conf"
    
    # Extract data from API response
    # NOTE: Adjusting keys based on the structure observed in the bash script
    wg_data = config_json.get("wireguard", {})
    server_data = config_json.get("server", {})
    
    priv_key = wg_data.get("privateKey")
    address = wg_data.get("address")
    dns = wg_data.get("dns")
    server_pub = server_data.get("publicKey")
    endpoint = server_data.get("endpoint")
    psk = wg_data.get("presharedKey")

    if not all([priv_key, address, server_pub, endpoint]):
        raise BlitzError("Missing Key Fields", f"Config data incomplete: {json.dumps(config_json)}")

    content = f"""[Interface]
PrivateKey = {priv_key}
Address = {address}
DNS = {dns}

[Peer]
PublicKey = {server_pub}
PresharedKey = {psk}
Endpoint = {endpoint}
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
"""
    with open(conf_file, "w") as f:
        f.write(content)
    
    os.chmod(conf_file, 0o600)
    
    # Store in subscriptions.toml
    subscription = {
        "type": "tunnelsats-v1",
        "id": f"tunnelsats_{server_id}",
        "active": True,
        "name": f"TunnelSats {server_id}",
        "server_id": server_id,
        "time_created": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "description": f"TunnelSats VPN via {server_id}"
    }
    
    # Load and update subscriptions
    os.system(f"sudo chown admin:admin {SUBSCRIPTIONS_FILE}")
    if Path(SUBSCRIPTIONS_FILE).is_file():
        subs = toml.load(SUBSCRIPTIONS_FILE)
    else:
        subs = {}
    
    if "subscriptions_tunnelsats" not in subs:
        subs["subscriptions_tunnelsats"] = []
    
    subs["subscriptions_tunnelsats"].append(subscription)
    
    with open(SUBSCRIPTIONS_FILE, "w") as f:
        f.write(toml.dumps(subs))
    
    return conf_file, subscription

# API Settings
# NOTE: Using the same dev API as the bash script for now
API_BASE = "https://dev2.tunnelsats.com/api/public/v1"

def get_api_headers():
    headers = {"Content-Type": "application/json"}
    # Check for sensitive tokens in environment or file
    cf_id = os.environ.get("cfClientId")
    cf_secret = os.environ.get("cfClientSecret")
    if cf_id and cf_secret:
        headers["CF-Access-Client-Id"] = cf_id
        headers["CF-Access-Client-Secret"] = cf_secret
    return headers

def get_servers():
    try:
        response = session.get(f"{API_BASE}/servers", headers=get_api_headers())
        if response.status_code != 200:
            raise BlitzError(f"HTTP {response.status_code}", response.text)
        return response.json()
    except Exception as e:
        raise BlitzError("Fetch Failed", str(e))

def create_ssh_dialog():
    from dialog import Dialog
    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("TunnelSats Subscription")
    
    # Check if a subscription already exists (limit to one for now)
    # This logic can be refined later if needed
    existing_subs = []
    if Path(SUBSCRIPTIONS_FILE).is_file():
        subs = toml.load(SUBSCRIPTIONS_FILE)
        if "subscriptions_tunnelsats" in subs:
            existing_subs = subs["subscriptions_tunnelsats"]

    if len(existing_subs) > 0:
        d.msgbox("You already have an active TunnelSats subscription.\nMultiple subscriptions are not supported yet.", title="Info")
        return

    # PHASE 1: Fetch Servers
    try:
        servers_data = get_servers()
        servers = servers_data.get("servers", [])
    except Exception as e:
        d.msgbox(f"Failed to fetch servers:\n{str(e)}", title="Error")
        return

    if not servers:
        d.msgbox("No TunnelSats servers are currently available.", title="Error")
        return

    # PHASE 2: Selection
    choices = []
    for s in servers:
        choices.append((s["id"], f"{s['city']} ({s['country']}) [{s['status']}]"))

    code, server_id = d.menu(
        "\nSelect a server location to proceed:",
        choices=choices, width=60, height=12, title="Select Location")

    if code != d.OK:
        return

    # PHASE 3: Duration Selection
    choices = [
        ("1", "1 Month"),
        ("3", "3 Months"),
        ("6", "6 Months"),
        ("12", "12 Months")
    ]
    code, duration = d.menu(
        f"\nSelected Location: {server_id}\n\nChoose subscription duration:",
        choices=choices, width=60, height=10, title="Select Duration")

    if code != d.OK:
        return

    # PHASE 4: Order Creation
    d.infobox("Creating order... please wait.", title="TunnelSats")
    try:
        headers = get_api_headers()
        payload = {"serverId": server_id, "duration": int(duration)}
        response = session.post(f"{API_BASE}/subscription/create", headers=headers, json=payload)
        if response.status_code != 200:
            raise BlitzError(f"HTTP {response.status_code}", response.text)
        order_data = response.json()
    except Exception as e:
        d.msgbox(f"Failed to create order:\n{str(e)}", title="Error")
        return

    invoice = order_data.get("invoice")
    order_id = order_data.get("id")

    if not invoice:
        d.msgbox(f"No invoice received from API.\nResponse: {json.dumps(order_data)}", title="Error")
        return

    # PHASE 5: Payment
    # Display invoice and QR code if possible
    qr_file = "/tmp/tunnelsats_qr.png"
    qr_text_file = "/tmp/tunnelsats_qr.txt"
    try:
        os.system(f"qrencode -o {qr_file} '{invoice}'")
        os.system(f"qrencode -t UTF8 '{invoice}' > {qr_text_file}")
    except:
        pass

    msg = f"Please pay the following BOLT11 invoice for your TunnelSats subscription:\n\n{invoice}\n\nWaiting for payment confirmation..."
    
    # Using a msgbox or custom dialog to show qr if possible.
    # For now, we'll try to pay automatically using local node like the bash script did.
    paid = False
    
    # Attempt automatic payment
    d.infobox("Attempting automatic payment via local node...", title="TunnelSats")
    try:
        # Check for LND
        if os.system(f"lncli payinvoice -f '{invoice}' --json") == 0:
            paid = True
        # Check for CLN if LND failed
        elif os.system(f"lightning-cli pay '{invoice}'") == 0:
            paid = True
    except:
        pass

    if not paid:
        # If auto-payment fails, show invoice and wait
        d.msgbox(f"Automatic payment failed or node not reachable.\n\nPlease pay manually:\n\n{invoice}", title="Manual Payment Required")

    # PHASE 6: Polling
    d.infobox("Payment detected or manual wait. Polling for configuration...", title="TunnelSats")
    config_json = None
    for _ in range(30): # 150 seconds timeout
        try:
            res = session.get(f"{API_BASE}/subscription/status?id={order_id}", headers=headers)
            if res.status_code == 200:
                status_data = res.json()
                if status_data.get("status") in ["paid", "successful"]:
                    config_json = status_data
                    break
        except:
            pass
        time.sleep(5)

    if not config_json:
        d.msgbox("Timeout waiting for payment confirmation.\nIf you paid, the subscription will activate automatically.", title="Timeout")
        return

    # PHASE 7: Success!
    try:
        conf_file, subscription = save_config_and_persist(config_json, server_id)
    except Exception as e:
        d.msgbox(f"Failed to persist configuration:\n{str(e)}", title="Error")
        return

    # User Backup Reminder (mimicking bash script)
    qr_text = ""
    if Path("/tmp/tunnelsats_qr.txt").is_file():
        with open("/tmp/tunnelsats_qr.txt", "r") as f:
            qr_text = f.read()

    d.msgbox(f"Success! TunnelSats subscription is active.\n\nConfiguration saved to:\n{conf_file}\n\nCRITICAL: Please save your config backup now!\n\n{qr_text}", title="Success / Backup")
    
    # PHASE 8: Handoff to core script
    # Look for the core script in standard locations
    core_script = Path("/home/admin/tunnelsats/scripts/tunnelsats.sh")
    if not core_script.is_file():
        core_script = Path("/home/hakuna/tunnelsats/scripts/tunnelsats.sh")

    if core_script.is_file():
        d.infobox("Triggering technical installation via tunnelsats.sh...", title="TunnelSats")
        # We use sudo as the bash script did
        os.system(f"sudo bash {core_script} install --config {conf_file}")
    else:
        d.msgbox(f"Core script not found.\nManual installation required using:\n{conf_file}", title="Manual Step Required")

if __name__ == "__main__":
    import sys
    if len(sys.argv) < 2:
        print("Usage: blitz.subscriptions.tunnelsats.py <command>")
        sys.exit(1)
        
    if sys.argv[1] == "create-ssh-dialog":
        create_ssh_dialog()
    elif sys.argv[1] == "subscriptions-list":
        subscriptions_list()
    elif sys.argv[1] == "subscription-cancel":
        if len(sys.argv) < 3:
            print("Usage: subscription-cancel <id>")
            sys.exit(1)
        subscriptions_cancel(sys.argv[2])
    else:
        print("Unknown command: {0}".format(sys.argv[1]))
        sys.exit(1)
