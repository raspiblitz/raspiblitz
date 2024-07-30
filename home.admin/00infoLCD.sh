#!/bin/bash

### USER PI AUTOSTART (LCD Display)
# this script gets started by the autologin of the pi user and
# and its output is gets displayed on the LCD or the RaspiBlitz

function usage() {
  echo -e "This script gets started by the autologin of the pi user and "
  echo -e "and its output is gets displayed on the LCD or the RaspiBlitz."
  echo -e ""
  echo -e "Usage: $0 [-h|--help] [-v*|--verbose] [-p|--pause STRING]"
  echo -e ""
  echo -e "  -h, --help\t\tprint this help message"
  echo -e "  -v, --verbose\t\tbe more verbose"
  echo -e "  -p, --pause STRING\ttime in seconds to pause"
  echo -e ""
}

# Default Values
verbose=0
pause=3

# this is used by touchscreen and command 'status'
# TODO: remove on v1.8
while [[ "$1" == -* ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    -v*)
      (( verbose += ${#1} - 1 ))
      ;;
    --verbose)
      (( verbose++ ))
      ;;
   -p|--pause)
      shift
      pause="$1"
      ;;
    --)
      shift
      break
      ;;
    *)
    echo "Unrecognized option $1."
    echo ""
    usage
    exit 1
    ;;
  esac
  shift
done

if ! [[ "$pause" =~ ^[[:digit:]]+$ ]]; then
  echo "pause must be a positive integer or 0." >&2
  exit 1
fi

# CONFIGFILE - configuration of RaspiBlitz
configFile="/mnt/hdd/raspiblitz.conf"

# INFOFILE - state data from bootstrap
infoFile="/home/admin/raspiblitz.info"

# check that user is pi
if [ "$USER" != "pi" ] && [ "$USER" != "root" ]; then
  echo "plz run as user pi or with sudo"
  exit 1
fi

# display a 10s startup time
source /home/admin/_version.info
if [ "$pause" -ne "0" ]; then
    dialog --pause "  Starting RaspiBlitz v${codeVersion} ..." 8 58 ${pause}
fi

# DISPLAY LOOP
chain=""
while :
    do

    ###########################
    # CHECK BASIC DATA
    ###########################   

    # get config info if already available (with state value)
    source ${infoFile}

    configExists=$(ls "${configFile}" 2>/dev/null | grep -c '.conf')
    if [ ${configExists} -eq 1 ]; then
      source ${configFile}
      source <(/home/admin/config.scripts/network.aliases.sh getvars)
    fi

    if [ "${setupPhase}" != "done" ] || [ "${state}" == "reboot" ] || [ "${state}" == "shutdown" ] || [ "${state}" == "copytarget" ] || [ "${state}" == "copysource" ]; then

      # show status info during boot & setup & repair on LCD
      if [ "${state}" == "" ]; then
        state="nostate"
      fi
      /home/admin/setup.scripts/eventInfoWait.sh "${state}" "${message}" lcd
      sleep 1
      continue

    fi

    # if lightning is syncing or scanning
    source <(/home/admin/_cache.sh get \
      lightning \
      ln_default_locked \
      btc_default_synced \
      btc_default_online \
      btc_default_sync_initialblockdownload \
      btc_default_blocks_behind \
    )

    if [ "${lightning}" != "" ] && [ "${lightning}" != "none" ] && [ "${ln_default_locked}" == "1" ]; then
      /home/admin/setup.scripts/eventInfoWait.sh "walletlocked" "" lcd
      sleep 3
      continue
    fi

    # when lightning is active - show sync until ln_default_sync_initial_done
    if [ "${lightning}" != "" ] && [ "${lightning}" != "none" ] && [ "${ln_default_sync_initial_done}" == "0" ]; then
      /home/admin/setup.scripts/eventBlockchainSync.sh lcd
      sleep 3
      continue
    fi

    # when btc not online or not synced - show sync screen
    if [ "${btc_default_synced}" != "1" ] || [ "${btc_default_online}" != "1" ]; then
      /home/admin/setup.scripts/eventBlockchainSync.sh lcd
      sleep 3
      continue
    fi

    # no special case - show status display
    /home/admin/00infoBlitz.sh ${chain}net $lightning
    sleep 5

done
