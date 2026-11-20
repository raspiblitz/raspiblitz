#!/bin/bash
# RaspiBlitz Live Monitor
INTERVAL=1

export LANG=${LANG:-en_US.UTF-8}
export LC_ALL=${LC_ALL:-en_US.UTF-8}

while getopts "i:" opt; do
  case $opt in
    i)
      INTERVAL=${OPTARG}
      ;;
    *)
      echo "Usage: $0 [-i interval_seconds]"
      exit 1
      ;;
  esac
done
shift $((OPTIND-1))

BOLD=$(tput bold); RESET=$(tput sgr0)
FG_WHITE=$(tput setaf 15); FG_CYAN=$(tput setaf 6); BG_BLUE=$(tput setab 4)

# --- Paths ---------------------------------------------------------
CONF="/mnt/hdd/app-data/bitcoin/bitcoin.conf"
CLI="bitcoin-cli -conf=${CONF}"

# detect debug.log path from conf (main.debuglogfile=...), else fallback
DEBUGLOG=$(awk -F= '/^[[:space:]]*main\.debuglogfile[[:space:]]*=/{gsub(/[[:space:]]/,"",$2); print $2}' "$CONF")
[ -z "$DEBUGLOG" ] && DEBUGLOG="/mnt/hdd/app-data/bitcoin/debug.log"

# --- Network interface ---------------------------------------------
IFACE=$(ip route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}')
[ -z "$IFACE" ] && IFACE="eth0"

# --- sysinfo helpers ----------------------------------------------
get_cpu_temp() {
  if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
    awk 'BEGIN{printf "%.1f°C",'$(cat /sys/class/thermal/thermal_zone0/temp)'/1000}'
  elif command -v vcgencmd >/dev/null 2>&1; then
    vcgencmd measure_temp 2>/dev/null | cut -d= -f2
  else echo "n/a"; fi
}
get_ram_summary(){ free -m | awk '/^Mem:/{printf "Used: %d MB | Buff/Cache: %d MB", $3, $6}'; }
get_bitcoind_rss(){ ps -o rss= -C bitcoind | awk '{s+=$1} END{printf "%.1f MB", s/1024}'; }

# --- JSON (without jq) --------------------------------------------
json_get_number(){ echo "$1" | tr -d '\n' | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p"; }
json_get_float(){  echo "$1" | tr -d '\n' | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\.[0-9][0-9]*\\).*/\\1/p"; }

# --- UTXO cache parsing -------------------------------------------
get_utxo_cache_target_mib() {
  [ -r "$DEBUGLOG" ] || { echo "n/a"; return; }
  awk '/Cache configuration:/{p=1;next} p&&/^\*/{print} p&&NF==0{p=0}' "$DEBUGLOG" 2>/dev/null \
  | grep -Eo 'Using[[:space:]]+[0-9.]+[[:space:]]+MiB[[:space:]]+for[[:space:]]+in-memory[[:space:]]+UTXO[[:space:]]+set' \
  | tail -1 | grep -Eo '[0-9.]+' || echo "n/a"
}
get_utxo_cache_used_mib() {
  [ -r "$DEBUGLOG" ] || { echo "n/a"; return; }
  tail -n 10000 "$DEBUGLOG" 2>/dev/null \
  | grep -a -Eo 'cache=[[:space:]]*[0-9.]+[[:space:]]*MiB' \
  | tail -1 | sed -E 's/.*cache=[[:space:]]*([0-9.]+)[[:space:]]*MiB/\1/' || echo "n/a"
}

# --- Net counters --------------------------------------------------
BASE="/sys/class/net/$IFACE/statistics"
RX_PREV=$(cat "$BASE/rx_bytes" 2>/dev/null || echo 0)
TX_PREV=$(cat "$BASE/tx_bytes" 2>/dev/null || echo 0)

# --- Layout (row/col positions) -----------------------------------
ROW_TITLE=0
ROW_HR1=1
ROW_DATA_START=2
COL_LABEL=2
COL_VALUE=18

# dynamic rows for each metric
R_BLOCKS=$((ROW_DATA_START+0))
R_PROGRESS=$((ROW_DATA_START+1))
R_PEERS=$((ROW_DATA_START+2))
R_UPTIME=$((ROW_DATA_START+3))
R_TEMP=$((ROW_DATA_START+4))
R_RAM=$((ROW_DATA_START+5))
R_UTXO=$((ROW_DATA_START+6))
R_NET=$((ROW_DATA_START+7))
R_IP=$((ROW_DATA_START+8))
ROW_HR2=$((ROW_DATA_START+9))
R_FOOT=$((ROW_DATA_START+10))

hr_line=""
make_hr() {
  local cols=$(tput cols); ((cols<60)) && cols=60
  hr_line=$(printf '=%.0s' $(seq 1 $((cols-1))))
}

draw_title() {
  local cols=$(tput cols); ((cols<60)) && cols=60
  local width=$((cols-1))
  local title="  RaspiBlitz Live Monitor  "
  local pad=$(( (width - ${#title}) / 2 )); [ $pad -lt 0 ] && pad=0
  tput cup $ROW_TITLE 0
  printf "${BG_BLUE}${FG_WHITE}${BOLD}"
  printf '%*s' "$pad" ""; printf "%s" "$title"
  printf '%*s' $((width - pad - ${#title})) ""
  printf "${RESET}"
}

draw_static_labels() {
  # top HR
  tput cup $ROW_HR1 0; printf "${FG_CYAN}%s${RESET}" "$hr_line"

  # labels (printed once)
  tput cup $R_BLOCKS $COL_LABEL;   printf "📦  Blocks:"
  tput cup $R_PROGRESS $COL_LABEL; printf "📊  Progress:"
  tput cup $R_PEERS $COL_LABEL;    printf "🌐  Peers:"
  tput cup $R_UPTIME $COL_LABEL;   printf "🕓  Uptime:"
  tput cup $R_TEMP $COL_LABEL;     printf "🔥  CPU Temp:"
  tput cup $R_RAM $COL_LABEL;      printf "💾  RAM:"
  tput cup $R_UTXO $COL_LABEL;     printf "🧠  UTXO Cache:"
  tput cup $R_NET $COL_LABEL;      printf "📡  Network:"
  tput cup $R_IP $COL_LABEL;       printf "🌍  IP:"

  # bottom HR and footer placeholder
  tput cup $ROW_HR2 0; printf "${FG_CYAN}%s${RESET}" "$hr_line"
}

print_val() {
  # args: ROW TEXT  (value area is cleaned each update)
  local row=$1; shift
  local text="$*"
  local cols=$(tput cols)
  local width=$((cols - COL_VALUE - 1))
  [ $width -lt 20 ] && width=20
  local padded=$(printf "%-${width}s" "$text")
  tput cup $row $COL_VALUE
  printf "${BOLD}%s${RESET}" "$padded"
}

cleanup() {
  tput cnorm 2>/dev/null
  stty echo 2>/dev/null
  tput sgr0 2>/dev/null
  tput rmcup 2>/dev/null
}

STOP=0
trap 'STOP=1' INT TERM
trap 'make_hr; tput clear; draw_title; draw_static_labels' WINCH

# prepare screen
tput smcup 2>/dev/null         # switch to alt screen
tput civis 2>/dev/null         # hide cursor
stty -echo 2>/dev/null
make_hr
tput clear
draw_title
draw_static_labels

UTXO_TARGET=$(get_utxo_cache_target_mib)

while [ $STOP -eq 0 ]; do
  INFO=$($CLI getblockchaininfo 2>/dev/null)
  NETI=$($CLI getnetworkinfo 2>/dev/null)

  if [ -z "$INFO" ] || [ -z "$NETI" ]; then
    print_val $R_BLOCKS  "bitcoin-cli could not connect to bitcoind."
    print_val $R_PROGRESS "Check the service and $CONF"
    print_val $R_PEERS   "Tip: sudo systemctl status bitcoind"
    tput cup $R_FOOT 0; printf "Refreshing every ${INTERVAL}s (Ctrl+C to exit)"
    sleep $INTERVAL; continue
  fi

  BLOCKS=$(json_get_number "$INFO" "blocks")
  HEADERS=$(json_get_number "$INFO" "headers")
  PROGRAW=$(json_get_float  "$INFO" "verificationprogress")
  PEERS=$(json_get_number  "$NETI" "connections")
  [ -n "$PROGRAW" ] && PROG_PCT=$(awk "BEGIN {printf \"%.2f\", $PROGRAW*100}") || PROG_PCT="n/a"

  UPTIME=$(uptime -p | sed 's/^up //')
  TEMP=$(get_cpu_temp)
  RAM_SUMMARY=$(get_ram_summary)
  BITCOIN_RSS=$(get_bitcoind_rss)
  IP=$(hostname -I 2>/dev/null | awk '{print $1}')

  RX_NOW=$(cat "$BASE/rx_bytes" 2>/dev/null || echo 0)
  TX_NOW=$(cat "$BASE/tx_bytes" 2>/dev/null || echo 0)
  DOWN=$(awk "BEGIN {d=$RX_NOW-$RX_PREV; if (d<0) d=0; printf \"%.2f\", (d*8)/($INTERVAL*1000000)}")
  UP=$(awk   "BEGIN {u=$TX_NOW-$TX_PREV; if (u<0) u=0; printf \"%.2f\", (u*8)/($INTERVAL*1000000)}")
  RX_PREV=$RX_NOW; TX_PREV=$TX_NOW

  UTXO_USED=$(get_utxo_cache_used_mib)

  # ---- Incremental updates (no full redraw) -----------------------
  print_val $R_BLOCKS   "${BLOCKS:-n/a} / ${HEADERS:-n/a}"
  print_val $R_PROGRESS "${PROG_PCT}%"
  print_val $R_PEERS    "${PEERS:-n/a}"
  print_val $R_UPTIME   "${UPTIME:-n/a}"
  print_val $R_TEMP     "$TEMP"
  print_val $R_RAM      "$RAM_SUMMARY   (bitcoind RSS: $BITCOIN_RSS)"

  if [ -n "$UTXO_USED" ] && [ "$UTXO_USED" != "n/a" ]; then
    if [ -n "$UTXO_TARGET" ] && [ "$UTXO_TARGET" != "n/a" ]; then
      print_val $R_UTXO  "$UTXO_USED MiB  /  target $UTXO_TARGET MiB"
    else
      print_val $R_UTXO  "$UTXO_USED MiB"
    fi
  else
    if [ -n "$UTXO_TARGET" ] && [ "$UTXO_TARGET" != "n/a" ]; then
      print_val $R_UTXO  "n/a  /  target $UTXO_TARGET MiB"
    else
      print_val $R_UTXO  "n/a"
    fi
  fi

  print_val $R_NET "iface $IFACE   ↓ ${DOWN} Mbit/s   ↑ ${UP} Mbit/s"
  print_val $R_IP  "${IP:-n/a}"

  tput cup $R_FOOT 0; printf "Refreshing every ${INTERVAL}s (Ctrl+C to exit)"

  # sleep loop that still reacts fast to Ctrl+C
  for ((i=0;i<INTERVAL;i++)); do [ $STOP -ne 0 ] && break; sleep 1; done
done

cleanup
echo "Exiting monitor."