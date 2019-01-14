#!/bin/bash

# SHORTCUT COMMANDS you can call as user 'admin' from terminal

# command: raspiblitz
# calls the the raspiblitz mainmenu
function raspiblitz() {
  cd /home/admin
  ./00mainMenu.sh
}