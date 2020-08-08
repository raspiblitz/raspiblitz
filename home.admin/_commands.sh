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

# command: balance
# switch to the bos user for Balance of Satoshis
function balance() {
  if [ $(cat /mnt/hdd/raspiblitz.conf 2>/dev/null | grep -c "bos=on") -eq 1 ]; then
    sudo su - bos
  else
    echo "Balance of Satoshis is not installed - to install run:"
    echo "/home/admin/config.scripts/bonus.bos.sh on"
  fi
}

# command: jmarket
# switch to the joinmarket user for the JoininBox menu
function jmarket() {
  if [ $(cat /mnt/hdd/raspiblitz.conf 2>/dev/null | grep -c "joinmarket=on") -eq 1 ]; then
    sudo su - joinmarket
  else
    echo "JoinMarket is not installed - to install run:"
    echo "sudo /home/admin/config.scripts/bonus.joinmarket.sh on"
  fi
}
