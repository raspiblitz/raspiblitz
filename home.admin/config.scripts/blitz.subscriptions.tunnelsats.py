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
    print("# blitz.subscriptions.tunnelsats.py check-payment <payment_hash>")
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
    """Setup logging to /home/admin/raspiblitz/logs/tunnelsats.log."""
    cfg_debug = getattr(cfg, "tunnelsats_debug", "") if cfg else ""
    debug_requested = (
        os.environ.get("TUNNELSATS_DEBUG", "").lower() in ("1", "true", "yes", "on") or
        os.environ.get("DEBUG", "").lower() in ("1", "true", "yes", "on") or
        str(cfg_debug).lower() in ("1", "true", "yes", "on")
    )

    logger = logging.getLogger("tunnelsats")
    logger.propagate = False # Avoid double logging
    logger.handlers.clear()
    
    # Always set to at least INFO, DEBUG if requested
    level = logging.DEBUG if debug_requested else logging.INFO
    logger.setLevel(level)
    
    log_dir = Path("/home/admin/raspiblitz/logs")
    try:
        log_dir.mkdir(parents=True, exist_ok=True)
        log_file = log_dir / "tunnelsats.log"
        
        file_handler = logging.FileHandler(log_file, mode='a', encoding='utf-8')
        file_handler.setLevel(level)
        
        formatter = logging.Formatter(
            '%(asctime)s [%(levelname)s] %(name)s:%(lineno)d - %(message)s',
            datefmt='%Y-%m-%d %H:%M:%S'
        )
        file_handler.setFormatter(formatter)
        logger.addHandler(file_handler)
    except Exception as e:
        # Fallback to stderr only if file writing fails
        print(f"Warning: Could not setup log file: {e}", file=sys.stderr)

    # Always log to stderr (console) as well
    console_handler = logging.StreamHandler(sys.stderr)
    console_handler.setLevel(level)
    console_handler.setFormatter(logging.Formatter('%(levelname)s: %(message)s'))
    logger.addHandler(console_handler)
    
    if debug_requested:
        logger.debug("Verbose debug logging enabled")
        
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

def claim_subscription(payment_hash, order_id=None):
    """Claim/activate subscription after payment confirmation.
    
    POST /api/public/v1/subscription/claim
    Payload: {"orderId": order_id, "paymentHash": payment_hash}
    """
    if not payment_hash or payment_hash == "None":
        log.error(f"Cannot claim subscription: invalid payment_hash={payment_hash}")
        return None
        
    log.info(f"Attempting to claim subscription for payment_hash={payment_hash[:8]}..., order_id={order_id}")
    try:
        headers = get_api_headers()
        # API requires identification. Best to send both if available.
        payload = {"paymentHash": payment_hash}
        if order_id:
            payload["orderId"] = order_id
        
        log.debug(f"Claim request: POST {API_BASE}/subscription/claim, payload={payload}")
        response = session.post(f"{API_BASE}/subscription/claim", headers=headers, json=payload, timeout=30)
        
        log.debug(f"Claim response status: {response.status_code}")
        if response.status_code == 200:
            config_data = response.json()
            # If server generates keys, they are in config_data (Easy Mode)
            log.debug(f"Claim successful, received data with keys: {list(config_data.keys())}")
            return config_data
        else:
            response_text = response.text if hasattr(response, 'text') else str(response.content)
            log.error(f"Claim failed with HTTP {response.status_code}: {response_text[:500]}")
            # Log exact response for debugging
            log.debug(f"Full claim error response: {response_text}")
            return None
    except Exception as e:
        log.exception(f"Exception while claiming subscription: {e}")
        return None



def _check_status_endpoint(payment_hash):
    """Internal helper to check payment status using GET with paymentHash path parameter.
    
    API Behavior (from OpenAPI spec):
    - GET /api/public/v1/subscription/{paymentHash} : Check payment status / heal
    
    This function checks if payment was confirmed. The paymentHash comes from
    the order creation response.
    """
    headers = get_api_headers()
    
    # API uses paymentHash as path parameter, NOT query parameter
    url = f"{API_BASE}/subscription/{payment_hash}"
    log.debug(f"Checking status via GET for payment_hash={payment_hash}")
    log.debug(f"Status check URL: {url}")
    try:
        response = session.get(url, headers=headers, timeout=10)
        log.debug(f"GET status check response: status={response.status_code}")
        
        if response.status_code == 200:
            return response.json()
        
        response_text = response.text if hasattr(response, 'text') else str(response.content)
        log.warning(f"GET status check failed: HTTP {response.status_code}, response={response_text[:500]}")
    except Exception as e:
        log.exception(f"Exception during status check: {e}")
        
    return None


def check_payment_status(payment_hash, order_id=None):
    """Check if payment was made and return config if ready.
    
    Args:
        payment_hash: The paymentHash from order creation (used for status check)
        order_id: The orderId from order creation (used for claim, optional - falls back to payment_hash)
    """
    log.debug(f"Checking payment status for payment_hash={payment_hash}, order_id={order_id}")
    try:
        status_data = _check_status_endpoint(payment_hash)
        if not status_data:
            return None
            
        log.debug(f"Status data: {json.dumps(status_data, indent=2)}")
        status = status_data.get("status", "").lower()
        log.debug(f"Payment status: {status}")
        if status in ["paid", "successful"]:
            log.info(f"Payment confirmed (status={status}), attempting to claim subscription")
            # Payment confirmed, now claim it to get the config
            config_data = claim_subscription(payment_hash, order_id)
            if config_data:
                log.info("Subscription claimed successfully, merging with status data")
                # Merge status_data into config_data to preserve metadata like serverId
                merged_data = status_data.copy()
                merged_data.update(config_data)
                return merged_data
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
    conf_file = Path(CONFIG_DIR) / f"tunnelsats_{server_id}.conf"
    log.debug(f"Config file path: {conf_file}")

    
    # Extract data from API response
    # Extract data from API response
    # Support multiple formats: 'wireguard', 'peer', 'interface', or 'config' for client config info
    # Support 'server' or 'server_info' for server connection info
    wg_data = config_json.get("wireguard") or config_json.get("peer") or config_json.get("interface") or config_json.get("config") or {}
    server_data = config_json.get("server") or config_json.get("server_info") or {}
    
    # If config_json itself has the keys (flat structure)
    if not wg_data or "privateKey" not in wg_data:
        if isinstance(config_json, dict) and ("privateKey" in config_json or "private_key" in config_json):
            wg_data = config_json
            
    # Handle the case where 'config' might be a string (full .conf content)
    if isinstance(wg_data, str):
        log.debug("wg_data is a string, attempting to parse as inline config")
        # Extract fields using regex
        priv_match = re.search(r"PrivateKey\s*=\s*(\S+)", wg_data, re.IGNORECASE)
        addr_match = re.search(r"Address\s*=\s*(\S+)", wg_data, re.IGNORECASE)
        pub_match = re.search(r"PublicKey\s*=\s*(\S+)", wg_data, re.IGNORECASE)
        psk_match = re.search(r"PresharedKey\s*=\s*(\S+)", wg_data, re.IGNORECASE)
        dns_match = re.search(r"DNS\s*=\s*(\S+)", wg_data, re.IGNORECASE)
        end_match = re.search(r"Endpoint\s*=\s*(\S+)", wg_data, re.IGNORECASE)
        
        priv_key = priv_match.group(1) if priv_match else None
        address = addr_match.group(1) if addr_match else None
        server_pub = pub_match.group(1) if pub_match else None
        psk = psk_match.group(1) if psk_match else None
        dns = dns_match.group(1) if dns_match else "1.1.1.1"
        endpoint = end_match.group(1) if end_match else None
    else:
        # Support various field name variations (camelCase, snake_case, PascalCase)
        priv_key = wg_data.get("privateKey") or wg_data.get("private_key") or wg_data.get("PrivateKey")
        address = wg_data.get("address") or wg_data.get("Address")
        dns = wg_data.get("dns") or wg_data.get("DNS") or "1.1.1.1"
        server_pub = server_data.get("publicKey") or server_data.get("public_key") or server_data.get("PublicKey") or wg_data.get("publicKey")
        endpoint = server_data.get("endpoint") or server_data.get("Endpoint") or server_data.get("domain") or wg_data.get("endpoint")
        psk = wg_data.get("presharedKey") or wg_data.get("preshared_key") or wg_data.get("PresharedKey")
    
    # Final fallbacks from server_data if not found in wg_data (dict or string)
    if not server_pub:
        server_pub = server_data.get("publicKey") or server_data.get("public_key") or server_data.get("PublicKey")
    if not endpoint:
        endpoint = server_data.get("endpoint") or server_data.get("Endpoint") or server_data.get("domain")
    
    log.debug(f"Extracted fields: address={address}, dns={dns}, endpoint={endpoint}, has_priv_key={bool(priv_key)}, has_pub_key={bool(server_pub)}")


    if not all([priv_key, address, server_pub, endpoint]):
        missing = []
        if not priv_key: missing.append("privateKey")
        if not address: missing.append("address")
        if not server_pub: missing.append("publicKey")
        if not endpoint: missing.append("endpoint")
        
        log.error(f"Missing required config fields: {missing}")
        # Identify if we are in the 'isProvisioned' state without keys
        if config_json.get("isProvisioned") and not priv_key:
            log.warning("Subscription is marked as provisioned but no private key was returned. This usually happens when the 'claim' endpoint fails or is called multiple times.")
            
        # MANDATORY DIAGNOSTIC: Print to stderr so user sees it even without file logs
        eprint("\n--- DIAGNOSTIC DATA ---")
        eprint(f"Missing: {missing}")
        eprint(f"Full Response: {json.dumps(config_json, indent=2)}")
        eprint("--- END DIAGNOSTIC ---\n")
        
        raise BlitzError("Missing Key Fields", {"missing": missing, "received_keys": list(config_json.keys())})



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
    def safe_write_file(path, data, mode=0o644):
        """Try to write file as user, fallback to sudo if permission denied."""
        path = str(path)
        current_uid = os.getuid()
        current_gid = os.getgid()
        try:
            # Try normal write
            with open(path, "w") as f:
                f.write(data)
            os.chmod(path, mode)
            log.debug(f"Successfully wrote {path} as user (UID={current_uid}, GID={current_gid})")
            return True
        except Exception as e:
            log.debug(f"Permission denied for {path} as user (UID={current_uid}, GID={current_gid}): {e}. Trying via sudo.")
            temp_path = f"/tmp/tunnelsats_write_{os.getpid()}"
            try:
                # Write to a temp file we definitely have access to
                with open(temp_path, "w") as f:
                    f.write(data)
                
                # Move and set permissions via sudo
                perm_str = format(mode, 'o')
                os.system(f"sudo mv {temp_path} {path}")
                os.system(f"sudo chown admin:admin {path}")
                os.system(f"sudo chmod {perm_str} {path}")
                
                if os.path.exists(path):
                    log.debug(f"Successfully wrote {path} via sudo fallback")
                    return True
                return False
            except Exception as e2:
                log.error(f"Failed to write {path} even with sudo: {e2}")
                return False

    def ensure_dir(path):
        """Ensure directory exists, try as user then sudo."""
        path = str(path)
        current_uid = os.getuid()
        if os.path.exists(path):
            return True
        try:
            os.makedirs(path, exist_ok=True)
            log.debug(f"Successfully created directory {path} as user (UID={current_uid})")
            return True
        except Exception as e:
            log.debug(f"Could not create directory {path} as user UID={current_uid} ({e}), trying sudo")
            os.system(f"sudo mkdir -p {path}")
            os.system(f"sudo chown admin:admin {path}")
            return os.path.exists(path)


    # Ensure directories exist
    if not ensure_dir(CONFIG_DIR):
        log.error(f"Failed to ensure directory exists: {CONFIG_DIR}")
        raise BlitzError("Directory Creation Failed", {"path": str(CONFIG_DIR)})
    
    # Save config file
    if not safe_write_file(conf_file, content, mode=0o600):
        raise BlitzError("Write Failed", {"path": str(conf_file)})
    
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
    subs_dir = os.path.dirname(SUBSCRIPTIONS_FILE)
    ensure_dir(subs_dir)
    
    # Ensure file exists before loading
    if not os.path.exists(SUBSCRIPTIONS_FILE):
        safe_write_file(SUBSCRIPTIONS_FILE, "")

    subs = {}
    if Path(SUBSCRIPTIONS_FILE).is_file():
        try:
            # Try reading as current user
            subs = toml.load(SUBSCRIPTIONS_FILE)
        except PermissionError:
            # Try reading via sudo/cat
            try:
                toml_content = subprocess.check_output(["sudo", "cat", SUBSCRIPTIONS_FILE]).decode()
                subs = toml.loads(toml_content)
            except:
                subs = {}
        except:
            subs = {}
    
    if "subscriptions_tunnelsats" not in subs:
        subs["subscriptions_tunnelsats"] = []
    
    # Check if subscription already exists and update it, or add new one
    exists = False
    for i, s in enumerate(subs["subscriptions_tunnelsats"]):
        if s.get("server_id") == server_id:
            subs["subscriptions_tunnelsats"][i] = subscription
            exists = True
            break
    
    if not exists:
        subs["subscriptions_tunnelsats"].append(subscription)
    
    if not safe_write_file(SUBSCRIPTIONS_FILE, toml.dumps(subs), mode=0o644):
        log.error(f"Failed to persist subscription metadata to {SUBSCRIPTIONS_FILE}")
        # Don't raise here, config is already saved
    
    log.info(f"Subscription persisted to {SUBSCRIPTIONS_FILE}")
    return conf_file, subscription


def show_success_guidance(conf_file, server_id):
    """Show detailed installation instructions after success."""
    qr_text = ""
    if Path("/tmp/tunnelsats_qr.txt").is_file():
        try:
            with open("/tmp/tunnelsats_qr.txt", "r") as f:
                qr_text = f.read()
        except:
            pass
            
    instructions = f"""Subscription activated successfully!

Your configuration has been saved to:
{conf_file}

NEXT STEPS:
1) Exit this menu (select 'Finish' or press ESC)
2) On the command line, run the verified installer:

"""
    
    installer_path = Path(CONFIG_DIR) / "tunnelsats.sh"
    if installer_path.is_file():
        instructions += f"sudo bash {installer_path} install --config {conf_file}\n"
    else:
        instructions += f"wget https://raw.githubusercontent.com/Tunnelsats/tunnelsats/main/scripts/tunnelsats.sh\n"
        instructions += f"sudo bash tunnelsats.sh install --config {conf_file}\n"

    instructions += """
--- CONFIG BACKUP (CRITICAL) ---
Please copy/save this configuration now!
"""
    if qr_text:
        instructions += f"\nQR Code:\n{qr_text}\n"
    
    try:
        with open(conf_file, "r") as f:
            instructions += f"\nFile Content:\n{f.read()}\n"
    except:
        pass

    d.msgbox(instructions, title="Success & Next Steps", width=75, height=30)


def ensure_installer(d):
    """Ensure tunnelsats.sh is downloaded and verified in CONFIG_DIR."""
    installer_path = Path(CONFIG_DIR) / "tunnelsats.sh"
    
    # Check if already exists
    if installer_path.is_file():
        log.debug(f"Installer already exists at {installer_path}")
        return installer_path

    ensure_dir(CONFIG_DIR)
    d.infobox("Downloading and verifying TunnelSats installer...", title="Maintenance")
    
    # We use the pinned version from the official guide for security/verification
    # Guide: https://tunnelsats.com/guide#step-2-install-tunnelsats-software
    script_url = "https://raw.githubusercontent.com/Tunnelsats/tunnelsats/5050d8b2e17ebed5584483d44ce808c749f3320c/scripts/tunnelsats.sh"
    expected_hash = "bd32dbb8362b15bdad035b4bfda1b3d348f410a50edb8e2a41997d82153a0d92"
    
    tmp_path = f"/tmp/tunnelsats_{os.getpid()}.sh"
    try:
        log.info(f"Downloading installer from {script_url}")
        r = session.get(script_url, timeout=30)
        r.raise_for_status()
        with open(tmp_path, "w") as f:
            f.write(r.text)
            
        # Verify hash
        log.debug("Verifying installer checksum")
        import hashlib
        sha256_hash = hashlib.sha256()
        with open(tmp_path, "rb") as f:
            for byte_block in iter(lambda: f.read(4096), b""):
                sha256_hash.update(byte_block)
        
        actual_hash = sha256_hash.hexdigest()
        if actual_hash != expected_hash:
            log.error(f"Checksum mismatch! Expected {expected_hash}, got {actual_hash}")
            d.msgbox(f"Security Alert: Installer checksum mismatch!\n\nExpected: {expected_hash}\nActual: {actual_hash}\n\nAborting for safety.", title="Security Error")
            if os.path.exists(tmp_path): os.remove(tmp_path)
            return None
            
        # Move to CONFIG_DIR as admin
        os.system(f"sudo mv {tmp_path} {installer_path}")
        os.system(f"sudo chown admin:admin {installer_path}")
        os.system(f"sudo chmod +x {installer_path}")
        
        log.info(f"Installer successfully downloaded and verified at {installer_path}")
        return installer_path
        
    except Exception as e:
        log.error(f"Failed to download installer: {e}")
        d.msgbox(f"Failed to download installer:\n{e}", title="Error")
        if os.path.exists(tmp_path): os.remove(tmp_path)
        return None




# API Settings
# Use dev API for testing, production API when available
# Production: https://tunnelsats.com/api/public/v1
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
    
    # Use yesno with custom labels to provide the "LIVE" option
    code = d.yesno(status_text, title="Subscription Status", yes_label="OK", no_label="LIVE", width=65, height=15)
    return code

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
    # Get paymentHash - this is needed for status checks (API uses GET /subscription/{paymentHash})
    payment_hash = order_data.get('paymentHash') or order_data.get('payment_hash')
    
    log.info(f"Renewal order details: order_id={order_id}, payment_hash={payment_hash[:20] if payment_hash else None}...")
    
    # Validate we have what we need - paymentHash is required for status checks
    if not payment_hash:
        log.error(f"No paymentHash found in renewal response. Response keys: {list(order_data.keys())}, Full response: {json.dumps(order_data, indent=2)}")
        d.msgbox(f"No paymentHash received from API.\nResponse keys: {list(order_data.keys())}", title="Error")
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
        config_json = check_payment_status(payment_hash, order_id)
        
        if config_json:
            d.msgbox("Payment confirmed! Processing renewal...", title="Success")
        else:
            # Offer to check again or cancel
            code = d.yesno("Payment not yet confirmed.\n\nDo you want to check again?", 
                          title="Payment Status", yes_label="Check Again", no_label="Cancel")
            if code == d.OK:
                # Check one more time
                config_json = check_payment_status(payment_hash, order_id)
                if not config_json:
                    d.msgbox("Payment still not confirmed.\n\nYou can check later by running:\n" +
                            f"python3 /home/admin/config.scripts/blitz.subscriptions.tunnelsats.py check-payment {payment_hash}",
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
                status_data = _check_status_endpoint(payment_hash)
                if status_data:
                    status = status_data.get("status", "").lower()
                    if status in ["paid", "successful"]:
                        # Payment confirmed, now claim it to get the config
                        config_data = claim_subscription(payment_hash, order_id)
                        if config_data and any(k in config_data for k in ["wireguard", "server", "peer", "config", "interface"]):
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
    conf_file = Path(CONFIG_DIR) / f"tunnelsats_{server_id}.conf"
    
    if not conf_file.is_file():
        d.msgbox(f"Config file not found:\n{conf_file}\n\nCannot reinstall.", title="Error")
        return
    
    code = d.yesno(f"Reinstall TunnelSats with existing config?\n\nConfig: {conf_file}", 
                   title="Reinstall", yes_label="Yes", no_label="Cancel")
    if code != d.OK:
        return
    
    # Ensure installer is present
    installer = ensure_installer(d)
    if not installer:
        return

    d.infobox("Triggering technical installation via tunnelsats.sh...", title="TunnelSats")
    os.system(f"sudo bash {installer} install --config {conf_file}")
    d.msgbox("Reinstallation complete!", title="Success")

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
    pending_payment_hash_file = Path("/tmp/tunnelsats_payment_hash.txt")
    if pending_order_file.exists() and pending_payment_hash_file.exists():
        try:
            with open(pending_order_file, "r") as f:
                pending_order_id = f.read().strip()
            with open(pending_payment_hash_file, "r") as f:
                pending_payment_hash = f.read().strip()
            
            code = d.yesno(
                "A pending payment was detected.\n\n"
                "Do you want to check if the payment was completed?",
                title="Pending Payment", yes_label="Check Payment", no_label="Continue"
            )
            if code == d.OK:
                d.infobox("Checking payment status...", title="TunnelSats")
                config_json = check_payment_status(pending_payment_hash, pending_order_id)
                if config_json:
                    d.msgbox("Payment confirmed! Processing subscription...", title="Success")
                    # Get server_id from invoice file or ask user
                    # For now, we'll need to handle this in the create flow
                    # Remove pending order files
                    pending_order_file.unlink()
                    pending_payment_hash_file.unlink()
                else:
                    d.msgbox("Payment not yet confirmed.\n\nYou can check again later.", title="Not Confirmed")
        except:
            pass


    # If subscription exists, show management menu
    if len(existing_subs) > 0:
        subscription = existing_subs[0]  # Use first subscription
        
        while True:
            choices = [
                ("STATUS", "View Subscription Status"),
                ("RENEW", "Renew/Extend Subscription"),
                ("REINSTALL", "Reinstall WireGuard Config"),
                ("NEW", "Create New Subscription (will replace existing)")
            ]
            
            code, action = d.menu(
                f"Existing subscription found: {subscription.get('name', 'TunnelSats VPN')}\n\nSelect an action:",
                choices=choices, width=60, height=12, title="TunnelSats Management")
            
            if code != d.OK:
                return
            
            if action == "STATUS":
                # Show status dialog and check for "LIVE" request
                # d.OK is "OK", d.EXTRA or d.CANCEL (from no_label="LIVE") is "LIVE"
                # In pythondialog, yesno returns d.OK (Yes) or d.CANCEL (No/Extra)
                res = show_status_dialog(d, subscription)
                if res != d.OK:
                    # User clicked "LIVE"
                    installer_path = Path(CONFIG_DIR) / "tunnelsats.sh"
                    if installer_path.is_file():
                        os.system(f"sudo bash {installer_path} status")
                    else:
                        d.msgbox("Installer script not found. Please reinstall to fix.", title="Error")
            elif action == "RENEW":
                handle_renew(d, subscription)
            elif action == "REINSTALL":
                handle_reinstall(d, subscription)
            elif action == "NEW":
                # Exit loop and continue to new subscription flow below
                break
            else:
                return
            
            # Re-load subscriptions in case they changed (e.g. after NEW)
            # (Though NEW breaks the loop, other actions might update it)
            if Path(SUBSCRIPTIONS_FILE).is_file():
                try:
                    subs = toml.load(SUBSCRIPTIONS_FILE)
                    if "subscriptions_tunnelsats" in subs and subs["subscriptions_tunnelsats"]:
                        subscription = subs["subscriptions_tunnelsats"][0]
                except:
                    pass

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
    # Get paymentHash - this is needed for status checks (API uses GET /subscription/{paymentHash})
    payment_hash = order_data.get('paymentHash') or order_data.get('payment_hash')
    
    log.info(f"Order details: order_id={order_id}, payment_hash={payment_hash[:20] if payment_hash else None}...")
    
    # Validate we have what we need - paymentHash is required for status checks
    if not payment_hash:
        log.error(f"No paymentHash found in order response. Response keys: {list(order_data.keys())}, Full response: {json.dumps(order_data, indent=2)}")
        d.msgbox(f"No paymentHash received from API.\nResponse keys: {list(order_data.keys())}", title="Error")
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
        
        # Save order_id and payment_hash for resuming
        order_file = Path("/tmp/tunnelsats_order_id.txt")
        with open(order_file, "w") as f:
            f.write(str(order_id))
        
        # Save payment_hash - this is needed for status checks
        payment_hash_file = Path("/tmp/tunnelsats_payment_hash.txt")
        with open(payment_hash_file, "w") as f:
            f.write(str(payment_hash))

        
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
        config_json = check_payment_status(payment_hash, order_id)
        
        if config_json:
            d.msgbox("Payment confirmed! Processing subscription...", title="Success")
        else:
            # Offer to check again or cancel
            code = d.yesno("Payment not yet confirmed.\n\nDo you want to check again?", 
                          title="Payment Status", yes_label="Check Again", no_label="Cancel")
            if code == d.OK:
                # Check one more time
                config_json = check_payment_status(payment_hash, order_id)
                if not config_json:
                    d.msgbox("Payment still not confirmed.\n\nYou can check later by running:\n" +
                            f"python3 /home/admin/config.scripts/blitz.subscriptions.tunnelsats.py check-payment {payment_hash}\n\n" +
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
                status_data = _check_status_endpoint(payment_hash)
                if status_data:
                    status = status_data.get("status", "").lower()
                    if status in ["paid", "successful"]:
                        # Payment confirmed, now claim it to get the config

                        config_data = claim_subscription(payment_hash, order_id)
                        if config_data and any(k in config_data for k in ["wireguard", "server", "peer", "config", "interface"]):
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

    # PHASE 7: Success & Next Steps
    try:
        conf_file, subscription = save_config_and_persist(config_json, server_id)
        show_success_guidance(conf_file, server_id)
    except Exception as e:
        d.msgbox(f"Failed to persist configuration:\n{str(e)}", title="Error")
        return

def handle_check_payment(payment_hash):
    """Handle check-payment command - check status and continue if paid.
    
    Args:
        payment_hash: The paymentHash from order creation (used for status check)
    """
    if not payment_hash or payment_hash == "None":
        print("Error: Invalid payment_hash. Please provide a valid payment hash.")
        print("You can find it in: /tmp/tunnelsats_payment_hash.txt")
        sys.exit(1)
    
    # Try to get order_id from temp file (for claim)
    order_id = None
    order_file = Path("/tmp/tunnelsats_order_id.txt")
    if order_file.exists():
        try:
            with open(order_file, "r") as f:
                order_id = f.read().strip()
        except:
            pass
    
    from dialog import Dialog
    d = Dialog(dialog="dialog", autowidgetsize=True)
    d.set_background_title("TunnelSats - Check Payment")
    
    d.infobox("Checking payment status...", title="TunnelSats")
    config_json = check_payment_status(payment_hash, order_id)

    
    if config_json:
        # Verify we actually have the config (keys) before proceeding
        # The 'config_json' might just be the status response if claim failed
        has_essential_keys = any(k in config_json for k in ["wireguard", "peer", "interface", "config", "fullConfig"])
        
        if has_essential_keys:
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
            if not server_id:
                server_id = config_json.get("serverId") or config_json.get("server_id")
                if not server_id and "server" in config_json:
                    s_data = config_json.get("server", {})
                    server_id = s_data.get("id") or s_data.get("serverId")
                    if not server_id and "domain" in s_data:
                        # Extract first part of domain as fallback (e.g. 'de2' from 'de2.tunnelsats.com')
                        server_id = s_data["domain"].split(".")[0]

            
            if not server_id:
                d.msgbox("Cannot determine server_id. Please use 'Manage Subscription' from the menu to complete setup.", title="Error")
                return
            
            try:
                conf_file, subscription = save_config_and_persist(config_json, server_id)
                show_success_guidance(conf_file, server_id)
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
            print("Usage: check-payment <payment_hash>")
            sys.exit(1)
        handle_check_payment(sys.argv[2])
    else:
        print("Unknown command: {0}".format(sys.argv[1]))
        sys.exit(1)
