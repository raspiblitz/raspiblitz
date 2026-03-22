#!/bin/bash

# menu.joinmarket-ng.sh
# TUI Menu for JoinMarket-NG on Raspiblitz
# Runs as joinmarketng user (invoked via: sudo -u joinmarketng menu.sh)
# Uses sudo only for specific privileged actions (maker-start/stop/status via bonus script)

# Config -- use explicit user home, not $HOME (which is /root when run as sudo)
USER_JM="joinmarketng"
HOME_JM="/home/${USER_JM}"
DATA_DIR="${HOME_JM}/.joinmarket-ng"
VENV_BIN="${HOME_JM}/venv/bin"
CONFIG_FILE="${DATA_DIR}/config.toml"
LOG_DIR="${DATA_DIR}/logs"
MAKER_ENV="${DATA_DIR}/.maker.env"

# Defaults for send/coinjoin parameters
DEFAULT_AMOUNT="0"
DEFAULT_MIXDEPTH="0"
DEFAULT_FEE_RATE=""
DEFAULT_DESTINATION=""
# Counterparty default: read from config.toml [taker] section, fall back to 10 (jm-taker default)
DEFAULT_COUNTERPARTIES=$(python3 - "$CONFIG_FILE" <<'PYEOF' 2>/dev/null
import sys, pathlib
try:
    import tomllib
except ImportError:
    import tomli as tomllib  # type: ignore[no-redef]
path = pathlib.Path(sys.argv[1])
if path.exists():
    try:
        data = tomllib.loads(path.read_text())
        val = data.get("taker", {}).get("counterparty_count")
        if val is not None:
            print(int(val))
    except Exception:
        pass
PYEOF
)
DEFAULT_COUNTERPARTIES="${DEFAULT_COUNTERPARTIES:-10}"

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

# Helper: Prompt for a parameter using whiptail inputbox.
# Usage: prompt_param "Title" "Prompt text" "default_value"
# Returns the value via stdout. Returns exit code 1 if user cancelled.
prompt_param() {
    local title="$1"
    local prompt="$2"
    local default="$3"
    local value
    value=$(whiptail --title " $title " \
      --inputbox "$prompt" \
      10 68 "$default" 3>&1 1>&2 2>&3)
    local rc=$?
    [ $rc -ne 0 ] && return 1
    echo "$value"
    return 0
}

# Helper: Sanitize a numeric string -- strip leading zeros, default to fallback.
# Usage: to_int "value" "fallback"
# Examples: to_int "02" "0" -> "2", to_int "" "0" -> "0", to_int "abc" "0" -> "0"
to_int() {
    local raw="$1"
    local fallback="${2:-0}"
    # Remove leading zeros, then validate as integer
    local stripped
    stripped=$(echo "$raw" | sed 's/^0*//' | sed 's/^$/0/')
    if [[ "$stripped" =~ ^[0-9]+$ ]]; then
        echo "$stripped"
    else
        echo "$fallback"
    fi
}

# Helper: Show a confirmation summary before executing a command.
# Compares chosen values against defaults and marks changed ones with ">>".
# Usage: show_summary "Title" "label1|default1|value1" "label2|default2|value2" ...
# Returns 0 if user confirms, 1 if cancelled.
show_summary() {
    local title="$1"
    shift
    local body=""
    local label default value marker

    for entry in "$@"; do
        IFS='|' read -r label default value <<< "$entry"
        if [ "$value" != "$default" ]; then
            marker=">>"
        else
            marker="  "
        fi
        # Show default in parentheses when there is one
        if [ -n "$default" ]; then
            body="${body}${marker} ${label}: ${value}  (default: ${default})\n"
        else
            body="${body}${marker} ${label}: ${value}\n"
        fi
    done

    body="${body}\n>> = changed from default\n\nProceed?"

    whiptail --title " $title " --yesno "$body" 20 70 3>&1 1>&2 2>&3
    return $?
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
    "S" "Send Bitcoin" \
    "W" "Wallet Management" \
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
    # ------------------------------------------------------------------
    # SEND BITCOIN (unified: normal tx when counterparties=0, coinjoin otherwise)
    # ------------------------------------------------------------------
    S)
      if [ -z "$CURRENT_WALLET" ]; then
          whiptail --title " Error " --msgbox "No wallet configured.\nSet up a wallet first (W -> NEW or SEL)." 9 50
          continue
      fi

      # 1. Destination address (required)
      SEND_DEST=$(prompt_param "Destination" \
        "Enter destination bitcoin address.\nLeave empty and press Enter for INTERNAL (next mixdepth, coinjoin only)." \
        "$DEFAULT_DESTINATION") || continue
      # For coinjoin with no destination, default to INTERNAL later

      # 2. Amount in satoshis
      SEND_AMOUNT=$(prompt_param "Amount" \
        "Amount in satoshis to send.\n0 = sweep entire mixdepth (best privacy for coinjoin)." \
        "$DEFAULT_AMOUNT") || continue
      SEND_AMOUNT=$(to_int "${SEND_AMOUNT}" "$DEFAULT_AMOUNT")

      # 3. Source mixdepth
      SEND_MIXDEPTH=$(prompt_param "Source Mixdepth" \
        "Source mixdepth (account) to send from." \
        "$DEFAULT_MIXDEPTH") || continue
      SEND_MIXDEPTH=$(to_int "${SEND_MIXDEPTH}" "$DEFAULT_MIXDEPTH")

      # 4. Fee rate
      SEND_FEE=$(prompt_param "Fee Rate" \
        "Fee rate in sat/vB.\nLeave blank for automatic estimation (3-block target from config)." \
        "$DEFAULT_FEE_RATE") || continue

      # 5. Number of counterparties (0 = normal transaction, >0 = coinjoin)
      SEND_CP=$(prompt_param "Counterparties" \
        "Number of counterparties (makers) for CoinJoin.\n0 = normal transaction (no CoinJoin).\nRecommended for CoinJoin: 4-10." \
        "$DEFAULT_COUNTERPARTIES") || continue
      SEND_CP=$(to_int "${SEND_CP}" "$DEFAULT_COUNTERPARTIES")

      # Apply INTERNAL default for coinjoin when destination is empty
      if [ -z "$SEND_DEST" ] && [ "$SEND_CP" -gt 0 ] 2>/dev/null; then
          SEND_DEST="INTERNAL"
      elif [ -z "$SEND_DEST" ]; then
          whiptail --title " Error " --msgbox "Destination address is required for normal transactions." 8 50
          continue
      fi

      # Determine transaction type label for summary
      if [ "$SEND_CP" -gt 0 ] 2>/dev/null; then
          TX_TYPE="CoinJoin ($SEND_CP counterparties)"
      else
          TX_TYPE="Normal transaction"
      fi

      # Fee display
      if [ -n "$SEND_FEE" ]; then
          FEE_DISPLAY="${SEND_FEE} sat/vB"
      else
          FEE_DISPLAY="auto (3-block estimate)"
      fi

      # Amount display
      if [ "$SEND_AMOUNT" = "0" ]; then
          AMOUNT_DISPLAY="0 (sweep)"
      else
          AMOUNT_DISPLAY="${SEND_AMOUNT} sats"
      fi

      # Show confirmation summary
      DEFAULT_TX_TYPE="CoinJoin ($DEFAULT_COUNTERPARTIES counterparties)"
      show_summary "Confirm Send -- $(basename "$CURRENT_WALLET")" \
        "Type|${DEFAULT_TX_TYPE}|${TX_TYPE}" \
        "Destination||${SEND_DEST}" \
        "Amount|$DEFAULT_AMOUNT (sweep)|${AMOUNT_DISPLAY}" \
        "Source mixdepth|$DEFAULT_MIXDEPTH|${SEND_MIXDEPTH}" \
        "Fee rate|auto (3-block estimate)|${FEE_DISPLAY}" || continue

      # Execute the appropriate command
      clear
      if [ "$SEND_CP" -gt 0 ] 2>/dev/null; then
          # CoinJoin via jm-taker
          echo "=== CoinJoin Send ==="
          echo ""
          echo "Wallet: $(basename "$CURRENT_WALLET")"
          echo "Counterparties: $SEND_CP"
          echo "Press Ctrl+C to abort."
          echo ""

          TAKER_ARGS=(coinjoin -a "$SEND_AMOUNT" -m "$SEND_MIXDEPTH" -d "$SEND_DEST")
          TAKER_ARGS+=(-n "$SEND_CP")
          [ -n "$SEND_FEE" ] && TAKER_ARGS+=(--fee-rate "$SEND_FEE")

          jm-taker "${TAKER_ARGS[@]}"
      else
          # Normal transaction via jm-wallet send
          echo "=== Send Bitcoin ==="
          echo ""
          echo "Wallet: $(basename "$CURRENT_WALLET")"
          echo ""

          SEND_ARGS=(send -a "$SEND_AMOUNT" -m "$SEND_MIXDEPTH")
          [ -n "$SEND_FEE" ] && SEND_ARGS+=(--fee-rate "$SEND_FEE")
          SEND_ARGS+=("$SEND_DEST")

          jm-wallet "${SEND_ARGS[@]}"
      fi
      pause
      ;;

    # ------------------------------------------------------------------
    # WALLET MANAGEMENT
    # ------------------------------------------------------------------
    W)
      # Wallet Submenu
      WCHOICE=$(whiptail --title " Wallet Management " --menu "Choose option:" 20 64 11 \
        "NEW"      "Create New Wallet (24-word seed)" \
        "IMP"      "Import Existing Wallet (from seed)" \
        "VAL"      "Validate a Seed Phrase" \
        "BAL"      "View Wallet Info / Balance" \
        "HIST"     "CoinJoin History" \
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

              # Ask for word count
              WORDS_CHOICE=$(whiptail --title " Import Wallet " \
                  --menu "How many seed words does your wallet have?" 12 50 2 \
                  "24" "24 words" \
                  "12" "12 words" \
                  3>&1 1>&2 2>&3) || break
              WORDS="${WORDS_CHOICE:-24}"

              WALLET_PATH="$DATA_DIR/wallets/${WNAME}.mnemonic"
              mkdir -p "$DATA_DIR/wallets"

              jm-wallet import --words "$WORDS" --prompt-password -o "$WALLET_PATH"
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
              if [ -z "$CURRENT_WALLET" ]; then
                  whiptail --title " Error " --msgbox "No wallet configured.\nSet up a wallet first (W -> NEW or SEL)." 9 50
              else
                  # Prompt parameters with whiptail
                  HIST_ROLE=$(prompt_param "Role Filter" \
                    "Filter by role: maker, taker.\nLeave blank for all." \
                    "") || continue

                  HIST_LIMIT=$(prompt_param "Max Entries" \
                    "Maximum number of entries to show.\nLeave blank for all." \
                    "") || continue

                  whiptail --title " Statistics " \
                    --yesno "Show statistics summary?" \
                    8 40 --defaultno 3>&1 1>&2 2>&3
                  HIST_SHOW_STATS=$?

                  # Build summary entries
                  ROLE_DISPLAY="${HIST_ROLE:-all}"
                  LIMIT_DISPLAY="${HIST_LIMIT:-all}"
                  if [ $HIST_SHOW_STATS -eq 0 ]; then
                      STATS_DISPLAY="yes"
                  else
                      STATS_DISPLAY="no"
                  fi

                  show_summary "Confirm History -- $(basename "$CURRENT_WALLET")" \
                    "Role filter|all|${ROLE_DISPLAY}" \
                    "Max entries|all|${LIMIT_DISPLAY}" \
                    "Show statistics|no|${STATS_DISPLAY}" || continue

                  clear
                  echo "=== CoinJoin History ==="
                  echo ""
                  echo "Active wallet: $(basename "$CURRENT_WALLET")"
                  echo ""
                  HIST_ARGS=()
                  [ -n "$HIST_ROLE" ]  && HIST_ARGS+=(-r "$HIST_ROLE")
                  [ -n "$HIST_LIMIT" ] && HIST_ARGS+=(-n "$HIST_LIMIT")
                  [ $HIST_SHOW_STATS -eq 0 ] && HIST_ARGS+=(-s)
                  jm-wallet history "${HIST_ARGS[@]}"
                  pause
              fi
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

    # ------------------------------------------------------------------
    # MAKER BOT CONTROL
    # ------------------------------------------------------------------
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
                        if [ -z "$CURRENT_WALLET" ]; then
                            whiptail --title " Error " --msgbox "No wallet configured.\nSet up a wallet first (W -> NEW or SEL)." 9 50
                            continue
                        fi

                        # Locktime month (required)
                        LOCKDATE=$(prompt_param "Fidelity Bond Locktime" \
                          "Enter locktime as YYYY-MM (must be a future month, e.g. 2027-06).\nCoins are NOT spendable until this date." \
                          "") || continue
                        if [ -z "$LOCKDATE" ]; then
                            whiptail --title " Error " --msgbox "No locktime entered." 8 40
                            continue
                        fi

                        # Derivation index (default 0)
                        BOND_INDEX=$(prompt_param "Bond Index" \
                          "Derivation index (0 for first bond, 1 for second, etc.)." \
                          "0") || continue
                        BOND_INDEX=$(to_int "${BOND_INDEX}" "0")

                        # Confirmation summary
                        show_summary "Confirm Fidelity Bond -- $(basename "$CURRENT_WALLET")" \
                          "Locktime|<required>|${LOCKDATE}" \
                          "Derivation index|0|${BOND_INDEX}" || continue

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
