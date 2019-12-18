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

# command: lndmanage
function lndmanage() {
  if [ $(cat /mnt/hdd/raspiblitz.conf 2>/dev/null | grep -c "lndmanage=on") -eq 1 ]; then
    cd lndmanage
    source venv/bin/activate
    echo "starting .. to exit enter ---> deactivate"
    lndmanage
  else
    echo "lndmanage not install - to install run:"
    echo "sudo /home/admin/config.scripts/bonus.lndmanage.sh on"
  fi
}


