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

# command: restart
function restart() {
  cd /home/admin
  ./XXshutdown.sh reboot
}

# command: restart
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


