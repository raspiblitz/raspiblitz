#!/bin/bash

# SHORTCUT COMMANDS you can call as user 'admin' from terminal

# command: raspiblitz
# calls the the raspiblitz mainmenu
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
function menu() {
  cd /home/admin
  ./98repairMenu.sh
}