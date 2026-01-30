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
        response = session.post(f"{API_BASE}/subscription/status", headers=headers, json=payload, timeout=10)
        if response.status_code != 200:
            return None
        return response.json()
    except:
        return None

def renew_subscription(pubkey, server_id, duration):
    """Renew/extend an existing subscription."""
    try:
        headers = get_api_headers()
        payload = {
            "wgPublicKey": pubkey,
            "duration": duration,
            "serverId": server_id
        }
        response = session.post(f"{API_BASE}/subscription/renew", headers=headers, json=payload, timeout=10)
        if response.status_code != 200:
            response_text = response.text if hasattr(response, 'text') else str(response.content)
            raise BlitzError(f"HTTP {response.status_code}", {"response_text": response_text})
        return response.json()
    except requests.exceptions.RequestException as e:
        raise BlitzError("Renewal Failed", {"error": str(e)}, e)
    except Exception as e:
        raise BlitzError("Renewal Failed", {"error": str(e)}, e)

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
        raise BlitzError("Missing Key Fields", {"config_data": config_json})

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
# Use dev API for testing, production API when available
# Production: https://api.tunnelsats.com/api/public/v1
# Dev: https://dev2.tunnelsats.com/api/public/v1
API_BASE = "https://dev2.tunnelsats.com/api/public/v1"

def load_env_file():
    """Load environment variables from .tunnelsats.env file if it exists."""
    env_file = Path("/home/admin/raspiblitz/.tunnelsats.env")
    if not env_file.is_file():
        # Try alternative location
        env_file = Path("/home/admin/.tunnelsats.env")
    
    if env_file.is_file():
        try:
            with open(env_file, "r") as f:
                for line in f:
                    line = line.strip()
                    if line and not line.startswith("#") and "=" in line:
                        key, value = line.split("=", 1)
                        os.environ[key.strip()] = value.strip()
        except Exception:
            pass  # Silently fail if env file can't be read

def get_api_headers():
    # Load env file first (for dev API access)
    load_env_file()
    
    h = {"Content-Type": "application/json"}
    # Check for sensitive tokens in environment or file
    cf_id = os.environ.get("cfClientId")
    cf_secret = os.environ.get("cfClientSecret")
    if cf_id and cf_secret:
        h["CF-Access-Client-Id"] = cf_id
        h["CF-Access-Client-Secret"] = cf_secret
    return h

def get_servers():
    try:
        response = session.get(f"{API_BASE}/servers", headers=get_api_headers(), timeout=10)
        if response.status_code != 200:
            response_text = response.text if hasattr(response, 'text') else str(response.content)
            # Truncate very long error messages to avoid dialog issues
            if len(response_text) > 500:
                response_text = response_text[:500] + "... (truncated)"
            raise BlitzError(f"HTTP {response.status_code}", {"response_text": response_text})
        return response.json()
    except BlitzError:
        # Re-raise BlitzError as-is (already properly formatted)
        raise
    except requests.exceptions.RequestException as e:
        raise BlitzError("Fetch Failed", {"error": str(e)}, e)
    except Exception as e:
        raise BlitzError("Fetch Failed", {"error": str(e)}, e)

def show_status_dialog(d, subscription):
    """Show subscription status details."""
    server_id = subscription.get("server_id")
    pubkey = get_local_pubkey(server_id)
    
    status_text = f"Subscription: {subscription.get('name', 'TunnelSats VPN')}\n"
    status_text += f"Server: {server_id}\n"
    status_text += f"Created: {subscription.get('time_created', 'Unknown')}\n"
    status_text += f"Status: {'ACTIVE' if subscription.get('active') else 'INACTIVE'}\n\n"
    
    if pubkey:
        status_data = check_status(pubkey)
        if status_data:
            status_text += f"Live Status: {status_data.get('status', 'unknown')}\n"
            if status_data.get('expiry'):
                status_text += f"Expires: {status_data.get('expiry')}\n"
        else:
            status_text += "Live Status: Unable to fetch (offline/expired?)\n"
    else:
        status_text += "Config file missing - cannot check live status\n"
    
    d.msgbox(status_text, title="Subscription Status")

def handle_renew(d, subscription):
    """Handle subscription renewal flow."""
    server_id = subscription.get("server_id")
    pubkey = get_local_pubkey(server_id)
    
    if not pubkey:
        d.msgbox("Cannot renew: Config file missing. Please reinstall.", title="Error")
        return
    
    # Show current status
    status_data = check_status(pubkey)
    if status_data:
        status_msg = f"Current Status: {status_data.get('status', 'unknown')}\n"
        if status_data.get('expiry'):
            status_msg += f"Expires: {status_data.get('expiry')}\n\n"
    else:
        status_msg = "Unable to fetch current status.\n\n"
    
    status_msg += "Select renewal duration:"
    
    # Duration selection
    choices = [
        ("1", "1 Month"),
        ("3", "3 Months"),
        ("6", "6 Months"),
        ("12", "12 Months")
    ]
    code, duration = d.menu(status_msg, choices=choices, width=60, height=10, title="Renew Subscription")
    
    if code != d.OK:
        return
    
    # Create renewal order
    d.infobox("Requesting renewal... please wait.", title="TunnelSats")
    try:
        order_data = renew_subscription(pubkey, server_id, int(duration))
    except Exception as e:
        if isinstance(e, BlitzError):
            d.msgbox(f"Renewal failed:\n{e.short}", title="Error")
        else:
            d.msgbox(f"Renewal failed:\n{str(e)}", title="Error")
        return
    
    invoice = order_data.get("invoice")
    order_id = order_data.get("id")
    
    if not invoice:
        d.msgbox(f"No invoice received from API.\nResponse: {json.dumps(order_data)}", title="Error")
        return
    
    # Payment
    paid = False
    d.infobox("Attempting automatic payment via local node...", title="TunnelSats")
    try:
        if os.system(f"lncli payinvoice -f '{invoice}' --json") == 0:
            paid = True
        elif os.system(f"lightning-cli pay '{invoice}'") == 0:
            paid = True
    except:
        pass
    
    if not paid:
        d.msgbox(f"Automatic payment failed.\n\nPlease pay manually:\n\n{invoice}", title="Manual Payment Required")
    
    # Poll for confirmation
    d.infobox("Waiting for payment confirmation...", title="TunnelSats")
    config_json = None
    max_attempts = 30
    for attempt in range(max_attempts):
        try:
            headers = get_api_headers()
            res = session.get(f"{API_BASE}/subscription/status?id={order_id}", headers=headers, timeout=10)
            if res.status_code == 200:
                status_data = res.json()
                if status_data.get("status") in ["paid", "successful"]:
                    config_json = status_data
                    break
        except:
            pass
        time.sleep(5)
    
    if config_json:
        d.msgbox("Subscription renewed successfully!", title="Success")
    else:
        d.msgbox("Timeout waiting for confirmation.\nIf you paid, the renewal will activate automatically.", title="Timeout")

def handle_reinstall(d, subscription):
    """Reinstall/reconfigure the WireGuard setup."""
    server_id = subscription.get("server_id")
    conf_file = Path(f"/mnt/hdd/app-data/tunnelsats/tunnelsats_{server_id}.conf")
    
    if not conf_file.is_file():
        d.msgbox(f"Config file not found:\n{conf_file}\n\nCannot reinstall.", title="Error")
        return
    
    code = d.yesno(f"Reinstall TunnelSats with existing config?\n\nConfig: {conf_file}", 
                   title="Reinstall", yes_label="Yes", no_label="Cancel")
    if code != d.OK:
        return
    
    # Find core script
    core_script = Path("/home/admin/tunnelsats/scripts/tunnelsats.sh")
    if not core_script.is_file():
        core_script = Path("/home/hakuna/tunnelsats/scripts/tunnelsats.sh")
    
    if core_script.is_file():
        d.infobox("Triggering technical installation via tunnelsats.sh...", title="TunnelSats")
        os.system(f"sudo bash {core_script} install --config {conf_file}")
        d.msgbox("Reinstallation complete!", title="Success")
    else:
        d.msgbox(f"Core script not found.\nManual installation required:\nsudo bash tunnelsats.sh install --config {conf_file}", 
                 title="Manual Step Required")

def create_ssh_dialog():
    from dialog import Dialog
    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("TunnelSats Subscription")
    
    # Check if a subscription already exists
    existing_subs = []
    if Path(SUBSCRIPTIONS_FILE).is_file():
        try:
            os.system(f"sudo chown admin:admin {SUBSCRIPTIONS_FILE}")
            subs = toml.load(SUBSCRIPTIONS_FILE)
            if "subscriptions_tunnelsats" in subs:
                existing_subs = subs["subscriptions_tunnelsats"]
        except:
            pass

    # If subscription exists, show management menu
    if len(existing_subs) > 0:
        subscription = existing_subs[0]  # Use first subscription
        
        choices = [
            ("STATUS", "View Subscription Status"),
            ("RENEW", "Renew/Extend Subscription"),
            ("REINSTALL", "Reinstall WireGuard Config"),
            ("CANCEL", "Cancel Subscription"),
            ("NEW", "Create New Subscription (will replace existing)")
        ]
        
        code, action = d.menu(
            f"Existing subscription found: {subscription.get('name', 'TunnelSats VPN')}\n\nSelect an action:",
            choices=choices, width=60, height=12, title="TunnelSats Management")
        
        if code != d.OK:
            return
        
        if action == "STATUS":
            show_status_dialog(d, subscription)
        elif action == "RENEW":
            handle_renew(d, subscription)
        elif action == "REINSTALL":
            handle_reinstall(d, subscription)
        elif action == "CANCEL":
            sub_id = subscription.get("id")
            if sub_id:
                code = d.yesno(f"Cancel subscription: {subscription.get('name')}?\n\nThis will remove it from your subscriptions list.", 
                              title="Cancel Subscription", yes_label="Yes, Cancel", no_label="No")
                if code == d.OK:
                    subscriptions_cancel(sub_id)
                    d.msgbox("Subscription cancelled.", title="Cancelled")
        elif action == "NEW":
            # Continue to new subscription flow below
            pass
        else:
            return
        
        # If not creating new, return after management action
        if action != "NEW":
            return

    # PHASE 1: Fetch Servers
    try:
        servers_data = get_servers()
        servers = servers_data.get("servers", [])
    except BlitzError as e:
        # Extract a clean error message
        error_msg = e.short
        if hasattr(e, 'details') and e.details:
            # Add relevant details if available, but keep it short
            if 'response_text' in e.details:
                # Don't show full HTML error pages
                error_msg += "\n\n(Server returned an error)"
            elif 'error' in e.details:
                error_msg += f"\n\n{e.details['error']}"
        d.msgbox(f"Failed to fetch servers:\n\n{error_msg}", title="Error", width=70, height=10)
        return
    except Exception as e:
        error_msg = str(e)
        # Truncate very long error messages
        if len(error_msg) > 500:
            error_msg = error_msg[:500] + "... (truncated)"
        d.msgbox(f"Failed to fetch servers:\n\n{error_msg}", title="Error", width=70, height=10)
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
        response = session.post(f"{API_BASE}/subscription/create", headers=headers, json=payload, timeout=10)
        if response.status_code != 200:
            response_text = response.text if hasattr(response, 'text') else str(response.content)
            raise BlitzError(f"HTTP {response.status_code}", {"response_text": response_text})
        order_data = response.json()
    except Exception as e:
        if isinstance(e, BlitzError):
            d.msgbox(f"Failed to create order:\n{e.short}", title="Error")
        else:
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
    max_attempts = 30  # 150 seconds timeout (30 * 5s)
    for attempt in range(max_attempts):
        try:
            res = session.get(f"{API_BASE}/subscription/status?id={order_id}", headers=headers, timeout=10)
            if res.status_code == 200:
                status_data = res.json()
                if status_data.get("status") in ["paid", "successful"]:
                    config_json = status_data
                    break
        except requests.exceptions.Timeout:
            # Continue polling on timeout
            pass
        except requests.exceptions.RequestException:
            # Continue polling on network errors
            pass
        except Exception:
            # Continue polling on other errors
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
    
    # Show config content
    config_content = ""
    try:
        with open(conf_file, "r") as f:
            config_content = f.read()
    except:
        pass
    
    backup_msg = f"Success! TunnelSats subscription is active.\n\nConfiguration saved to:\n{conf_file}\n\nCRITICAL: Please save your config backup now!\n\n"
    if qr_text:
        backup_msg += f"QR Code:\n{qr_text}\n\n"
    if config_content:
        backup_msg += f"Config Content:\n{config_content}\n\n"
    backup_msg += "Have you saved the config backup?"
    
    # Force user acknowledgement
    code = d.yesno(backup_msg, title="Success / Backup Required", yes_label="Yes, I saved it", no_label="Show again")
    if code != d.OK:
        # Show again if user didn't confirm
        d.msgbox(backup_msg, title="Backup Required - Please Save Now")
    
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
