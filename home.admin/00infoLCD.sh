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
if [ "$USER" != "pi" ]; then
  echo "plz run as user pi --> su pi"
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
    source <(/home/admin/_cache.sh get state message)

    configExists=$(ls ${configFile} 2>/dev/null | grep -c '.conf')
    if [ ${configExists} -eq 1 ]; then
      source ${configFile}
      source <(/home/admin/config.scripts/network.aliases.sh getvars)
    fi

    if [ "${setupPhase}" != "done" ] || [ "${state}" == "reboot" ] || [ "${state}" == "shutdown" ] || [ "${state}" == "copytarget" ] || [ "${state}" == "copysource" ] || [ "${state}" == "copystation" ]; then

      # show status info during boot & setup & repair on LCD
      /home/admin/setup.scripts/eventInfoWait.sh "${state}" "${message}" lcd
      sleep 1
      continue

    fi

    # TODO: ALSO SEPARATE GUI/ACTION FOR THE SCANNING / WALLET UNLOCK / ERROR DETECTION 
    # if lightning is syncing or scanning
    source <(sudo /home/admin/config.scripts/blitz.statusscan.sh $lightning)
    if [ "${walletLocked}" == "1" ] || [ "${CLwalletLocked}" == "1" ]; then
      /home/admin/setup.scripts/eventInfoWait.sh "walletlocked" "" lcd
      sleep 3
      continue
    fi

    if [ "${syncedToChain}" != "1" ]; then
      /home/admin/setup.scripts/eventBlockchainSync.sh lcd
      sleep 10
      continue
    fi

    # no special case - show status display
    /home/admin/00infoBlitz.sh $lightning ${chain}net
    sleep 5

done
