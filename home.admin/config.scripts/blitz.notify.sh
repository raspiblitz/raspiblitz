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

# write default values if no custum values in raspiblitz config yet
if ! grep -Eq "^notifyMethod=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyMethod "mail"
fi
if ! grep -Eq "^notifyMailTo=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyMailTo "mail@example.com"
fi
if ! grep -Eq "^notifyMailServer=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyMailServer "mail.example.com"
fi
if ! grep -Eq "^notifyMailHostname=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyMailHostname "${hostname}"
fi
if ! grep -Eq "^notifyMailFromAddress=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyMailFromAddress "rb@example.com"
fi
if ! grep -Eq "^notifyMailFromName=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyMailFromName "RB User"
fi
if ! grep -Eq "^notifyMailUser=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyMailUser "username"
fi
if ! grep -Eq "^notifyMailPass=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyMailPass "password"
fi
if ! grep -Eq "^notifyMailEncrypt=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyMailEncrypt "off"
fi
if ! grep -Eq "^notifyMailToCert=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyMailToCert "/mnt/hdd/notify_mail_cert.pem"
fi
if ! grep -Eq "^notifyExtCmd=.*" /mnt/hdd/raspiblitz.conf; then
    /home/admin/config.scripts/blitz.conf.sh set notifyExtCmd "/usr/bin/printf"
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
port 587
tls on
tls_trust_file /etc/ssl/certs/ca-certificates.crt

account mail
host ${notifyMailServer}
from ${notifyMailFromAddress}
auth on
user ${notifyMailUser}
password ${notifyMailPass}

# Set a default account
account default : mail

EOF

  # edit raspi blitz config
  echo "editing /mnt/hdd/raspiblitz.conf"
  /home/admin/config.scripts/blitz.conf.sh set notify "on"
  exit 0
fi


###################
# switch off
###################
if [ "$1" = "0" ] || [ "$1" = "off" ]; then
  echo "switching the NOTIFY OFF"
  # edit raspi blitz config
  echo "editing /mnt/hdd/raspiblitz.conf"
  /home/admin/config.scripts/blitz.conf.sh set notify "off"
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

