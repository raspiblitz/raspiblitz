#!/bin/bash

# menu.joinmarket-ng.sh
# TUI Menu for JoinMarket-NG on Raspiblitz
# Runs as joinmarketng user (invoked via: sudo -u joinmarketng menu.sh)
# Uses sudo only for specific privileged actions (maker-start/stop/status via bonus script)

# Config — use explicit user home, not $HOME (which is /root when run as sudo)
USER_JM="joinmarketng"
HOME_JM="/home/${USER_JM}"
DATA_DIR="${HOME_JM}/.joinmarket-ng"
VENV_BIN="${HOME_JM}/venv/bin"
CONFIG_FILE="${DATA_DIR}/config.toml"
LOG_DIR="${DATA_DIR}/logs"
MAKER_ENV="${DATA_DIR}/.maker.env"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Load environment
source "$VENV_BIN/activate"
# Ensure ~/.local/bin is in PATH (fallback for pip console scripts)
export PATH="${HOME_JM}/.local/bin:$PATH"

# Helper: Pause
pause() {
  echo ""
  read -p "Press [Enter] key to continue..." fackEnterKey
}

# Helper: Get configured mnemonic file from config.toml
get_mnemonic_file() {
    local val
    val=$(grep '^mnemonic_file[[:space:]]*=' "$CONFIG_FILE" 2>/dev/null | head -1 | sed 's/^mnemonic_file[[:space:]]*=[[:space:]]*//' | tr -d '"')
    echo "$val"
}

# Helper: Set a value in config.toml (uncomment if needed)
set_config_value() {
    local key=$1
    local value=$2
    local quote=$3 # "true" to wrap in quotes

    if [ "$quote" == "true" ]; then
        value="\"${value}\""
    fi

    if grep -q "^${key}[[:space:]]*=" "$CONFIG_FILE"; then
        sed -i "s|^${key}[[:space:]]*=.*|${key} = ${value}|" "$CONFIG_FILE"
    elif grep -q "^#[[:space:]]*${key}[[:space:]]*=" "$CONFIG_FILE"; then
        sed -i "s|^#[[:space:]]*${key}[[:space:]]*=.*|${key} = ${value}|" "$CONFIG_FILE"
    else
        echo "# Warning: Could not find key '${key}' in config"
    fi
}

# Helper: List .mnemonic files in wallets dir
list_wallets() {
    find "$DATA_DIR/wallets" -maxdepth 1 -name '*.mnemonic' -type f -printf '%f\n' 2>/dev/null
}

# Main Loop
while true; do

  # Get Maker Service Status
  if pgrep -f "jm-maker" > /dev/null 2>&1; then
    MAKER_STATUS="RUNNING"
  else
    MAKER_STATUS="STOPPED"
  fi

  # Check if a wallet is configured
  CURRENT_WALLET=$(get_mnemonic_file)
  if [ -n "$CURRENT_WALLET" ]; then
    WALLET_INFO="Wallet: $(basename "$CURRENT_WALLET")"
  else
    WALLET_INFO="Wallet: (none configured)"
  fi

  CHOICE=$(whiptail --title " JoinMarket-NG Menu " --menu "Maker: $MAKER_STATUS | $WALLET_INFO" 18 64 9 \
    "W" "Wallet Management" \
    "T" "Taker: Run CoinJoin" \
    "M" "Maker Bot Control (${MAKER_STATUS})" \
    "C" "Edit Configuration" \
    "I" "Info / Documentation" \
    "X" "Exit" 3>&1 1>&2 2>&3)

  exitstatus=$?
  if [ $exitstatus != 0 ]; then
    clear
    exit 0
  fi

  case $CHOICE in
    W)
      # Wallet Submenu
      WCHOICE=$(whiptail --title " Wallet Management " --menu "Choose option:" 20 64 11 \
        "NEW"      "Create New Wallet (24-word seed)" \
        "IMP"      "Import Existing Wallet (from seed)" \
        "VAL"      "Validate a Seed Phrase" \
        "BAL"      "View Wallet Info / Balance" \
        "HIST"     "CoinJoin History" \
        "SEND"     "Send Bitcoin" \
        "FREEZE"   "Freeze / Unfreeze UTXOs" \
        "SEL"      "Select Active Wallet" \
        "BACK"     "Back to Main Menu" 3>&1 1>&2 2>&3)

      case $WCHOICE in
          NEW)
              clear
              echo "=== Create New Wallet ==="
              echo ""
              echo "This will generate a new 24-word BIP39 mnemonic."
              echo "IMPORTANT: Write down the seed words! They are your backup."
              echo ""
              read -p "Enter wallet name (default: default): " WNAME
              WNAME=${WNAME:-default}
              # Strip extension if provided, we add .mnemonic
              WNAME="${WNAME%.mnemonic}"

              WALLET_PATH="$DATA_DIR/wallets/${WNAME}.mnemonic"
              mkdir -p "$DATA_DIR/wallets"

              echo ""
              echo "Generating wallet..."
              jm-wallet generate --prompt-password -o "$WALLET_PATH"
              RESULT=$?

              if [ $RESULT -eq 0 ] && [ -f "$WALLET_PATH" ]; then
                  echo ""
                  echo "Wallet saved to: $WALLET_PATH"
                  # Ask to set as active wallet
                  read -p "Set as active wallet in config? (Y/n): " SET_ACTIVE
                  SET_ACTIVE=${SET_ACTIVE:-Y}
                  if [[ "$SET_ACTIVE" =~ ^[Yy] ]]; then
                      set_config_value "mnemonic_file" "$WALLET_PATH" "true"
                      echo "Active wallet updated in config.toml"
                  fi
                  # Ask whether to store the encryption password in config.toml
                  echo ""
                  echo "You can store the wallet password in config.toml so all"
                  echo "commands (including the maker) work without prompting."
                  echo "If you choose No, the maker will ask for the password each time."
                  read -p "Store wallet password in config.toml? (y/N): " STORE_PWD
                  if [[ "$STORE_PWD" =~ ^[Yy] ]]; then
                      read -r -s -p "Enter the wallet encryption password: " PWD_STORE
                      echo ""
                      sudo /home/admin/config.scripts/bonus.joinmarket-ng.sh store-password "${PWD_STORE}"
                      unset PWD_STORE
                      echo "Password stored in config.toml."
                  fi
              else
                  echo "Wallet creation may have failed. Check output above."
              fi
              pause
              ;;
          IMP)
              clear
              echo "=== Import Wallet from Seed ==="
              echo ""
              echo "You will be prompted to enter your BIP39 seed words."
              echo ""
              read -p "Enter wallet name (default: imported): " WNAME
              WNAME=${WNAME:-imported}
              WNAME="${WNAME%.mnemonic}"

              WALLET_PATH="$DATA_DIR/wallets/${WNAME}.mnemonic"
              mkdir -p "$DATA_DIR/wallets"

              jm-wallet import --prompt-password -o "$WALLET_PATH"
              RESULT=$?

              if [ $RESULT -eq 0 ] && [ -f "$WALLET_PATH" ]; then
                  echo ""
                  echo "Wallet imported to: $WALLET_PATH"
                  read -p "Set as active wallet in config? (Y/n): " SET_ACTIVE
                  SET_ACTIVE=${SET_ACTIVE:-Y}
                  if [[ "$SET_ACTIVE" =~ ^[Yy] ]]; then
                      set_config_value "mnemonic_file" "$WALLET_PATH" "true"
                      echo "Active wallet updated in config.toml"
                  fi
                  # Ask whether to store the encryption password in config.toml
                  echo ""
                  echo "You can store the wallet password in config.toml so all"
                  echo "commands (including the maker) work without prompting."
                  echo "If you choose No, the maker will ask for the password each time."
                  read -p "Store wallet password in config.toml? (y/N): " STORE_PWD
                  if [[ "$STORE_PWD" =~ ^[Yy] ]]; then
                      read -r -s -p "Enter the wallet encryption password: " PWD_STORE
                      echo ""
                      sudo /home/admin/config.scripts/bonus.joinmarket-ng.sh store-password "${PWD_STORE}"
                      unset PWD_STORE
                      echo "Password stored in config.toml."
                  fi
              else
                  echo "Import may have failed. Check output above."
              fi
              pause
              ;;
          VAL)
              clear
              echo "=== Validate Seed Phrase ==="
              echo ""
              echo "Check that a BIP39 mnemonic is valid before importing."
              echo ""
                  jm-wallet validate
              pause
              ;;
          BAL)
              clear
              echo "=== Wallet Info / Balance ==="
              echo ""
              if [ -z "$CURRENT_WALLET" ]; then
                  echo "No wallet configured in config.toml (mnemonic_file is empty)."
                  echo "Use 'Select Active Wallet' or 'Create New Wallet' first."
              else
                  echo "Active wallet: $(basename "$CURRENT_WALLET")"
                  echo ""
                  jm-wallet info
              fi
              pause
              ;;
          HIST)
              clear
              echo "=== CoinJoin History ==="
              echo ""
              if [ -z "$CURRENT_WALLET" ]; then
                  echo "No wallet configured in config.toml (mnemonic_file is empty)."
              else
                  echo "Active wallet: $(basename "$CURRENT_WALLET")"
                  echo ""
                  echo "Filter by role: maker, taker, or leave blank for all."
                  read -p "Role filter (blank=all): " HIST_ROLE
                  echo ""
                  read -p "Max entries to show (blank=all): " HIST_LIMIT
                  echo ""
                  HIST_ARGS=()
                  [ -n "$HIST_ROLE" ]  && HIST_ARGS+=(-r "$HIST_ROLE")
                  [ -n "$HIST_LIMIT" ] && HIST_ARGS+=(-n "$HIST_LIMIT")
                  jm-wallet history "${HIST_ARGS[@]}"
              fi
              pause
              ;;
          SEND)
              clear
              echo "=== Send Bitcoin ==="
              echo ""
              if [ -z "$CURRENT_WALLET" ]; then
                  echo "No wallet configured in config.toml (mnemonic_file is empty)."
                  pause
              else
                  echo "Active wallet: $(basename "$CURRENT_WALLET")"
                  echo ""
                  read -p "Destination address: " SEND_DEST
                  if [ -z "$SEND_DEST" ]; then
                      echo "No destination entered. Aborting."
                      pause
                  else
                      read -p "Amount in sats (0 for sweep): " SEND_AMOUNT
                      SEND_AMOUNT=${SEND_AMOUNT:-0}

                      read -p "Source mixdepth (default 0): " SEND_DEPTH
                      SEND_DEPTH=${SEND_DEPTH:-0}

                      echo ""
                      echo "Fee rate: leave blank for automatic 3-block estimate."
                      read -p "Fee rate in sat/vB (blank=auto): " SEND_FEE

                      echo ""
                      SEND_ARGS=(-a "$SEND_AMOUNT" -m "$SEND_DEPTH")
                      [ -n "$SEND_FEE" ] && SEND_ARGS+=(--fee-rate "$SEND_FEE")

                      echo "Transaction preview:"
                      echo "  To:     $SEND_DEST"
                      echo "  Amount: $SEND_AMOUNT sats (0=sweep)"
                      echo "  From:   mixdepth $SEND_DEPTH"
                      [ -n "$SEND_FEE" ] && echo "  Fee:    ${SEND_FEE} sat/vB"
                      echo ""
                      jm-wallet send "${SEND_ARGS[@]}" "$SEND_DEST"
                  fi
              fi
              pause
              ;;
          FREEZE)
              clear
              echo "=== Freeze / Unfreeze UTXOs ==="
              echo ""
              if [ -z "$CURRENT_WALLET" ]; then
                  echo "No wallet configured in config.toml (mnemonic_file is empty)."
              else
                  echo "Active wallet: $(basename "$CURRENT_WALLET")"
                  echo "Opening interactive UTXO selector. Use arrow keys to navigate,"
                  echo "Space to toggle freeze state, Enter to confirm, q to quit."
                  echo ""
                  jm-wallet freeze
              fi
              pause
              ;;
          SEL)
              clear
              echo "=== Select Active Wallet ==="
              echo ""
              WALLETS=$(list_wallets)
              if [ -z "$WALLETS" ]; then
                  echo "No wallet files found in $DATA_DIR/wallets/"
                  echo "Create or import a wallet first."
              else
                  echo "Available wallets:"
                  echo "$WALLETS" | nl -ba
                  echo ""
                  echo "Current: $(get_mnemonic_file)"
                  echo ""
                  read -p "Enter wallet filename: " WNAME
                  if [ -f "$DATA_DIR/wallets/$WNAME" ]; then
                      set_config_value "mnemonic_file" "$DATA_DIR/wallets/$WNAME" "true"
                      echo "Active wallet set to: $WNAME"
                      echo "Restart the maker service for changes to take effect."
                  else
                      echo "File not found: $DATA_DIR/wallets/$WNAME"
                  fi
              fi
              pause
              ;;
      esac
      ;;

    T)
      clear
      echo "=== Taker: Run CoinJoin ==="
      echo ""
      if [ -z "$CURRENT_WALLET" ]; then
          echo "No wallet configured. Set up a wallet first."
          pause
          continue
      fi
      echo "Active wallet: $(basename "$CURRENT_WALLET")"
      echo ""
      echo "Amount: Enter satoshis to mix, or 0 for sweep (best privacy)."
      read -p "Amount (0=sweep): " AMOUNT
      AMOUNT=${AMOUNT:-0}

      read -p "Source mixdepth (default 0): " MIXDEPTH
      MIXDEPTH=${MIXDEPTH:-0}

      echo ""
      echo "Destination: INTERNAL sends to next mixdepth (recommended)."
      echo "Or enter a bitcoin address for external destination."
      read -p "Destination (default INTERNAL): " DEST
      DEST=${DEST:-INTERNAL}

      echo ""
      echo "Starting CoinJoin..."
      echo "Press Ctrl+C to abort."
      echo ""
      jm-taker coinjoin -a "$AMOUNT" -m "$MIXDEPTH" -d "$DEST"
      pause
      ;;

    M)
      # Maker submenu
      MCHOICE=$(whiptail --title " Maker Bot (${MAKER_STATUS}) " --menu "Choose option:" 18 64 8 \
        "START"   "Start Maker Bot" \
        "STOP"    "Stop Maker Bot" \
        "RESTART" "Restart Maker Bot" \
        "BONDS"   "Fidelity Bond Management" \
        "LOG"     "Follow Maker Logs (Ctrl+C to stop)" \
        "STATUS"  "Show Service Status" \
        "BACK"    "Back to Main Menu" 3>&1 1>&2 2>&3)

      case $MCHOICE in
          START)
              clear
              if [ -z "$CURRENT_WALLET" ]; then
                  echo "ERROR: No wallet configured. Set up a wallet first (W -> SEL or NEW)."
              else
                  sudo /home/admin/config.scripts/bonus.joinmarket-ng.sh maker-start
                  sleep 2
                  echo ""
                  echo "Service status:"
                  sudo /home/admin/config.scripts/bonus.joinmarket-ng.sh maker-status
              fi
              pause
              ;;
          STOP)
              clear
              sudo /home/admin/config.scripts/bonus.joinmarket-ng.sh maker-stop
              pause
              ;;
          RESTART)
              clear
              if [ -z "$CURRENT_WALLET" ]; then
                  echo "ERROR: No wallet configured. Set up a wallet first (W -> SEL or NEW)."
              else
                  sudo /home/admin/config.scripts/bonus.joinmarket-ng.sh maker-stop
                  sudo /home/admin/config.scripts/bonus.joinmarket-ng.sh maker-start
                  sleep 2
                  echo ""
                  echo "Service status:"
                  sudo /home/admin/config.scripts/bonus.joinmarket-ng.sh maker-status
              fi
              pause
              ;;
          LOG)
              clear
              echo "=== Maker Logs ==="
              echo "Press Ctrl+C to stop following."
              echo ""
              LOG_FILE="$LOG_DIR/maker.log"
              if [ -r "$LOG_FILE" ]; then
                  tail -n 50 -f "$LOG_FILE"
              else
                  echo "No log file found at $LOG_FILE (maker may not have run yet)."
                  echo "Trying journalctl..."
                  sudo /home/admin/config.scripts/bonus.joinmarket-ng.sh maker-status
              fi
              pause
              ;;
          STATUS)
              clear
              echo "=== Maker Service Status ==="
              echo ""
              sudo /home/admin/config.scripts/bonus.joinmarket-ng.sh maker-status
              pause
              ;;
          BONDS)
              # Fidelity bond submenu
              while true; do
                BCHOICE=$(whiptail --title " Fidelity Bonds " \
                  --menu "Fidelity bonds lock coins until a date to boost maker reputation.\nExpired bonds appear in wallet balance and are spendable." \
                  16 72 4 \
                  "LIST"   "List existing fidelity bonds" \
                  "CREATE" "Generate a new bond address (lock coins)" \
                  "BACK"   "Back to Maker Menu" 3>&1 1>&2 2>&3)
                [ $? -ne 0 ] && break
                case $BCHOICE in
                    LIST)
                        clear
                        echo "=== Fidelity Bonds ==="
                        echo ""
                        if [ -z "$CURRENT_WALLET" ]; then
                            echo "ERROR: No wallet configured. Set up a wallet first (W -> SEL or NEW)."
                        else
                            echo "Scanning for fidelity bonds (this may take a moment)..."
                            echo ""
                            jm-wallet list-bonds
                        fi
                        pause
                        ;;
                    CREATE)
                        clear
                        if [ -z "$CURRENT_WALLET" ]; then
                            echo "ERROR: No wallet configured. Set up a wallet first (W -> SEL or NEW)."
                            pause
                            continue
                        fi
                        echo "=== Generate Fidelity Bond Address ==="
                        echo ""
                        echo "A fidelity bond locks coins at a P2WSH address until a chosen date."
                        echo "The longer and larger the bond, the higher your maker reputation."
                        echo "Coins are NOT spendable until the locktime expires."
                        echo ""
                        # Ask for locktime month
                        LOCKDATE=$(whiptail --title " Fidelity Bond Locktime " \
                          --inputbox "Enter locktime as YYYY-MM (must be a future month, e.g. 2027-06):" \
                          10 60 "" 3>&1 1>&2 2>&3)
                        [ $? -ne 0 ] && continue
                        if [ -z "$LOCKDATE" ]; then
                            whiptail --title "Error" --msgbox "No locktime entered." 8 40
                            continue
                        fi
                        # Ask for derivation index (default 0)
                        BOND_INDEX=$(whiptail --title " Bond Index " \
                          --inputbox "Derivation index (0 for first bond, 1 for second, etc.):" \
                          10 60 "0" 3>&1 1>&2 2>&3)
                        [ $? -ne 0 ] && continue
                        BOND_INDEX="${BOND_INDEX:-0}"
                        clear
                        echo "=== Generating Bond Address ==="
                        echo ""
                        jm-wallet generate-bond-address \
                          --locktime-date "${LOCKDATE}" \
                          --index "${BOND_INDEX}"
                        echo ""
                        echo "Send coins to the address above to create the fidelity bond."
                        echo "Funds will be locked until the locktime expires."
                        pause
                        ;;
                    BACK|"")
                        break
                        ;;
                esac
              done
              ;;
      esac
      ;;

    C)
      nano "$CONFIG_FILE"
      ;;

    I)
      whiptail --title " JoinMarket-NG Info " --msgbox "\
JoinMarket-NG - Next Generation CoinJoin

Docs: https://github.com/joinmarket-ng/joinmarket-ng

Config: $CONFIG_FILE
Data:   $DATA_DIR
Logs:   $LOG_DIR

CLI tools (from venv):
  jm-wallet generate   - Create new wallet
  jm-wallet import     - Import from seed
  jm-wallet validate   - Validate a seed phrase
  jm-wallet info       - Show balance by mixdepth
  jm-wallet history    - CoinJoin history
  jm-wallet send       - Send bitcoin
  jm-wallet freeze     - Freeze/unfreeze UTXOs
  jm-wallet list-bonds              - List fidelity bonds
  jm-wallet generate-bond-address   - Create bond address
  jm-maker start       - Maker bot (earn fees)
  jm-taker coinjoin    - Run a CoinJoin

Maker service (as admin):
  sudo systemctl start joinmarket-ng-maker
  sudo systemctl stop joinmarket-ng-maker
  sudo journalctl -u joinmarket-ng-maker -f" 24 60
      ;;

    X)
      clear
      exit 0
      ;;
  esac

done
