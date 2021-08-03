#!/bin/bash

# command info
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ]; then
 echo "script to enable/disable or send notifications"
 echo "blitz.notify.sh on"
 echo "blitz.notify.sh off"
 echo "blitz.notify.sh send \"Message to be send via configured method\""
# todo: enable explicit sending method so user can be informed (messenger) and have log term storage (email)
# echo "blitz.notify.sh mail \"Message to be send via mail method\""
# echo "blitz.notify.sh xmpp \"Message to be send via xmpp method\""
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
elif [ $(grep "notifyMethod=" /mnt/hdd/raspiblitz.conf|cut -d"=" -f2) = "xmpp" ]; then
    # XMPP
    if ! grep -Eq "^notifyXMPPTo=.*" /mnt/hdd/raspiblitz.conf; then
        echo "notifyXMPPTo=user@domain.tld" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
    fi
fi

# Mail
if ! grep -Eq "^notifyMailTo=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailTo=mail@example.com" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
fi

if ! grep -Eq "^notifyMailServer=.*" /mnt/hdd/raspiblitz.conf; then
    echo "notifyMailServer=mail.example.com" | sudo tee -a /mnt/hdd/raspiblitz.conf >/dev/null
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

  # install sendxmpp
  [ -z "$(find -H /usr/share/doc/sendxmpp/README -maxdepth 0 -mtime -7)" ] && sudo apt-get update
  if ! command -v msmtp >/dev/null; then
      sudo apt-get install -y sendxmpp
  fi

  # install mstmp if not already present
  if ! command -v msmtp >/dev/null; then
    [ -z "$(find -H /var/lib/apt/lists -maxdepth 0 -mtime -7)" ] && sudo apt-get update
    sudo apt-get install -y msmtp msmtp-mta mailutils
    # todo: configuration for msmtp
    #sudo wget -O /etc/msmtprc https://marlam.de/msmtp/msmtprc.txt
    #sudo chmod 600 /etc/msmtprc
    #sudo cp /etc/msmtprc ~/.msmtprc
  fi

  # install python lib for smime into virtual env
  sudo -H /usr/bin/python3 -m pip install smime

  # write msmtp config
#  cat << EOF | sudo tee /etc/ssmtp/ssmtp.conf >/dev/null
  cat << EOF | sudo tee /etc/msmtprc >/dev/null
# outdated service configuration #
# Config file for sSMTP sendmail
#
# The person who gets all mail for userids < 1000
# Make this empty to disable rewriting.
#Root=${notifyMailTo}

# hostname of this system
#Hostname=${notifyMailHostname}

# relay/smarthost server settings
#Mailhub=${notifyMailServer}
#AuthUser=${notifyMailUser}
#AuthPass=${notifyMailPass}
#UseSTARTTLS=YES
#FromLineOverride=YES

# possible successor service cnfiguration #
# mSMTP configuration, acc. to binfalse.de/2020/02/17/migrating-from-ssmtp-to-msmtp/
defaults
port 25
tls on

account default
auth off
host RELAY
domain HOSTNAME
from webserver@HOSTNAME
add_missing_date_header on
EOF
  chmod 600 /etc/msmtprc

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

#case "$1" in
#  send)
#    ;;
#  xmpp)
#    notifyMethod=xmpp
#    1=send
#    ;;
#  *)
#    notifyMethod=mail
#    1=send
#    ;;  
#esac

if [ "$1" = "send" ]; then
  # check if "notify" is enabled - if not exit
  if ! grep -Eq "^notify=on" /mnt/hdd/raspiblitz.conf; then
    echo "Notifications are NOT enabled in /mnt/hdd/raspiblitz.conf"
    exit 1
  fi

 # now parse settings from config and use to send the message
  if [ "${notifyMethod}" = "mail" ]; then
    if ! command -v msmtp >/dev/null; then
      echo "please make sure msmtp is configured first"
      exit 1
    fi
    if [ "${notifyMailEncrypt}" = "on" ]; then
      /usr/bin/python3 /home/admin/XXsendNotification.py mail --from-address "${notifyMailFromAddress}" --from-name "${notifyMailFromName}" --cert "${notifyMailToCert}" --encrypt ${notifyMailTo} "${@:3}" "$2"
    else
      /usr/bin/python3 /home/admin/XXsendNotification.py mail --from-address "${notifyMailFromAddress}" --from-name "${notifyMailFromName}" "${notifyMailTo}" "${@:3}" "$2"
    fi
  elif [ "${notifyMethod}" = "xmpp" ]; then
    if ! command -v sendxmpp >/dev/null; then
      echo "please make sure sendxmpp is installed and configured first."
    fi
    echo -e $(whoami)"@"$(hostname)":\n\n---\n## ${2}\n${@:3}" | sendxmpp "${notifyXMPPTo}" || { echo "error sending XMPP message"; exit 1; }
    # 
  elif [ "${notifyMethod}" = "ext" ]; then
    /usr/bin/python3 /home/admin/XXsendNotification.py ext ${notifyExtCmd} "$2"
  elif [ "${notifyMethod}" = "slack" ]; then
    /usr/bin/python3 /home/admin/XXsendNotification.py slack -h "$2"
  else
    echo "unknown notification method - check /mnt/hdd/raspiblitz.conf"
  fi

  exit 0
fi

echo "FAIL - Unknown Parameter $1"
exit 1
