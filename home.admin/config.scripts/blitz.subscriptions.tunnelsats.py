import json
import logging
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
    print("# blitz.subscriptions.tunnelsats.py check-payment <order_id>")
    print("#")
    print("# Debug logging: Set TUNNELSATS_DEBUG=1 or DEBUG=1 to enable verbose logging")
    print("# Logs are saved to: /home/admin/raspiblitz/logs/tunnelsats.log")
    sys.exit(1)

#####################
# BASIC SETTINGS
#####################

# Config file locations:
# - Subscription metadata: /mnt/hdd/app-data/subscriptions/subscriptions.toml
# - WireGuard config files: /mnt/hdd/app-data/tunnelsats/tunnelsats_{server_id}.conf
# - Payment logs: See log locations below in log_payment_attempt()
SUBSCRIPTIONS_FILE = "/mnt/hdd/app-data/subscriptions/subscriptions.toml"
CONFIG_DIR = "/mnt/hdd/app-data/tunnelsats"

# explicitly set path because some blitzpy versions have wrong default
cfg_path = "/mnt/hdd/app-data/raspiblitz.conf"
if not os.path.exists(cfg_path):
    cfg_path = "/mnt/hdd/raspiblitz.conf"
cfg = RaspiBlitzConfig(abs_path=cfg_path)
cfg.reload()

session = requests.session()

#####################
# LOGGING SETUP
#####################

def setup_debug_logging():
    """Setup debug logging to /home/admin/raspiblitz/logs/tunnelsats.log if debug is enabled."""
    # Check for debug level via environment variable or config
    debug_enabled = (
        os.environ.get("TUNNELSATS_DEBUG", "").lower() in ("1", "true", "yes", "on") or
        os.environ.get("DEBUG", "").lower() in ("1", "true", "yes", "on") or
        cfg.get("tunnelsats_debug", "").lower() in ("1", "true", "yes", "on")
    )
    
    if not debug_enabled:
        # Return a no-op logger
        return logging.getLogger("tunnelsats")
    
    # Create logs directory if it doesn't exist
    log_dir = Path("/home/admin/raspiblitz/logs")
    log_dir.mkdir(parents=True, exist_ok=True)
    log_file = log_dir / "tunnelsats.log"
    
    # Setup logger
    logger = logging.getLogger("tunnelsats")
    logger.setLevel(logging.DEBUG)
    
    # Remove existing handlers to avoid duplicates
    logger.handlers.clear()
    
    # Create file handler
    file_handler = logging.FileHandler(log_file, mode='a', encoding='utf-8')
    file_handler.setLevel(logging.DEBUG)
    
    # Create formatter with detailed information
    formatter = logging.Formatter(
        '%(asctime)s [%(levelname)8s] %(name)s.%(funcName)s:%(lineno)d - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(formatter)
    
    logger.addHandler(file_handler)
    
    # Also log to stderr for immediate visibility
    console_handler = logging.StreamHandler(sys.stderr)
    console_handler.setLevel(logging.DEBUG)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    
    logger.debug(f"Debug logging enabled. Logging to: {log_file}")
    return logger

# Initialize logger
log = setup_debug_logging()

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

def format_invoice(invoice, line_length=70):
    """Format a long invoice string into readable lines."""
    if len(invoice) <= line_length:
        return invoice
    # Split into chunks
    lines = []
    for i in range(0, len(invoice), line_length):
        lines.append(invoice[i:i+line_length])
    return "\n".join(lines)

def get_qr_code_text(invoice):
    """Generate QR code as text using qrencode."""
    try:
        proc = subprocess.run(
            ["qrencode", "-t", "UTF8", "-m", "1"],
            input=invoice.encode(),
            capture_output=True,
            check=True,
            timeout=5
        )
        return proc.stdout.decode()
    except (subprocess.TimeoutExpired, subprocess.CalledProcessError, FileNotFoundError):
        return None

def log_payment_attempt(invoice, method, success, error_msg=None):
    """Log payment attempts for debugging."""
    log_file = Path("/tmp/tunnelsats_payment.log")
    timestamp = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    with open(log_file, "a") as f:
        status = "SUCCESS" if success else "FAILED"
        f.write(f"[{timestamp}] {method}: {status}\n")
        if error_msg:
            f.write(f"  Error: {error_msg}\n")
        f.write(f"  Invoice: {invoice[:50]}...\n")
        f.write(f"  Full logs available at:\n")
        f.write(f"    - LND: /mnt/hdd/app-data/lnd/logs/*/mainnet/lnd.log\n")
        f.write(f"    - CLN: /home/bitcoin/.lightning/*/cl.log\n")
        f.write(f"    - System: journalctl -u lnd or journalctl -u lightningd\n\n")
    
    # Also log to debug logger if enabled
    if success:
        log.debug(f"Payment attempt SUCCESS: method={method}, invoice={invoice[:50]}...")
    else:
        log.error(f"Payment attempt FAILED: method={method}, error={error_msg}, invoice={invoice[:50]}...")

def show_invoice_in_terminal(invoice, order_id, invoice_file):
    """Exit dialog and show invoice in terminal for easy copying."""
    # Clear screen and show invoice
    os.system("clear")
    print("=" * 80)
    print("TunnelSats - Manual Payment Required")
    print("=" * 80)
    print()
    print("Automatic payment failed or node not reachable.")
    print("Please pay the following invoice manually.")
    print()
    print("-" * 80)
    print("INVOICE (select and copy this text):")
    print("-" * 80)
    print(invoice)
    print("-" * 80)
    print()
    print(f"Invoice also saved to: {invoice_file}")
    print()
    
    # Show QR code in terminal if available
    qr_text = get_qr_code_text(invoice)
    if qr_text:
        print("QR Code (scan with your wallet):")
        print("-" * 80)
        print(qr_text)
        print("-" * 80)
        print()
    
    # Show QR on LCD if available
    try:
        os.system(f"sudo /home/admin/config.scripts/blitz.display.sh qr '{invoice}'")
    except:
        pass
    
    if order_id and order_id != "None":
        print("To check payment status and continue, run:")
        print(f"  python3 /home/admin/config.scripts/blitz.subscriptions.tunnelsats.py check-payment {order_id}")
        print()
    print("Or return to the menu and select 'Manage Subscription' again.")
    print()
    print("Press ENTER to return to menu...")
    input()
    
    # Hide QR code from LCD
    try:
        os.system("sudo /home/admin/config.scripts/blitz.display.sh hide")
    except:
        pass

def claim_subscription(order_id):
    """Claim/activate subscription after payment confirmation.
    
    POST /api/public/v1/subscription/claim
    Payload: {"id": order_id}
    """
    if not order_id or order_id == "None":
        log.error(f"Cannot claim subscription: invalid order_id={order_id}")
        return None
        
    log.debug(f"Claiming subscription for order_id={order_id}")
    try:
        headers = get_api_headers()
        payload = {"id": order_id}
        log.debug(f"Claim request: POST {API_BASE}/subscription/claim, payload={payload}")
        response = session.post(f"{API_BASE}/subscription/claim", headers=headers, json=payload, timeout=30)
        log.debug(f"Claim response: status={response.status_code}, headers={dict(response.headers)}")
        if response.status_code == 200:
            config_data = response.json()
            log.debug(f"Claim successful, received config with keys: {list(config_data.keys())}")
            log.debug(f"Full claim response: {json.dumps(config_data, indent=2)}")
            return config_data
        else:
            response_text = response.text if hasattr(response, 'text') else str(response.content)
            log.error(f"Claim failed: HTTP {response.status_code}, response={response_text[:500]}")
            eprint(f"Claim failed: HTTP {response.status_code} - {response_text[:200]}")
            return None
    except Exception as e:
        log.exception(f"Exception while claiming subscription: {e}")
        eprint(f"Error claiming subscription: {e}")
        return None

def _check_status_endpoint(order_id):
    """Internal helper to check status endpoint using GET for order IDs.
    
    API Behavior:
    - GET /subscription/status?id=<order_id> : Check order/payment status
    - POST /subscription/status with {"wgPublicKey": ...} : Check existing subscription status
    
    This function is specifically for checking ORDER status (payment confirmation),
    so it uses GET with query parameter.
    """
    headers = get_api_headers()
    
    # API requires GET with query param for checking Order ID
    log.debug(f"Checking status via GET for order_id={order_id}")
    try:
        response = session.get(f"{API_BASE}/subscription/status?id={order_id}", headers=headers, timeout=10)
        log.debug(f"GET status check response: status={response.status_code}")
        
        if response.status_code == 200:
            return response.json()
        
        response_text = response.text if hasattr(response, 'text') else str(response.content)
        log.warning(f"GET status check failed: HTTP {response.status_code}, response={response_text[:500]}")
    except Exception as e:
        log.exception(f"Exception during status check: {e}")
        
    return None


def check_payment_status(order_id):
    """Check if payment was made and return config if ready."""
    log.debug(f"Checking payment status for order_id={order_id}")
    try:
        status_data = _check_status_endpoint(order_id)
        if not status_data:
            return None
            
        log.debug(f"Status data: {json.dumps(status_data, indent=2)}")
        status = status_data.get("status", "").lower()
        log.debug(f"Payment status: {status}")
        if status in ["paid", "successful"]:
            log.info(f"Payment confirmed (status={status}), attempting to claim subscription")
            # Payment confirmed, now claim it to get the config
            config_data = claim_subscription(order_id)
            if config_data:
                log.info("Subscription claimed successfully")
                return config_data
            # If claim fails, return status data anyway (might already be claimed)
            log.warning("Claim failed but payment confirmed, returning status data")
            return status_data
        else:
            log.debug(f"Payment not yet confirmed, status={status}")
        return None
    except Exception as e:
        log.exception(f"Exception while checking payment status: {e}")
        eprint(f"Error checking payment status: {e}")
        return None

def get_local_pubkey(server_id=None):
    # Find config file
    # Config files are stored in: /mnt/hdd/app-data/tunnelsats/tunnelsats_{server_id}.conf
    conf_dir = Path(CONFIG_DIR)
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
        # Config files are stored in: /mnt/hdd/app-data/tunnelsats/tunnelsats_{server_id}.conf
        conf_file = Path(CONFIG_DIR) / f"tunnelsats_{server_id}.conf"
        if conf_file.is_file():
            print(f"# archiving config: {conf_file}")
            # Instead of deleting, we might want to archive it
            os.system(f"mv {conf_file} {conf_file}.bak")

    # 4. Persist
    with open(SUBSCRIPTIONS_FILE, "w") as f:
        f.write(toml.dumps(subs))
    
    print(json.dumps(subs, indent=2))

def save_config_and_persist(config_json, server_id):
    # Config files are stored in: /mnt/hdd/app-data/tunnelsats/tunnelsats_{server_id}.conf
    log.info(f"Saving config for server_id={server_id}")
    conf_dir = Path(CONFIG_DIR)
    conf_dir.mkdir(parents=True, exist_ok=True)
    conf_file = conf_dir / f"tunnelsats_{server_id}.conf"
    log.debug(f"Config file path: {conf_file}")
    
    # Extract data from API response
    # NOTE: Adjusting keys based on the structure observed in the bash script
    wg_data = config_json.get("wireguard", {})
    server_data = config_json.get("server", {})
    log.debug(f"Config JSON keys: wireguard={list(wg_data.keys())}, server={list(server_data.keys())}")
    
    priv_key = wg_data.get("privateKey")
    address = wg_data.get("address")
    dns = wg_data.get("dns")
    server_pub = server_data.get("publicKey")
    endpoint = server_data.get("endpoint")
    psk = wg_data.get("presharedKey")
    
    log.debug(f"Extracted config fields: address={address}, dns={dns}, endpoint={endpoint}, has_priv_key={bool(priv_key)}, has_server_pub={bool(server_pub)}, has_psk={bool(psk)}")

    if not all([priv_key, address, server_pub, endpoint]):
        missing = [k for k, v in [("privateKey", priv_key), ("address", address), ("publicKey", server_pub), ("endpoint", endpoint)] if not v]
        log.error(f"Missing required config fields: {missing}")
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
        log.debug("Cloudflare Access credentials loaded")
    else:
        log.debug("No Cloudflare Access credentials found")
    return h

def get_servers():
    log.debug(f"Fetching servers from {API_BASE}/servers")
    try:
        headers = get_api_headers()
        response = session.get(f"{API_BASE}/servers", headers=headers, timeout=10)
        log.debug(f"Server fetch response: status={response.status_code}, headers={dict(response.headers)}")
        if response.status_code != 200:
            response_text = response.text if hasattr(response, 'text') else str(response.content)
            log.error(f"Server fetch failed: HTTP {response.status_code}, response={response_text[:200]}")
            # Truncate very long error messages to avoid dialog issues
            if len(response_text) > 500:
                response_text = response_text[:500] + "... (truncated)"
            raise BlitzError(f"HTTP {response.status_code}", {"response_text": response_text})
        servers_data = response.json()
        log.debug(f"Successfully fetched {len(servers_data.get('servers', []))} servers")
        return servers_data
    except BlitzError:
        # Re-raise BlitzError as-is (already properly formatted)
        raise
    except requests.exceptions.RequestException as e:
        log.exception(f"Request exception while fetching servers: {e}")
        raise BlitzError("Fetch Failed", {"error": str(e)}, e)
    except Exception as e:
        log.exception(f"Unexpected error while fetching servers: {e}")
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
    # Try different possible field names for order_id - prioritize orderId (dev2 API standard)
    order_id = order_data.get('orderId') or order_data.get('id') or order_data.get('order_id') or order_data.get('orderID')
    
    # Validate order_id
    if not order_id:
        log.error(f"No order ID found in response. Response keys: {list(order_data.keys())}, Full response: {json.dumps(order_data, indent=2)}")
        d.msgbox(f"No order ID received from API.\nResponse: {json.dumps(order_data)}", title="Error")
        return
    
    if not invoice:
        d.msgbox(f"No invoice received from API.\nResponse: {json.dumps(order_data)}", title="Error")
        return
    
    # Payment
    paid = False
    
    # Pre-flight: Decode and log invoice details before attempting payment
    d.infobox("Preparing payment...", title="TunnelSats")
    try:
        # Try LND decode first
        log.info(f"Decoding invoice: {invoice[:30]}...")
        decode_proc = subprocess.run(
            ["lncli", "decodepayreq", invoice, "--json"],
            capture_output=True, text=True, timeout=5
        )
        if decode_proc.returncode == 0:
            decoded = json.loads(decode_proc.stdout)
            amount_sats = decoded.get('num_satoshis', decoded.get('num_msat', 0))
            if isinstance(amount_sats, str):
                amount_sats = int(amount_sats)
            log.info(f"INTENDING TO PAY: {amount_sats} sats to {decoded.get('destination', 'unknown')}")
        else:
            # Try CLN decode as fallback
            decode_proc = subprocess.run(
                ["lightning-cli", "decode", invoice],
                capture_output=True, text=True, timeout=5
            )
            if decode_proc.returncode == 0:
                decoded = json.loads(decode_proc.stdout)
                # CLN uses amount_msat
                amount_msat = decoded.get('amount_msat', 0)
                if isinstance(amount_msat, str) and amount_msat.endswith('msat'):
                    amount_msat = int(amount_msat[:-4])
                elif isinstance(amount_msat, str):
                    amount_msat = int(amount_msat)
                log.info(f"INTENDING TO PAY: {int(amount_msat/1000)} sats to {decoded.get('payee', 'unknown')}")
            else:
                log.warning(f"Could not decode invoice for pre-flight logging")
    except Exception as e:
        log.warning(f"Could not decode invoice for logging: {e}")
    
    d.infobox("Attempting automatic payment via local node...", title="TunnelSats")
    
    # Try LND first
    try:
        result = subprocess.run(
            ["lncli", "payinvoice", "-f", invoice, "--json"],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0:
            paid = True
            log_payment_attempt(invoice, "lncli", True)
        else:
            error_msg = result.stderr[:200] if result.stderr else "Unknown error"
            log_payment_attempt(invoice, "lncli", False, error_msg)
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        log_payment_attempt(invoice, "lncli", False, str(e))
    except Exception as e:
        log_payment_attempt(invoice, "lncli", False, str(e))
    
    # Try CLN if LND failed
    if not paid:
        try:
            result = subprocess.run(
                ["lightning-cli", "pay", invoice],
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0:
                paid = True
                log_payment_attempt(invoice, "lightning-cli", True)
            else:
                error_msg = result.stderr[:200] if result.stderr else "Unknown error"
                log_payment_attempt(invoice, "lightning-cli", False, error_msg)
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            log_payment_attempt(invoice, "lightning-cli", False, str(e))
        except Exception as e:
            log_payment_attempt(invoice, "lightning-cli", False, str(e))
    
    if not paid:
        # Save invoice to file for easy copying
        invoice_file = Path("/tmp/tunnelsats_invoice.txt")
        with open(invoice_file, "w") as f:
            f.write(invoice)
        
        # Save order_id for resuming
        order_file = Path("/tmp/tunnelsats_order_id.txt")
        with open(order_file, "w") as f:
            f.write(str(order_id))
        
        # Show log file location in dialog before exiting
        log_file = Path("/tmp/tunnelsats_payment.log")
        if log_file.exists():
            d.msgbox(f"Payment attempt logs saved to:\n{log_file}\n\nExiting to terminal for manual payment...", 
                    title="Payment Logs", width=70, height=10)
        
        # Exit dialog and show invoice in terminal
        d.msgbox("Exiting to terminal for manual payment.\n\nYou can copy the invoice from the terminal.", 
                title="Manual Payment Required", width=70, height=8)
        
        # Exit dialog and show in terminal
        show_invoice_in_terminal(invoice, order_id, invoice_file)
        
        # After user returns, check if payment was made
        d.infobox("Checking if payment was made...", title="TunnelSats")
        config_json = check_payment_status(order_id)
        
        if config_json:
            d.msgbox("Payment confirmed! Processing renewal...", title="Success")
        else:
            # Offer to check again or cancel
            code = d.yesno("Payment not yet confirmed.\n\nDo you want to check again?", 
                          title="Payment Status", yes_label="Check Again", no_label="Cancel")
            if code == d.OK:
                # Check one more time
                config_json = check_payment_status(order_id)
                if not config_json:
                    d.msgbox("Payment still not confirmed.\n\nYou can check later by running:\n" +
                            f"python3 /home/admin/config.scripts/blitz.subscriptions.tunnelsats.py check-payment {order_id}",
                            title="Not Confirmed", width=70, height=10)
                    return
            else:
                return
    else:
        # Automatic payment succeeded, poll for confirmation
        d.infobox("Waiting for payment confirmation...", title="TunnelSats")
        config_json = None
        max_attempts = 30
        for attempt in range(max_attempts):
            try:
                status_data = _check_status_endpoint(order_id)
                if status_data:
                    status = status_data.get("status", "").lower()
                    if status in ["paid", "successful"]:
                        # Payment confirmed, now claim it to get the config
                        config_data = claim_subscription(order_id)
                        if config_data and ("wireguard" in config_data or "server" in config_data):
                            config_json = config_data
                        else:
                            # If claim fails, use status data (might already be claimed)
                            config_json = status_data
                        break
            except:
                pass
            time.sleep(5)
        
        if not config_json:
            d.msgbox("Timeout waiting for confirmation.\nIf you paid, the renewal will activate automatically.", title="Timeout")
            return
    
    # Process renewal if payment confirmed
    if config_json:
        # Update subscription expiry in config
        d.msgbox("Subscription renewed successfully!", title="Success")

def handle_reinstall(d, subscription):
    """Reinstall/reconfigure the WireGuard setup."""
    server_id = subscription.get("server_id")
    # Config files are stored in: /mnt/hdd/app-data/tunnelsats/tunnelsats_{server_id}.conf
    conf_file = Path(CONFIG_DIR) / f"tunnelsats_{server_id}.conf"
    
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
    log.info("Starting TunnelSats subscription dialog")
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

    # Check for pending order (user might have exited during payment)
    pending_order_file = Path("/tmp/tunnelsats_order_id.txt")
    if pending_order_file.exists():
        try:
            with open(pending_order_file, "r") as f:
                pending_order_id = f.read().strip()
            
            code = d.yesno(
                "A pending payment was detected.\n\n"
                "Do you want to check if the payment was completed?",
                title="Pending Payment", yes_label="Check Payment", no_label="Continue"
            )
            if code == d.OK:
                d.infobox("Checking payment status...", title="TunnelSats")
                config_json = check_payment_status(pending_order_id)
                if config_json:
                    d.msgbox("Payment confirmed! Processing subscription...", title="Success")
                    # Get server_id from invoice file or ask user
                    # For now, we'll need to handle this in the create flow
                    # Remove pending order file
                    pending_order_file.unlink()
                else:
                    d.msgbox("Payment not yet confirmed.\n\nYou can check again later.", title="Not Confirmed")
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
    log.info(f"Creating subscription order: server_id={server_id}, duration={duration} months")
    d.infobox("Creating order... please wait.", title="TunnelSats")
    try:
        headers = get_api_headers()
        payload = {"serverId": server_id, "duration": int(duration)}
        log.debug(f"Order creation payload: {payload}")
        log.debug(f"Order creation URL: POST {API_BASE}/subscription/create")
        response = session.post(f"{API_BASE}/subscription/create", headers=headers, json=payload, timeout=10)
        log.debug(f"Order creation response: status={response.status_code}, content-type={response.headers.get('Content-Type', 'unknown')}")
        
        # Check if we got HTML instead of JSON (indicates wrong endpoint or routing issue)
        content_type = response.headers.get('Content-Type', '').lower()
        if 'text/html' in content_type or response.status_code == 404:
            response_text = response.text if hasattr(response, 'text') else str(response.content)
            log.error(f"Order creation failed: Got HTML response (404 or wrong endpoint). URL: {API_BASE}/subscription/create")
            log.error(f"Response preview: {response_text[:200]}")
            # Try to provide helpful error message
            if response.status_code == 404:
                error_msg = f"API endpoint not found (404).\n\nEndpoint: {API_BASE}/subscription/create\n\nThis endpoint may not be available on the dev2 server, or the API structure may have changed.\n\nPlease check the API documentation at https://api.tunnelsats.com/"
            else:
                error_msg = f"Unexpected response format (got HTML instead of JSON).\n\nStatus: {response.status_code}\n\nThis may indicate a routing issue or the endpoint path is incorrect."
            raise BlitzError("API Endpoint Error", {"response_text": error_msg, "status_code": response.status_code})
        
        if response.status_code != 200:
            response_text = response.text if hasattr(response, 'text') else str(response.content)
            log.error(f"Order creation failed: HTTP {response.status_code}, response={response_text[:500]}")
            raise BlitzError(f"HTTP {response.status_code}", {"response_text": response_text})
        order_data = response.json()
        log.debug(f"Full order creation response: {json.dumps(order_data, indent=2)}")
        # Try different possible field names for order_id - prioritize orderId (dev2 API standard)
        order_id = order_data.get('orderId') or order_data.get('id') or order_data.get('order_id') or order_data.get('orderID')
        log.info(f"Order created successfully: order_id={order_id}, invoice_length={len(order_data.get('invoice', ''))}, response_keys={list(order_data.keys())}")
    except Exception as e:
        log.exception(f"Exception during order creation: {e}")
        if isinstance(e, BlitzError):
            d.msgbox(f"Failed to create order:\n{e.short}", title="Error")
        else:
            d.msgbox(f"Failed to create order:\n{str(e)}", title="Error")
        return

    invoice = order_data.get("invoice")
    # Try different possible field names for order_id - prioritize orderId (dev2 API standard)
    order_id = order_data.get('orderId') or order_data.get('id') or order_data.get('order_id') or order_data.get('orderID')
    
    # Validate order_id
    if not order_id:
        log.error(f"No order ID found in renewal response. Response keys: {list(order_data.keys())}, Full response: {json.dumps(order_data, indent=2)}")
        d.msgbox(f"No order ID received from API.\nResponse: {json.dumps(order_data)}", title="Error")
        return
    
    if not invoice:
        d.msgbox(f"No invoice received from API.\nResponse: {json.dumps(order_data)}", title="Error")
        return

    # PHASE 5: Payment
    paid = False
    
    # Pre-flight: Decode and log invoice details before attempting payment
    d.infobox("Preparing payment...", title="TunnelSats")
    try:
        # Try LND decode first
        log.info(f"Decoding invoice: {invoice[:30]}...")
        decode_proc = subprocess.run(
            ["lncli", "decodepayreq", invoice, "--json"],
            capture_output=True, text=True, timeout=5
        )
        if decode_proc.returncode == 0:
            decoded = json.loads(decode_proc.stdout)
            amount_sats = decoded.get('num_satoshis', decoded.get('num_msat', 0))
            if isinstance(amount_sats, str):
                amount_sats = int(amount_sats)
            log.info(f"INTENDING TO PAY: {amount_sats} sats to {decoded.get('destination', 'unknown')}")
        else:
            # Try CLN decode as fallback
            decode_proc = subprocess.run(
                ["lightning-cli", "decode", invoice],
                capture_output=True, text=True, timeout=5
            )
            if decode_proc.returncode == 0:
                decoded = json.loads(decode_proc.stdout)
                # CLN uses amount_msat
                amount_msat = decoded.get('amount_msat', 0)
                if isinstance(amount_msat, str) and amount_msat.endswith('msat'):
                    amount_msat = int(amount_msat[:-4])
                elif isinstance(amount_msat, str):
                    amount_msat = int(amount_msat)
                log.info(f"INTENDING TO PAY: {int(amount_msat/1000)} sats to {decoded.get('payee', 'unknown')}")
            else:
                log.warning(f"Could not decode invoice for pre-flight logging")
    except Exception as e:
        log.warning(f"Could not decode invoice for logging: {e}")
    
    d.infobox("Attempting automatic payment via local node...", title="TunnelSats")
    
    # Try LND first
    try:
        result = subprocess.run(
            ["lncli", "payinvoice", "-f", invoice, "--json"],
            capture_output=True,
            text=True,
            timeout=30
        )
        if result.returncode == 0:
            paid = True
            log_payment_attempt(invoice, "lncli", True)
        else:
            error_msg = result.stderr[:200] if result.stderr else "Unknown error"
            log_payment_attempt(invoice, "lncli", False, error_msg)
    except (subprocess.TimeoutExpired, FileNotFoundError) as e:
        log_payment_attempt(invoice, "lncli", False, str(e))
    except Exception as e:
        log_payment_attempt(invoice, "lncli", False, str(e))
    
    # Try CLN if LND failed
    if not paid:
        try:
            result = subprocess.run(
                ["lightning-cli", "pay", invoice],
                capture_output=True,
                text=True,
                timeout=30
            )
            if result.returncode == 0:
                paid = True
                log_payment_attempt(invoice, "lightning-cli", True)
            else:
                error_msg = result.stderr[:200] if result.stderr else "Unknown error"
                log_payment_attempt(invoice, "lightning-cli", False, error_msg)
        except (subprocess.TimeoutExpired, FileNotFoundError) as e:
            log_payment_attempt(invoice, "lightning-cli", False, str(e))
        except Exception as e:
            log_payment_attempt(invoice, "lightning-cli", False, str(e))

    if not paid:
        # Save invoice to file for easy copying
        invoice_file = Path("/tmp/tunnelsats_invoice.txt")
        with open(invoice_file, "w") as f:
            f.write(invoice)
        
        # Save order_id for resuming
        order_file = Path("/tmp/tunnelsats_order_id.txt")
        with open(order_file, "w") as f:
            f.write(str(order_id))
        
        # Show log file location in dialog before exiting
        log_file = Path("/tmp/tunnelsats_payment.log")
        if log_file.exists():
            d.msgbox(f"Payment attempt logs saved to:\n{log_file}\n\nExiting to terminal for manual payment...", 
                    title="Payment Logs", width=70, height=10)
        
        # Exit dialog and show invoice in terminal
        d.msgbox("Exiting to terminal for manual payment.\n\nYou can copy the invoice from the terminal.", 
                title="Manual Payment Required", width=70, height=8)
        
        # Exit dialog and show in terminal
        show_invoice_in_terminal(invoice, order_id, invoice_file)
        
        # After user returns, check if payment was made
        d.infobox("Checking if payment was made...", title="TunnelSats")
        config_json = check_payment_status(order_id)
        
        if config_json:
            d.msgbox("Payment confirmed! Processing subscription...", title="Success")
        else:
            # Offer to check again or cancel
            code = d.yesno("Payment not yet confirmed.\n\nDo you want to check again?", 
                          title="Payment Status", yes_label="Check Again", no_label="Cancel")
            if code == d.OK:
                # Check one more time
                config_json = check_payment_status(order_id)
                if not config_json:
                    d.msgbox("Payment still not confirmed.\n\nYou can check later by running:\n" +
                            f"python3 /home/admin/config.scripts/blitz.subscriptions.tunnelsats.py check-payment {order_id}\n\n" +
                            "Or return to the menu and select 'Manage Subscription' again.",
                            title="Not Confirmed", width=70, height=12)
                    return
            else:
                return
    else:
        # Automatic payment succeeded, poll for confirmation
        d.infobox("Payment detected. Polling for configuration...", title="TunnelSats")
        config_json = None
        max_attempts = 30  # 150 seconds timeout (30 * 5s)
        for attempt in range(max_attempts):
            try:
                status_data = _check_status_endpoint(order_id)
                if status_data:
                    status = status_data.get("status", "").lower()
                    if status in ["paid", "successful"]:
                        # Payment confirmed, now claim it to get the config
                        config_data = claim_subscription(order_id)
                        if config_data and ("wireguard" in config_data or "server" in config_data):
                            config_json = config_data
                        else:
                            # If claim fails, use status data (might already be claimed)
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

def handle_check_payment(order_id):
    """Handle check-payment command - check status and continue if paid."""
    if not order_id or order_id == "None":
        print("Error: Invalid order_id. Please provide a valid order ID.")
        print("You can find it in: /tmp/tunnelsats_order_id.txt")
        sys.exit(1)
    
    from dialog import Dialog
    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("TunnelSats - Check Payment")
    
    d.infobox("Checking payment status...", title="TunnelSats")
    config_json = check_payment_status(order_id)
    
    if config_json:
        # Check if config_json has wireguard config (from claim) or just status
        has_config = "wireguard" in config_json or "server" in config_json
        
        if has_config:
            # Payment confirmed and config received - need server_id
            d.msgbox("Payment confirmed! Processing subscription...", title="Success")
            
            # Try to get server_id from saved order file or existing subscriptions
            server_id = None
            
            # Try to get from saved invoice file metadata or existing subscriptions
            if Path(SUBSCRIPTIONS_FILE).is_file():
                try:
                    os.system(f"sudo chown admin:admin {SUBSCRIPTIONS_FILE}")
                    subs = toml.load(SUBSCRIPTIONS_FILE)
                    tunnelsats_subs = subs.get("subscriptions_tunnelsats", [])
                    if tunnelsats_subs:
                        server_id = tunnelsats_subs[0].get("server_id")
                except:
                    pass
            
            # If still no server_id, try to extract from config_json
            if not server_id and "server" in config_json:
                server_id = config_json.get("server", {}).get("id")
            
            if not server_id:
                d.msgbox("Cannot determine server_id. Please use 'Manage Subscription' from the menu to complete setup.", title="Error")
                return
            
            try:
                conf_file, subscription = save_config_and_persist(config_json, server_id)
                d.msgbox("Subscription activated successfully!", title="Success")
            except Exception as e:
                d.msgbox(f"Failed to save configuration:\n{str(e)}", title="Error")
        else:
            # Status shows paid but no config yet - might need to claim
            d.msgbox("Payment confirmed but configuration not ready yet.\n\nPlease wait a moment and try again, or return to the menu.", title="Processing")
    else:
        d.msgbox("Payment not yet confirmed.\n\nPlease wait a moment and try again.", title="Not Confirmed")

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
    elif sys.argv[1] == "check-payment":
        if len(sys.argv) < 3:
            print("Usage: check-payment <order_id>")
            sys.exit(1)
        handle_check_payment(sys.argv[2])
    else:
        print("Unknown command: {0}".format(sys.argv[1]))
        sys.exit(1)
