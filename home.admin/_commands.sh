#!/bin/bash

# source aliases from /home/admin/_aliases
if [ -f /home/admin/_aliases ];then
  source /home/admin/_aliases
fi

# confirm interrupting commands
confirm=0
function confirmMsg() {
  while true; do
    read -p "$(echo -e "Execute the blitz command '$1'? (y/n): ")" yn
    case $yn in
        [Yy]* ) confirm=1;break;;
        [Nn]* ) confirm=0;break;;
        * ) echo "Please answer yes or no.";;
    esac
  done
}

# SHORTCUT COMMANDS you can call as user 'admin' from terminal

# command: blitz
# calls the the raspiblitz mainmenu (shortcut)
function blitz() {
  cd /home/admin
  ./00raspiblitz.sh
}

# command: blitzhelp
# gives overview of commands
function blitzhelp() {
  echo
  echo "Blitz commands are consolidated here."
  echo
  echo "Menu access:"
  echo "  raspiblitz   menu"
  echo "  menu         menu"
  echo "  bash         menu"
  echo "  repair       menu > repair"
  echo
  echo "Debug:"
  echo "  debug        print debug logs"
  echo "  debug -l     print debug logs with bin link with tor by default"
  echo "  debug -l -n  print debug logs with bin link without tor"
  echo
  echo "Checks:"
  echo "  status       informational Blitz status screen"
  echo "  sourcemode   copy blockchain source modus"
  echo "  check        check if Blitz configuration files are correct"
  echo "  patch [all]  sync all scripts with latest from github and branch"
  echo "  patch code   sync only blitz scripts with latest from github and branch"
  echo "  patch api    sync only Blitz-API with latest from github and branch"
  echo "  patch web    sync only Blitz-WebUI with latest from github and branch"
  echo "  cache        check on chache system state"
  echo "  github       jumping directly into the options to change branch/repo/pr"
  echo
  echo "Development with VM:"
  echo "  sync         sync all repos from shared folder"
  echo "  sync code    sync only main raspiblitz repo from shared folder"
  echo "  sync api     sync only blitz api repo from shared folder"
  echo  
  echo "Power:"
  echo "  restart      restart the node"
  echo "  off          shutdown the node"
  echo
  echo "Display:"
  echo "  hdmi         switch video output to HDMI"
  echo "  lcd          switch video output to LCD"
  echo "  headless     switch video output to HEADLESS"
  echo
  echo "BTC tx:"
  echo "  torthistx    broadcast transaction through Tor to Blockstreams API and into the network"
  echo "  gettx        retrieve transaction from mempool or blockchain and print as JSON"
  echo "  watchtx      retrieve transaction from mempool or blockchain until certain confirmation target"
  echo
  echo "Users:"
  echo "  bos          Balance of Satoshis"
  echo "  chantools    ChanTools"
  echo "  lit          Lightning Terminal"
  echo "  jm           JoinMarket"
  echo "  pyblock      PyBlock"
  echo "  ckbunker     CKbunker"
  echo
  echo "Extras:"
  echo "  whitepaper   download the whitepaper from the blockchain to /home/admin/bitcoin.pdf"
  echo "  notifyme     wrapper for blitz.notify.sh that will send a notification using the configured method and settings"
  echo "  suez         visualize channels (for the default ln implementation and chain when installed)"
  echo "  lnproxy      wrap invoices with lnproxy"
  echo
  echo "LND:"
  echo "  lncli        LND commandline interface (when installed)"
  echo "  balance      your satoshi balance"
  echo "  channels     your lightning channels"
  echo "  fwdreport    show forwarding report"
  echo "  manage       use the lndmanage bonus app"
  echo
  echo "CLN:"
  echo " lightning-cli Core Lightning commandline interface (when installed)"
}

# command: raspiblitz
# calls the the raspiblitz mainmenu (legacy)
function raspiblitz() {
  cd /home/admin
  ./00raspiblitz.sh
}

# command: menu
# calls directly the main menu
function menu() {
  cd /home/admin
  ./00mainMenu.sh
}

# command: repair
# calls directly the repair menu
function repair() {
  cd /home/admin
  ./98repairMenu.sh
}

# command: restart
function restart() {
  echo "Command to restart your RaspiBlitz"
  confirmMsg restart
  if [ $confirm -eq 1 ]; then
    sudo /home/admin/config.scripts/blitz.shutdown.sh reboot
  fi
}

# command: sourcemode
function sourcemode() {
  /home/admin/config.scripts/blitz.copychain.sh source
}

# command: check
function check() {
  /home/admin/config.scripts/blitz.configcheck.py
}

# command: release
function release() {
  firstPARAM=$1
  echo "Command to prepare your RaspiBlitz installation for sd card image:"
  echo "- delete logs"
  echo "- clean raspiblitz.info"
  echo "- delete SSH Pub keys"
  echo "- delete local DNS confs"
  echo "- delete old API conf"
  echo "- delete local WIFI conf"
  echo "- shutdown"
  confirmMsg release
  if [ $confirm -eq 1 ]; then
    /home/admin/config.scripts/blitz.release.sh $firstPARAM
  fi
}

# command: fatpack
function fatpack() {
  echo "Command to be called only on a fresh stopped minimal build to re-pack installs."
  confirmMsg fatpack
  if [ $confirm -eq 1 ]; then
    sudo /home/admin/config.scripts/blitz.fatpack.sh
    # raspberry pi fatpack has lcd display be default
    sudo /home/admin/config.scripts/blitz.display.sh set-display lcd
  fi
}

# command: debug
function debug() {
  clear
  echo "Printing debug logs. Be patient, this should take maximum 2 minutes .."
  sudo rm /var/cache/raspiblitz/debug.log 2>/dev/null
  /home/admin/config.scripts/blitz.debug.sh > /var/cache/raspiblitz/debug.log
  echo "Redacting .."
  /home/admin/config.scripts/blitz.debug.sh redact /var/cache/raspiblitz/debug.log
  sudo chmod 640 /var/cache/raspiblitz/debug.log
  sudo chown root:sudo /var/cache/raspiblitz/debug.log
  if [ "$1" = "-l" ]||[ "$1" = "--link" ]; then
    proxy="-X 5 -x localhost:9050"
    if [ "$2" = "-n" ]||[ "$2" = "--no-tor" ]; then proxy=""; fi
    cat /var/cache/raspiblitz/debug.log | nc ${proxy} termbin.com 9999
  else
    cat /var/cache/raspiblitz/debug.log
  fi
}

# command: patch
# syncs script with latest set github and branch
function patch() {
  if [ "$1" == "" ]; then
    echo "Command to patch your RaspiBlitz from github"
    confirmMsg patch
    if [ $confirm -eq 1 ]; then
      patch all
    fi
  fi

  cd /home/admin

  if [ "$1" == "all" ] || [ "$1" == "code" ]; then
    echo
    echo "#######################################################"
    echo "### UPDATE BLITZ --> SCRIPTS (code)"
    /home/admin/config.scripts/blitz.github.sh -run
  fi

  if [ "$1" == "all" ] || [ "$1" == "api" ]; then
    echo
    echo "#######################################################"
    echo "### UPDATE BLITZ --> API"
    sudo /home/admin/config.scripts/blitz.web.api.sh update-code
  fi

  if [ "$1" == "all" ] || [ "$1" == "web" ]; then
    echo
    echo "#######################################################"
    echo "### UPDATE BLITZ --> WEBUI"
    sudo /home/admin/config.scripts/blitz.web.ui.sh update
  fi

  echo
}

# command: sync
# sync VM with shared folder
function sync() {
  sudo /home/admin/config.scripts/blitz.vm.sh sync ${1}
  echo
}

# command: off
function off() {
  echo "Command to power off your RaspiBlitz"
  confirmMsg off
  if [ $confirm -eq 1 ]; then
    sudo /home/admin/config.scripts/blitz.shutdown.sh
  fi
}

# command: github
# jumpng directly into the options to change branch/repo/pr
function github() {
  cd /home/admin
  ./99updateMenu.sh github
}

# command: hdmi
function hdmi() {
  echo "Command to switch video output of your RaspiBlitz to hdmi"
  confirmMsg hdmi
  if [ $confirm -eq 1 ]; then
    echo "# SWITCHING VIDEO OUTPUT TO --> HDMI"
    sudo /home/admin/config.scripts/blitz.display.sh set-display hdmi
    restart
  fi
}

# command: lcd
function lcd() {
  echo "Command to switch video output of your RaspiBlitz to lcd"
  confirmMsg lcd
  if [ $confirm -eq 1 ]; then
    echo "# SWITCHING VIDEO OUTPUT TO --> LCD"
    sudo /home/admin/config.scripts/blitz.display.sh set-display lcd
    restart
  fi
}

# command: headless
function headless() {
  echo "Command to switch off any video output of your RaspiBlitz (ssh only)"
  confirmMsg headless
  if [ $confirm -eq 1 ]; then
    echo "# SWITCHING VIDEO OUTPUT TO --> HEADLESS"
    sudo /home/admin/config.scripts/blitz.display.sh set-display headless
    restart
  fi
}

# command: cache
function cache() {
  sudo /home/admin/_cache.sh $@
}

# command: torthistx
function torthistx() {
  if [ $(cat /mnt/hdd/raspiblitz.conf 2>/dev/null | grep -c "runBehindTor=on") -eq 1 ]; then
    echo "Broadcasting transaction through Tor to Blockstreams API and into the network."
    curl --socks5-hostname localhost:9050 -d $1 -X POST http://explorerzydxu5ecjrkwceayqybizmpjjznk5izmitf2modhcusuqlid.onion/api/tx
  else
    echo "Not running behind Tor - to install run:"
    echo "sudo /home/admin/config.scripts/tor.network.sh on"
  fi
}

# command: status
# start the status screen in the terminal
function status() {
  echo
  echo "Keep X pressed to EXIT loop ... (please wait)"
  echo
  sleep 4
  while :
  do
    # show the same info as on LCD screen
    # 00infoBlitz.sh <testnet|mainnet|signet> <cl|lnd>
    /home/admin/00infoBlitz.sh $1 $2
    # wait 6 seconds for user exiting loop
    #echo
    #echo -en "Screen is updating in a loop .... press 'x' now to get back to menu."
    read -n 1 -t 6 keyPressed
    # check if user wants to abort session
    if [ "${keyPressed}" = "x" ]; then
      echo
      echo "Returning to menu ....."
      sleep 4
      break
    fi
  done
}

# command: lnbalance
# show balance report
function balance() {
  echo "*** YOUR SATOSHI BALANCES ***"
  /home/admin/config.scripts/lnd.balance.sh
}

# command: lnchannels
# show channel listing
function channels() {
  echo "*** YOUR LIGHTNING CHANNELS ***"
  /home/admin/config.scripts/lnd.channels.sh
}

# command: lnfwdreport
# show forwarding report
function fwdreport() {
  /home/admin/config.scripts/lnd.fwdreport.sh -menu
}

# command: bos
# switch to the bos user for Balance of Satoshis
function bos() {
  if [ $(grep -c "bos=on" < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "# switching to the bos user with the command: 'sudo su - bos'"
    echo "# use command 'exit' and then 'raspiblitz' to return to menu"
    echo "# use command 'bos --help' to list all possible options"
    sudo su - bos
    echo "# use command 'raspiblitz' to return to menu"
  else
    echo "Balance of Satoshis is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.bos.sh on"
  fi
}

# command: pyblock
# switch to the pyblock user for PyBLOCK
function pyblock() {
  if [ $(grep -c "pyblock=on" < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    cd /home/pyblock/pyblock
    sudo -u pyblock poetry run python -m pybitblock.console
  else
    echo "PyBlock is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.pyblock.sh on"
  fi
}

# command: chantools
# switch to the bitcoin user for chantools
function chantools() {
  if [ $(grep -c "chantools=on" < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "# switching to the bitcoin user with the command: 'sudo su - bitcoin'"
    echo "# use command 'exit' and then 'raspiblitz' to return to menu"
    echo "# use command 'chantools' again to start"
    sudo su - bitcoin
    echo "# use command 'raspiblitz' to return to menu"
  else
    echo "chantools is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.chantools.sh on"
  fi
}

# command: jm
# switch to the joinmarket user for the JoininBox menu
function jm() {
  if [ $(grep -c "joinmarket=on"  < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "# switching to the joinmarket user with the command: 'sudo su - joinmarket'"
    sudo su - joinmarket
    echo "# use command 'raspiblitz' to return to menu"
  else
    echo "JoinMarket is not installed - to install run:"
    echo "sudo /home/admin/config.scripts/bonus.joinmarket.sh on"
  fi
}

# command: manage
# switch to lndmanage env
function manage() {
  if [ $(cat /mnt/hdd/raspiblitz.conf 2>/dev/null | grep -c "lndmanage=on") -eq 1 ]; then
    cd /home/admin/lndmanage
    source venv/bin/activate
    echo "NOTICE: Needs at least one active channel to run without error."
    echo "to exit (venv) enter ---> deactivate"
    lndmanage
  else
    echo "lndmanage not installed - to install run:"
    echo "sudo /home/admin/config.scripts/bonus.lndmanage.sh on"
  fi
}

# command: ckbunker
# switch to the ckbunker user
function ckbunker() {
  if [ $(grep -c "ckbunker=on"  < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "# switching to the ckbunker user with the command: 'sudo su - ckbunker'"
    sudo su - ckbunker
    echo "# use command 'raspiblitz' to return to menu"
  else
    echo "ckbunker is not installed - to install run:"
    echo "sudo /home/admin/config.scripts/bonus.ckbunker.sh on"
  fi
}

# command: lit
# switch to the lit user for the loop, pool & faraday services
function lit() {
  if [ $(grep -c "lit=on"  < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "# switching to the lit user with the command: 'sudo su - lit'"
    echo "# use command 'exit' and then 'raspiblitz' to return to menu"
    echo "# see the prefilled parameters with 'alias'"
    echo "# use the commands: 'lncli', 'lit-frcli', 'lit-loop', 'lit-pool'"
    sudo su - lit
    echo "# use command 'raspiblitz' to return to menu"
  else
    echo "LIT is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.lit.sh on"
  fi
}

# aliases for lit
# switch to the pool user for the Pool Service
if [ -f "/mnt/hdd/raspiblitz.conf" ] && [ $(grep -c "lit=on"  < /mnt/hdd/raspiblitz.conf) -gt 0 ]; then
  source /mnt/hdd/raspiblitz.conf
  alias lit-frcli="sudo -u lit frcli --rpcserver=localhost:8443 \
    --tlscertpath=/home/lit/.lit/tls.cert \
    --macaroonpath=/home/lit/.faraday/${chain}net/faraday.macaroon"
  alias lit-loop="sudo -u lit loop --rpcserver=localhost:8443 \\
    --tlscertpath=/home/lit/.lit/tls.cert \\
    --macaroonpath=/home/lit/.loop/${chain}net/loop.macaroon"
  alias lit-pool="sudo -u lit pool --rpcserver=localhost:8443 \
    --tlscertpath=/home/lit/.lit/tls.cert \
    --macaroonpath=/home/lit/.pool/${chain}net/pool.macaroon"
fi

# command: gettx
# retrieve transaction from mempool or blockchain and print as JSON
# $ gettx "f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16"
function gettx() {
    tx_id="${1:-f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16}"
    if result=$(bitcoin-cli getrawtransaction "${tx_id}" 1 2>/dev/null); then
        echo "${result}"
    else
        echo "{\"error\": \"unable to find TX\", \"tx_id\": \"${tx_id}\"}"
        return 1
    fi
}

# command: watchtx
# try to retrieve transaction from mempool or blockchain until certain confirmation target
# is reached and then exit cleanly. Default is to wait for 2 confs and to sleep for 60 secs.
# $ watchtx "f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16" 6 30
function watchtx() {
    tx_id="${1}"
    wait_n_confirmations="${2:-2}"
    sleep_time="${3:-60}"

    echo "Waiting for ${wait_n_confirmations} confirmations"

    while true; do

      if result=$(bitcoin-cli getrawtransaction "${tx_id}" 1 2>/dev/null); then
        confirmations=$(echo "${result}" | jq .confirmations)

        if [[ "${confirmations}" -ge "${wait_n_confirmations}" ]]; then
          printf "confirmations: ${confirmations} - target reached!\n"
          return 0
        else
          printf "confirmations: ${confirmations} - "
        fi

      else
        printf "unable to find TX - "
      fi

      printf "sleeping for ${sleep_time} seconds...\n"
      sleep ${sleep_time}

    done
}

# command: notifyme
# A wrapper for blitz.notify.sh that will send a notification using the configured
# method and settings.
# This makes sense when waiting for commands to finish and then sending a notification.
# $ notifyme "Hello there..!"
# $ ./run_job_which_takes_long.sh && notifyme "I'm done."
# $ ./run_job_which_takes_long.sh && notifyme "success" || notifyme "fail"
function notifyme() {
    content="${1:-Notified}"
    /home/admin/config.scripts/blitz.notify.sh send "${content}"
}

# command: whitepaper
# downloads the whitepaper from the blockchain to /home/admin/bitcoin.pdf
function whitepaper() {
  cd /home/admin
  ./config.scripts/bonus.whitepaper.sh on
}

# command: qr ["string"]
# shows a QR code from the string
function qr() {
  if [ ${#1} -eq 0 ]; then
    echo "# Error='missing string'"
  fi
  echo
  echo "Displaying the text:"
  echo "$1"
  echo
  qrencode -t ANSIUTF8 "${1}"
  echo "(To shrink QR code: MacOS press CMD- / Linux press CTRL-)"
  echo
}

# command: bm
# switch to the bitcoinminds user for the 'BitcoinMinds.org' in your local environment
function bm() {
  if [ $(grep -c "bitcoinminds=on"  < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo ""
    echo "# ***"
    echo "# Switching to the bitcoinminds user with the command: 'sudo su - bitcoinminds'"
    echo "# ***"
    echo ""
    sudo su - bitcoinminds
    echo "# Use command 'raspiblitz' to return to menu"
  else
    echo "BitcoinMinds script is not installed - to install run:"
    echo "sudo /home/admin/config.scripts/bonus.bitcoinminds.sh on"
  fi
}

# command: lnproxy
function lnproxy() {
  source /mnt/hdd/raspiblitz.conf
  if [ $# -gt 0 ]; then
    invoice=$1
  else
    echo "Paste the invoice to be wrapped and press enter:"
    read -r invoice
  fi
  if systemctl is-active --quiet tor@default; then
    if [ -z "${lnproxy_override_tor}" ]; then
      lnproxy_override_tor="rdq6tvulanl7aqtupmoboyk2z3suzkdwurejwyjyjf4itr3zhxrm2lad.onion/api"
    fi
    wrapped=$(torsocks curl -sS http://${lnproxy_override_tor}/${invoice})
    echo
    echo "Requesting a wrapped invoice from ${lnproxy_override_tor}"
  else
    if [ -z "${lnproxy_override_clearnet}" ]; then
      lnproxy_override_clearnet="lnproxy.org/api"
    fi
    wrapped=$(curl -sS https://${lnproxy_override_clearnet}/${invoice})
    echo
    echo "Requesting a wrapped invoice from ${lnproxy_override_clearnet}"
  fi
  echo
  /home/admin/config.scripts/blitz.check-invoice-wrap.py "$1" "$wrapped"
  echo
  echo $wrapped
}

# command: suez
function suez() {
  source /mnt/hdd/raspiblitz.conf
  if [ ${lightning} = 'cl' ] || [ ${lightning} = 'lnd' ]; then
    if [ ! -f /home/bitcoin/suez/suez ];then
      /home/admin/config.scripts/bonus.suez.sh on
    fi
    source <(/home/admin/config.scripts/network.aliases.sh getvars ${lightning} ${chain}net)
    cd /home/bitcoin/suez || exit 1
    clear
    echo "# Showing the channels of ${lightning} ${chain}net - consider reducing the font size (press CTRL- or CMD-)"
    if [ ${lightning} = cl ]; then
      sudo -u bitcoin poetry run /home/bitcoin/suez/suez \
      --client=c-lightning --client-args=--conf=${CLCONF}
    elif [ ${lightning} = lnd ]; then
      sudo -u bitcoin poetry run /home/bitcoin/suez/suez \
      --client-args=-n=${CHAIN} \
      --client-args=--rpcserver=localhost:1${L2rpcportmod}009
    fi
    cd
  else
    echo "# Lightning is ${lightning}"
  fi
}
