#!/bin/bash

# SHORTCUT COMMANDS you can call as user 'admin' from terminal

# command: raspiblitz
# calls the the raspiblitz mainmenu (legacy)
function raspiblitz() {
  cd /home/admin
  ./00raspiblitz.sh
}

# command: blitz
# calls the the raspiblitz mainmenu (shortcut)
function blitz() {
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

# command: sourcemode
function sourcemode() {
  cd /home/admin
  ./98repairMenu.sh sourcemode
}

# command: check
function check() {
  /home/admin/config.scripts/blitz.configcheck.py
}

# command: debug
function debug() {
  cd /home/admin
  ./XXdebugLogs.sh
}

# command: patch
# syncs script with latest set github and branch
function patch() {
  cd /home/admin
  ./XXsyncScripts.sh -run
}

# command: restart
function restart() {
  cd /home/admin
  ./XXshutdown.sh reboot
}

# command: off
function off() {
  cd /home/admin
  ./XXshutdown.sh
}

# command: github
# jumpng directly into the options to change branch/repo/pr
function github() {
  cd /home/admin
  ./99updateMenu.sh github
}

# command: hdmi
function hdmi() {
  echo "# SWITCHING VIDEO OUTPUT TO --> HDMI"
  sudo /home/admin/config.scripts/blitz.lcd.sh hdmi on
}

# command: lcd
function lcd() {
  echo "# SWITCHING VIDEO OUTPUT TO --> LCD"
  sudo /home/admin/config.scripts/blitz.lcd.sh hdmi off
}

# command: manage
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

# command: torthistx
function torthistx() {
  if [ $(cat /mnt/hdd/raspiblitz.conf 2>/dev/null | grep -c "runBehindTor=on") -eq 1 ]; then
    echo "Broadcasting transaction through Tor to Blockstreams API and into the network."
    curl --socks5-hostname localhost:9050 -d $1 -X POST http://explorerzydxu5ecjrkwceayqybizmpjjznk5izmitf2modhcusuqlid.onion/api/tx
  else
    echo "Not running behind Tor - to install run:"
    echo "sudo /home/admin/config.scripts/internet.tor.sh on"
  fi
}

# command: status
# start the status screen in the terminal
function status() {
  echo "Gathering data - please wait a moment..."
  sudo -u pi /home/admin/00infoLCD.sh --pause 0
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
  _temp="./download/dialog.$$"
  _error="./.error.out"

  # load raspiblitz config data (with backup from old config)
  source /home/admin/raspiblitz.info
  source /mnt/hdd/raspiblitz.conf
  if [ ${#network} -eq 0 ]; then network=`cat .network`; fi
  if [ ${#network} -eq 0 ]; then network="bitcoin"; fi
  if [ ${#chain} -eq 0 ]; then
    echo "gathering chain info ... please wait"
    chain=$(${network}-cli getblockchaininfo | jq -r '.chain')
  fi

  # let user enter a <pubkey>@host
  l1="Enter the number of days to query:"
  l2="e.g. '7' will query the last 7 days"
  dialog --title "Create a forwarding event report" \
--backtitle "Lightning ( ${network} | ${chain} )" \
--inputbox "$l1\n$l2" 10 60 7 2>$_temp
_input=$(cat $_temp | xargs )
  shred -u $_temp
  if [ ${#_input} -eq 0 ]; then
    exit 1
  fi
  clear
  /home/admin/config.scripts/lnd.fwdreport.sh -n ${chain}net -c ${network} -- ${_input}
}

# command: bos
# switch to the bos user for Balance of Satoshis
function bos() {
  if [ $(grep -c "bos=on" < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "# switching to the bos user with the command: 'sudo su - bos'"
    sudo su - bos
  else
    echo "Balance of Satoshis is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.bos.sh on"
  fi
}

# command: pyblock
# switch to the pyblock user for PyBLOCK
function pyblock() {
  if [ $(grep -c "pyblock=on" < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "# switching to the pyblock user with the command: 'sudo su - pyblock'"
    sudo su - pyblock
  else
    echo "PyBlock is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.pyblock.sh on"
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

# command: faraday
# switch to the faraday user for the Faraday Service
function faraday() {
  if [ $(grep -c "faraday=on"  < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "# switching to the faraday user with the command: 'sudo su - faraday'"
    echo "# use command 'exit' and then 'raspiblitz' to return to menu"
    echo "# use command 'frcli --help' now to get more info"
    sudo su - faraday
  else
    echo "Faraday is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.faraday.sh on"
  fi
}

# command: loop
# switch to the loop user for the Lightning Loop Service
function loop() {
  if [ $(grep -c "loop=on"  < /mnt/hdd/raspiblitz.conf) -eq 1 ]; then
    echo "# switching to the loop user with the command: 'sudo su - loop'"
    echo "# use command 'exit' and then 'raspiblitz' to return to menu"
    echo "# use command 'loop --help' now to get more info"
    sudo su - loop
  else
    echo "Lightning Loop is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.loop.sh on"
  fi
}

# command: pool
# switch to the pool user for the Pool Service
function pool() {
  if [ $(grep -c "pool=on"  < /mnt/hdd/raspiblitz.conf) -gt 0 ]; then
    echo "# switching to the pool user with the command: 'sudo su - pool'"
    echo "# use command 'exit' and then 'raspiblitz' to return to menu"
    echo "# use command 'pool --help' now to get more info"
    sudo su - pool
  else
    echo "Pool is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.pool.sh on"
  fi
}

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
