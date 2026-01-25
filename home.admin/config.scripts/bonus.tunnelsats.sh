#!/bin/bash

# TunnelSats Bonus Script for RaspiBlitz
# handles subscription management (Pay -> Provision -> Persist)

# --- Configuration & Defaults ---
CONFIG_DIR="/mnt/hdd/app-data/tunnelsats"
ENV_FILE="/home/hakuna/.tunnelsats.env"
API_BASE="https://dev2.tunnelsats.com"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Load sensitive tokens if available
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

# --- Utility Functions ---

print_info() { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Populates global CURL_FLAGS array
set_api_flags() {
    local url="$1"
    CURL_FLAGS=("-H" "Content-Type: application/json")
    if [[ "$url" == *"dev2.tunnelsats.com"* ]] && [ -n "$cfClientId" ] && [ -n "$cfClientSecret" ]; then
        CURL_FLAGS+=("-H" "CF-Access-Client-Id: $cfClientId")
        CURL_FLAGS+=("-H" "CF-Access-Client-Secret: $cfClientSecret")
    fi
}

check_dependencies() {
    local deps=("jq" "curl" "wg" "whiptail")
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "Missing dependency: $dep"
            exit 1
        fi
    done
    if ! command -v "qrencode" &> /dev/null; then
        print_info "qrencode not found. QR code backup will be skipped."
    fi
}

# --- Core Functions ---

# Fetch available servers from API
get_servers() {
    set_api_flags "$API_BASE"
    local response
    response=$(curl -s "${CURL_FLAGS[@]}" "${API_BASE}/setup/servers")
    
    if [ -z "$response" ] || [[ "$response" == *"Access Denied"* ]]; then
        print_error "Failed to fetch servers from API (Check tokens/URL)."
        return 1
    fi
    
    echo "$response"
}

# Create a new subscription order
create_order() {
    local server_id="$1"
    print_info "Creating order for $server_id..."
    
    set_api_flags "$API_BASE"
    local payload="{\"id\":\"$server_id\"}"
    
    local response
    response=$(curl -s "${CURL_FLAGS[@]}" -X POST -d "$payload" "${API_BASE}/setup/order")
    
    if echo "$response" | jq -e '.error' > /dev/null; then
        local msg=$(echo "$response" | jq -r '.message')
        print_error "Order Error: $msg"
        return 1
    fi
    
    echo "$response"
}

# Pay the BOLT11 invoice using local node
pay_invoice() {
    local invoice="$1"
    print_info "Detecting Lightning node..."
    
    if command -v lncli &> /dev/null; then
        print_info "Attempting payment via LND..."
        lncli payinvoice -f "$invoice"
    elif command -v lightning-cli &> /dev/null; then
        print_info "Attempting payment via CLN..."
        lightning-cli pay "$invoice"
    else
        print_error "No Lightning node CLI (lncli or lightning-cli) found."
        return 1
    fi
}

# Poll order status until success
poll_order() {
    local order_id="$1"
    print_info "Waiting for payment confirmation and configuration..."
    set_api_flags "$API_BASE"
    
    while true; do
        local response
        response=$(curl -s "${CURL_FLAGS[@]}" "${API_BASE}/setup/order?id=${order_id}")
        
        local status=$(echo "$response" | jq -r '.status')
        if [ "$status" == "paid" ] || [ "$status" == "successful" ]; then
            echo "$response"
            return 0
        elif [ "$status" == "failed" ] || [ "$status" == "expired" ]; then
            print_error "Order status: $status"
            return 1
        fi
        
        sleep 5
    done
}

# Save configuration to persistent storage and show backup
save_config_and_backup() {
    local json="$1"
    local server_id="$2"
    local conf_file="${CONFIG_DIR}/tunnelsats_${server_id}.conf"
    
    mkdir -p "$CONFIG_DIR"
    
    print_info "Saving configuration to $conf_file..."
    
    local priv_key=$(echo "$json" | jq -r '.wireguard.privateKey')
    local address=$(echo "$json" | jq -r '.wireguard.address')
    local dns=$(echo "$json" | jq -r '.wireguard.dns')
    local server_pub=$(echo "$json" | jq -r '.server.publicKey')
    local endpoint=$(echo "$json" | jq -r '.server.endpoint')
    local psk=$(echo "$json" | jq -r '.wireguard.presharedKey')
    
    cat <<EOF > "$conf_file"
[Interface]
PrivateKey = $priv_key
Address = $address
DNS = $dns

[Peer]
PublicKey = $server_pub
PresharedKey = $psk
Endpoint = $endpoint
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
EOF

    chmod 600 "$conf_file"
    print_success "Config saved."
    
    # Backup UI
    clear
    print_info "=================================================================="
    print_info "                  CRITICAL BACKUP STEP                            "
    print_info "=================================================================="
    echo "Please save this configuration externally (Password Manager / Print)."
    echo ""
    
    if command -v qrencode &> /dev/null; then
        qrencode -t ANSI < "$conf_file"
    else
        cat "$conf_file"
    fi
    
    echo ""
    read -p "Press [Enter] once you have safely backed up your configuration..."
}

# Helper to get the public key from local config
get_local_pubkey() {
    # Find the first tunnelsats_*.conf file
    local conf_file=$(find "$CONFIG_DIR" -maxdepth 1 -name "tunnelsats_*.conf" -type f | head -n 1)
    if [ -z "$conf_file" ] || [ ! -f "$conf_file" ]; then
        return 1
    fi
    
    local priv_key=$(grep "^PrivateKey" "$conf_file" | cut -d '=' -f2 | tr -d ' ')
    if [ -z "$priv_key" ]; then
        return 1
    fi
    
    echo "$priv_key" | wg pubkey
}

# Renew/Extend an existing subscription
renew_subscription() {
    local pubkey
    pubkey=$(get_local_pubkey) || { print_error "No local subscription found to renew."; return 1; }
    
    local status_json
    status_json=$(check_status "$pubkey") || return 1
    
    local is_active=$(echo "$status_json" | jq -r '.is_active')
    local valid_until=$(echo "$status_json" | jq -r '.valid_until')
    
    if ! (whiptail --title "Subscription Status" --yesno "Current Status: $is_active\nValid Until: $valid_until\n\nDo you want to extend your subscription?" 12 60); then
        return 0
    fi
    
    local duration
    duration=$(whiptail --title "Extend Subscription" --menu "Choose duration:" 12 60 4 \
        "1" "1 Month" \
        "3" "3 Months" \
        "6" "6 Months" \
        "12" "12 Months" 3>&1 1>&2 2>&3)
    
    [ -z "$duration" ] && return 0
    
    print_info "Requesting renewal for $duration months..."
    set_api_flags "$API_BASE"
    local payload="{\"pubkey\":\"$pubkey\", \"months\":$duration}"
    
    local order_json
    order_json=$(curl -s "${CURL_FLAGS[@]}" -X POST -d "$payload" "${API_BASE}/setup/renew")
    
    if echo "$order_json" | jq -e '.error' > /dev/null; then
        local msg=$(echo "$order_json" | jq -r '.message')
        print_error "Renewal Error: $msg"
        return 1
    fi
    
    local bolt11=$(echo "$order_json" | jq -r '.invoice')
    local order_id=$(echo "$order_json" | jq -r '.id')
    
    if ! pay_invoice "$bolt11"; then
        whiptail --title "Payment Failed" --msgbox "Payment failed. Please pay manually:\n$bolt11" 15 60
        return 1
    fi
    
    poll_order "$order_id" || return 1
    print_success "Subscription extended successfully!"
}

# Check subscription status for a given public key
check_status() {
    local pubkey="$1"
    
    if [ -z "$pubkey" ]; then
        print_error "PublicKey is required for status check."
        return 1
    fi
    
    print_info "Checking status for: ${pubkey:0:10}..."
    set_api_flags "$API_BASE"
    
    local response
    response=$(curl -s "${CURL_FLAGS[@]}" "${API_BASE}/status?pubkey=${pubkey}")
    
    if echo "$response" | jq -e '.error' > /dev/null; then
        local msg=$(echo "$response" | jq -r '.message')
        print_error "API Error: $msg"
        return 1
    fi
    
    echo "$response"
}

# Interactive Setup Flow
setup_flow() {
    local servers_json
    servers_json=$(get_servers) || return 1
    
    # Format for whiptail menu: ID "City (Country)"
    local menu_options=()
    while IFS= read -r line; do
        menu_options+=($line)
    done < <(echo "$servers_json" | jq -r '.[] | .id, "\"\(.city) (\(.country))\""')
    
    local server_id
    server_id=$(whiptail --title "TunnelSats Setup" --menu "Select a server location:" 15 60 8 "${menu_options[@]}" 3>&1 1>&2 2>&3)
    
    if [ -z "$server_id" ]; then
        print_info "Setup cancelled."
        return 0
    fi
    
    # 1. Create Order
    local order_json
    order_json=$(create_order "$server_id") || return 1
    
    local bolt11=$(echo "$order_json" | jq -r '.invoice')
    local order_id=$(echo "$order_json" | jq -r '.id')
    
    # 2. Pay Invoice
    if ! pay_invoice "$bolt11"; then
        print_error "Payment failed or skipped. You can pay this invoice manually: $bolt11"
        whiptail --title "Payment Required" --msgbox "Payment initiation failed.\n\nInvoice:\n$bolt11\n\nReturning to menu." 15 60
        return 1
    fi
    
    # 3. Poll for Success
    local config_json
    config_json=$(poll_order "$order_id") || return 1
    
    # 4. Save and Backup
    save_config_and_backup "$config_json" "$server_id"
    
    # 5. Handoff to core script
    local core_script="/home/hakuna/tunnelsats/scripts/tunnelsats.sh"
    if [ -f "$core_script" ]; then
        print_info "Triggering core installation..."
        sudo bash "$core_script" install --config "${CONFIG_DIR}/tunnelsats_${server_id}.conf"
    else
        print_error "Core script not found at $core_script"
    fi
}

# Main routing logic
main() {
    check_dependencies
    
    case "$1" in
        status)
            check_status "$2"
            ;;
        get-servers)
            get_servers
            ;;
        setup)
            setup_flow
            ;;
        renew)
            renew_subscription
            ;;
        *)
            echo "Usage: $0 [status|get-servers|setup|renew] [args...]"
            exit 1
            ;;
    esac
}

main "$@"
