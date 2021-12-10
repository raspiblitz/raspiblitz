#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "script to enable/disable or send notifications"
 echo "blitz.notify.sh on"
 echo "blitz.notify.sh off"
 echo "blitz.notify.sh send \"Message to be send via configured method\""
 exit 1
fi

# load config values
source /home/admin/raspiblitz.info 2>/dev/null
source /mnt/hdd/raspiblitz.conf 2>/dev/null
if [ ${#network} -eq 0 ]; then
  echo "FAIL - was not able to load config data / network"
  exit 1
fi

# make sure main "notify" setting is present (add with default if not)
if ! grep -Eq "^notify=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notify=off" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

# check all other settings and add if missing
if ! grep -Eq "^notifyMethod=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMethod=mail" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

# Mail
if ! grep -Eq "^notifyMailTo=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailTo=mail@example.com" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

if ! grep -Eq "^notifyMailServer=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailServer=mail.example.com" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

if ! grep -Eq "^notifyMailPort=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailPort=587" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

if ! grep -Eq "^notifyMailHostname=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailHostname=$(hostname)" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

if ! grep -Eq "^notifyMailFromAddress=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailFromAddress=rb@example.com" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

if ! grep -Eq "^notifyMailFromName=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailFromName=\"RB User\"" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

if ! grep -Eq "^notifyMailUser=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailUser=username" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

if ! grep -Eq "^notifyMailPass=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailPass=password" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

if ! grep -Eq "^notifyMailEncrypt=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailEncrypt=off" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

if ! grep -Eq "^notifyMailToCert=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailToCert=/mnt/hdd/notify_mail_cert.pem" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

# Ext
if ! grep -Eq "^notifyExtCmd=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyExtCmd=/usr/bin/printf" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

# reload settings
source /mnt/hdd/raspiblitz.conf 2>/dev/null


###################
# switch on
###################
if [ "$1" = "1" ] || [ "$1" = "on" ]; then
  echo "switching the NOTIFY ON"

  # install mstmp if not already present
  if ! command -v msmtp >/dev/null; then
    [ -z "$(find -H /var/lib/apt/lists -maxdepth 0 -mtime -7)" ] && sudo apt-get update
    sudo apt-get install -y msmtp
  fi

  # install python lib for smime into virtual env
  sudo -H /usr/bin/python3 -m pip install smime

  # write ssmtp config
  cat << EOF | sudo tee /etc/msmtprc >/dev/null
# Set default values for all following accounts.
defaults
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt

account mail
host ${notifyMailServer}
port ${notifyMailPort}
from ${notifyMailFromAddress}
auth on
user ${notifyMailUser}
password ${notifyMailPass}

# Set a default account
account default : mail

EOF

  # edit raspi blitz config
  echo "editing /mnt/hdd/raspiblitz.conf"
  sudo sed -i "s/^notify=.*/notify=on/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi


###################
# switch off
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "switching the NOTIFY OFF"
  # edit raspi blitz config
  echo "editing /mnt/hdd/raspiblitz.conf"
  sudo sed -i "s/^notify=.*/notify=off/g" /mnt/hdd/raspiblitz.conf
  exit 0
fi


###################
# send the message
###################
if [ "$1" = "send" ]; then
  # check if "notify" is enabled - if not exit
  if ! grep -Eq "^notify=on" /mnt/hdd/raspiblitz.conf; then
    echo "Notifications are NOT enabled in /mnt/hdd/raspiblitz.conf"
    exit 1
  fi

  if ! command -v msmtp >/dev/null; then
    echo "please run \"on\" first"
    exit 1
  fi

  # now parse settings from config and use to send the message
  if [ "${notifyMethod}" = "ext" ]; then
    /usr/bin/python3 /home/admin/config.scripts/blitz.sendnotification.py ext ${notifyExtCmd} "$2"
  elif [ "${notifyMethod}" = "mail" ]; then
    if [ "${notifyMailEncrypt}" = "on" ]; then
      /usr/bin/python3 /home/admin/config.scripts/blitz.sendnotification.py mail --from-address "${notifyMailFromAddress}" --from-name "${notifyMailFromName}" --cert "${notifyMailToCert}" --encrypt ${notifyMailTo} "${@:3}" "$2"
    else
      /usr/bin/python3 /home/admin/config.scripts/blitz.sendnotification.py mail --from-address "${notifyMailFromAddress}" --from-name "${notifyMailFromName}" "${notifyMailTo}" "${@:3}" "$2"
    fi
  elif [ "${notifyMethod}" = "slack" ]; then
    /usr/bin/python3 /home/admin/config.scripts/blitz.sendnotification.py slack -h "$2"
  else
    echo "unknown notification method - check /mnt/hdd/raspiblitz.conf"
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1

