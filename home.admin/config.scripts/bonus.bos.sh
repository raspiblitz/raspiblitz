#!/bin/bash

# versioning:
# https://github.com/alexbosworth/balanceofsatoshis/blob/master/package.json#L85
# https://www.npmjs.com/package/balanceofsatoshis

BOSVERSION="19.3.4"

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "config script to install, update or uninstall Balance of Satoshis"
 echo "bonus.bos.sh [on|off|menu|update|telegram]"
 echo "installs the version $BOSVERSION by default"
 exit 1
fi

source /mnt/hdd/raspiblitz.conf

# show info menu
if [ "$1" = "menu" ]; then

  text="
Balance of Satoshis is a command line tool.
Type: 'bos' in the command line to switch to the dedicated user.
Then see 'bos help' for the options. Usage:
https://github.com/alexbosworth/balanceofsatoshis/blob/master/README.md
"

  whiptail --title " Info Balance of Satoshis" --yes-button "OK" --no-button "OPTIONS" --yesno "${text}" 10 75
  result=$?
  sudo /home/admin/config.scripts/blitz.display.sh hide
  echo "option (${result}) - please wait ..."

  # exit when user presses OK to close menu
  if [ ${result} -eq 0 ]; then
    exit 0
  fi

  # Balance of Satoshis OPTIONS menu
  OPTIONS=()
  OPTIONS+=(TELEGRAM-SETUP "Setup or renew BoS telegram bot")
  if [ -e /etc/systemd/system/bos-telegram.service ]; then
    OPTIONS+=(TELEGRAM-DISABLE "Remove BoS telegram bot service")
  else
    OPTIONS+=(TELEGRAM-SERVICE "Install BoS telegram bot as a service")
  fi

  WIDTH=66
  CHOICE_HEIGHT=$(("${#OPTIONS[@]}/2+1"))
  HEIGHT=$((CHOICE_HEIGHT+7))
  CHOICE=$(dialog --clear \
                --title " BoS - Options" \
                --ok-label "Select" \
                --cancel-label "Back" \
                --menu "Choose one of the following options:" \
                $HEIGHT $WIDTH $CHOICE_HEIGHT \
                "${OPTIONS[@]}" \
                2>&1 >/dev/tty)

  case $CHOICE in
        TELEGRAM-DISABLE)
            clear
            /home/admin/config.scripts/bonus.bos.sh telegram off
            echo
            echo "OK telegram disabled."
            echo "PRESS ENTER to continue"
            read key
            exit 0
            ;;
        TELEGRAM-SETUP)
            clear
            whiptail --title " First time setup instructions " \
            --yes-button "Back" \
            --no-button "Setup" \
            --yesno "1. Create your telegram bot: https://t.me/botfather\n
2. BoS asks for HTTP API Token given from telegram.\n
3. BoS asks for your connection code (Bot command: /connect)\n
Start BoS telegram setup now?" 14 72
            if [ "$?" != "1" ]; then
              exit 0
            fi
            sudo bash /home/admin/config.scripts/bonus.bos.sh telegram setup
            echo
            echo "OK Balance of Satoshis telegram setup done."
            echo "PRESS ENTER to continue"
            read key
            exit 0
            ;;
        TELEGRAM-SERVICE)
            clear
            connectMsg="
Start chatting with the bot for connect code (/connect)\n
Please enter the CONNECT CODE from your telegram bot
"
            connectCode=$(whiptail --inputbox "$connectMsg" 14 62 --title "Connect Telegram Bot" 3>&1 1>&2 2>&3)
            exitstatus=$?
            if [ $exitstatus = 0 ]; then
              connectCode=$(echo "${connectCode}" | cut -d " " -f1)
            else
              exit 0
            fi
            /home/admin/config.scripts/bonus.bos.sh telegram on ${connectCode}
            echo
            echo "OK BoS telegram service active."
            echo "PRESS ENTER to continue"
            read key
            exit 0
            ;;
        *)
            clear
            exit 0
  esac

  exit 0
fi

# telegram on
if [ "$1" = "telegram" ] && [ "$2" = "on" ] && [ "$3" != "" ] ; then
  sudo rm /etc/systemd/system/bos-telegram.service 2>/dev/null

  # install service
  echo "*** INSTALL BoS Telegram ***"
  cat <<EOF | sudo tee /etc/systemd/system/bos-telegram.service >/dev/null
# systemd unit for bos telegram

[Unit]
Description=Balance of Satoshis Telegram Bot
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
ExecStart=/home/bos/.npm-global/bin/bos telegram --connect $3 -v
User=bos
Group=bos
Restart=always
TimeoutSec=120
RestartSec=15

[Install]
WantedBy=multi-user.target
EOF

  sudo systemctl enable bos-telegram
  sudo systemctl start bos-telegram

  # check for error
  isDead=$(sudo systemctl status bos-telegram | grep -c 'inactive (dead)')
  if [ ${isDead} -eq 1 ]; then
    echo "error='Service Failed'"
    exit 0
  fi

  exit 0
fi

# telegram off
if [ "$1" = "telegram" ] && [ "$2" = "off" ]; then
  echo "*** DISABLE BoS Telegram ***"
  isInstalled=$(sudo ls /etc/systemd/system/bos-telegram.service 2>/dev/null | grep -c 'bos-telegram.service')
  if [ ${isInstalled} -eq 1 ]; then
    sudo systemctl stop bos-telegram
    sudo systemctl disable bos-telegram
    sudo rm /etc/systemd/system/bos-telegram.service
    echo "OK bos-telegram.service removed."
  else
    echo "bos-telegram.service is not installed."
  fi

  echo "result='OK'"
  exit 0
fi

# telegram bot setup
if [ "$1" = "telegram" ] && [ "$2" = "setup" ]; then
  /home/admin/config.scripts/bonus.bos.sh telegram off
  echo "*** SETUP BoS Telegram ***"
  echo "Wait to start 'bos telegram --reset-api-key' (CTRL + C when done) ..."
  sudo -u bos /home/bos/.npm-global/bin/bos telegram --reset-api-key
fi

# install
if [ "$1" = "1" ] || [ "$1" = "on" ]; then

  if [ $(sudo ls /home/bos/.npmrc 2>/dev/null | grep -c ".npmrc") -gt 0 ]; then
    echo "# FAIL - bos already installed"
    sleep 3
    exit 1
  fi

  echo "*** INSTALL BALANCE OF SATOSHIS ***"
  # check and install NodeJS
  /home/admin/config.scripts/bonus.nodejs.sh on

  # create bos user
  USERNAME=bos
  echo "# add the user: ${USERNAME}"
  sudo adduser --system --group --shell /bin/bash --home /home/${USERNAME} ${USERNAME}
  echo "Copy the skeleton files for login"
  sudo -u ${USERNAME} cp -r /etc/skel/. /home/${USERNAME}/

  echo "# Create data folder on the disk"
  # move old data if present
  sudo mv /home/bos/.bos /mnt/hdd/app-data/ 2>/dev/null
  echo "# make sure the data directory exists"
  sudo mkdir -p /mnt/hdd/app-data/.bos
  echo "# symlink"
  sudo rm -rf /home/bos/.bos # not a symlink.. delete it silently
  sudo ln -s /mnt/hdd/app-data/.bos/ /home/bos/.bos
  sudo chown bos:bos -R /mnt/hdd/app-data/.bos

  # set up npm-global
  sudo -u bos mkdir /home/bos/.npm-global
  sudo -u bos npm config set prefix '/home/bos/.npm-global'
  sudo bash -c "echo 'PATH=$PATH:/home/bos/.npm-global/bin' >> /home/bos/.bashrc"

  # make sure symlink to central app-data directory exists ***"
  sudo rm -rf /home/bos/.lnd  # not a symlink.. delete it silently
  # create symlink
  sudo ln -s "/mnt/hdd/app-data/lnd/" "/home/bos/.lnd"

  # add user to group with admin access to lnd
  sudo /usr/sbin/usermod --append --groups lndadmin bos

  # install bos
  # check latest version:
  # https://github.com/alexbosworth/balanceofsatoshis/blob/master/package.json#L70
  sudo -u bos npm install -g balanceofsatoshis@$BOSVERSION
  if ! [ $? -eq 0 ]; then
    echo "FAIL - npm install did not run correctly, aborting"
    exit 1
  fi

  # add cli autocompletion https://www.npmjs.com/package/caporal/v/0.7.0#if-you-are-using-bash
  sudo -u bos bash -c 'echo "source <(bos completion bash)" >> /home/bos/.bashrc'

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set bos "on"

  echo "# Usage: https://github.com/alexbosworth/balanceofsatoshis/blob/master/README.md"
  echo "# To start type: 'sudo su bos' in the command line."
  echo "# Then see 'bos help' for options."
  echo "# To exit the user - type 'exit' and press ENTER"

  exit 0
fi


# switch off
if [ "$1" = "0" ] || [ "$1" = "off" ]; then

  # setting value in raspi blitz config
  /home/admin/config.scripts/blitz.conf.sh set bos "off"

  echo "*** REMOVING BALANCE OF SATOSHIS ***"
  sudo userdel -rf bos
  echo "# OK, bos is removed."
  exit 0

fi


# update
if [ "$1" = "update" ]; then
  echo "*** UPDATING BALANCE OF SATOSHIS ***"
  sudo -u bos npm i -g balanceofsatoshis
  echo "*** Updated to the latest in https://github.com/alexbosworth/balanceofsatoshis ***"
  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit
