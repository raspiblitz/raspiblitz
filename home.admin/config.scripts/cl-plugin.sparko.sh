#!/bin/bash

# explanation on paths https://github.com/ElementsProject/lightning/issues/4223
# built-in path dir: /usr/local/libexec/c-lightning/plugins/
# added --plugin-dir=/home/bitcoin/${netprefix}cl-plugins-enabled

SPARKOVERSION="v2.7"

# command info
if [ $# -lt 1 ] || [ "$1" = "-h" ] || [ "$1" = "-help" ];then
  echo
  echo "Install, remove, connect or get info about the Sparko plugin for C-lightning"
  echo "version: $SPARKOVERSION"
  echo "Usage:"
  echo "cl-plugin.sparko.sh [on|off|menu|connect] [testnet|mainnet|signet] [norestart]"
  echo
  exit 1
fi

# source <(/home/admin/config.scripts/network.aliases.sh getvars cl <mainnet|testnet|signet>)
source <(/home/admin/config.scripts/network.aliases.sh getvars cl $2)

# show info menu
if [ "$1" = "menu" ]; then

  # get network info
  localip=$(ip addr | grep 'state UP' -A2 | grep -E -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}sparko/hostname)
  toraddresstext="Hidden Service address for the Tor Browser (QRcode on LCD):\n$toraddress"
  if [ ${#toraddress} -eq 0 ];then
    toraddresstext="Activate Tor to access the web interface from outside of the local network."
  else
    /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
  fi
  fingerprint=$(openssl x509 -in /home/bitcoin/.lightning/sparko-tls/cert.pem -fingerprint -noout | cut -d"=" -f2)

  whiptail --title "\
Sparko - $CHAIN" --msgbox "Open in your local web browser:
https://${localip}:${portprefix}9000\n
username: blitz
password: 'your Password B'\n
Accept the self-signed SSL certificate with the fingerprint:
${fingerprint}\n
${toraddresstext}
" 17 67
  
  /home/admin/config.scripts/blitz.display.sh hide

  echo "# please wait ..."
  exit 0
fi

# add default value to raspi config if needed
configEntry="${netprefix}sparko"
configEntryExists=$(sudo cat /mnt/hdd/raspiblitz.conf | grep -c "${configEntry}")
if [ "${configEntryExists}" == "0" ]; then
  echo "# adding default config entry for '${configEntry}'"
  sudo /bin/sh -c "echo '${configEntry}=off' >> /mnt/hdd/raspiblitz.conf"
else
  echo "# default config entry for '${configEntry}' exists"
fi

if [ $1 = connect ];then
  localip=$(ip addr | grep 'state UP' -A2 | grep -E -v 'docker0|veth' | grep 'eth0\|wlan0\|enp0' | tail -n1 | awk '{print $2}' | cut -f1 -d'/')
  toraddress=$(sudo cat /mnt/hdd/tor/${netprefix}sparko/hostname)
  accesskey=$(sudo cat ${CLCONF} | grep "^sparko-keys=" | cut -d= -f2 | cut -d';' -f1) 
  url="https://${localip}:${portprefix}9000/"
  #string="${url}?access-key=${accesskey}"
  #/home/admin/config.scripts/blitz.display.sh qr "$string"
  #clear
  #echo "connection string (shown as a QRcode on the top and on the LCD):"
  #echo "$string"
  #qrencode -t ANSIUTF8 "${string}"
  clear
  echo
  /home/admin/config.scripts/blitz.display.sh qr "${toraddress}"
  echo "The Tor address is shown as a QRcode below and on the LCD"
  echo "Scan it to your phone with a QR scanner app and paste it to: 'Host'"
  echo
  echo "Host: ${toraddress}"
  echo
  qrencode -t ANSIUTF8 "${toraddress}"
  echo
  echo
  echo "Alternatively to connect through the LAN the address is:"
  echo "${url}"
  echo
  echo "# Press enter to continue to show the access key"
  read key
  /home/admin/config.scripts/blitz.display.sh hide
  /home/admin/config.scripts/blitz.display.sh qr "${accesskey}"
  clear
  echo
  echo "The Access Key is shown as a QRcode below and on the LCD"
  echo "Scan it to your phone with a QR scanner app and paste it to: 'Access Key'"
  echo
  echo "Acces Key: ${accesskey}"
  echo
  qrencode -t ANSIUTF8 "${accesskey}"
  echo
  echo "# Press enter to hide the QRcode from the LCD"
  read key
  /home/admin/config.scripts/blitz.display.sh hide
  exit 0
fi

if [ "$1" = "on" ];then
  echo "# Detect CPU architecture ..."
  isARM=$(uname -m | grep -c 'arm')
  isAARCH64=$(uname -m | grep -c 'aarch64')
  isX86_64=$(uname -m | grep -c 'x86_64')
      
  if [ ${isARM} -eq 1 ] ; then
    DISTRO="linux-arm"
  elif [ ${isAARCH64} -eq 1 ] ; then
    DISTRO="linux_arm"
  elif [ ${isX86_64} -eq 1 ] ; then
    DISTRO="linux_amd64"
  fi
  
  if [ ! -f /home/bitcoin/cl-plugins-available/sparko ];then
    sudo -u bitcoin mkdir /home/bitcoin/cl-plugins-available
    # download binary
    sudo -u bitcoin wget https://github.com/fiatjaf/sparko/releases/download/${SPARKOVERSION}/sparko_${DISTRO}\
    -O /home/bitcoin/cl-plugins-available/sparko || exit 1
    # make executable
    sudo chmod +x /home/bitcoin/cl-plugins-available/sparko
  fi

  if [ ! -L /home/bitcoin/${netprefix}cl-plugins-enabled/sparko ];then
    sudo ln -s /home/bitcoin/cl-plugins-available/sparko \
               /home/bitcoin/${netprefix}cl-plugins-enabled
  fi

  if [ ! -f /home/bitcoin/.lightning/sparko-tls/key.pem ];then
    # create a self signed cert https://github.com/fiatjaf/sparko#how-to-use
    /home/admin/config.scripts/internet.selfsignedcert.sh   
    # sparko looks for specific filenames
    sudo -u bitcoin mkdir /home/bitcoin/.lightning/sparko-tls
    sudo ln -sf /mnt/hdd/app-data/selfsignedcert/selfsigned.key \
        /home/bitcoin/.lightning/sparko-tls/key.pem
    sudo ln -sf /mnt/hdd/app-data/selfsignedcert/selfsigned.cert \
        /home/bitcoin/.lightning/sparko-tls/cert.pem
  fi

  ##########
  # Config #
  ##########
  if ! grep -Eq "^sparko" ${CLCONF};then
    echo "# Editing ${CLCONF}"
    echo "# See: https://github.com/fiatjaf/sparko#how-to-use"
    PASSWORD_B=$(sudo cat /mnt/hdd/bitcoin/bitcoin.conf | grep rpcpassword | cut -c 13-)
    # Spark wallet only allows alphanumeric characters
    masterkeythatcandoeverything=$(< /dev/urandom tr -dc a-zA-Z0-9 | head -c20)
    secretaccesskeythatcanreadstuff=$(< /dev/urandom tr -dc a-zA-Z0-9 | head -c20)
    verysecretkeythatcanpayinvoices=$(< /dev/urandom tr -dc a-zA-Z0-9 | head -c20)
    keythatcanlistentoallevents=$(< /dev/urandom tr -dc a-zA-Z0-9 | head -c20)
  echo "
sparko-host=0.0.0.0
sparko-port=${portprefix}9000
sparko-tls-path=/home/bitcoin/.lightning/sparko-tls
sparko-login=blitz:$PASSWORD_B
sparko-keys=${masterkeythatcandoeverything}; ${secretaccesskeythatcanreadstuff}: getinfo, listchannels, listnodes; ${verysecretkeythatcanpayinvoices}: pay; ${keythatcanlistentoallevents}: stream
" | sudo tee -a ${CLCONF}
  else
    echo "# Sparko is already configured in ${CLCONF}"
  fi

  echo "# Allowing port ${portprefix}9000 through the firewall"
  sudo ufw allow "${portprefix}9000" comment "${netprefix}sparko"

  # hidden service to https://xx.onion
  /home/admin/config.scripts/internet.hiddenservice.sh ${netprefix}sparko 443 ${portprefix}9000

  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}sparko=.*/${netprefix}sparko=on/g" /mnt/hdd/raspiblitz.conf

  source <(/home/admin/config.scripts/blitz.cache.sh get state)
  if [ "${state}" == "ready" ] && [ "$3" != "norestart" ]; then
    echo "# Restart the ${netprefix}lightningd.service to activate Sparko"
    sudo systemctl restart ${netprefix}lightningd
  fi

  echo "# Sparko was installed"
  echo "# Monitor with:"
  echo "sudo journalctl | grep sparko | tail -n5"
  echo "sudo tail -n 100 -f /home/bitcoin/.lightning/${CLNETWORK}/cl.log | grep sparko"
  
fi

if [ "$1" = "off" ];then
  # delete symlink
  sudo rm -rf /home/bitcoin/${netprefix}cl-plugins-enabled/sparko
  
  echo "# Editing ${CLCONF}"
  sudo sed -i "/^sparko/d" ${CLCONF}

  echo "# Restart the ${netprefix}lightningd.service to deactivate Sparko"
  sudo systemctl restart ${netprefix}lightningd

  echo "# Deny port ${portprefix}9000 through the firewall"
  sudo ufw deny "${portprefix}9000"
  
  /home/admin/config.scripts/internet.hiddenservice.sh off ${netprefix}sparko

  # purge
  if [ "$(echo "$@" | grep -c purge)" -gt 0 ];then
    echo "# Delete plugin"
    sudo rm -rf /home/bitcoin/cl-plugins-available/sparko
  fi
  # setting value in raspi blitz config
  sudo sed -i "s/^${netprefix}sparko=.*/${netprefix}sparko=off/g" /mnt/hdd/raspiblitz.conf
  echo "# Sparko was uninstalled"

fi
